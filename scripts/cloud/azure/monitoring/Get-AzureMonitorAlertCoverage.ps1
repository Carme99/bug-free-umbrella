<#
.SYNOPSIS
    Reports Azure Monitor alert coverage gaps across alert rules, action groups and severity levels.

.DESCRIPTION
    Read-only Azure Monitor alert coverage report for one subscription or for every subscription the
    signed-in account can read. An alert rule only notifies when a fired alert can invoke the action
    groups attached to it, so a rule with no action group, or a disabled rule, leaves the monitored
    resource unwatched even though the rule exists. The alerting model audited here is documented at
    https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-overview and the platform
    metrics that metric alert rules evaluate are listed at
    https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/metrics-supported .

    The inventory is built from the Az.Monitor cmdlets that list each rule type, plus the action
    groups in scope:
    https://learn.microsoft.com/en-us/powershell/module/az.monitor/get-azmetricalertrulev2
    https://learn.microsoft.com/en-us/powershell/module/az.monitor/get-azactivitylogalert
    https://learn.microsoft.com/en-us/powershell/module/az.monitor/get-azscheduledqueryrule
    https://learn.microsoft.com/en-us/powershell/module/az.monitor/get-azactiongroup

    Findings are: alert rules with no action group, disabled alert rules, resource groups that have
    no enabled alert rule with a working action group, and subscriptions with no enabled severity 0
    or severity 1 metric alert rule.

    The script never mutates Azure resources, so re-running it against an unchanged environment
    produces the same report and the same exit code. For -OutputFormat Json or Csv it writes one
    uniquely named report file under -OutputPath. Exit codes: 0 = coverage complete; 2 = coverage
    gaps found; 1 = error (missing Az module, not signed in, unsafe -OutputPath, or an alert rule
    query failed so coverage cannot be verified).

.PARAMETER SubscriptionId
    Subscription ID to audit, or '*' to audit every subscription the signed-in account can read.
    Default: '*'.

.PARAMETER ResourceGroupName
    Optional resource group filter applied to the action group and alert rule queries. When omitted
    every resource group in the audited subscriptions is included.

.PARAMETER OutputFormat
    Report format: 'Table' prints the report to the console only, while 'Json' and 'Csv' also write a
    report file under -OutputPath. Default: 'Table'.

.PARAMETER OutputPath
    Local directory that receives the JSON/CSV report file. Must be a local path without '..'
    traversal. Default: MyDocuments\Reports.

.EXAMPLE
    PS C:\> .\Get-AzureMonitorAlertCoverage.ps1
    Audits every readable subscription and flags alert rules without action groups, disabled rules,
    resource groups with no enabled alert coverage, and missing severity 0/1 metric alert rules.

