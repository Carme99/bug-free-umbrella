<#
.SYNOPSIS
    [DEPRECATED] Legacy V1 winget update remediation template - use remediate_v3_standard.ps1.

.DESCRIPTION
    DEPRECATED: this legacy template is superseded by remediate_v3_standard.ps1 in this directory.
    Existing Intune Proactive Remediations assignments may still reference this path, so the filename
    and location are preserved (docs/RELAUNCH-SPEC.md section 6 forbids renames); new deployments
    should use the V3 standard template instead.
    Template for winget application update remediation scripts. Checks whether the configured package
    has a winget update available and installs it silently when the application process is not running;
    exits 0 when the package was upgraded, was already up to date, or is not installed, and exits 1
    when the application is running (update skipped) or the upgrade fails. Replace the APPNAME,
    WINGETID and PROCESS placeholders before deployment.

.EXAMPLE
    PS C:\> .\remediate_v1_legacy.ps1

    Runs the template directly against the placeholder configuration.

.EXAMPLE
    PS C:\> pwsh -NoProfile -File .\remediate_v1_legacy.ps1

    Runs the template in a clean PowerShell process; behavior and exit codes are unchanged.

.NOTES
    File Name  : remediate_v1_legacy.ps1
    Author     : Intune / Proactive Remediations
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

#region Configuration (replace placeholders before deployment)
# Display name of your application (used for reporting purposes).
$name = 'APPNAME'
# Winget ID for the package.
$ID = 'WINGETID'
# Name of the running process (so you don't force close it).
$AppProcess = 'PROCESS'
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
    if (-not $package) {
        Write-Host "[+] $name is not installed on this device." -ForegroundColor Green
        return 0
    }

    if (-not $package.IsUpdateAvailable) {
        Write-Host "[+] Already up to date: $name (version $($package.InstalledVersion))." -ForegroundColor Green
        return 0
    }

    $process = Get-Process -Name $AppProcess -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "[!] $name is currently running, will try again later." -ForegroundColor Yellow
        return 1
    }

    Write-Host "[*] Installing $name update..." -ForegroundColor Cyan
    Update-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -Mode Silent -Force -ErrorAction Stop

    $updated = Get-WinGetPackage -Id $ID -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue
    if (-not $updated) {
        throw "Failed to verify $name installation after upgrade."
    }

    Write-Host "[+] $name upgraded to version $($updated.InstalledVersion)." -ForegroundColor Green
    return 0
}

function Invoke-CliFallbackRemediation {
    # Fallback path: winget.exe CLI, reached only when the Microsoft.WinGet.Client module is unavailable.
    [CmdletBinding()]
    param()

    $lines = Invoke-WingetCommand -Arguments @('list', '--exact', '--id', $ID, '--accept-source-agreements')

    if ($lines -match 'No installed package found matching input criteria') {
        Write-Host "[+] $name is not installed on this device." -ForegroundColor Green
        return 0
    }

    $process = Get-Process -Name $AppProcess -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "[!] $name is currently running, will try again later." -ForegroundColor Yellow
        return 1
    }

    if ($lines -match '\bVersion\s+Available\b') {
        Write-Host "[*] Application update available for $name." -ForegroundColor Cyan
        $null = Invoke-WingetCommand -Arguments @('upgrade', '-e', '--id', $ID, '--silent',
            '--accept-package-agreements', '--accept-source-agreements')

        $updatedLines = Invoke-WingetCommand -Arguments @('list', '--exact', '--id', $ID,
            '--accept-source-agreements')
        if ($updatedLines -match '\d+(\.\d+)+') {
            $versionInstalled = @(-split $updatedLines[-1])[-2]
            Write-Host "[+] $name upgraded to version $versionInstalled." -ForegroundColor Green
            return 0
        }

        throw "Failed to verify $name installation after upgrade."
    }

    if ($lines -match '\d+(\.\d+)+') {
        $versionInstalled = @(-split $lines[-1])[-2]
        Write-Host "[+] Already up to date: $name (version $versionInstalled)." -ForegroundColor Green
        return 0
    }

    throw "Unable to determine the winget state of $name."
}

function Main {
    try {
        Write-Host "[*] Starting winget remediation for package $ID..." -ForegroundColor Cyan
        Write-Warning 'DEPRECATED: remediate_v1_legacy.ps1 is superseded by remediate_v3_standard.ps1.'

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
