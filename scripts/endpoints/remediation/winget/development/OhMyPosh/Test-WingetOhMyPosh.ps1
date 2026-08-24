<#
.SYNOPSIS
    Detects pending updates for Oh My Posh (winget id JanDeDobbeleer.OhMyPosh) for Intune Proactive Remediations.
.DESCRIPTION
        Detection half of the Oh My Posh update pair. Prefers the Microsoft.WinGet.Client PowerShell
    module because the winget CLI is not supported in the SYSTEM context that Intune
    Proactive Remediations use; when the module is unavailable it falls back to the winget.exe
    CLI through the Invoke-WingetWithRetry wrapper (the only place a native executable is called).
    Exit codes:
    - 0: compliant - Oh My Posh is up to date, not installed, or the check could not run (network down,
      transient winget failure); failures deliberately exit 0 so remediation is never falsely triggered.
    - 1: non-compliant - an application update is available.
.EXAMPLE
    PS C:\> .\Test-WingetOhMyPosh.ps1
    Runs the detection check and exits 0 when Oh My Posh is up to date or absent, 1 when an update is available.
.EXAMPLE
    PS C:\> & 'C:\Program Files\...\Test-WingetOhMyPosh.ps1'
    Runs the same check from Intune Management Extension under the SYSTEM context.
.NOTES
    File Name: Test-WingetOhMyPosh.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

#region Configuration
$ID = 'JanDeDobbeleer.OhMyPosh'
$ConnectivityHost = 'www.microsoft.com'
$MaxRetries = 3
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


function Main {
    try {
        $outputMsg = "[*] Checking $ID for available updates..."
        Write-Host $outputMsg -ForegroundColor Cyan

        if (-not (Test-NetworkConnectivity)) {
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
            catch { Write-Verbose \"Handled exception: $($_.Exception.Message)\" }
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
        $name = if ($packageInfo -match "^(JanDeDobbeleer.OhMyPosh)\s+(.+?)\s+\d") {
            $Matches[2].Trim()
        }
        else {
            "Oh My Posh"
        }
        if ($packageInfo -match "No installed package found") {
            $outputMsg = "[+] $name not installed."
            Write-Host $outputMsg -ForegroundColor Green
            return 0
        }
        if ($packageInfo -match '\bVersion\s+Available\b') {
            $v = (-split $packageInfo[-1])[-3, -2]
            $outputMsg = "[!] Update available: $($v[0]) -> $($v[1])"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }
        $outputMsg = "[+] $name is up to date."
        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        # Preserve original behavior: a failed detection must never trigger false remediation.
        $outputMsg = "[-] Error during update check: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 0
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
