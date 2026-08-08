<#
.SYNOPSIS
    Remove stale user profiles to free disk space

.DESCRIPTION
    Removes user profiles that haven't been used within the configured threshold
    using the documented mechanism: Get-CimInstance Win32_UserProfile with
    Remove-CimInstance, which invokes DeleteProfileW semantics and removes BOTH
    the profile folder and the ProfileList registry entry. Only unloaded
    profiles (Loaded -eq $false) are ever removed. Uses a more conservative
    threshold than detection to avoid accidental removal of active profiles.

.NOTES
    For Intune Proactive Remediations
    Exit 0 = Remediation completed successfully

    Default Threshold: 120 days since last use (more conservative than detect)
    Loaded profiles are NEVER removed (DeleteProfileW fails on loaded profiles
    and deleting their folder would corrupt the session).

    WARNING: This permanently deletes user profile data. Ensure proper backups
    exist and threshold is set appropriately for your environment.
#>

[CmdletBinding()]
param()

# Configuration
$PROFILE_REMOVAL_AGE_DAYS = 120  # More conservative than detection threshold

$removed = @()

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
        $age = ((Get-Date) - $lastUse).Days
    }
    catch {
        # Unparseable LastUseTime - skip this profile
        continue
    }

    if ($age -gt $PROFILE_REMOVAL_AGE_DAYS) {
        try {
            $profileName = Split-Path $profile.LocalPath -Leaf
            $sizeBefore = [math]::Round((Get-ChildItem $profile.LocalPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB, 2)

            # Documented mechanism: Remove-CimInstance on Win32_UserProfile calls
            # DeleteProfileW, which removes the profile folder AND its
            # ProfileList registry key (plain Remove-Item would orphan the
            # registry entry and can delete loaded profiles).
            Remove-CimInstance -InputObject $profile -ErrorAction Stop
            $removed += "$profileName ($sizeBefore GB)"
        }
        catch {
            Write-Host "Could not remove $profileName : $($_.Exception.Message)"
        }
    }
}

if ($removed.Count -gt 0) {
    Write-Host "Removed $($removed.Count) stale profile(s): $($removed -join '; ')"
}
else {
    Write-Host "No profiles removed"
}
exit 0
