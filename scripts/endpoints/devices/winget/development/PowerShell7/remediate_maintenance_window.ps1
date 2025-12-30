<#
.SYNOPSIS
    Maintenance window update for PowerShell 7 (V3).

.DESCRIPTION
    Updates PowerShell 7 ONLY during weekend maintenance windows.
    Recommended for production environments to avoid disrupting scheduled scripts.

.NOTES
    Package ID: Microsoft.PowerShell
    Maintenance Window: Saturdays & Sundays, 2 AM - 6 AM
    Force closes PowerShell sessions during maintenance window
#>

#region Configuration
$ID = 'Microsoft.PowerShell'
$name = 'PowerShell 7'
$AppProcess = 'pwsh'

# Maintenance Window: Weekends 2-6 AM
$MaintenanceWindowDays = @('Saturday', 'Sunday')
$MaintenanceWindowStartHour = 2
$MaintenanceWindowEndHour = 6
$ForceCloseInMaintenanceWindow = $true

$MaxRetries = 3
$GracePeriodSeconds = 5
$VerifyWaitSeconds = 10
$EnableLogging = $true
$LogPath = "C:\ProgramData\IntuneScripts\Logs\PowerShell7_Maintenance.log"
#endregion

#region Functions
function Write-Log {
    param([string]$Message, [string]$Level = 'Info')
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    switch ($Level) { 'Error' { Write-Error $Message } 'Warning' { Write-Warning $Message } default { Write-Host $Message } }
    if ($EnableLogging) {
        try {
            $logDir = Split-Path $LogPath -Parent
            if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
            Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
        } catch { }
    }
}

function Test-MaintenanceWindow {
    $now = Get-Date
    $currentDay = $now.DayOfWeek.ToString()
    $currentHour = $now.Hour
    Write-Log "Current: $($now.ToString('yyyy-MM-dd HH:mm')) | Day: $currentDay | Hour: $currentHour"

    if ($MaintenanceWindowDays -notcontains $currentDay) {
        Write-Log "Day ($currentDay) not in maintenance window: $($MaintenanceWindowDays -join ', ')"
        return $false
    }

    if ($currentHour -lt $MaintenanceWindowStartHour -or $currentHour -ge $MaintenanceWindowEndHour) {
        Write-Log "Hour ($currentHour) outside window: $MaintenanceWindowStartHour-$MaintenanceWindowEndHour"
        return $false
    }

    Write-Log "IN MAINTENANCE WINDOW: $currentDay $currentHour`:00" -Level Warning
    return $true
}

function Invoke-WingetWithRetry { param([string]$Arguments); $a = 1; while ($a -le 3) { try { $r = Invoke-Expression "sysget $Arguments 2>&1"; if ($r) { return $r } } catch { }; Start-Sleep -Seconds 2; $a++ }; throw "Failed" }
#endregion

#region Script
try {
    Write-Log "=== PowerShell 7 Maintenance Window Update ===" -Level Warning

    if (-not (Test-MaintenanceWindow)) {
        Write-Host "Outside maintenance window. Updates run: $($MaintenanceWindowDays -join ', ') $MaintenanceWindowStartHour`:00-$MaintenanceWindowEndHour`:00"
        Write-Log "Exiting - outside maintenance window"
        exit 0
    }

    Write-Host "Inside maintenance window. Proceeding with update..."

    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    New-Alias -Name sysget -Value $(if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }) -Force

    $packageInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"

    if ($packageInfo -match "No installed package found") {
        Write-Host "$name not installed."; exit 0
    }

    if ($packageInfo -match '\bVersion\s+Available\b') {
        $v = (-split $packageInfo[-1])[-3,-2]
        Write-Log "Update available: $($v[0]) -> $($v[1])" -Level Warning

        # Force close PowerShell 7 sessions during maintenance
        $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
        if ($process) {
            Write-Log "Closing PowerShell 7 sessions (PID: $($process.Id -join ', '))" -Level Warning
            Write-Host "Force closing PowerShell 7 sessions..."
            Stop-Process -Name "$AppProcess" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds $GracePeriodSeconds
        }

        Write-Host "Installing PowerShell 7 update ($($v[0]) -> $($v[1]))..."
        Write-Log "Starting update installation..."

        Invoke-WingetWithRetry -Arguments "upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements" | Out-Null
        Start-Sleep -Seconds $VerifyWaitSeconds

        $verify = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"
        if ($verify -match '\d+(\.\d+)+') {
            $installedVer = (-split $verify[-1])[-2]
            Write-Host "PowerShell 7 updated successfully to version $installedVer"
            Write-Log "Update completed: $installedVer" -Level Warning
            exit 0
        }

        Write-Error "Verification failed"
        Write-Log "Verification failed" -Level Error
        exit 1
    }

    Write-Host "$name is up to date."
    exit 0
} catch {
    Write-Error "Update failed: $_"
    Write-Log "ERROR: $_" -Level Error
    exit 1
}
#endregion
