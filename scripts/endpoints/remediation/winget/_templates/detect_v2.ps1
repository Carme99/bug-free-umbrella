<#
.SYNOPSIS
    Winget update detection script for Intune Proactive Remediations (V2).

.DESCRIPTION
    Checks whether the configured package is installed and whether an update is available,
    preferring the Microsoft.WinGet.Client PowerShell module (the winget CLI is NOT supported in the
    SYSTEM context that Intune Proactive Remediations runs in) and falling back to the winget.exe
    CLI only when the module is unavailable.
    Exit codes: 1 = update available (triggers remediation); 0 = up to date, package not installed,
    or unexpected error (an error must not trigger remediation).
    Only the winget ID is required; the application display name is auto-detected from winget when
    the optional $name configuration value is left empty.

.EXAMPLE
    PS C:\> .\detect_v2.ps1

    Runs the detection using the package ID configured in the Configuration region, for example
    $ID = 'Google.Chrome'.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\detect_v2.ps1

    Runs the script in a clean PowerShell process; exit-code semantics are unchanged.

.NOTES
    File Name  : detect_v2.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 5.1+ (run in the Intune Proactive Remediation context)
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
$ErrorActionPreference = 'Stop'

#region Configuration
# ===== REQUIRED: Set your winget package ID =====
$ID = 'WINGETID'  # Example: 'Google.Chrome', 'Mozilla.Firefox', 'Adobe.Acrobat.Reader.64-bit'

# ===== OPTIONAL: Customize these if needed =====
$name = $null     # Leave as $null to auto-detect from winget, or set manually: 'Google Chrome'
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
        Write-Host "[*] Checking '$ID' for updates..." -ForegroundColor Cyan

        # Prefer the Microsoft.WinGet.Client PowerShell module - the winget CLI is NOT supported in
        # the SYSTEM context (Intune Proactive Remediations run as SYSTEM). Only fall back to the
        # winget.exe CLI when the module is unavailable.
        # Reference: https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
        if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
            try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop }
            catch { Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false }

            if (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue) {
                $package = Invoke-WingetPackageLookup -Id $ID

                # Auto-detect name if not provided
                if (-not $name) {
                    $name = if ($package.Name) { $package.Name } else { $ID }
                }

                # Check if package is installed
                if (-not $package) {
                    Write-Host "[+] $name is not installed on this device." -ForegroundColor Green
                    return 0
                }

                # Check if update is available
                if ($package.IsUpdateAvailable) {
                    $verInstalled = $package.InstalledVersion
                    $verAvailable = $package.AvailableVersions | Select-Object -Last 1
                    $msg = "Update available for $name (current: $verInstalled, available: $verAvailable)"
                    Write-Host "[!] $msg" -ForegroundColor Yellow
                    return 1
                }

                # No update available
                Write-Host "[+] $name is up to date (version $($package.InstalledVersion))." -ForegroundColor Green
                return 0
            }
        }

        # Fallback: winget.exe CLI (only reached when the Microsoft.WinGet.Client module is unavailable)
        # Locate winget executable
        $wingetGlob = 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe'
        $wingetexe = Resolve-Path $wingetGlob -ErrorAction Stop
        $SystemContext = $wingetexe[-1].Path

        # Get package information (exact ID match)
        $packageInfo = Invoke-WingetList -SysgetPath $SystemContext -PackageId $ID

        # Auto-detect name if not provided
        if (-not $name) {
            $nameMatch = $packageInfo | Select-String -Pattern "^($ID)\s+(.+?)\s+\d"
            if ($nameMatch) {
                $name = $nameMatch.Matches[0].Groups[2].Value.Trim()
            }
            else {
                $name = $ID
            }
        }

        # Check if package is installed
        if ($packageInfo -match 'No installed package found matching input criteria') {
            Write-Host "[+] $name is not installed on this device." -ForegroundColor Green
            return 0
        }

        # Check if update is available
        if ($packageInfo -match '\bVersion\s+Available\b') {
            $verInstalled, $verAvailable = (-split $packageInfo[-1])[-3, -2]
            $msg = "Update available for $name (current: $verInstalled, available: $verAvailable)"
            Write-Host "[!] $msg" -ForegroundColor Yellow
            return 1
        }
        elseif ($packageInfo -match '\d+(\.\d+)+') {
            # No update available
            $versionInstalled = (-split $packageInfo[-1])[-2]
            Write-Host "[+] $name is already up to date (version $versionInstalled)." -ForegroundColor Green
            return 0
        }

        Write-Host "[!] $name appears installed but its version could not be determined." -ForegroundColor Yellow
        return 0
    }
    catch {
        # Documented semantics: an unexpected error must not trigger remediation.
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 0
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
