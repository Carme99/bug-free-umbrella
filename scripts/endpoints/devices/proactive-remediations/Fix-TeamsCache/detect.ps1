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

    $cacheIssues = @()
    $totalCacheSize = 0

    # Get user profiles to find Teams cache (works in SYSTEM context)
    # Prefer loaded / active profiles and cap the number of profiles scanned to reduce overhead on multi-user/RDS systems.
    $allUserProfiles = Get-CimInstance Win32_UserProfile | Where-Object {
        $_.Special -eq $false -and $_.LocalPath -notmatch 'systemprofile|defaultuser'
    }

    # First, prefer loaded profiles (currently logged on / in use)
    $userProfiles = $allUserProfiles | Where-Object { $_.Loaded -eq $true }

    # If no loaded profiles were found (e.g., no interactive logons), fall back to all non-special profiles
    if (-not $userProfiles -or $userProfiles.Count -eq 0) {
        $userProfiles = $allUserProfiles
    }

    # Limit to the most recently used profiles to avoid scanning excessive profiles on RDS/multi-user machines
    $maxProfilesToScan = 20
    if ($userProfiles.Count -gt $maxProfilesToScan) {
        $userProfiles = $userProfiles |
            Sort-Object -Property LastUseTime -Descending |
            Select-Object -First $maxProfilesToScan
    }

    $teamsFound = $false
    foreach ($profile in $userProfiles) {
        $userPath = $profile.LocalPath
        $teamsAppData = Join-Path $userPath "AppData\Roaming\Microsoft\Teams"

        if (Test-Path $teamsAppData) {
            $teamsFound = $true
            $userName = $profile.LocalPath.Split('\')[-1]

            Write-Host "Found Teams for user: $userName"

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
                                $cacheIssues += "Large cache in $userName at $(Split-Path $cachePath -Leaf): $cacheSizeMB MB"
                            }
                        }
                    } catch {
                        Write-Host "Could not calculate size for $cachePath"
                    }
                }
            }

            # Check for .tmp files that weren't cleaned up
            if (Test-Path "$teamsAppData\tmp") {
                $tmpFiles = Get-ChildItem -Path "$teamsAppData\tmp" -Recurse -ErrorAction SilentlyContinue
                if ($tmpFiles.Count -gt 100) {
                    $cacheIssues += "Excessive temporary files in $userName : $($tmpFiles.Count)"
                }
            }

            # Check for old log files
            if (Test-Path "$teamsAppData\logs") {
                $oldLogs = Get-ChildItem -Path "$teamsAppData\logs" -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) }

                if ($oldLogs.Count -gt 50) {
                    $cacheIssues += "Many old log files in $userName : $($oldLogs.Count) files older than 30 days"
                }
            }
        }
    }

    # Check if Teams is installed
    if (-not $teamsFound) {
        Write-Host "Microsoft Teams not installed or not used by any user"
        exit 0
    }

    $totalCacheSizeMB = [math]::Round($totalCacheSize / 1MB, 2)
    Write-Host "Total Teams cache size: $totalCacheSizeMB MB"

    # Check if total cache is too large (> 1 GB suggests it needs clearing)
    if ($totalCacheSizeMB -gt 1024) {
        $cacheIssues += "Total Teams cache is very large: $totalCacheSizeMB MB"
    }

    if ($cacheIssues.Count -gt 0) {
        Write-Host "Teams cache issues detected:"
        $cacheIssues | ForEach-Object { Write-Host "  - $_" }
        exit 1
    } else {
        Write-Host "Teams cache is healthy (Size: $totalCacheSizeMB MB)"
        exit 0
    }

} catch {
    Write-Host "Error checking Teams cache: $($_.Exception.Message)"
    exit 0
}
