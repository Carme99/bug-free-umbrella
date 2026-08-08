# Wrapper script to deploy and trigger your notification script via scheduled task

# Paths and variables
$LogPath = "C:\IT_Logs"
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath "$LogPath\DeployRestartNotification.log" -Append -Encoding UTF8
    Write-Output "$Timestamp - $Message" # For Intune 'Post Remediation Detection Output'
}

Write-Log "Deployment script started."

# === Check BurntToast module on deployment machine and install if missing ===
if (-not (Get-Module -ListAvailable -Name BurntToast)) {
    Write-Log "BurntToast module not found. Installing..."
    try {
        Install-Module -Name BurntToast -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
        Write-Log "BurntToast module installed successfully."
    }
    catch {
        Write-Error "Failed to install BurntToast module: $_"
        Exit 1
    }
}
else {
    Write-Log "BurntToast module already installed."
}

# Where to save your notification script
$NotificationScriptPath = "$env:LOCALAPPDATA\Temp\RestartNotification.ps1"

# Your exact notification script content as a here-string
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

Write-Log "Notification script started."

# Ensure TLS 1.2 (GitHub requires it)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Download logo image if needed
$LogoImageUri = "https://raw.githubusercontent.com/insignit/endpointmanagerbranding/master/insignit_512.jpg"
$LogoImage = "$env:TEMP\ToastLogoImage.png"

if (-not (Test-Path $LogoImage) -or ((Get-Item $LogoImage).Length -eq 0)) {
    Write-Log "Downloading logo image $LogoImageUri"
    try {
        Invoke-WebRequest -Uri $LogoImageUri -OutFile $LogoImage -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        Write-Log "Downloaded logo image $LogoImage"
    }
    catch {
        Write-Log "Failed to download logo image: $_"
        Exit 1
    }
}
else {
    Write-Log "Logo image already exists: $LogoImage"
}

    # Get time since last restart for notification text
    # NOTE: OSUptime derives from Win32_OperatingSystem.LastBootUpTime (time since the OS
    # was last restarted); sleep/hibernate time does not count.
    try {
        $Uptime = (Get-ComputerInfo).OSUptime
        $UptimeDays = [math]::Floor($Uptime.TotalDays)
    }
    catch {
        Write-Log "Failed to get uptime: $_"
        $UptimeDays = "unknown"
    }

# Show toast notification with buttons
try {
    Import-Module BurntToast
    
    # Create toast buttons
    $btnRestart = New-BTButton -Content "Restart Now" -Arguments "shutdown /r /t 0" -ActivationType Protocol
    $btnRemind = New-BTButton -Content "Remind Me Later" -Arguments "dismiss" -ActivationType Protocol

    # Show toast with buttons
    New-BurntToastNotification `
        -Text "Restart Required", "Your device has not been restarted in $UptimeDays days.", "Restart for better performance and security." `
        -AppLogo $LogoImage `
        -Button $btnRestart, $btnRemind

    Write-Log "Toast notification shown successfully with buttons."
}
catch {
    Write-Log "Failed to show toast notification: $_"
    Exit 1
}

Write-Log "Notification script completed."
Exit 0
'@

# Save the notification script
try {
    Set-Content -Path $NotificationScriptPath -Value $NotificationScriptContent -Force -Encoding UTF8
    Write-Log "Notification script saved to $NotificationScriptPath."
}
catch {
    Write-Error "Failed to save notification script: $_"
    Exit 1
}

# Scheduled task details
$TaskName = "RestartNotification"

# Remove existing task if present
try {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Log "Existing scheduled task '$TaskName' removed."
    }
}
catch {
    Write-Error "Failed to remove existing task: $_"
}

# Create scheduled task action to run your script
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$NotificationScriptPath`""

# Trigger: run once, 15 seconds from now
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(15)

# Principal: current user, interactive logon, limited privileges
$CurrentUser = "$env:USERDOMAIN\$env:USERNAME"
$Principal = New-ScheduledTaskPrincipal -UserId $CurrentUser -LogonType Interactive -RunLevel Limited

# Register the scheduled task
try {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Force
    Write-Log "Scheduled task '$TaskName' registered successfully."
}
catch {
    Write-Error "Failed to register scheduled task: $_"
    Exit 1
}

Write-Log "Deployment script completed. Waiting for scheduled task to trigger."
Exit 0
