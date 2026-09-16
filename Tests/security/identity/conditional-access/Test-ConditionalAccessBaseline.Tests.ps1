#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/security/identity/conditional-access/Test-ConditionalAccessBaseline.ps1.

.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior of the
    Conditional Access baseline auditor using fully mocked Microsoft Graph cmdlets. Runs offline
    on Linux pwsh; no network, elevation, or installed product modules required.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/security/identity/conditional-access/Test-ConditionalAccessBaseline.Tests.ps1
    Runs this test file.

.EXAMPLE
    PS C:\> $testFile = './Tests/security/identity/conditional-access/Test-ConditionalAccessBaseline.Tests.ps1'
    PS C:\> Invoke-Pester -Path $testFile -Output Detailed
    Runs this test file with per-test output.

.NOTES
    File Name   : Test-ConditionalAccessBaseline.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Test-ConditionalAccessBaseline' {
    BeforeAll {
        $relativeScript = '../../../../scripts/security/identity/conditional-access/Test-ConditionalAccessBaseline.ps1'
        $scriptPath = Join-Path $PSScriptRoot $relativeScript
        $scriptName = Split-Path $scriptPath -Leaf
        $raw = [IO.File]::ReadAllText($scriptPath)
        $workingDirectory = (Get-Location).Path
        $tempRoot = [IO.Path]::GetTempPath()

        # Safe: the script's top-level guard skips Main when dot-sourced (spec section 3).
        . $scriptPath

        # The product module is not installed offline: declare its cmdlets as advanced-function
        # stubs carrying the real parameter sets, then mock them.
        function Import-Module {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true, Position = 0)][string[]]$Name
            )
        }

        function Connect-MgGraph {
            [CmdletBinding()]
            param(
                [Parameter()][string]$TenantId,
                [Parameter()][string[]]$Scopes,
                [Parameter()][switch]$NoWelcome
            )
        }

        function Invoke-MgGraphRequest {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)][string]$Method,
                [Parameter(Mandatory = $true)][string]$Uri,
                [Parameter()][hashtable]$Body,
                [Parameter()][string]$OutputType
            )
        }

        function New-GraphPage {
            [CmdletBinding()]
            param(
                [Parameter()][object[]]$Value,
                [Parameter()][string]$NextLink
            )

            $page = @{ value = @($Value) }
            if (-not [string]::IsNullOrWhiteSpace($NextLink)) { $page['@odata.nextLink'] = $NextLink }
            return $page
        }

        function New-CaPolicy {
            [CmdletBinding()]
            param(
                [Parameter()][string]$DisplayName = 'CA001: Baseline',
                [Parameter()][string]$State = 'enabled',
                [Parameter()][string[]]$IncludeApplications = @('All'),
                [Parameter()][string[]]$IncludeUsers = @('All'),
                [Parameter()][string[]]$ExcludeGroups = @()
            )

            return @{
                id          = 'policy-' + $DisplayName
                displayName = $DisplayName
                state       = $State
                conditions  = @{
                    applications = @{ includeApplications = @($IncludeApplications) }
                    users        = @{
                        includeUsers  = @($IncludeUsers)
                        includeGroups = @()
                        includeRoles  = @()
                        excludeUsers  = @()
                        excludeGroups = @($ExcludeGroups)
                    }
                }
            }
        }

        function New-CaPolicyWithoutAppScope {
            [CmdletBinding()]
            param(
                [Parameter()][string]$DisplayName = 'CA002: Report only'
            )

            $policy = New-CaPolicy -DisplayName $DisplayName -IncludeApplications @()
            $policy.state = 'enabledForReportingButNotEnforced'
            return $policy
        }

        Mock Import-Module { }
        Mock Connect-MgGraph { }
        Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*identity/conditionalAccess/policies*' } {
            New-GraphPage -Value @()
        }

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath, [ref]$tokens, [ref]$parseErrors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match "(?m)^\s*File Name\s*:\s*$([regex]::Escape($scriptName))\s*$"
            $raw | Should -Match '(?m)^\s*Author\s*:\s*\S+'
            $raw | Should -Match '(?m)^\s*Prerequisite\s*:\s*PowerShell 7\.0\s*$'
            $raw | Should -Match '(?m)^\s*Version\s*:\s*2\.0\.0\s*$'
            $raw | Should -Match '(?m)^\s*Date\s*:\s*2026-09-16\s*$'
        }

        It 'Has one .PARAMETER entry per declared parameter' {
            $parameters = @(
                'TenantId',
                'EmergencyAccessGroupId',
                'IncludeReportOnly',
                'OutputFormat',
                'OutputPath'
            )
            foreach ($name in $parameters) {
                $raw | Should -Match "(?m)^\.PARAMETER\s+$name\s*$"
            }
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

        It 'Uses CmdletBinding, Main, and the dot-source guard' {
            $raw | Should -Match '\[CmdletBinding\('
            $raw | Should -Match '(?m)^function Main\b'
            $raw | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
        }

        It 'Contains no PS7-only operators and no #Requires opt-out' {
            ($raw -match '\?\?') | Should -BeFalse
            ($raw -match '\|\|') | Should -BeFalse
            ($raw -match '&&') | Should -BeFalse
            ($raw -match '#Requires\s+-Version') | Should -BeFalse
        }

        It 'Is UTF-8 with BOM and CRLF line endings' {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }

        It 'Cites Microsoft Learn in its help' {
            $raw | Should -Match 'learn\.microsoft\.com'
        }
    }

    Context 'Behavior' {
        It 'Connects to the supplied tenant with the documented Microsoft Graph scope' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*identity/conditionalAccess/policies*' } {
                New-GraphPage -Value @( (New-CaPolicy -DisplayName 'CA007: All users') )
            }
            $TenantId = 'contoso.onmicrosoft.com'
            $OutputFormat = 'Table'
            $EmergencyAccessGroupId = ''
            $IncludeReportOnly = $false
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter {
                $TenantId -eq 'contoso.onmicrosoft.com' -and $Scopes -contains 'Policy.Read.All'
            }
        }

        It 'Passes the baseline and returns 0 when every policy is scoped' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*identity/conditionalAccess/policies*' } {
                New-GraphPage -Value @( (New-CaPolicy -DisplayName 'CA001: All users') )
            }
            $OutputFormat = 'Table'
            $EmergencyAccessGroupId = ''
            $IncludeReportOnly = $false
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($Out | Out-String) | Should -Match '\[\+\] Conditional Access baseline passed'
            ($Out | Out-String) | Should -Match 'Retrieved 1 Conditional Access policies'
            (Get-Location).Path | Should -Be $workingDirectory
            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
        }

        It 'Ignores report-only policies by default and evaluates them with -IncludeReportOnly' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*identity/conditionalAccess/policies*' } {
                New-GraphPage -Value @( (New-CaPolicyWithoutAppScope) )
            }
            $OutputFormat = 'Table'
            $EmergencyAccessGroupId = ''
            $IncludeReportOnly = $false
            $Out = Main *>&1
            ($Out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($Out | Out-String) | Should -Not -Match 'EMPTY-APP-INCLUDE'

            $IncludeReportOnly = $true
            $Out = Main *>&1
            ($Out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($Out | Out-String) | Should -Match 'EMPTY-APP-INCLUDE'
        }

        It 'Reports All-resources policies that do not exclude the emergency access group' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*identity/conditionalAccess/policies*' } {
                New-GraphPage -Value @( (New-CaPolicy -DisplayName 'CA003: All resources') )
            }
            $OutputFormat = 'Table'
            $IncludeReportOnly = $false
            $EmergencyAccessGroupId = '6f1d4e58-0d61-4f0a-8a8e-1e0d5d2a9c11'
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($Out | Out-String) | Should -Match 'ALL-APPS-NO-BREAKGLASS'
        }

        It 'Follows @odata.nextLink and counts policies across both pages' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*identity/conditionalAccess/policies*' } {
                if ($Uri -like '*skiptoken*') {
                    return New-GraphPage -Value @( (New-CaPolicy -DisplayName 'CA005: Page two') )
                }
                $nextLink = 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?$skiptoken=2'
                return New-GraphPage -Value @( (New-CaPolicy -DisplayName 'CA004: Page one') ) -NextLink $nextLink
            }
            $OutputFormat = 'Table'
            $EmergencyAccessGroupId = ''
            $IncludeReportOnly = $false
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($Out | Out-String) | Should -Match 'Retrieved 2 Conditional Access policies'
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
        }

        It 'Writes a JSON report under $env:TEMP and leaves the working directory unchanged' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*identity/conditionalAccess/policies*' } {
                New-GraphPage -Value @( (New-CaPolicy -DisplayName 'CA006: All users') )
            }
            $reportPath = Join-Path $tempRoot 'bfu-ca-baseline-report.json'
            if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath -Force }
            $OutputFormat = 'Json'
            $OutputPath = $reportPath
            $EmergencyAccessGroupId = ''
            $IncludeReportOnly = $false
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 0
            Test-Path -LiteralPath $reportPath | Should -BeTrue
            (Get-Content -LiteralPath $reportPath -Raw) | Should -Match 'PolicyCount'
            (Get-Content -LiteralPath $reportPath -Raw) | Should -Match 'FindingCount'
            (Get-Location).Path | Should -Be $workingDirectory
        }

        It 'Rejects an unsafe -OutputPath before contacting Microsoft Graph' {
            $OutputFormat = 'Json'
            $OutputPath = 'C:\..\evil-report.json'
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($Out | Out-String) | Should -Match 'Unsafe OutputPath'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
            (Get-Location).Path | Should -Be $workingDirectory
        }

        It 'Returns 1 and writes [-] output when Microsoft Graph fails' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*identity/conditionalAccess/policies*' } {
                throw 'Graph request failed'
            }
            $OutputFormat = 'Table'
            $EmergencyAccessGroupId = ''
            $IncludeReportOnly = $false
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($Out | Out-String) | Should -Match '\[-\]'
            ($Out | Out-String) | Should -Match 'Graph request failed'
        }
    }
}
