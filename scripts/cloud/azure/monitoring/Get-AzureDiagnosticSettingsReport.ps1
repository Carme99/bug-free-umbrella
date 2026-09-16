<#
.SYNOPSIS
    Reports Azure Monitor diagnostic settings coverage and destinations across subscription resources.

.DESCRIPTION
    Read-only Azure Monitor diagnostic settings report for one subscription or for every subscription
    the signed-in account can read. Diagnostic settings are the per-resource configuration that routes
    platform metrics, the activity log and resource logs to destinations such as a Log Analytics
    workspace, a storage account or an event hub; a resource with no diagnostic setting sends nothing
    anywhere, and a setting with no Log Analytics workspace cannot be queried with log search alerts.
    The concepts and destination rules applied here are documented at
    https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/diagnostic-settings and the
    platform metrics available per resource type are listed at
    https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/metrics-supported .

    The inventory is built with Get-AzResource for the resource list and with Get-AzDiagnosticSetting
    per resource ID:
    https://learn.microsoft.com/en-us/powershell/module/az.resources/get-azresource
    https://learn.microsoft.com/en-us/powershell/module/az.monitor/get-azdiagnosticsetting

    Findings are resources with no diagnostic setting and diagnostic settings with no Log Analytics
    workspace destination.

    The script never mutates Azure resources, so re-running it against an unchanged environment
    produces the same report and the same exit code. For -OutputFormat Json or Csv it writes one
    uniquely named report file under -OutputPath. Exit codes: 0 = compliant; 2 = findings present;
    1 = error (missing Az module, not signed in, unsafe -OutputPath, or a diagnostic settings query
    failed so compliance cannot be verified).

.PARAMETER SubscriptionId
    Subscription ID to report on, or '*' to report on every subscription the signed-in account can
    read. Default: '*'.

.PARAMETER ResourceType
    Resource type filter passed to Get-AzResource, for example 'Microsoft.KeyVault/vaults'. '*' lists
    every resource type in the audited subscriptions. Default: '*'.

.PARAMETER OutputFormat
    Report format: 'Table' prints the report to the console only, while 'Json' and 'Csv' also write a
    report file under -OutputPath. Default: 'Table'.

.PARAMETER OutputPath
    Local directory that receives the JSON/CSV report file. Must be a local path without '..'
    traversal. Default: MyDocuments\Reports.

.EXAMPLE
    PS C:\> .\Get-AzureDiagnosticSettingsReport.ps1
    Lists every resource in every readable subscription with the destinations and enabled categories
    of its diagnostic settings, and flags resources with none and settings with no Log Analytics
    destination.

