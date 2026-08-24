<#
.SYNOPSIS
    Updates Git (winget id Git.Git) silently for Intune Proactive Remediations.
.DESCRIPTION
        Remediation half of the Git update pair. Git can be safely force-closed because its CLI
    operations are short-lived, so running git processes are stopped (grace period follows)
    instead of deferring the update. Prefers the Microsoft.WinGet.Client PowerShell module
    because the winget CLI is not supported in the SYSTEM context that Intune Proactive
    Remediations use; when the module is unavailable it falls back to the winget.exe CLI through
    the Invoke-WingetWithRetry wrapper (the only place a native executable is called).
    Exit codes:
    - 0: success - updated, already up to date, or package not installed.
    - 1: failure - verification failed after update, or an error occurred.
    Re-running on a converged system exits 0 without changes (idempotent).
.EXAMPLE
    PS C:\> .\Invoke-WingetGit.ps1
    Updates Git silently, force-closing short-lived git processes first; exits 0 on success or when already up to date.
.EXAMPLE
    PS C:\> & 'C:\Program Files\...\Invoke-WingetGit.ps1'
    Runs the same check from Intune Management Extension under the SYSTEM context.
.NOTES
    File Name: Invoke-WingetGit.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]

$ErrorActionPreference = 'Stop'

#region Configuration
$ID = 'Git.Git'
$ConnectivityHost = 'www.microsoft.com'
$MaxRetries = 3
$AppProcess = 'git'
$GracePeriodSeconds = 2
$VerifyWaitSeconds = 5
#endregion

#region Functions

function Test-NetworkConnectivity {
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


function Stop-GitProcesses {
    <#
    .SYNOPSIS
        Force-closes any running git processes and waits out the grace period.
    #>
    $outputMsg = "[*] Closing git processes (safe: CLI operations are short-lived)..."
    Write-Host $outputMsg -ForegroundColor Cyan
    Stop-Process -Name "$AppProcess" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds $GracePeriodSeconds
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
            catch { Write-Verbose \"Handled exception: $($_.Exception.Message)\" }
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
                        Stop-GitProcesses
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
        $name = if ($packageInfo -match "^(Git\.Git)\s+(.+?)\s+\d") {
            $Matches[2].Trim()
        }
        else {
            "Git"
        }

        if ($packageInfo -match "No installed package found") {
            $outputMsg = "[+] $name not installed."
            Write-Host $outputMsg -ForegroundColor Green
            return 0
        }

        # Close any running git processes before upgrading (usually safe as operations are quick).
        $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
        if ($process) {
            Stop-GitProcesses
        }

        if ($packageInfo -match '\bVersion\s+Available\b') {
            $v = (-split $packageInfo[-1])[-3, -2]

            $outputMsg = "[*] Installing Git update ($($v[0]) -> $($v[1]))..."

            Write-Host $outputMsg -ForegroundColor Cyan
            if ($PSCmdlet.ShouldProcess($name, "Update package $ID via winget CLI")) {
                $upgradeArgs = "upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements"
                Invoke-WingetWithRetry -Arguments $upgradeArgs | Out-Null
            }
            Start-Sleep -Seconds $VerifyWaitSeconds

            $verify = Invoke-WingetWithRetry -Arguments "list --exact --id $ID --accept-source-agreements"
            if ($verify -match '\d+(\.\d+)+') {
                $ver = (-split $verify[-1])[-2]
                $outputMsg = "[+] Git updated to version $ver"
                Write-Host $outputMsg -ForegroundColor Green
                return 0
            }
            $outputMsg = "[-] Verification failed for Git."
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
