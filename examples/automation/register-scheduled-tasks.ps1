<#
.SYNOPSIS
    Register automated monitoring tasks in Windows Task Scheduler

.DESCRIPTION
    This script registers various automated monitoring and reporting tasks in Windows Task Scheduler.
    Includes tasks for daily reporting, weekly health checks, monthly compliance audits, and
    real-time alerting.

    All tasks run under SYSTEM account with highest privileges for full access to system resources.

.NOTES
    Copyright (c) 2025 bug-free-umbrella contributors
    Licensed under Apache License 2.0
    https://github.com/Carme99/bug-free-umbrella

    PREREQUISITES:
    - Run this script with Administrator privileges
    - Ensure all script paths are correct for your environment
    - Update email addresses and SMTP server settings
    - Verify service accounts have required permissions

.EXAMPLE
    .\register-scheduled-tasks.ps1

.EXAMPLE
    .\register-scheduled-tasks.ps1 -ScriptBasePath "D:\Scripts" -EmailTo "it-ops@company.com"

.EXAMPLE
    .\register-scheduled-tasks.ps1 -TaskPrefix "ACME-IT" -RemoveExisting
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ScriptBasePath = "C:\Scripts\bug-free-umbrella",

    [Parameter(Mandatory = $false)]
    [string]$EmailTo = "it-team@company.com",

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer = "smtp.company.com",

    [Parameter(Mandatory = $false)]
    [string]$TaskPrefix = "BFU",

    [Parameter(Mandatory = $false)]
    [switch]$RemoveExisting
)

# Requires Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

Write-Host "=== AUTOMATED TASK SCHEDULER REGISTRATION ===" -ForegroundColor Cyan
Write-Host "Base Path: $ScriptBasePath" -ForegroundColor Yellow
Write-Host "Task Prefix: $TaskPrefix" -ForegroundColor Yellow
Write-Host ""

$TasksCreated = 0
$TasksFailed = 0

# Function to create or update scheduled task
function Register-AutomatedTask {
    param(
        [string]$TaskName,
        [string]$Description,
        [string]$ScriptPath,
        [string]$Arguments,
        [object]$Trigger,
        [string]$RunLevel = "Highest"
    )

    $FullTaskName = "$TaskPrefix - $TaskName"

    try {
        # Check if task exists and remove if requested
        $ExistingTask = Get-ScheduledTask -TaskName $FullTaskName -ErrorAction SilentlyContinue
        if ($ExistingTask -and $RemoveExisting) {
            Write-Host "  Removing existing task: $FullTaskName" -ForegroundColor Yellow
            Unregister-ScheduledTask -TaskName $FullTaskName -Confirm:$false
        }

        # Create task action
        $Action = New-ScheduledTaskAction `
            -Execute "PowerShell.exe" `
            -Argument "-ExecutionPolicy Bypass -NonInteractive -NoProfile -WindowStyle Hidden -File `"$ScriptPath`" $Arguments"

        # Create task principal (SYSTEM account with highest privileges)
        $Principal = New-ScheduledTaskPrincipal `
            -UserId "SYSTEM" `
            -LogonType ServiceAccount `
            -RunLevel $RunLevel

        # Create task settings
        $Settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RunOnlyIfNetworkAvailable `
            -MultipleInstances IgnoreNew

        # Register task
        Register-ScheduledTask `
            -TaskName $FullTaskName `
            -Description $Description `
            -Action $Action `
            -Trigger $Trigger `
            -Principal $Principal `
            -Settings $Settings `
            -Force | Out-Null

        Write-Host "  ✓ Created: $FullTaskName" -ForegroundColor Green
        return $true
    } catch {
        Write-Warning "  ✗ Failed to create $FullTaskName : $_"
        return $false
    }
}

Write-Host "[1/7] Creating Daily Reporting Task..." -ForegroundColor Cyan
$DailyTrigger = New-ScheduledTaskTrigger -Daily -At 8:00AM
$Result = Register-AutomatedTask `
    -TaskName "Daily IT Report" `
    -Description "Automated daily compliance, security, and health reporting" `
    -ScriptPath "$ScriptBasePath\examples\automation\scheduled-daily-reporting.ps1" `
    -Arguments "-EmailTo `"$EmailTo`" -SMTPServer `"$SMTPServer`"" `
    -Trigger $DailyTrigger
if ($Result) { $TasksCreated++ } else { $TasksFailed++ }

Write-Host "`n[2/7] Creating Weekly Health Check Task..." -ForegroundColor Cyan
$WeeklyTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 7:00AM
$Result = Register-AutomatedTask `
    -TaskName "Weekly Health Check" `
    -Description "Comprehensive weekly server and workstation health check" `
    -ScriptPath "$ScriptBasePath\examples\maintenance\weekly-health-check.ps1" `
    -Arguments "-EmailReport -SMTPServer `"$SMTPServer`" -To `"$EmailTo`"" `
    -Trigger $WeeklyTrigger
if ($Result) { $TasksCreated++ } else { $TasksFailed++ }

Write-Host "`n[3/7] Creating Monthly Compliance Audit Task..." -ForegroundColor Cyan
# Monthly on the 1st at 6:00 AM
$MonthlyTrigger = New-ScheduledTaskTrigger -Daily -At 6:00AM
# Modify trigger to run monthly
$MonthlyTrigger.Repetition.Interval = "P1M"  # Every 1 month
$Result = Register-AutomatedTask `
    -TaskName "Monthly Compliance Audit" `
    -Description "Monthly comprehensive compliance audit across all frameworks" `
    -ScriptPath "$ScriptBasePath\examples\compliance\monthly-compliance-audit.ps1" `
    -Arguments "-EmailReport -SMTPServer `"$SMTPServer`" -To `"$EmailTo`"" `
    -Trigger $MonthlyTrigger