.EXAMPLE
    PS C:\> .\Get-AzureDiagnosticSettingsReport.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 `
        -ResourceType Microsoft.KeyVault/vaults -OutputFormat Json -OutputPath C:\Reports
    Reports diagnostic settings for key vaults only and writes the findings to a timestamped JSON file
    in C:\Reports, returning 2 when any finding is present.

.NOTES
    File Name   : Get-AzureDiagnosticSettingsReport.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16

    Diagnostic settings : https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/diagnostic-settings
    Get-AzDiagnosticSetting : https://learn.microsoft.com/en-us/powershell/module/az.monitor/get-azdiagnosticsetting
    Get-AzResource : https://learn.microsoft.com/en-us/powershell/module/az.resources/get-azresource
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
    [ValidateNotNullOrEmpty()]
    [string]$ResourceType = '*',

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

function Get-DiagnosticDestination {
    <#
    .SYNOPSIS
        Returns the destination names configured on one diagnostic setting.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowNull()][object]$Setting
    )

    $destinations = @()
    if ($null -eq $Setting) { return $destinations }

    if (-not [string]::IsNullOrWhiteSpace([string]$Setting.WorkspaceId)) {
        $destinations += 'LogAnalytics'
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Setting.StorageAccountId)) {
        $destinations += 'Storage'
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Setting.EventHubAuthorizationRuleId)) {
        $destinations += 'EventHub'
    }
    return $destinations
}

function Get-EnabledCategory {
    <#
    .SYNOPSIS
        Returns the enabled category or category group names from a diagnostic setting category list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][object[]]$Categories
    )

    $names = @()
    foreach ($category in @($Categories)) {
        if ($null -eq $category) { continue }
        if (-not [bool]$category.Enabled) { continue }
        $name = [string]$category.Category
        if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]$category.CategoryGroup }
        if (-not [string]::IsNullOrWhiteSpace($name)) { $names += $name }
    }
    return @($names | Sort-Object -Unique)
}

function ConvertTo-DiagnosticSettingRecord {
    <#
    .SYNOPSIS
        Normalises one resource plus its diagnostic settings into the report row shape.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Resource,
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][object[]]$Setting,
        [Parameter(Mandatory = $true)][string]$SubscriptionName
    )

    $rows = @()
    $settings = @($Setting)

    if ($settings.Count -eq 0) {
        return @([pscustomobject]@{
                Subscription     = $SubscriptionName
                ResourceName     = [string]$Resource.Name
                ResourceType     = [string]$Resource.ResourceType
                ResourceGroup    = [string]$Resource.ResourceGroupName
                ResourceId       = [string]$Resource.ResourceId
                SettingName      = ''
                Destinations     = ''
                LogCategories    = ''
                MetricCategories = ''
                Status           = 'NoSettings'
            })
    }

    foreach ($item in $settings) {
        $destinations = @(Get-DiagnosticDestination -Setting $item)
        $logCategories = @(Get-EnabledCategory -Categories @($item.Log))
        $metricCategories = @(Get-EnabledCategory -Categories @($item.Metric))
        $status = if ($destinations -contains 'LogAnalytics') { 'OK' } else { 'NoLogAnalytics' }

        $rows += [pscustomobject]@{
            Subscription     = $SubscriptionName
            ResourceName     = [string]$Resource.Name
            ResourceType     = [string]$Resource.ResourceType
            ResourceGroup    = [string]$Resource.ResourceGroupName
            ResourceId       = [string]$Resource.ResourceId
            SettingName      = [string]$item.Name
            Destinations     = ($destinations -join ';')
            LogCategories    = ($logCategories -join ';')
            MetricCategories = ($metricCategories -join ';')
            Status           = $status
        }
    }
    return $rows
}

function Main {
    <#
    .SYNOPSIS
        Audits Azure Monitor diagnostic settings and returns the documented exit code.
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
        Import-Module Az.Resources -ErrorAction Stop
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

        $rows = @()
        $resourceTotal = 0
        $failureCount = 0

        foreach ($subscription in $subscriptions) {
            $header = "[*] Auditing diagnostic settings for subscription: $($subscription.Name)"
            Write-Host $header -ForegroundColor Cyan
            Set-AzContext -SubscriptionId $subscription.Id -ErrorAction Stop | Out-Null

            try {
                $resources = if ($ResourceType -eq '*') {
                    @(Get-AzResource -ErrorAction Stop)
                }
                else {
                    @(Get-AzResource -ResourceType $ResourceType -ErrorAction Stop)
                }
            }
            catch {
                Write-Host "[!] Resource query failed: $($_.Exception.Message)" -ForegroundColor Yellow
                $failureCount = $failureCount + 1
                continue
            }
            $resourceTotal = $resourceTotal + $resources.Count

            foreach ($resource in $resources) {
                try {
                    $settings = @(Get-AzDiagnosticSetting -ResourceId $resource.ResourceId -ErrorAction Stop)
                    $rows += ConvertTo-DiagnosticSettingRecord -Resource $resource -Setting $settings `
                        -SubscriptionName $subscription.Name
                }
                catch {
                    $failureMessage = "Diagnostic setting query failed for '$($resource.Name)': " +
                        "$($_.Exception.Message)"
                    Write-Host "[!] $failureMessage" -ForegroundColor Yellow
                    $failureCount = $failureCount + 1
                }
            }
        }

        $noSettingsRows = @($rows | Where-Object { $_.Status -eq 'NoSettings' })
        $noLogAnalyticsRows = @($rows | Where-Object { $_.Status -eq 'NoLogAnalytics' })
        $settingRows = @($rows | Where-Object { $_.Status -ne 'NoSettings' })

        Write-Host "[+] Resources evaluated: $resourceTotal" -ForegroundColor Green
        Write-Host "[+] Diagnostic settings found: $($settingRows.Count)" -ForegroundColor Green

        foreach ($row in $settingRows) {
            $header = "    $($row.ResourceName) [$($row.SettingName)] -> $($row.Destinations)"
            Write-Host $header -ForegroundColor Cyan
            Write-Host "        logs: $($row.LogCategories)"
            Write-Host "        metrics: $($row.MetricCategories)"
        }

        if ($noSettingsRows.Count -gt 0) {
            $header = "[!] $($noSettingsRows.Count) resource(s) have no diagnostic setting:"
            Write-Host $header -ForegroundColor Yellow
            foreach ($row in $noSettingsRows) {
                Write-Host "    - $($row.ResourceType)/$($row.ResourceName)" -ForegroundColor Yellow
            }
        }

        if ($noLogAnalyticsRows.Count -gt 0) {
            $header = "[!] $($noLogAnalyticsRows.Count) diagnostic setting(s) have no Log Analytics " +
                "destination:"
            Write-Host $header -ForegroundColor Yellow
            foreach ($row in $noLogAnalyticsRows) {
                Write-Host "    - $($row.ResourceName)/$($row.SettingName)" -ForegroundColor Yellow
            }
        }

        if ($OutputFormat -ne 'Table') {
            if (-not (Test-Path -LiteralPath $resolvedOutputPath)) {
                New-Item -ItemType Directory -Path $resolvedOutputPath -Force | Out-Null
            }
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            if ($OutputFormat -eq 'Csv') {
                $reportFile = Join-Path $resolvedOutputPath "AzureDiagnosticSettings-$stamp.csv"
                $content = @($rows | ConvertTo-Csv -NoTypeInformation)
            }
            else {
                $reportFile = Join-Path $resolvedOutputPath "AzureDiagnosticSettings-$stamp.json"
                $content = @($rows | ConvertTo-Json -Depth 6)
            }
            Set-Content -LiteralPath $reportFile -Value $content -Encoding UTF8
            Write-Host "[+] Report written to: $reportFile" -ForegroundColor Green
        }

        if ($failureCount -gt 0) {
            $header = "[!] $failureCount diagnostic settings query(ies) failed; " +
                "compliance cannot be verified."
            Write-Host $header -ForegroundColor Yellow
            Write-Host "[-] Error: diagnostic settings inventory incomplete" -ForegroundColor Red
            return 1
        }

        $findingCount = $noSettingsRows.Count + $noLogAnalyticsRows.Count
        if ($findingCount -eq 0) {
            Write-Host ("[+] Diagnostic settings are compliant: every resource has a diagnostic setting " +
                "and every setting sends data to Log Analytics.") -ForegroundColor Green
            return 0
        }

        Write-Host "[!] $findingCount diagnostic settings finding(s) detected." -ForegroundColor Yellow
        return 2
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
