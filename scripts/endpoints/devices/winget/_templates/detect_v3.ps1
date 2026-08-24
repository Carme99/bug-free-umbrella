<#
.SYNOPSIS
    Enhanced winget update detection script for Intune Proactive Remediations (V3).

.DESCRIPTION
    Checks whether the configured package is installed and whether an update is available,
    preferring the Microsoft.WinGet.Client PowerShell module (the winget CLI is NOT supported in the
    SYSTEM context that Intune Proactive Remediations runs in) and falling back to the winget.exe
    CLI only when the module is unavailable.
    V3 enhancements retained: configurable retry logic with exponential backoff, optional file
    logging, network connectivity validation, and detailed status reporting.
    Exit codes: 1 = update available (triggers remediation); 0 = up to date, package not installed,
    offline (when network checking is enabled), or unexpected error (an error must not trigger
    remediation).
    Only the winget ID is required; the application display name is auto-detected from winget when
    the optional $name configuration value is left empty.

.EXAMPLE
    PS C:\> .\detect_v3.ps1

    Runs the enhanced detection using the package ID and advanced settings configured in the
    Configuration region.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\detect_v3.ps1

    Runs the script in a clean PowerShell process; exit-code semantics are unchanged.

.NOTES
    File Name  : detect_v3.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 5.1+ (run in the Intune Proactive Remediation context)
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

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
$NetworkProbeHost = 'www.microsoft.com'  # Host used by the network connectivity check
#endregion

#region Functions
function Write-DetectionLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"

    # Always write to console using the mandated prefixed output convention.
    switch ($Level) {
        'Error' { Write-Host "[-] $Message" -ForegroundColor Red }
        'Warning' { Write-Host "[!] $Message" -ForegroundColor Yellow }
        'Info' { Write-Host "[*] $Message" -ForegroundColor Cyan }
    }

    # Optionally write to file
    if ($EnableLogging) {
        try {
            $logDir = Split-Path -Path $LogPath -Parent
            if (-not (Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
            Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
        }
    }
}

function Test-NetworkConnectivity {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $testConnection = Test-Connection -ComputerName $NetworkProbeHost -Count 1 -Quiet -ErrorAction SilentlyContinue
        return $testConnection
    }
    catch {
        return $false
    }
}

function Wait-RetryDelay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Seconds
    )

    # Injectable delay seam: tests set $RetryDelaySeconds to 0 so no sleeping occurs; a zero or
    # negative delay skips Start-Sleep entirely.
    if ($Seconds -gt 0) {
        Start-Sleep -Seconds $Seconds
    }
}

function Invoke-WingetCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WingetPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Arguments
    )

    # Thin wrapper seam: winget.exe is a native executable that Pester cannot mock, so every CLI
    # invocation goes through this function (tests mock the wrapper instead).
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $WingetPath
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
        if ($stderr) { Write-DetectionLog "Winget stderr: $stderr" -Level Warning }
        return $stdout
    }

    throw "winget.exe exited with code 0x$($p.ExitCode.ToString('X8'))"
}

function Invoke-WingetWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Arguments,

        [int]$MaxAttempts = $MaxRetries
    )

    $wingetGlob = 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe'
    $wingetexe = Resolve-Path $wingetGlob -ErrorAction Stop
    $wingetPath = if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }

    $attempt = 1
    $delay = $RetryDelaySeconds

    while ($attempt -le $MaxAttempts) {
        try {
            Write-DetectionLog "Executing winget command (attempt $attempt/$MaxAttempts): $Arguments" -Level Info
            return (Invoke-WingetCli -WingetPath $wingetPath -Arguments $Arguments)
        }
        catch {
            Write-DetectionLog "Winget command failed on attempt $attempt : $($_.Exception.Message)" -Level Warning
        }

        if ($attempt -lt $MaxAttempts) {
            Write-DetectionLog "Waiting $delay seconds before retry..." -Level Info
            Wait-RetryDelay -Seconds $delay
            $delay = $delay * 2  # Exponential backoff
        }

        $attempt++
    }

    throw "Winget command failed after $MaxAttempts attempts"
}

function Invoke-WingetPackageLookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Id
    )

    # Thin wrapper seam around the Microsoft.WinGet.Client cmdlet so tests can mock this function.
    return (Get-WinGetPackage -Id $Id -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue)
}
#endregion

