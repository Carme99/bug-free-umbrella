<#
.SYNOPSIS
    Detects Windows license activation issues.

.DESCRIPTION
    Checks if Windows is properly activated and licensed. Unlicensed Windows
    can cause compliance issues and limited functionality.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Windows is activated
    Exit 1: Activation issues detected
#>

try {
    $issues = @()

    # Check Windows activation status using slmgr
    $activationStatus = cscript //nologo C:\Windows\System32\slmgr.vbs /dli 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error checking Windows activation status"
        exit 1
    }

    # Parse activation status
    if ($activationStatus -match "License Status: Licensed") {
        Write-Host "Windows is properly activated and licensed"
        exit 0
    }
    else {
        # Check for specific activation states
        if ($activationStatus -match "License Status: Notification") {
            $issues += "Windows is in notification mode (grace period or unlicensed)"
        }
        elseif ($activationStatus -match "License Status: Unlicensed") {
            $issues += "Windows is unlicensed"
        }
        elseif ($activationStatus -match "License Status: Out-of-tolerance") {
            $issues += "Windows is out of tolerance (requires reactivation)"
        }
        else {
            $issues += "Windows activation status is unknown or problematic"
        }
    }

    # Additional check using WMI
    $licensingStatus = Get-WmiObject -Class SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey <> null" -ErrorAction SilentlyContinue

    if ($licensingStatus) {
        $licenseStatus = $licensingStatus.LicenseStatus
        # 0 = Unlicensed, 1 = Licensed, 2 = OOBGrace, 3 = OOTGrace, 4 = NonGenuineGrace, 5 = Notification, 6 = ExtendedGrace
        if ($licenseStatus -ne 1) {
            $issues += "Windows license status code: $licenseStatus (not fully licensed)"
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host "Windows activation issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "Windows is properly activated"
    exit 0

}
catch {
    Write-Host "Error checking Windows activation: $_"
    exit 1
}
