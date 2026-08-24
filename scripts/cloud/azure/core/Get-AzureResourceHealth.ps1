<#
.SYNOPSIS
    Checks Azure resource health across VMs, storage, and networking.
.DESCRIPTION
    Verifies an active Azure connection (Az.Accounts), optionally switches subscription,
    and inventories virtual machines, storage accounts, virtual networks, and network
    security groups, printing per-service counts plus a summary to the console.
    Individual resource-query failures are reported as warnings without aborting the run;
    a missing Azure connection or module fails with exit code 1. The script is read-only
    and idempotent: re-running it never mutates Azure resources.
.PARAMETER SubscriptionId
    Optional subscription ID to switch context to before querying resources.
.PARAMETER ExportHTML
    Reserved switch for future HTML report export; currently has no effect.
.EXAMPLE
    PS C:\> .\Get-AzureResourceHealth.ps1
    Runs a health check against the currently active Azure subscription.
.EXAMPLE
    PS C:\> .\Get-AzureResourceHealth.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000" -ExportHTML
    Switches to the given subscription and runs the health check there.
.NOTES
    File Name   : Get-AzureResourceHealth.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23


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

$ErrorActionPreference = 'Stop'

# Analyzer warnings accepted: PSAvoidUsingWriteHost (spec section 3 mandates Write-Host prefix output)
# and PSReviewUnusedParameter (script params are consumed by Main via parent scope).

function Main {
    try {
        Write-Host "[*] Checking Azure connection..." -ForegroundColor Cyan
        Import-Module Az.Accounts -ErrorAction Stop
        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            throw "Not connected to Azure. Run: Connect-AzAccount"
        }
        Write-Host "[+] Connected to: $($context.Subscription.Name)" -ForegroundColor Green

        if ($SubscriptionId) {
            Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
            Write-Host "[+] Switched to subscription: $SubscriptionId" -ForegroundColor Green
        }

        Write-Host "[*] Checking VMs..." -ForegroundColor Cyan
        try {
            $vms = @(Get-AzVM -Status -ErrorAction Stop)
            $runningVMs = @($vms | Where-Object { $_.PowerState -eq 'VM running' }).Count
            Write-Host "[+] Found $($vms.Count) VMs ($runningVMs running)" -ForegroundColor Green
        }
        catch {
            Write-Host "[!] Failed to retrieve VMs: $($_.Exception.Message)" -ForegroundColor Yellow
            $vms = @()
            $runningVMs = 0
        }

        Write-Host "[*] Checking storage accounts..." -ForegroundColor Cyan
        try {
            $storage = @(Get-AzStorageAccount -ErrorAction Stop)
            Write-Host "[+] Found $($storage.Count) storage accounts" -ForegroundColor Green
        }
        catch {
            Write-Host "[!] Failed to retrieve storage accounts: $($_.Exception.Message)" -ForegroundColor Yellow
            $storage = @()
        }

        Write-Host "[*] Checking network resources..." -ForegroundColor Cyan
        try {
            $vnets = @(Get-AzVirtualNetwork -ErrorAction Stop)
        }
        catch {
            Write-Host "[!] Failed to retrieve virtual networks: $($_.Exception.Message)" -ForegroundColor Yellow
            $vnets = @()
        }
        try {
            $nsgs = @(Get-AzNetworkSecurityGroup -ErrorAction Stop)
        }
        catch {
            Write-Host "[!] Failed to retrieve NSGs: $($_.Exception.Message)" -ForegroundColor Yellow
            $nsgs = @()
        }
        Write-Host "[+] Found $($vnets.Count) VNets, $($nsgs.Count) NSGs" -ForegroundColor Green

        Write-Host ""
        Write-Host "=== Summary ===" -ForegroundColor Cyan
        Write-Host "Subscription: $($context.Subscription.Name)" -ForegroundColor White
        Write-Host "VMs: $($vms.Count) ($runningVMs running)" -ForegroundColor White
        Write-Host "Storage Accounts: $($storage.Count)" -ForegroundColor White
        Write-Host "Virtual Networks: $($vnets.Count)" -ForegroundColor White
        Write-Host "[+] Health check complete" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
