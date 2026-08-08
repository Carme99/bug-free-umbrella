<#
.SYNOPSIS
    Disables power management on network adapters.

.DESCRIPTION
    Disables "Allow computer to turn off this device to save power" on all
    physical network adapters to prevent connectivity issues.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Get all physical network adapters
    $adapters = Get-NetAdapter | Where-Object {
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
            Disable-NetAdapterPowerManagement -Name $adapter.Name -ErrorAction Stop
            $remediationActions += "Disabled power management on $($adapter.Name)"
        } catch {
            Write-Host "Warning: Could not disable power management on $($adapter.Name): $_"
        }
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "Network adapter power management remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
    } else {
        Write-Host "No network adapters required power management changes"
    }

    exit 0

} catch {
    Write-Host "Error during network adapter remediation: $_"
    exit 1
}
