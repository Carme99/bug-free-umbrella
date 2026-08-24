<#
.SYNOPSIS
    Updates TeamViewer Host (winget id TeamViewer.TeamViewer.Host) silently without blocking on running state.

.DESCRIPTION
    Remediation half of the TeamViewer Host update pair. Checks whether a TeamViewer update is
    available and installs it silently with winget. The running-process check uses the sentinel
    name NotNeededAutoCloseOK, so the check never trips and the update proceeds even while
    TeamViewer runs - the installer closes the application itself. Prefers the
    Microsoft.WinGet.Client PowerShell module because the winget CLI is not supported in the
    SYSTEM context that Intune Proactive Remediations use; when the module is unavailable it
    falls back to the winget.exe CLI through the Invoke-WingetWithRetry wrapper (the only place
    a native executable is called).
    Exit codes:
    - 0: success - updated, already up to date, or package not installed.
    - 1: failure - verification failed after update or an error occurred.
    Re-running on a converged system exits 0 without changes (idempotent).

.NOTES
    File Name: Invoke-WingetTeamViewerHost.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Invoke-WingetTeamViewerFull.ps1
    Updates TeamViewer Host silently regardless of whether the app is running.

.EXAMPLE
    PS C:\> .\Invoke-WingetTeamViewerFull.ps1 -WhatIf
    Shows which update action would run without performing it.
#>

[CmdletBinding(SupportsShouldProcess)]

$ErrorActionPreference = 'Stop'

#region Configuration
$ID = 'TeamViewer.TeamViewer.Host'
$AppProcess = 'NotNeededAutoCloseOK'
$MaxRetries = 3
$VerifyWaitSeconds = 5
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
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        $outputMsg = "=== Starting winget update remediation for package: $ID ==="
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

                $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive `
                    -ErrorAction SilentlyContinue

                # Check if package is installed
                if (-not $package) {
                    $outputMsg = "[+] $ID is not installed on this device."
                    Write-Host $outputMsg -ForegroundColor Green
                    return 0
                }

                $name = if ($package.Name) { $package.Name } else { $ID }

                # Check if update is available
                if ($package.IsUpdateAvailable) {
                    $verInstalled = $package.InstalledVersion
                    $verAvailable = $package.AvailableVersions | Select-Object -Last 1

                    # Defer while the application is running; Intune retries later.
                    $process = Get-Process -Name $AppProcess -ErrorAction SilentlyContinue
                    if ($process) {
                        $outputMsg = "[!] $name is currently running, will try again later."
                        Write-Host $outputMsg -ForegroundColor Yellow
                        return 1
                    }

                    $outputMsg = "[*] Installing $name update ($verInstalled -> $verAvailable)..."
                    Write-Host $outputMsg -ForegroundColor Cyan
                    if ($PSCmdlet.ShouldProcess($name, "Update package $ID silently")) {
                        Update-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive `
                            -Mode Silent -Force -ErrorAction Stop
                    }

                    $outputMsg = "Waiting $VerifyWaitSeconds seconds before verifying installation..."
                    Write-Log $outputMsg -Level Info
                    Start-Sleep -Seconds $VerifyWaitSeconds

                    # Verify installation
                    $outputMsg = "Verifying installation..."
                    Write-Log $outputMsg -Level Info
                    $verify = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive `
                        -ErrorAction SilentlyContinue
                    if ($verify) {
                        $outputMsg = "[+] $name updated successfully to version $($verify.InstalledVersion)"
                        Write-Host $outputMsg -ForegroundColor Green

                        [pscustomobject] @{
                            Name             = $name
                            InstalledVersion = $verify.InstalledVersion
                            Status           = "Updated Successfully"
                        }

                        return 0
                    }
                    $outputMsg = "[-] Failed to verify $name installation after update."
                    Write-Host $outputMsg -ForegroundColor Red
                    return 1
                }

                # No update available
                $outputMsg = "[+] $name is already up to date."
                Write-Host $outputMsg -ForegroundColor Green
                return 0
            }
        }

        # Fallback: winget.exe CLI path via the wrapper function.
        $outputMsg = "Microsoft.WinGet.Client module unavailable, falling back to winget.exe CLI"
        Write-Log $outputMsg -Level Warning

        $packageInfo = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"

        $name = if ($packageInfo -match "^($ID)\s+(.+?)\s+\d") { $Matches[2].Trim() } else { 'TeamViewer Host' }

        # Check if package is installed
        if ($packageInfo -match "No installed package found") {
            $outputMsg = "[+] $name is not installed on this device."
            Write-Host $outputMsg -ForegroundColor Green
            return 0
        }

        if ($packageInfo -match '\bVersion\s+Available\b') {
            $v = (-split $packageInfo[-1])[-3, -2]

            # Defer while the application is running; Intune retries later.
            $process = Get-Process -Name $AppProcess -ErrorAction SilentlyContinue
            if ($process) {
                $outputMsg = "[!] $name is currently running, will try again later."
                Write-Host $outputMsg -ForegroundColor Yellow
                return 1
            }

            $outputMsg = "[*] Installing $name update ($($v[0]) -> $($v[1]))..."
            Write-Host $outputMsg -ForegroundColor Cyan
            if ($PSCmdlet.ShouldProcess($name, "Update package $ID via winget CLI")) {
                $upgradeArgs = "upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements"
                Invoke-WingetWithRetry -Arguments $upgradeArgs | Out-Null
            }

            Start-Sleep -Seconds $VerifyWaitSeconds

            # Verify installation
            $outputMsg = "Verifying installation..."
            Write-Log $outputMsg -Level Info
            $verify = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"
            if ($verify -match '\d+(\.\d+)+') {
                $ver = (-split $verify[-1])[-2]
                $outputMsg = "[+] $name updated successfully to version $ver"
                Write-Host $outputMsg -ForegroundColor Green
                return 0
            }
            $outputMsg = "[-] Failed to verify $name installation after update."
            Write-Host $outputMsg -ForegroundColor Red
            return 1
        }

        # No update available
        $outputMsg = "[+] $name is already up to date."
        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Failed to update $ID : $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
    finally {
        $outputMsg = "=== Update remediation script completed ==="
        Write-Log $outputMsg -Level Info
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
