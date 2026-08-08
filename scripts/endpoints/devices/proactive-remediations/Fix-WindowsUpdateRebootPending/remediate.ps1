<#
.SYNOPSIS
    Schedules a restart to clear a stuck Windows Update reboot-pending state.

.DESCRIPTION
    The RebootPending/RebootRequired registry flags are authoritative signals of
    genuine pending servicing operations (Windows Update restart, CBS servicing,
    file rename operations). MS Learn documents a reboot as the ONLY resolution
    for these flags - deleting the keys can strand servicing operations
    mid-flight and the state reappears anyway. This remediation therefore
    schedules a restart (15 minutes out, so the user can save work) instead of
    deleting the keys. Windows clears the flags itself during the restart.

.NOTES
    Author: Intune Admin
    Version: 1.1
    Intune Context: SYSTEM
    Exit 0: Restart scheduled (or no pending state present)
    Exit 1: Failed to schedule restart
#>

try {
    $rebootPending = $false

    # Component-Based Servicing reboot pending
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $rebootPending = $true
    }

    # Windows Update reboot required
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        $rebootPending = $true
    }

    if (-not $rebootPending) {
        Write-Host "No reboot pending flags present - nothing to remediate"
        exit 0
    }

    # Schedule a restart 15 minutes out so the user can save work. The registry
    # flags are intentionally left intact - they are cleared by Windows during
    # the restart (deleting them is the bug this script previously had).
    shutdown.exe /r /t 900 /c "Windows Update requires a restart to finish installing updates. This device will restart in 15 minutes. Please save your work."

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Reboot pending state detected. Scheduled a restart in 15 minutes (shutdown /r /t 900)."
        Write-Host "Note: The RebootPending/RebootRequired registry keys were left intact - they are cleared by Windows during the restart. Deleting them would strand servicing operations."
        exit 0
    } else {
        Write-Host "Failed to schedule restart: shutdown.exe exited with code $LASTEXITCODE"
        exit 1
    }

} catch {
    Write-Host "Error during reboot pending remediation: $_"
    exit 1
}
