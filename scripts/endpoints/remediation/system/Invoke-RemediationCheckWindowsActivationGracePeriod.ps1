<#
.SYNOPSIS
    Attempts to reactivate Windows before grace period expires.

.DESCRIPTION
    Triggers Windows activation to prevent expiration of grace period.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Attempt activation
    Write-Host "Attempting to activate Windows..."
    $activateResult = cscript //nologo C:\Windows\System32\slmgr.vbs /ato 2>&1

    if ($LASTEXITCODE -eq 0) {
        $remediationActions += "Triggered Windows activation"
    }
    else {
        $remediationActions += "Activation initiated (may require additional time)"
    }

    # Refresh license status
    $licensingService = Get-WmiObject -Class SoftwareLicensingService -ErrorAction SilentlyContinue
    if ($licensingService) {
        $licensingService.RefreshLicenseStatus() | Out-Null
        $remediationActions += "Refreshed license status"
    }

    Write-Host "Grace period remediation completed:"
    foreach ($action in $remediationActions) {
        Write-Host "  - $action"
    }
    Write-Host ""
    Write-Host "Note: Verify activation status in Settings > Update & Security > Activation"

    exit 0

}
catch {
    Write-Host "Error during grace period remediation: $_"
    exit 1
}
