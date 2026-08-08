<#
.SYNOPSIS
    Azure cloud resource health check.
.DESCRIPTION
    Monitors Azure subscription resources including VMs, storage, and networking.
.EXAMPLE
    .\Get-AzureResourceHealth.ps1 -SubscriptionId "xxx" -ExportHTML
.NOTES
    Requires: Az PowerShell module

    Cost analysis is intentionally not included: the Consumption Usage Details API
    (Az.Consumption/Az.Billing cmdlets) is deprecated. Use the Cost Details API /
    cost exports instead:
    https://learn.microsoft.com/en-us/azure/cost-management-billing/automate/migrate-consumption-usage-details-api
#>
[CmdletBinding()]
param(
    [Parameter()][string]$SubscriptionId,
    [switch]$ExportHTML
)

Write-Host "`n=== Azure Resource Health Check ===" -ForegroundColor Cyan
Write-Host "[*] Checking Azure connection..." -ForegroundColor Cyan

try {
    Import-Module Az.Accounts -ErrorAction Stop
    $context = Get-AzContext
    if (-not $context) {
        throw "Not connected to Azure. Run: Connect-AzAccount"
    }
    Write-Host "[+] Connected to: $($context.Subscription.Name)" -ForegroundColor Green
} catch {
    if ($_.Exception.Message -like "Not connected to Azure*") {
        throw "Not connected to Azure. Run: Connect-AzAccount"
    }
    throw "Az module not installed. Run: Install-Module Az -AllowClobber"
}

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}

Write-Host "[*] Checking VMs..." -ForegroundColor Cyan
try {
    $vms = Get-AzVM -Status -ErrorAction Stop
    $runningVMs = ($vms | Where-Object { $_.PowerState -eq "VM running" }).Count
    Write-Host "[+] Found $($vms.Count) VMs ($runningVMs running)" -ForegroundColor Green
} catch {
    Write-Warning "Failed to retrieve VMs: $($_.Exception.Message)"
    $vms = @()
    $runningVMs = 0
}

Write-Host "[*] Checking storage accounts..." -ForegroundColor Cyan
try {
    $storage = Get-AzStorageAccount -ErrorAction Stop
    Write-Host "[+] Found $($storage.Count) storage accounts" -ForegroundColor Green
} catch {
    Write-Warning "Failed to retrieve storage accounts: $($_.Exception.Message)"
    $storage = @()
}

Write-Host "[*] Checking network resources..." -ForegroundColor Cyan
try {
    $vnets = Get-AzVirtualNetwork -ErrorAction Stop
} catch {
    Write-Warning "Failed to retrieve virtual networks: $($_.Exception.Message)"
    $vnets = @()
}

try {
    $nsgs = Get-AzNetworkSecurityGroup -ErrorAction Stop
} catch {
    Write-Warning "Failed to retrieve network security groups: $($_.Exception.Message)"
    $nsgs = @()
}
Write-Host "[+] Found $($vnets.Count) VNets, $($nsgs.Count) NSGs" -ForegroundColor Green

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Subscription: $($context.Subscription.Name)" -ForegroundColor White
Write-Host "VMs: $($vms.Count) ($runningVMs running)" -ForegroundColor White
Write-Host "Storage Accounts: $($storage.Count)" -ForegroundColor White
Write-Host "Virtual Networks: $($vnets.Count)" -ForegroundColor White

Write-Host "`nHealth check complete!`n" -ForegroundColor Green
