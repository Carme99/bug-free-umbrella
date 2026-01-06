<#
.SYNOPSIS
    Checks laptop battery health and capacity degradation.

.DESCRIPTION
    Monitors battery design capacity vs current full charge capacity to
    detect battery degradation on laptops.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Battery is healthy or not applicable
    Exit 1: Battery degradation detected

.CONFIGURATION
    $degradationThreshold: Warn when battery capacity drops below this percentage (default: 70%)
#>

try {
    # Configuration
    $degradationThreshold = 70  # Percentage

    # Check if device has a battery
    $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue

    if (-not $battery) {
        Write-Host "No battery detected (desktop or battery not present)"
        exit 0
    }

    $issues = @()

    # Get battery report
    powercfg /batteryreport /output "$env:TEMP\battery-report.xml" /xml | Out-Null

    if (Test-Path "$env:TEMP\battery-report.xml") {
        [xml]$batteryReport = Get-Content "$env:TEMP\battery-report.xml"

        $designCapacity = [int]$batteryReport.BatteryReport.Batteries.Battery.DesignCapacity
        $fullChargeCapacity = [int]$batteryReport.BatteryReport.Batteries.Battery.FullChargeCapacity

        if ($designCapacity -gt 0) {
            $healthPercentage = [math]::Round(($fullChargeCapacity / $designCapacity) * 100, 1)

            if ($healthPercentage -lt $degradationThreshold) {
                $issues += "Battery capacity degraded to $healthPercentage% (design: $designCapacity mWh, current: $fullChargeCapacity mWh)"
            }

            Write-Host "Battery Health: $healthPercentage%"
            Write-Host "Design Capacity: $designCapacity mWh"
            Write-Host "Full Charge Capacity: $fullChargeCapacity mWh"
        }

        # Clean up
        Remove-Item "$env:TEMP\battery-report.xml" -Force -ErrorAction SilentlyContinue
    }

    # Check for battery warnings in event log
    $batteryEvents = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Microsoft-Windows-Kernel-Power'
        ID = 105, 106  # Battery capacity warnings
        StartTime = (Get-Date).AddDays(-30)
    } -MaxEvents 5 -ErrorAction SilentlyContinue

    if ($batteryEvents) {
        $issues += "Battery capacity warnings detected in event log"
    }

    if ($issues.Count -gt 0) {
        Write-Host "Battery health issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "Battery health is acceptable"
    exit 0

} catch {
    Write-Host "Error checking battery health: $_"
    exit 1
}
