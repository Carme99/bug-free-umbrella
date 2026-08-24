<#
.SYNOPSIS
    Updates Adobe Acrobat Reader 32-bit (winget id Adobe.Acrobat.Reader.32-bit) silently.

.DESCRIPTION
    Standard remediation for Adobe Acrobat Reader 32-bit - defers the update while AcroRd32 is
    running so open documents are never lost. Prefers the Microsoft.WinGet.Client PowerShell module
    because the winget CLI is not supported in the SYSTEM context that Intune Proactive Remediations
    use; when the module is unavailable it falls back to the winget.exe CLI through the
    Invoke-WingetWithRetry wrapper (the only place a native executable is called).
    If the AcroRd32 process is running, the update is deferred (exit 1) so Intune retries later.
    Exit codes:
    - 0: success - updated, already up to date, or package not installed.
    - 1: failure or deferral - app running, verification failed, or an error occurred.
    Re-running on a converged system exits 0 without changes (idempotent).

.NOTES
    File Name: Invoke-WingetAdobeReader32bit.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Invoke-WingetAdobeReader32bit.ps1
    Updates Adobe Acrobat Reader 32-bit silently; exits 0 on success or when already up to date.

.EXAMPLE
    PS C:\> .\Invoke-WingetAdobeReader32bit.ps1 -WhatIf
    Shows which package update would run without performing it.
#>

[CmdletBinding(SupportsShouldProcess)]
# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

#region Configuration
$ID = 'Adobe.Acrobat.Reader.32-bit'
$AppProcess = 'AcroRd32'
$MaxRetries = 3
$VerifyWaitSeconds = 5
#endregion

#region Functions

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
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        $outputMsg = "[*] Starting $ID update..."
        Write-Host $outputMsg -ForegroundColor Cyan

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
                $name = if ($package.Name) { $package.Name } else { $ID }
                if ($package.IsUpdateAvailable) {
                    $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
                    if ($process) {
                        $outputMsg = "[!] $name is currently running, will try again later."
                        Write-Host $outputMsg -ForegroundColor Yellow
                        return 1
                    }
                    $verInstalled = $package.InstalledVersion
                    $verAvailable = $package.AvailableVersions | Select-Object -Last 1
                    $outputMsg = "[*] Installing $name update ($verInstalled -> $verAvailable)..."
                    Write-Host $outputMsg -ForegroundColor Cyan
                    if ($PSCmdlet.ShouldProcess($name, "Update package $ID silently")) {
                        Update-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive `
                            -Mode Silent -Force -ErrorAction Stop
                    }
                    Start-Sleep -Seconds $VerifyWaitSeconds
                    $verify = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue
                    if ($verify) {
                        Write-Host "[+] $name updated successfully to version $($verify.InstalledVersion)" `
                            -ForegroundColor Green
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
                $outputMsg = "[+] $name is already up to date."
                Write-Host $outputMsg -ForegroundColor Green
                return 0
            }
        }

        # Fallback: winget.exe CLI path via the wrapper function.
        $packageInfo = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"
        $name = if ($packageInfo -match "^($ID)\s+(.+?)\s+\d") {
            $Matches[2].Trim()
        }
        else {
            "Adobe Acrobat Reader 32-bit"
        }

        if ($packageInfo -match "No installed package found") {
            $outputMsg = "[+] $name not installed."
            Write-Host $outputMsg -ForegroundColor Green
            return 0
        }

        if ($packageInfo -match '\bVersion\s+Available\b') {
            $v = (-split $packageInfo[-1])[-3, -2]
            $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue

            # Check if Adobe Acrobat Reader 32-bit is open - don't interrupt the user
            if ($process) {
                $outputMsg = "[!] $name is currently running. Will retry later."
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
        $outputMsg = "[-] Failed: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
