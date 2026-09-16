#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for scripts/collaboration/microsoft365/purview/Get-DlpPolicyPostureReport.ps1.

.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior using fully
    mocked Security & Compliance PowerShell cmdlets. Runs offline on Linux pwsh; no network,
    elevation, or installed product modules required.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/collaboration/microsoft365/purview
    Runs this test file.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/collaboration/microsoft365/purview -Output Detailed
    Runs this test file with per-test output.

.NOTES
    File Name   : Get-DlpPolicyPostureReport.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-DlpPolicyPostureReport' {
    BeforeAll {
        $scriptRelPath = ('../../../../scripts/collaboration/microsoft365/purview/' +
            'Get-DlpPolicyPostureReport.ps1')
        $scriptPath = (Resolve-Path (Join-Path $PSScriptRoot $scriptRelPath)).Path

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Security & Compliance PowerShell is not installed offline: declare each cmdlet the
        # script calls as an advanced function carrying its real parameter set, then mock it.
        function Connect-IPPSSession {
            [CmdletBinding()]
            param(
                [string]$UserPrincipalName,
                [string]$DelegatedOrganization,
                [System.Management.Automation.PSCredential]$Credential,
                [switch]$ShowBanner,
                [switch]$UseDeviceAuthentication
            )
        }

        function Get-DlpCompliancePolicy {
            [CmdletBinding()]
            param(
                [Parameter(Position = 0)][string]$Identity,
                [switch]$DistributionDetail,
                [switch]$ErrorPolicyOnly,
                [switch]$ExcludeTeamsPolicy,
                [switch]$IncludeTestModeResults,
                [switch]$PriorityCleanup,
                [switch]$TeamsPolicyOnly
            )
        }

        function Get-DlpComplianceRule {
            [CmdletBinding()]
            param(
                [Parameter(Position = 0)][string]$Identity,
                [string]$Policy,
                [switch]$IncludeTestModeResults,
                [switch]$PriorityCleanup
            )
        }

        $enforcedPolicy = [pscustomobject]@{
            Name               = 'Enabled Exchange Policy'
            Mode               = 'Enable'
            Enabled            = $true
            DistributionStatus = 'Complete'
            ExchangeLocation   = @('All')
            TeamsLocation      = @('All')
        }

        $simulationPolicy = [pscustomobject]@{
            Name               = 'Simulation Policy'
            Mode               = 'TestWithoutNotifications'
            Enabled            = $true
            DistributionStatus = 'Complete'
            SharePointLocation = @('All')
        }

        $disabledPolicy = [pscustomobject]@{
            Name               = 'Disabled Legacy Policy'
            Mode               = 'Disable'
            Enabled            = $false
            DistributionStatus = 'Pending'
            ExchangeLocation   = @('All')
        }

        $rulelessPolicy = [pscustomobject]@{
            Name             = 'Empty Policy'
            Mode             = 'Enforce'
            Enabled          = $true
            DistributionStatus = 'Complete'
            OneDriveLocation = @('All')
        }

        $defaultPolicies = @($enforcedPolicy, $simulationPolicy, $disabledPolicy, $rulelessPolicy)

        $enforcedRule = [pscustomobject]@{
            Name          = 'Exchange Baseline'
            Policy        = 'Enabled Exchange Policy'
            Disabled      = $false
            Mode          = 'Enforce'
            GenerateAlert = @('secops@contoso.com')
        }

        $silentRule = [pscustomobject]@{
            Name          = 'Simulation Rule'
            Policy        = 'Simulation Policy'
            Disabled      = $false
            Mode          = 'TestWithoutNotifications'
            GenerateAlert = @()
        }

        $disabledRules = @(
            [pscustomobject]@{
                Name          = 'Legacy Rule A'
                Policy        = 'Disabled Legacy Policy'
                Disabled      = $true
                Mode          = 'Disable'
                GenerateAlert = @()
            }
            [pscustomobject]@{
                Name          = 'Legacy Rule B'
                Policy        = 'Disabled Legacy Policy'
                Disabled      = $false
                Mode          = 'Disable'
                GenerateAlert = @('secops@contoso.com')
            }
        )

        $defaultRules = @($enforcedRule, $silentRule) + $disabledRules

        Mock Connect-IPPSSession { }
        Mock Get-DlpCompliancePolicy { $defaultPolicies }
        Mock Get-DlpComplianceRule { $defaultRules }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath, [ref]$tokens, [ref]$parseErrors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Get-DlpPolicyPostureReport\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*Bug-Free Umbrella'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Documents every declared parameter, in order' {
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object {
                    $_.Name.Extent.Text.TrimStart('$')
                })
            $helpParams = @([regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value })
            $declared | Should -Be @(
                'PolicyName', 'IncludeEndpoints', 'OutputFormat', 'OutputPath')
            $helpParams | Should -Be $declared
        }

        It 'Provides at least two examples with PS prompts' {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $parseErrors.Count | Should -Be 0
        }

        It 'Uses CmdletBinding, Main function, and dot-source guard' {
            $raw | Should -Match '\[CmdletBinding\('
            $raw | Should -Match '(?m)^function Main \{'
            $raw | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
        }

        It 'Contains no PS7-only operators and no #Requires opt-out' {
            # Token-level scan: the forbidden operator texts are built from code points so this
            # file does not itself contain them.
            $forbidden = @(
                (-join [char[]](0x3F, 0x3F))
                (-join [char[]](0x3F, 0x3F, 0x3D))
                (-join [char[]](0x26, 0x26))
                (-join [char[]](0x7C, 0x7C))
            )
            $declaredTokens = @($tokens | ForEach-Object { $_.Text })
            foreach ($operator in $forbidden) {
                $declaredTokens | Should -Not -Contain $operator
            }
            $raw | Should -Not -Match '#Requires\s+-Version'
        }

        It 'Is UTF-8 with BOM and CRLF line endings' {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }

        It 'Keeps all lines within 120 columns and free of tabs' {
            ($raw -split "`r`n" | Where-Object { $_.Length -gt 120 }) | Should -BeNullOrEmpty
            $raw | Should -Not -Match "`t"
        }

        It 'Cites Microsoft Learn in its help' {
            $raw | Should -Match 'learn\.microsoft\.com'
        }
    }

    Context 'Behavior' {
        It 'Reports the posture findings and returns 2' {
            . $scriptPath
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            $text = $out | Out-String
            $text | Should -Match 'Policies matched\s+:\s+4'
            $text | Should -Match 'Disabled policies\s+:\s+1'
            $text | Should -Match 'Test-mode policies without alerts\s+:\s+1'
            $text | Should -Match 'Policies with zero rules\s+:\s+1'
            $text | Should -Match ('Enabled Exchange Policy mode=Enforce enabled=True ' +
                'distribution=Complete rules=1 locations=Exchange;Teams')
            $text | Should -Match 'rule Exchange Baseline: disabled=False mode=Enforce'
            $text | Should -Match '\[!\] Disabled Legacy Policy: policy is disabled'
            $text | Should -Match '\[!\] Simulation Policy: test mode with no alerting rules'
            $text | Should -Match '\[!\] Empty Policy: no DLP rules'
            $text | Should -Match '\[!\] DLP posture findings: 3'
            $text | Should -Not -Match 'Endpoint coverage'
            Should -Invoke Connect-IPPSSession -Exactly 1
            Should -Invoke Get-DlpCompliancePolicy -Exactly 1
            Should -Invoke Get-DlpCompliancePolicy -ParameterFilter {
                $DistributionDetail } -Exactly 1
            Should -Invoke Get-DlpComplianceRule -Exactly 1
        }

        It 'Returns 0 and reports a clean posture for a fully enforced tenant' {
            Mock Get-DlpCompliancePolicy {
                @([pscustomobject]@{
                        Name               = 'Endpoint And Exchange Enforcement'
                        Mode               = 'Enable'
                        Enabled            = $true
                        DistributionStatus = 'Complete'
                        ExchangeLocation   = @('All')
                        EndpointDlpLocation = @('All')
                    })
            }
            Mock Get-DlpComplianceRule {
                @([pscustomobject]@{
                        Name          = 'Baseline Rule'
                        Policy        = 'Endpoint And Exchange Enforcement'
                        Disabled      = $false
                        Mode          = 'Enforce'
                        GenerateAlert = @('secops@contoso.com')
                    })
            }
            . $scriptPath -IncludeEndpoints
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match 'Policies matched\s+:\s+1'
            $text | Should -Match 'Endpoint coverage\s+:\s+Covered'
            $text | Should -Match '\[\+\] DLP policy posture is clean'
        }

        It 'Narrows the report with a wildcard -PolicyName filter' {
            . $scriptPath -PolicyName 'Simulation*'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            $text = $out | Out-String
            $text | Should -Match 'Policies matched\s+:\s+1'
            $text | Should -Match 'Simulation Policy mode=TestWithoutNotifications'
            $text | Should -Not -Match 'Enabled Exchange Policy'
        }

        It 'Flags missing endpoint coverage under -IncludeEndpoints' {
            . $scriptPath -IncludeEndpoints
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            $text = $out | Out-String
            $text | Should -Match 'Endpoint coverage\s+:\s+Not covered'
            $text | Should -Match ('\[!\] endpoint devices: no enabled DLP policy covers them')
            $text | Should -Match '\[!\] DLP posture findings: 4'
            Should -Invoke Get-DlpCompliancePolicy -Exactly 1
        }

        It 'Returns 1 with [-] output when Connect-IPPSSession is unavailable' {
            Mock Get-Command -ParameterFilter { $Name -eq 'Connect-IPPSSession' } { }
            . $scriptPath
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[\-\] Error: Connect-IPPSSession'
            Should -Invoke Connect-IPPSSession -Exactly 0
            Should -Invoke Get-DlpCompliancePolicy -Exactly 0
        }

        It 'Returns the documented exit code 1 when a Purview cmdlet throws' {
            Mock Get-DlpComplianceRule { throw 'session expired' }
            . $scriptPath
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[\-\] Error: session expired'
        }

        It 'Writes a CSV report and leaves the working directory unchanged' {
            $csvPath = Join-Path ([IO.Path]::GetTempPath()) `
                ('dlp-posture-{0}.csv' -f [guid]::NewGuid().ToString('N'))
            $workingDirectory = (Get-Location).Path
            try {
                . $scriptPath -OutputFormat Csv -OutputPath $csvPath
                Main | Should -Be 2
                Test-Path -LiteralPath $csvPath | Should -BeTrue
                (Get-Location).Path | Should -Be $workingDirectory
                $csv = Get-Content -LiteralPath $csvPath -Raw
                $csv | Should -Match 'Simulation Policy'
                $csv | Should -Match 'Disabled Legacy Policy'
            }
            finally {
                Remove-Item -LiteralPath $csvPath -ErrorAction SilentlyContinue
            }
        }

        It 'Writes a JSON report whose summary matches the console counts' {
            $jsonPath = Join-Path ([IO.Path]::GetTempPath()) `
                ('dlp-posture-{0}.json' -f [guid]::NewGuid().ToString('N'))
            try {
                . $scriptPath -OutputFormat Json -OutputPath $jsonPath
                Main | Should -Be 2
                $parsed = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
                $parsed.Summary.Matched | Should -Be 4
                $parsed.Summary.Disabled | Should -Be 1
                $parsed.Summary.SilentTestMode | Should -Be 1
                $parsed.Summary.ZeroRules | Should -Be 1
                $parsed.Findings.Count | Should -Be 3
                $parsed.Policies[0].Name | Should -Be 'Enabled Exchange Policy'
                $parsed.Policies[0].Locations | Should -Match 'Exchange'
            }
            finally {
                Remove-Item -LiteralPath $jsonPath -ErrorAction SilentlyContinue
            }
        }
    }
}
