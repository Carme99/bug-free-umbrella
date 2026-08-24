#Requires -Modules Pester

Describe "Test-BackupIntegrity" {
    BeforeAll {
        $scriptRelPath = '../../../../scripts/infrastructure/windows/backup-recovery/Test-BackupIntegrity.ps1'
        $scriptPath = Join-Path $PSScriptRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Local stubs for Windows-only module commands: they do not exist on Linux,
        # and Pester cannot mock a command that does not resolve.
        function Get-WBPolicy { }
        function Get-WBSchedule { }
        function Get-WBBackupTarget { }
        function Get-WBSummary { }
        function Get-WBBackupSet { }
        function Get-Service { }
        function Get-CimInstance { }
        # Mock -CommandName ALL external commands so nothing leaves the machine.
        Mock -CommandName Import-Module { }
        Mock -CommandName Get-WBPolicy { $null }
        Mock -CommandName Get-WBSchedule { @() }
        Mock -CommandName Get-WBBackupTarget { @() }
        Mock -CommandName Get-WBSummary { [pscustomobject]@{
                LastSuccessfulBackupTime = (Get-Date).AddHours(-2)
                LastBackupTime           = (Get-Date).AddHours(-2)
                NextBackupTime           = (Get-Date).AddDays(1)
                NumberOfVersions         = 12
            } }
        Mock -CommandName Get-WBBackupSet { @([pscustomobject]@{
                    BackupTime  = (Get-Date).AddDays(-1)
                    BackupState = 'Succeeded'
                    TargetLabel = 'Disk 0'
                }) }
        Mock -CommandName Get-Service { [pscustomobject]@{ Name = 'VSS'; Status = 'Running' } }
        Mock -CommandName Get-CimInstance { @() }
    }

    Context "Help & Metadata" {
        It "Declares File Name matching the disk filename" {
            Get-Content -Raw $scriptPath | Should -Match 'File Name:\s*Test-BackupIntegrity\.ps1'
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

        It "Has exit only in the top-level dot-source guard line" {
            $text = Get-Content -Raw $scriptPath
            $text | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
            [regex]::Matches($text, '\bexit\b').Count | Should -Be 1
        }
    }

    Context "Behavior" {
        It "Returns 0 when backups are healthy and recent" {
            $DaysToCheck = 7
            $CheckVSS = $false
            $TestRestore = $false
            $ExportHTML = $false
            $ExportCSV = $false
            $BackupLocation = $null

            Main | Should -Be 0
            Should -Invoke Get-WBSummary -Times 1 -Exactly
            Should -Invoke Get-WBBackupSet -Times 1 -Exactly
        }

        It "Returns 1 with [-] output when the Windows Server Backup module is missing" {
            Mock -CommandName Import-Module { throw 'WindowsServerBackup not installed' }
            $DaysToCheck = 7; $CheckVSS = $false; $TestRestore = $false; $ExportHTML = $false; $ExportCSV = $false

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It "Returns 1 when the last successful backup is stale beyond threshold" {
            Mock -CommandName Get-WBSummary { [pscustomobject]@{ LastSuccessfulBackupTime = (Get-Date).AddDays(-30) } }
            $DaysToCheck = 7; $CheckVSS = $false; $TestRestore = $false; $ExportHTML = $false; $ExportCSV = $false

            Main | Should -Be 1
        }

        It "Is idempotent: re-running against an already-healthy system returns 0 with no changes" {
            $DaysToCheck = 7; $CheckVSS = $false; $TestRestore = $false; $ExportHTML = $false; $ExportCSV = $false

            Main | Should -Be 0
            Main | Should -Be 0
            Should -Invoke Get-WBSummary -Times 2 -Exactly -Because "each run re-reads state and mutates nothing"
        }
    }
}
