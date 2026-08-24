<#
.SYNOPSIS
    Detects bloated Microsoft Edge browser cache directories.

.DESCRIPTION
    Sums the size of the Edge cache locations (Cache, Code Cache, GPUCache) across every user
    profile and flags the device when the combined cache grows beyond the configured threshold,
    which can impact performance and disk space.
    Exit codes:
    - 0: healthy - total Edge cache is within the configured threshold.
    - 1: non-compliant - bloated cache detected, or the check failed.

.NOTES
    File Name: Test-RemediationFixEdgeCacheSize.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Test-RemediationFixEdgeCacheSize.ps1
    Measures the Edge cache across all profiles and returns 0 when healthy, 1 when bloated.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\Test-RemediationFixEdgeCacheSize.ps1
    Runs the same detection under the Intune Management Extension SYSTEM context.
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

#region Configuration
$MaxCacheSizeMb = 500   # Maximum combined cache size in MB before remediation
#endregion

#region Functions

function Main {
    try {
        $outputMsg = "[*] Checking Microsoft Edge cache size..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $maxCacheSizeBytes = $MaxCacheSizeMb * 1MB
        $totalCacheSize = 0

        # Get all user profiles
        $userProfiles = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch "Public|Default|All Users" }

        foreach ($userProfile in $userProfiles) {
            # Edge cache locations
            $edgeCachePaths = @(
                "$($userProfile.FullName)\AppData\Local\Microsoft\Edge\User Data\Default\Cache",
                "$($userProfile.FullName)\AppData\Local\Microsoft\Edge\User Data\Default\Code Cache",
                "$($userProfile.FullName)\AppData\Local\Microsoft\Edge\User Data\Default\GPUCache"
            )

            foreach ($cachePath in $edgeCachePaths) {
                if (Test-Path $cachePath) {
                    $cacheSize = (Get-ChildItem -Path $cachePath -Recurse -File -ErrorAction SilentlyContinue |
                            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum

                    if ($cacheSize) {
                        $totalCacheSize += $cacheSize
                    }
                }
            }
        }

        $totalCacheSizeMb = [math]::Round($totalCacheSize / 1MB, 2)

        if ($totalCacheSize -gt $maxCacheSizeBytes) {
            $outputMsg = "[!] Edge cache is bloated: $totalCacheSizeMb MB (threshold: $MaxCacheSizeMb MB)"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        $outputMsg = "[+] Edge cache size is healthy: $totalCacheSizeMb MB."

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking Edge cache size: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}
#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
