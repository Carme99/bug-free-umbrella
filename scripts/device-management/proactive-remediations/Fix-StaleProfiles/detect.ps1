<#
.SYNOPSIS
    Detect stale user profiles not accessed recently

.DESCRIPTION
    Scans user profiles in C:\Users for profiles that haven't been accessed
    within the configured threshold. Excludes system profiles (Public, Default).
    Reports profile age and size for stale profiles.

.NOTES
    For Intune Proactive Remediations
    Exit 0 = Compliant (no stale profiles)
    Exit 1 = Non-compliant (stale profiles found)

    Default Threshold: 90 days since last access
    Excluded Profiles: Public, Default, Default User, All Users
#>

[CmdletBinding()]
param()

# Configuration
$STALE_PROFILE_AGE_DAYS = 90  # Consider profiles stale after this many days
$PROFILE_PATH = "C:\Users"

$staleProfiles = @()

$profiles = Get-ChildItem $PROFILE_PATH -Directory -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -notmatch '^(Public|Default|Default User|All Users)$'
}

foreach ($profile in $profiles) {
    $lastAccess = $profile.LastAccessTime
    $age = ((Get-Date) - $lastAccess).Days

    if ($age -gt $STALE_PROFILE_AGE_DAYS) {
        $sizeGB = [math]::Round((Get-ChildItem $profile.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
        $staleProfiles += "$($profile.Name) ($age days old, $sizeGB GB)"
    }
}

if ($staleProfiles.Count -gt 0) {
    Write-Host "Found $($staleProfiles.Count) stale profiles: $($staleProfiles -join '; ')"
    exit 1
}

Write-Host "No stale profiles found"
exit 0
