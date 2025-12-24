<#
.SYNOPSIS
    Enhanced standard winget update script with retry logic and logging (V3).

.DESCRIPTION
    This template checks if an app update is available and installs it.
    If the app is running, it will skip the update and retry later.

    V3 ENHANCEMENTS:
    - Retry logic with exponential backoff
    - Optional logging to file
    - Better error handling and status reporting
    - Configurable wait times
    - Pre/post update hooks

.NOTES
    REQUIRED: Only the winget ID is required. The script will auto-detect app name and process.

.CONFIGURATION
    1. Set the $ID variable to your winget package ID
    2. (Optional) Enable logging and customize retry settings
    3. (Optional) Define pre/post update hooks for custom actions

.EXAMPLE
    # For Google Chrome with logging enabled:
    $ID = 'Google.Chrome'
    $EnableLogging = $true
#>

#region Configuration
# ===== REQUIRED: Set your winget package ID =====
$ID = 'WINGETID'  # Example: 'Google.Chrome', 'Microsoft.Teams', 'Slack.Slack'

# ===== OPTIONAL: Basic Settings =====
$name = $null           # Leave as $null to auto-detect from winget
$AppProcess = $null     # Leave as $null to auto-detect from package ID

# ===== OPTIONAL: Advanced Settings =====
$MaxRetries = 3                    # Number of retry attempts for winget operations
$RetryDelaySeconds = 2             # Initial delay between retries (doubles each retry)
$VerifyWaitSeconds = 5             # Time to wait after update before verification
$EnableLogging = $false            # Set to $true to enable file logging
$LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetRemediation_$ID.log"  # Log file path

# ===== OPTIONAL: Hooks for Custom Actions =====
$PreUpdateScriptBlock = $null      # Script block to run before update (e.g., { Stop-Service MyService })
$PostUpdateScriptBlock = $null     # Script block to run after update (e.g., { Start-Service MyService })
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
        } catch {
            # Fail silently if logging doesn't work
        }
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
    Write-Log "=== Starting winget remediation for package: $ID ===" -Level Info

    # Locate winget executable
    Write-Log "Locating winget executable..." -Level Info
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop

    if ($wingetexe.Count -gt 1) {
        $SystemContext = $wingetexe[-1].Path
    } else {
        $SystemContext = $wingetexe.Path
    }

    New-Alias -Name sysget -Value "$SystemContext" -Force
    Write-Log "Found winget: $SystemContext" -Level Info

    # Get package information
    Write-Log "Querying package information for: $ID" -Level Info
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

        # Check if app is running
        $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
        if ($process) {
            Write-Log "$name is currently running. Skipping update - will retry later." -Level Warning
            Write-Host "$name is currently running. Will try again later."
            [pscustomobject] @{
                Name = $name
                InstalledVersion = $verInstalled
                AvailableVersion = $verAvailable
                Status = "Skipped - App Running"
            }
            exit 1
        }

        Write-Log "$name is not running. Proceeding with update..." -Level Info

        # Execute pre-update hook if defined
        if ($PreUpdateScriptBlock) {
            Write-Log "Executing pre-update hook..." -Level Info
            try {
                & $PreUpdateScriptBlock
                Write-Log "Pre-update hook completed successfully" -Level Info
            } catch {
                Write-Log "Pre-update hook failed: $($_.Exception.Message)" -Level Warning
            }
        }

        # Perform upgrade with retry logic
        Write-Log "Installing $name update ($verInstalled -> $verAvailable)..." -Level Info
        Write-Host "Installing $name update ($verInstalled -> $verAvailable)..."

        $upgradeResult = Invoke-WingetWithRetry -Arguments "upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements"

        # Wait for installation to complete
        Write-Log "Waiting $VerifyWaitSeconds seconds for installation to complete..." -Level Info
        Start-Sleep -Seconds $VerifyWaitSeconds

        # Execute post-update hook if defined
        if ($PostUpdateScriptBlock) {
            Write-Log "Executing post-update hook..." -Level Info
            try {
                & $PostUpdateScriptBlock
                Write-Log "Post-update hook completed successfully" -Level Info
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
                Status = "Updated Successfully"
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
