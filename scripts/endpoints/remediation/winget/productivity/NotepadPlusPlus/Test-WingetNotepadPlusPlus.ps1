<#
.SYNOPSIS
    Detects pending updates for Notepad++ (winget id Notepad++.Notepad++).

.DESCRIPTION
    Detection half of the Notepad++ update pair. Prefers the Microsoft.WinGet.Client PowerShell
    module because the winget CLI is not supported in the SYSTEM context that Intune Proactive
    Remediations use; when the module is unavailable it falls back to the winget.exe CLI through
    the Invoke-WingetWithRetry wrapper (the only place a native executable is called).
    Exit codes:
    - 0: compliant - Notepad++ is up to date, not installed, its version could not be parsed, or
      the check could not run (network down or transient winget failure); failures deliberately
      exit 0 so remediation is never falsely triggered.
    - 1: non-compliant - an application update is available.

.EXAMPLE
    PS C:\> .\Test-WingetNotepadPlusPlus.ps1
    Runs the detection check and exits 0 when Notepad++ is up to date or absent, 1 when an update is available.

.EXAMPLE
    PS C:\> & 'C:\Program Files\IntuneScripts\Test-WingetNotepadPlusPlus.ps1'
    Runs the same check from Intune Management Extension under the SYSTEM context.

.NOTES
    File Name: Test-WingetNotepadPlusPlus.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]
# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

#region Configuration
$ID = 'Notepad++.Notepad++'
$ConnectivityHost = 'www.microsoft.com'
$MaxRetries = 3
$EnableLogging = $false
$LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetDetection_$ID.log"
$CheckNetworkConnectivity = $true
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

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
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
        Thin wrapper around the native winget.exe CLI with bounded retries.
    #>
    param([string]$Arguments)

    $wingetPathFilter = 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe'
    $wingetexe = Resolve-Path -Path $wingetPathFilter -ErrorAction Stop
    $wingetPath = if ($wingetexe.Count -gt 1) { $wingetexe[-1].Path } else { $wingetexe.Path }
    $attempt = 1
    while ($attempt -le $MaxRetries) {
        try {
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = $wingetPath
            $processInfo.Arguments = $Arguments
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.UseShellExecute = $false
            $processInfo.CreateNoWindow = $true
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processInfo
            $process.Start() | Out-Null

            # Drain BOTH output streams before waiting so a full stderr pipe cannot deadlock the child.
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()

            # Base success on the process exit code, not on stdout content.
            # Success: 0 (S_OK), 0x8A150014 (no packages found - "not installed" for list),
            # 0x8A150109 (install succeeded, reboot required).
            # Reference: https://github.com/microsoft/winget-cli/blob/master/doc/
            # windows/package-manager/winget/returnCodes.md
            if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 0x8A150014 -or $process.ExitCode -eq 0x8A150109) {
                return $stdout
            }

            Write-Verbose "Winget exited with code 0x$($process.ExitCode.ToString('X8')) on attempt $attempt"
        }
        catch {
            Write-Verbose "Handled exception: $($_.Exception.Message)"
        }
        Start-Sleep -Seconds 2
        $attempt++
    }
    throw "Failed to execute winget after $MaxRetries attempts"
}

function Main {
    try {
        $outputMsg = "[*] Checking $ID for available updates..."
        Write-Host $outputMsg -ForegroundColor Cyan

        if ($CheckNetworkConnectivity -and -not (Test-NetworkConnectivity)) {
            $outputMsg = "[!] Network connectivity unavailable; skipping update check."
            Write-Host $outputMsg -ForegroundColor Yellow
            return 0
        }

        # Prefer the Microsoft.WinGet.Client PowerShell module - the winget CLI is NOT supported in
        # the SYSTEM context (Intune Proactive Remediations run as SYSTEM). Only fall back to the
        # winget.exe CLI when the module is unavailable.
        # Reference: https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
        if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
            try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop }
            catch { Write-Verbose "Handled exception: $($_.Exception.Message)" }
            if (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue) {
                $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue
                if (-not $package) {
                    $outputMsg = "[+] $ID is not installed on this device."
                    Write-Host $outputMsg -ForegroundColor Green
                    return 0
                }
                if ($package.IsUpdateAvailable) {
                    $verInstalled = $package.InstalledVersion
                    $verAvailable = $package.AvailableVersions | Select-Object -Last 1
                    $updateMsg = "[!] Application update available for $($package.Name). "
                    $updateMsg += "Current: $verInstalled, Available: $verAvailable"
                    Write-Host $updateMsg -ForegroundColor Yellow
                    [pscustomobject] @{
                        Name             = $package.Name
                        InstalledVersion = $verInstalled
                        AvailableVersion = $verAvailable
                    }
                    return 1
                }
                $upToDateMsg = "[+] $($package.Name) is already up to date (version $($package.InstalledVersion))."
                Write-Host $upToDateMsg -ForegroundColor Green
                return 0
            }
        }

        # Fallback: winget.exe CLI path via the wrapper function.
        $packageInfo = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"
        $name = if ($packageInfo -match "^($([regex]::Escape($ID)))\s+(.+?)\s+\d") { $Matches[2].Trim() } else { $ID }

        if ($packageInfo -match "No installed package found") {
            $outputMsg = "[+] $name is not installed."
            Write-Host $outputMsg -ForegroundColor Green
            return 0
        }
        if ($packageInfo -match '\bVersion\s+Available\b') {
            $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3, -2]
            $outputMsg = "[!] Update available for $name. Current: $verInstalled, Available: $verAvailable"
            Write-Host $outputMsg -ForegroundColor Yellow
            [pscustomobject] @{ Name = $name; InstalledVersion = $verInstalled; AvailableVersion = $verAvailable }
            return 1
        }
        if ($packageInfo -match '\d+(\.\d+)+') {
            $versionInstalled = (-split $packageInfo[-1])[-2]
            $outputMsg = "[+] $name is up to date (version $versionInstalled)."
            Write-Host $outputMsg -ForegroundColor Green
            return 0
        }
        $outputMsg = "[!] $name appears to be installed but version could not be determined; treating as compliant."
        Write-Host $outputMsg -ForegroundColor Yellow
        return 0
    }
    catch {
        # Preserve original behavior: a failed detection must never trigger false remediation.
        $outputMsg = "[-] Detection failed: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 0
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
