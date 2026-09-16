#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for scripts/collaboration/microsoft365/purview/Get-RetentionPolicyCoverageReport.ps1.

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
    File Name   : Get-RetentionPolicyCoverageReport.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-RetentionPolicyCoverageReport' {
    BeforeAll {
        $scriptRelPath = ('../../../../scripts/collaboration/microsoft365/purview/' +
            'Get-RetentionPolicyCoverageReport.ps1')
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

        function Get-RetentionCompliancePolicy {
            [CmdletBinding()]
            param(
                [Parameter(Position = 0)][string]$Identity,
                [switch]$DistributionDetail,
                [switch]$ErrorPolicyOnly,
                [switch]$ExcludeTeamsPolicy,
                [switch]$IncludeTestModeResults,
                [switch]$PriorityCleanup,
                [switch]$RetentionRuleTypes,
                [switch]$TeamsPolicyOnly
            )
        }

        function Get-AppRetentionCompliancePolicy {
            [CmdletBinding()]
            param(
                [Parameter(Position = 0)][string]$Identity,
                [switch]$DistributionDetail,
                [switch]$ErrorPolicyOnly,
                [switch]$RetentionRuleTypes
            )
        }

        function Get-RetentionComplianceRule {
            [CmdletBinding()]
            param(
                [Parameter(Position = 0)][string]$Identity,
                [string]$Policy,
                [switch]$PriorityCleanup
            )
        }

        function Get-AppRetentionComplianceRule {
            [CmdletBinding()]
            param(
                [Parameter(Position = 0)][string]$Identity,
                [string]$Policy
            )
        }

        function Get-ComplianceTag {
            [CmdletBinding()]
            param(
                [Parameter(Position = 0)][string]$Identity,
                [switch]$IncludingLabelState,
                [switch]$PriorityCleanup
            )
        }

        $exchangePolicy = [pscustomobject]@{
            Name                 = 'Exchange 7 Year Retention'
            Enabled              = $true
            Mode                 = 'Enforce'
            DistributionStatus   = 'Complete'
            RetentionRuleTypes   = 'ComplianceTag'
            ExchangeLocation     = @('All')
            SharePointLocation   = @()
            OneDriveLocation     = @()
            ModernGroupLocation  = @()
            SkypeLocation        = @('All')
            PublicFolderLocation = @()
            TeamsChannelLocation = @()
            TeamsChatLocation    = @()
        }

        $sharePointPolicy = [pscustomobject]@{
            Name                 = 'SharePoint Site Retention'
            Enabled              = $true
            Mode                 = 'Enforce'
            DistributionStatus   = 'Complete'
            RetentionRuleTypes   = 'ComplianceTag'
            ExchangeLocation     = @()
            SharePointLocation   = @('All')
            OneDriveLocation     = @('All')
            ModernGroupLocation  = @()
            SkypeLocation        = @()
            PublicFolderLocation = @()
            TeamsChannelLocation = @()
            TeamsChatLocation    = @()
        }

        $pendingPolicy = [pscustomobject]@{
            Name                 = 'Unassigned Project Hold'
            Enabled              = $true
            Mode                 = 'Enforce'
            DistributionStatus   = 'Pending'
            RetentionRuleTypes   = ''
            ExchangeLocation     = @('All')
            SharePointLocation   = @()
            OneDriveLocation     = @()
            ModernGroupLocation  = @()
            SkypeLocation        = @()
            PublicFolderLocation = @()
            TeamsChannelLocation = @()
            TeamsChatLocation    = @()
        }

        $labelPolicy = [pscustomobject]@{
            Name                 = 'HR Label Policy'
            Enabled              = $true
            Mode                 = 'Enforce'
            DistributionStatus   = 'Complete'
            RetentionRuleTypes   = 'TagPolicy'
            ExchangeLocation     = @()
            SharePointLocation   = @('All')
            OneDriveLocation     = @()
            ModernGroupLocation  = @()
            SkypeLocation        = @()
            PublicFolderLocation = @()
            TeamsChannelLocation = @()
            TeamsChatLocation    = @()
        }

        $appPolicy = [pscustomobject]@{
            Name                 = 'Teams Chat Retention (App)'
            Enabled              = $true
            Mode                 = 'Enforce'
            DistributionStatus   = 'Complete'
            RetentionRuleTypes   = 'ComplianceTag'
            Applications         = @('User:TeamsChatUserInteractions')
            TeamsChatLocation    = @('All')
        }

        $defaultPolicies = @($exchangePolicy, $sharePointPolicy, $pendingPolicy, $labelPolicy)

        $exchangeRule = [pscustomobject]@{
            Name                      = 'Exchange 7 Year'
            Policy                    = 'Exchange 7 Year Retention'
            RetentionDuration         = '2555'
            RetentionComplianceAction = 'KeepAndDelete'
        }

        $sharePointRule = [pscustomobject]@{
            Name                      = 'SharePoint 3 Year'
            Policy                    = 'SharePoint Site Retention'
            RetentionDuration         = '1095'
            RetentionComplianceAction = 'Keep'
        }

        $publishRule = [pscustomobject]@{
            Name                 = 'Publish HR label'
            Policy               = 'HR Label Policy'
            PublishComplianceTag = 'HR Content'
        }

        $appRule = [pscustomobject]@{
            Name                      = 'Teams Chat 30 Day'
            Policy                    = 'Teams Chat Retention (App)'
            RetentionDuration         = '30'
            RetentionComplianceAction = 'Delete'
        }

        # App retention policies carry their own rules, returned by Get-AppRetentionComplianceRule.
        # The name must not collide with the script's own $appRules variable: mock bodies resolve
        # variables in the script's scope, so a colliding name would feed the mock its own empties.
        $appRuleFixtures = @($appRule)

        $defaultRules = @($exchangeRule, $sharePointRule, $publishRule)

        Mock Connect-IPPSSession { }
        Mock Get-RetentionCompliancePolicy { $defaultPolicies }
        Mock Get-RetentionComplianceRule { $defaultRules }
        Mock Get-AppRetentionCompliancePolicy { @() }
        Mock Get-AppRetentionComplianceRule { @() }
        Mock Get-ComplianceTag { @() }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath, [ref]$tokens, [ref]$parseErrors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Get-RetentionPolicyCoverageReport\.ps1'
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
                'PolicyName', 'IncludeAppPolicies', 'IncludeLabels', 'OutputFormat', 'OutputPath')
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
        It 'Reports the coverage gaps and returns 2' {
            . $scriptPath
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            $text = $out | Out-String
            $text | Should -Match 'Policies matched\s+:\s+4'
            $text | Should -Match 'Policies not distributed\s+:\s+1'
            $text | Should -Match 'Policies with zero rules\s+:\s+1'
            $text | Should -Match 'Uncovered workloads\s+:\s+4'
            $text | Should -Match 'rule Exchange 7 Year: duration=2555 action=KeepAndDelete'
            $text | Should -Match 'Unassigned Project Hold \[Retention\] mode=Enforce enabled=True'
            $text | Should -Match 'distribution=Pending rules=0'
            $text | Should -Match '\[!\] Unassigned Project Hold: distribution status Pending'
            $text | Should -Match '\[!\] Unassigned Project Hold: no retention rules'
            $text | Should -Match '\[!\] uncovered workload: TeamsChat'
            $text | Should -Match '\[!\] Retention coverage gaps: 6'
            $text | Should -Not -Match 'Labels published to no policy'
            Should -Invoke Connect-IPPSSession -Exactly 1
            Should -Invoke Get-RetentionCompliancePolicy -Exactly 1
            Should -Invoke Get-RetentionCompliancePolicy -ParameterFilter {
                $DistributionDetail -and $RetentionRuleTypes } -Exactly 1
            Should -Invoke Get-RetentionComplianceRule -Exactly 1
            Should -Invoke Get-AppRetentionCompliancePolicy -Exactly 0
            Should -Invoke Get-AppRetentionComplianceRule -Exactly 0
            Should -Invoke Get-ComplianceTag -Exactly 0
        }

        It 'Returns 0 and reports complete coverage for a fully covered tenant' {
            Mock Get-RetentionCompliancePolicy {
                @([pscustomobject]@{
                        Name                 = 'Global Retention'
                        Enabled              = $true
                        Mode                 = 'Enforce'
                        DistributionStatus   = 'Complete'
                        ExchangeLocation     = @('All')
                        SharePointLocation   = @('All')
                        OneDriveLocation     = @('All')
                        ModernGroupLocation  = @('All')
                        SkypeLocation        = @('All')
                        PublicFolderLocation = @('All')
                        TeamsChannelLocation = @('All')
                        TeamsChatLocation    = @('All')
                    })
            }
            Mock Get-RetentionComplianceRule {
                @([pscustomobject]@{
                        Name                      = 'Global Rule'
                        Policy                    = 'Global Retention'
                        RetentionDuration         = 'Unlimited'
                        RetentionComplianceAction = 'Keep'
                    })
            }
            . $scriptPath
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match 'Policies matched\s+:\s+1'
            $text | Should -Match 'Uncovered workloads\s+:\s+0'
            $text | Should -Match '\[\+\] Retention policy coverage is complete'
        }

        It 'Narrows the report with a wildcard -PolicyName filter' {
            . $scriptPath -PolicyName 'Exchange*'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            $text = $out | Out-String
            $text | Should -Match 'Policies matched\s+:\s+1'
            $text | Should -Match 'Exchange 7 Year Retention'
            $text | Should -Not -Match 'SharePoint Site Retention'
        }

        It 'Adds app retention policies and their locations under -IncludeAppPolicies' {
            Mock Get-AppRetentionCompliancePolicy { @($appPolicy) }
            Mock Get-AppRetentionComplianceRule { @($appRuleFixtures) }
            . $scriptPath -IncludeAppPolicies
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            $text = $out | Out-String
            $text | Should -Match 'Policies matched\s+:\s+5'
            $text | Should -Match ('Teams Chat Retention \(App\) \[App\] mode=Enforce ' +
                'enabled=True distribution=Complete rules=1')
            $text | Should -Match 'rule Teams Chat 30 Day: duration=30 action=Delete'
            $text | Should -Match 'Uncovered workloads\s+:\s+3'
            $text | Should -Not -Match '\[!\] uncovered workload: TeamsChat'
            Should -Invoke Get-AppRetentionCompliancePolicy -Exactly 1
            Should -Invoke Get-AppRetentionCompliancePolicy -ParameterFilter {
                $DistributionDetail -and $RetentionRuleTypes } -Exactly 1
            Should -Invoke Get-AppRetentionComplianceRule -Exactly 1
        }

        It 'Flags labels that no policy publishes under -IncludeLabels' {
            Mock Get-ComplianceTag {
                @([pscustomobject]@{ Name = 'HR Content' },
                    [pscustomobject]@{ Name = 'Contract Review' })
            }
            . $scriptPath -IncludeLabels
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            $text = $out | Out-String
            $text | Should -Match 'Labels published to no policy: 1'
            $text | Should -Match '\[!\] Contract Review: label published to no retention policy'
            $text | Should -Not -Match '\[!\] HR Content: label published to no retention policy'
            Should -Invoke Get-ComplianceTag -Exactly 1
        }

        It 'Returns 1 with [-] output when Connect-IPPSSession is unavailable' {
            Mock Get-Command -ParameterFilter { $Name -eq 'Connect-IPPSSession' } { }
            . $scriptPath
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[\-\] Error: Connect-IPPSSession'
            Should -Invoke Connect-IPPSSession -Exactly 0
            Should -Invoke Get-RetentionCompliancePolicy -Exactly 0
        }

        It 'Returns the documented exit code 1 when a Purview cmdlet throws' {
            Mock Get-RetentionComplianceRule { throw 'session expired' }
            . $scriptPath
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[\-\] Error: session expired'
        }

        It 'Writes a CSV report and leaves the working directory unchanged' {
            $csvPath = Join-Path $TestDrive 'retention-coverage.csv'
            $workingDirectory = (Get-Location).Path
            . $scriptPath -OutputFormat Csv -OutputPath $csvPath
            Main | Should -Be 2
            Test-Path -LiteralPath $csvPath | Should -BeTrue
            (Get-Location).Path | Should -Be $workingDirectory
            $csv = Get-Content -LiteralPath $csvPath -Raw
            $csv | Should -Match 'Unassigned Project Hold'
            $csv | Should -Match 'Exchange 7 Year \(2555/KeepAndDelete\)'
        }

        It 'Writes a JSON report whose summary matches the console counts' {
            $jsonPath = Join-Path $TestDrive 'retention-coverage.json'
            . $scriptPath -OutputFormat Json -OutputPath $jsonPath
            Main | Should -Be 2
            $parsed = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
            $parsed.Summary.Matched | Should -Be 4
            $parsed.Summary.UncoveredWorkloads | Should -Be 4
            $parsed.Findings.Count | Should -Be 6
            $parsed.Policies[0].Workloads | Should -Match 'Exchange'
        }
    }
}