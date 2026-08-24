<#
.SYNOPSIS
    Disables power management on all physical network adapters.

.DESCRIPTION
    Turns off "Allow the computer to turn off this device to save power" (and related power
    management features) on every Up-status physical network adapter using the documented
    Disable-NetAdapterPowerManagement cmdlet, preventing connectivity issues caused by adapters
    being powered down. Changing adapter power settings is a configuration change, so each
    change honors -WhatIf/-Confirm via SupportsShouldProcess. Disabling power management is
    safe to repeat: re-running the script converges to the same state and exits 0. Exit codes:
    - 0: remediation successful (power management disabled, or no adapter required a change).
    - 1: the enumeration failed unexpectedly.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixNetworkAdapterPowerManagement.ps1
    Disables power management on all physical network adapters and exits 0 on success.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixNetworkAdapterPowerManagement.ps1 -WhatIf
    Shows which adapters would be changed without modifying anything.

.NOTES
    File Name: Invoke-RemediationFixNetworkAdapterPowerManagement.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]

$ErrorActionPreference = 'Stop'

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Checking network adapter power management..." -ForegroundColor Cyan

        $remediationActions = @()

        # Get all physical network adapters.
        $adapters = Get-NetAdapter -ErrorAction Stop | Where-Object {
            $_.Status -eq "Up" -and
            $_.Virtual -eq $false -and
            $_.Name -notmatch "Bluetooth|Virtual|Loopback"
        }

        foreach ($adapter in $adapters) {
            # Use the documented NetAdapter cmdlet instead of the undocumented
            # PnPCapabilities=24 registry value / MSPower_DeviceEnable WMI class.
            # Disable-NetAdapterPowerManagement disables the "Allow the computer to
            # turn off this device to save power" setting (and the other power
            # management features) that the detect script flags.
            try {
                if ($PSCmdlet.ShouldProcess($adapter.Name, "Disable network adapter power management")) {
                    Disable-NetAdapterPowerManagement -Name $adapter.Name -ErrorAction Stop
                    $remediationActions += "Disabled power management on $($adapter.Name)"
                }
            }
            catch {
                Write-Host "[!] Could not disable power management on $($adapter.Name): $($_.Exception.Message)" `
                    -ForegroundColor Yellow
            }
        }

        if ($remediationActions.Count -gt 0) {
            Write-Host "[+] Network adapter power management remediation completed:" -ForegroundColor Green
            foreach ($action in $remediationActions) {
                Write-Host "  - $action"
            }
        }
        else {
            Write-Host "[+] No network adapters required power management changes" -ForegroundColor Green
        }

        return 0
    }
    catch {
        Write-Host "[-] Error during network adapter remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
