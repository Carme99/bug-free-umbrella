<#
.SYNOPSIS
    Enhanced winget update detection script for Intune Proactive Remediations (V3).

.DESCRIPTION
    This template checks if an app update is available via winget with enhanced features:
    - Retry logic with exponential backoff
    - Better error handling and logging
    - Network connectivity validation
    - Detailed status reporting

    Returns exit code 1 if update is available (triggers remediation).
    Returns exit code 0 if app is up to date or not installed (no action needed).

.NOTES
    REQUIRED: Only the winget ID is required. The script will auto-detect app name.

    V3 ENHANCEMENTS:
    - Configurable retry logic (default: 3 attempts with exponential backoff)
    - Optional logging to file or event log
    - Network connectivity checks before querying winget
    - More detailed error messages and status reporting

.CONFIGURATION
    1. Set the $ID variable to your winget package ID
    2. (Optional) Customize retry, logging, and other advanced settings

.EXAMPLE
    # For Microsoft Teams:
    $ID = 'Microsoft.Teams'

    # Enable logging:
    $EnableLogging = $true
    $LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetDetection.log"
#>

#region Configuration
# ===== REQUIRED: Set your winget package ID =====
$ID = 'WINGETID'  # Example: 'Google.Chrome', 'Microsoft.Teams', 'Slack.Slack'

# ===== OPTIONAL: Basic Settings =====
$name = $null     # Leave as $null to auto-detect from winget, or set manually

# ===== OPTIONAL: Advanced Settings =====
$MaxRetries = 3                    # Number of retry attempts for winget operations
$RetryDelaySeconds = 2             # Initial delay between retries (doubles each retry)
$EnableLogging = $false            # Set to $true to enable file logging
$LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetDetection_$ID.log"  # Log file path
$CheckNetworkConnectivity = $true  # Verify internet connectivity before querying winget
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

    # Always write to console
    switch ($Level) {
        'Error'   { Write-Error $Message }
        'Warning' { Write-Warning $Message }
        'Info'    { Write-Host $Message }
    }

    # Optionally write to file
    if ($EnableLogging) {
        try {
            $logDir = Split-Path -Path $LogPath -Parent
            if (-not (Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
            Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
        } catch {
            # Fail silently if logging doesn't work
        }
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

            # Execute winget command
            $result = Invoke-Expression "sysget $Arguments 2>&1"

            # Check if result is valid (not empty and not an error)
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
            $delay = $delay * 2  # Exponential backoff
        }

        $attempt++
    }

    throw "Winget command failed after $MaxAttempts attempts"
}
#endregion

#region Script
try {
    Write-Log "=== Starting winget detection for package: $ID ===" -Level Info

    # Check network connectivity if enabled
    if ($CheckNetworkConnectivity) {
        Write-Log "Checking network connectivity..." -Level Info
        if (-not (Test-NetworkConnectivity)) {
            Write-Log "No network connectivity detected. Cannot check for updates." -Level Warning
            exit 0  # Don't trigger remediation if offline
        }
        Write-Log "Network connectivity confirmed" -Level Info
    }

    # Locate winget executable
    Write-Log "Locating winget executable..." -Level Info
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop

    if ($wingetexe.Count -gt 1) {
        $SystemContext = $wingetexe[-1].Path
        Write-Log "Found multiple winget installations, using latest: $SystemContext" -Level Info
    } else {
        $SystemContext = $wingetexe.Path
        Write-Log "Found winget: $SystemContext" -Level Info
    }

    New-Alias -Name sysget -Value "$SystemContext" -Force

    # Get package information with retry logic
    Write-Log "Querying package information for: $ID" -Level Info
    $packageInfo = Invoke-WingetWithRetry -Arguments "list --accept-source-agreements --Id $ID"

    # Auto-detect name if not provided
    if (-not $name) {
        $nameMatch = $packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d"
        if ($nameMatch) {
            $name = $nameMatch.Matches[0].Groups[2].Value.Trim()
            Write-Log "Auto-detected application name: $name" -Level Info
        } else {
            $name = $ID
            Write-Log "Could not auto-detect name, using ID: $name" -Level Warning
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
        Write-Host "Application update available for $name. Current: $verInstalled, Available: $verAvailable"

        [pscustomobject] @{
            Name = $name
            InstalledVersion = $verInstalled
            AvailableVersion = $verAvailable
            Status = "UpdateAvailable"
        }

        exit 1  # Trigger remediation
    } else {
        # No update available
        if ($packageInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $packageInfo[-1])[-2]
            Write-Log "$name is up to date (version $versionInstalled)" -Level Info
            Write-Host "$name is already up to date (version $versionInstalled)"

            [pscustomobject] @{
                Name = $name
                InstalledVersion = $versionInstalled
                Status = "UpToDate"
            }

            exit 0  # No action needed
        } else {
            Write-Log "$name appears to be installed but version info could not be parsed" -Level Warning
            Write-Host "$name is installed but version could not be determined"
            exit 0
        }
    }

} catch {
    $errMsg = $_.Exception.Message
    Write-Log "ERROR: Failed to check $name for updates: $errMsg" -Level Error
    Write-Error "Failed to check $name for updates: $errMsg"
    exit 0  # Don't trigger remediation on error
} finally {
    Write-Log "=== Detection script completed ===" -Level Info
}
#endregion
