<#
.SYNOPSIS
    Deploy the restart notification script and scheduled task.

.DESCRIPTION
    Deploys a toast notification script (RestartNotification.ps1) and registers a scheduled task that
    shows it after uptime/detect.ps1 flags a device that has not been restarted for 4+ days. Installs
    the BurntToast module when missing and registers a one-shot scheduled task that triggers 15 seconds
    after deployment. Destructive steps (replacing an existing task) honor -WhatIf/-Confirm.
    Idempotent: re-running on a converged device succeeds and only refreshes the same task.
    Exit codes: 0 = deployment succeeded; 1 = any deployment step failed.

.EXAMPLE
    PS C:\> .\remediate.ps1

    Deploys the restart notification script and registers the RestartNotification scheduled task.

.EXAMPLE
    PS C:\> .\remediate.ps1 -WhatIf

    Shows which files would be written and tasks registered without changing the system.

.NOTES
    File Name  : remediate.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

$LogPath = 'C:\IT_Logs'
$TaskName = 'RestartNotification'

function Write-DeploymentLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [string]$LogRoot = $LogPath
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logFile = Join-Path $LogRoot 'DeployRestartNotification.log'
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
    Write-Host "[*] $Message" -ForegroundColor Cyan  # For Intune 'Post Remediation Detection Output'
}

function Install-BurntToastModule {
    # Module-installation seam (network operation): tests mock this function.
    [CmdletBinding()]
    param()

    if (Get-Module -ListAvailable -Name BurntToast) {
        Write-DeploymentLog 'BurntToast module already installed.'
        return
    }

    Write-DeploymentLog 'BurntToast module not found. Installing...'
    Install-Module -Name BurntToast -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
    Write-DeploymentLog 'BurntToast module installed successfully.'
}

function Save-RestartNotificationScript {
    # File-write seam so tests can verify the deployed script without touching disk.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Content
    )

    Set-Content -Path $Path -Value $Content -Force -Encoding UTF8 -ErrorAction Stop
}

$NotificationScriptContent = @'
# Set up logging
$LogPath = "C:\IT_Logs"
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath "$LogPath\RestartNotification.log" -Append -Encoding UTF8
}

Write-DeploymentLog "Notification script started."

# Ensure TLS 1.2 (GitHub requires it)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Download logo image if needed
$LogoImageUri = "https://raw.githubusercontent.com/insignit/endpointmanagerbranding/master/insignit_512.jpg"
$LogoImage = "$env:TEMP\ToastLogoImage.png"

if (-not (Test-Path $LogoImage) -or ((Get-Item $LogoImage).Length -eq 0)) {
    Write-DeploymentLog "Downloading logo image $LogoImageUri"
    try {
        Invoke-WebRequest -Uri $LogoImageUri -OutFile $LogoImage -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        Write-DeploymentLog "Downloaded logo image $LogoImage"
    }
    catch {
        Write-DeploymentLog "Failed to download logo image: $_"
        Exit 1
    }
}
else {
    Write-DeploymentLog "Logo image already exists: $LogoImage"
}

    # Get time since last restart for notification text
    # NOTE: OSUptime derives from Win32_OperatingSystem.LastBootUpTime (time since the OS
    # was last restarted); sleep/hibernate time does not count.
    try {
        $Uptime = (Get-ComputerInfo).OSUptime
        $UptimeDays = [math]::Floor($Uptime.TotalDays)
    }
    catch {
        Write-DeploymentLog "Failed to get uptime: $_"
        $UptimeDays = "unknown"
    }

# Show toast notification with buttons
try {
    Import-Module BurntToast

    # Create toast buttons
    $btnRestart = New-BTButton -Content "Restart Now" -Arguments "shutdown /r /t 0" -ActivationType Protocol
    $btnRemind = New-BTButton -Content "Remind Me Later" -Arguments "dismiss" -ActivationType Protocol

    # Show toast with buttons
    $toastText = @(
        "Restart Required",
        "Your device has not been restarted in $UptimeDays days.",
        "Restart for better performance and security."
    )
    New-BurntToastNotification `
        -Text $toastText `
        -AppLogo $LogoImage `
        -Button $btnRestart, $btnRemind

    Write-DeploymentLog "Toast notification shown successfully with buttons."
}
catch {
    Write-DeploymentLog "Failed to show toast notification: $_"
    Exit 1
}

Write-DeploymentLog "Notification script completed."
Exit 0
'@

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param()

    try {
        Write-DeploymentLog 'Deployment script started.'

        if (-not (Test-Path $LogPath)) {
            if ($PSCmdlet.ShouldProcess($LogPath, 'Create log directory')) {
                New-Item -ItemType Directory -Path $LogPath -Force -ErrorAction Stop | Out-Null
            }
        }

        Install-BurntToastModule

        # Where to save the notification script.
        $notificationScriptPath = "$env:LOCALAPPDATA\Temp\RestartNotification.ps1"

        if ($PSCmdlet.ShouldProcess($notificationScriptPath, 'Write restart notification script')) {
            Save-RestartNotificationScript -Path $notificationScriptPath -Content $NotificationScriptContent
            Write-DeploymentLog "Notification script saved to $notificationScriptPath."
        }

        # Remove existing task if present (destructive: gated by ShouldProcess).
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            if ($PSCmdlet.ShouldProcess($TaskName, 'Remove existing scheduled task')) {
                Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
                Write-DeploymentLog "Existing scheduled task '$TaskName' removed."
            }
        }

        # Scheduled task action: run the notification script hidden, bypassing execution policy.
        $actionArgs = @{
            Execute  = 'powershell.exe'
            Argument = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$notificationScriptPath`""
        }
        $action = New-ScheduledTaskAction @actionArgs

        # Trigger: run once, 15 seconds from now.
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(15)

        # Principal: current user, interactive logon, limited privileges.
        $currentUser = "$env:USERDOMAIN\$env:USERNAME"
        $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited

        if ($PSCmdlet.ShouldProcess($TaskName, 'Register restart notification scheduled task')) {
            $registerArgs = @{
                TaskName  = $TaskName
                Action    = $action
                Trigger   = $trigger
                Principal = $principal
                Force     = $true
            }
            Register-ScheduledTask @registerArgs -ErrorAction Stop | Out-Null
            Write-DeploymentLog "Scheduled task '$TaskName' registered successfully."
        }

        Write-DeploymentLog 'Deployment script completed. Waiting for scheduled task to trigger.'
        Write-Host '[+] Restart notification deployed.' -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }

