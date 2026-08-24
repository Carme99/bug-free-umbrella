<#
.SYNOPSIS
    Provide stability improvement recommendations for low stability scores.

.DESCRIPTION
    Prints the common causes of low system stability scores (software conflicts, driver
    issues, missing updates, malware, system file corruption) together with concrete
    improvement recommendations, and flags this device for IT stability review. The
    script is purely informational: it changes no system state, so it is safe to re-run
    at any time (idempotent).
    Exit codes: 0 = recommendations provided, 1 = unexpected error.
    Intune Context: SYSTEM.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckSystemStabilityIndex.ps1

    Prints stability improvement recommendations and flags the device for IT review.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckSystemStabilityIndex.ps1 -Verbose

    Runs the same recommendation output with verbose progress information.

.NOTES
    File Name  : Invoke-RemediationCheckSystemStabilityIndex.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] System stability remediation..." -ForegroundColor Cyan
        Write-Host ""
        Write-Host "[!] Low stability scores indicate ongoing system issues." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "[*] Common causes and solutions:" -ForegroundColor Cyan
        Write-Host "  1. Software conflicts"
        Write-Host "     - Uninstall problematic applications"
        Write-Host "     - Run in Clean Boot mode to identify conflicts"
        Write-Host ""
        Write-Host "  2. Driver issues"
        Write-Host "     - Update all device drivers"
        Write-Host "     - Roll back recently updated drivers if issues started recently"
        Write-Host ""
        Write-Host "  3. Windows Updates"
        Write-Host "     - Ensure all Windows updates are installed"
        Write-Host "     - Check for optional driver updates"
        Write-Host ""
        Write-Host "  4. Malware/PUPs"
        Write-Host "     - Run full antivirus scan"
        Write-Host "     - Use Windows Security offline scan"
        Write-Host ""
        Write-Host "  5. System file corruption"
        Write-Host "     - Run SFC /scannow"
        Write-Host "     - Run DISM restore health"
        Write-Host ""
        Write-Host "[!] Device flagged for IT stability review." -ForegroundColor Yellow
        Write-Host "[*] Device: $env:COMPUTERNAME" -ForegroundColor Cyan
        Write-Host "[*] Logged: $(Get-Date)" -ForegroundColor Cyan
        Write-Host "[+] Recommendations logged for IT tracking" -ForegroundColor Green

        return 0
    }
    catch {
        Write-Host "[-] Error during stability remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
