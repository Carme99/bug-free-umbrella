<#
.SYNOPSIS
    Provides guidance for critical system errors.

.DESCRIPTION
    Critical system errors require immediate IT attention. This script logs
    the errors for investigation and provides troubleshooting guidance.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Guidance provided
#>

try {
    Write-Host "Critical System Event Remediation:"
    Write-Host ""
    Write-Host "Critical system errors require immediate investigation."
    Write-Host ""
    Write-Host "Priority actions based on error type:"
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
    Write-Host "URGENT: Device flagged for immediate IT investigation."
    Write-Host "Device: $env:COMPUTERNAME"
    Write-Host "Action Required: Review event logs and take corrective action"

    exit 0

}
catch {
    Write-Host "Error during system event remediation: $_"
    exit 1
}
