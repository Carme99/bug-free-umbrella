<#
.SYNOPSIS
    Detects Task Scheduler corruption or service issues for Intune Proactive Remediations.

.DESCRIPTION
    Checks that the Task Scheduler service is running, verifies the task database is
    queryable via Get-ScheduledTask, and inspects the Task Scheduler operational event log
    for recent critical errors (event IDs 101, 102, 103). Read-only: makes no changes.
    Exit codes:
    - 0: Task Scheduler is healthy.
    - 1: issues were detected (service not running, task query failed, critical events) or
      the check itself failed; triggers remediation.
    Re-running against an unchanged system yields the same result (idempotent).

.NOTES
    File Name: Test-RemediationFixTaskSchedulerCorruption.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Test-RemediationFixTaskSchedulerCorruption.ps1
    Runs the checks; exits 0 when Task Scheduler is healthy, 1 on issues.

.EXAMPLE
    PS C:\> .\Test-RemediationFixTaskSchedulerCorruption.ps1; $LASTEXITCODE
    Runs the checks and prints the resulting exit code for pipeline consumption.
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

function Main {
    try {
        $outputMsg = "[*] Checking Task Scheduler health..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $issues = @()

        # Check Task Scheduler service
        $schedService = Get-Service -Name 'Schedule' -ErrorAction SilentlyContinue

        if (-not $schedService -or $schedService.Status -ne 'Running') {
            $issues += "Task Scheduler service is not running"
        }

        # Try to query scheduled tasks (database may be corrupted)
        try {
            Get-ScheduledTask -ErrorAction Stop | Select-Object -First 1 | Out-Null
        }
        catch {
            $issues += "Unable to query scheduled tasks (database may be corrupted)"
        }

        # Check for Task Scheduler event log errors
        $taskSchedErrors = Get-WinEvent -FilterHashtable @{
            LogName   = 'Microsoft-Windows-TaskScheduler/Operational'
            Level     = 2  # Error
            StartTime = (Get-Date).AddDays(-7)
        } -MaxEvents 10 -ErrorAction SilentlyContinue

        if ($taskSchedErrors) {
            $criticalErrors = @($taskSchedErrors | Where-Object { $_.Id -in @(101, 102, 103) })
            if ($criticalErrors.Count -gt 0) {
                $issues += "Critical Task Scheduler errors detected in event log"
            }
        }

        if ($issues.Count -gt 0) {
            $outputMsg = "[!] Task Scheduler issues detected:"
            Write-Host $outputMsg -ForegroundColor Yellow
            foreach ($issue in $issues) {
                $outputMsg = "  - $issue"
                Write-Host $outputMsg -ForegroundColor Yellow
            }
            return 1
        }

        $outputMsg = "[+] Task Scheduler is healthy"

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking Task Scheduler: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
