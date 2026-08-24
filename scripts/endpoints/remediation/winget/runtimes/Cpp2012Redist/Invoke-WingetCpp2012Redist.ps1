<#
.SYNOPSIS
    Updates the C++ 2012 x64 Redistributable silently, skipping while its process runs.

.DESCRIPTION
    Remediation half of the C++ 2012 x64 Redistributable update pair. Checks whether an update is
    available and installs it silently; this variant never terminates processes - when the
    Microsoft.VCRedist.2012.x64 process is running the update is skipped so Intune can retry on a
    later cycle. Prefers the Microsoft.WinGet.Client PowerShell module because the winget CLI is not
    supported in the SYSTEM context that Intune Proactive Remediations use; when the module is
    unavailable it falls back to the winget.exe CLI through the Invoke-WingetWithRetry wrapper (the
    only place a native executable is called directly).
    Exit codes:
    - 0: success - updated, already up to date, or package not installed.
    - 1: skipped or failure - the process was running (retry later), verification failed after
      update, or an error occurred.
    Re-running on a converged system exits 0 without changes (idempotent).

.NOTES
    File Name: Invoke-WingetCpp2012Redist.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Invoke-WingetCpp2012Redist.ps1
    Installs any pending redistributable update silently unless its process is running; exits 0 on success.

.EXAMPLE
    PS C:\> .\Invoke-WingetCpp2012Redist.ps1 -WhatIf
    Shows which install action would run without performing it.
#>

[CmdletBinding(SupportsShouldProcess)]

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

#region Configuration
$ID = 'Microsoft.VCRedist.2012.x64'
$AppProcess = 'Microsoft.VCRedist.2012.x64'
$MaxRetries = 3
$VerifyWaitSeconds = 5

# Advanced settings
$RetryDelaySeconds = 2              # Initial delay between retries
$EnableLogging = $false             # Set to $true to enable file logging
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
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        $outputMsg = "=== Starting winget remediation for package: $ID ==="
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
                    $outputMsg = "[+] ${ID} is not installed on this device."
                    Write-Host $outputMsg -ForegroundColor Green
                    return 0
                }

                # Auto-detect display name from winget, falling back to the package ID
                $name = if ($package.Name) { $package.Name } else { $ID }

                if ($package.IsUpdateAvailable) {
                    # Skip-if-running variant: never terminate processes - defer to the next cycle.
                    $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
                    if ($process) {
                        $outputMsg = "[!] $name is currently running. Will try again later."
                        Write-Host $outputMsg -ForegroundColor Yellow

                        return 1
                    }

                    $verInstalled = $package.InstalledVersion
                    $verAvailable = $package.AvailableVersions | Select-Object -Last 1
                    $outputMsg = "Update available for $name | Installed: $verInstalled | Available: $verAvailable"
                    Write-Log $outputMsg -Level Info

                    # Perform upgrade via the module
                    $installMsg = "[*] Installing $name update ($verInstalled -> $verAvailable)..."
                    Write-Host $installMsg -ForegroundColor Cyan
                    if ($PSCmdlet.ShouldProcess($name, "Update package $ID silently")) {
                        Update-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive `
                            -Mode Silent -Force -ErrorAction Stop
                    }

                    # Wait for installation to complete
                    $outputMsg = "Waiting $VerifyWaitSeconds seconds for installation to complete..."
                    Write-Log $outputMsg -Level Info
                    Start-Sleep -Seconds $VerifyWaitSeconds

                    # Verify installation
                    $verify = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive `
                        -ErrorAction SilentlyContinue

                    if ($verify) {
                        $outputMsg = "[+] $name updated successfully to version $($verify.InstalledVersion)"
                        Write-Host $outputMsg -ForegroundColor Green

                        [pscustomobject] @{
                            Name             = $name
                            InstalledVersion = $verify.InstalledVersion
                            Status           = 'Updated Successfully'
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
        $pattern = "^($ID)\s+(.+?)\s+\d"
        $name = if ($packageInfo | Select-String -Pattern $pattern) {
            $Matches[2].Trim()
        }
        else {
            'Microsoft.VCRedist.2012.x64'
        }

        # Check if package is installed
        if ($packageInfo -match 'No installed package found') {
            $outputMsg = "[+] $name not installed."
            Write-Host $outputMsg -ForegroundColor Green
            return 0
        }

        if ($packageInfo -match '\bVersion\s+Available\b') {
            $v = (-split $packageInfo[-1])[-3, -2]

            # Skip-if-running variant: never terminate processes - defer to the next cycle.
            $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
            if ($process) {
                $outputMsg = "[!] $name is running. Will retry later."
                Write-Host $outputMsg -ForegroundColor Yellow

                return 1
            }

            # Perform upgrade via the winget CLI wrapper
            $installMsg = "[*] Installing $name update ($($v[0]) -> $($v[1]))..."
            Write-Host $installMsg -ForegroundColor Cyan
            if ($PSCmdlet.ShouldProcess($name, "Update package $ID via winget CLI")) {
                $upgradeArgs = "upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements"
                Invoke-WingetWithRetry -Arguments $upgradeArgs | Out-Null
            }
            Start-Sleep -Seconds $VerifyWaitSeconds

            # Verify installation
            $verify = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"
            if ($verify -match '\d+(\.\d+)+') {
                $ver = (-split $verify[-1])[-2]
                $outputMsg = "[+] $name updated to version $ver"
                Write-Host $outputMsg -ForegroundColor Green

                return 0
            }

            $outputMsg = "[-] Verification failed for $name."
            Write-Host $outputMsg -ForegroundColor Red
            return 1
        }

        $outputMsg = "[+] $name is up to date."
        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Failed to update package ${ID}: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
    finally {
        $outputMsg = "=== Remediation script completed ==="
        Write-Log $outputMsg -Level Info
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
