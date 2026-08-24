<#
.SYNOPSIS
    Detects pending updates for TeamViewer Full (winget id TeamViewer.TeamViewer) for Intune Proactive Remediations.

.DESCRIPTION
    Detection half of the TeamViewer Full update pair. Checks whether a TeamViewer Full update is available and
    exits non-compliant so remediation can be triggered. Prefers the Microsoft.WinGet.Client
    PowerShell module because the winget CLI is not supported in the SYSTEM context that Intune
    Proactive Remediations use; when the module is unavailable it falls back to the winget.exe CLI
    through the Invoke-WingetWithRetry wrapper (the only place a native executable is called).
    A network connectivity check runs first; when offline the check reports compliant because no
    update query is possible, and any internal error also reports compliant so remediation is
    never falsely triggered.
    Exit codes:
    - 0: compliant - TeamViewer Full is up to date, not installed, the device is offline, or the check failed.
    - 1: non-compliant - an application update is available.

.NOTES
    File Name: Test-WingetTeamViewerFull.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Test-WingetTeamViewerFull.ps1
    Runs the detection check and exits 0 when TeamViewer Full is up to date or absent, 1 when an update is available.

.EXAMPLE
    PS C:\> & 'C:\Program Files\IntuneScripts\Test-WingetTeamViewerFull.ps1'
    Runs the same check from Intune Management Extension under the SYSTEM context.
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

#region Configuration
$ID = 'TeamViewer.TeamViewer'
$ConnectivityHost = 'www.microsoft.com'
$MaxRetries = 3
$CheckNetworkConnectivity = $true
#endregion

#region Functions

# Spec-mandated console output convention ([+]/[!]/[-]/[*] prefixes); file logging intentionally unused.
function Write-Log {
    <#
    .SYNOPSIS
        Writes a prefixed, leveled message to the console.
    #>
    [CmdletBinding()]
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    switch ($Level) {
        'Error' { Write-Host "[-] $Message" -ForegroundColor Red }
        'Warning' { Write-Host "[!] $Message" -ForegroundColor Yellow }
        'Info' { Write-Host $Message }
    }
}

function Test-NetworkConnectivity {
    <#
    .SYNOPSIS
        Thin wrapper around the native Test-Connection ping used for connectivity validation.
    #>
    [CmdletBinding()]
    param()

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
        Thin wrapper around the native winget.exe CLI with bounded retries.
    #>
    [CmdletBinding()]
    param(
        [string]$Arguments,
        [int]$MaxAttempts = $MaxRetries
    )

    $wingetPathFilter = 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe'
    $wingetexe = Resolve-Path -Path $wingetPathFilter -ErrorAction Stop
    $wingetPath = if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }

    $attempt = 1
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

            # Base success on the process exit code, not on stdout content.
            # Success: 0 (S_OK), 0x8A150014 (no packages found - "not installed" for list),
            # 0x8A150109 (install succeeded, reboot required).
            # Reference: https://github.com/microsoft/winget-cli/blob/master/doc/
            # windows/package-manager/winget/returnCodes.md
            if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 0x8A150014 -or $p.ExitCode -eq 0x8A150109) {
                if ($stderr) { Write-Verbose "Winget stderr: $stderr" }
                return $stdout
            }

            $outputMsg = "Winget command exited with code 0x$($p.ExitCode.ToString('X8')) on attempt $attempt"
            Write-Log $outputMsg -Level Warning
            if ($stderr) { Write-Verbose "Winget stderr: $stderr" }
        }
        catch {
            $outputMsg = "Winget command failed on attempt $attempt : $($_.Exception.Message)"
            Write-Log $outputMsg -Level Warning
        }

        if ($attempt -lt $MaxAttempts) {
            Start-Sleep -Seconds 2
        }

        $attempt++
    }

    throw "Failed to execute winget after $MaxRetries attempts"
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

                $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive `
                    -ErrorAction SilentlyContinue

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
                    $updateMsg = "[!] Application update available for $($package.Name). " +
                        "Current: $verInstalled, Available: $verAvailable"
                    Write-Host $updateMsg -ForegroundColor Yellow

                    [pscustomobject] @{
                        Name             = $package.Name
                        InstalledVersion = $verInstalled
                        AvailableVersion = $verAvailable
                    }

                    return 1  # Trigger remediation
                }

                # No update available
                $outputMsg = "[+] $($package.Name) is already up to date (version $($package.InstalledVersion))."
                Write-Host $outputMsg -ForegroundColor Green
                return 0
            }
        }

        # Fallback: winget.exe CLI path via the wrapper function.
        $outputMsg = "Microsoft.WinGet.Client module unavailable, falling back to winget.exe CLI"
        Write-Log $outputMsg -Level Warning

        $packageInfo = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"

        $name = if ($packageInfo -match "^(TeamViewer\.TeamViewer)\s+(.+?)\s+\d") { $Matches[2].Trim() } else { $ID }

        # Check if package is installed
        if ($packageInfo -match "No installed package found") {
            $outputMsg = "[+] $name is not installed on this device."
            Write-Host $outputMsg -ForegroundColor Green
            return 0
        }

        # Check if update is available
        if ($packageInfo -match '\bVersion\s+Available\b') {
            $v = (-split $packageInfo[-1])[-3, -2]
            $outputMsg = "[!] Application update available. Current: $($v[0]), Available: $($v[1])"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1  # Trigger remediation
        }

        # No update available
        $outputMsg = "[+] $name is already up to date."
        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        # Detection must stay fail-safe: any internal error reports compliant so remediation
        # is never falsely triggered.
        $outputMsg = "[-] Detection check failed: $($_.Exception.Message)"
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
