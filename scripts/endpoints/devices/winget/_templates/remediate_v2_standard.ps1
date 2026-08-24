<#
.SYNOPSIS
    Standard winget update template that waits for the app to close before updating (V2).

.DESCRIPTION
    This template checks if an app update is available and installs it.
    If the app is running, it will skip the update and retry later.
    It prefers the Microsoft.WinGet.Client PowerShell module (the winget CLI is NOT
    supported in the SYSTEM context that Intune Proactive Remediations run in) and
    falls back to the winget.exe CLI only when the module is unavailable.
    Exit codes follow the Intune remediation convention: 0 = updated, already up to date,
    or not installed; 1 = application running (update skipped) or the upgrade failed.
    Template note (docs/RELAUNCH-SPEC.md section 6): examples below show placeholder
    configuration, which makes some help rules inapplicable until placeholders are replaced.
    Configuration:
    1. Set the $ID variable to your winget package ID
    2. (Optional) Customize $name if you want a specific display name
    3. (Optional) Set $AppProcess if auto-detection doesn't work

.EXAMPLE
    PS C:\> .\remediate_v2_standard.ps1

    Runs the template directly against the placeholder configuration; only $ID must be set
    for real use, for example $ID = 'Google.Chrome'.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\remediate_v2_standard.ps1

    Runs the template in a clean PowerShell process; behavior and exit codes are unchanged.

.NOTES
    REQUIRED: Only the winget ID is required. The script will auto-detect app name and process.
    File Name  : remediate_v2_standard.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 5.1+
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

# PSAvoidUsingWriteHost is intentionally accepted: prefixed, colored console output is the mandated
# output convention of docs/RELAUNCH-SPEC.md section 3.
# PSUseOutputTypeCorrectly is intentionally accepted: internal helper functions return plain
# values (bool/string/object[]) by design; only Main's exit code (int) is a public contract.
$ErrorActionPreference = 'Stop'

#region Configuration
# ===== REQUIRED: Set your winget package ID =====
$ID = 'WINGETID'  # Example: 'Google.Chrome', 'Mozilla.Firefox', 'Adobe.Acrobat.Reader.64-bit'

# ===== OPTIONAL: Customize these if needed =====
$name = $null           # Leave as $null to auto-detect from winget, or set manually: 'Google Chrome'
$AppProcess = $null     # Leave as $null to auto-detect, or set manually: 'chrome'
$VerifyWaitSeconds = 5  # Time to wait after update before verification (mockable delay)
#endregion

function Get-WingetExecutable {
    # Thin wrapper seam: locates the winget.exe CLI bundled with App Installer; tests mock this function.
    [CmdletBinding()]
    param()

    $wingetGlob = 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe'
    $resolved = Resolve-Path -Path $wingetGlob -ErrorAction Stop
    if (@($resolved).Count -gt 1) {
        return @($resolved)[-1].Path
    }
    return $resolved.Path
}

function Invoke-WingetCommand {
    # Thin wrapper seam: EVERY native winget.exe invocation (the sysget alias target) routes through
    # this function so Pester can mock the wrapper; the executable is never called elsewhere.
    # docs/RELAUNCH-SPEC.md section 3: check $LASTEXITCODE and translate non-zero into failure handling.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Arguments
    )

    $wingetPath = Get-WingetExecutable
    $output = & $wingetPath @Arguments 2>$null
    $exitCode = $LASTEXITCODE

    # Success codes: 0 (S_OK), 0x8A150014 (no installed package found), 0x8A150109 (reboot required).
    # Reference: https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md
    if ($exitCode -ne 0 -and $exitCode -ne 0x8A150014 -and $exitCode -ne 0x8A150109) {
        throw "winget exited with code 0x$('{0:X8}' -f $exitCode) for arguments: $($Arguments -join ' ')"
    }

    return @($output)
}

