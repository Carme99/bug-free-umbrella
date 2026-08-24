<#
.SYNOPSIS
    Detects Microsoft Teams cache issues for Intune Proactive Remediations.

.DESCRIPTION
    Scans user profiles (preferring loaded profiles, capped at the 20 most recently used on
    multi-user systems) for oversized Teams caches, excessive temporary files, and old log
    files. Read-only: makes no changes.
    Exit codes:
    - 0: the Teams cache is healthy, Teams is not installed/used by any scanned user, no
      eligible user profiles were found, or the check itself failed transiently. The last
      case is deliberate: a transient scan failure must not trigger remediation.
    - 1: cache issues were detected (oversized per-location or total cache, excessive tmp
      files, many stale logs); triggers remediation.

.NOTES
    File Name: Test-RemediationFixTeamsCache.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Test-RemediationFixTeamsCache.ps1
    Scans Teams caches for all eligible users; exits 0 when healthy, 1 on issues.

.EXAMPLE
    PS C:\> .\Test-RemediationFixTeamsCache.ps1; $LASTEXITCODE
    Runs the checks and prints the resulting exit code for pipeline consumption.
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

function Main {
    try {
        $outputMsg = "[*] Checking Microsoft Teams cache..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $cacheIssues = @()
        $totalCacheSize = 0

        # Get user profiles to find Teams cache (works in SYSTEM context)
        # Prefer loaded / active profiles and cap the number of profiles scanned to
        # reduce overhead on multi-user/RDS systems.
        $allUserProfiles = Get-CimInstance Win32_UserProfile | Where-Object {
            $_.Special -eq $false -and $_.LocalPath -notmatch 'systemprofile|defaultuser'
        }

        # Early exit if no eligible profiles found
        if (-not $allUserProfiles -or $allUserProfiles.Count -eq 0) {
            $outputMsg = "[+] No eligible user profiles found"
            Write-Host $outputMsg -ForegroundColor Green
            return 0
        }

        # First, prefer loaded profiles (currently logged on / in use)
        $userProfiles = @($allUserProfiles | Where-Object { $_.Loaded -eq $true })

        # If no loaded profiles were found (e.g., no interactive logons), fall back to all non-special profiles
        if ($userProfiles.Count -eq 0) {
            $userProfiles = @($allUserProfiles)
        }

        # Limit to the most recently used profiles to avoid scanning excessive profiles on RDS/multi-user machines
        $maxProfilesToScan = 20
        if ($userProfiles.Count -gt $maxProfilesToScan) {
            $userProfiles = @($userProfiles |
                    Sort-Object -Property LastUseTime -Descending |
                    Select-Object -First $maxProfilesToScan)
        }

        $teamsFound = $false
        foreach ($userProfile in $userProfiles) {
            $userPath = $userProfile.LocalPath
            $teamsAppData = Join-Path $userPath 'AppData\Roaming\Microsoft\Teams'

            if (Test-Path $teamsAppData) {
                $teamsFound = $true
                $userName = Split-Path $userPath -Leaf

                $outputMsg = "[*] Found Teams for user: $userName"

                Write-Host $outputMsg -ForegroundColor Cyan

                $teamsCacheLocations = @(
                    "$teamsAppData\Application Cache",
                    "$teamsAppData\Cache",
                    "$teamsAppData\GPUCache",
                    "$teamsAppData\IndexedDB",
                    "$teamsAppData\Local Storage",
                    "$teamsAppData\tmp"
                )

                # Calculate cache size for this user
                foreach ($cachePath in $teamsCacheLocations) {
                    if (Test-Path $cachePath) {
                        try {
                            $cacheSize = (Get-ChildItem -Path $cachePath -Recurse -ErrorAction SilentlyContinue |
                                    Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum

                            if ($null -ne $cacheSize) {
                                $totalCacheSize += $cacheSize
                                $cacheSizeMB = [math]::Round($cacheSize / 1MB, 2)
                                if ($cacheSizeMB -gt 500) {
                                                                        $cacheIssues += "Large cache in $userName at `
                                        $(Split-Path $cachePath -Leaf): $cacheSizeMB MB"
                                }
                            }
                        }
                        catch {
                            $outputMsg = "[!] Could not calculate size for $cachePath"
                            Write-Host $outputMsg -ForegroundColor Yellow
                        }
                    }
                }

                # Check for .tmp files that weren't cleaned up
                if (Test-Path "$teamsAppData\tmp") {
                    $tmpFiles = @(Get-ChildItem -Path "$teamsAppData\tmp" -Recurse -ErrorAction SilentlyContinue)
                    if ($tmpFiles.Count -gt 100) {
                        $cacheIssues += "Excessive temporary files in ${userName}: $($tmpFiles.Count)"
                    }
                }

                # Check for old log files
                if (Test-Path "$teamsAppData\logs") {
                    $oldLogs = @(Get-ChildItem -Path "$teamsAppData\logs" -Recurse -ErrorAction SilentlyContinue |
                            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) })

                    if ($oldLogs.Count -gt 50) {
                        $cacheIssues += "Many old log files in ${userName}: $($oldLogs.Count) files older than 30 days"
                    }
                }
            }
        }

        # Check if Teams is installed
        if (-not $teamsFound) {
            $outputMsg = "[+] Microsoft Teams not installed or not used by any user"
            Write-Host $outputMsg -ForegroundColor Green
            return 0
        }

        $totalCacheSizeMB = [math]::Round($totalCacheSize / 1MB, 2)
        $outputMsg = "[*] Total Teams cache size: $totalCacheSizeMB MB"
        Write-Host $outputMsg -ForegroundColor Cyan

        # Check if total cache is too large (> 1 GB suggests it needs clearing)
        if ($totalCacheSizeMB -gt 1024) {
            $cacheIssues += "Total Teams cache is very large: $totalCacheSizeMB MB"
        }

        if ($cacheIssues.Count -gt 0) {
            $outputMsg = "[!] Teams cache issues detected:"
            Write-Host $outputMsg -ForegroundColor Yellow
            foreach ($issue in $cacheIssues) {
                $outputMsg = "  - $issue"
                Write-Host $outputMsg -ForegroundColor Yellow
            }
            return 1
        }

        $outputMsg = "[+] Teams cache is healthy (Size: $totalCacheSizeMB MB)"

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        # Original behavior preserved: a transient failure exits 0 so remediation is not triggered.
        $outputMsg = "[-] Error checking Teams cache: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 0
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
