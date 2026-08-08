<#
.SYNOPSIS
    Detects outdated or missing critical drivers.

.DESCRIPTION
    Checks Windows Update for available driver updates and identifies
    devices with driver issues.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: All drivers are up to date
    Exit 1: Driver updates available
#>

try {
    $issues = @()

    # Check for devices with driver problems
    $problemDevices = Get-WmiObject -Class Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object { $_.ConfigManagerErrorCode -ne 0 }

    if ($problemDevices) {
        foreach ($device in $problemDevices) {
            $issues += "Device with driver issue: $($device.Name) (Error code: $($device.ConfigManagerErrorCode))"
        }
    }

    # Check Windows Update for driver updates using COM object
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()

        # Search for driver updates
        Write-Host "Searching for driver updates..."
        $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Driver'")

        if ($searchResult.Updates.Count -gt 0) {
            Write-Host "Driver updates available:"
            foreach ($update in $searchResult.Updates) {
                Write-Host "  - $($update.Title)"
            }
            exit 1
        }
    }
    catch {
        Write-Host "Note: Could not check Windows Update for drivers: $_"
    }

    if ($issues.Count -gt 0) {
        Write-Host "Driver issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "All drivers appear to be up to date"
    exit 0

}
catch {
    Write-Host "Error checking driver status: $_"
    exit 1
}
