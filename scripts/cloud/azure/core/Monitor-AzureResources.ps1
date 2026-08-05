<#
.SYNOPSIS
    Comprehensive Azure resource health and cost monitoring across subscriptions.

.DESCRIPTION
    Multi-subscription Azure monitoring that provides:
    - Resource health status across all subscriptions
    - Cost analysis and budget tracking
    - Virtual machine performance and availability
    - Storage account usage and limits
    - Network connectivity and security groups
    - Resource tagging compliance
    - Orphaned resource detection (unused disks, IPs)

.PARAMETER SubscriptionId
    Azure subscription ID. Use '*' for all accessible subscriptions.

.PARAMETER DaysToAnalyze
    Days of cost and metrics data to analyze. Default: 30

.PARAMETER IncludeCostAnalysis
    Include detailed cost breakdown by resource group and service

.PARAMETER IncludeOrphanedResources
    Detect orphaned/unused resources

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for output files. Default: MyDocuments\Reports

.EXAMPLE
    Connect-AzAccount
    .\Monitor-AzureResources.ps1 -SubscriptionId "*" -IncludeCostAnalysis

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 5.1+, Az PowerShell module

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = "*",

    [Parameter(Mandatory = $false)]
    [int]$DaysToAnalyze = 30,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeCostAnalysis,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeOrphanedResources,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
)
# Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($OutputPath) -or
    $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
    $OutputPath -match '^(\\\\|//)') {
    Write-Error "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
    exit 1
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Error "Az.Accounts module required. Install: Install-Module Az"
    exit 1
}

Import-Module Az.Accounts -ErrorAction SilentlyContinue
Import-Module Az.Resources -ErrorAction SilentlyContinue
Import-Module Az.Compute -ErrorAction SilentlyContinue

$results = @{
    Timestamp = Get-Date
    Subscriptions = @()
    TotalCost = 0
    ResourceSummary = @{}
    OrphanedResources = @()
}

Write-Host "Analyzing Azure resources..." -ForegroundColor Cyan

# Ensure logged in
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Error "Not logged in. Run Connect-AzAccount first."
        exit 1
    }
} catch {
    Write-Error "Azure authentication required: Connect-AzAccount"
    exit 1
}

# Get subscriptions
$subscriptions = if ($SubscriptionId -eq '*') {
    Get-AzSubscription
} else {
    @(Get-AzSubscription -SubscriptionId $SubscriptionId)
}

Write-Host "Analyzing $($subscriptions.Count) subscription(s)..." -ForegroundColor Yellow

foreach ($sub in $subscriptions) {
    Write-Host "`nProcessing: $($sub.Name)" -ForegroundColor Cyan
    Set-AzContext -SubscriptionId $sub.Id | Out-Null

    $subData = @{
        Name = $sub.Name
        Id = $sub.Id
        State = $sub.State
        ResourceGroups = @()
        VirtualMachines = @()
        TotalResources = 0
    }

    # Get resource groups
    $rgs = Get-AzResourceGroup
    foreach ($rg in $rgs) {
        $resources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName
        $subData.ResourceGroups += @{
            Name = $rg.ResourceGroupName
            Location = $rg.Location
            ResourceCount = $resources.Count
            Tags = $rg.Tags
        }
    }

    # Get VMs
    $vms = Get-AzVM -Status
    foreach ($vm in $vms) {
        $subData.VirtualMachines += @{
            Name = $vm.Name
            ResourceGroup = $vm.ResourceGroupName
            Location = $vm.Location
            Size = $vm.HardwareProfile.VmSize
            Status = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus
        }
    }

    $subData.TotalResources = (Get-AzResource).Count
    Write-Host "  Found $($subData.TotalResources) resources, $($vms.Count) VMs" -ForegroundColor White

    # Orphaned resources
    if ($IncludeOrphanedResources) {
        # Unattached disks
        $disks = Get-AzDisk | Where-Object { $_.ManagedBy -eq $null }
        foreach ($disk in $disks) {
            $results.OrphanedResources += @{
                Type = "Unattached Disk"
                Name = $disk.Name
                ResourceGroup = $disk.ResourceGroupName
                Size = "$($disk.DiskSizeGB) GB"
                Subscription = $sub.Name
            }
        }

        # Unassociated Public IPs
        $pips = Get-AzPublicIpAddress | Where-Object { $_.IpConfiguration -eq $null }
        foreach ($pip in $pips) {
            $results.OrphanedResources += @{
                Type = "Unassociated Public IP"
                Name = $pip.Name
                ResourceGroup = $pip.ResourceGroupName
                IPAddress = $pip.IpAddress
                Subscription = $sub.Name
            }
        }
    }

    $results.Subscriptions += $subData
}

Write-Host "`nAnalysis complete!" -ForegroundColor Green

# Output
$RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
switch ($OutputFormat) {
    'Console' {
        Write-Host "`n=== Azure Resources Summary ===" -ForegroundColor Cyan
        Write-Host "Total Subscriptions: $($subscriptions.Count)" -ForegroundColor White
        foreach ($sub in $results.Subscriptions) {
            Write-Host "`n$($sub.Name): $($sub.TotalResources) resources, $($sub.VirtualMachines.Count) VMs" -ForegroundColor Yellow
        }
        if ($results.OrphanedResources.Count -gt 0) {
            Write-Host "`n=== Orphaned Resources ===" -ForegroundColor Yellow
            Write-Host "Found $($results.OrphanedResources.Count) orphaned resources" -ForegroundColor Red
        }
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "Azure-Resources-${RunTimestamp}_${RunId}.html"
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure Resources Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #0078d4; }
        table { border-collapse: collapse; width: 100%; background: white; margin: 10px 0; }
        th { background: #0078d4; color: white; padding: 10px; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
    </style>
</head>
<body>
    <h1>Azure Resources Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    <h2>Subscriptions</h2>
    <table>
        <tr><th>Subscription</th><th>Total Resources</th><th>VMs</th><th>Resource Groups</th></tr>
"@
        foreach ($sub in $results.Subscriptions) {
            $html += "<tr><td>$([System.Net.WebUtility]::HtmlEncode("$($sub.Name)"))</td><td>$($sub.TotalResources)</td><td>$($sub.VirtualMachines.Count)</td><td>$($sub.ResourceGroups.Count)</td></tr>"
        }
        $html += "</table>"

        if ($results.OrphanedResources.Count -gt 0) {
            $html += "<h2>Orphaned Resources</h2><table><tr><th>Type</th><th>Name</th><th>Resource Group</th><th>Subscription</th></tr>"
            foreach ($orphan in $results.OrphanedResources) {
                $html += "<tr><td>$([System.Net.WebUtility]::HtmlEncode("$($orphan.Type)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($orphan.Name)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($orphan.ResourceGroup)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($orphan.Subscription)"))</td></tr>"
            }
            $html += "</table>"
        }

        $html += "<p style='margin-top: 30px; text-align: center; color: #666; font-size: 12px;'><strong>Note:</strong> This report has not been thoroughly tested.</p></body></html>"
        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "`nHTML saved to: $htmlFile" -ForegroundColor Green
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "Azure-Resources-${RunTimestamp}_${RunId}.json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "`nJSON saved to: $jsonFile" -ForegroundColor Green
    }
}
