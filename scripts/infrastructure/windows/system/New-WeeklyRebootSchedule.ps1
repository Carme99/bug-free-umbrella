<#
.SYNOPSIS
    Creates a scheduled task to reboot Windows Server on a weekly basis.

.DESCRIPTION
    This script creates a comprehensive weekly reboot schedule for Windows Server by:
    - Interactively prompting for day of week selection (unless -DayOfWeek is supplied)
    - Accepting time input in 24-hour format (unless -Time is supplied)
    - Creating a scheduled task under the NT AUTHORITY\SYSTEM account with highest privileges
    - Validating all inputs before task creation
    - Providing detailed logging and error handling

    Task creation follows a check-then-act pattern: an existing task with the same
    name is detected first and (with -Force or user confirmation) replaced, so
    re-running the script is safe. The registration itself is gated by
    -WhatIf/-Confirm (SupportsShouldProcess).

    Exit codes: 0 = task created (or user cancelled), 1 = fatal error or missing
    Administrator privileges.

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
    PS C:\> .\New-WeeklyRebootSchedule.ps1
    Runs interactively, prompting for day and time.

.EXAMPLE
    PS C:\> .\New-WeeklyRebootSchedule.ps1 -DayOfWeek Sunday -Time "03:00"
    Creates a weekly reboot scheduled for Sunday at 3:00 AM.

.EXAMPLE
    PS C:\> .\New-WeeklyRebootSchedule.ps1 -DayOfWeek Saturday -Time "23:30" -RebootDelay 120
    Creates a weekly reboot for Saturday at 11:30 PM with 2-minute delay.

.EXAMPLE
    PS C:\> .\New-WeeklyRebootSchedule.ps1 -DayOfWeek Monday -Time "02:00" -Force
    Creates/replaces the task for Monday at 2:00 AM without confirmation.

.NOTES
    File Name:     New-WeeklyRebootSchedule.ps1
    Author:        System Administrator
    Prerequisite:  PowerShell 5.1+
    Version:       1.0.0
    Date:          2026-08-23

    Requires Administrator privileges on supported operating systems.
    Compatible with Windows Server 2016, 2019, and 2022.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Console remediation tool: prefixed, color-coded host output is the intended user interface.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")]
    [string]$DayOfWeek,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$')]
    [string]$Time,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$TaskName = "Weekly Server Reboot",

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 600)]
    [int]$RebootDelay = 60,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Test-AdminPrivilege {
    [CmdletBinding()]
    param()

    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [System.Security.Principal.WindowsPrincipal]$identity
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        # Non-Windows platform or unavailable identity APIs.
        return $false
    }
}

function Write-LogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = switch ($Type) {
        "ERROR" { "[-]" }
        "SUCCESS" { "[+]" }
        "WARNING" { "[!]" }
        default { "[*]" }
    }
    $color = switch ($Type) {
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        default { "Cyan" }
    }
    Write-Host "[$timestamp] $prefix $Message" -ForegroundColor $color
}

function Show-Banner {
    <#
    .SYNOPSIS
        Displays script banner and system information.
    #>
    [CmdletBinding()]
    param()

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
    [CmdletBinding()]
    param()

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
    [CmdletBinding()]
    param()

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
            return "${hour}:${minute}"
        }
        else {
            Write-Host "Invalid time format. Use 24-hour format (HH:mm), e.g., 02:00 or 23:30" -ForegroundColor Red
        }
    } while ($true)
}

