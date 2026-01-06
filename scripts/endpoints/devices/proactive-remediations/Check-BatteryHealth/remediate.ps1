<#
.SYNOPSIS
    Reports battery health degradation.

.DESCRIPTION
    Battery degradation cannot be fixed in software. This script generates
    a detailed report for IT to track devices needing battery replacement.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Report generated
#>

try {
    # Generate detailed battery report
    powercfg /batteryreport /output "$env:TEMP\battery-report.html" | Out-Null

    $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue

    if ($battery) {
        Write-Host "Battery Health Report:"
        Write-Host "  Device: $env:COMPUTERNAME"
        Write-Host "  Chemistry: $($battery.Chemistry)"
        Write-Host "  Status: $($battery.Status)"
        Write-Host ""
        Write-Host "Battery degradation cannot be fixed in software."
        Write-Host "IT should assess if battery replacement is needed."
        Write-Host ""
        Write-Host "Detailed report generated at: $env:TEMP\battery-report.html"
        Write-Host "This information has been logged for IT tracking."
    }

    exit 0

} catch {
    Write-Host "Error generating battery report: $_"
    exit 1
}
