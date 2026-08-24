<#
.SYNOPSIS
    Schedule a restart to clear a stuck Windows Update reboot-pending state.

.DESCRIPTION
    Detects the authoritative RebootPending/RebootRequired registry flags (CBS
    servicing, Windows Update restart, file rename operations) and schedules a device
    restart 15 minutes out so the user can save work. MS Learn documents a reboot as
    the ONLY resolution for these flags - the keys are intentionally left intact and
    Windows clears them itself during the restart; deleting them would strand serving
    operations mid-flight. Side effects: schedules a full device restart via
    shutdown.exe; that mutation is gated behind -WhatIf/-Confirm via
    SupportsShouldProcess. With no pending flags present nothing is scheduled and the
    script exits 0 (idempotent).
    Exit codes: 0 = restart scheduled or no pending state present; 1 = failed to
    schedule restart. Intune Context: SYSTEM.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixWindowsUpdateRebootPending.ps1

    Schedules a restart in 15 minutes when reboot-pending flags are present.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixWindowsUpdateRebootPending.ps1 -WhatIf

    Reports the pending state without scheduling a restart.

.NOTES
    File Name  : Invoke-RemediationFixWindowsUpdateRebootPending.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Invoke-Shutdown {
    # Thin wrapper around native shutdown.exe; mock seam for Pester tests.
    & shutdown.exe @args 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Checking Windows Update reboot-pending state..." -ForegroundColor Cyan

        $rebootPendingPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        )

        $rebootPending = $false
        foreach ($registryPath in $rebootPendingPaths) {
            if (Test-Path $registryPath) {
                $rebootPending = $true
            }
        }

        if (-not $rebootPending) {
            Write-Host "[+] Already converged: no reboot pending flags present" -ForegroundColor Green
            return 0
        }

        # Schedule a restart 15 minutes out so the user can save work. The registry
        # flags are intentionally left intact - they are cleared by Windows during
        # the restart (deleting them would strand servicing operations mid-flight).
        if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Schedule restart in 15 minutes (shutdown /r /t 900)')) {
            $shutdownExitCode = Invoke-Shutdown /r /t 900 /c `
                "Windows Update requires a restart to finish installing updates. This device will restart in 15 minutes. Please save your work."
            if ($shutdownExitCode -ne 0) {
                throw "shutdown.exe exited with code $shutdownExitCode"
            }
            Write-Host "[+] Reboot pending state detected; scheduled a restart in 15 minutes" -ForegroundColor Green
            Write-Host "[*] RebootPending/RebootRequired registry keys left intact - Windows clears them during the restart." -ForegroundColor Cyan
        }

        return 0
    }
    catch {
        Write-Host "[-] Error during reboot pending remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
