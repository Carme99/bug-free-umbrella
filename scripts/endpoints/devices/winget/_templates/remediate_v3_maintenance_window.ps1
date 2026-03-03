<#
.SYNOPSIS
    Maintenance window winget update script that only runs during specified hours (V3).

.DESCRIPTION
    This template checks if an app update is available and installs it ONLY during
    configured maintenance windows. Outside maintenance windows, the script exits without action.

    V3 ENHANCEMENTS:
    - Configurable maintenance window (day of week + time range)
    - Option to force close app during maintenance window
    - Retry logic with exponential backoff
    - Better error handling and logging
    - Pre/post update hooks

.NOTES
    REQUIRED: Configure winget ID and maintenance window schedule.
    BEST FOR: Critical apps that should only update during off-hours (e.g., databases, production tools).

.CONFIGURATION
    1. Set the $ID variable to your winget package ID
    2. Configure maintenance window settings (days, start/end times)
    3. Choose whether to force close app during maintenance window

.EXAMPLE
    # For SQL Server Management Studio - only update on weekends between 2-6 AM:
    $ID = 'Microsoft.SQLServerManagementStudio'
    $MaintenanceWindowDays = @('Saturday', 'Sunday')
    $MaintenanceWindowStartHour = 2
    $MaintenanceWindowEndHour = 6
    $ForceCloseInMaintenanceWindow = $true
#>

#region Configuration
# ===== REQUIRED: Set your winget package ID =====
$ID = 'WINGETID'  # Example: 'Microsoft.SQLServerManagementStudio', 'OBSProject.OBSStudio'

# ===== REQUIRED: Maintenance Window Configuration =====
# Days when updates are allowed (Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday)
$MaintenanceWindowDays = @('Saturday', 'Sunday')  # Update only on weekends

# Time range when updates are allowed (24-hour format)
$MaintenanceWindowStartHour = 2   # 2 AM
$MaintenanceWindowEndHour = 6     # 6 AM

# ===== OPTIONAL: Basic Settings =====
$name = $null                              # Leave as $null to auto-detect from winget
$AppProcess = $null                        # Leave as $null to auto-detect from package ID
$ForceCloseInMaintenanceWindow = $true     # Force close app if running during maintenance window

# ===== OPTIONAL: Advanced Settings =====
$MaxRetries = 3                            # Number of retry attempts for winget operations
$RetryDelaySeconds = 2                     # Initial delay between retries
$GracePeriodSeconds = 5                    # Time to wait after closing app (if force close enabled)
$VerifyWaitSeconds = 10                    # Time to wait after update to verify installation
$EnableLogging = $false                    # Set to $true to enable file logging
$LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetRemediation_$ID.log"

# ===== OPTIONAL: Hooks for Custom Actions =====
$PreUpdateScriptBlock = $null              # Script block to run before update
$PostUpdateScriptBlock = $null             # Script block to run after update
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

function Test-MaintenanceWindow {
    $now = Get-Date
    $currentDay = $now.DayOfWeek.ToString()
    $currentHour = $now.Hour

    Write-Log "Current time: $($now.ToString('yyyy-MM-dd HH:mm:ss')) | Day: $currentDay | Hour: $currentHour" -Level Info

    # Check if current day is in maintenance window
    if ($MaintenanceWindowDays -notcontains $currentDay) {
        Write-Log "Current day ($currentDay) is not in maintenance window. Allowed days: $($MaintenanceWindowDays -join ', ')" -Level Info
        return $false
    }

    # Check if current hour is in maintenance window
    if ($currentHour -lt $MaintenanceWindowStartHour -or $currentHour -ge $MaintenanceWindowEndHour) {
        Write-Log "Current hour ($currentHour) is outside maintenance window ($MaintenanceWindowStartHour-$MaintenanceWindowEndHour)" -Level Info
        return $false
    }

    Write-Log "Currently IN maintenance window: $currentDay $currentHour`:00" -Level Info
    return $true
}

function Invoke-WingetWithRetry {
    param(
        [string]$Arguments,
        [int]$MaxAttempts = $MaxRetries
    )

    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    $wingetPath = if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }
    
    $attempt = 1
    $delay = $RetryDelaySeconds

    while ($attempt -le $MaxAttempts) {
        try {
            Write-Log "Executing winget command (Attempt $attempt/$MaxAttempts): $wingetPath $Arguments" -Level Info
            
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

            if ($stdout -and -not ($stdout -match "error|failed|exception")) {
                return $stdout
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
    Write-Log "=== Starting winget maintenance window remediation for package: $ID ===" -Level Info

    # Check if we're in maintenance window
    if (-not (Test-MaintenanceWindow)) {
        Write-Log "Outside maintenance window. Update will not be performed." -Level Info
        Write-Host "Outside maintenance window. Updates only run during: $($MaintenanceWindowDays -join ', ') between $MaintenanceWindowStartHour`:00-$MaintenanceWindowEndHour`:00"
        exit 0  # Don't trigger remediation outside maintenance window
    }

    Write-Host "Inside maintenance window. Proceeding with update check..."

    # Locate winget executable
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop

    if ($wingetexe.Count -gt 1) {
        $SystemContext = $wingetexe[-1].Path
    } else {
        $SystemContext = $wingetexe.Path
    }

    New-Alias -Name sysget -Value "$SystemContext" -Force
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

    # Check if update is available
    if ($packageInfo -match '\bVersion\s+Available\b') {
        $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3,-2]
        Write-Log "Update available for $name | Installed: $verInstalled | Available: $verAvailable" -Level Info

        # Auto-detect process name if not provided
        if (-not $AppProcess) {
            $AppProcess = ($ID -split '\.')[-1]
        }

        # Handle running processes
        $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
        if ($process) {
            if ($ForceCloseInMaintenanceWindow) {
                Write-Log "$name is running. Force closing during maintenance window..." -Level Info
                Write-Host "$name is running. Force closing application during maintenance window..."

                Stop-Process -Name "$AppProcess" -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds $GracePeriodSeconds

                # Verify process was closed
                $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
                if ($process) {
                    Write-Log "$name process still running after force close attempt. Retrying..." -Level Warning
                    Stop-Process -Name "$AppProcess" -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                }

                Write-Log "$name closed successfully." -Level Info
            } else {
                Write-Log "$name is running. Skipping update (force close disabled)." -Level Warning
                Write-Host "$name is currently running. Skipping update."
                exit 1
            }
        } else {
            Write-Log "$name is not currently running." -Level Info
        }

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
                Status = "Updated During Maintenance Window"
                MaintenanceWindow = "$($MaintenanceWindowDays -join ', ') $MaintenanceWindowStartHour-$MaintenanceWindowEndHour"
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
