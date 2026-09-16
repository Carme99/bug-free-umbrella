<#
.SYNOPSIS
    Reports Azure NSG-to-virtual-network flow log migration status read-only.

.DESCRIPTION
    Read-only migration readiness report for the NSG flow log retirement. NSG
    flow logs retire on September 30, 2027 and no longer support new creation,
    so every subscription must move to virtual network flow logs:
    https://learn.microsoft.com/azure/network-watcher/nsg-flow-logs-manage

    For every selected subscription the script lists virtual networks, reads
    the flow log resources of each region those networks occupy, and reports:

    - virtual networks covered by a virtual network flow log, plus virtual
      network flow log resources that are disabled and therefore not logging
    - network security groups that still have a legacy NSG flow log, with the
      storage account each flow log writes to
    - virtual networks with no flow logging at all, calculated from enabled
      flow logs only

    The script also prints the retirement date and the Microsoft.Insights
    resource provider registration check that virtual network flow logging
    requires:
    https://learn.microsoft.com/azure/network-watcher/vnet-flow-logs-overview

    The script is read-only and idempotent: it never mutates Azure state, so
    re-running it makes no changes. Exit codes: 0 = fully migrated;
    2 = legacy NSG flow logs or uncovered virtual networks remain; 1 = error
    (no Azure context, Az modules unavailable, unsafe -OutputPath, or a flow
    log query failed so the report is incomplete).

.PARAMETER SubscriptionId
    Subscription ID to report on. Use '*' (the default) for every accessible
    subscription.

.PARAMETER OutputFormat
    Report format: 'Table' (console detail), 'Json', or 'Csv'. Default: 'Table'.

.PARAMETER OutputPath
    Optional directory for the Json or Csv report. Must be a local absolute
    path without '..' traversal. When omitted, Json and Csv output is written
    to the console instead.

.EXAMPLE
    PS C:\> .\Get-AzureFlowLogMigrationStatus.ps1 -SubscriptionId '*'
    Reports flow log migration status for every accessible subscription.

.EXAMPLE
    PS C:\> .\Get-AzureFlowLogMigrationStatus.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000001' `
        -OutputFormat Csv -OutputPath 'C:\Reports'
    Reports one subscription and writes a CSV report into C:\Reports.

.NOTES
    File Name   : Get-AzureFlowLogMigrationStatus.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16

    NSG flow logs retire on September 30, 2027:
    https://learn.microsoft.com/azure/network-watcher/nsg-flow-logs-manage
    Virtual network flow log scope and provider registration:
    https://learn.microsoft.com/azure/network-watcher/vnet-flow-logs-overview
    Cmdlet reference pages:
    https://learn.microsoft.com/powershell/module/az.network/get-aznetworkwatcherflowlog
    https://learn.microsoft.com/powershell/module/az.network/get-azvirtualnetwork
