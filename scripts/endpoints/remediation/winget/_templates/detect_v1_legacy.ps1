<#
.SYNOPSIS
    DEPRECATED: use detect_v3.ps1. Legacy winget update detection template (V1).

.DESCRIPTION
    Deprecated template generation retained so existing copies keep working; new deployments should
    use detect_v3.ps1 instead. Checks whether the configured package is installed (preferring the
    Microsoft.WinGet.Client module, which is required in the SYSTEM context that Intune Proactive
    Remediations runs under) and whether an update is available.
    Exit codes: 1 = update available (triggers remediation) or unexpected error;
    0 = package up to date or not installed.
    Replace the APPNAME, WINGETID and PROCESS placeholders before use.

.EXAMPLE
    PS C:\> .\detect_v1_legacy.ps1

    Runs the detection directly after replacing the placeholders in the Configuration region.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\detect_v1_legacy.ps1

    Runs the template in a clean PowerShell process; exit-code semantics are unchanged.

.NOTES
    File Name  : detect_v1_legacy.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1+ (run in the Intune Proactive Remediation context)
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

#region Configuration - replace the placeholders below before use
# Display name of your application (used for reporting purposes)
$name = 'APPNAME'
# Winget ID for the package
$ID = 'WINGETID'
# Name of the running process (so you do not force close it while it is running)
$AppProcess = 'PROCESS'
#endregion

function Invoke-WingetPackageLookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Id
    )

    # Thin wrapper seam around the Microsoft.WinGet.Client cmdlet so tests can mock this function.
    return (Get-WinGetPackage -Id $Id -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue)
}

function Invoke-WingetList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SysgetPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId
    )

    # Thin wrapper seam: $SysgetPath resolves to winget.exe, a native executable that Pester cannot
    # mock, so every CLI invocation goes through this function (tests mock the wrapper instead).
    # Template deviation note: the legacy sysget alias trick is replaced by passing the resolved
    # winget.exe path straight into this wrapper.
    return (& $SysgetPath list --exact --id $PackageId --accept-source-agreements)
}

function Main {
    try {
        Write-Host "[*] Checking '$name' ($ID) for updates..." -ForegroundColor Cyan

        # Prefer the Microsoft.WinGet.Client PowerShell module - the winget CLI is NOT supported in
        # the SYSTEM context (Intune Proactive Remediations run as SYSTEM). Only fall back to the
        # winget.exe CLI when the module is unavailable.
        # Reference: https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
        if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
            try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop }
            catch { Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false }

            if (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue) {
                $package = Invoke-WingetPackageLookup -Id $ID
                $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue

                if (-not $package) {
                    Write-Host "[+] $name is not installed on this device." -ForegroundColor Green
                    return 0
                }

                if ($package.IsUpdateAvailable) {
                    $verInstalled = $package.InstalledVersion
                    $verAvailable = $package.AvailableVersions | Select-Object -Last 1
                    $msg = "Update available for $name (current: $verInstalled, available: $verAvailable)"
                    if ($null -ne $process) {
                        $msg = "$msg. $name is currently running, will try again later."
                    }
                    Write-Host "[!] $msg" -ForegroundColor Yellow
                    return 1
                }

                Write-Host "[+] $name is up to date (version $($package.InstalledVersion))." -ForegroundColor Green
                return 0
            }
        }

        # Fallback: winget.exe CLI (only reached when the Microsoft.WinGet.Client module is unavailable)
        $wingetGlob = 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe'
        $wingetexe = Resolve-Path $wingetGlob -ErrorAction Stop
        $SystemContext = $wingetexe[-1].Path

        # Gets the info on the app (whether it has an update, or not).
        $lines = Invoke-WingetList -SysgetPath $SystemContext -PackageId $ID
        $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue

        if ($lines -match '\bVersion\s+Available\b') {
            $verInstalled, $verAvailable = (-split $lines[-1])[-3, -2]
            $msg = "Update available for $name (current: $verInstalled, available: $verAvailable)"
            if ($null -ne $process) {
                $msg = "$msg. $name is currently running, will try again later."
            }
            Write-Host "[!] $msg" -ForegroundColor Yellow
            return 1
        }
        elseif ($lines -eq 'No installed package found matching input criteria.') {
            Write-Host "[+] $name is not installed on this device." -ForegroundColor Green
            return 0
        }
        else {
            # Rechecks the version when the package is installed and already up to date.
            $lines = Invoke-WingetList -SysgetPath $SystemContext -PackageId $ID
            $versionInstalled = '<unknown>'
            if ($lines -match '\d+(\.\d+)+') {
                $versionInstalled = (-split $lines[-1])[-2]
            }
            Write-Host "[+] $name upgraded to $versionInstalled, or was already up to date." -ForegroundColor Green
            return 0
        }
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
