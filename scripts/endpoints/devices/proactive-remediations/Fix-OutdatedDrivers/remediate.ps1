<#
.SYNOPSIS
    Installs available driver updates.

.DESCRIPTION
    Attempts to install available driver updates from Windows Update.
    May require a restart to complete installation.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Install driver updates using Windows Update COM object
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()

        Write-Host "Searching for driver updates..."
        $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Driver'")

        if ($searchResult.Updates.Count -gt 0) {
            $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl

            foreach ($update in $searchResult.Updates) {
                if ($update.IsDownloaded -eq $false) {
                    Write-Host "Driver update available: $($update.Title)"
                    $updatesToInstall.Add($update) | Out-Null
                }
            }

            if ($updatesToInstall.Count -gt 0) {
                # Download updates
                $downloader = $updateSession.CreateUpdateDownloader()
                $downloader.Updates = $updatesToInstall
                Write-Host "Downloading $($updatesToInstall.Count) driver update(s)..."
                $downloadResult = $downloader.Download()

                # Install updates
                $installer = $updateSession.CreateUpdateInstaller()
                $installer.Updates = $updatesToInstall
                Write-Host "Installing driver updates..."
                $installResult = $installer.Install()

                if ($installResult.ResultCode -eq 2) {
                    $remediationActions += "Successfully installed $($updatesToInstall.Count) driver update(s)"
                }
                else {
                    $remediationActions += "Driver installation completed with result code: $($installResult.ResultCode)"
                }
            }
        }
    }
    catch {
        Write-Host "Error installing driver updates: $_"
        $remediationActions += "Could not install drivers automatically - may require manual intervention"
    }

    # Try to fix devices with driver issues by scanning for hardware changes
    $problemDevices = Get-WmiObject -Class Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object { $_.ConfigManagerErrorCode -ne 0 }

    if ($problemDevices) {
        # Trigger hardware scan
        $devcon = pnputil /scan-devices
        $remediationActions += "Triggered hardware rescan for problem devices"
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "Driver remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
        Write-Host ""
        Write-Host "Note: A restart may be required to complete driver installation"
    }
    else {
        Write-Host "No driver updates were necessary"
    }

    exit 0

}
catch {
    Write-Host "Error during driver remediation: $_"
    exit 1
}
