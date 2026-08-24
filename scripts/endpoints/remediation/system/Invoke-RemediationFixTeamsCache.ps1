<#
.SYNOPSIS
    Clear corrupt Microsoft Teams caches for every user profile.

.DESCRIPTION
    Stops running Microsoft Teams processes, clears the known Teams cache
    folders (Application Cache, Cache, GPUCache, IndexedDB, Local Storage, tmp)
    and deletes Teams log files older than 7 days for EVERY non-special user
    profile. Profiles are enumerated from Win32_UserProfile because in SYSTEM
    context $env:APPDATA points at the SYSTEM profile - clearing only that
    would never converge with per-user detection.
    Side effects: Teams processes are killed and cached data plus old log files
    are permanently deleted; user settings and credentials are preserved and
    Teams is deliberately not restarted (it starts fresh on next launch).
    Every deletion and process kill is gated behind -WhatIf/-Confirm via
    SupportsShouldProcess. Re-running on a converged system clears nothing and
    still exits 0 (idempotent).
    Exit codes: 0 = remediation successful (or nothing to clear), 1 = profile
    enumeration failed.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixTeamsCache.ps1

    Stops Teams if running and clears every user's stale Teams cache folders
    and old log files.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixTeamsCache.ps1 -WhatIf

    Shows which cache folders and log files would be cleared without deleting
    anything.

.NOTES
    File Name  : Invoke-RemediationFixTeamsCache.ps1
    Author     : Intune / Proactive Remediations
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
        Write-Host "[*] Clearing Microsoft Teams caches..." -ForegroundColor Cyan

        $clearedCount = 0

        # Stop Teams if running so cache files are not locked while clearing.
        $teamsProcesses = Get-Process -Name 'Teams' -ErrorAction SilentlyContinue
        if ($teamsProcesses) {
            Write-Host "[*] Stopping running Microsoft Teams processes..." -ForegroundColor Cyan
            if ($PSCmdlet.ShouldProcess('Teams', 'Stop Microsoft Teams processes')) {
                $teamsProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
            }
            Start-Sleep -Seconds 3
        }

        # Per-user cache folders - SYSTEM context requires explicit enumeration.
        $userProfiles = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
            Where-Object { $_.Special -eq $false -and $_.LocalPath -notmatch 'systemprofile|defaultuser' }

        $teamsCacheFolders = @(
            'Application Cache',
            'Cache',
            'GPUCache',
            'IndexedDB',
            'Local Storage',
            'tmp'
        )

        foreach ($userProfile in $userProfiles) {
            $teamsAppData = Join-Path $userProfile.LocalPath 'AppData\Roaming\Microsoft\Teams'

            foreach ($cacheFolder in $teamsCacheFolders) {
                $cachePath = Join-Path $teamsAppData $cacheFolder
                if (-not (Test-Path -LiteralPath $cachePath)) {
                    continue
                }

                if ($PSCmdlet.ShouldProcess($cachePath, 'Clear Teams cache folder')) {
                    Get-ChildItem -LiteralPath $cachePath -Force -ErrorAction SilentlyContinue |
                        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Host "[*] Cleared $(Split-Path $cachePath -Leaf) for $(Split-Path $userProfile.LocalPath -Leaf)" -ForegroundColor Cyan
                    $clearedCount++
                }
            }

            # Old logs (older than 7 days) are deleted; recent logs are kept.
            $logsPath = Join-Path $teamsAppData 'logs'
            if (Test-Path -LiteralPath $logsPath) {
                $oldLogs = Get-ChildItem -LiteralPath $logsPath -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }

                foreach ($logFile in $oldLogs) {
                    if ($PSCmdlet.ShouldProcess($logFile.FullName, 'Delete old Teams log file')) {
                        Remove-Item -LiteralPath $logFile.FullName -Force -ErrorAction SilentlyContinue
                        $clearedCount++
                    }
                }
            }
        }

        if ($clearedCount -gt 0) {
            Write-Host "[+] Cleared $clearedCount Teams cache/log location(s); Teams will use a fresh cache on next launch" -ForegroundColor Green
        }
        else {
            Write-Host "[+] Already clean: no Teams cache locations found to clear" -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error clearing Teams caches: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