function Test-ScheduledTaskPresence {
    <#
    .SYNOPSIS
        Checks if a scheduled task exists.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
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
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    try {
        if ($PSCmdlet.ShouldProcess($Name, 'Unregister scheduled task')) {
            Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop
            Write-LogEntry "Removed existing scheduled task: $Name" "SUCCESS"
            return $true
        }

        return $false
    }
    catch {
        Write-LogEntry "Failed to remove existing task: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function New-RebootScheduledTask {
    <#
    .SYNOPSIS
        Creates the scheduled task for weekly reboots.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TaskName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Day,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScheduledTime,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 3600)]
        [int]$Delay
    )

    try {
        Write-LogEntry "Creating scheduled task configuration..." "INFO"

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
        Write-LogEntry "Registering scheduled task..." "INFO"
        if ($PSCmdlet.ShouldProcess($TaskName, 'Register weekly reboot scheduled task')) {
            $task = Register-ScheduledTask `
                -TaskName $TaskName `
                -Action $action `
                -Trigger $trigger `
                -Settings $settings `
                -Principal $principal `
                -Description "Weekly reboot every $Day at $ScheduledTime. Created by New-WeeklyRebootSchedule.ps1" `
                -ErrorAction Stop

            return $task
        }

        return $null
    }
    catch {
        Write-LogEntry "Failed to create scheduled task: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Show-TaskSummary {
    <#
    .SYNOPSIS
        Displays a summary of the created scheduled task.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Task,

        [Parameter(Mandatory = $true)]
        [string]$Day,

        [Parameter(Mandatory = $true)]
        [string]$ScheduledTime,

        [Parameter(Mandatory = $true)]
        [int]$Delay
    )

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "[+] Scheduled Task Created Successfully  " -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Task Name:       $($Task.TaskName)" -ForegroundColor White
    Write-Host "[*] Schedule:        Every $Day at $ScheduledTime" -ForegroundColor White
    Write-Host "Reboot Delay:    $Delay seconds" -ForegroundColor White
    Write-Host "Run As:          NT AUTHORITY\SYSTEM" -ForegroundColor White
    Write-Host "[*] State:           $($Task.State)" -ForegroundColor White

    # Calculate next run time
    $taskInfo = Get-ScheduledTaskInfo -TaskName $Task.TaskName
    if ($taskInfo.NextRunTime) {
        Write-Host "[*] Next Run:        $($taskInfo.NextRunTime)" -ForegroundColor Cyan
    }

    Write-Host "========================================`n" -ForegroundColor Green
}

function Get-UserConfirmation {
    <#
    .SYNOPSIS
        Prompts user for confirmation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-Host "`n$Message" -ForegroundColor Yellow
    Write-Host "Continue? (Y/N): " -NoNewline -ForegroundColor Cyan
    $response = Read-Host
    return ($response -eq 'Y' -or $response -eq 'y')
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")]
        [string]$DayOfWeek,

        [Parameter(Mandatory = $false)]
        [string]$Time,

        [Parameter(Mandatory = $false)]
        [string]$TaskName = "Weekly Server Reboot",

        [Parameter(Mandatory = $false)]
        [int]$RebootDelay = 60,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    try {
        Show-Banner

        Write-LogEntry "Starting Weekly Reboot Scheduler configuration..." "INFO"

        if (-not (Test-AdminPrivilege)) {
            Write-LogEntry "Administrator privileges are required. Re-run from an elevated PowerShell session." "ERROR"
            return 1
        }

        # Get day of week (interactive or parameter)
        if ([string]::IsNullOrEmpty($DayOfWeek)) {
            $DayOfWeek = Get-DayOfWeekSelection
            Write-LogEntry "Selected day: $DayOfWeek" "INFO"
        }
        else {
            Write-LogEntry "Using day from parameter: $DayOfWeek" "INFO"
        }

        # Get time (interactive or parameter)
        if ([string]::IsNullOrEmpty($Time)) {
            $Time = Get-TimeInput
            Write-LogEntry "Selected time: $Time" "INFO"
        }
        else {
            Write-LogEntry "Using time from parameter: $Time" "INFO"
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

        # Check if task already exists (check-then-act: converge safely on re-run)
        $taskExists = Test-ScheduledTaskPresence -Name $TaskName

        if ($taskExists) {
            Write-LogEntry "A scheduled task with the name '$TaskName' already exists." "WARNING"

            if (-not $Force) {
                $confirmOverwrite = Get-UserConfirmation -Message "Do you want to replace the existing task?"
                if (-not $confirmOverwrite) {
                    Write-LogEntry "Operation cancelled by user." "INFO"
                    return 0
                }
            }
            else {
                Write-LogEntry "Force parameter specified - will overwrite existing task." "INFO"
            }

            # Remove existing task
            $removed = Remove-ExistingTask -Name $TaskName
            if (-not $removed) {
                Write-LogEntry "Cannot proceed - failed to remove existing task." "ERROR"
                return 1
            }
        }

        # Final confirmation (unless Force is specified)
        if (-not $Force) {
            $confirmCreate = Get-UserConfirmation -Message "Create the scheduled task with the above configuration?"
            if (-not $confirmCreate) {
                Write-LogEntry "Operation cancelled by user." "INFO"
                return 0
            }
        }

        # Create the scheduled task
        Write-LogEntry "Creating scheduled task for weekly reboot..." "INFO"
        $createdTask = New-RebootScheduledTask `
            -TaskName $TaskName `
            -Day $DayOfWeek `
            -ScheduledTime $Time `
            -Delay $RebootDelay

        if ($null -eq $createdTask) {
            Write-LogEntry "Failed to create scheduled task. Please check the error messages above." "ERROR"
            return 1
        }

        # Verify task was created successfully
        Start-Sleep -Seconds 2
        $verifyTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

        if ($null -eq $verifyTask) {
            Write-LogEntry "Task creation reported success, but task cannot be found in Task Scheduler." "ERROR"
            return 1
        }

        # Display success summary
        Write-LogEntry "Scheduled task created successfully!" "SUCCESS"
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

        Write-LogEntry "Script completed successfully." "SUCCESS"
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
