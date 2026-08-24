#Requires -Modules Pester

Describe "Manage-RestorePoints" {
    BeforeAll {
        $scriptRelPath = '../../../../scripts/infrastructure/windows/backup-recovery/Manage-RestorePoints.ps1'
        $scriptPath = Join-Path $PSScriptRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Local stubs for Windows-only cmdlets: they do not exist on Linux,
        # and Pester cannot mock a command that does not resolve.
        function Get-ComputerRestorePoint { }
        function Enable-ComputerRestore { }
        function Checkpoint-Computer { }
        # Mock -CommandName ALL external commands so nothing leaves the machine.
        Mock -CommandName Test-IsAdministrator { $true }
        Mock -CommandName Test-SystemRestoreEnabled { $true }
        Mock -CommandName Get-ComputerRestorePoint { @() }
        Mock -CommandName Enable-ComputerRestore { }
        Mock -CommandName Checkpoint-Computer { }
        Mock -CommandName Start-Sleep { }
        Mock -CommandName Read-Host { 'N' }
        Mock -CommandName Invoke-VssAdmin { 0 }
    }

    Context "Help & Metadata" {
        It "Declares File Name matching the disk filename" {
            Get-Content -Raw $scriptPath | Should -Match 'File Name:\s*Manage-RestorePoints\.ps1'
        }

        It "Declares Version 1.0.0 and relaunch Date" {
            $helpText = Get-Content -Raw $scriptPath
            $helpText | Should -Match 'Version:\s*1\.0\.0'
            $helpText | Should -Match 'Date:\s*2026-08-23'
        }

        It "Has one .PARAMETER entry per declared parameter, in order" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $paramNames = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $paramMatches = [regex]::Matches(
                (Get-Content -Raw $scriptPath), '(?m)^\.PARAMETER\s+(\S+)')
            $declared = @($paramMatches | ForEach-Object { $_.Groups[1].Value })
            $declared.Count | Should -Be $paramNames.Count
            for ($i = 0; $i -lt $paramNames.Count; $i++) {
                $declared[$i] | Should -Be $paramNames[$i]
            }
        }

        It "Declares SupportsShouldProcess for the destructive Create/Cleanup actions" {
            (Get-Content -Raw $scriptPath) | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
            $errors.Count | Should -Be 0
        }

        It "Contains no PS7-only syntax without a #Requires -Version 7.0 opt-out" {
            $text = Get-Content -Raw $scriptPath
            if (-not ($text -match '(?m)^\s*#Requires\s+-Version\s+7\.0')) {
                $text | Should -Not -Match '\?\?'
                $text | Should -Not -Match '\|\|'
                $text | Should -Not -Match '&&'
                $text | Should -Not -Match '-Parallel\b'
            }
        }

        It "Routes the native vssadmin.exe only through the Invoke-VssAdmin wrapper" {
            $text = Get-Content -Raw $scriptPath
            ($text | Select-String -Pattern '& vssadmin\.exe' -AllMatches).Matches.Count | Should -Be 1
        }
    }

    Context "Behavior" {
        It "Lists restore points and returns 0 on success" {
            Mock -CommandName Get-ComputerRestorePoint { @(
                    [pscustomobject]@{
                        SequenceNumber   = 2
                        CreationTime     = (Get-Date).AddDays(-1)
                        Description      = 'Recent'
                        RestorePointType = 12
                    },
                    [pscustomobject]@{
                        SequenceNumber   = 1
                        CreationTime     = (Get-Date).AddDays(-10)
                        Description      = 'Older'
                        RestorePointType = 0
                    }
                ) }
            $Action = 'List'

            # Format-Table emits formatting records on the success stream; assert the int return.
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-ComputerRestorePoint -Times 1 -Exactly
        }

        It "Returns 1 with [-] output when Create is called without a Description" {
            $Action = 'Create'
            $Description = $null

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Checkpoint-Computer -Times 0 -Exactly -Because "no description was supplied"
        }

        It "Creates a restore point via Checkpoint-Computer and returns 0" {
            $Action = 'Create'
            $Description = 'Before GPO changes'
            $RestorePointType = 'ModifySettings'

            Main | Should -Be 0
            Should -Invoke Checkpoint-Computer -Times 1 -Exactly
            Should -Invoke Enable-ComputerRestore -Times 1 -Exactly
        }

        It "Is idempotent: Cleanup with no old restore points makes no changes and returns 0" {
            Mock -CommandName Get-ComputerRestorePoint { @(
                    [pscustomobject]@{
                        SequenceNumber   = 5
                        CreationTime     = (Get-Date)
                        Description      = 'Fresh'
                        RestorePointType = 12
                    }
                ) }
            $Action = 'Cleanup'
            $RetentionDays = 30

            Main | Should -Be 0
            Should -Invoke Invoke-VssAdmin -Times 0 -Exactly -Because "nothing is past retention"
        }
    }
}
