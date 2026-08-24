<#
.SYNOPSIS
    Detect broken desktop and Start Menu shortcuts that point to missing targets.

.DESCRIPTION
    This detection script scans for broken shortcuts (.lnk files) that point to
    non-existent targets and reports them; it deletes or repairs nothing. It checks
    common locations: per-user Desktops (including OneDrive-known-folder redirection),
    Public Desktop, Start Menu and Quick Launch. In SYSTEM context $env:USERPROFILE is
    the system profile - real user desktops must be enumerated via Win32_UserProfile
    or they are never scanned.
    Exit codes: 0 = compliant/healthy (no broken shortcuts found), 1 = issue detected
    (broken shortcuts present, triggering remediation, or an unexpected error
    occurred). The script changes no system state, so it is idempotent.

.EXAMPLE
    PS C:\> .\Test-RemediationFixBrokenShortcuts.ps1

    Exits 0 when no broken shortcuts are found; exits 1 with the list of broken
    shortcuts otherwise.

.EXAMPLE
    PS C:\> .\Test-RemediationFixBrokenShortcuts.ps1 -Verbose

    Runs the same read-only scan with verbose pipeline output for troubleshooting.

.NOTES
    File Name  : Test-RemediationFixBrokenShortcuts.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-ShortcutTargetPath {
    # Resolves a .lnk shortcut's target path via the WScript.Shell COM object.
    # Thin wrapper so Pester tests have a mock seam (COM activation cannot be mocked).
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($Path)
    return $link.TargetPath
}

function Main {
    param()

    try {
        Write-Host "[*] Scanning Desktop and Start Menu locations for broken shortcuts..." -ForegroundColor Cyan

        # Paths to scan
        $pathsToScan = @(
            "$env:PUBLIC\Desktop",
            "$env:APPDATA\Microsoft\Windows\Start Menu",
            "$env:ProgramData\Microsoft\Windows\Start Menu"
        )

        # Per-user desktops (SYSTEM context never sees them via $env:USERPROFILE) -
        # every non-special profile is enumerated. OneDrive-known-folder redirection
        # moves the desktop under the user's OneDrive folder; the default folder name is
        # "OneDrive" (tenant-renamed folders cannot be derived without loading each user
        # hive, so only the default is covered).
        $userProfiles = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
            Where-Object { $_.Special -eq $false -and $_.LocalPath -notmatch 'systemprofile|defaultuser' }

        foreach ($userProfile in $userProfiles) {
            $desktopPath = Join-Path $userProfile.LocalPath "Desktop"
            $pathsToScan += $desktopPath

            $oneDriveDesktop = Join-Path $userProfile.LocalPath "OneDrive\Desktop"
            if (Test-Path $oneDriveDesktop) {
                $pathsToScan += $oneDriveDesktop
            }
        }

        $brokenShortcuts = @()

        foreach ($path in $pathsToScan) {
            if (-not (Test-Path $path)) {
                continue
            }

            $shortcuts = Get-ChildItem -Path $path -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue

            foreach ($shortcut in $shortcuts) {
                try {
                    $target = Get-ShortcutTargetPath -Path $shortcut.FullName

                    # Check if target exists
                    if ($target -and -not (Test-Path $target)) {
                        $brokenShortcuts += $shortcut.FullName
                    }
                }
                catch {
                    # Skip shortcuts that can't be read
                    continue
                }
            }
        }

        if ($brokenShortcuts.Count -gt 0) {
            Write-Host "[!] Found $($brokenShortcuts.Count) broken shortcut(s):" -ForegroundColor Yellow
            foreach ($brokenShortcut in $brokenShortcuts) {
                Write-Host "[!]   - $brokenShortcut" -ForegroundColor Yellow
            }
            return 1  # Triggers remediation
        }

        Write-Host "[+] No broken shortcuts found" -ForegroundColor Green
        return 0  # Compliant
    }
    catch {
        Write-Host "[-] Error detecting broken shortcuts: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
