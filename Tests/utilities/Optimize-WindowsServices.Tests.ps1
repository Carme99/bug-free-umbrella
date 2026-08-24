#Requires -Modules Pester

Describe "Optimize-WindowsServices" {
    BeforeAll {
        # Stub Windows-only commands so Pester can mock them on Linux pwsh.
        function Get-Service { param($Name) }
        function Set-Service { param($Name, $StartupType) }
        function Stop-Service { param($Name, $Force) }

        # Mirrored layout: this file lives at Tests/utilities/ -> script is two levels up.
        $scriptPath = Join-Path $PSScriptRoot "../../scripts/utilities/Optimize-WindowsServices.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Default no-op mocks so nothing touches real service state.
        Mock Get-Service { @() }
        Mock Set-Service { }
        Mock Stop-Service { }
        Mock Export-Clixml { }
        Mock Import-Clixml { }
    }

    Context "Help & Metadata" {
        It "Declares File Name, Version 1.0.0 and relaunch Date 2026-08-23 in the header" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match 'File Name:\s*Optimize-WindowsServices\.ps1'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
            $raw | Should -Match 'Author:\s*\S+'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
        }

        It "Has one .PARAMETER entry per declared parameter, in declaration order" {
            $tokens = $null; $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declared = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)

            $helpParams = [regex]::Matches((Get-Content -Raw $scriptPath), '\.PARAMETER\s+(\w+)') |
                ForEach-Object { $_.Groups[1].Value }

            $helpParams.Count | Should -Be $declared.Count
            $helpParams | Should -Be $declared
        }

        It "Provides SYNOPSIS, DESCRIPTION and at least two EXAMPLES with PS C:\> prompts" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match '\.SYNOPSIS'
            $raw | Should -Match '\.DESCRIPTION'
            ([regex]::Matches($raw, '\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses cleanly with zero parser errors" {
            $tokens = $null; $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only tokens (opt-out requires line 1)" {
            $raw = Get-Content -Raw $scriptPath
            $requiresV7 = ($raw -split "`r?`n")[0] -match '#Requires\s+-Version\s+7'
            if (-not $requiresV7) {
                $tokens = $null; $parseErrors = $null
                [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
                $badKinds = $tokens | Where-Object {
                    $_.Kind.ToString() -in @('QuestionMark', 'QuestionQuestion', 'AmpersandAmpersand', 'PipePipe')
                }
                $badKinds | Should -BeNullOrEmpty -Because "PS7-only operators need #Requires -Version 7.0 on line 1"
            }
        }

        It "Uses UTF-8 BOM and CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            ($text -replace "`r`n", '') | Should -Not -Match "`n"
        }
    }

    Context "Behavior" {
        It "Analyzes services, recommends changes, and never mutates state in Analyze mode" {
            Mock Get-Service {
                @(
                    [pscustomobject]@{ Name = 'Fax'; DisplayName = 'Fax'; Status = 'Running'; StartType = 'Manual' },
                    [pscustomobject]@{
                        Name = 'RemoteRegistry'; DisplayName = 'Remote Registry'
                        Status = 'Stopped'; StartType = 'Disabled'
                    }
                )
            }

            $out = Main -Mode Analyze -Profile Minimal *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Changes Recommended: 1'
            Should -Invoke Set-Service -Times 0 -Exactly
            Should -Invoke Stop-Service -Times 0 -Exactly
        }

        It "Applies startup type changes via Set-Service only when -ApplyChanges is given" {
            Mock Get-Service {
                param($Name)
                [pscustomobject]@{ Name = $Name; DisplayName = "Svc $Name"; Status = 'Running'; StartType = 'Manual' }
            }
            Mock Export-Clixml { }
            Mock Set-Service { }
            Mock Stop-Service { }

            $out = Main -Mode Optimize -Profile Minimal -ApplyChanges *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Export-Clixml -Times 1 -Exactly -Because "a backup must precede mutations"
            Should -Invoke Set-Service -Times 8 -Exactly -Because "Minimal profile covers 8 services"
            Should -Invoke Set-Service -ParameterFilter { $StartupType -eq 'Disabled' } -Times 8 -Exactly
            Should -Invoke Stop-Service -ParameterFilter { $Name } -Times 8 -Exactly
        }

        It "Is idempotent: converged services exit 0 with no mutations" {
            Mock Get-Service {
                param($Name)
                [pscustomobject]@{ Name = $Name; DisplayName = "Svc $Name"; Status = 'Stopped'; StartType = 'Disabled' }
            }
            Mock Export-Clixml { }

            $out = Main -Mode Optimize -Profile Minimal -ApplyChanges *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'no changes made'
            Should -Invoke Set-Service -Times 0 -Exactly -Because "nothing left to change"
            Should -Invoke Stop-Service -Times 0 -Exactly
        }

        It "Honors -WhatIf: no service is touched even with -ApplyChanges" {
            Mock Get-Service {
                param($Name)
                [pscustomobject]@{ Name = $Name; DisplayName = "Svc $Name"; Status = 'Running'; StartType = 'Manual' }
            }
            Mock Export-Clixml { }

            $out = Main -Mode Optimize -Profile Minimal -ApplyChanges -WhatIf *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Set-Service -Times 0 -Exactly
            Should -Invoke Stop-Service -Times 0 -Exactly
        }

        It "Returns 1 and writes [-] prefixed output when the restore backup is missing" {
            $out = Main -Mode Restore -BackupPath (Join-Path $TestDrive 'missing.xml') *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
        It "Restores only services whose startup type drifted from the backup" {
            $backupFile = Join-Path $TestDrive 'services.xml'
            [IO.File]::WriteAllText($backupFile, 'placeholder')
            Mock Import-Clixml {
                @(
                    [pscustomobject]@{ Name = 'Fax'; DisplayName = 'Fax'; Status = 'Stopped'; StartType = 'Manual' },
                    [pscustomobject]@{
                        Name = 'RemoteRegistry'; DisplayName = 'Remote Registry'
                        Status = 'Stopped'; StartType = 'Disabled'
                    }
                )
            }
            Mock Get-Service {
                param($Name)
                if ($Name -eq 'Fax') {
                    [pscustomobject]@{ Name = 'Fax'; DisplayName = 'Fax'; Status = 'Stopped'; StartType = 'Automatic' }
                }
                else {
                    [pscustomobject]@{
                        Name = $Name; DisplayName = "Svc $Name"; Status = 'Stopped'; StartType = 'Disabled'
                    }
                }
            }
            Mock Set-Service { }

            $out = Main -Mode Restore -BackupPath (Join-Path $TestDrive 'services.xml') *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Set-Service -Times 1 -Exactly -Because "only Fax drifted from its backup state"
            Should -Invoke Set-Service -ParameterFilter { $Name -eq 'Fax' } -Times 1 -Exactly
        }
    }
}
