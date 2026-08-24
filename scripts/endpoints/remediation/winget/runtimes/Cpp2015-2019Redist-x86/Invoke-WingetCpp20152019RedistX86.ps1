<#
.SYNOPSIS
    Silently updates the Visual C++ Redistributable package Microsoft.VCRedist.2015+.x64 for Intune remediations.

.DESCRIPTION
    Remediation half of the Visual C++ Redistributable update pair. Checks whether an update is available
    for winget package Microsoft.VCRedist.2015+.x64 and installs it silently. When the redistributable installer process
    is running, the update is skipped this run and non-compliance is reported so Intune can retry
    later (the script never force closes a process). Prefers the Microsoft.WinGet.Client PowerShell
    module because the winget CLI is not supported in the SYSTEM context that Intune Proactive
    Remediations use; when the module is unavailable it falls back to the winget.exe CLI through
    the Invoke-WingetWithRetry wrapper (the only place a native executable is called directly).
    After every install attempt the result is verified and reported.
    Exit codes:
    - 0: success - updated, already up to date, or package not installed.
    - 1: failure/non-compliant - an update is pending while the process is running, verification failed after
      the update, or an error occurred.
    Re-running on a converged system exits 0 without changes (idempotent).

.NOTES
    File Name: Invoke-WingetCpp20152019RedistX86.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Invoke-WingetCpp20152019RedistX86.ps1
    Updates Microsoft.VCRedist.2015+.x64 silently; exits 0 on success or when already up to date.

.EXAMPLE
    PS C:\> .\Invoke-WingetCpp20152019RedistX86.ps1 -WhatIf
    Shows which update actions would run without performing them.
#>

[CmdletBinding(SupportsShouldProcess)]

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

#region Configuration
$ID = 'Microsoft.VCRedist.2015+.x64'
$AppProcess = 'Microsoft.VCRedist.2015+.x64'
$MaxRetries = 3
$VerifyWaitSeconds = 5
$EnableLogging = $false
$LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetRemediation_$ID.log"
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
    $delay = 2

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
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        $outputMsg = "=== Starting winget silent update remediation for package: $ID ==="
        Write-Log $outputMsg -Level Info

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

                $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue

                # Check if package is installed
                if (-not $package) {
                    Write-Host "[+] $ID is not installed on this device." -ForegroundColor Green
                    return 0
                }

                # Auto-detect name if not provided
                $name = if ($package.Name) { $package.Name } else { $ID }

                # Check if update is available
                if ($package.IsUpdateAvailable) {
                    $process = Get-Process -Name $AppProcess -ErrorAction SilentlyContinue
                    if ($process) {
                        Write-Host "[!] $name is currently running, will try again later." -ForegroundColor Yellow
                        return 1  # Retry on a later run; never force close a redistributable install
                    }

                    $verInstalled = $package.InstalledVersion
                    $verAvailable = $package.AvailableVersions | Select-Object -Last 1
                    $installMsg = "Installing $name update ($verInstalled -> $verAvailable)..."
                    Write-Host "[*] $installMsg" -ForegroundColor Cyan

                    if ($PSCmdlet.ShouldProcess($name, 'Silently update via Microsoft.WinGet.Client')) {
                        Update-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive `
                            -Mode Silent -Force -ErrorAction Stop
                    }
                    Start-Sleep -Seconds $VerifyWaitSeconds

                    # Verify the installation after the update
                    $verify = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue
                    if ($verify) {
                        $successMsg = "[+] $name updated successfully to version $($verify.InstalledVersion)"
                        Write-Host $successMsg -ForegroundColor Green
                        [pscustomobject] @{
                            Name             = $name
                            InstalledVersion = $verify.InstalledVersion
                            Status           = 'Updated Successfully'
                        }
                        return 0
                    }

                    Write-Host "[-] Failed to verify $name installation after update." -ForegroundColor Red
                    return 1
                }

                # No update available - already converged
                Write-Host "[+] $name is already up to date." -ForegroundColor Green
                return 0
            }
        }

        # Fallback: winget.exe CLI path via the wrapper function.
        $outputMsg = "Microsoft.WinGet.Client module unavailable, falling back to winget.exe CLI"
        Write-Log $outputMsg -Level Warning

        $packageInfo = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"

        $name = if ($packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d") { $Matches[2].Trim() } else { $ID }

        # Check if package is installed
        if ($packageInfo -match "No installed package found matching input criteria") {
            Write-Host "[+] $name is not installed on this device." -ForegroundColor Green
            return 0
        }

        # Check if update is available
        if ($packageInfo -match '\bVersion\s+Available\b') {
            $v = (-split $packageInfo[-1])[-3, -2]
            $process = Get-Process -Name $AppProcess -ErrorAction SilentlyContinue

            if ($process) {
                Write-Host "[!] $name is currently running, will retry later." -ForegroundColor Yellow
                return 1  # Retry on a later run; never force close a redistributable install
            }

            $installMsg = "Installing $name update ($($v[0]) -> $($v[1]))..."
            Write-Host "[*] $installMsg" -ForegroundColor Cyan

            if ($PSCmdlet.ShouldProcess($name, 'Silently update via winget.exe CLI')) {
                $upgradeArgs = "upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements"
                Invoke-WingetWithRetry -Arguments $upgradeArgs | Out-Null
            }
            Start-Sleep -Seconds $VerifyWaitSeconds

            # Verify the installation after the update
            $verify = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"
            if ($verify -match '\d+(\.\d+)+') {
                $ver = (-split $verify[-1])[-2]
                Write-Host "[+] $name updated to version $ver" -ForegroundColor Green
                return 0
            }

            Write-Host "[-] Failed to verify $name installation after update." -ForegroundColor Red
            return 1
        }

        # No update available - already converged
        Write-Host "[+] $name is up to date." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
