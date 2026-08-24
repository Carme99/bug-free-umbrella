#Requires -Modules Pester

Describe "Get-DeviceComplianceReport" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/intune/reporting/;
        # the script sits under <repo root>/scripts/endpoints/intune/reporting/.
        $repoRoot = Join-Path $PSScriptRoot "../../../.."
        $scriptPath = Join-Path $repoRoot "scripts/endpoints/intune/reporting/Get-DeviceComplianceReport.ps1"

        # IntuneGraphHelper.psm1 / Microsoft.Graph surfaces are mocked at command-name level.
        # Pester requires the command to exist before Mock, so declare minimal stubs first
        # (the real Import-Module is mocked below and never runs).
        function Connect-IntuneGraph { param([string[]]$Scopes) $true }
        function Disconnect-IntuneGraph { }
        function Export-IntuneReportToHTML { param($Data, $Title, $FilePath) return $FilePath }
        function Export-IntuneReportToCSV { param($Data, $Title, $FilePath) return $FilePath }
        function Invoke-MgGraphRequest { param([string]$Uri) throw "Invoke-MgGraphRequest not mocked for URI: $Uri" }
        function Get-MgDeviceManagementManagedDevice {
            param($All) throw "Get-MgDeviceManagementManagedDevice not mocked"
        }

        # --- Mock all externals so nothing leaves the machine (offline, no Graph tenant) ---
        Mock Import-Module { }
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock Connect-IntuneGraph { $true }
        Mock Disconnect-IntuneGraph { }
        Mock Export-IntuneReportToHTML { return "/tmp/fake.html" }
        Mock Export-IntuneReportToCSV { return "/tmp/fake.csv" }

        function script:New-FakeDevice {
            param($Id, $Name, $State)
            [pscustomobject]@{
                Id = $Id; DeviceName = $Name; UserPrincipalName = "$($Name.ToLower())@contoso.com"
                Manufacturer = 'Contoso'; Model = 'X1'; OperatingSystem = 'Windows'; OsVersion = '10.0.19045'
                ComplianceState = $State; LastSyncDateTime = [datetime]'2026-08-21 09:00:00'
                SerialNumber = $Id; EnrolledDateTime = [datetime]'2025-01-15 09:00:00'; ManagementAgent = 'MDM'
            }
        }

        $compliantDevice = New-FakeDevice -Id 'dev-c' -Name 'DEV-COMPLIANT' -State 'compliant'
        $nonCompliantDevice = New-FakeDevice -Id 'dev-n' -Name 'DEV-NONCOMPLIANT' -State 'noncompliant'
        $unknownDevice = New-FakeDevice -Id 'dev-u' -Name 'DEV-UNKNOWN' -State 'unknown'

        Mock Get-MgDeviceManagementManagedDevice { @($compliantDevice, $nonCompliantDevice, $unknownDevice) }

        Mock Invoke-MgGraphRequest {
            param($Uri)
            # Order matters: most specific URIs first
            switch -Wildcard ($Uri) {
                '*deviceCompliancePolicyStates*' {
                    if ($Uri -like '*dev-n*') {
                        [pscustomobject]@{ value = @(
                            [pscustomobject]@{ state = 'nonCompliant'; displayName = 'Password Policy' }
                            [pscustomobject]@{ state = 'compliant'; displayName = 'Encryption Policy' }
                        ) }
                    }
                    else {
                        [pscustomobject]@{ value = @() }
                    }
                }
                '*deviceCompliancePolicies' {
                    [pscustomobject]@{ value = @(
                        [pscustomobject]@{ id = 'pol-1'; displayName = 'Password Policy' }
                        [pscustomobject]@{ id = 'pol-2'; displayName = 'Encryption Policy' }
                    ) }
                }
                default {
                    throw "Unexpected Graph URI in test: $Uri"
                }
            }
        }
    }

    Context "Help & Metadata" {
        It "Is UTF-8 with BOM and CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            $hasUtf8Bom = ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            ($bytes.Length -gt 3 -and $hasUtf8Bom) | Should -BeTrue
            $raw = [System.IO.File]::ReadAllText($scriptPath)
            $raw.Contains("`n") | Should -BeTrue
            ($raw -split "`n" | Where-Object { $_ -notmatch "`r$" }) | Should -BeNullOrEmpty
        }

        It "Has required header fields: File Name, Author, Prerequisite, Version 1.0.0, Date 2026-08-23" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match '\.NOTES'
            $raw | Should -Match 'File Name\s*:\s*Get-DeviceComplianceReport\.ps1'
            $raw | Should -Match 'Author\s*:'
            $raw | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match 'Version\s*:\s*1\.0\.0'
            $raw | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Has complete help: SYNOPSIS, DESCRIPTION, >=2 EXAMPLES with PS C:\> prompts" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match '\.SYNOPSIS'
            $raw | Should -Match '\.DESCRIPTION'
            $examples = [regex]::Matches($raw, '(?m)^\.EXAMPLE')
            $examples.Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>') | Measure-Object).Count | Should -BeGreaterOrEqual 2
        }

        It "Has one .PARAMETER per declared param, in param() order" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $declaredParams = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $paramMatches = [regex]::Matches((Get-Content -Raw $scriptPath), '(?m)^\.PARAMETER\s+(\S+)')
            $helpParams = @($paramMatches | ForEach-Object { $_.Groups[1].Value })
            $helpParams.Count | Should -Be ($declaredParams.Count)
            $helpParams | Should -Be $declaredParams
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
            $errors.Count | Should -Be 0
        }

        It "Contains no PS7-only operators (&&, ||, ??, ternary, -Parallel)" {
            $raw = Get-Content -Raw $scriptPath
            $codeOnly = ($raw -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
            $codeOnly | Should -Not -Match '&&'
            $codeOnly | Should -Not -Match '\|\|'
            $codeOnly | Should -Not -Match '\?\?'
            $codeOnly | Should -Not -Match '-Parallel'
        }

        It "Defines Main, sets ErrorActionPreference Stop, guards dot-source, exits only in guard line" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $isMainFn = { param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Main'
            }
            $mainFns = @($ast.FindAll($isMainFn, $true))
            $mainFns.Count | Should -BeGreaterOrEqual 1

            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match "\`$ErrorActionPreference\s*=\s*'Stop'"

            $lines = Get-Content $scriptPath
            $exitLines = @($lines | Where-Object { $_ -match '(^|[^\w-])exit([^\w-]|$)' })
            $exitLines.Count | Should -Be 1
            $exitLines[0] | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\)'
        }
    }

    Context "Behavior" {
        It "Returns 0 and reports only non-compliant devices by default (HTML export)" {
            . $scriptPath

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text | Should -Match '\[\+\]'
            $text | Should -Match 'COMPLIANCE SUMMARY'
            Should -Invoke Export-IntuneReportToHTML -ParameterFilter {
                $ncRow = $Data | Where-Object { $_.DeviceName -eq 'DEV-NONCOMPLIANT' }
                $Data.Count -eq 2 -and
                -not ($Data | Where-Object { $_.ComplianceState -eq 'compliant' }) -and
                $ncRow.ComplianceReason -like '*Password Policy*'
            }
            Should -Invoke Export-IntuneReportToHTML -Times 1 -Exactly
            Should -Invoke Export-IntuneReportToCSV -Times 0 -Exactly
            Should -Invoke Disconnect-IntuneGraph -Times 1 -Exactly
        }

        It "-IncludeCompliant adds compliant devices and -ExportFormat Both exports both formats" {
            . $scriptPath -ExportFormat Both -IncludeCompliant

            Main *>&1 | Out-Null
            Should -Invoke Export-IntuneReportToCSV -ParameterFilter { $Data.Count -eq 3 }
            Should -Invoke Export-IntuneReportToHTML -ParameterFilter { $Data.Count -eq 3 }
            Should -Invoke Export-IntuneReportToCSV -Times 1 -Exactly
        }

        It "Is converged-safe: all-compliant fleet returns 0 without generating a report" {
            Mock Get-MgDeviceManagementManagedDevice { @($compliantDevice) }

            . $scriptPath
            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text | Should -Match 'All devices are compliant'
            Should -Invoke Export-IntuneReportToHTML -Times 0 -Exactly
            Should -Invoke Export-IntuneReportToCSV -Times 0 -Exactly
        }

        It "Continues past a per-device Graph failure and still returns 0 with report data" {
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -like '*deviceCompliancePolicyStates*' -and $Uri -like '*dev-n*') {
                    throw "per-device graph hiccup"
                }
                switch -Wildcard ($Uri) {
                    '*deviceCompliancePolicyStates*' { [pscustomobject]@{ value = @() } }
                    '*deviceCompliancePolicies' {
                        $fakePolicies = @([pscustomobject]@{ id = 'pol-1'; displayName = 'Password Policy' })
                        [pscustomobject]@{ value = $fakePolicies }
                    }
                    default { throw "Unexpected Graph URI in test: $Uri" }
                }
            }

            . $scriptPath
            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text | Should -Match '\[!\]'
            $text | Should -Match 'per-device graph hiccup'
            Should -Invoke Export-IntuneReportToHTML -ParameterFilter {
                $Data.Count -eq 2 -and
                (($Data | Where-Object { $_.DeviceName -eq 'DEV-NONCOMPLIANT' }).ComplianceReason -eq 'Unknown')
            }
        }

        It "Returns 1 with [-] prefixed output when device retrieval fails" {
            Mock Get-MgDeviceManagementManagedDevice { throw "graph unavailable" }

            . $scriptPath
            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            $text | Should -Match '\[-\]'
            $text | Should -Match 'graph unavailable'
        }

        It "Returns 1 with [-] output when Graph connection fails" {
            Mock Connect-IntuneGraph { $false }

            . $scriptPath
            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            $text | Should -Match '\[-\]'
            $text | Should -Match 'Failed to connect'
            Should -Invoke Get-MgDeviceManagementManagedDevice -Times 0 -Exactly
        }
    }
}
