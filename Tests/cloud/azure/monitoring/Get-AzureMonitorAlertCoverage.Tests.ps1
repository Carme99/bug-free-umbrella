#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/monitoring/Get-AzureMonitorAlertCoverage.ps1.
.DESCRIPTION
    Validates help and metadata conformance, static syntax rules, and observable behavior of the Azure
    Monitor alert coverage report using fully mocked Az.Monitor cmdlets, so no Azure call ever leaves
    the machine. Runs offline on Linux pwsh; no network, Azure connectivity, or installed Az modules
    are required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/monitoring/Get-AzureMonitorAlertCoverage.Tests.ps1
    Runs this test file.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/monitoring/Get-AzureMonitorAlertCoverage.Tests.ps1 -Output Detailed
    Runs this test file with per-test output.
.NOTES
    File Name   : Get-AzureMonitorAlertCoverage.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-AzureMonitorAlertCoverage' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            '../../../../scripts/cloud/azure/monitoring/Get-AzureMonitorAlertCoverage.ps1'

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # The Az modules are not installed offline: declare their cmdlets as advanced functions with
        # the documented parameter sets (see the Learn links in the script help) so an unsupported
        # parameter throws instead of being silently ignored, then Mock each one.
        function Get-AzContext {
            [CmdletBinding()]
            param()
        }
        function Get-AzSubscription {
            [CmdletBinding()]
            param([string]$SubscriptionId, [string]$SubscriptionName, [string]$TenantId)
        }
        function Set-AzContext {
            [CmdletBinding()]
            param([string]$SubscriptionId, [string]$SubscriptionName, [string]$Name)
        }
        function Get-AzActionGroup {
            [CmdletBinding()]
            param(
                [Parameter()][string]$Name,
                [Parameter()][string]$ResourceGroupName,
                [Parameter()][string[]]$SubscriptionId,
                [Parameter()][object]$InputObject,
                [Parameter()][object]$DefaultProfile
            )
        }
        function Get-AzMetricAlertRuleV2 {
            [CmdletBinding()]
            param(
                [Parameter()][string]$ResourceGroupName,
                [Parameter()][string]$Name,
                [Parameter()][string]$ResourceId,
                [Parameter()][object]$DefaultProfile
            )
        }
        function Get-AzActivityLogAlert {
            [CmdletBinding()]
            param(
                [Parameter()][string]$ResourceGroupName,
                [Parameter()][string]$Name,
                [Parameter()][string[]]$SubscriptionId,
                [Parameter()][object]$InputObject,
                [Parameter()][object]$DefaultProfile
            )
        }
        function Get-AzScheduledQueryRule {
            [CmdletBinding()]
            param(
                [Parameter()][string]$ResourceGroupName,
                [Parameter()][string]$Name,
                [Parameter()][string[]]$SubscriptionId,
                [Parameter()][object]$InputObject,
                [Parameter()][object]$DefaultProfile
            )
        }

        $actionGroupId = '/subscriptions/sub-1/resourceGroups/rg-app/providers/' +
            'Microsoft.Insights/actionGroups/ag-ops'

        Mock Import-Module { }
        Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } } }
        Mock Get-AzSubscription { @([pscustomobject]@{ Id = 'sub-1'; Name = 'sub-prod' }) }
        Mock Set-AzContext { }
        Mock Get-AzActionGroup { @([pscustomobject]@{ Name = 'ag-ops'; ResourceGroupName = 'rg-app' }) }

        # Healthy baseline: one enabled severity 1 metric alert rule and one activity log alert, both
        # wired to the same action group.
        Mock Get-AzMetricAlertRuleV2 {
            @(
                [pscustomobject]@{
                    Name          = 'metric-cpu-high'
                    Severity      = 1
                    Enabled       = $true
                    Actions       = @($actionGroupId)
                    Scopes        = @('/subscriptions/sub-1/resourceGroups/rg-app/providers/' +
                        'Microsoft.Compute/virtualMachines/vm-1')
                    ResourceGroup = 'rg-app'
                    Id            = '/subscriptions/sub-1/resourceGroups/rg-app/providers/' +
                        'Microsoft.Insights/metricAlerts/metric-cpu-high'
                }
            )
        }
        Mock Get-AzActivityLogAlert {
            @(
                [pscustomobject]@{
                    Name    = 'activity-delete'
                    Enabled = $true
                    Actions = @([pscustomobject]@{
                            ActionGroup = @([pscustomobject]@{ ActionGroupId = $actionGroupId })
                        })
                    Scopes  = @('/subscriptions/sub-1/resourceGroups/rg-app/providers/Microsoft.Web/sites/app')
                    Id      = '/subscriptions/sub-1/resourceGroups/rg-app/providers/' +
                        'Microsoft.Insights/activityLogAlerts/activity-delete'
                }
            )
        }
        Mock Get-AzScheduledQueryRule { @() }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Get-AzureMonitorAlertCoverage\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            foreach ($name in @('SubscriptionId', 'ResourceGroupName', 'OutputFormat', 'OutputPath')) {
                $raw | Should -Match "(?m)\.PARAMETER\s+$name"
            }
        }

        It 'Provides at least two examples with PS prompts' {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, '(?m)^\s*PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $errors.Count | Should -Be 0
        }

        It 'Uses CmdletBinding, Main function, and dot-source guard' {
            $raw | Should -Match '\[CmdletBinding\('
            $raw | Should -Match '(?m)function Main\b'
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

        It 'Cites Microsoft Learn and drives the documented Az.Monitor cmdlets' {
            $raw | Should -Match 'learn\.microsoft\.com'
            $raw | Should -Match 'Get-AzMetricAlertRuleV2'
            $raw | Should -Match 'Get-AzActivityLogAlert'
            $raw | Should -Match 'Get-AzScheduledQueryRule'
            $raw | Should -Match 'Get-AzActionGroup'
        }
    }

    Context 'Behavior' {
        It 'Reports complete coverage and returns 0 when every rule is enabled with an action group' {
            $SubscriptionId = '*'
            $ResourceGroupName = $null
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive
            $workingDirectory = (Get-Location).Path

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Connected to: sub-prod'
            $text | Should -Match '\[\+\] Alert rules evaluated: 2 \(metric 1, activity log 1, scheduled query 0\)'
            $text | Should -Match '\[\+\] Action groups in scope: 1'
            $text | Should -Match '\[\+\] Enabled severity 0/1 metric alert rules: 1'
            $text | Should -Match '\[\+\] Alert coverage complete'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-AzMetricAlertRuleV2 -Times 1 -Exactly
            Should -Invoke Get-AzActivityLogAlert -Times 1 -Exactly
            Should -Invoke Get-AzScheduledQueryRule -Times 1 -Exactly
            Should -Invoke Get-AzActionGroup -Times 1 -Exactly
            (Get-Location).Path | Should -Be $workingDirectory
        }

        It 'Flags action group, disabled rule, resource group and severity gaps, returning 2' {
            $SubscriptionId = '*'
            $ResourceGroupName = $null
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Get-AzMetricAlertRuleV2 {
                @(
                    [pscustomobject]@{
                        Name          = 'metric-no-action'
                        Severity      = 3
                        Enabled       = $true
                        Actions       = @()
                        Scopes        = @('/subscriptions/sub-1/resourceGroups/rg-app/providers/' +
                            'Microsoft.Compute/virtualMachines/vm-1')
                        ResourceGroup = 'rg-app'
                        Id            = 'id-metric-no-action'
                    }
                    [pscustomobject]@{
                        Name          = 'metric-disabled'
                        Severity      = 1
                        Enabled       = $false
                        Actions       = @('ag-ops')
                        Scopes        = @('/subscriptions/sub-1/resourceGroups/rg-db/providers/' +
                            'Microsoft.Sql/servers/sql-1')
                        ResourceGroup = 'rg-db'
                        Id            = 'id-metric-disabled'
                    }
                )
            }
            Mock Get-AzActivityLogAlert { @() }
            Mock Get-AzScheduledQueryRule { @() }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[!\] 1 alert rule\(s\) have no action group'
            $text | Should -Match '    - \[Metric\] metric-no-action'
            $text | Should -Match '\[!\] 1 alert rule\(s\) are disabled'
            $text | Should -Match '    - \[Metric\] metric-disabled'
            $text | Should -Match '\[!\] 2 resource group\(s\) have no enabled alert coverage'
            $text | Should -Match '    - rg-app'
            $text | Should -Match '    - rg-db'
            $text | Should -Match '\[!\] No enabled severity 0 or severity 1 metric alert rule'
            $text | Should -Match '\[!\] 5 alert coverage gap\(s\) detected\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Writes a CSV report when OutputFormat is Csv without touching the working directory' {
            $SubscriptionId = '*'
            $ResourceGroupName = $null
            $OutputFormat = 'Csv'
            $OutputPath = $TestDrive
            $workingDirectory = (Get-Location).Path

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Report written to:'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0

            $reports = @(Get-ChildItem -Path $TestDrive -Filter 'AzureMonitorAlertCoverage-*.csv')
            $reports.Count | Should -Be 1
            (Get-Content -LiteralPath $reports[0].FullName -Raw) | Should -Match 'metric-cpu-high'
            (Get-Location).Path | Should -Be $workingDirectory
        }

        It 'Filters the queries by resource group when ResourceGroupName is supplied' {
            $SubscriptionId = '*'
            $ResourceGroupName = 'rg-app'
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-AzMetricAlertRuleV2 -Times 1 -Exactly `
                -ParameterFilter { $ResourceGroupName -eq 'rg-app' }
            Should -Invoke Get-AzActionGroup -Times 1 -Exactly `
                -ParameterFilter { $ResourceGroupName -eq 'rg-app' }
        }

        It 'Returns 1 with [-] output when not connected to Azure' {
            $SubscriptionId = '*'
            $ResourceGroupName = $null
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Get-AzContext { $null }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: Not connected to Azure'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-AzMetricAlertRuleV2 -Times 0 -Exactly -Because 'the connection check fails first'
        }

        It 'Returns 1 when the Az.Monitor module cannot be imported' {
            $SubscriptionId = '*'
            $ResourceGroupName = $null
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Import-Module { throw 'Az.Monitor is not installed' }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: Az\.Monitor is not installed'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Returns 1 when an alert rule query fails so coverage cannot be verified' {
            $SubscriptionId = '*'
            $ResourceGroupName = $null
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Get-AzMetricAlertRuleV2 { throw 'metric alert query failed with status 429' }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[!\] Metric alert rule query failed: metric alert query failed with status 429'
            $text | Should -Match '\[-\] Error: alert rule inventory incomplete'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Returns 1 when OutputPath is unsafe' {
            $SubscriptionId = '*'
            $ResourceGroupName = $null
            $OutputFormat = 'Csv'
            $OutputPath = '../outside'

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: Unsafe OutputPath'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Is idempotent: repeated read-only runs return the same exit code' {
            $SubscriptionId = '*'
            $ResourceGroupName = $null
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Main | Should -Be 0
            Main | Should -Be 0
            Should -Invoke Get-AzActionGroup -Times 2 -Exactly -Because 'one action group query per run'
        }
    }
}
