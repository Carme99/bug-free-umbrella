<#
.SYNOPSIS
    Remove stale user profiles to free disk space

.DESCRIPTION
    Removes user profile directories that haven't been accessed within the
    configured threshold. Uses a more conservative threshold than detection
    to avoid accidental removal of active profiles.

.NOTES
    For Intune Proactive Remediations
    Exit 0 = Remediation completed successfully

    Default Threshold: 120 days since last access (more conservative than detect)
    Excluded Profiles: Public, Default, Default User, All Users

    WARNING: This permanently deletes user profile data. Ensure proper backups
    exist and threshold is set appropriately for your environment.
#>

[CmdletBinding()]
param()

# Configuration
$PROFILE_REMOVAL_AGE_DAYS = 120  # More conservative than detection threshold
$PROFILE_PATH = "C:\Users"

$removed = @()

$profiles = Get-ChildItem $PROFILE_PATH -Directory -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -notmatch '^(Public|Default|Default User|All Users)$'
}

foreach ($profile in $profiles) {
    $age = ((Get-Date) - $profile.LastAccessTime).Days

    if ($age -gt $PROFILE_REMOVAL_AGE_DAYS) {
        try {
            $sizeBefore = [math]::Round((Get-ChildItem $profile.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
            Remove-Item $profile.FullName -Recurse -Force -ErrorAction Stop
            $removed += "$($profile.Name) ($sizeBefore GB)"
        } catch {
            Write-Host "Could not remove $($profile.Name): $($_.Exception.Message)"
        }
    }
}

if ($removed.Count -gt 0) {
    Write-Host "Removed $($removed.Count) stale profile(s): $($removed -join '; ')"
} else {
    Write-Host "No profiles removed"
}
exit 0
