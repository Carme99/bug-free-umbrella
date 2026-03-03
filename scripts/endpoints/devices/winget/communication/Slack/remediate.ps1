<#
.SYNOPSIS
    Enhanced force close winget update script with user notification and retry logic (V3).

.DESCRIPTION
    This template checks if an app update is available and installs it.
    If the app is running, it will optionally notify the user before forcefully closing the app.

    V3 ENHANCEMENTS:
    - Optional user notification before force closing
    - Retry logic with exponential backoff
    - Better error handling and logging
    - Configurable grace periods
    - Pre/post update hooks

.NOTES
    REQUIRED: Only the winget ID is required. The script will auto-detect app name and process.
    WARNING: This will force close the application, potentially causing data loss!

.CONFIGURATION
    1. Set the $ID variable to your winget package ID
    2. (Optional) Enable user notifications and customize timing
    3. (Optional) Enable logging for troubleshooting

.EXAMPLE
    # For Slack with user notification:
    $ID = 'SlackTechnologies.Slack'
    $NotifyUserBeforeClose = $true
    $UserNotificationSeconds = 30
#>

#region Configuration
# ===== REQUIRED: Set your winget package ID =====
$ID = 'SlackTechnologies.Slack'

# ===== OPTIONAL: Basic Settings =====
$name = $null                   # Leave as $null to auto-detect from winget
$AppProcess = $null             # Leave as $null to auto-detect from package ID

# ===== OPTIONAL: Force Close Settings =====
$NotifyUserBeforeClose = $true      # Show notification to user before closing app
$UserNotificationSeconds = 60       # How long to show notification before closing (if enabled)
$GracePeriodSeconds = 5             # Time to wait after closing app before updating
$VerifyWaitSeconds = 10             # Time to wait after update to verify installation
$MaxProcessCloseAttempts = 3        # Number of attempts to close the process

# ===== OPTIONAL: Advanced Settings =====
$MaxRetries = 3                     # Number of retry attempts for winget operations
$RetryDelaySeconds = 2              # Initial delay between retries
$EnableLogging = $false             # Set to $true to enable file logging
$LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetRemediation_$ID.log"

# ===== OPTIONAL: Hooks for Custom Actions =====
$PreUpdateScriptBlock = $null       # Script block to run before update
$PostUpdateScriptBlock = $null      # Script block to run after update
#endregion

#region Functions
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'Error'   { Write-Error $Message }
        'Warning' { Write-Warning $Message }
        'Info'    { Write-Host $Message }
    }

    if ($EnableLogging) {
        try {
            $logDir = Split-Path -Path $LogPath -Parent
            if (-not (Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
            Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
        } catch { }
    }
}

function Show-UserNotification {
    param(
        [string]$AppName,
        [int]$Seconds
    )

    try {
        $notificationTitle = "Application Update Required"
        $notificationMessage = "$AppName will be closed in $Seconds seconds for an important update. Please save your work."

        # Use msg.exe to show notification (works in SYSTEM context)
        $users = query user 2>$null | Select-Object -Skip 1
        foreach ($user in $users) {
            if ($user -match '^\s*(\S+)') {
                $username = $Matches[1]
                msg.exe $username /TIME:$Seconds "$notificationTitle`n`n$notificationMessage" 2>$null
            }
        }

        Write-Log "User notification sent: $AppName will close in $Seconds seconds" -Level Info
    } catch {
        Write-Log "Failed to send user notification: $($_.Exception.Message)" -Level Warning
    }
}

function Stop-ApplicationProcess {
    param(
        [string]$ProcessName,
        [int]$MaxAttempts = $MaxProcessCloseAttempts
    )

    $attempt = 1
    while ($attempt -le $MaxAttempts) {
        $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue

        if (-not $process) {
            Write-Log "$ProcessName is not running (attempt $attempt)" -Level Info
            return $true
        }

        Write-Log "Stopping $ProcessName process (attempt $attempt/$MaxAttempts)..." -Level Info
        Stop-Process -Name $ProcessName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        $attempt++
    }

    # Final check
    $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($process) {
        Write-Log "Failed to stop $ProcessName after $MaxAttempts attempts" -Level Error
        return $false
    }

    return $true
}

function Invoke-WingetWithRetry {
    param(
        [string]$Arguments,
        [int]$MaxAttempts = $MaxRetries
    )

    $attempt = 1
    $delay = $RetryDelaySeconds

    while ($attempt -le $MaxAttempts) {
        try {
            Write-Log "Executing winget command (Attempt $attempt/$MaxAttempts): sysget $Arguments" -Level Info
function Invoke-WingetWithRetry {
    param([string]$Arguments)
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    $wingetPath = if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }
    $a = 1
    while ($a -le 3) {
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $wingetPath
            $psi.Arguments = $Arguments
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $p = New-Object System.Diagnostics.Process
            $p.StartInfo = $psi
            $p.Start() | Out-Null
            $stdout = $p.StandardOutput.ReadToEnd()
            $p.WaitForExit()
            if ($stdout) { return $stdout }
        } catch {
            Write-Verbose "Winget command failed on attempt $a: $($_.Exception.Message)" -Verbose:$false
        }
        Start-Sleep -Seconds 2
        $a++
    }
    throw "Failed after 3 attempts"
}

            if ($result -and -not ($result -match "error|failed|exception")) {
                return $result
            }

            Write-Log "Winget command returned invalid result on attempt $attempt" -Level Warning
        } catch {
            Write-Log "Winget command failed on attempt $attempt : $($_.Exception.Message)" -Level Warning
        }

        if ($attempt -lt $MaxAttempts) {
            Start-Sleep -Seconds $delay
            $delay = $delay * 2
        }

        $attempt++
    }

    throw "Winget command failed after $MaxAttempts attempts"
}
#endregion

