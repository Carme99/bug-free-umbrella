<#
.SYNOPSIS
    Detect Windows Update stuck for more than 7 days

.DESCRIPTION
    Detects a Windows Update state that has been stuck for more than 7 days:
      - Windows Update service not running/missing
      - Pending updates that have persisted for more than 7 days (tracked via a
        first-seen marker under HKLM\SOFTWARE\BugFreeUmbrella)

    Ordinary pending updates (installed recently, still within the 7-day
    window) do NOT trigger remediation - the full component reset in
    remediate.ps1 only runs for genuinely stuck states.

.NOTES
    For Intune Proactive Remediations
    Exit 0 = Windows Update healthy (or pending state not yet stuck)
    Exit 1 = Non-compliant (stuck Windows Update detected)
#>

# Marker registry location recording when the pending-update state was first seen
$markerPath = "HKLM:\SOFTWARE\BugFreeUmbrella\WUStuckFirstSeen"
$markerName = "FirstSeen"
$STUCK_DAYS = 7

# Detect stuck Windows Update
$wuService = Get-Service wuauserv -ErrorAction SilentlyContinue

if (-not $wuService) {
    Write-Host "Windows Update service not found"
    exit 1
}

if ($wuService.Status -ne 'Running') {
    Write-Host "Windows Update service is $($wuService.Status)"
    exit 1
}

# Check for pending updates
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $searchResult = $updateSearcher.Search("IsInstalled=0")
    $pendingCount = $searchResult.Updates.Count
}
catch {
    Write-Host "Could not query updates: $($_.Exception.Message)"
    exit 1
}

if ($pendingCount -eq 0) {
    # No pending updates - clear the first-seen marker (state is healthy)
    if (Test-Path $markerPath) {
        Remove-Item -Path $markerPath -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Windows Update healthy"
    exit 0
}

# Pending updates exist - check how long the pending state has persisted
$firstSeen = (Get-ItemProperty -Path $markerPath -Name $markerName -ErrorAction SilentlyContinue).$markerName

if (-not $firstSeen) {
    # First observation of the pending state - record the timestamp but do NOT
    # flag yet; remediation only triggers once the state persists > 7 days.
    if (-not (Test-Path $markerPath)) {
        New-Item -Path $markerPath -Force | Out-Null
    }
    Set-ItemProperty -Path $markerPath -Name $markerName -Value (Get-Date).ToString("o") -Force
    Write-Host "Found $pendingCount pending updates (first observation - not yet flagged)"
    exit 0
}

try {
    $firstSeenDate = [DateTime]::Parse($firstSeen)
} catch {
    # Unparseable marker - reset it and re-observe
    Set-ItemProperty -Path $markerPath -Name $markerName -Value (Get-Date).ToString("o") -Force
    Write-Host "Found $pendingCount pending updates (marker reset - not yet flagged)"
    exit 0
}

$pendingDays = ((Get-Date) - $firstSeenDate).Days

if ($pendingDays -gt $STUCK_DAYS) {
    Write-Host "Found $pendingCount pending updates stuck for more than $STUCK_DAYS days (since $firstSeenDate)"
    exit 1
}

Write-Host "Found $pendingCount pending updates (pending for $pendingDays days - not yet stuck)"
exit 0
