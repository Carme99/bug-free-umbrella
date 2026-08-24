<#
.SYNOPSIS
    Delete user profiles unused beyond the retention threshold.

.DESCRIPTION
    Removes local user profiles whose LastUseTime is older than 120 days using
    the documented mechanism Get-CimInstance Win32_UserProfile plus
    Remove-CimInstance, which invokes DeleteProfileW semantics and removes BOTH
    the profile folder and its ProfileList registry entry (plain Remove-Item
    would orphan the registry entry).
    Side effects: stale profile folders and their registry entries are
    permanently deleted. Only unloaded profiles (Loaded -eq $false) are ever
    removed - loaded profiles are skipped because DeleteProfileW fails on them
    and deleting their folder would corrupt an active session. Every deletion
    is gated behind -WhatIf/-Confirm via SupportsShouldProcess.
    WARNING: this permanently deletes user data; ensure backups exist and the
    threshold fits the environment. Re-running on a converged system removes
    nothing and still exits 0 (idempotent).
    Exit codes: 0 = remediation successful (or nothing to remove), 1 = profile
    enumeration failed.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixStaleProfiles.ps1

    Deletes every unloaded profile unused for more than 120 days.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixStaleProfiles.ps1 -WhatIf

    Shows which stale profiles would be deleted without deleting anything.

.NOTES
    File Name  : Invoke-RemediationFixStaleProfiles.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function ConvertFrom-DmtfDateTime {
    # Converts a WMI/DMTF datetime string (yyyyMMddHHmmss.ffffff[+-]zzz) to DateTime.
    # Parses the local-time portion only - the timezone offset is irrelevant for
    # computing profile age in whole days.
    param([string]$DmtfValue)

    return [DateTime]::ParseExact(
        $DmtfValue.Substring(0, 14),
        'yyyyMMddHHmmss',
        [Globalization.CultureInfo]::InvariantCulture)
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    # More conservative than the detection threshold to avoid removing active profiles.
    $removalAgeDays = 120

    try {
        Write-Host "[*] Removing user profiles unused for more than $removalAgeDays days..." -ForegroundColor Cyan

        $removed = @()

        $staleProfiles = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop | Where-Object {
            $_.Special -eq $false -and
            $_.LocalPath -and
            $_.LocalPath -notmatch 'systemprofile|defaultuser' -and
            $_.Loaded -eq $false -and
            $_.LastUseTime
        }

        foreach ($userProfile in $staleProfiles) {
            try {
                $lastUse = ConvertFrom-DmtfDateTime -DmtfValue $userProfile.LastUseTime
                $ageDays = ((Get-Date) - $lastUse).Days
            }
            catch {
                # Unparseable LastUseTime - skip this profile rather than guessing its age.
                continue
            }

            if ($ageDays -le $removalAgeDays) {
                continue
            }

            $profileName = Split-Path $userProfile.LocalPath -Leaf

            # Documented mechanism: Remove-CimInstance on Win32_UserProfile calls
            # DeleteProfileW, which removes the profile folder AND its ProfileList
            # registry key.
            if ($PSCmdlet.ShouldProcess("$profileName (unused for $ageDays days)", 'Delete stale user profile')) {
                Remove-CimInstance -InputObject $userProfile -ErrorAction Stop
                $removed += $profileName
            }
        }

        if ($removed.Count -gt 0) {
            Write-Host "[+] Removed $($removed.Count) stale profile(s): $($removed -join '; ')" -ForegroundColor Green
        }
        else {
            Write-Host "[+] Already clean: no profiles unused for more than $removalAgeDays days found" -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error removing stale profiles: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
