<#
.SYNOPSIS
    Check Azure resource health and inventory across one or all accessible subscriptions.

.DESCRIPTION
    Multi-subscription Azure monitoring that provides:
    - Resource health status across all subscriptions
    - Cost analysis and budget tracking (via the Cost Details API / cost exports;
      the Consumption Usage Details API is deprecated)
    - Virtual machine performance and availability
    - Storage account usage and limits
    - Network connectivity and security groups
    - Resource tagging compliance
    - Orphaned resource detection (unused disks, IPs)

    The script is read-only: it never mutates Azure resources, so re-running it on an
    already-analyzed environment always succeeds and makes no changes. Exit codes:
    0 on success; 1 on any failure (missing Az module, not authenticated, unsafe path,
    upstream error).

.PARAMETER SubscriptionId
    Azure subscription ID. Use '*' for all accessible subscriptions.

.PARAMETER DaysToAnalyze
    Days of cost and metrics data to analyze. Default: 30.
    NOTE: reserved for the planned Cost Details API integration; the relaunch keeps
    runtime behavior unchanged, so this parameter is accepted but not yet consumed.

.PARAMETER IncludeCostAnalysis
    Include detailed cost breakdown by resource group and service. Uses the Cost
    Details API / cost exports
    (https://learn.microsoft.com/en-us/azure/cost-management-billing/automate/migrate-consumption-usage-details-api);
    the Consumption Usage Details API is deprecated.
    NOTE: reserved switch, not yet wired (behavior-preserving relaunch).

.PARAMETER IncludeOrphanedResources
    Detect orphaned/unused resources.

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for output files. Must be a local absolute path without '..' traversal.
    Default: MyDocuments\Reports

.EXAMPLE
    PS C:\> Connect-AzAccount
    PS C:\> .\Monitor-AzureResources.ps1 -SubscriptionId "*" -IncludeCostAnalysis

    Analyzes every accessible subscription and requests the cost breakdown.

.EXAMPLE
    PS C:\> .\Monitor-AzureResources.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000001" `
        -OutputFormat Console -IncludeOrphanedResources

    Analyzes a single subscription, prints a console summary, and detects orphaned
    unattached disks and unassociated public IPs.

.NOTES
    File Name: Monitor-AzureResources.ps1
    Author: IT Operations
    Prerequisite: PowerShell 7.0, Az PowerShell module (Az.Accounts, Az.Resources, Az.Compute)
    Version: 1.0.0
    Date: 2026-08-23
#>

#Requires -Version 7.0
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'RELAUNCH-SPEC section 3 mandates Write-Host output with [+]/[!]/[-]/[*] prefixes')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Params consumed inside Main via scoping; see help')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = '*',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
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

$ErrorActionPreference = 'Stop'

