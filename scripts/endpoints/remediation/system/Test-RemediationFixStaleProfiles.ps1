<#
.SYNOPSIS
    Detects stale user profiles not used recently for Intune Proactive Remediations.

.DESCRIPTION
    Scans user profiles via Win32_UserProfile for profiles whose LastUseTime is older than
    the configured threshold (default 90 days). Excludes special/system profiles (Public,
    Default, systemprofile, defaultuser) and any loaded profile, because loaded profiles are
    in use and must never be flagged. Reports profile age and size for each stale profile.
    This is a read-only detection script; it makes no changes to the system.
    Uses Win32_UserProfile.LastUseTime instead of filesystem LastAccessTime (NTFS last-access
    updates are frequently disabled, making the filesystem property unreliable).
    Exit codes:
    - 0: compliant - no stale profiles found.
    - 1: non-compliant - stale profiles were found, or the scan itself failed.
    Re-running against an unchanged system yields the same result (idempotent).

.NOTES
    File Name: Test-RemediationFixStaleProfiles.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Test-RemediationFixStaleProfiles.ps1
    Scans local profiles; exits 0 when none are stale, 1 when stale profiles exist.

.EXAMPLE
    PS C:\> .\Test-RemediationFixStaleProfiles.ps1; $LASTEXITCODE
    Runs the scan and prints the resulting exit code for pipeline consumption.
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

# Configuration
$STALE_PROFILE_AGE_DAYS = 90  # Consider profiles stale after this many days

function ConvertFrom-DmtfDateTime {
    <#
    .SYNOPSIS
        Parses a DMTF datetime string (as returned by legacy WMI) into a DateTime.
    .DESCRIPTION
        Accepts an existing [DateTime] unchanged and parses DMTF strings such as
        '20240115083000.000000+000' without depending on System.Management, which is
        unavailable off-Windows. Timezone offsets are applied; sub-second precision is
        ignored (day-granularity age math is unaffected).
    #>
    param([Parameter(Mandatory)][object]$Value)

    if ($Value -is [datetime]) {
        return $Value
    }

    if ($Value -is [string] -and $Value -match '^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:\.(\d+))?([+-]\d{3})?$') {
        $utc = [datetime]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3],
            [int]$Matches[4], [int]$Matches[5], [int]$Matches[6], [System.DateTimeKind]::Utc)
        if ($Matches[8]) {
            # e.g. '+330' -> subtract 330 minutes; '-060' -> add 60 minutes
            $utc = $utc.AddMinutes(-([int]$Matches[8]))
        }
        return $utc
    }

    throw "Unrecognized LastUseTime value: '$Value'"
}

function Main {
    try {
        $outputMsg = "[*] Scanning for user profiles not used in the last $STALE_PROFILE_AGE_DAYS days..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $staleProfiles = @()

        $profiles = Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object {
            $_.Special -eq $false -and
            $_.LocalPath -and
            $_.LocalPath -notmatch 'systemprofile|defaultuser' -and
            $_.Loaded -eq $false -and
            $_.LastUseTime
        }

        foreach ($userProfile in $profiles) {
            try {
                $lastUse = ConvertFrom-DmtfDateTime -Value $userProfile.LastUseTime
            }
            catch {
                # Unparseable LastUseTime - skip this profile
                continue
            }
            $age = ((Get-Date) - $lastUse).Days

            if ($age -gt $STALE_PROFILE_AGE_DAYS) {
                $profileName = Split-Path $userProfile.LocalPath -Leaf
                $sizeGB = [math]::Round((Get-ChildItem $userProfile.LocalPath -Recurse -File `
                    -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum).Sum / 1GB, 2)
                $staleProfiles += "$profileName ($age days old, $sizeGB GB)"
            }
        }

        if ($staleProfiles.Count -gt 0) {
            $outputMsg = "[!] Found $($staleProfiles.Count) stale profiles: $($staleProfiles -join '; ')"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        $outputMsg = "[+] No stale profiles found"

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error scanning user profiles: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
