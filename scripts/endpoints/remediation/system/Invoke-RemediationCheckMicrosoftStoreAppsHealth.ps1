<#
.SYNOPSIS
    Repair Microsoft Store apps registration issues.

.DESCRIPTION
    Re-registers AppX packages that are in an error state and resets the Windows Store
    cache via wsreset when any package needed repair. Re-running on an already-healthy
    device finds no error-state packages, makes no changes and still exits 0 (idempotent).
    The re-registration and cache reset are gated behind -WhatIf/-Confirm via
    SupportsShouldProcess.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckMicrosoftStoreAppsHealth.ps1

    Re-registers every AppX package in an error state and resets the Store cache.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckMicrosoftStoreAppsHealth.ps1 -WhatIf

    Shows which packages would be re-registered without changing anything.

.NOTES
    File Name  : Invoke-RemediationCheckMicrosoftStoreAppsHealth.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Invoke-WsReset {
    # Thin wrapper around the native wsreset.exe executable.
    # Exists as the mock seam for Pester tests (native commands cannot be mocked).
    & wsreset.exe @args 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Repairing Microsoft Store apps registration issues..." -ForegroundColor Cyan

        # Get packages in error state.
        $appxPackages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        $errorPackages = @($appxPackages | Where-Object { $_.Status -ne 'Ok' })

        $remediationActions = @()

        foreach ($package in $errorPackages) {
            if ($PSCmdlet.ShouldProcess($package.Name, 'Re-register AppX package')) {
                Add-AppxPackage -DisableDevelopmentMode -Register "$($package.InstallLocation)\AppXManifest.xml" -ErrorAction Stop
                $remediationActions += "Re-registered $($package.Name)"
            }
        }

        # Re-register the Store app itself if it is still in an error state.
        $storeApp = Get-AppxPackage -Name 'Microsoft.WindowsStore' -AllUsers -ErrorAction SilentlyContinue
        if ($storeApp -and $storeApp.Status -ne 'Ok') {
            if ($PSCmdlet.ShouldProcess('Microsoft.WindowsStore', 'Re-register Microsoft Store app')) {
                Add-AppxPackage -DisableDevelopmentMode -Register "$($storeApp.InstallLocation)\AppXManifest.xml" -ErrorAction Stop
                $remediationActions += 'Re-registered Microsoft Store app'
            }
        }

        if ($remediationActions.Count -gt 0) {
            # Only reset the Store cache when a repair was actually needed.
            if ($PSCmdlet.ShouldProcess('Windows Store cache', 'Reset Store cache via wsreset')) {
                $wsResetExitCode = Invoke-WsReset
                if ($wsResetExitCode -ne 0) {
                    Write-Host "[!] wsreset exited with code $wsResetExitCode" -ForegroundColor Yellow
                }
                else {
                    $remediationActions += 'Reset Windows Store cache'
                }
            }

            Write-Host "[+] Store apps remediation completed:" -ForegroundColor Green
            foreach ($action in $remediationActions) {
                Write-Host "  - $action"
            }
        }
        else {
            Write-Host "[+] Already healthy: no Store apps required remediation" -ForegroundColor Green
        }
        return 0
    }
    catch {
        Write-Host "[-] Error during Store apps remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
