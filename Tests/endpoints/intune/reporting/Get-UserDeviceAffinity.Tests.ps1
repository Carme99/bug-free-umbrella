#Requires -Modules Pester

Describe "Get-UserDeviceAffinity" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/intune/reporting/Get-UserDeviceAffinity.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # External commands mocked by name (works offline without the Graph SDK).
        function Connect-IntuneGraph { }
        function Get-AllIntuneDevices { @() }
        function Invoke-MgGraphRequest { }
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $fileName = Split-Path $scriptPath -Leaf
            $raw | Should -Match ("File Name:\s*" + [regex]::Escape($fileName))
            $raw | Should -Match 'Author:\s*\S'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
        }

        It "Has SYNOPSIS, DESCRIPTION and at least two EXAMPLES" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Synopsis.Length | Should -BeLessOrEqual 120
            $help.Description | Should -Not -BeNullOrEmpty
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
        }

        It "Declares one .PARAMETER per param() parameter" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
            $declared = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $documented = @((Get-Help $scriptPath).Parameters.Parameter.Name)
            $declared.Count | Should -Be $documented.Count
            foreach ($p in $declared) { $documented | Should -Contain $p }
        }
    }

    Context "Syntax & Static" {
        BeforeAll {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        }
        It "Parses with zero errors" {
            $errors | Should -BeNullOrEmpty
        }
        It "Contains no PS7-only operators (no #Requires -Version 7.0 opt-out present)" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Not -Match '(?m)&&|\|\||\?\?|\?\?='
            $raw | Should -Not -Match '\$\w+\s*\?\s*[^:]'
        }
    }

    Context "Behavior" {
        It "Generates a CSV report and returns 0 when Graph data is available" {
            Mock Import-Module { }
            Mock Connect-IntuneGraph { }
            Mock Get-AllIntuneDevices {
                @([pscustomobject]@{
                    userPrincipalName = 'alice@contoso.com'; deviceName = 'PC-ALICE'
                    operatingSystem = 'Windows'; osVersion = '10.0.19045'; model = 'XPS 13'
                    serialNumber = 'SN1'; complianceState = 'compliant'
                    lastSyncDateTime = (Get-Date); enrolledDateTime = (Get-Date).AddDays(-30)
                })
            }
            Mock Invoke-MgGraphRequest {
                [pscustomobject]@{
                    value = @([pscustomobject]@{
                        id = 'u1'; displayName = 'Alice'; userPrincipalName = 'alice@contoso.com'
                        accountEnabled = $true; department = 'IT'; jobTitle = 'Engineer'
                    })
                }
            }
            Mock Export-Csv { }

            $OutputPath = Join-Path $TestDrive 'reports'
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            $Format = 'CSV'

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Export-Csv -Exactly 1
            Should -Invoke Invoke-MgGraphRequest -Exactly 1
        }

        It "Paginates over multiple user pages and counts every user" {
            Mock Import-Module { }
            Mock Connect-IntuneGraph { }
            Mock Get-AllIntuneDevices { @() }

            $script:graphPage = 0
            Mock Invoke-MgGraphRequest {
                $script:graphPage++
                if ($script:graphPage -eq 1) {
                    return [pscustomobject]@{
                        value = @([pscustomobject]@{
                            id = 'u1'; displayName = 'Alice'; userPrincipalName = 'alice@contoso.com'
                            accountEnabled = $true; department = 'IT'; jobTitle = 'Engineer'
                        })
                        '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?$skiptoken=page2'
                    }
                }
                return [pscustomobject]@{
                    value = @([pscustomobject]@{
                        id = 'u2'; displayName = 'Bob'; userPrincipalName = 'bob@contoso.com'
                        accountEnabled = $true; department = 'HR'; jobTitle = 'Analyst'
                    })
                }
            }
            Mock Out-File { }

            $Format = 'HTML'
            $ShowNoDeviceUsers = $false
            $ShowMultiDeviceUsers = $false

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match 'Total Users: 2'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Invoke-MgGraphRequest -Exactly 2
            Should -Invoke Out-File -Exactly 1
        }

        It "Applies the no-device filter and reports only users without devices" {
            Mock Import-Module { }
            Mock Connect-IntuneGraph { }
            Mock Get-AllIntuneDevices {
                @([pscustomobject]@{
                    userPrincipalName = 'alice@contoso.com'; deviceName = 'PC-ALICE'
                    operatingSystem = 'Windows'; osVersion = '10.0.19045'; model = 'XPS 13'
                    serialNumber = 'SN1'; complianceState = 'compliant'
                    lastSyncDateTime = (Get-Date); enrolledDateTime = (Get-Date).AddDays(-30)
                })
            }
            Mock Invoke-MgGraphRequest {
                [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{
                            id = 'u1'; displayName = 'Alice'; userPrincipalName = 'alice@contoso.com'
                            accountEnabled = $true; department = 'IT'; jobTitle = 'Engineer'
                        }
                        [pscustomobject]@{
                            id = 'u2'; displayName = 'Bob'; userPrincipalName = 'bob@contoso.com'
                            accountEnabled = $true; department = 'HR'; jobTitle = 'Analyst'
                        }
                    )
                }
            }
            Mock Out-File { }

            $Format = 'HTML'
            $ShowNoDeviceUsers = $true
            $ShowMultiDeviceUsers = $false

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match 'Total Users: 1'
            $text | Should -Match 'Users without Devices: 1'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 and writes [-] prefixed output when the Graph connection fails" {
            Mock Import-Module { }
            Mock Connect-IntuneGraph { throw "Authentication failed" }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
