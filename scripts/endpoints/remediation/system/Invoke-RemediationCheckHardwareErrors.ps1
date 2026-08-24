<#
.SYNOPSIS
    Provide critical hardware failure remediation guidance.

.DESCRIPTION
    Prints urgent step-by-step guidance for responding to hardware errors covering disk,
    memory, processor/thermal, motherboard/WHEA, USB controller, network adapter and
    battery failures, plus warranty-check advice for IT follow-up. The script is purely
    informational: it changes no system state, so it is safe to re-run at any time
    (idempotent).

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckHardwareErrors.ps1

    Prints the critical hardware failure guidance for this device.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckHardwareErrors.ps1 -Verbose

    Runs the same report with verbose progress information.

.NOTES
    File Name  : Invoke-RemediationCheckHardwareErrors.ps1
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
        Write-Host "[!] CRITICAL: Hardware Error Remediation" -ForegroundColor Yellow
        Write-Host "========================================"
        Write-Host ""
        Write-Host "Hardware errors can lead to data loss and system failure."
        Write-Host "[!] IMMEDIATE ACTIONS REQUIRED:" -ForegroundColor Yellow
        Write-Host ""

        Write-Host "1. DISK FAILURES (HIGHEST PRIORITY)"
        Write-Host "   [!] BACK UP ALL CRITICAL DATA IMMEDIATELY"
        Write-Host "   - Use cloud backup or external drive"
        Write-Host "   - Do not delay - disk can fail at any time"
        Write-Host "   - Check SMART status: Get-PhysicalDisk | Get-StorageReliabilityCounter"
        Write-Host "   - Prepare for disk replacement"
        Write-Host ""

        Write-Host "2. MEMORY (RAM) ERRORS"
        Write-Host "   - Run Windows Memory Diagnostic immediately"
        Write-Host "   - Test each RAM module separately"
        Write-Host "   - Memory errors cause data corruption - replace ASAP"
        Write-Host "   - Check for latest BIOS updates"
        Write-Host ""

        Write-Host "3. PROCESSOR/THERMAL ISSUES"
        Write-Host "   - Check system temperatures"
        Write-Host "   - Clean dust from vents and fans"
        Write-Host "   - Ensure adequate ventilation"
        Write-Host "   - Consider thermal paste replacement (older systems)"
        Write-Host "   - Verify CPU cooler is functioning"
        Write-Host ""

        Write-Host "4. MOTHERBOARD/CHIPSET ERRORS (WHEA, PCI)"
        Write-Host "   - Update BIOS/UEFI to latest version"
        Write-Host "   - Update chipset drivers"
        Write-Host "   - Reseat expansion cards"
        Write-Host "   - Check for bulging capacitors"
        Write-Host ""

        Write-Host "5. USB CONTROLLER ISSUES"
        Write-Host "   - Update USB controller drivers"
        Write-Host "   - Update BIOS (fixes USB bugs)"
        Write-Host "   - Disconnect unnecessary USB devices"
        Write-Host "   - Try different USB ports"
        Write-Host ""

        Write-Host "6. NETWORK ADAPTER ERRORS"
        Write-Host "   - Update network adapter drivers"
        Write-Host "   - Update adapter firmware if available"
        Write-Host "   - Consider replacement if errors persist"
        Write-Host ""

        Write-Host "7. BATTERY HARDWARE ERRORS"
        Write-Host "   - Check battery health report"
        Write-Host "   - Schedule battery replacement"
        Write-Host "   [!] Swollen batteries are fire hazard - replace immediately"
        Write-Host ""

        Write-Host "[*] WARRANTY CHECK:" -ForegroundColor Cyan
        Write-Host "  - Verify if device is under warranty"
        Write-Host "  - Contact manufacturer for hardware replacement"
        Write-Host "  - Document all errors for warranty claim"
        Write-Host ""

        Write-Host "========================================"
        Write-Host "[!] CRITICAL ALERT: This device requires immediate IT attention" -ForegroundColor Yellow
        Write-Host "Device: $env:COMPUTERNAME"
        Write-Host "Priority: URGENT - Hardware failure risk"
        Write-Host "Action: Contact IT immediately"
        Write-Host "Report Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Write-Host "========================================"

        Write-Host "[+] Critical hardware failure guidance provided" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error during hardware error remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
