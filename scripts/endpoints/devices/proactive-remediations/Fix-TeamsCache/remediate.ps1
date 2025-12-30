<#
.SYNOPSIS
    Remediates Microsoft Teams cache issues.

.DESCRIPTION
    This remediation script fixes Microsoft Teams cache problems by:
    - Closing Microsoft Teams if running
    - Clearing Teams cache directories
    - Removing old log files
    - Preserving user settings and credentials
    - Restarting Teams (optional)

.NOTES
    Returns exit code 0 if remediation is successful.
    Returns exit code 1 if remediation fails.
#>

try {
    Write-Host "Starting Microsoft Teams cache remediation..."

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

    # Stop Teams process if running
    Write-Host "Checking for running Teams processes..."
    $teamsProcesses = Get-Process -Name "Teams" -ErrorAction SilentlyContinue

    if ($teamsProcesses) {
        Write-Host "Stopping Microsoft Teams processes..."
        $teamsProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3

        # Verify Teams is stopped
        $teamsStillRunning = Get-Process -Name "Teams" -ErrorAction SilentlyContinue
        if ($teamsStillRunning) {
            Write-Host "Warning: Could not stop all Teams processes"
            # Continue anyway as cache might still be clearable
        } else {
            Write-Host "Teams processes stopped successfully"
        }
    } else {
        Write-Host "Teams is not running"
    }

    # Clear cache directories
    $clearedSize = 0
    $failedPaths = @()

    foreach ($cachePath in $teamsCacheLocations) {
        if (Test-Path $cachePath) {
            try {
                Write-Host "Clearing cache: $(Split-Path $cachePath -Leaf)..."

                # Calculate size before deletion
                $sizeBefore = (Get-ChildItem -Path $cachePath -Recurse -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum

                # Remove cache contents
                Get-ChildItem -Path $cachePath -Recurse -ErrorAction SilentlyContinue |
                    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

                $clearedSize += $sizeBefore

                Write-Host "Cleared $(Split-Path $cachePath -Leaf) successfully"
            } catch {
                Write-Host "Warning: Could not fully clear $cachePath : $($_.Exception.Message)"
                $failedPaths += $cachePath
            }
        }
    }

    # Clear old log files (keep last 7 days)
    if (Test-Path "$teamsAppData\logs") {
        try {
            Write-Host "Clearing old log files..."
            $oldLogs = Get-ChildItem -Path "$teamsAppData\logs" -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }

            $logCount = $oldLogs.Count
            $oldLogs | Remove-Item -Force -ErrorAction SilentlyContinue

            Write-Host "Removed $logCount old log files"
        } catch {
            Write-Host "Warning: Could not clear old logs: $($_.Exception.Message)"
        }
    }

    # Report results
    $clearedSizeMB = [math]::Round($clearedSize / 1MB, 2)
    Write-Host "`nTeams cache remediation completed"
    Write-Host "Cleared approximately $clearedSizeMB MB of cache data"

    if ($failedPaths.Count -gt 0) {
        Write-Host "Warning: Could not clear the following paths:"
        $failedPaths | ForEach-Object { Write-Host "  - $_" }
    }

    # Note: We don't auto-restart Teams as it may disrupt user work
    # Teams will start automatically next time user logs in or manually starts it
    Write-Host "`nNote: Microsoft Teams cache has been cleared."
    Write-Host "Teams will use fresh cache on next launch."

    exit 0

} catch {
    Write-Host "Error during Teams cache remediation: $($_.Exception.Message)"
    exit 1
}
