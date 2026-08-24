<#
.SYNOPSIS
    Enable the system-managed page file when it is completely disabled.

.DESCRIPTION
    Checks the page file configuration and enables the system-managed page file ONLY
    when it is completely disabled (automatic management off AND no page file settings
    exist). Custom page file configurations are intentionally left untouched because
    they may be deliberate (SQL Server, crash dump requirements, performance tuning).
    Side effects: when remediation fires, Win32_ComputerSystem.AutomaticManagedPagefile
    is set to $true via CIM - a change that requires a restart to take effect. Every
    mutation is gated behind -WhatIf/-Confirm via SupportsShouldProcess. Re-running on
    an already-converged system makes no changes and exits 0 (idempotent).
    Exit codes: 0 = compliant or remediated, 1 = unexpected error.
    Intune Context: SYSTEM.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckPageFileConfiguration.ps1

    Enables the system-managed page file if it is disabled; leaves custom configurations alone.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckPageFileConfiguration.ps1 -WhatIf

    Reports what would change without modifying the page file configuration.

.NOTES
    File Name  : Invoke-RemediationCheckPageFileConfiguration.ps1
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
        Write-Host "[*] Checking page file configuration..." -ForegroundColor Cyan

        # SAFETY CHECK: Only remediate if the page file is COMPLETELY DISABLED.
        # Do NOT touch custom page file configurations - they may be intentional
        # (e.g., SQL Server, crash dump requirements, performance tuning).
        $compSys = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $pageFiles = Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue

        if ($compSys.AutomaticManagedPagefile -eq $false -and (-not $pageFiles)) {
            Write-Host "[*] Page file is completely disabled. Enabling system-managed page file..." -ForegroundColor Cyan

            if ($PSCmdlet.ShouldProcess($compSys.Name, "Enable system-managed page file")) {
                $compSys.AutomaticManagedPagefile = $true
                Set-CimInstance -CimInstance $compSys -ErrorAction Stop
                Write-Host "[+] Enabled system-managed page file" -ForegroundColor Green
            }

            Write-Host "[!] IMPORTANT: A system restart is required for changes to take effect" -ForegroundColor Yellow
        }
        elseif ($pageFiles) {
            # Custom page file exists - don't touch it even if undersized.
            Write-Host "[*] Custom page file configuration detected:" -ForegroundColor Cyan
            foreach ($pf in $pageFiles) {
                Write-Host "    - $($pf.Name): Initial=$($pf.InitialSize)MB, Maximum=$($pf.MaximumSize)MB"
            }
            Write-Host ""
            Write-Host "[!] NOTICE: Custom page file configurations are not automatically changed." -ForegroundColor Yellow
            Write-Host "[!] If this configuration is unintentional, manually review and adjust." -ForegroundColor Yellow
            Write-Host "[*] Custom configurations may be required for:" -ForegroundColor Cyan
            Write-Host "    - SQL Server performance"
            Write-Host "    - Complete memory dump collection"
            Write-Host "    - Application-specific requirements"
            Write-Host "[+] No changes made: custom page file configuration preserved" -ForegroundColor Green
        }
        else {
            Write-Host "[+] Already configured: page file is system-managed" -ForegroundColor Green
        }

        return 0
    }
    catch {
        Write-Host "[-] Error during page file remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
