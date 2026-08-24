<#
.SYNOPSIS
    Repair a corrupted Start Menu layout by rebuilding its databases.

.DESCRIPTION
    Stops the StartMenuExperienceHost and ShellExperienceHost shell processes,
    removes every real user profile's corrupted TileDataLayer database and
    clears the Start Menu cache, then restarts Windows Explorer so the layout
    is rebuilt fresh.
    Side effects: shell processes are killed, TileDataLayer databases and Start
    Menu cache contents are permanently deleted and Windows Explorer is
    restarted. User profiles are enumerated from "<SystemDrive>\Users" because
    in SYSTEM context per-user appdata must be visited explicitly.
    Every deletion and process kill is gated behind -WhatIf/-Confirm via
    SupportsShouldProcess. Re-running on an already-converged device finds
    nothing to remove, skips the Explorer restart and still exits 0 (idempotent).

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixStartMenuLayout.ps1

    Clears the corrupted Start Menu tile database and cache for every user and
    restarts Explorer to rebuild the layout.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixStartMenuLayout.ps1 -WhatIf

    Shows which processes would be stopped and which folders would be removed
    without changing anything.

.NOTES
    File Name  : Invoke-RemediationFixStartMenuLayout.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Repairing Start Menu layout..." -ForegroundColor Cyan

        $usersRoot = "$env:SystemDrive\Users"
        $processesToStop = @('StartMenuExperienceHost', 'ShellExperienceHost')
        $changeCount = 0

        # Stop Start Menu related shell processes so they release their databases.
        foreach ($processName in $processesToStop) {
            if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
                if ($PSCmdlet.ShouldProcess($processName, 'Stop Start Menu shell process')) {
                    Stop-Process -Name $processName -Force -ErrorAction SilentlyContinue
                    Write-Host "[*] Stopped $processName process" -ForegroundColor Cyan
                    $changeCount++
                }
            }
        }

        if ($changeCount -gt 0) {
            Start-Sleep -Seconds 2
        }

        # Per-user cleanup - every real user profile directory is enumerated.
        $userDirs = Get-ChildItem -LiteralPath $usersRoot -ErrorAction SilentlyContinue |
            Where-Object { $_.PSIsContainer -and $_.Name -notmatch 'Public|Default|All Users' }

        foreach ($userDir in $userDirs) {
            # Remove the Start Menu tile database.
            $tileDataPath = Join-Path $userDir.FullName 'AppData\Local\TileDataLayer'
            if (Test-Path -LiteralPath $tileDataPath) {
                if ($PSCmdlet.ShouldProcess($tileDataPath, 'Remove corrupted tile database')) {
                    Remove-Item -LiteralPath $tileDataPath -Recurse -Force -ErrorAction Stop
                    Write-Host "[*] Removed tile database for user $($userDir.Name)" -ForegroundColor Cyan
                    $changeCount++
                }
            }

            # Clear the Start Menu cache.
            $startMenuCache = Join-Path $userDir.FullName 'AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState'
            if (Test-Path -LiteralPath $startMenuCache) {
                if ($PSCmdlet.ShouldProcess($startMenuCache, 'Clear Start Menu cache')) {
                    Remove-Item -Path (Join-Path $startMenuCache '*') -Recurse -Force -ErrorAction Stop
                    Write-Host "[*] Cleared Start Menu cache for user $($userDir.Name)" -ForegroundColor Cyan
                    $changeCount++
                }
            }
        }

        # Restart Explorer so the Start Menu rebuilds itself - but only when
        # something actually changed (a converged system keeps Explorer running).
        if ($changeCount -gt 0) {
            if ($PSCmdlet.ShouldProcess('explorer', 'Restart Windows Explorer')) {
                Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Start-Process 'explorer.exe' -ErrorAction SilentlyContinue
                Write-Host "[*] Restarted Windows Explorer" -ForegroundColor Cyan
            }
            Write-Host "[+] Start Menu remediation completed; users may need to sign out and back in for changes to take full effect" -ForegroundColor Green
        }
        else {
            Write-Host "[+] Already clean: no Start Menu remediation was necessary" -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error repairing Start Menu layout: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
