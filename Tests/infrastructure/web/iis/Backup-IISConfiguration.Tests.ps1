#Requires -Modules Pester

Describe "Backup-IISConfiguration" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../../scripts/infrastructure/web/iis/Backup-IISConfiguration.ps1"
        $scriptText = Get-Content -LiteralPath $scriptPath -Raw

        # Placeholder functions: product modules are not installed offline;
        # Pester Mock requires the command names to be resolvable.
        function Get-IISSite { }
        function Get-IISAppPool { }

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Baseline mocks: no IIS, no network, no admin required.
        Mock Get-IISSite { @() }
        Mock Get-IISAppPool { @() }
    }

    Context "Help & Metadata" {
        It "Declares the complete header block" {
            $scriptText | Should -Match '(?m)^\.SYNOPSIS'
            $scriptText | Should -Match '(?m)^\.DESCRIPTION'
            $scriptText | Should -Match '(?m)^\.NOTES'
        }

        It "Populates all five .NOTES fields correctly" {
            $scriptText | Should -Match 'File Name\s*:\s*Backup-IISConfiguration\.ps1'
            $scriptText | Should -Match 'Author\s*:\s*\S'
            $scriptText | Should -Match 'Prerequisite\s*:\s*PowerShell'
            $scriptText | Should -Match 'Version\s*:\s*1\.0\.0'
            $scriptText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Has at least 2 examples with PS C:\> prompts" {
            ([regex]::Matches($scriptText, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($scriptText, [regex]::Escape('PS C:\>'))).Count | Should -BeGreaterOrEqual 2
        }

        It "Documents one .PARAMETER per declared parameter, in order" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
            $declared = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
            $documented = [regex]::Matches($scriptText, '(?m)^\.PARAMETER\s+(\S+)') |
                    ForEach-Object { $_.Groups[1].Value }
            $documented | Should -Be $declared
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                    $scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
            $errors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only operators without a #Requires -Version 7.0 opt-out" {
            if ($scriptText -notmatch '(?m)^#Requires\s+-Version\s+7\.0') {
                $tokens = $null
                $parseErrors = $null
                [System.Management.Automation.Language.Parser]::ParseInput(
                        $scriptText, [ref]$tokens, [ref]$parseErrors) | Out-Null
                $kindType = [System.Management.Automation.Language.TokenKind]
                $ps7Kinds = @('AmpersandAmpersand', 'BarBar', 'QuestionMark', 'QuestionQuestionEquals') |
                    Where-Object { $kindType.GetMember($_) }
                $offenders = @($tokens | Where-Object { $ps7Kinds -contains [string]$_.Kind })
                $offenders | Should -BeNullOrEmpty -Because "PS7-only operators require #Requires opt-out"
            }
        }

        It "Uses the mandatory Main entrypoint and dot-source guard" {
            $guard = "if (`$MyInvocation.InvocationName -ne '.') { exit (Main) }"
            $scriptText.Contains($guard) | Should -BeTrue
        }
    }

    Context "Behavior" {
        It "Creates a full backup set and returns 0 on success" {
            $physPath = Join-Path $TestDrive 'wwwroot'
            New-Item -ItemType Directory -Path $physPath -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $physPath 'web.config') -Value '<configuration />'

            $site = [pscustomobject]@{
                Name     = 'Site1'
                Id       = 1
                State    = 'Started'
                Bindings = @([pscustomobject]@{ Protocol = 'http'; BindingInformation = '*:80:' })
                Applications = @{
                    '/' = [pscustomobject]@{
                        ApplicationPoolName = 'Pool1'
                        VirtualDirectories  = @{ '/' = [pscustomobject]@{ PhysicalPath = $physPath } }
                    }
                }
            }
            $pool = [pscustomobject]@{
                Name                  = 'Pool1'
                State                 = 'Started'
                ManagedRuntimeVersion = 'v4.0'
                ManagedPipelineMode   = 'Integrated'
                StartMode             = 'OnDemand'
                Enable32BitAppOnWin64 = $false
                ProcessModel          = [pscustomobject]@{ IdleTimeout = [timespan]::FromMinutes(20) }
Recycling             = [pscustomobject]@{
                        PeriodicRestart     = [pscustomobject]@{ Schedule = @(); PrivateMemory = 0 }
                    }
            }
            Mock Get-IISSite { @($site) }
            Mock Get-IISAppPool { @($pool) }

            $BackupPath = Join-Path $TestDrive 'backups'
            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            $backupDirs = @(Get-ChildItem -LiteralPath $BackupPath -Directory)
            $backupDirs.Count | Should -Be 1
            $backupDir = $backupDirs[0].FullName
            Test-Path (Join-Path $backupDir 'Sites.csv') | Should -BeTrue
            Test-Path (Join-Path $backupDir 'ApplicationPools.csv') | Should -BeTrue
            Test-Path (Join-Path $backupDir 'manifest.json') | Should -BeTrue
            Test-Path (Join-Path $backupDir 'Sites/Site1/web.config') | Should -BeTrue
        }

        It "Is repeatable: two consecutive backup runs both succeed (exit 0)" {
            Mock Get-IISSite { @() }
            Mock Get-IISAppPool { @() }
            $BackupPath = Join-Path $TestDrive 'repeat-backups'
            Main | Should -Be 0
            Main | Should -Be 0
        }

        It "Returns 1 and writes [-] prefixed output when the restore path is invalid" {
            $Restore = $true
            $RestoreFrom = Join-Path $TestDrive 'does-not-exist'
            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It "Honors -WhatIf: restore performs no copy mutation" {
            $restoreDir = Join-Path $TestDrive 'whatif_src'
            New-Item -ItemType Directory -Path $restoreDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $restoreDir 'ApplicationHost.config') -Value '<config />'
            $Restore = $true
            $RestoreFrom = $restoreDir
            Mock Copy-Item { }

            ($out = Main -WhatIf *>&1) | Out-Null

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Copy-Item -Times 0 -Exactly
        }

        It "Check-then-act: restore with no ApplicationHost.config copies nothing yet still succeeds" {
            $emptyDir = Join-Path $TestDrive 'empty_restore'
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
            $Restore = $true
            $RestoreFrom = $emptyDir
            Mock Copy-Item { }

            ($out = Main *>&1) | Out-Null

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Copy-Item -Times 0 -Exactly
        }
    }
}