if ($Result) { $TasksCreated++ } else { $TasksFailed++ }

Write-Host "`n[4/7] Creating Certificate Expiration Monitor Task..." -ForegroundColor Cyan
$CertTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Wednesday -At 9:00AM
$Result = Register-AutomatedTask `
    -TaskName "Certificate Expiration Monitor" `
    -Description "Weekly certificate expiration monitoring (30 day warning)" `
    -ScriptPath "$ScriptBasePath\scripts\security\compliance\frameworks\Get-ExpiredCertificates.ps1" `
    -Arguments "-DaysBeforeExpiration 30 -ExportToCSV -EmailAlert -SMTPServer `"$SMTPServer`" -To `"$EmailTo`"" `
    -Trigger $CertTrigger
if ($Result) { $TasksCreated++ } else { $TasksFailed++ }

Write-Host "`n[5/7] Creating Stale Device Cleanup Monitor..." -ForegroundColor Cyan
$StaleTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Friday -At 10:00AM
$Result = Register-AutomatedTask `
    -TaskName "Stale Device Cleanup Monitor" `
    -Description "Weekly identification of stale/inactive devices (90+ days)" `
    -ScriptPath "$ScriptBasePath\scripts\endpoints\intune\maintenance\Find-StaleDevices.ps1" `
    -Arguments "-InactiveDays 90 -ExportToCSV -EmailReport -SMTPServer `"$SMTPServer`" -To `"$EmailTo`"" `
    -Trigger $StaleTrigger
if ($Result) { $TasksCreated++ } else { $TasksFailed++ }

Write-Host "`n[6/7] Creating Failed Login Monitor Task..." -ForegroundColor Cyan
$LoginTrigger = New-ScheduledTaskTrigger -Daily -At 11:00PM
$Result = Register-AutomatedTask `
    -TaskName "Failed Login Monitor" `
    -Description "Daily failed login attempt monitoring and alerting" `
    -ScriptPath "$ScriptBasePath\scripts\security\compliance\frameworks\Get-FailedLoginReport.ps1" `
    -Arguments "-Hours 24 -ExportHTML -EmailAlert -SMTPServer `"$SMTPServer`" -To `"$EmailTo`"" `
    -Trigger $LoginTrigger
if ($Result) { $TasksCreated++ } else { $TasksFailed++ }

Write-Host "`n[7/7] Creating Intune Sync Monitor Task..." -ForegroundColor Cyan
# Every 4 hours
$SyncTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Hours 4) -RepetitionDuration ([TimeSpan]::MaxValue)
$Result = Register-AutomatedTask `
    -TaskName "Intune Connectivity Monitor" `
    -Description "Monitor Intune connectivity every 4 hours" `
    -ScriptPath "$ScriptBasePath\scripts\endpoints\intune\maintenance\Test-IntuneConnectivity.ps1" `
    -Arguments "-Verbose -EmailOnFailure -SMTPServer `"$SMTPServer`" -To `"$EmailTo`"" `
    -Trigger $SyncTrigger
if ($Result) { $TasksCreated++ } else { $TasksFailed++ }

# Summary
Write-Host "`n=== TASK REGISTRATION COMPLETE ===" -ForegroundColor Cyan
Write-Host "Tasks Created: $TasksCreated" -ForegroundColor Green
Write-Host "Tasks Failed: $TasksFailed" -ForegroundColor $(if ($TasksFailed -gt 0) { "Red" } else { "Green" })

Write-Host "`n📋 Registered Tasks:" -ForegroundColor Yellow
try {
    Get-ScheduledTask -TaskPath "\" | Where-Object { $_.TaskName -like "$TaskPrefix -*" } | ForEach-Object {
        $NextRun = (Get-ScheduledTaskInfo -TaskName $_.TaskName).NextRunTime
        Write-Host "  • $($_.TaskName) - Next Run: $NextRun" -ForegroundColor Gray
    }
} catch {
    Write-Warning "Could not retrieve task list: $_"
}

Write-Host "`n💡 Management Commands:" -ForegroundColor Yellow
Write-Host "  View all tasks:    Get-ScheduledTask | Where-Object { `$_.TaskName -like '$TaskPrefix -*' }" -ForegroundColor Gray
Write-Host "  Run task now:      Start-ScheduledTask -TaskName '$TaskPrefix - Daily IT Report'" -ForegroundColor Gray
Write-Host "  Disable task:      Disable-ScheduledTask -TaskName '$TaskPrefix - Daily IT Report'" -ForegroundColor Gray
Write-Host "  Remove all tasks:  Get-ScheduledTask | Where-Object { `$_.TaskName -like '$TaskPrefix -*' } | Unregister-ScheduledTask -Confirm:`$false" -ForegroundColor Gray

Write-Host "`n⚠ Important Notes:" -ForegroundColor Yellow
Write-Host "  1. Verify all script paths exist and are accessible" -ForegroundColor Gray
Write-Host "  2. Test email delivery by running one task manually" -ForegroundColor Gray
Write-Host "  3. Monitor task history in Task Scheduler for the first week" -ForegroundColor Gray
Write-Host "  4. Adjust schedules based on your organization's needs" -ForegroundColor Gray
Write-Host "  5. Ensure required PowerShell modules are installed for all tasks" -ForegroundColor Gray

Write-Host "`n✓ Automated monitoring is now configured!" -ForegroundColor Green
