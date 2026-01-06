<#
.SYNOPSIS
    Clears stuck reboot pending registry keys.

.DESCRIPTION
    Removes false positive reboot pending keys that can block Windows Update.
    CAUTION: Only run after verifying no legitimate reboot is actually needed.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Note: This is conservative - we only clear if system has been up for >7 days
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $lastBoot = $os.ConvertToDateTime($os.LastBootUpTime)
    $daysSinceBoot = ((Get-Date) - $lastBoot).Days

    if ($daysSinceBoot -lt 7) {
        Write-Host "System was rebooted recently ($daysSinceBoot days ago)"
        Write-Host "Not clearing reboot pending flags - a reboot may be legitimately required"
        exit 0
    }

    # Clear Component-Based Servicing reboot pending (if older than 7 days)
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -Force -ErrorAction SilentlyContinue
        $remediationActions += "Cleared Component-Based Servicing reboot pending flag"
    }

    # Clear Windows Update reboot required
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -Force -Recurse -ErrorAction SilentlyContinue
        $remediationActions += "Cleared Windows Update reboot required flag"
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "Reboot pending remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
        Write-Host ""
        Write-Host "Note: Verify that no legitimate updates are pending installation"
    } else {
        Write-Host "No reboot pending flags to clear"
    }

    exit 0

} catch {
    Write-Host "Error during reboot pending remediation: $_"
    exit 1
}
