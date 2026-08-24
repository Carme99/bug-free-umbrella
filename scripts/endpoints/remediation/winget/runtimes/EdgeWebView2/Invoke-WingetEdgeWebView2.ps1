<#
.SYNOPSIS
    Silently updates Edge WebView2 via winget (skips while running) for Intune Proactive Remediations.

.DESCRIPTION
    Remediation half of the Edge WebView2 update pair. Checks whether an update is available and installs it
    silently through the Microsoft.WinGet.Client module, falling back to the winget.exe CLI through the
    Invoke-WingetWithRetry wrapper when the module is unavailable. When the R@ndomProcess process is running the
    update is skipped and exit code 1 is returned so Intune retries later. Honors -WhatIf; the silent
    update only runs behind a ShouldProcess gate.
    Exit codes:
    - 0: success - updated, already up to date, or package not installed.
    - 1: skipped because the application is running, verification failed after update, or an error occurred.
    Re-running on a converged system exits 0 without changes (idempotent).

.NOTES
    File Name: Invoke-WingetEdgeWebView2.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Invoke-WingetEdgeWebView2.ps1
    Updates Edge WebView2 silently unless R@ndomProcess runs; exits 0 on success or when already up to date.

.EXAMPLE
    PS C:\> .\Invoke-WingetEdgeWebView2.ps1 -WhatIf
    Shows which update actions would run without performing them.
#>


[CmdletBinding(SupportsShouldProcess)]

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

#region Configuration
$ID = 'Microsoft.EdgeWebView2Runtime'
$AppProcess = 'R@ndomProcess'
$MaxRetries = 3
$VerifyWaitSeconds = 5
#endregion

#region Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes a timestamped message to the console.
    #>
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
                    Write-Host "[+] $ID is not installed on this device." -ForegroundColor Green
                    return 0
                }

                # Auto-detect name if not provided
                $name = if ($package.Name) { $package.Name } else { $ID }

                # Check if update is available
                if ($package.IsUpdateAvailable) {
                    # Skip while the application is running; Intune will retry later.
                    $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
                    if ($process) {
                        Write-Host "[*] $name is currently running, will try again later." -ForegroundColor Cyan
                        return 1
                    }

                    $verInstalled = $package.InstalledVersion
                    $verAvailable = $package.AvailableVersions | Select-Object -Last 1
                    $outputMsg = "Update available for $name ($verInstalled -> $verAvailable)"
                    Write-Log $outputMsg -Level Info

                    # Perform upgrade via the module
                    Write-Host "[*] Installing $name update ($verInstalled -> $verAvailable)..." -ForegroundColor Cyan
                    if ($PSCmdlet.ShouldProcess($name, "Update package $ID silently")) {
                        Update-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive `
                            -Mode Silent -Force -ErrorAction Stop
                    }

                    # Wait for installation to complete, then verify
                    $outputMsg = "Waiting $VerifyWaitSeconds seconds for installation to complete..."
                    Write-Log $outputMsg -Level Info
                    Start-Sleep -Seconds $VerifyWaitSeconds

                    $verify = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue
                    if ($verify) {
                        Write-Host "[+] $name updated successfully to version $($verify.InstalledVersion)" `
                            -ForegroundColor Green

                        [pscustomobject] @{
                            Name = $name
                            PreviousVersion = $verInstalled
                            InstalledVersion = $verify.InstalledVersion
                            Status = "Updated Successfully"
                        }

                        return 0
                    }

                    Write-Host "[-] Failed to verify $name installation after update." -ForegroundColor Red
                    return 1
                }
                else {
                    # No update available
                    $versionInstalled = $package.InstalledVersion
                    $outputMsg = "$name is already up to date (version $versionInstalled)"
                    Write-Log $outputMsg -Level Info
                    Write-Host "[+] $name is already up to date (version $versionInstalled)." -ForegroundColor Green
                    return 0
                }
            }
        }

        # Fallback: winget.exe CLI path via the wrapper function.
        $outputMsg = "Microsoft.WinGet.Client module unavailable, falling back to winget.exe CLI"
        Write-Log $outputMsg -Level Warning

        $packageInfo = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"
        $nameMatch = $packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d"
        $name = if ($nameMatch) { $nameMatch.Matches[0].Groups[2].Value.Trim() } else { "Edge WebView2" }

        # Check if package is installed
        if ($packageInfo -match "No installed package found") {
            Write-Host "[+] $name is not installed on this device." -ForegroundColor Green
            return 0
        }

        # Check if update is available
        if ($packageInfo -match '\bVersion\s+Available\b') {
            $v = (-split $packageInfo[-1])[-3, -2]

            # Skip while the application is running; Intune will retry later.
            $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
            if ($process) {
                Write-Host "[*] $name is running. Will retry later." -ForegroundColor Cyan
                return 1
            }

            Write-Host "[*] Installing $name update ($($v[0]) -> $($v[1]))..." -ForegroundColor Cyan
            if ($PSCmdlet.ShouldProcess($name, "Update package $ID via winget CLI")) {
                $upgradeArgs = "upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements"
                Invoke-WingetWithRetry -Arguments $upgradeArgs | Out-Null
            }

            Start-Sleep -Seconds $VerifyWaitSeconds

            # Verify installation
            $verify = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"
            if ($verify -match '\d+(\.\d+)+') {
                $ver = (-split $verify[-1])[-2]
                Write-Host "[+] $name updated to version $ver" -ForegroundColor Green
                return 0
            }

            Write-Host "[-] Verification failed." -ForegroundColor Red
            return 1
        }

        Write-Host "[+] $name is up to date." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Failed: $($_.Exception.Message)" -ForegroundColor Red
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
