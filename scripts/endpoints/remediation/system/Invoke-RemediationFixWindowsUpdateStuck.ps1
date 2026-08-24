<#
.SYNOPSIS
    Reset Windows Update components for a genuinely stuck update state.

.DESCRIPTION
    Resets Windows Update components when the pending state persisted for more than
    7 days (as detected by the companion detect script): removes the stuck-state
    first-seen marker, stops WU services, renames SoftwareDistribution and catroot2
    so they are recreated, and restarts the services. Side effects: service restart,
    rename of the two update cache folders (downloads are re-fetched automatically)
    and deletion of the first-seen marker key; every mutation is gated behind
    -WhatIf/-Confirm via SupportsShouldProcess. When the marker is gone and both
    cache folders were already renamed, nothing is changed and the script exits 0
    (idempotent).
    Exit codes: 0 = reset complete or already reset; 1 = an unexpected error
    occurred. For Intune Proactive Remediations, Intune Context: SYSTEM.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixWindowsUpdateStuck.ps1

    Stops the WU services, renames SoftwareDistribution/catroot2 and restarts them.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixWindowsUpdateStuck.ps1 -WhatIf

    Shows which reset steps would run without stopping services or renaming folders.

.NOTES
    File Name  : Invoke-RemediationFixWindowsUpdateStuck.ps1
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
        Write-Host "[*] Resetting Windows Update components..." -ForegroundColor Cyan

        $wuServices = @('wuauserv', 'cryptSvc', 'bits', 'msiserver')
        $markerPath = 'HKLM:\SOFTWARE\BugFreeUmbrella\WUStuckFirstSeen'
        $wuCachePath = Join-Path $env:SystemRoot 'SoftwareDistribution'
        $catrootPath = Join-Path $env:SystemRoot 'System32\catroot2'

        $markerExists = Test-Path $markerPath
        $wuCacheExists = Test-Path $wuCachePath
        $catrootExists = Test-Path $catrootPath

        # Check-then-act: nothing to reset when the marker is gone and both cache
        # folders were already renamed by an earlier reset run.
        if (-not ($markerExists -or $wuCacheExists -or $catrootExists)) {
            Write-Host "[+] Already reset: no stuck Windows Update state found" -ForegroundColor Green
            return 0
        }

        # Clear the first-seen marker used by detect.ps1 - the reset restarts the
        # pending-state timer; otherwise a legitimately re-pending update would be
        # flagged as stuck again on the very next cycle.
        if ($markerExists) {
            if ($PSCmdlet.ShouldProcess($markerPath, 'Remove stuck-state first-seen marker key')) {
                Remove-Item -Path $markerPath -Force -ErrorAction SilentlyContinue
            }
        }

        # Stop services so the cache folders are not locked while renaming.
        if ($PSCmdlet.ShouldProcess(($wuServices -join ', '), 'Stop Windows Update services')) {
            Stop-Service -Name $wuServices -Force -ErrorAction Stop
        }

        if ($wuCacheExists) {
            if ($PSCmdlet.ShouldProcess($wuCachePath, 'Rename Windows Update cache to SoftwareDistribution.old')) {
                Rename-Item -Path $wuCachePath -NewName 'SoftwareDistribution.old' -Force -ErrorAction Stop
            }
        }

        if ($catrootExists) {
            if ($PSCmdlet.ShouldProcess($catrootPath, 'Rename crypto catalog cache to catroot2.old')) {
                Rename-Item -Path $catrootPath -NewName 'catroot2.old' -Force -ErrorAction Stop
            }
        }

        # Restart the Windows Update services.
        if ($PSCmdlet.ShouldProcess(($wuServices -join ', '), 'Restart Windows Update services')) {
            Start-Service -Name $wuServices -ErrorAction SilentlyContinue
        }

        Write-Host "[+] Windows Update reset complete" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error resetting Windows Update components: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
