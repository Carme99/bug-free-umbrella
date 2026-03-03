<#
.SYNOPSIS
    Winget update detection script for Adobe Acrobat Reader 32-bit (V3).

.DESCRIPTION
    Enhanced detection script with retry logic and better error handling.
    Auto-detects application name from winget.

.NOTES
    Package ID: Adobe.Acrobat.Reader.32-bit
    Application: Adobe Acrobat Reader (32-bit)
    Template Version: V3
#>

#region Configuration
$ID = 'Adobe.Acrobat.Reader.32-bit'

# Optional: Advanced Settings
$MaxRetries = 3
$RetryDelaySeconds = 2
$EnableLogging = $false
$LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetDetection_$ID.log"
$CheckNetworkConnectivity = $true
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

function Test-NetworkConnectivity {
    try {
        $testConnection = Test-Connection -ComputerName "www.microsoft.com" -Count 1 -Quiet -ErrorAction SilentlyContinue
        return $testConnection
    } catch {
        return $false
    }
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
            $result = Invoke-Expression "sysget $Arguments 2>&1"

            if ($result -and -not ($result -match "error|failed|exception")) {
                Write-Log "Winget command succeeded on attempt $attempt" -Level Info
                return $result
            }

            Write-Log "Winget command returned invalid result on attempt $attempt" -Level Warning
        } catch {
            Write-Log "Winget command failed on attempt $attempt : $($_.Exception.Message)" -Level Warning
        }

        if ($attempt -lt $MaxAttempts) {
            Write-Log "Waiting $delay seconds before retry..." -Level Info
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
    Write-Log "=== Starting winget detection for package: $ID ===" -Level Info

    if ($CheckNetworkConnectivity) {
        Write-Log "Checking network connectivity..." -Level Info
        if (-not (Test-NetworkConnectivity)) {
            Write-Log "No network connectivity detected. Cannot check for updates." -Level Warning
            exit 0
        }
        Write-Log "Network connectivity confirmed" -Level Info
    }

    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop

    if ($wingetexe.Count -gt 1) {
        $SystemContext = $wingetexe[-1].Path
        Write-Log "Found multiple winget installations, using latest: $SystemContext" -Level Info
    } else {
        $SystemContext = $wingetexe.Path
        Write-Log "Found winget: $SystemContext" -Level Info
    }

    

    Write-Log "Querying package information for: $ID" -Level Info
    $packageInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"

    $nameMatch = $packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d"
    if ($nameMatch) {
        $name = $nameMatch.Matches[0].Groups[2].Value.Trim()
        Write-Log "Auto-detected application name: $name" -Level Info
    } else {
        $name = $ID
        Write-Log "Could not auto-detect name, using ID: $name" -Level Warning
    }

    if ($packageInfo -match "No installed package found matching input criteria") {
        Write-Log "$name is not installed on this device." -Level Info
        Write-Host "$name is not installed on this device."
        exit 0
    }

    if ($packageInfo -match '\bVersion\s+Available\b') {
        $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3,-2]
        Write-Log "Update available for $name | Installed: $verInstalled | Available: $verAvailable" -Level Info
        Write-Host "Application update available for $name. Current: $verInstalled, Available: $verAvailable"

        [pscustomobject] @{
            Name = $name
            InstalledVersion = $verInstalled
            AvailableVersion = $verAvailable
            Status = "UpdateAvailable"
        }

        exit 1
    } else {
        if ($packageInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $packageInfo[-1])[-2]
            Write-Log "$name is up to date (version $versionInstalled)" -Level Info
            Write-Host "$name is already up to date (version $versionInstalled)"

            [pscustomobject] @{
                Name = $name
                InstalledVersion = $versionInstalled
                Status = "UpToDate"
            }

            exit 0
        } else {
            Write-Log "$name appears to be installed but version info could not be parsed" -Level Warning
            Write-Host "$name is installed but version could not be determined"
            exit 0
        }
    }

} catch {
    $errMsg = $_.Exception.Message
    Write-Log "ERROR: Failed to check $name for updates: $errMsg" -Level Error
    Write-Error "Failed to check for updates: $errMsg"
    exit 0
} finally {
    Write-Log "=== Detection script completed ===" -Level Info
}
#endregion
