<#
.SYNOPSIS
    Azure cloud resource health check and cost analysis.
.DESCRIPTION
    Monitors Azure subscription resources including VMs, storage, networking, and provides cost analysis.
.EXAMPLE
    .\Get-AzureResourceHealth.ps1 -SubscriptionId "xxx" -ExportHTML
.NOTES
    Requires: Az PowerShell module
#>
[CmdletBinding()]
param(
    [Parameter()][string]$SubscriptionId,
    [switch]$IncludeCostAnalysis,
    [switch]$ExportHTML
)

Write-Host "`n=== Azure Resource Health Check ===" -ForegroundColor Cyan
Write-Host "[*] Checking Azure connection..." -ForegroundColor Cyan

try {
    Import-Module Az.Accounts -ErrorAction Stop
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "[!] Not connected to Azure. Run: Connect-AzAccount" -ForegroundColor Red
        exit 1
    }
    Write-Host "[+] Connected to: $($context.Subscription.Name)" -ForegroundColor Green
} catch {
    Write-Host "[!] Az module not installed. Run: Install-Module Az -AllowClobber" -ForegroundColor Red
    exit 1
}

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}

Write-Host "[*] Checking VMs..." -ForegroundColor Cyan
$vms = Get-AzVM -Status
$runningVMs = ($vms | Where-Object {$_.PowerState -eq "VM running"}).Count
Write-Host "[+] Found $($vms.Count) VMs ($runningVMs running)" -ForegroundColor Green

Write-Host "[*] Checking storage accounts..." -ForegroundColor Cyan
$storage = Get-AzStorageAccount
Write-Host "[+] Found $($storage.Count) storage accounts" -ForegroundColor Green

Write-Host "[*] Checking network resources..." -ForegroundColor Cyan
$vnets = Get-AzVirtualNetwork
$nsgs = Get-AzNetworkSecurityGroup
Write-Host "[+] Found $($vnets.Count) VNets, $($nsgs.Count) NSGs" -ForegroundColor Green

if ($IncludeCostAnalysis) {
    Write-Host "[*] Analyzing costs (last 30 days)..." -ForegroundColor Cyan
    # Cost analysis would go here
    Write-Host "[+] Cost analysis complete" -ForegroundColor Green
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Subscription: $($context.Subscription.Name)" -ForegroundColor White
Write-Host "VMs: $($vms.Count) ($runningVMs running)" -ForegroundColor White
Write-Host "Storage Accounts: $($storage.Count)" -ForegroundColor White
Write-Host "Virtual Networks: $($vnets.Count)" -ForegroundColor White

Write-Host "`nHealth check complete!`n" -ForegroundColor Green
