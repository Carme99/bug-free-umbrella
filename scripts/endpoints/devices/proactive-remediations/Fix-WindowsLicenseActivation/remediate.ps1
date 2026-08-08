<#
.SYNOPSIS
    Attempts to activate Windows.

.DESCRIPTION
    Tries to reactivate Windows by triggering online activation.
    This works if the device has a valid license key or digital entitlement.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Try to reactivate Windows online
    Write-Host "Attempting to activate Windows online..."
    $activateResult = cscript //nologo C:\Windows\System32\slmgr.vbs /ato 2>&1

    if ($LASTEXITCODE -eq 0) {
        $remediationActions += "Successfully triggered Windows activation"
    }
    else {
        $remediationActions += "Activation attempt completed (may require additional steps)"
    }

    # Refresh license status
    $refreshResult = cscript //nologo C:\Windows\System32\slmgr.vbs /dli 2>&1

    # Try using PowerShell licensing cmdlet as backup
    try {
        $licensingService = Get-WmiObject -Class SoftwareLicensingService -ErrorAction SilentlyContinue
        if ($licensingService) {
            $licensingService.RefreshLicenseStatus() | Out-Null
            $remediationActions += "Refreshed license status"
        }
    }
    catch {
        Write-Host "Note: Could not refresh license status via WMI"
    }

    Write-Host "Windows activation remediation completed:"
    foreach ($action in $remediationActions) {
        Write-Host "  - $action"
    }
    Write-Host ""
    Write-Host "Note: If activation fails, verify:"
    Write-Host "  - Device has internet connectivity"
    Write-Host "  - Valid license key is installed (use slmgr /ipk)"
    Write-Host "  - Device has digital entitlement linked to Microsoft account"

    exit 0

}
catch {
    Write-Host "Error during Windows activation remediation: $_"
    exit 1
}
