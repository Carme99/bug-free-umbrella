<#
.SYNOPSIS
    Detects pending updates for the C++ 2008 Redistributable (Microsoft.VCRedist.2010.x86).

.DESCRIPTION
    Detection half of the C++ 2008 Redistributable update pair. Checks whether a redistributable
    update is available and exits non-compliant so remediation can be triggered. Prefers the
    Microsoft.WinGet.Client PowerShell module because the winget CLI is not supported in the SYSTEM
    context that Intune Proactive Remediations use; when the module is unavailable it falls back to
    the winget.exe CLI through the Invoke-WingetWithRetry wrapper (the only place a native
    executable is called).
    A network connectivity check runs first; when offline the check reports compliant because no
    update query is possible, and any internal error also reports compliant so remediation is
    never falsely triggered.
    Exit codes:
    - 0: compliant - the package is up to date, not installed, the device is offline, or the check failed.
    - 1: non-compliant - an application update is available.

.NOTES
    File Name: Test-WingetCpp2010Redist.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Test-WingetCpp2010Redist.ps1
    Runs the detection check and exits 0 when the package is up to date or absent, 1 when an update is available.

.EXAMPLE
    PS C:\> & 'C:\Program Files\IntuneScripts\Test-WingetCpp2010Redist.ps1'
    Runs the same check from Intune Management Extension under the SYSTEM context.
#>

[CmdletBinding()]

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

#region Configuration
$ID = 'Microsoft.VCRedist.2010.x86'
$MaxRetries = 3
$CheckNetworkConnectivity = $true
$ConnectivityHost = 'www.microsoft.com'  # Host used by the network connectivity check

# Advanced settings
$RetryDelaySeconds = 2              # Initial delay between retries
$EnableLogging = $false             # Set to $true to enable file logging
$LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetDetection_$ID.log"
#endregion

#region Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes a timestamped message to the console and, optionally, to a log file.
    #>
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'Error' { Write-Host "[-] $Message" -ForegroundColor Red }
        'Warning' { Write-Host "[!] $Message" -ForegroundColor Yellow }
        'Info' { Write-Host $Message }
    }

    if ($EnableLogging) {
        try {
            $logDir = Split-Path -Path $LogPath -Parent
            if (-not (Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
            Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose "Handled exception: $($_.Exception.Message)"
        }
    }
}

function Test-NetworkConnectivity {
    <#
    .SYNOPSIS
        Thin wrapper around the native Test-Connection ping used for connectivity validation.
    #>
    try {
        return (Test-Connection -ComputerName $ConnectivityHost -Count 1 -Quiet -ErrorAction SilentlyContinue)
    }
    catch {
        return $false
    }
}

function Invoke-WingetWithRetry {
    <#
    .SYNOPSIS
        Thin wrapper around the native winget.exe CLI with bounded retries and exponential backoff.
    #>
    param(
        [string]$Arguments,
        [int]$MaxAttempts = $MaxRetries
    )

    $wingetPathFilter = 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe'
    $wingetexe = Resolve-Path -Path $wingetPathFilter -ErrorAction Stop
    $wingetPath = if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }

    $attempt = 1
    $delay = $RetryDelaySeconds

    while ($attempt -le $MaxAttempts) {
        try {
            $outputMsg = "Executing winget command (Attempt $attempt/$MaxAttempts): $wingetPath $Arguments"
            Write-Log $outputMsg -Level Info

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
            # Reference: https://github.com/microsoft/winget-cli/blob/master/doc/
            # windows/package-manager/winget/returnCodes.md
            if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 0x8A150014 -or $p.ExitCode -eq 0x8A150109) {
                $outputMsg = "Winget command succeeded on attempt $attempt (exit code 0x$($p.ExitCode.ToString('X8')))"
                Write-Log $outputMsg -Level Info
                if ($stderr) { Write-Log "Winget stderr: $stderr" -Level Warning }
                return $stdout
            }

            $outputMsg = "Winget command exited with code 0x$($p.ExitCode.ToString('X8')) on attempt $attempt"

            Write-Log $outputMsg -Level Warning
            if ($stderr) { Write-Log "Winget stderr: $stderr" -Level Warning }
        }
        catch {
            $outputMsg = "Winget command failed on attempt $attempt : $($_.Exception.Message)"
            Write-Log $outputMsg -Level Warning
        }

        if ($attempt -lt $MaxAttempts) {
            $outputMsg = "Waiting $delay seconds before retry..."
            Write-Log $outputMsg -Level Info
            Start-Sleep -Seconds $delay
            $delay = $delay * 2  # Exponential backoff
        }

        $attempt++
    }

    throw "Winget command failed after $MaxAttempts attempts"
}

