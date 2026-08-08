<#
.SYNOPSIS
    Checks Windows activation grace period status.

.DESCRIPTION
    Monitors Windows activation status and warns if device is in grace period
    or activation is about to expire.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Activation is valid
    Exit 1: Grace period or expiration warning
#>

try {
    $issues = @()

    # Get licensing information
    $licensingStatus = Get-WmiObject -Class SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey <> null" -ErrorAction SilentlyContinue

    if ($licensingStatus) {
        $licenseStatus = $licensingStatus.LicenseStatus
        $gracePeriodRemaining = $licensingStatus.GracePeriodRemaining

        # License Status: 0=Unlicensed, 1=Licensed, 2=OOBGrace, 3=OOTGrace, 4=NonGenuineGrace, 5=Notification, 6=ExtendedGrace
        switch ($licenseStatus) {
            0 { $issues += "Windows is unlicensed" }
            2 { $issues += "Windows is in Out-of-Box grace period" }
            3 { $issues += "Windows is in Out-of-Tolerance grace period" }
            4 { $issues += "Windows is in non-genuine grace period" }
            5 { $issues += "Windows is in notification mode" }
            6 { $issues += "Windows is in extended grace period" }
        }

        # Check grace period remaining (in minutes)
        if ($gracePeriodRemaining -gt 0) {
            $daysRemaining = [math]::Round($gracePeriodRemaining / 1440, 1)
            if ($daysRemaining -le 30) {
                $issues += "Grace period expires in $daysRemaining days"
            }
        }

        # Check evaluation end date
        if ($licensingStatus.EvaluationEndDate) {
            $evalEndDate = [Management.ManagementDateTimeConverter]::ToDateTime($licensingStatus.EvaluationEndDate)
            $daysUntilExpiry = ($evalEndDate - (Get-Date)).Days

            if ($daysUntilExpiry -le 30 -and $daysUntilExpiry -gt 0) {
                $issues += "Evaluation expires in $daysUntilExpiry days"
            }
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host "Windows activation grace period warnings:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "Windows activation is valid"
    exit 0

}
catch {
    Write-Host "Error checking activation grace period: $_"
    exit 1
}