.EXAMPLE
    PS C:\> .\Get-AzureMonitorAlertCoverage.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 `
        -ResourceGroupName rg-app -OutputFormat Csv -OutputPath C:\Reports
    Audits the rg-app resource group only and writes the coverage report to a timestamped CSV file in
    C:\Reports, returning 2 when any coverage gap is found.

.NOTES
    File Name   : Get-AzureMonitorAlertCoverage.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16

    Alert model  : https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-overview
    Metric alert : https://learn.microsoft.com/en-us/powershell/module/az.monitor/get-azmetricalertrulev2
    Action group : https://learn.microsoft.com/en-us/powershell/module/az.monitor/get-azactiongroup
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'The script spec mandates Write-Host status output with [+]/[!]/[-]/[*] prefixes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Script parameters are consumed by Main through the caller scope; see the help.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId = '*',

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path ($(if ($bfuMyDocs = [Environment]::GetFolderPath('MyDocuments')) { $bfuMyDocs }
            elseif ($env:USERPROFILE) { $env:USERPROFILE }
            elseif ($env:HOME) { $env:HOME }
            else { [IO.Path]::GetTempPath() })) 'Reports')
)

$ErrorActionPreference = 'Stop'

function Get-ActionGroupId {
    <#
    .SYNOPSIS
        Returns every action group resource ID attached to one alert rule object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowNull()][object]$Rule
    )

    $ids = @()
    if ($null -eq $Rule) { return $ids }

    $queue = @()
    $actions = $Rule.PSObject.Properties['Actions']
    if ($null -ne $actions) { $queue = @($actions.Value) }

    while ($queue.Count -gt 0) {
        $current = $queue[0]
        if ($queue.Count -gt 1) {
            $queue = @($queue[1..($queue.Count - 1)])
        }
        else {
            $queue = @()
        }
        if ($null -eq $current) { continue }
        if ($current -is [string]) {
            if (-not [string]::IsNullOrWhiteSpace($current)) { $ids += [string]$current }
            continue
        }
        foreach ($name in @('ActionGroup', 'ActionGroups', 'ActionGroupId')) {
            $member = $current.PSObject.Properties[$name]
            if ($null -ne $member -and $null -ne $member.Value) { $queue += @($member.Value) }
        }
    }
    return @($ids)
}

function Get-RuleResourceGroup {
    <#
    .SYNOPSIS
        Returns the resource group names an alert rule targets, from its metadata and its scopes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowNull()][object]$Rule
    )

    $names = @()
    if ($null -eq $Rule) { return $names }

    foreach ($name in @('ResourceGroup', 'ResourceGroupName')) {
        $member = $Rule.PSObject.Properties[$name]
        if ($null -ne $member -and -not [string]::IsNullOrWhiteSpace([string]$member.Value)) {
            $names += [string]$member.Value
        }
    }

    foreach ($identifier in @(@($Rule.Scopes) + @($Rule.TargetResourceId))) {
        if ($null -eq $identifier) { continue }
        $match = [regex]::Match([string]$identifier, '/resourceGroups/([^/]+)', 'IgnoreCase')
        if ($match.Success) { $names += $match.Groups[1].Value }
    }

    return @($names | Sort-Object -Unique)
}

function ConvertTo-AlertRuleRecord {
    <#
    .SYNOPSIS
        Normalises one alert rule object into the record shape the report consumes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowNull()][object]$Rule,
        [Parameter(Mandatory = $true)][string]$RuleType,
        [Parameter(Mandatory = $true)][string]$SubscriptionName
    )

    $actionGroupIds = @(Get-ActionGroupId -Rule $Rule)
    $severity = -1
    $enabled = $true

    $severityMember = $Rule.PSObject.Properties['Severity']
    if ($null -ne $severityMember -and $null -ne $severityMember.Value) {
        $severity = [int]$severityMember.Value
    }
    $enabledMember = $Rule.PSObject.Properties['Enabled']
    if ($null -ne $enabledMember -and $null -ne $enabledMember.Value) {
        $enabled = [bool]$enabledMember.Value
    }

    return [pscustomobject]@{
        Subscription     = $SubscriptionName
        RuleType         = $RuleType
        Name             = [string]$Rule.Name
        Severity         = $severity
        Enabled          = $enabled
        ActionGroupCount = $actionGroupIds.Count
        ResourceGroups   = @(Get-RuleResourceGroup -Rule $Rule)
        Id               = [string]$Rule.Id
    }
}

function Main {
    <#
    .SYNOPSIS
        Audits Azure Monitor alert coverage and returns the documented exit code.
    #>
    [CmdletBinding()]
    param()

    try {
        if ([string]::IsNullOrWhiteSpace($OutputPath) -or
            $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
            $OutputPath -match '^(\\\\|//)') {
            throw "Unsafe OutputPath: '$OutputPath'. Use a local path without '..' traversal."
        }
        $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)

        Write-Host "[*] Checking Azure connection..." -ForegroundColor Cyan
        Import-Module Az.Accounts -ErrorAction Stop
        Import-Module Az.Monitor -ErrorAction Stop
        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            throw "Not connected to Azure. Run: Connect-AzAccount"
        }
        Write-Host "[+] Connected to: $($context.Subscription.Name)" -ForegroundColor Green

        $subscriptions = if ($SubscriptionId -eq '*') {
            @(Get-AzSubscription -ErrorAction Stop)
        }
        else {
            @(Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop)
        }
        if ($subscriptions.Count -eq 0) {
            throw "No readable subscriptions found for '$SubscriptionId'."
        }

        $filterByResourceGroup = -not [string]::IsNullOrWhiteSpace($ResourceGroupName)
        $queries = @(
            @{ Type = 'Metric'; Cmdlet = 'Get-AzMetricAlertRuleV2' }
            @{ Type = 'ActivityLog'; Cmdlet = 'Get-AzActivityLogAlert' }
            @{ Type = 'ScheduledQuery'; Cmdlet = 'Get-AzScheduledQueryRule' }
        )

        $records = @()
        $actionGroupCount = 0
        $queryFailures = 0

        foreach ($subscription in $subscriptions) {
            Write-Host "[*] Auditing alert rules for subscription: $($subscription.Name)" -ForegroundColor Cyan
            Set-AzContext -SubscriptionId $subscription.Id -ErrorAction Stop | Out-Null

            try {
                $actionGroups = if ($filterByResourceGroup) {
                    @(Get-AzActionGroup -ResourceGroupName $ResourceGroupName -ErrorAction Stop)
                }
                else {
                    @(Get-AzActionGroup -SubscriptionId $subscription.Id -ErrorAction Stop)
                }
                $actionGroupCount = $actionGroupCount + $actionGroups.Count
            }
            catch {
                Write-Host "[!] Action group query failed: $($_.Exception.Message)" -ForegroundColor Yellow
                $queryFailures = $queryFailures + 1
            }

            foreach ($query in $queries) {
                try {
                    $rules = if ($filterByResourceGroup) {
                        @(& $query.Cmdlet -ResourceGroupName $ResourceGroupName -ErrorAction Stop)
                    }
                    else {
                        @(& $query.Cmdlet -ErrorAction Stop)
                    }
                    foreach ($rule in $rules) {
                        $records += ConvertTo-AlertRuleRecord -Rule $rule -RuleType $query.Type `
                            -SubscriptionName $subscription.Name
                    }
                }
                catch {
                    Write-Host "[!] $($query.Type) alert rule query failed: $($_.Exception.Message)" `
                        -ForegroundColor Yellow
                    $queryFailures = $queryFailures + 1
                }
            }
        }

        $metricRules = @($records | Where-Object { $_.RuleType -eq 'Metric' })
        $activityLogRules = @($records | Where-Object { $_.RuleType -eq 'ActivityLog' })
        $scheduledRules = @($records | Where-Object { $_.RuleType -eq 'ScheduledQuery' })
        $noActionGroup = @($records | Where-Object { $_.ActionGroupCount -eq 0 })
        $disabledRules = @($records | Where-Object { -not $_.Enabled })
        $criticalRules = @($metricRules | Where-Object {
                $_.Enabled -and ($_.Severity -eq 0 -or $_.Severity -eq 1)
            })

        $coveredGroups = @($records | Where-Object { $_.Enabled -and $_.ActionGroupCount -gt 0 } |
            ForEach-Object { $_.ResourceGroups } | Sort-Object -Unique)
        $uncoveredGroups = @(@($records | ForEach-Object { $_.ResourceGroups } | Sort-Object -Unique) |
            Where-Object { $coveredGroups -notcontains $_ })

        $breakdown = "metric $($metricRules.Count), activity log $($activityLogRules.Count), " +
            "scheduled query $($scheduledRules.Count)"
        Write-Host "[+] Alert rules evaluated: $($records.Count) ($breakdown)" -ForegroundColor Green
        Write-Host "[+] Action groups in scope: $actionGroupCount" -ForegroundColor Green
        Write-Host "[+] Enabled severity 0/1 metric alert rules: $($criticalRules.Count)" -ForegroundColor Green

        $findingCount = 0

        if ($noActionGroup.Count -gt 0) {
            $findingCount = $findingCount + $noActionGroup.Count
            $header = "[!] $($noActionGroup.Count) alert rule(s) have no action group (no notification path):"
            Write-Host $header -ForegroundColor Yellow
            foreach ($rule in $noActionGroup) {
                Write-Host "    - [$($rule.RuleType)] $($rule.Name)" -ForegroundColor Yellow
            }
        }

        if ($disabledRules.Count -gt 0) {
            $findingCount = $findingCount + $disabledRules.Count
            Write-Host "[!] $($disabledRules.Count) alert rule(s) are disabled:" -ForegroundColor Yellow
            foreach ($rule in $disabledRules) {
                Write-Host "    - [$($rule.RuleType)] $($rule.Name)" -ForegroundColor Yellow
            }
        }

        if ($uncoveredGroups.Count -gt 0) {
            $findingCount = $findingCount + $uncoveredGroups.Count
            $header = "[!] $($uncoveredGroups.Count) resource group(s) have no enabled alert coverage:"
            Write-Host $header -ForegroundColor Yellow
            foreach ($group in $uncoveredGroups) {
                Write-Host "    - $group" -ForegroundColor Yellow
            }
        }

        if ($criticalRules.Count -eq 0) {
            $findingCount = $findingCount + 1
            $header = "[!] No enabled severity 0 or severity 1 metric alert rule: critical coverage is missing."
            Write-Host $header -ForegroundColor Yellow
        }

        $reportRows = @($records | ForEach-Object {
                [pscustomobject]@{
                    Subscription     = $_.Subscription
                    RuleType         = $_.RuleType
                    Name             = $_.Name
                    Severity         = $_.Severity
                    Enabled          = $_.Enabled
                    ActionGroupCount = $_.ActionGroupCount
                    ResourceGroups   = ($_.ResourceGroups -join ';')
                    Id               = $_.Id
                }
            })

        if ($OutputFormat -ne 'Table') {
            if (-not (Test-Path -LiteralPath $resolvedOutputPath)) {
                New-Item -ItemType Directory -Path $resolvedOutputPath -Force | Out-Null
            }
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            if ($OutputFormat -eq 'Csv') {
                $reportFile = Join-Path $resolvedOutputPath "AzureMonitorAlertCoverage-$stamp.csv"
                $content = @($reportRows | ConvertTo-Csv -NoTypeInformation)
            }
            else {
                $reportFile = Join-Path $resolvedOutputPath "AzureMonitorAlertCoverage-$stamp.json"
                $content = @($reportRows | ConvertTo-Json -Depth 6)
            }
            Set-Content -LiteralPath $reportFile -Value $content -Encoding UTF8
            Write-Host "[+] Report written to: $reportFile" -ForegroundColor Green
        }

        if ($queryFailures -gt 0) {
            $header = "[!] $queryFailures alert rule query(ies) failed; coverage cannot be verified."
            Write-Host $header -ForegroundColor Yellow
            Write-Host "[-] Error: alert rule inventory incomplete" -ForegroundColor Red
            return 1
        }

        if ($findingCount -eq 0) {
            Write-Host ("[+] Alert coverage complete: every rule is enabled, has an action group, " +
                "and severity 0/1 coverage exists.") -ForegroundColor Green
            return 0
        }

        Write-Host "[!] $findingCount alert coverage gap(s) detected." -ForegroundColor Yellow
        return 2
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
