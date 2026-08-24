<#
.SYNOPSIS
    Repair Windows licensing by triggering online product activation.

.DESCRIPTION
    Attempts to reactivate Windows online using slmgr.vbs (/ato) and refreshes the
    license status afterwards so the licensing platform picks up digital entitlements.
    Side effects: sends an activation request to Microsoft and refreshes the local
    license state; every mutation is gated behind -WhatIf/-Confirm via
    SupportsShouldProcess. When Windows already reports an active license the script
    makes no changes and still exits 0 (idempotent).
    Exit codes: 0 = activation triggered, already active, or attempted without hard
    failure; 1 = an unexpected error occurred. Intune Context: SYSTEM.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixWindowsLicenseActivation.ps1

    Triggers online Windows activation and refreshes the license status.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixWindowsLicenseActivation.ps1 -WhatIf

    Shows which activation steps would run without contacting the activation service.

.NOTES
    File Name  : Invoke-RemediationFixWindowsLicenseActivation.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Invoke-CScript {
    # Thin wrapper around native cscript.exe; mock seam for Pester tests.
    & cscript.exe @args 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Repairing Windows license activation..." -ForegroundColor Cyan

        # Check-then-act: a fully licensed, already-active device needs no activation.
        $licensedProducts = Get-CimInstance -ClassName SoftwareLicensingProduct `
            -Filter "PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue |
            Where-Object { $_.LicenseStatus -eq 1 }
        if ($licensedProducts) {
            Write-Host "[+] Already activated: Windows license is active, no changes made" -ForegroundColor Green
            return 0
        }

        $slmgrPath = Join-Path $env:SystemRoot "System32\slmgr.vbs"

        # Trigger online activation.
        if ($PSCmdlet.ShouldProcess('Windows product license', 'Trigger online activation (slmgr.vbs /ato)')) {
            $activateExitCode = Invoke-CScript //nologo $slmgrPath /ato
            if ($activateExitCode -eq 0) {
                Write-Host "[+] Successfully triggered Windows activation" -ForegroundColor Green
            }
            else {
                Write-Host "[!] Activation attempt completed (may require additional steps)" -ForegroundColor Yellow
            }
        }

        # Record the resulting license state in the log.
        if ($PSCmdlet.ShouldProcess('Windows product license', 'Show license status (slmgr.vbs /dli)')) {
            $null = Invoke-CScript //nologo $slmgrPath /dli
        }

        # Refresh the licensing platform state via WMI as well.
        $licensingService = Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction SilentlyContinue
        if ($licensingService) {
            if ($PSCmdlet.ShouldProcess('SoftwareLicensingService', 'Refresh license status via WMI')) {
                $null = $licensingService.RefreshLicenseStatus()
                Write-Host "[+] Refreshed license status" -ForegroundColor Green
            }
        }

        Write-Host "[*] If activation still fails verify: internet connectivity, an installed" -ForegroundColor Cyan
        Write-Host "[*] valid license key (slmgr /ipk), or a digital entitlement linked to a" -ForegroundColor Cyan
        Write-Host "[*] Microsoft account." -ForegroundColor Cyan
        return 0
    }
    catch {
        Write-Host "[-] Error during Windows activation remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
