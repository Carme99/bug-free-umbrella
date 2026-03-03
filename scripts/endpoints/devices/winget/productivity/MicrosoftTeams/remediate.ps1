<#
.SYNOPSIS
    Enhanced update script for Microsoft Teams with user notification (V3).

.DESCRIPTION
    Notifies users 60 seconds before force-closing Teams for updates.
    This gives users time to save conversations and finish calls.

.NOTES
    Package ID: Microsoft.Teams
    Application: Microsoft Teams
    User notification enabled with 60-second warning
#>

#region Configuration
$ID = 'Microsoft.Teams'
$AppProcess = 'ms-teams'

# User Notification Settings - Give users time to save work
$NotifyUserBeforeClose = $true
$UserNotificationSeconds = 60
$GracePeriodSeconds = 5
$VerifyWaitSeconds = 10
$MaxProcessCloseAttempts = 3

$MaxRetries = 3
$RetryDelaySeconds = 2
$EnableLogging = $false
$LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetRemediation_$ID.log"
#endregion

#region Functions
function Write-Log {
    param([string]$Message, [ValidateSet('Info', 'Warning', 'Error')][string]$Level = 'Info')
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"; $logMessage = "[$timestamp] [$Level] $Message"
    switch ($Level) { 'Error' { Write-Error $Message } 'Warning' { Write-Warning $Message } 'Info' { Write-Host $Message } }
    if ($EnableLogging) { try { $logDir = Split-Path -Path $LogPath -Parent; if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }; Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue } catch { } }
}

function Show-UserNotification {
    param([string]$AppName, [int]$Seconds)
    try {
        $notificationTitle = "Application Update Required"
        $notificationMessage = "$AppName will be closed in $Seconds seconds for an important update. Please save your work and finish any calls."
        $users = query user 2>$null | Select-Object -Skip 1
        foreach ($user in $users) {
            if ($user -match '^\s*(\S+)') {
                $username = $Matches[1]
                msg.exe $username /TIME:$Seconds "$notificationTitle`n`n$notificationMessage" 2>$null
            }
        }
        Write-Log "User notification sent: $AppName will close in $Seconds seconds" -Level Info
    } catch { Write-Log "Failed to send notification: $($_.Exception.Message)" -Level Warning }
}

function Stop-ApplicationProcess {
    param([string]$ProcessName, [int]$MaxAttempts = $MaxProcessCloseAttempts)
    $attempt = 1
    while ($attempt -le $MaxAttempts) {
        $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if (-not $process) { return $true }
        Write-Log "Stopping $ProcessName (attempt $attempt/$MaxAttempts)..." -Level Info
        Stop-Process -Name $ProcessName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $attempt++
    }
    return (-not (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue))
}

function Invoke-WingetWithRetry {
    param([string]$Arguments, [int]$MaxAttempts = $MaxRetries)
    $attempt = 1; $delay = $RetryDelaySeconds
    while ($attempt -le $MaxAttempts) {
        try {
            $result = Invoke-Expression "sysget $Arguments 2>&1"
            if ($result -and -not ($result -match "error|failed|exception")) { return $result }
        } catch { Write-Log "Failed: $($_.Exception.Message)" -Level Warning }
        if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds $delay; $delay = $delay * 2 }
        $attempt++
    }
    throw "Winget command failed after $MaxAttempts attempts"
}
#endregion

#region Script
try {
    Write-Log "=== Starting Microsoft Teams update ===" -Level Info

    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    $SystemContext = if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }
    

    $packageInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"
    $nameMatch = $packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d"
    $name = if ($nameMatch) { $nameMatch.Matches[0].Groups[2].Value.Trim() } else { $ID }

    if ($packageInfo -match "No installed package found matching input criteria") {
        Write-Host "$name is not installed."; exit 0
    }

    # Check if Teams is running and notify user
    $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
    if ($process) {
        Write-Log "$name is running. Sending user notification..." -Level Info
        Show-UserNotification -AppName $name -Seconds $UserNotificationSeconds
        Write-Host "$name will be closed in $UserNotificationSeconds seconds. Notifying users..."
        Start-Sleep -Seconds $UserNotificationSeconds

        Write-Host "Force closing $name..."
        if (-not (Stop-ApplicationProcess -ProcessName $AppProcess)) {
            Write-Error "Failed to close $name. Cannot proceed with update."; exit 1
        }
        Start-Sleep -Seconds $GracePeriodSeconds
    }

    if ($packageInfo -match '\bVersion\s+Available\b') {
        $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3,-2]
        Write-Host "Installing $name update ($verInstalled -> $verAvailable)..."

        $upgradeResult = Invoke-WingetWithRetry -Arguments "upgrade --accept-package-agreements --accept-source-agreements -e --id $ID --silent --accept-package-agreements --accept-source-agreements"
        Start-Sleep -Seconds $VerifyWaitSeconds

        $verifyInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"
        if ($verifyInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $verifyInfo[-1])[-2]
            Write-Host "$name updated successfully to version $versionInstalled"
            [pscustomobject] @{ Name = $name; PreviousVersion = $verInstalled; InstalledVersion = $versionInstalled; Status = "Updated Successfully" }
            exit 0
        } else {
            Write-Error "Failed to verify installation."; exit 1
        }
    } else {
        if ($packageInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $packageInfo[-1])[-2]
            Write-Host "$name is already up to date (version $versionInstalled)"
            exit 0
        }
    }
} catch {
    Write-Error "Failed to update: $($_.Exception.Message)"; exit 1
} finally {
    Write-Log "=== Remediation completed ===" -Level Info
}
#endregion
