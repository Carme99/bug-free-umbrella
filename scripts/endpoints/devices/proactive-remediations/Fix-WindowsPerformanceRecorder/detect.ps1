<#
.SYNOPSIS
    Detects stuck Windows Performance Recorder (WPR) or ETW sessions.

.DESCRIPTION
    Checks for orphaned WPR/ETW tracing sessions that can cause high CPU usage
    and performance degradation.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: No stuck sessions
    Exit 1: Stuck sessions detected
#>

try {
    $issues = @()

    # Check for running WPR sessions
    $wprSessions = logman query -ets 2>&1 | Select-String -Pattern "WPR_initiated_"

    if ($wprSessions) {
        $issues += "Active WPR tracing sessions detected (may cause performance issues)"
    }

    # Check for excessive ETW sessions
    $allSessions = logman query -ets 2>&1
    $sessionCount = ($allSessions | Select-String -Pattern "^[A-Za-z]").Count

    if ($sessionCount -gt 50) {
        $issues += "Excessive ETW sessions detected: $sessionCount (threshold: 50)"
    }

    # Check for autologger sessions that may be stuck
    $autoLoggers = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\*" -ErrorAction SilentlyContinue

    $stuckAutoLoggers = $autoLoggers | Where-Object {
        $_.Start -eq 1 -and $_.PSChildName -notmatch "EventLog-System|EventLog-Application"
    }

    if ($stuckAutoLoggers) {
        $issues += "Potentially stuck AutoLogger sessions detected"
    }

    if ($issues.Count -gt 0) {
        Write-Host "Performance recorder issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "No stuck WPR/ETW sessions detected"
    exit 0

} catch {
    Write-Host "Error checking performance recorder status: $_"
    exit 1
}
