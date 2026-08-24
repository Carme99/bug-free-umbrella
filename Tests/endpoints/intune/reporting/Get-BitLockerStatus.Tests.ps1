#Requires -Modules Pester

Describe "Get-BitLockerStatus" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/intune/reporting/;
        # the script sits under <repo root>/scripts/endpoints/intune/reporting/.
        $repoRoot = Join-Path $PSScriptRoot "../../../.."
        $scriptPath = Join-Path $repoRoot "scripts/endpoints/intune/reporting/Get-BitLockerStatus.ps1"

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
        Mock Write-Progress { }
        Mock Connect-IntuneGraph { $true }
        Mock Disconnect-IntuneGraph { }
        Mock Export-IntuneReportToHTML { return "/tmp/fake.html" }
        Mock Export-IntuneReportToCSV { return "/tmp/fake.csv" }

        $winEncrypted = [pscustomobject]@{
            Id = 'dev-1'; DeviceName = 'WIN-01'; UserPrincipalName = 'user1@contoso.com'
            OperatingSystem = 'Windows'; OsVersion = '10.0.19045'; LastSyncDateTime = [datetime]'2026-08-21 09:00:00'
            ComplianceState = 'compliant'; Manufacturer = 'Contoso'; Model = 'X1'; SerialNumber = 'SN1'
            AzureAdDeviceId = 'aad-1'
        }
        $winNoBackup = [pscustomobject]@{
            Id = 'dev-2'; DeviceName = 'WIN-02'; UserPrincipalName = 'user2@contoso.com'
            OperatingSystem = 'Windows'; OsVersion = '11.0.22621'; LastSyncDateTime = [datetime]'2026-08-20 14:00:00'
            ComplianceState = 'noncompliant'; Manufacturer = 'Contoso'; Model = 'Book 3'; SerialNumber = 'SN2'
            AzureAdDeviceId = 'aad-2'
        }
        $macDevice = [pscustomobject]@{
            Id = 'dev-3'; DeviceName = 'MAC-01'; UserPrincipalName = 'user3@contoso.com'
            OperatingSystem = 'macOS'; OsVersion = '15.0'; LastSyncDateTime = $null
            ComplianceState = 'compliant'; Manufacturer = 'Apple'; Model = 'MacBook Pro'; SerialNumber = 'SN3'
            AzureAdDeviceId = ''
        }

        function script:Get-FakeManagedDevices { @($winEncrypted, $winNoBackup) }

        Mock Get-MgDeviceManagementManagedDevice { script:Get-FakeManagedDevices }

        Mock Invoke-MgGraphRequest {
            param($Uri)
            # Order matters: most specific URIs first
            switch -Wildcard ($Uri) {
                '*recoveryKeys*' {
                    if ($Uri -like '*aad-1*') {
                        $fakeKeys = @([pscustomobject]@{ createdDateTime = [datetime]'2026-07-01 12:00:00' })
                        [pscustomobject]@{ value = $fakeKeys }
                    }
                    else {
                        [pscustomobject]@{ value = @() }
                    }
                }
                '*deviceCompliancePolicyStates*' {
                    [pscustomobject]@{ value = @() }
                }
                '*managedDevices/dev-1' {
                    [pscustomobject]@{ isEncrypted = $true }
                }
                '*managedDevices/dev-2' {
                    [pscustomobject]@{ isEncrypted = $false }
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
            $raw | Should -Match 'File Name\s*:\s*Get-BitLockerStatus\.ps1'
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
        It "Returns 0, audits Windows devices only by default, and exports both reports" {
            . $scriptPath

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text | Should -Match '\[\+\]'
            $text | Should -Match 'BITLOCKER ENCRYPTION SUMMARY'
            Should -Invoke Export-IntuneReportToCSV -ParameterFilter { $Data.Count -eq 2 }
            Should -Invoke Export-IntuneReportToHTML -Times 1 -Exactly
            Should -Invoke Export-IntuneReportToCSV -Times 1 -Exactly
        }

        It "Classifies encrypted vs unencrypted and key backup status from Graph data" {
            . $scriptPath
            Main *>&1 | Out-Null

            Should -Invoke Export-IntuneReportToCSV -ParameterFilter {
                $encryptedRow = $Data | Where-Object { $_.DeviceName -eq 'WIN-01' }
                $unencryptedRow = $Data | Where-Object { $_.DeviceName -eq 'WIN-02' }
                $encryptedRow.EncryptionStatus -eq 'Encrypted' -and
                $encryptedRow.RecoveryKeyStatus -like 'Backed Up*' -and
                $unencryptedRow.EncryptionStatus -eq 'Not Encrypted' -and
                $unencryptedRow.RecoveryKeyStatus -eq 'No Backup'
            }
        }

        It "Excludes macOS devices unless -IncludeNonWindows is passed" {
            Mock Get-MgDeviceManagementManagedDevice { @($winEncrypted, $winNoBackup, $macDevice) }

            . $scriptPath
            Main *>&1 | Out-Null
            Should -Invoke Export-IntuneReportToCSV -ParameterFilter {
                $Data.Count -eq 2 -and -not ($Data | Where-Object { $_.OperatingSystem -notlike 'Windows*' })
            }

            # Now include non-Windows devices
            . $scriptPath -IncludeNonWindows
            Main *>&1 | Out-Null
            Should -Invoke Export-IntuneReportToCSV -ParameterFilter {
                $macRow = $Data | Where-Object { $_.DeviceName -eq 'MAC-01' }
                $Data.Count -eq 3 -and $macRow.EncryptionStatus -eq 'N/A'
            }
        }

        It "Applies -ShowMissingKeys filter to exported report data" {
            . $scriptPath -ShowMissingKeys
            ($out = Main *>&1 | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Export-IntuneReportToCSV -ParameterFilter {
                $Data.Count -eq 1 -and $Data[0].RecoveryKeyStatus -eq 'No Backup'
            }
        }

        It "Returns 1 with [-] output when no devices are found (nothing to audit)" {
            Mock Get-MgDeviceManagementManagedDevice { @() }

            . $scriptPath
            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            $text | Should -Match '\[-\]'
            $text | Should -Match 'No devices found'
            Should -Invoke Export-IntuneReportToHTML -Times 0 -Exactly
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
