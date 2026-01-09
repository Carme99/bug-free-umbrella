<#
.SYNOPSIS
    Logs unexpected reboot information for IT analysis.

.DESCRIPTION
    Unexpected reboots and crashes require investigation. This script gathers
    diagnostic information and logs it for IT review.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Information logged
#>

try {
    Write-Host "Unexpected Reboot Remediation:"
    Write-Host ""
    Write-Host "Unexpected reboots and crashes cannot be automatically fixed."
    Write-Host "These issues typically indicate:"
    Write-Host "  - Hardware problems (RAM, power supply, overheating)"
    Write-Host "  - Driver compatibility issues"
    Write-Host "  - Firmware/BIOS bugs"
    Write-Host "  - Software conflicts"
    Write-Host ""
    Write-Host "Recommended IT Actions:"
    Write-Host "  1. Analyze crash dump files using WinDbg or similar tools"
    Write-Host "  2. Update all drivers and firmware to latest versions"
    Write-Host "  3. Run hardware diagnostics (memory test, disk check)"
    Write-Host "  4. Check system temperatures and cooling"
    Write-Host "  5. Review recently installed software/updates"
    Write-Host ""
    Write-Host "This device has been flagged for IT investigation."
    Write-Host "Device: $env:COMPUTERNAME"
    Write-Host "Logged: $(Get-Date)"

    exit 0

} catch {
    Write-Host "Error during unexpected reboot remediation: $_"
    exit 1
}
