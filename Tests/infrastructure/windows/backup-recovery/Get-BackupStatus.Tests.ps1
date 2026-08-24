#Requires -Modules Pester

Describe "Get-BackupStatus" {
    BeforeAll {
        $scriptRelPath = '../../../../scripts/infrastructure/windows/backup-recovery/Get-BackupStatus.ps1'
        $scriptPath = Join-Path $PSScriptRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Local stubs for Windows-only module commands: they do not exist on Linux,
        # and Pester cannot mock a command that does not resolve.
        function Get-WindowsFeature { }
        function Get-WBPolicy { }
        function Get-WBBackupTarget { }
        function Get-WBBackupSet { }
        function Get-WBSummary { }
        # Mock -CommandName ALL external commands so nothing leaves the machine.
        Mock -CommandName Get-WindowsFeature { [pscustomobject]@{ Name = 'Windows-Server-Backup'; Installed = $true } }
        Mock -CommandName Import-Module { }
        Mock -CommandName Get-WBPolicy { [pscustomobject]@{
                Schedule               = @('2026-08-23T02:00:00')
                BackupTargets          = @()
                VolumesToBackup        = @()
                BMRBackupEnabled       = $false
                SystemStateBackupEnabled = $true
            } }
        Mock -CommandName Get-WBBackupTarget { @() }
        Mock -CommandName Get-WBBackupSet { @() }
        Mock -CommandName Get-WBSummary { [pscustomobject]@{ LastBackupResultHR = 0; LastBackupTime = (Get-Date) } }
    }

    Context "Help & Metadata" {
        It "Declares File Name matching the disk filename" {
            $helpText = Get-Content -Raw $scriptPath
            $helpText | Should -Match 'File Name:\s*Get-BackupStatus\.ps1'
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
            $helpText = Get-Content -Raw $scriptPath
            $paramMatches = [regex]::Matches($helpText, '(?m)^\.PARAMETER\s+(\S+)')
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
            $hasOptOut = $text -match '(?m)^\s*#Requires\s+-Version\s+7\.0'
            if (-not $hasOptOut) {
                $text | Should -Not -Match '\?\?'
                $text | Should -Not -Match '\|\|'
                $text | Should -Not -Match '&&'
                $text | Should -Not -Match '-Parallel\b'
            }
        }

        It "Wraps execution in Main with a dot-source guard and no stray exit" {
            $text = Get-Content -Raw $scriptPath
            $text | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
            [regex]::Matches($text, '\bexit\b').Count | Should -Be 1
        }
    }

    Context "Behavior" {
        It "Returns 0 on the success path and writes report files" {
            $outDir = Join-Path $TestDrive 'status-ok'
            $CheckDays = 30
            $OutputPath = $outDir
            $ValidateBackups = $false; $AlertIfNoBackup = $false; $EmailReport = $false

            Main | Should -Be 0
            Should -Invoke Import-Module -Times 1 -Exactly
            Join-Path $outDir 'BackupStatus.json' | Should -Exist
            Join-Path $outDir 'BackupStatusReport.html' | Should -Exist
        }

        It "Returns 1 when the Windows Server Backup feature is not installed" {
            Mock -CommandName Get-WindowsFeature {
                [pscustomobject]@{ Name = 'Windows-Server-Backup'; Installed = $false }
            }
            $OutputPath = (Join-Path $TestDrive 'status-missing')
            $CheckDays = 30; $EmailReport = $false

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It "Returns 1 with [-] output when the backup module cannot be loaded" {
            Mock -CommandName Import-Module { throw 'module gone' }
            $OutputPath = (Join-Path $TestDrive 'status-nomodule')
            $CheckDays = 30; $EmailReport = $false

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
