<#
.SYNOPSIS
    Removes broken shortcuts from Desktop and Start Menu.

.DESCRIPTION
    Scans the public Desktop, the Start Menu locations and every per-user Desktop
    folder (including OneDrive-redirected Desktops) for .lnk shortcuts whose target
    no longer exists and deletes them. Each deletion is gated behind -WhatIf/-Confirm
    via SupportsShouldProcess. Re-running on an already-converged system finds no
    broken shortcuts, changes nothing and still exits 0 (idempotent).
    Exit codes: 0 = scan completed successfully (with or without removals),
    1 = an unexpected error occurred.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixBrokenShortcuts.ps1

    Deletes every shortcut with a missing target from the scanned Desktop and
    Start Menu folders.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixBrokenShortcuts.ps1 -WhatIf

    Shows which broken shortcuts would be deleted without deleting anything.

.NOTES
    File Name  : Invoke-RemediationFixBrokenShortcuts.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Resolve-ShortcutTarget {
    # Resolves a shortcut's target path via the WScript.Shell COM object.
    # Exists as the mock seam for Pester tests (COM activation cannot be mocked otherwise).
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($Path)
    return $link.TargetPath
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Scanning for broken shortcuts..." -ForegroundColor Cyan

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
            $pathsToScan += Join-Path $userProfile.LocalPath "Desktop"

            $oneDriveDesktop = Join-Path $userProfile.LocalPath "OneDrive\Desktop"
            if (Test-Path $oneDriveDesktop) {
                $pathsToScan += $oneDriveDesktop
            }
        }

        $removedCount = 0

        foreach ($path in $pathsToScan) {
            if (-not (Test-Path $path)) {
                continue
            }

            $shortcuts = Get-ChildItem -Path $path -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue

            foreach ($shortcut in $shortcuts) {
                try {
                    $target = Resolve-ShortcutTarget -Path $shortcut.FullName

                    # Check if target exists
                    if ($target -and -not (Test-Path $target)) {
                        if ($PSCmdlet.ShouldProcess($shortcut.FullName, "Delete broken shortcut")) {
                            Remove-Item -LiteralPath $shortcut.FullName -Force -ErrorAction Stop
                            $removedCount++
                        }
                    }
                }
                catch {
                    continue
                }
            }
        }

        if ($removedCount -gt 0) {
            Write-Host "[+] Removed $removedCount broken shortcut(s)" -ForegroundColor Green
        }
        else {
            Write-Host "[+] Already clean: no broken shortcuts found" -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error removing broken shortcuts: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
