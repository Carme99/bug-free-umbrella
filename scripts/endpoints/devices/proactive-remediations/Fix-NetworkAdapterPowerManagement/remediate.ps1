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
        # Disable power management using registry
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}"

        # Find the adapter's registry key
        $adapterKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
        foreach ($key in $adapterKeys) {
            $netCfgInstanceId = (Get-ItemProperty -Path $key.PSPath -Name "NetCfgInstanceId" -ErrorAction SilentlyContinue).NetCfgInstanceId

            if ($netCfgInstanceId -eq $adapter.InterfaceGuid) {
                # Disable power management
                Set-ItemProperty -Path $key.PSPath -Name "PnPCapabilities" -Value 24 -ErrorAction SilentlyContinue
                $remediationActions += "Disabled power management on $($adapter.Name)"
            }
        }

        # Also try using WMI method
        $powerMgmt = Get-WmiObject -Class MSPower_DeviceEnable -Namespace root\wmi -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceName -like "*$($adapter.InterfaceGuid)*" }

        if ($powerMgmt -and $powerMgmt.Enable -eq $true) {
            $powerMgmt.Enable = $false
            $powerMgmt.Put() | Out-Null
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