#region Script
try {
    Write-Log "=== Starting winget force close remediation for package: $ID ===" -Level Info

    # Locate winget executable

    if ($wingetexe.Count -gt 1) {
        $SystemContext = $wingetexe[-1].Path
    } else {
        $SystemContext = $wingetexe.Path
    }

    
    Write-Log "Found winget: $SystemContext" -Level Info

    # Get package information
    $packageInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"

    # Auto-detect name if not provided
    if (-not $name) {
        $nameMatch = $packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d"
        if ($nameMatch) {
            $name = $nameMatch.Matches[0].Groups[2].Value.Trim()
        } else {
            $name = $ID
        }
    }

    # Check if package is installed
    if ($packageInfo -match "No installed package found matching input criteria") {
        Write-Log "$name is not installed on this device." -Level Info
        Write-Host "$name is not installed on this device."
        exit 0
    }

    # Auto-detect process name if not provided
    if (-not $AppProcess) {
        $AppProcess = ($ID -split '\.')[-1]
    }

    # Check if app is running and handle accordingly
    $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
    if ($process) {
        Write-Log "$name is currently running (PID: $($process.Id -join ', '))" -Level Info

        # Send user notification if enabled
        if ($NotifyUserBeforeClose) {
            Write-Log "Sending user notification before closing $name..." -Level Info
            Show-UserNotification -AppName $name -Seconds $UserNotificationSeconds
            Write-Host "$name will be closed in $UserNotificationSeconds seconds. Notifying users..."
            Start-Sleep -Seconds $UserNotificationSeconds
        }

        # Force close the application
        Write-Host "$name is running. Force closing application..."
        $closedSuccessfully = Stop-ApplicationProcess -ProcessName $AppProcess

        if (-not $closedSuccessfully) {
            Write-Log "Failed to close $name process. Aborting update." -Level Error
            Write-Error "Failed to close $name process. Cannot proceed with update."
            exit 1
        }

        Write-Log "$name closed successfully. Waiting $GracePeriodSeconds seconds..." -Level Info
        Start-Sleep -Seconds $GracePeriodSeconds
    } else {
        Write-Log "$name is not currently running." -Level Info
        Write-Host "$name is not currently running."
    }

    # Check if update is available
    if ($packageInfo -match '\bVersion\s+Available\b') {
        $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3,-2]
        Write-Log "Update available for $name | Installed: $verInstalled | Available: $verAvailable" -Level Info

        # Execute pre-update hook if defined
        if ($PreUpdateScriptBlock) {
            Write-Log "Executing pre-update hook..." -Level Info
            try {
                & $PreUpdateScriptBlock
            } catch {
                Write-Log "Pre-update hook failed: $($_.Exception.Message)" -Level Warning
            }
        }

        # Perform upgrade
        Write-Log "Installing $name update ($verInstalled -> $verAvailable)..." -Level Info
        Write-Host "Installing $name update..."

        $upgradeResult = Invoke-WingetWithRetry -Arguments "upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements"

        # Wait for installation to complete
        Write-Log "Waiting $VerifyWaitSeconds seconds for installation to complete..." -Level Info
        Start-Sleep -Seconds $VerifyWaitSeconds

        # Execute post-update hook if defined
        if ($PostUpdateScriptBlock) {
            Write-Log "Executing post-update hook..." -Level Info
            try {
                & $PostUpdateScriptBlock
            } catch {
                Write-Log "Post-update hook failed: $($_.Exception.Message)" -Level Warning
            }
        }

        # Verify installation
        Write-Log "Verifying installation..." -Level Info
        $verifyInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"

        if ($verifyInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $verifyInfo[-1])[-2]
            Write-Log "$name updated successfully to version $versionInstalled" -Level Info
            Write-Host "$name updated successfully to version $versionInstalled"

            [pscustomobject] @{
                Name = $name
                PreviousVersion = $verInstalled
                InstalledVersion = $versionInstalled
                Status = "Force Updated Successfully"
            }

            exit 0
        } else {
            Write-Log "Failed to verify $name installation after update" -Level Error
            Write-Error "Failed to verify $name installation after update."
            exit 1
        }
    } else {
        # No update available
        if ($packageInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $packageInfo[-1])[-2]
            Write-Log "$name is already up to date (version $versionInstalled)" -Level Info
            Write-Host "$name is already up to date (version $versionInstalled)"

            [pscustomobject] @{
                Name = $name
                InstalledVersion = $versionInstalled
                Status = "Up to Date"
            }

            exit 0
        }
    }

} catch {
    $errMsg = $_.Exception.Message
    Write-Log "ERROR: Failed to update $name : $errMsg" -Level Error
    Write-Error "Failed to update $name : $errMsg"
    exit 1
} finally {
    Write-Log "=== Remediation script completed ===" -Level Info
}
#endregion
