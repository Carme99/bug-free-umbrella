<#
.SYNOPSIS
    Stops stuck Windows Performance Recorder sessions.

.DESCRIPTION
    Terminates orphaned WPR/ETW tracing sessions to restore system performance.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Stop all WPR sessions
    $wprSessions = logman query -ets 2>&1 | Select-String -Pattern "WPR_initiated_"

    foreach ($session in $wprSessions) {
        $sessionName = $session.Line.Trim()
        try {
            logman stop $sessionName -ets | Out-Null
            $remediationActions += "Stopped WPR session: $sessionName"
        }
        catch {
            Write-Host "Warning: Could not stop session $sessionName : $_"
        }
    }

    # Stop WPR if running
    $wprProcess = Get-Process -Name "wpr" -ErrorAction SilentlyContinue
    if ($wprProcess) {
        Stop-Process -Name "wpr" -Force -ErrorAction SilentlyContinue
        $remediationActions += "Stopped WPR process"
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "Performance recorder remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
    }
    else {
        Write-Host "No stuck performance recorder sessions to stop"
    }

    exit 0

}
catch {
    Write-Host "Error during performance recorder remediation: $_"
    exit 1
}
