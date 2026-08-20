<#
.SYNOPSIS
    Detects network adapters with problematic power management settings.

.DESCRIPTION
    Checks if network adapters have "Allow computer to turn off this device to save power"
    enabled, which can cause connectivity issues and disconnect from Intune.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Power management properly configured
    Exit 1: Issues detected - remediation needed
#>

try {
    $issues = @()
    $problematicAdapters = @()

    # Get all physical network adapters (exclude virtual adapters)
    $adapters = Get-NetAdapter | Where-Object {
        $_.Status -eq "Up" -and
        $_.Virtual -eq $false -and
        $_.Name -notmatch "Bluetooth|Virtual|Loopback"
    }

    foreach ($adapter in $adapters) {
        # Get power management settings
        $powerMgmt = Get-WmiObject -Class MSPower_DeviceEnable -Namespace root\wmi -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceName -like "*$($adapter.InterfaceGuid)*" }

        if ($powerMgmt -and $powerMgmt.Enable -eq $true) {
            $problematicAdapters += $adapter.Name
        }
    }

    if ($problematicAdapters.Count -gt 0) {
        Write-Host "Network adapters with power saving enabled:"
        foreach ($adapterName in $problematicAdapters) {
            Write-Host "  - $adapterName"
        }
        exit 1
    }

    Write-Host "Network adapter power management is properly configured"
    exit 0

}
catch {
    Write-Host "Error checking network adapter power settings: $_"
    exit 1
}
