<#
.SYNOPSIS
    Detects network adapters with problematic power management settings.
.DESCRIPTION
    Enumerates physical network adapters (virtual, Bluetooth and loopback adapters are excluded)
    and checks whether "Allow the computer to turn off this device to save power" is enabled via
    the MSPower_DeviceEnable WMI class, which can cause connectivity issues and disconnect the
    device from Intune. This is a read-only detection script: it never changes adapter settings,
    so re-running it on a converged system is safe (idempotent).
    Exit codes:
    - 0: compliant - no physical adapter allows power saving, or none are present.
    - 1: non-compliant - one or more adapters have power saving enabled, or the check failed.
.EXAMPLE
    PS C:\> .\Test-RemediationFixNetworkAdapterPowerManagement.ps1
    Lists physical adapters with power saving enabled and exits 1 when any are found.
.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationFixNetworkAdapterPowerManagement.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.
.NOTES
    File Name: Test-RemediationFixNetworkAdapterPowerManagement.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Checking network adapter power management settings..." -ForegroundColor Cyan

        $problematicAdapters = @()

        # Get all physical network adapters (exclude virtual adapters).
        $adapters = Get-NetAdapter -ErrorAction Stop | Where-Object {
            $_.Status -eq 'Up' -and
            $_.Virtual -eq $false -and
            $_.Name -notmatch 'Bluetooth|Virtual|Loopback'
        }

        foreach ($adapter in $adapters) {
            # Tolerated read: a missing MSPower_DeviceEnable instance is not an issue.
            $powerMgmt = Get-WmiObject -Class MSPower_DeviceEnable -Namespace root\wmi -ErrorAction SilentlyContinue |
                Where-Object { $_.InstanceName -like "*$($adapter.InterfaceGuid)*" }

            if ($powerMgmt -and $powerMgmt.Enable -eq $true) {
                $problematicAdapters += $adapter.Name
            }
        }

        if ($problematicAdapters.Count -gt 0) {
            Write-Host "[!] Network adapters with power saving enabled:" -ForegroundColor Yellow
            foreach ($adapterName in $problematicAdapters) {
                Write-Host "[!]   - $adapterName" -ForegroundColor Yellow
            }
            return 1
        }

        Write-Host "[+] Network adapter power management is properly configured" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking network adapter power settings: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
