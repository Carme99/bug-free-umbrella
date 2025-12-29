<#
.SYNOPSIS
    Creates a scheduled task to reboot Windows Server on a weekly basis.

.DESCRIPTION
    This script creates a comprehensive weekly reboot schedule for Windows Server by:
    - Interactively prompting for day of week selection
    - Accepting time input in 24-hour format
    - Creating a scheduled task under the SYSTEM account
    - Configuring the task with appropriate security settings
    - Validating all inputs before task creation
    - Providing detailed logging and error handling

    The scheduled task will execute a system reboot at the specified day and time.
    The task runs under the NT AUTHORITY\SYSTEM account with highest privileges.

.PARAMETER DayOfWeek
    Optional. The day of the week for the reboot (Monday-Sunday).
    If not provided, the script will prompt interactively.

.PARAMETER Time
    Optional. The time for the reboot in 24-hour format (HH:mm).
    If not provided, the script will prompt interactively.

.PARAMETER TaskName
    Optional. Custom name for the scheduled task.
    Default: "Weekly Server Reboot"

.PARAMETER RebootDelay
    Optional. Delay in seconds before the reboot executes (for graceful shutdown).
    Default: 60 seconds

.PARAMETER Force
    Optional. Overwrites existing task with the same name without prompting.

.EXAMPLE
    .\New-WeeklyRebootSchedule.ps1
    Runs interactively, prompting for day and time.

.EXAMPLE
    .\New-WeeklyRebootSchedule.ps1 -DayOfWeek Sunday -Time "03:00"
    Creates a weekly reboot scheduled for Sunday at 3:00 AM.

.EXAMPLE
    .\New-WeeklyRebootSchedule.ps1 -DayOfWeek Saturday -Time "23:30" -RebootDelay 120
    Creates a weekly reboot for Saturday at 11:30 PM with 2-minute delay.

.EXAMPLE
    .\New-WeeklyRebootSchedule.ps1 -DayOfWeek Monday -Time "02:00" -Force
    Creates/replaces the task for Monday at 2:00 AM without confirmation.

.NOTES
    Author: System Administrator
    Requires: Administrator privileges
    Compatible: Windows Server 2016, 2019, 2022
    Version: 1.0
    Last Updated: 2025-12-29
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")]
    [string]$DayOfWeek,

    [Parameter(Mandatory=$false)]
    [ValidatePattern('^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$')]
    [string]$Time,

    [Parameter(Mandatory=$false)]
    [string]$TaskName = "Weekly Server Reboot",

    [Parameter(Mandatory=$false)]
    [ValidateRange(0, 600)]
    [int]$RebootDelay = 60,

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

#Requires -RunAsAdministrator

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    <#
    .SYNOPSIS
        Writes formatted log messages to console with color coding.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Type = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch($Type) {
        "ERROR"   { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        default   { "White" }
    }
    Write-Host "[$timestamp] [$Type] $Message" -ForegroundColor $color
}

