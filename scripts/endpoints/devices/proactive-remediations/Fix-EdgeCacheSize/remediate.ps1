<#
.SYNOPSIS
    Clears bloated Microsoft Edge browser cache.

.DESCRIPTION
    Clears Edge cache files to free up disk space and improve browser performance.
    Edge must be closed for this to work properly.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Close Edge browser processes
    $edgeProcesses = Get-Process -Name "msedge" -ErrorAction SilentlyContinue
    if ($edgeProcesses) {
        Stop-Process -Name "msedge" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        $remediationActions += "Closed Microsoft Edge browser"
    }

    # Get all user profiles
    $userProfiles = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch "Public|Default|All Users" }

    $totalCleared = 0

    foreach ($profile in $userProfiles) {
        # Edge cache locations
        $edgeCachePaths = @(
            "$($profile.FullName)\AppData\Local\Microsoft\Edge\User Data\Default\Cache",
            "$($profile.FullName)\AppData\Local\Microsoft\Edge\User Data\Default\Code Cache",
            "$($profile.FullName)\AppData\Local\Microsoft\Edge\User Data\Default\GPUCache"
        )

        foreach ($cachePath in $edgeCachePaths) {
            if (Test-Path $cachePath) {
                try {
                    $cacheSize = (Get-ChildItem -Path $cachePath -Recurse -File -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum

                    # Clear cache
                    Remove-Item -Path "$cachePath\*" -Recurse -Force -ErrorAction SilentlyContinue

                    if ($cacheSize) {
                        $totalCleared += $cacheSize
                    }
                } catch {
                    Write-Host "Warning: Could not clear cache at $cachePath : $_"
                }
            }
        }
    }

    $totalClearedMB = [math]::Round($totalCleared / 1MB, 2)

    if ($totalClearedMB -gt 0) {
        $remediationActions += "Cleared $totalClearedMB MB of Edge cache"
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "Edge cache remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
    } else {
        Write-Host "No Edge cache to clear"
    }

    exit 0

} catch {
    Write-Host "Error during Edge cache remediation: $_"
    exit 1
}
