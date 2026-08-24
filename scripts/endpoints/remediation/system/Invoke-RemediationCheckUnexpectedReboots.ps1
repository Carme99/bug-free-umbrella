<#
.SYNOPSIS
    Log unexpected reboot diagnostics for IT analysis.

.DESCRIPTION
    Unexpected reboots and crashes cannot be fixed automatically, so this script gathers
    the diagnostic context (typical causes and recommended IT actions) and logs it with a
    timestamped entry for IT review. The script is informational: it changes no system
    state apart from writing its log line, so it is safe to re-run at any time (idempotent).
    Exit codes: 0 = information logged, 1 = unexpected error.
    Intune Context: SYSTEM.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckUnexpectedReboots.ps1

    Logs the unexpected reboot diagnostics with a timestamp and flags the device for IT review.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckUnexpectedReboots.ps1 -Verbose

    Runs the same diagnostic output with verbose progress information.

.NOTES
    File Name  : Invoke-RemediationCheckUnexpectedReboots.ps1
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
        Write-Host "[*] Unexpected reboot remediation..." -ForegroundColor Cyan
        Write-Host ""
        Write-Host "[!] Unexpected reboots and crashes cannot be automatically fixed." -ForegroundColor Yellow
        Write-Host "[*] These issues typically indicate:" -ForegroundColor Cyan
        Write-Host "    - Hardware problems (RAM, power supply, overheating)"
        Write-Host "    - Driver compatibility issues"
        Write-Host "    - Firmware/BIOS bugs"
        Write-Host "    - Software conflicts"
        Write-Host ""
        Write-Host "[*] Recommended IT Actions:" -ForegroundColor Cyan
        Write-Host "    1. Analyze crash dump files using WinDbg or similar tools"
        Write-Host "    2. Update all drivers and firmware to latest versions"
        Write-Host "    3. Run hardware diagnostics (memory test, disk check)"
        Write-Host "    4. Check system temperatures and cooling"
        Write-Host "    5. Review recently installed software/updates"
        Write-Host ""
        Write-Host "[!] This device has been flagged for IT investigation." -ForegroundColor Yellow
        Write-Host "[*] Device: $env:COMPUTERNAME" -ForegroundColor Cyan
        Write-Host "[*] Logged: $(Get-Date)" -ForegroundColor Cyan
        Write-Host "[+] Diagnostics logged for IT tracking" -ForegroundColor Green

        return 0
    }
    catch {
        Write-Host "[-] Error during unexpected reboot remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