#>
[CmdletBinding()]
param(
    [Parameter()][string]$SubscriptionId = '*',
    [Parameter()][ValidateSet('Table', 'Json', 'Csv')][string]$OutputFormat = 'Table',
    [Parameter()][string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Get-ResourceNameFromId {
    param([string]$Id)

    if ([string]::IsNullOrWhiteSpace($Id)) {
        return $null
    }
    $segments = $Id.TrimEnd('/').Split('/')
    return $segments[$segments.Count - 1]
}

function Test-IdInList {
    param([string]$Id, [string[]]$List)

    if (-not $Id) {
        return $false
    }
    foreach ($item in $List) {
        if ($item -and ($item.TrimEnd('/') -ieq $Id.TrimEnd('/'))) {
            return $true
        }
    }
    return $false
}

function Main {
    try {
        if (-not (Get-Command Get-AzContext -ErrorAction SilentlyContinue)) {
            throw "Az.Accounts is not available. Install-Module Az.Accounts"
        }

        Write-Host "[*] Checking Azure connection..." -ForegroundColor Cyan
        Import-Module Az.Accounts -ErrorAction Stop
        Import-Module Az.Network -ErrorAction Stop

        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            throw "Not connected to Azure. Run: Connect-AzAccount"
        }
        Write-Host "[+] Azure context: $($context.Subscription.Name)" -ForegroundColor Green

        if ($OutputPath) {
            if ($OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or $OutputPath -match '^(\\\\|//)') {
                Write-Host "[-] Unsafe OutputPath: $OutputPath." -ForegroundColor Red
                Write-Host "    Use a local absolute path without '..' traversal." -ForegroundColor Red
                return 1
            }
            if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
                New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            }
        }

        if ($SubscriptionId -eq '*') {
            $subscriptions = @(Get-AzSubscription -ErrorAction Stop)
        }
        else {
            $subscriptions = @(Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop)
        }
        if ($subscriptions.Count -eq 0) {
            throw "No accessible Azure subscription matched '$SubscriptionId'."
        }
        Write-Host "[*] Auditing $($subscriptions.Count) subscription(s)..." -ForegroundColor Cyan
        Write-Host "[*] NSG flow logs retire on September 30, 2027 and no longer support new" `
            -ForegroundColor Cyan -NoNewline
        Write-Host " creation." -ForegroundColor Cyan
        Write-Host "[*] Migrate to virtual network flow logs:" -ForegroundColor Cyan
        Write-Host "    https://learn.microsoft.com/azure/network-watcher/nsg-flow-logs-manage" `
            -ForegroundColor Cyan
        Write-Host "[*] Virtual network flow logging requires the Microsoft.Insights provider:" `
            -ForegroundColor Cyan
        Write-Host "    Check: Get-AzResourceProvider -ProviderNamespace 'Microsoft.Insights'" `
            -ForegroundColor White
        Write-Host "    Fix:   Register-AzResourceProvider -ProviderNamespace 'Microsoft.Insights'" `
            -ForegroundColor White

        $vnetFlowLogs = @()
        $legacyFlowLogs = @()
        $uncoveredVnets = @()
        $coveredVnetIds = @()
        $incomplete = $false

        foreach ($sub in $subscriptions) {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            Write-Host "[*] Auditing subscription: $($sub.Name)" -ForegroundColor Cyan

            try {
                $vnets = @(Get-AzVirtualNetwork -ErrorAction Stop)
            }
            catch {
                Write-Host "[!] Failed to read VNets: $($_.Exception.Message)" -ForegroundColor Yellow
                $incomplete = $true
                continue
            }

            $flowLogs = @()
            $locations = @($vnets | ForEach-Object { $_.Location } | Where-Object { $_ } |
                Sort-Object -Unique)
            foreach ($location in $locations) {
                try {
                    $flowLogs += @(Get-AzNetworkWatcherFlowLog -Location $location -ErrorAction Stop)
                }
                catch {
                    Write-Host "[!] Failed to read flow logs in ${location}: $($_.Exception.Message)" `
                        -ForegroundColor Yellow
                    $incomplete = $true
                }
            }
            Write-Host "[+] $($sub.Name): $($vnets.Count) VNets, $($flowLogs.Count) flow logs" `
                -ForegroundColor Green

            $enabledVnetIds = @()
            $enabledLegacyNsgIds = @()

            foreach ($flowLog in $flowLogs) {
                $targetId = "$($flowLog.TargetResourceId)"
                $state = 'enabled'
                if ($flowLog.Enabled -eq $false) {
                    $state = 'disabled'
                }
                if ($targetId -match '(?i)/virtualNetworks/[^/]+$') {
                    $vnetFlowLogs += [pscustomobject]@{
                        Subscription = $sub.Name
                        Name         = $flowLog.Name
                        Location     = $flowLog.Location
                        VNet         = Get-ResourceNameFromId -Id $targetId
                        State        = $state
                    }
                    if ($state -eq 'enabled') {
                        $enabledVnetIds += $targetId
                    }
                    continue
                }
                if ($targetId -notmatch '(?i)/networkSecurityGroups/[^/]+$') {
                    continue
                }
                $storageAccount = 'unknown'
                if ("$($flowLog.StorageId)" -match '(?i)/storageAccounts/([^/]+)$') {
                    $storageAccount = $Matches[1]
                }
                $legacyFlowLogs += [pscustomobject]@{
                    Subscription        = $sub.Name
                    Name                = $flowLog.Name
                    Location            = $flowLog.Location
                    NetworkSecurityGroup = Get-ResourceNameFromId -Id $targetId
                    StorageAccount      = $storageAccount
                    State               = $state
                }
                if ($state -eq 'enabled') {
                    $enabledLegacyNsgIds += $targetId
                }
            }

            foreach ($vnet in $vnets) {
                if (Test-IdInList -Id $vnet.Id -List $enabledVnetIds) {
                    $coveredVnetIds += $vnet.Id
                    continue
                }
                $legacyCovered = $false
                foreach ($subnet in @($vnet.Subnets)) {
                    $nsgId = $null
                    if ($subnet.NetworkSecurityGroup) {
                        $nsgId = $subnet.NetworkSecurityGroup.Id
                    }
                    if (Test-IdInList -Id $nsgId -List $enabledLegacyNsgIds) {
                        $legacyCovered = $true
                    }
                }
                if ($legacyCovered) {
                    continue
                }
                $uncoveredVnets += [pscustomobject]@{
                    Subscription      = $sub.Name
                    Name              = $vnet.Name
                    ResourceGroupName = $vnet.ResourceGroupName
                    Location          = $vnet.Location
                }
            }
        }

        $coveredCount = @($coveredVnetIds | Sort-Object -Unique).Count

        Write-Host ""
        Write-Host "=== Azure Flow Log Migration Status ===" -ForegroundColor Cyan
        Write-Host "Subscriptions audited: $($subscriptions.Count)" -ForegroundColor White
        Write-Host "VNets covered by enabled virtual network flow logs: $coveredCount" -ForegroundColor White
        Write-Host "Virtual network flow log resources: $($vnetFlowLogs.Count)" -ForegroundColor White
        Write-Host "Legacy NSG flow log resources: $($legacyFlowLogs.Count)" -ForegroundColor White
        Write-Host "VNets with no flow logging: $($uncoveredVnets.Count)" -ForegroundColor White

        if ($legacyFlowLogs.Count -gt 0) {
            Write-Host "[!] $($legacyFlowLogs.Count) legacy NSG flow log(s) still present." `
                -ForegroundColor Yellow
        }

        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

        switch ($OutputFormat) {
            'Table' {
                foreach ($entry in $vnetFlowLogs) {
                    $prefix = '[+]'
                    $color = 'Green'
                    if ($entry.State -eq 'disabled') {
                        $prefix = '[!]'
                        $color = 'Yellow'
                    }
                    $message = "  $prefix VNet flow log '$($entry.Name)' covers VNet '$($entry.VNet)'"
                    $message += " ($($entry.State))"
                    Write-Host $message -ForegroundColor $color
                }
                foreach ($entry in $legacyFlowLogs) {
                    $message = "  [!] Legacy NSG flow log '$($entry.Name)' on NSG"
                    $message += " '$($entry.NetworkSecurityGroup)' -> storage account"
                    $message += " '$($entry.StorageAccount)' ($($entry.State))"
                    Write-Host $message -ForegroundColor Yellow
                }
                foreach ($vnet in $uncoveredVnets) {
                    $message = "  [!] No flow logging: $($vnet.ResourceGroupName)/$($vnet.Name)"
                    $message += " ($($vnet.Location))"
                    Write-Host $message -ForegroundColor Yellow
                }
                if ($vnetFlowLogs.Count -eq 0) {
                    Write-Host "[!] No virtual network flow logs found." -ForegroundColor Yellow
                }
            }
            'Json' {
                $report = [pscustomobject]@{
                    GeneratedAt   = (Get-Date).ToString('s')
                    RetiresOn     = '2027-09-30'
                    Subscriptions = @($subscriptions | ForEach-Object { $_.Name })
                    VNetFlowLogs  = @($vnetFlowLogs)
                    LegacyFlowLogs = @($legacyFlowLogs)
                    UncoveredVNets = @($uncoveredVnets)
                }
                $json = ConvertTo-Json -InputObject $report -Depth 5
                if ($OutputPath) {
                    $jsonFile = Join-Path $OutputPath "Azure-FlowLogMigration_$stamp.json"
                    Set-Content -LiteralPath $jsonFile -Value $json -Encoding utf8
                    Write-Host "[+] JSON report written: $jsonFile" -ForegroundColor Green
                }
                else {
                    Write-Host $json
                }
            }
            'Csv' {
                if ($OutputPath) {
                    $csvFile = Join-Path $OutputPath "Azure-FlowLogMigration_$stamp.csv"
                    $rows = @()
                    foreach ($entry in $uncoveredVnets) {
                        $rows += [pscustomobject]@{
                            State        = 'NoFlowLogging'
                            Resource     = $entry.Name
                            Detail       = $entry.ResourceGroupName
                            StorageAccount = ''
                        }
                    }
                    foreach ($entry in $legacyFlowLogs) {
                        $rows += [pscustomobject]@{
                            State        = 'LegacyNsgFlowLog'
                            Resource     = $entry.NetworkSecurityGroup
                            Detail       = $entry.Name
                            StorageAccount = $entry.StorageAccount
                        }
                    }
                    foreach ($entry in $vnetFlowLogs) {
                        $rows += [pscustomobject]@{
                            State        = 'VNetFlowLog'
                            Resource     = $entry.VNet
                            Detail       = $entry.Name
                            StorageAccount = ''
                        }
                    }
                    if ($rows.Count -eq 0) {
                        Write-Host "[+] No flow log resources to export." -ForegroundColor Green
                    }
                    else {
                        $rows | Export-Csv -LiteralPath $csvFile -NoTypeInformation -Encoding utf8
                        Write-Host "[+] CSV report written: $csvFile" -ForegroundColor Green
                    }
                }
                else {
                    Write-Host "[!] -OutputPath is required for CSV output." -ForegroundColor Yellow
                }
            }
        }

        if ($incomplete) {
            Write-Host "[!] Report incomplete: one or more flow log queries failed." -ForegroundColor Yellow
            return 1
        }
        if ($legacyFlowLogs.Count -gt 0 -or $uncoveredVnets.Count -gt 0) {
            Write-Host "[!] Migration incomplete: legacy NSG flow logs or uncovered VNets remain." `
                -ForegroundColor Yellow
            return 2
        }

        Write-Host "[+] Migration complete: every virtual network has enabled flow logging." `
            -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
