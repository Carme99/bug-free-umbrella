<#
.SYNOPSIS
    Detects bloated Microsoft Edge browser cache.

.DESCRIPTION
    Checks if Edge cache directory has grown beyond optimal size thresholds,
    which can impact performance and disk space.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Edge cache is healthy
    Exit 1: Bloated cache detected - remediation needed

.CONFIGURATION
    $maxCacheSizeMB: Maximum cache size in MB (default: 500MB)
#>

try {
    # Configuration
    $maxCacheSizeMB = 500
    $maxCacheSizeBytes = $maxCacheSizeMB * 1MB

    $issues = @()

    # Get all user profiles
    $userProfiles = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch "Public|Default|All Users" }

    $totalCacheSize = 0

    foreach ($profile in $userProfiles) {
        # Edge cache locations
        $edgeCachePaths = @(
            "$($profile.FullName)\AppData\Local\Microsoft\Edge\User Data\Default\Cache",
            "$($profile.FullName)\AppData\Local\Microsoft\Edge\User Data\Default\Code Cache",
            "$($profile.FullName)\AppData\Local\Microsoft\Edge\User Data\Default\GPUCache"
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

    $totalCacheSizeMB = [math]::Round($totalCacheSize / 1MB, 2)

    if ($totalCacheSize -gt $maxCacheSizeBytes) {
        Write-Host "Edge cache is bloated: $totalCacheSizeMB MB (threshold: $maxCacheSizeMB MB)"
        exit 1
    }

    Write-Host "Edge cache size is healthy: $totalCacheSizeMB MB"
    exit 0

} catch {
    Write-Host "Error checking Edge cache size: $_"
    exit 1
}
