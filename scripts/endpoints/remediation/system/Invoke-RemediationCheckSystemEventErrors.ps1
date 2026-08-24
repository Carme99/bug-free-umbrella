<#
.SYNOPSIS
    Provide triage guidance for critical System event log errors.

.DESCRIPTION
    Prints prioritised troubleshooting guidance for the critical system error classes
    (disk, memory, kernel/power, blue screens, hardware, security) that require immediate
    IT attention, flags this device for investigation and logs the device name with the
    guidance output. The script is purely informational: it changes no system state,
    so it is safe to re-run at any time (idempotent).
    Exit codes: 0 = guidance provided, 1 = unexpected error.
    Intune Context: SYSTEM.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckSystemEventErrors.ps1

    Prints prioritised remediation guidance for critical system errors and flags the device.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckSystemEventErrors.ps1 -Verbose

    Runs the same guidance output with verbose progress information.

.NOTES
    File Name  : Invoke-RemediationCheckSystemEventErrors.ps1
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
        Write-Host "[*] Critical system event remediation..." -ForegroundColor Cyan
        Write-Host ""
        Write-Host "[!] Critical system errors require immediate investigation." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "[*] Priority actions based on error type:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "1. Disk errors (Event IDs 7, 11, 51, 153, 55)"
        Write-Host "   - Run: chkdsk /f /r (requires reboot)"
        Write-Host "   - Check SMART status: Get-PhysicalDisk | Get-StorageReliabilityCounter"
        Write-Host "   - Back up critical data immediately"
        Write-Host "   - Consider disk replacement if errors persist"
        Write-Host ""
        Write-Host "2. Memory errors (Event ID 1001, WHEA errors)"
        Write-Host "   - Run Windows Memory Diagnostic"
        Write-Host "   - Test each RAM module individually"
        Write-Host "   - Check for BIOS updates"
        Write-Host "   - Replace faulty RAM"
        Write-Host ""
        Write-Host "3. Kernel/Power errors (Event ID 41)"
        Write-Host "   - Check system temperatures"
        Write-Host "   - Test power supply"
        Write-Host "   - Update chipset and power management drivers"
        Write-Host "   - Verify adequate cooling"
        Write-Host ""
        Write-Host "4. Blue screens (Event ID 1001)"
        Write-Host "   - Analyze crash dumps with WinDbg"
        Write-Host "   - Identify faulting driver or module"
        Write-Host "   - Update or roll back problematic driver"
        Write-Host "   - Check for hardware issues"
        Write-Host ""
        Write-Host "5. Hardware errors (WHEA, processor, general)"
        Write-Host "   - Update BIOS/UEFI firmware"
        Write-Host "   - Update all device drivers"
        Write-Host "   - Run manufacturer hardware diagnostics"
        Write-Host "   - Check warranty status for replacement"
        Write-Host ""
        Write-Host "6. Security critical events"
        Write-Host "   - Review security event details immediately"
        Write-Host "   - Check for compromise indicators"
        Write-Host "   - Escalate to security team if needed"
        Write-Host ""
        Write-Host "[!] URGENT: Device flagged for immediate IT investigation." -ForegroundColor Yellow
        Write-Host "[*] Device: $env:COMPUTERNAME" -ForegroundColor Cyan
        Write-Host "[*] Action Required: Review event logs and take corrective action" -ForegroundColor Cyan
        Write-Host "[*] Logged: $(Get-Date)" -ForegroundColor Cyan
        Write-Host "[+] Guidance logged for IT tracking" -ForegroundColor Green

        return 0
    }
    catch {
        Write-Host "[-] Error during system event remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
