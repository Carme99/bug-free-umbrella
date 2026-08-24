<#
.SYNOPSIS
    Repair Windows Store licensing by resetting the license token cache.

.DESCRIPTION
    Repairs broken Windows Store licensing using the documented MS Learn sequence
    ("Rebuild the tokens.dat file"): stops the Client License Service (ClipSVC),
    deletes %ProgramData%\Microsoft\Windows\ClipSVC\tokens.dat so ClipSVC rebuilds it
    on restart, re-registers the Microsoft Store app package and resets the Store
    cache. Side effects: ClipSVC service restart, deletion of the licensing token
    cache and Store app re-registration; every mutation is gated behind
    -WhatIf/-Confirm via SupportsShouldProcess. When no token cache exists there is
    nothing to rebuild, so the script makes no changes and exits 0 (idempotent).
    Exit codes: 0 = remediation complete or nothing to do; 1 = an unexpected error
    occurred. Intune Context: SYSTEM.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixWindowsStoreLicensing.ps1

    Rebuilds the Store licensing token cache and re-registers the Store app.

.EXAMPLE
    PS C:\> .\Invoke-RemediationFixWindowsStoreLicensing.ps1 -WhatIf

    Shows which licensing repair steps would run without changing anything.

.NOTES
    File Name  : Invoke-RemediationFixWindowsStoreLicensing.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Invoke-Wsreset {
    # Thin wrapper around native wsreset.exe; mock seam for Pester tests.
    & wsreset.exe @args 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Repairing Windows Store licensing..." -ForegroundColor Cyan

        # Check-then-act: no token cache means nothing to reset or rebuild.
        $tokensPath = Join-Path $env:ProgramData 'Microsoft\Windows\ClipSVC\tokens.dat'
        if (-not (Test-Path $tokensPath)) {
            Write-Host "[+] Already clean: no Store licensing token cache to rebuild" -ForegroundColor Green
            return 0
        }

        $storeService = Get-Service -Name 'ClipSVC' -ErrorAction SilentlyContinue

        # MS Learn "Rebuild the tokens.dat file": stop ClipSVC before deleting the
        # file (deleting while ClipSVC is running can corrupt licensing state),
        # delete, then restart so ClipSVC rebuilds tokens.dat on startup.
        if ($storeService -and $storeService.Status -eq 'Running') {
            if ($PSCmdlet.ShouldProcess('ClipSVC', 'Stop Client License Service')) {
                Stop-Service -Name 'ClipSVC' -Force -ErrorAction Stop
                Write-Host "[+] Stopped Client License Service (ClipSVC)" -ForegroundColor Green
            }
        }

        if ($PSCmdlet.ShouldProcess($tokensPath, 'Delete Store licensing token cache')) {
            Remove-Item -LiteralPath $tokensPath -Force -ErrorAction Stop
            Write-Host "[+] Removed Store licensing cache: $tokensPath" -ForegroundColor Green
        }

        if ($storeService) {
            if ($PSCmdlet.ShouldProcess('ClipSVC', 'Start Client License Service')) {
                Start-Service -Name 'ClipSVC' -ErrorAction Stop
                Start-Sleep -Seconds 2
                Write-Host "[+] Started Client License Service (ClipSVC)" -ForegroundColor Green
            }
        }

        # Re-register the Store app.
        $storeApp = Get-AppxPackage -Name 'Microsoft.WindowsStore' -AllUsers -ErrorAction SilentlyContinue
        if ($storeApp) {
            if ($PSCmdlet.ShouldProcess('Microsoft.WindowsStore', 'Re-register Store app package')) {
                Add-AppxPackage -DisableDevelopmentMode `
                    -Register "$($storeApp.InstallLocation)\AppXManifest.xml" -ErrorAction Stop
                Write-Host "[+] Re-registered Microsoft Store app" -ForegroundColor Green
            }
        }

        if ($PSCmdlet.ShouldProcess('Windows Store', 'Reset Store cache (wsreset.exe)')) {
            $null = Invoke-Wsreset
            Write-Host "[+] Reset Windows Store cache" -ForegroundColor Green
        }

        Write-Host "[+] Windows Store licensing remediation completed" -ForegroundColor Green
        Write-Host "[*] Users may need to sign out and back in for changes to take effect." -ForegroundColor Cyan
        return 0
    }
    catch {
        Write-Host "[-] Error during Windows Store licensing remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
