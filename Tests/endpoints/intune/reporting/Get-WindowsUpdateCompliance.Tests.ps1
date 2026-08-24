#Requires -Modules Pester

Describe "Get-WindowsUpdateCompliance" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/intune/reporting/Get-WindowsUpdateCompliance.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # External commands mocked by name (works offline without the Graph SDK).
        function Connect-IntuneGraph { }
        function Disconnect-IntuneGraph { }
        function Get-MgDeviceManagementManagedDevice { @() }
        function Invoke-MgGraphRequest { }
        function Export-IntuneReportToHTML { }
        function Export-IntuneReportToCSV { }

        # Two devices: PC-A protected and reporting, PC-B unprotected with a stale AV report.
        function Get-TestDevices {
            @(
                [pscustomobject]@{
                    Id = 'd1'; DeviceName = 'PC-A'; UserPrincipalName = 'a@contoso.com'
                    OsVersion = '10.0.19045'; OperatingSystem = 'Windows'; AzureAdDeviceId = 'aad-1'
                    ComplianceState = 'compliant'; LastSyncDateTime = (Get-Date).AddHours(-2)
                    Manufacturer = 'Dell'; Model = 'Latitude'; SerialNumber = 'SN1'
                }
                [pscustomobject]@{
                    Id = 'd2'; DeviceName = 'PC-B'; UserPrincipalName = 'b@contoso.com'
                    OsVersion = '11.0.22621'; OperatingSystem = 'Windows'; AzureAdDeviceId = 'aad-2'
                    ComplianceState = 'noncompliant'; LastSyncDateTime = (Get-Date).AddDays(-9)
                    Manufacturer = 'HP'; Model = 'EliteBook'; SerialNumber = 'SN2'
                }
            )
        }

        Mock Import-Module { }
        Mock Connect-IntuneGraph { $true }
        Mock Disconnect-IntuneGraph { }
        Mock Get-MgDeviceManagementManagedDevice { Get-TestDevices }
        Mock Invoke-MgGraphRequest {
            [pscustomobject]@{
                antivirusEnabled = $true
                malwareProtectionEnabled = $false
                lastReportedDateTime = (Get-Date).AddDays(-45).ToString('o')
            }
        }
        Mock Export-IntuneReportToHTML { 'html' }
        Mock Export-IntuneReportToCSV { 'csv' }
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
        It "Audits devices, exports HTML and CSV reports, and returns 0" {
            $ShowNonCompliantOnly = $false
            $IncludeAutoPatchInfo = $false
            $ExportFormat = 'Both'

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            $text | Should -Match '\[\+\]'
            $text | Should -Match 'Not Protected:\s+2'
            Should -Invoke Export-IntuneReportToHTML -Exactly 1
            Should -Invoke Export-IntuneReportToCSV -Exactly 1
            Should -Invoke Invoke-MgGraphRequest -Exactly 2
            Should -Invoke Disconnect-IntuneGraph -Exactly 1
        }

        It "Flags stale devices and prints recommendations when reports are old" {
            $ShowNonCompliantOnly = $false
            $IncludeAutoPatchInfo = $false
            $ExportFormat = 'Both'

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match 'RECOMMENDATIONS'
            $text | Should -Match '\[!\]'
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
        }

        It "Returns 0 with a [!] notice when no devices match ShowNonCompliantOnly" {
            Mock Invoke-MgGraphRequest {
                [pscustomobject]@{
                    antivirusEnabled = $true
                    malwareProtectionEnabled = $true
                    lastReportedDateTime = (Get-Date).AddDays(-1).ToString('o')
                }
            }
            $ShowNonCompliantOnly = $true
            $IncludeAutoPatchInfo = $false
            $ExportFormat = 'Both'

            $out = Main *>&1
            ($out | Out-String) | Should -Match 'No devices match the current filter criteria'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Export-IntuneReportToHTML -Exactly 0
        }

        It "Returns 1 and writes [-] prefixed output when the Graph connection fails" {
            Mock Connect-IntuneGraph { $false }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