function Main {
    try {
        $outputMsg = "=== Starting winget detection for package: $ID ==="
        Write-Log $outputMsg -Level Info

        # Check network connectivity if enabled
        if ($CheckNetworkConnectivity) {
            $outputMsg = "Checking network connectivity..."
            Write-Log $outputMsg -Level Info
            if (-not (Test-NetworkConnectivity)) {
                $outputMsg = "[!] No network connectivity detected. Cannot check for updates."
                Write-Host $outputMsg -ForegroundColor Yellow
                return 0  # Don't trigger remediation if offline
            }
            $outputMsg = "Network connectivity confirmed"
            Write-Log $outputMsg -Level Info
        }

        # Prefer the Microsoft.WinGet.Client PowerShell module - the winget CLI is NOT supported in
        # the SYSTEM context (Intune Proactive Remediations run as SYSTEM). Only fall back to the
        # winget.exe CLI when the module is unavailable.
        # Reference: https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
        if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
            try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop }
            catch { Write-Verbose "Handled exception: $($_.Exception.Message)" }
            if (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue) {
                $outputMsg = "Using Microsoft.WinGet.Client module"
                Write-Log $outputMsg -Level Info

                # Get package information (exact ID match)
                $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue

                # Check if package is installed
                if (-not $package) {
                    $outputMsg = "[+] $ID is not installed on this device."
                    Write-Host $outputMsg -ForegroundColor Green
                    return 0
                }

                # Check if update is available
                if ($package.IsUpdateAvailable) {
                    $verInstalled = $package.InstalledVersion
                    $verAvailable = $package.AvailableVersions | Select-Object -Last 1
                    $outputMsg = "Update available | Installed: $verInstalled | Available: $verAvailable"
                    Write-Log $outputMsg -Level Info
                    $updateMsg = "[!] Application update available for $($package.Name). " +
                        "Current: $verInstalled, Available: $verAvailable"
                    Write-Host $updateMsg -ForegroundColor Yellow

                    [pscustomobject] @{
                        Name             = $package.Name
                        InstalledVersion = $verInstalled
                        AvailableVersion = $verAvailable
                        Status           = 'UpdateAvailable'
                    }

                    return 1  # Trigger remediation
                }

                # No update available
                $versionInstalled = $package.InstalledVersion
                $outputMsg = "$($package.Name) is already up to date (version $versionInstalled)"
                Write-Log $outputMsg -Level Info
                $upToDateMsg = "[+] $($package.Name) is already up to date (version $versionInstalled)."
                Write-Host $upToDateMsg -ForegroundColor Green

                [pscustomobject] @{
                    Name             = $package.Name
                    InstalledVersion = $versionInstalled
                    Status           = 'UpToDate'
                }

                return 0  # No action needed
            }
        }

        # Fallback: winget.exe CLI path via the wrapper function.
        $outputMsg = "Microsoft.WinGet.Client module unavailable, falling back to winget.exe CLI"
        Write-Log $outputMsg -Level Warning

        $packageInfo = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"
        $name = if ($packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d") { $Matches[2].Trim() } else { $ID }

        # Check if package is installed
        if ($packageInfo -match 'No installed package found') {
            $outputMsg = "[+] $name not installed."
            Write-Host $outputMsg -ForegroundColor Green
            return 0
        }

        # Check if update is available
        if ($packageInfo -match '\bVersion\s+Available\b') {
            $v = (-split $packageInfo[-1])[-3, -2]
            $outputMsg = "[!] Update available: $($v[0]) -> $($v[1])"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1  # Trigger remediation
        }

        $outputMsg = "[+] $name is up to date."
        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        # Preserve original behavior: a failed detection must never trigger false remediation.
        $outputMsg = "[-] Failed to check ${ID} for updates: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 0
    }
    finally {
        $outputMsg = "=== Detection script completed ==="
        Write-Log $outputMsg -Level Info
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
