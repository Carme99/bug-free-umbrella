<#
.SYNOPSIS
    Reset Windows Update components

.DESCRIPTION
    Resets Windows Update components for a genuinely stuck Windows Update state
    (detected by Fix-WindowsUpdateStuck/detect.ps1 after the pending state
    persisted for more than 7 days): stops WU services, renames
    SoftwareDistribution and catroot2, restarts services, and clears the
    first-seen marker so the stuck timer restarts.

.NOTES
    For Intune Proactive Remediations
    Exit 0 = Reset complete
#>

# Clear the first-seen marker used by detect.ps1 - the reset restarts the
# pending-state timer; otherwise a legitimately re-pending update would be
# flagged as stuck again on the very next cycle.
$markerPath = "HKLM:\SOFTWARE\BugFreeUmbrella\WUStuckFirstSeen"
if (Test-Path $markerPath) {
    Remove-Item -Path $markerPath -Force -ErrorAction SilentlyContinue
}

# Reset Windows Update components
Write-Host "Resetting Windows Update..."

# Stop services
Stop-Service wuauserv, cryptSvc, bits, msiserver -Force -ErrorAction SilentlyContinue

# Clear Windows Update cache
$wuCache = "$env:SystemRoot\SoftwareDistribution"
if (Test-Path $wuCache) {
    Rename-Item $wuCache "$wuCache.old" -Force -ErrorAction SilentlyContinue
}

$catroot = "$env:SystemRoot\System32\catroot2"
if (Test-Path $catroot) {
    Rename-Item $catroot "$catroot.old" -Force -ErrorAction SilentlyContinue
}

# Restart services
Start-Service wuauserv, cryptSvc, bits, msiserver -ErrorAction SilentlyContinue

Write-Host "Windows Update reset complete"
exit 0