function Show-Banner {
    <#
    .SYNOPSIS
        Displays script banner and system information.
    #>
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Weekly Reboot Scheduler for Windows  " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Server: $env:COMPUTERNAME" -ForegroundColor Gray
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Host "OS: $($os.Caption)" -ForegroundColor Gray
    Write-Host "Version: $($os.Version)" -ForegroundColor Gray
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Get-DayOfWeekSelection {
    <#
    .SYNOPSIS
        Prompts user to select day of week.
    #>
    Write-Host "`nPlease select the day of week for the weekly reboot:" -ForegroundColor Yellow
    Write-Host "  1. Monday" -ForegroundColor White
    Write-Host "  2. Tuesday" -ForegroundColor White
    Write-Host "  3. Wednesday" -ForegroundColor White
    Write-Host "  4. Thursday" -ForegroundColor White
    Write-Host "  5. Friday" -ForegroundColor White
    Write-Host "  6. Saturday" -ForegroundColor White
    Write-Host "  7. Sunday" -ForegroundColor White

    do {
        Write-Host "`nEnter selection (1-7): " -NoNewline -ForegroundColor Cyan
        $selection = Read-Host

        switch ($selection) {
            "1" { return "Monday" }
            "2" { return "Tuesday" }
            "3" { return "Wednesday" }
            "4" { return "Thursday" }
            "5" { return "Friday" }
            "6" { return "Saturday" }
            "7" { return "Sunday" }
            default {
                Write-Host "Invalid selection. Please enter a number between 1 and 7." -ForegroundColor Red
            }
        }
    } while ($true)
}

function Get-TimeInput {
    <#
    .SYNOPSIS
        Prompts user to enter time in 24-hour format.
    #>
    Write-Host "`nPlease enter the time for the weekly reboot (24-hour format):" -ForegroundColor Yellow
    Write-Host "  Examples: 02:00, 23:30, 18:45" -ForegroundColor Gray

    do {
        Write-Host "`nEnter time (HH:mm): " -NoNewline -ForegroundColor Cyan
        $timeInput = Read-Host

        # Validate time format
        if ($timeInput -match '^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$') {
            # Normalize to HH:mm format
            $timeParts = $timeInput -split ':'
            $hour = $timeParts[0].PadLeft(2, '0')
            $minute = $timeParts[1]
            return "$hour:$minute"
        } else {
            Write-Host "Invalid time format. Please use 24-hour format (HH:mm), e.g., 02:00 or 23:30" -ForegroundColor Red
        }
    } while ($true)
}

function Test-ScheduledTaskExists {
    <#
    .SYNOPSIS
        Checks if a scheduled task exists.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    try {
        $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
        return ($null -ne $task)
    }
    catch {
        return $false
    }
}

function Remove-ExistingTask {
    <#
    .SYNOPSIS
        Removes an existing scheduled task.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    try {
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop
        Write-Log "Removed existing scheduled task: $Name" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to remove existing task: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function New-RebootScheduledTask {
    <#
    .SYNOPSIS
        Creates the scheduled task for weekly reboots.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TaskName,

        [Parameter(Mandatory=$true)]
        [string]$Day,

        [Parameter(Mandatory=$true)]
        [string]$ScheduledTime,

        [Parameter(Mandatory=$true)]
        [int]$Delay
    )

    try {
        Write-Log "Creating scheduled task configuration..." "INFO"

        # Create task action (shutdown command with delay)
        $actionCmd = "shutdown.exe"
        $actionArgs = "/r /f /t $Delay /c `"Scheduled weekly server reboot - initiated by scheduled task`""
        $action = New-ScheduledTaskAction -Execute $actionCmd -Argument $actionArgs

        # Create trigger (weekly on specified day)
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Day -At $ScheduledTime

        # Create task settings
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RunOnlyIfNetworkAvailable:$false `
            -DontStopOnIdleEnd `
            -RestartCount 3 `
            -RestartInterval (New-TimeSpan -Minutes 1)

        # Create task principal (run as SYSTEM with highest privileges)
        $principal = New-ScheduledTaskPrincipal `
            -UserId "NT AUTHORITY\SYSTEM" `
            -LogonType ServiceAccount `
            -RunLevel Highest

        # Register the scheduled task
        Write-Log "Registering scheduled task..." "INFO"
        $task = Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Description "Automatically reboots the server weekly on $Day at $ScheduledTime. Created by New-WeeklyRebootSchedule.ps1" `
            -ErrorAction Stop

        return $task
    }
    catch {
        Write-Log "Failed to create scheduled task: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Show-TaskSummary {
    <#
    .SYNOPSIS
        Displays a summary of the created scheduled task.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [Microsoft.Management.Infrastructure.CimInstance]$Task,

        [Parameter(Mandatory=$true)]
        [string]$Day,

        [Parameter(Mandatory=$true)]
        [string]$ScheduledTime,

        [Parameter(Mandatory=$true)]
        [int]$Delay
    )

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  Scheduled Task Created Successfully  " -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Task Name:       $($Task.TaskName)" -ForegroundColor White
    Write-Host "Schedule:        Every $Day at $ScheduledTime" -ForegroundColor White
    Write-Host "Reboot Delay:    $Delay seconds" -ForegroundColor White
    Write-Host "Run As:          NT AUTHORITY\SYSTEM" -ForegroundColor White
    Write-Host "State:           $($Task.State)" -ForegroundColor White

    # Calculate next run time
    $taskInfo = Get-ScheduledTaskInfo -TaskName $Task.TaskName
    if ($taskInfo.NextRunTime) {
        Write-Host "Next Run:        $($taskInfo.NextRunTime)" -ForegroundColor Cyan
    }

    Write-Host "========================================`n" -ForegroundColor Green
}

function Get-UserConfirmation {
    <#
    .SYNOPSIS
        Prompts user for confirmation.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message
    )

    Write-Host "`n$Message" -ForegroundColor Yellow
    Write-Host "Continue? (Y/N): " -NoNewline -ForegroundColor Cyan
    $response = Read-Host
    return ($response -eq 'Y' -or $response -eq 'y')
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

# Display banner
Show-Banner

Write-Log "Starting Weekly Reboot Scheduler configuration..." "INFO"

# Get day of week (interactive or parameter)
if ([string]::IsNullOrEmpty($DayOfWeek)) {
    $DayOfWeek = Get-DayOfWeekSelection
    Write-Log "Selected day: $DayOfWeek" "INFO"
} else {
    Write-Log "Using day from parameter: $DayOfWeek" "INFO"
}

# Get time (interactive or parameter)
if ([string]::IsNullOrEmpty($Time)) {
    $Time = Get-TimeInput
    Write-Log "Selected time: $Time" "INFO"
} else {
    Write-Log "Using time from parameter: $Time" "INFO"
}

# Display configuration summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Configuration Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Task Name:     $TaskName" -ForegroundColor White
Write-Host "Day:           $DayOfWeek" -ForegroundColor White
Write-Host "Time:          $Time (24-hour format)" -ForegroundColor White
Write-Host "Reboot Delay:  $RebootDelay seconds" -ForegroundColor White
Write-Host "Run As:        NT AUTHORITY\SYSTEM" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

# Check if task already exists
$taskExists = Test-ScheduledTaskExists -Name $TaskName

if ($taskExists) {
    Write-Log "A scheduled task with the name '$TaskName' already exists." "WARNING"

    if (-not $Force) {
        $confirmOverwrite = Get-UserConfirmation -Message "Do you want to replace the existing task?"
        if (-not $confirmOverwrite) {
            Write-Log "Operation cancelled by user." "INFO"
            exit 0
        }
    } else {
        Write-Log "Force parameter specified - will overwrite existing task." "INFO"
    }

    # Remove existing task
    $removed = Remove-ExistingTask -Name $TaskName
    if (-not $removed) {
        Write-Log "Cannot proceed - failed to remove existing task." "ERROR"
        exit 1
    }
}

# Final confirmation (unless Force is specified)
if (-not $Force) {
    $confirmCreate = Get-UserConfirmation -Message "Create the scheduled task with the above configuration?"
    if (-not $confirmCreate) {
        Write-Log "Operation cancelled by user." "INFO"
        exit 0
    }
}

# Create the scheduled task
Write-Log "Creating scheduled task for weekly reboot..." "INFO"
$createdTask = New-RebootScheduledTask `
    -TaskName $TaskName `
    -Day $DayOfWeek `
    -ScheduledTime $Time `
    -Delay $RebootDelay

if ($null -eq $createdTask) {
    Write-Log "Failed to create scheduled task. Please check the error messages above." "ERROR"
    exit 1
}

# Verify task was created successfully
Start-Sleep -Seconds 2
$verifyTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($null -eq $verifyTask) {
    Write-Log "Task creation reported success, but task cannot be found in Task Scheduler." "ERROR"
    exit 1
}

# Display success summary
Write-Log "Scheduled task created successfully!" "SUCCESS"
Show-TaskSummary -Task $verifyTask -Day $DayOfWeek -ScheduledTime $Time -Delay $RebootDelay

# Display additional information
Write-Host "Additional Information:" -ForegroundColor Cyan
Write-Host "  - To view the task: " -NoNewline -ForegroundColor Gray
Write-Host "Get-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host "  - To disable the task: " -NoNewline -ForegroundColor Gray
Write-Host "Disable-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host "  - To enable the task: " -NoNewline -ForegroundColor Gray
Write-Host "Enable-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host "  - To remove the task: " -NoNewline -ForegroundColor Gray
Write-Host "Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false" -ForegroundColor White
Write-Host "  - To test the reboot: " -NoNewline -ForegroundColor Gray
Write-Host "Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host ""

Write-Log "Script completed successfully." "SUCCESS"
exit 0
