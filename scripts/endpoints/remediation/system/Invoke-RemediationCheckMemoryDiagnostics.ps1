<#
.SYNOPSIS
    Schedule Windows Memory Diagnostic on next reboot.

.DESCRIPTION
    Queues the Windows Memory Diagnostic tool to run before Windows starts on the next
    reboot so memory errors can be tested in detail, first relaxing the BCD boot status
    policy via bcdedit. Scheduling is detected through the {memdiag} bootsequence entry,
    so re-running on a device that already has a diagnostic queued makes no changes and
    still exits 0 (idempotent). Both mutations are gated behind -WhatIf/-Confirm via
    SupportsShouldProcess.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckMemoryDiagnostics.ps1

    Schedules the Windows Memory Diagnostic for the next reboot unless already queued.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckMemoryDiagnostics.ps1 -WhatIf

    Shows which scheduling steps would run without changing the boot configuration.

.NOTES
    File Name  : Invoke-RemediationCheckMemoryDiagnostics.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Get-BcdBootSequence {
    # Thin read-only wrapper around the native bcdedit.exe executable.
    # Exists as the mock seam for Pester tests (native commands cannot be mocked).
    & bcdedit.exe /enum '{bootmgr}' 2>&1
}

function Invoke-BcdEdit {
    # Thin wrapper around the native bcdedit.exe executable.
    # Exists as the mock seam for Pester tests (native commands cannot be mocked).
    & bcdedit.exe @args 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Invoke-MdSched {
    # Thin wrapper around the native MdSched.exe executable.
    # Exists as the mock seam for Pester tests (native commands cannot be mocked).
    & MdSched.exe @args 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Memory diagnostic remediation:" -ForegroundColor Cyan

        # Check-then-act: a queued diagnostic shows up as a bootsequence entry pointing
        # at the {memdiag} boot application - never queue a second one.
        $bootManagerOutput = (Get-BcdBootSequence | Out-String)
        if ($bootManagerOutput -match 'memdiag') {
            Write-Host "[+] Already scheduled: Windows Memory Diagnostic is queued for next reboot" -ForegroundColor Green
            return 0
        }

        # Relax the boot status policy so a failed early boot does not enter recovery.
        if ($PSCmdlet.ShouldProcess('BCD default entry', 'Set bootstatuspolicy to ignoreallfailures')) {
            $bcdExitCode = Invoke-BcdEdit /set '{default}' bootstatuspolicy ignoreallfailures
            if ($bcdExitCode -ne 0) {
                throw "bcdedit failed with exit code $bcdExitCode"
            }
        }

        # Queue the diagnostic for the next reboot.
        if ($PSCmdlet.ShouldProcess('Windows Memory Diagnostic', 'Schedule diagnostic for next reboot')) {
            $memDiagExitCode = Invoke-MdSched /v
            if ($memDiagExitCode -ne 0) {
                throw "MdSched failed with exit code $memDiagExitCode"
            }
            Write-Host "[+] Scheduled Windows Memory Diagnostic for next reboot" -ForegroundColor Green
        }

        Write-Host ""
        Write-Host "[*] IMPORTANT:" -ForegroundColor Cyan
        Write-Host "  - User will be prompted to restart the computer"
        Write-Host "  - Memory test will run before Windows starts"
        Write-Host "  - Test takes 10-20 minutes depending on RAM size"
        Write-Host "  - Results will be available in Event Viewer after boot"
        Write-Host ""
        Write-Host "[!] If memory errors are confirmed, RAM replacement is required" -ForegroundColor Yellow
        return 0
    }
    catch {
        Write-Host "[-] Error scheduling memory diagnostic: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
