<#
.SYNOPSIS
    Detects Task Scheduler corruption or service issues.

.DESCRIPTION
    Checks if Task Scheduler service is running and if the task database
    is accessible and not corrupted.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Task Scheduler is healthy
    Exit 1: Issues detected
#>

try {
    $issues = @()

    # Check Task Scheduler service
    $schedService = Get-Service -Name "Schedule" -ErrorAction SilentlyContinue

    if ($schedService.Status -ne "Running") {
        $issues += "Task Scheduler service is not running"
    }

    # Try to query scheduled tasks
    try {
        $tasks = Get-ScheduledTask -ErrorAction Stop | Select-Object -First 1
    }
    catch {
        $issues += "Unable to query scheduled tasks (database may be corrupted)"
    }

    # Check for Task Scheduler event log errors
    $taskSchedErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'Microsoft-Windows-TaskScheduler/Operational'
        Level = 2  # Error
        StartTime = (Get-Date).AddDays(-7)
    } -MaxEvents 10 -ErrorAction SilentlyContinue

    if ($taskSchedErrors) {
        $criticalErrors = $taskSchedErrors | Where-Object { $_.Id -in @(101, 102, 103) }
        if ($criticalErrors) {
            $issues += "Critical Task Scheduler errors detected in event log"
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host "Task Scheduler issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "Task Scheduler is healthy"
    exit 0

}
catch {
    Write-Host "Error checking Task Scheduler: $_"
    exit 1
}
