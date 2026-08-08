<#
.SYNOPSIS
    Enhanced winget update detection script for Intune Proactive Remediations (V3).

.DESCRIPTION
    This template checks if an app update is available with enhanced features:
    - Prefers the Microsoft.WinGet.Client PowerShell module (the winget CLI is NOT
      supported in the SYSTEM context that Intune Proactive Remediations run in)
    - Falls back to the winget.exe CLI only when the module is unavailable
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
    - Microsoft.WinGet.Client module preferred over the winget.exe CLI (SYSTEM context safe)

.CONFIGURATION
    1. Set the $ID variable to your winget package ID
    2. (Optional) Customize retry, logging, and other advanced settings

.EXAMPLE
    # For your application:
    $ID = 'Adobe.Acrobat.Reader.32-bit'

    # Enable logging:
    $EnableLogging = $true
    $LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetDetection.log"
#>

#region Configuration
# ===== REQUIRED: Set your winget package ID =====
$ID = 'Adobe.Acrobat.Reader.32-bit'  # Example: 'Google.Chrome', 'Microsoft.Teams', 'Slack.Slack'

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

            # Drain BOTH output streams before waiting so a full stderr pipe cannot deadlock the child.
            $stdout = $p.StandardOutput.ReadToEnd()
            $stderr = $p.StandardError.ReadToEnd()
            $p.WaitForExit()

            # Base success on the process exit code, not on a grep of stdout.
            # Success: 0 (S_OK), 0x8A150014 (no packages found - "not installed" for list),
            # 0x8A150109 (install succeeded, reboot required).
            # Reference: https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md
            if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 0x8A150014 -or $p.ExitCode -eq 0x8A150109) {
                Write-Log "Winget command succeeded on attempt $attempt (exit code 0x$($p.ExitCode.ToString('X8')))" -Level Info
                if ($stderr) { Write-Log "Winget stderr: $stderr" -Level Warning }
                return $stdout
            }

            Write-Log "Winget command exited with code 0x$($p.ExitCode.ToString('X8')) on attempt $attempt" -Level Warning
            if ($stderr) { Write-Log "Winget stderr: $stderr" -Level Warning }
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

    # Prefer the Microsoft.WinGet.Client PowerShell module - the winget CLI is NOT supported in
    # the SYSTEM context (Intune Proactive Remediations run as SYSTEM). Only fall back to the
    # winget.exe CLI when the module is unavailable.
    # Reference: https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
    if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
        try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop } catch { }
        if (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue) {
            Write-Log "Using Microsoft.WinGet.Client module" -Level Info

            # Get package information (exact ID match)
            $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue

            # Auto-detect name if not provided
            if (-not $name) {
                $name = if ($package.Name) { $package.Name } else { $ID }
            }

            # Check if package is installed
            if (-not $package) {
                Write-Log "$name is not installed on this device." -Level Info
                Write-Host "$name is not installed on this device."
                exit 0
            }

            # Check if update is available
            if ($package.IsUpdateAvailable) {
                $verInstalled = $package.InstalledVersion
                $verAvailable = $package.AvailableVersions | Select-Object -Last 1
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
                $versionInstalled = $package.InstalledVersion
                Write-Log "$name is already up to date (version $versionInstalled)" -Level Info
                Write-Host "$name is already up to date (version $versionInstalled)"

                [pscustomobject] @{
                    Name = $name
                    InstalledVersion = $versionInstalled
                    Status = "UpToDate"
                }

                exit 0  # No action needed
            }
        }
    }

    # Fallback: winget.exe CLI (only reached when the Microsoft.WinGet.Client module is unavailable)
    Write-Log "Microsoft.WinGet.Client module unavailable, falling back to winget.exe CLI" -Level Warning

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

    # Get package information with retry logic (exact ID match)
    Write-Log "Querying package information for: $ID" -Level Info
    $packageInfo = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"

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
