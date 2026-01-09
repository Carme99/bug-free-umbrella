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
    # NOTE: This check may produce false positives for legitimate active tracing.
    # WPR sessions are typically short-lived (<1 hour). Long-running sessions
    # may indicate orphaned traces consuming CPU/disk resources.
    $wprSessions = logman query -ets 2>&1 | Select-String -Pattern "WPR_initiated_"

    if ($wprSessions) {
        $sessionCount = ($wprSessions | Measure-Object).Count
        # Only flag if multiple WPR sessions (more likely to be orphaned)
        if ($sessionCount -gt 2) {
            $issues += "Multiple active WPR tracing sessions detected: $sessionCount (may indicate orphaned sessions)"
        }
    }

    # Check for excessive ETW sessions (more reliable indicator of issues)
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