function Invoke-ModuleRemediation {
    # Microsoft.WinGet.Client path: the winget CLI is NOT supported in the SYSTEM context that Intune
    # Proactive Remediations run in.
    [CmdletBinding()]
    param()

    $package = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue

    # Auto-detect name if not provided
    if (-not $name) {
        $name = if ($package -and $package.Name) { $package.Name } else { $ID }
    }

    # Check if package is installed
    if (-not $package) {
        Write-Host "[+] $name is not installed on this device." -ForegroundColor Green
        return 0
    }

    # Check if update is available (idempotent converged path)
    if (-not $package.IsUpdateAvailable) {
        Write-Host "[+] Already up to date: $name (version $($package.InstalledVersion))." -ForegroundColor Green
        return 0
    }

    $verInstalled = $package.InstalledVersion
    $verAvailable = @($package.AvailableVersions)[-1]

    # Auto-detect process name if not provided
    if (-not $AppProcess) {
        # Extract process name from package ID (e.g., 'Google.Chrome' -> 'chrome')
        $AppProcess = ($ID -split '\.')[-1]
    }

    # Check if app is running
    $process = Get-Process -Name $AppProcess -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "[!] $name is currently running. Will try again later." -ForegroundColor Yellow
        return 1
    }

    # Perform upgrade via the module
    Write-Host "[*] Installing $name update ($verInstalled -> $verAvailable)..." -ForegroundColor Cyan
    Update-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -Mode Silent -Force -ErrorAction Stop

    # Wait for installation to complete (configurable, mockable delay)
    Start-Sleep -Seconds $VerifyWaitSeconds

    # Verify installation
    $verifyPackage = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue
    if (-not $verifyPackage) {
        throw "Failed to verify $name installation after update."
    }

    Write-Host "[+] $name updated successfully to version $($verifyPackage.InstalledVersion)." -ForegroundColor Green
    return 0
}

function Invoke-CliFallbackRemediation {
    # Fallback path: winget.exe CLI, reached only when the Microsoft.WinGet.Client module is unavailable.
    [CmdletBinding()]
    param()

    # Get package information (exact ID match) through the wrapper seam
    $packageInfo = Invoke-WingetCommand -Arguments @('list', '--exact', '--id', $ID,
        '--accept-source-agreements')

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

    # Auto-detect process name if not provided
    if (-not $AppProcess) {
        $AppProcess = ($ID -split '\.')[-1]
    }

    # Check if app is running
    $process = Get-Process -Name $AppProcess -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "[!] $name is currently running. Will try again later." -ForegroundColor Yellow
        return 1
    }

    # Check if update is available (idempotent converged path)
    if ($packageInfo -match '\bVersion\s+Available\b') {
        $verInstalled, $verAvailable = @(-split $packageInfo[-1])[-3, -2]
        Write-Host "[*] Installing $name update ($verInstalled -> $verAvailable)..." -ForegroundColor Cyan

        $null = Invoke-WingetCommand -Arguments @('upgrade', '-e', '--id', $ID, '--silent',
            '--accept-package-agreements', '--accept-source-agreements')

        # Wait for installation to complete (configurable, mockable delay)
        Start-Sleep -Seconds $VerifyWaitSeconds

        # Verify installation
        $verifyInfo = Invoke-WingetCommand -Arguments @('list', '--exact', '--id', $ID,
            '--accept-source-agreements')
        if ($verifyInfo -match '\d+(\.\d+)+') {
            $versionInstalled = @(-split $verifyInfo[-1])[-2]
            Write-Host "[+] $name updated successfully to version $versionInstalled." -ForegroundColor Green
            return 0
        }

        throw "Failed to verify $name installation after update."
    }

    if ($packageInfo -match '\d+(\.\d+)+') {
        $versionInstalled = @(-split $packageInfo[-1])[-2]
        Write-Host "[+] Already up to date: $name (version $versionInstalled)." -ForegroundColor Green
        return 0
    }

    throw "Unable to determine the winget state of $name."
}

function Main {
    try {
        Write-Host "[*] Starting winget remediation for package $ID..." -ForegroundColor Cyan

        # Prefer the Microsoft.WinGet.Client module - the winget CLI is NOT supported in the SYSTEM
        # context (Intune Proactive Remediations run as SYSTEM). Only fall back to the winget.exe CLI
        # when the module is unavailable.
        # Reference: https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting
        if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
            try {
                Import-Module Microsoft.WinGet.Client -ErrorAction Stop
            }
            catch {
                Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
            }
            if (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue) {
                return Invoke-ModuleRemediation
            }
        }

        return Invoke-CliFallbackRemediation
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
