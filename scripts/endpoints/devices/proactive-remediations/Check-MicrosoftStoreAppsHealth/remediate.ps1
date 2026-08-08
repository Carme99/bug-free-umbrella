<#
.SYNOPSIS
    Repairs Microsoft Store apps registration issues.

.DESCRIPTION
    Re-registers AppX packages that are in error state and resets
    the Windows Store cache.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Get packages in error state
    $appxPackages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    $errorPackages = $appxPackages | Where-Object { $_.Status -ne "Ok" }

    foreach ($package in $errorPackages) {
        try {
            # Re-register the package
            Add-AppxPackage -DisableDevelopmentMode -Register "$($package.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
            $remediationActions += "Re-registered $($package.Name)"
        }
        catch {
            Write-Host "Warning: Could not re-register $($package.Name): $_"
        }
    }

    # Reset Windows Store cache
    Start-Process "wsreset.exe" -WindowStyle Hidden -ErrorAction SilentlyContinue
    $remediationActions += "Reset Windows Store cache"

    # Re-register Store app if needed
    $storeApp = Get-AppxPackage -Name "Microsoft.WindowsStore" -AllUsers -ErrorAction SilentlyContinue
    if ($storeApp -and $storeApp.Status -ne "Ok") {
        Add-AppxPackage -DisableDevelopmentMode -Register "$($storeApp.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
        $remediationActions += "Re-registered Microsoft Store app"
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "Store apps remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
    }
    else {
        Write-Host "No Store apps required remediation"
    }

    exit 0

}
catch {
    Write-Host "Error during Store apps remediation: $_"
    exit 1
}
