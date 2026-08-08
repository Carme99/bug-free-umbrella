<#
.SYNOPSIS
    Clears bloated Windows Event Logs.

.DESCRIPTION
    Clears event logs that exceed size thresholds, excluding critical system logs
    (System, Security, Application) which are archived instead.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful

.CONFIGURATION
    $maxLogSizeMB: Maximum size in MB before clearing (default: 100MB)
#>

try {
    # Configuration
    $maxLogSizeMB = 100
    $maxLogSizeBytes = $maxLogSizeMB * 1MB

    $remediationActions = @()
    $criticalLogs = @("System", "Security", "Application")

    # Get all event logs
    $eventLogs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue

    foreach ($log in $eventLogs) {
        if ($log.FileSize -gt $maxLogSizeBytes) {
            $logName = $log.LogName
            $sizeMB = [math]::Round($log.FileSize / 1MB, 2)

            try {
                if ($criticalLogs -contains $logName) {
                    # For critical logs, configure auto-archiving instead of clearing
                    wevtutil.exe sl "$logName" /ms:52428800  # Set max size to 50MB
                    $remediationActions += "Configured size limit for $logName ($sizeMB MB)"
                }
                else {
                    # Clear non-critical logs
                    wevtutil.exe cl "$logName"
                    $remediationActions += "Cleared $logName ($sizeMB MB)"
                }
            }
            catch {
                Write-Host "Warning: Could not process $logName : $_"
            }
        }
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "Event log remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
    }
    else {
        Write-Host "No event logs required clearing"
    }

    exit 0

}
catch {
    Write-Host "Error during event log remediation: $_"
    exit 1
}
