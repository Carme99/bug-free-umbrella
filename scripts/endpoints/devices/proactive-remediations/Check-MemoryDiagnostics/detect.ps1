<#
.SYNOPSIS
    Checks for memory errors in event logs.

.DESCRIPTION
    Scans event logs for memory errors that could indicate failing RAM.
    Early detection helps prevent data corruption and system crashes.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: No memory errors detected
    Exit 1: Memory errors found
#>

try {
    $issues = @()

    # Check for memory errors in System event log
    $memoryErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results'
        Level = 2, 3  # Error and Warning
        StartTime = (Get-Date).AddDays(-30)
    } -MaxEvents 10 -ErrorAction SilentlyContinue

    if ($memoryErrors) {
        $issues += "Found $($memoryErrors.Count) memory diagnostic errors in last 30 days"
    }

    # Check for hardware errors (Event ID 19 - Bad memory page)
    $hardwareErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Microsoft-Windows-Kernel-General'
        ID = 19
        StartTime = (Get-Date).AddDays(-30)
    } -MaxEvents 10 -ErrorAction SilentlyContinue

    if ($hardwareErrors) {
        $issues += "Bad memory pages detected (potential RAM failure)"
    }

    # Check for unexpected reboots that could be memory-related
    $unexpectedReboots = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Microsoft-Windows-Kernel-Power'
        ID = 41  # System rebooted without cleanly shutting down
        StartTime = (Get-Date).AddDays(-7)
    } -MaxEvents 5 -ErrorAction SilentlyContinue

    if ($unexpectedReboots) {
        $issues += "Unexpected system reboots detected (may be memory-related)"
    }

    # Check physical memory status using WMI
    $memoryDevices = Get-WmiObject -Class Win32_PhysicalMemory -ErrorAction SilentlyContinue
    foreach ($mem in $memoryDevices) {
        if ($mem.Status -ne "OK") {
            $issues += "Memory module $($mem.DeviceLocator) status: $($mem.Status)"
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host "Memory diagnostic issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "No memory errors detected"
    exit 0

} catch {
    Write-Host "Error checking memory diagnostics: $_"
    exit 1
}
