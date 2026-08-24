<#
.SYNOPSIS
    Trigger Windows activation before the grace period expires.

.DESCRIPTION
    Runs slmgr.vbs /ato via cscript to trigger Windows activation, then refreshes the
    license status through the SoftwareLicensingService CIM class so the renewed grace
    period or activation state is reflected immediately. Side effects: an activation
    attempt against Microsoft licensing services and a license status refresh - both are
    system state changes gated behind -WhatIf/-Confirm via SupportsShouldProcess.
    Re-running on an already-activated device is a harmless no-op that exits 0 (idempotent).
    Exit codes: 0 = activation triggered or already handled, 1 = unexpected error.
    Intune Context: SYSTEM.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckWindowsActivationGracePeriod.ps1

    Triggers Windows activation and refreshes the license status.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckWindowsActivationGracePeriod.ps1 -WhatIf

    Reports what would be attempted without touching licensing state.

.NOTES
    File Name  : Invoke-RemediationCheckWindowsActivationGracePeriod.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Invoke-Cscript {
    # Thin wrapper around the native cscript.exe executable.
    # Exists as the mock seam for Pester tests (native commands cannot be mocked).
    & cscript.exe @args 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Attempting to activate Windows..." -ForegroundColor Cyan

        if ($PSCmdlet.ShouldProcess('Windows Software Licensing', 'Trigger Windows activation')) {
            # Windows sets SystemRoot; fall back to the default install path when unset.
            $windowsDir = $env:SystemRoot
            if (-not $windowsDir) {
                $windowsDir = 'C:\Windows'
            }
            $slmgrPath = "$windowsDir\System32\slmgr.vbs"
            $activateExitCode = Invoke-Cscript //nologo $slmgrPath /ato

            if ($activateExitCode -eq 0) {
                Write-Host "[+] Triggered Windows activation" -ForegroundColor Green
            }
            else {
                Write-Host "[!] Activation initiated (may require additional time)" -ForegroundColor Yellow
            }
        }

        # Refresh license status so the current state is reported immediately.
        $licensingService = Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction SilentlyContinue
        if ($licensingService) {
            if ($PSCmdlet.ShouldProcess('SoftwareLicensingService', 'Refresh license status')) {
                Invoke-CimMethod -InputObject $licensingService -MethodName RefreshLicenseStatus -ErrorAction Stop | Out-Null
                Write-Host "[+] Refreshed license status" -ForegroundColor Green
            }
        }

        Write-Host ""
        Write-Host "[*] Note: Verify activation status in Settings > Update & Security > Activation" -ForegroundColor Cyan

        return 0
    }
    catch {
        Write-Host "[-] Error during grace period remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
