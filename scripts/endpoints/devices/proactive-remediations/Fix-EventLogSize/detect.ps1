<#
.SYNOPSIS
    Detects bloated Windows Event Logs.

.DESCRIPTION
    Checks if event logs are consuming excessive disk space or have grown
    beyond optimal size thresholds.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Event logs are healthy
    Exit 1: Bloated logs detected - remediation needed

.CONFIGURATION
    $maxLogSizeMB: Maximum size in MB before remediation (default: 100MB)
#>

try {
    # Configuration
    $maxLogSizeMB = 100
    $maxLogSizeBytes = $maxLogSizeMB * 1MB

    $bloatedLogs = @()

    # Get all event logs
    $eventLogs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue

    foreach ($log in $eventLogs) {
        if ($log.FileSize -gt $maxLogSizeBytes) {
            $bloatedLogs += [PSCustomObject]@{
                LogName = $log.LogName
                SizeMB = [math]::Round($log.FileSize / 1MB, 2)
            }
        }
    }

    if ($bloatedLogs.Count -gt 0) {
        Write-Host "Bloated event logs detected (over $maxLogSizeMB MB):"
        foreach ($log in $bloatedLogs) {
            Write-Host "  - $($log.LogName): $($log.SizeMB) MB"
        }
        exit 1
    }

    Write-Host "Event log sizes are within normal limits"
    exit 0

} catch {
    Write-Host "Error checking event log sizes: $_"
    exit 1
}
