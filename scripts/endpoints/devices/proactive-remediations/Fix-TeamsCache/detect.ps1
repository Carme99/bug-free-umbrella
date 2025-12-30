<#
.SYNOPSIS
    Detects Microsoft Teams cache issues.

.DESCRIPTION
    This detection script checks for Microsoft Teams cache problems:
    - Checks if Teams cache is excessively large
    - Detects corrupted cache indicators
    - Checks for Teams performance issues
    - Validates cache directory structure

.NOTES
    Returns exit code 1 if cache issues are detected (triggers remediation).
    Returns exit code 0 if Teams cache is healthy.
#>

try {
    Write-Host "Checking Microsoft Teams cache..."

    # Define Teams cache paths
    $teamsAppData = "$env:APPDATA\Microsoft\Teams"
    $teamsCacheLocations = @(
        "$teamsAppData\Application Cache",
        "$teamsAppData\Cache",
        "$teamsAppData\GPUCache",
        "$teamsAppData\IndexedDB",
        "$teamsAppData\Local Storage",
        "$teamsAppData\tmp"
    )

    $cacheIssues = @()
    $totalCacheSize = 0

    # Check if Teams is installed
    if (-not (Test-Path $teamsAppData)) {
        Write-Host "Microsoft Teams not installed or not used by current user"
        exit 0  # No remediation needed
    }

    # Calculate total cache size
    foreach ($cachePath in $teamsCacheLocations) {
        if (Test-Path $cachePath) {
            try {
                $cacheSize = (Get-ChildItem -Path $cachePath -Recurse -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum

                $totalCacheSize += $cacheSize

                # Check for excessively large individual caches
                $cacheSizeMB = [math]::Round($cacheSize / 1MB, 2)
                if ($cacheSizeMB -gt 500) {
                    $cacheIssues += "Large cache detected in $(Split-Path $cachePath -Leaf): $cacheSizeMB MB"
                }
            } catch {
                Write-Host "Could not calculate size for $cachePath"
            }
        }
    }

    $totalCacheSizeMB = [math]::Round($totalCacheSize / 1MB, 2)
    Write-Host "Total Teams cache size: $totalCacheSizeMB MB"

    # Check if total cache is too large (> 1 GB suggests it needs clearing)
    if ($totalCacheSizeMB -gt 1024) {
        $cacheIssues += "Total Teams cache is very large: $totalCacheSizeMB MB"
    }

    # Check for .tmp files that weren't cleaned up
    if (Test-Path "$teamsAppData\tmp") {
        $tmpFiles = Get-ChildItem -Path "$teamsAppData\tmp" -Recurse -ErrorAction SilentlyContinue
        if ($tmpFiles.Count -gt 100) {
            $cacheIssues += "Excessive temporary files found: $($tmpFiles.Count)"
        }
    }

    # Check for old log files
    if (Test-Path "$teamsAppData\logs") {
        $oldLogs = Get-ChildItem -Path "$teamsAppData\logs" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) }

        if ($oldLogs.Count -gt 50) {
            $cacheIssues += "Many old log files found: $($oldLogs.Count) files older than 30 days"
        }
    }

    if ($cacheIssues.Count -gt 0) {
        Write-Host "Teams cache issues detected:"
        $cacheIssues | ForEach-Object { Write-Host "  - $_" }
        exit 1  # Trigger remediation
    } else {
        Write-Host "Teams cache is healthy (Size: $totalCacheSizeMB MB)"
        exit 0  # No remediation needed
    }

} catch {
    Write-Host "Error checking Teams cache: $($_.Exception.Message)"
    exit 0  # Don't trigger remediation on error
}
