<#
.SYNOPSIS
    Detect stale user profiles not used recently

.DESCRIPTION
    Scans user profiles via Win32_UserProfile for profiles whose documented
    LastUseTime is older than the configured threshold. Excludes system profiles
    (Public, Default, systemprofile, defaultuser). Reports profile age and size
    for stale profiles.

.NOTES
    For Intune Proactive Remediations
    Exit 0 = Compliant (no stale profiles)
    Exit 1 = Non-compliant (stale profiles found)

    Default Threshold: 90 days since last use
    Loaded profiles are excluded - they are in use and must never be flagged.

    Uses Win32_UserProfile.LastUseTime instead of filesystem LastAccessTime
    (NTFS last-access updates are frequently disabled, making the filesystem
    property unreliable).
#>

[CmdletBinding()]
param()

# Configuration
$STALE_PROFILE_AGE_DAYS = 90  # Consider profiles stale after this many days

$staleProfiles = @()

$profiles = Get-CimInstance Win32_UserProfile | Where-Object {
    $_.Special -eq $false -and
    $_.LocalPath -and
    $_.LocalPath -notmatch 'systemprofile|defaultuser' -and
    $_.Loaded -eq $false -and
    $_.LastUseTime
}

foreach ($profile in $profiles) {
    try {
        $lastUse = [Management.ManagementDateTimeConverter]::ToDateTime($profile.LastUseTime)
    }
    catch {
        # Unparseable LastUseTime - skip this profile
        continue
    }
    $age = ((Get-Date) - $lastUse).Days

    if ($age -gt $STALE_PROFILE_AGE_DAYS) {
        $profileName = Split-Path $profile.LocalPath -Leaf
        $sizeGB = [math]::Round((Get-ChildItem $profile.LocalPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
        $staleProfiles += "$profileName ($age days old, $sizeGB GB)"
    }
}

if ($staleProfiles.Count -gt 0) {
    Write-Host "Found $($staleProfiles.Count) stale profiles: $($staleProfiles -join '; ')"
    exit 1
}

Write-Host "No stale profiles found"
exit 0
