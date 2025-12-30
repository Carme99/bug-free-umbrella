<#
.SYNOPSIS
    Force close winget update script that automatically closes the app before updating.

.DESCRIPTION
    This template checks if an app update is available and installs it.
    If the app is running, it will forcefully close the app before updating.

.NOTES
    REQUIRED: Only the winget ID is required. The script will auto-detect app name and process.
    WARNING: This will force close the application without saving user work!

.CONFIGURATION
    1. Set the $ID variable to your winget package ID
    2. (Optional) Customize $name if you want a specific display name
    3. (Optional) Set $AppProcess if auto-detection doesn't work
    4. (Optional) Adjust $GracePeriodSeconds for app shutdown time

.EXAMPLE
    # For TeamViewer, you only need to set:
    $ID = 'TeamViewer.TeamViewer'

    # The script will automatically:
    # - Detect name: "TeamViewer"
    # - Detect process: "TeamViewer"
    # - Close the app if running
    # - Install the update
#>

#region Configuration
# ===== REQUIRED: Set your winget package ID =====
$ID = 'WINGETID'  # Example: 'TeamViewer.TeamViewer', 'Mozilla.Firefox', 'OBSProject.OBSStudio'

# ===== OPTIONAL: Customize these if needed =====
$name = $null                   # Leave as $null to auto-detect from winget, or set manually: 'TeamViewer'
$AppProcess = $null             # Leave as $null to auto-detect, or set manually: 'TeamViewer'
$GracePeriodSeconds = 5         # Time to wait after closing app before updating
$VerifyWaitSeconds = 10         # Time to wait after update to verify installation
#endregion

#region Script - DO NOT MODIFY BELOW THIS LINE
try {
    # Locate winget executable
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction Stop
    $SystemContext = $wingetexe[-1].Path
    New-Alias -Name sysget -Value "$SystemContext" -Force

    # Get package information
    $packageInfo = sysget list --accept-source-agreements --Id $ID 2>$null

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
        Write-Host "$name is not installed on this device."
        exit 0
    }

    # Auto-detect process name if not provided
    if (-not $AppProcess) {
        # Extract process name from package ID (e.g., 'TeamViewer.TeamViewer' -> 'TeamViewer')
        $AppProcess = ($ID -split '\.')[-1]
    }

    # Check if app is running and force close if needed
    $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "$name is running. Force closing application..."
        Stop-Process -Name "$AppProcess" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds $GracePeriodSeconds

        # Verify process was closed
        $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
        if ($process) {
            Write-Warning "$name process still running after force close attempt. Retrying..."
            Stop-Process -Name "$AppProcess" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        Write-Host "$name closed successfully."
    } else {
        Write-Host "$name is not currently running."
    }

    # Check if update is available
    if ($packageInfo -match '\bVersion\s+Available\b') {
        $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3,-2]
        Write-Host "Update available for $name : $verInstalled -> $verAvailable"

        # Perform upgrade
        Write-Host "Installing $name update..."
        sysget upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements

        # Wait for installation to complete
        Start-Sleep -Seconds $VerifyWaitSeconds

        # Verify installation
        $verifyInfo = sysget list --accept-source-agreements --Id $ID
        if ($verifyInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $verifyInfo[-1])[-2]
            Write-Host "$name updated successfully to version $versionInstalled"
            [pscustomobject] @{
                Name = $name
                PreviousVersion = $verInstalled
                InstalledVersion = $versionInstalled
                Status = "Force Updated Successfully"
            }
            exit 0
        } else {
            Write-Error "Failed to verify $name installation after update."
            exit 1
        }
    } else {
        # No update available
        if ($packageInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $packageInfo[-1])[-2]
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
    Write-Error "Failed to update $name : $errMsg"
    exit 1
}
#endregion
