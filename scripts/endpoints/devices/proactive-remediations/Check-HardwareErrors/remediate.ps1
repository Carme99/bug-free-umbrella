<#
.SYNOPSIS
    Provides critical hardware failure guidance.

.DESCRIPTION
    Hardware failures require immediate action to prevent data loss.
    This script logs hardware errors and provides urgent remediation steps.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Critical guidance provided
#>

try {
    Write-Host "CRITICAL: Hardware Error Remediation"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Hardware errors can lead to data loss and system failure."
    Write-Host "IMMEDIATE ACTIONS REQUIRED:"
    Write-Host ""
    Write-Host "1. DISK FAILURES (HIGHEST PRIORITY)"
    Write-Host "   ⚠ BACK UP ALL CRITICAL DATA IMMEDIATELY"
    Write-Host "   - Use cloud backup or external drive"
    Write-Host "   - Do not delay - disk can fail at any time"
    Write-Host "   - Check SMART status: wmic diskdrive get status"
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
    Write-Host "   - Swollen batteries are fire hazard - replace immediately"
    Write-Host ""
    Write-Host "WARRANTY CHECK:"
    Write-Host "  - Verify if device is under warranty"
    Write-Host "  - Contact manufacturer for hardware replacement"
    Write-Host "  - Document all errors for warranty claim"
    Write-Host ""
    Write-Host "========================================"
    Write-Host "CRITICAL ALERT: This device requires immediate IT attention"
    Write-Host "Device: $env:COMPUTERNAME"
    Write-Host "Priority: URGENT - Hardware failure risk"
    Write-Host "Action: Contact IT immediately"
    Write-Host "========================================"

    exit 0

} catch {
    Write-Host "Error during hardware error remediation: $_"
    exit 1
}