#region Script
function Main {
    try {
        Write-DetectionLog "=== Starting winget detection for package: $ID ===" -Level Info

        # Check network connectivity if enabled
        if ($CheckNetworkConnectivity) {
            Write-DetectionLog "Checking network connectivity..." -Level Info
            if (-not (Test-NetworkConnectivity)) {
                Write-DetectionLog "No network connectivity detected. Cannot check for updates." -Level Warning
                return 0  # Don't trigger remediation if offline
            }
            Write-DetectionLog "Network connectivity confirmed" -Level Info
        }

        # Prefer the Microsoft.WinGet.Client PowerShell module - the winget CLI is NOT supported in
        # the SYSTEM context (Intune Proactive Remediations run as SYSTEM). Only fall back to the
        # winget.exe CLI when the module is unavailable.
        # Reference: https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
        if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
            try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop }
            catch { Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false }

            if (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue) {
                Write-DetectionLog "Using Microsoft.WinGet.Client module" -Level Info

                # Get package information (exact ID match)
                $package = Invoke-WingetPackageLookup -Id $ID

                # Auto-detect name if not provided
                if (-not $name) {
                    $name = if ($package.Name) { $package.Name } else { $ID }
                }

                # Check if package is installed
                if (-not $package) {
                    Write-DetectionLog "$name is not installed on this device." -Level Info
                    Write-Host "[+] $name is not installed on this device." -ForegroundColor Green
                    return 0
                }

                # Check if update is available
                if ($package.IsUpdateAvailable) {
                    $verInstalled = $package.InstalledVersion
                    $verAvailable = $package.AvailableVersions | Select-Object -Last 1
                    $detail = "Update available for $name | Installed: $verInstalled | Available: $verAvailable"
                    Write-DetectionLog $detail -Level Info
                    $msg = "Update available for $name (current: $verInstalled, available: $verAvailable)"
                    Write-Host "[!] $msg" -ForegroundColor Yellow
                    return 1
                }

                # No update available
                $versionInstalled = $package.InstalledVersion
                Write-DetectionLog "$name is already up to date (version $versionInstalled)" -Level Info
                Write-Host "[+] $name is already up to date (version $versionInstalled)." -ForegroundColor Green
                return 0
            }
        }

        # Fallback: winget.exe CLI (only reached when the Microsoft.WinGet.Client module is unavailable)
        Write-DetectionLog "Microsoft.WinGet.Client module unavailable, falling back to winget.exe CLI" -Level Warning

        # Get package information with retry logic (exact ID match)
        Write-DetectionLog "Querying package information for: $ID" -Level Info
        $packageInfo = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"

        # Auto-detect name if not provided
        if (-not $name) {
            $nameMatch = $packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d"
            if ($nameMatch) {
                $name = $nameMatch.Matches[0].Groups[2].Value.Trim()
                Write-DetectionLog "Auto-detected application name: $name" -Level Info
            }
            else {
                $name = $ID
                Write-DetectionLog "Could not auto-detect name, using ID: $name" -Level Warning
            }
        }

        # Check if package is installed
        if ($packageInfo -match 'No installed package found matching input criteria') {
            Write-DetectionLog "$name is not installed on this device." -Level Info
            Write-Host "[+] $name is not installed on this device." -ForegroundColor Green
            return 0
        }

        # Check if update is available
        if ($packageInfo -match '\bVersion\s+Available\b') {
            $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3, -2]
            $detail = "Update available for $name | Installed: $verInstalled | Available: $verAvailable"
            Write-DetectionLog $detail -Level Info
            $msg = "Update available for $name (current: $verInstalled, available: $verAvailable)"
            Write-Host "[!] $msg" -ForegroundColor Yellow
            return 1
        }
        elseif ($packageInfo -match '\d+(\.\d+)+') {
            # No update available
            $versionInstalled = (-split $packageInfo[-1])[-2]
            Write-DetectionLog "$name is up to date (version $versionInstalled)" -Level Info
            Write-Host "[+] $name is already up to date (version $versionInstalled)." -ForegroundColor Green
            return 0
        }
        else {
            Write-DetectionLog "$name appears to be installed but version info could not be parsed" -Level Warning
            Write-Host "[!] $name is installed but its version could not be determined." -ForegroundColor Yellow
            return 0
        }
    }
    catch {
        # Documented semantics: an unexpected error must not trigger remediation.
        Write-DetectionLog "ERROR: Failed to check $name for updates: $($_.Exception.Message)" -Level Error
        return 0
    }
    finally {
        Write-DetectionLog "=== Detection script completed ===" -Level Info
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
#endregion