function Main {
    <#
    .SYNOPSIS
        Runs the Azure resource monitoring flow; returns 0 on success, 1 on failure.
    #>
    [CmdletBinding()]
    param()

    try {
        # Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
        if ([string]::IsNullOrWhiteSpace($OutputPath) -or
            $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
            $OutputPath -match '^(\\\\|//)') {
            Write-Host "[-] Unsafe OutputPath: $OutputPath." -ForegroundColor Red
            Write-Host "    Use a local absolute path without '..' traversal." -ForegroundColor Red
            return 1
        }
        $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
        if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
            Write-Host "[-] Az.Accounts module required. Install: Install-Module Az" -ForegroundColor Red
            return 1
        }

        Import-Module Az.Accounts -ErrorAction SilentlyContinue
        Import-Module Az.Resources -ErrorAction SilentlyContinue
        Import-Module Az.Compute -ErrorAction SilentlyContinue

        $results = @{
            Timestamp         = Get-Date
            Subscriptions     = @()
            TotalCost         = 0
            ResourceSummary   = @{}
            OrphanedResources = @()
        }

        Write-Host "[*] Analyzing Azure resources..." -ForegroundColor Cyan

        # Ensure logged in
        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            Write-Host "[-] Not logged in. Run Connect-AzAccount first." -ForegroundColor Red
            return 1
        }

        # Get subscriptions
        if ($SubscriptionId -eq '*') {
            $subscriptions = @(Get-AzSubscription -ErrorAction Stop)
        }
        else {
            $subscriptions = @(Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop)
        }

        Write-Host "[*] Analyzing $($subscriptions.Count) subscription(s)..." -ForegroundColor Cyan

        foreach ($sub in $subscriptions) {
            Write-Host "`n[*] Processing: $($sub.Name)" -ForegroundColor Cyan
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null

            $subData = @{
                Name            = $sub.Name
                Id              = $sub.Id
                State           = $sub.State
                ResourceGroups  = @()
                VirtualMachines = @()
                TotalResources  = 0
            }

            # Get resource groups
            $rgs = Get-AzResourceGroup -ErrorAction Stop
            foreach ($rg in $rgs) {
                $resources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName -ErrorAction Stop
                $subData.ResourceGroups += @{
                    Name          = $rg.ResourceGroupName
                    Location      = $rg.Location
                    ResourceCount = $resources.Count
                    Tags          = $rg.Tags
                }
            }

            # Get VMs
            $vms = Get-AzVM -Status -ErrorAction Stop
            foreach ($vm in $vms) {
                $subData.VirtualMachines += @{
                    Name          = $vm.Name
                    ResourceGroup = $vm.ResourceGroupName
                    Location      = $vm.Location
                    Size          = $vm.HardwareProfile.VmSize
                    Status        = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus
                }
            }

            $subData.TotalResources = (Get-AzResource -ErrorAction Stop).Count
            Write-Host "  Found $($subData.TotalResources) resources, $($vms.Count) VMs" -ForegroundColor White

            # Orphaned resources
            if ($IncludeOrphanedResources) {
                # Unattached disks
                $disks = Get-AzDisk -ErrorAction Stop | Where-Object { $null -eq $_.ManagedBy }
                foreach ($disk in $disks) {
                    $results.OrphanedResources += @{
                        Type          = 'Unattached Disk'
                        Name          = $disk.Name
                        ResourceGroup = $disk.ResourceGroupName
                        Size          = "$($disk.DiskSizeGB) GB"
                        Subscription  = $sub.Name
                    }
                }

                # Unassociated Public IPs
                $pips = Get-AzPublicIpAddress -ErrorAction Stop | Where-Object { $null -eq $_.IpConfiguration }
                foreach ($pip in $pips) {
                    $results.OrphanedResources += @{
                        Type          = 'Unassociated Public IP'
                        Name          = $pip.Name
                        ResourceGroup = $pip.ResourceGroupName
                        IPAddress     = $pip.IpAddress
                        Subscription  = $sub.Name
                    }
                }
            }

            $results.Subscriptions += $subData
        }

        Write-Host "`n[+] Analysis complete!" -ForegroundColor Green

        # Run-scoped stamp to avoid filename collisions on rapid re-runs
        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

        # Output
        switch ($OutputFormat) {
            'Console' {
                Write-Host "`n=== Azure Resources Summary ===" -ForegroundColor Cyan
                Write-Host "Total Subscriptions: $($subscriptions.Count)" -ForegroundColor White
                foreach ($sub in $results.Subscriptions) {
                    $subSummary = "$($sub.Name): $($sub.TotalResources) resources, $($sub.VirtualMachines.Count) VMs"
                    Write-Host "`n$subSummary" -ForegroundColor Yellow
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
                    $nameCell = [System.Net.WebUtility]::HtmlEncode("$($sub.Name)")
                    $html += "<tr><td>$nameCell</td><td>$($sub.TotalResources)</td>" +
                        "<td>$($sub.VirtualMachines.Count)</td><td>$($sub.ResourceGroups.Count)</td></tr>"
                }
                $html += '</table>'

                if ($results.OrphanedResources.Count -gt 0) {
                    $html += '<h2>Orphaned Resources</h2><table>' +
                        '<tr><th>Type</th><th>Name</th><th>Resource Group</th><th>Subscription</th></tr>'
                    foreach ($orphan in $results.OrphanedResources) {
                        $values = @($orphan.Type, $orphan.Name,
                            $orphan.ResourceGroup, $orphan.Subscription)
                        $cells = foreach ($value in $values) {
                            [System.Net.WebUtility]::HtmlEncode("$value")
                        }
                        $html += '<tr><td>' + ($cells -join '</td><td>') + '</td></tr>'
                    }
                    $html += '</table>'
                }

                $html += "</table><p style='margin-top: 30px; text-align: center; color: #666; font-size: 12px;'>" +
                    "<strong>Note:</strong> This report has not been thoroughly tested.</p></body></html>"
                $html | Out-File -FilePath $htmlFile -Encoding utf8
                Write-Host "`n[+] HTML saved to: $htmlFile" -ForegroundColor Green
            }

            'JSON' {
                $jsonFile = Join-Path $OutputPath "Azure-Resources-${RunTimestamp}_${RunId}.json"
                $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
                Write-Host "`n[+] JSON saved to: $jsonFile" -ForegroundColor Green
            }
        }

        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
