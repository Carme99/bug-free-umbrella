<#
.SYNOPSIS
    Monitors critical system event log errors.

.DESCRIPTION
    Scans System event log for critical errors that indicate hardware problems,
    driver issues, or system instability. Provides early warning of serious issues.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: No critical system errors
    Exit 1: Critical system errors detected

.CONFIGURATION
    $daysToCheck: Number of days to analyze (default: 7 days)
    $maxCriticalErrors: Maximum acceptable critical errors (default: 5)
#>

try {
    # Configuration
    $daysToCheck = 7
    $maxCriticalErrors = 5

    $issues = @()

    Write-Host "Checking for critical system errors in last $daysToCheck days..."

    # Get all critical (Level 1) errors from System log
    $criticalErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        Level = 1  # Critical
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 100 -ErrorAction SilentlyContinue

    if ($criticalErrors) {
        $criticalCount = $criticalErrors.Count
        Write-Host "  Critical errors: $criticalCount"

        if ($criticalCount -gt $maxCriticalErrors) {
            $issues += "Excessive critical system errors: $criticalCount events"

            # Group by provider to identify problem areas
            $errorProviders = $criticalErrors | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 5

            Write-Host "  Top error sources:"
            foreach ($provider in $errorProviders) {
                Write-Host "    - $($provider.Name): $($provider.Count) errors"
            }
        }
    }

    # Check for specific critical event IDs
    $criticalEventIDs = @{
        41 = "Kernel-Power: System crash/unexpected shutdown"
        1001 = "BugCheck: Blue screen of death"
        20 = "Partition Manager: Disk corruption"
        7 = "Disk: Bad block detected"
        11 = "Disk: Controller error"
        51 = "Disk: Page file error"
        153 = "Disk: IO error"
        55 = "NTFS: File system corruption"
    }

    foreach ($eventID in $criticalEventIDs.Keys) {
        $specificErrors = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ID = $eventID
            StartTime = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 10 -ErrorAction SilentlyContinue

        if ($specificErrors) {
            $errorCount = $specificErrors.Count
            $errorDesc = $criticalEventIDs[$eventID]
            Write-Host "  Event ID $eventID ($errorDesc): $errorCount"
            $issues += "Critical event detected: $errorDesc ($errorCount events)"
        }
    }

    # Check for error-level events (Level 2) from critical providers
    $errorsByProvider = @{
        'Microsoft-Windows-Kernel-General' = 'Kernel errors'
        'Microsoft-Windows-Kernel-Processor-Power' = 'Processor errors'
        'Microsoft-Windows-Kernel-WHEA' = 'Hardware error architecture'
        'volsnap' = 'Volume snapshot errors'
        'BTHUSB' = 'Bluetooth USB errors'
    }

    foreach ($provider in $errorsByProvider.Keys) {
        $providerErrors = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ProviderName = $provider
            Level = 2  # Error
            StartTime = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 20 -ErrorAction SilentlyContinue

        if ($providerErrors) {
            $errorCount = $providerErrors.Count
            $errorType = $errorsByProvider[$provider]

            if ($errorCount -gt 3) {
                Write-Host "  $errorType`: $errorCount errors"
                $issues += "Detected $errorType`: $errorCount events"
            }
        }
    }

    # Check Security log for critical security events
    $securityCritical = Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        Level = 1  # Critical
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 20 -ErrorAction SilentlyContinue

    if ($securityCritical) {
        $securityCount = $securityCritical.Count
        Write-Host "  Critical security events: $securityCount"

        if ($securityCount -gt 0) {
            $issues += "Critical security events detected: $securityCount events"
        }
    }

    # Check for event log service issues
    $eventLogErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'EventLog'
        Level = 2
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 10 -ErrorAction SilentlyContinue

    if ($eventLogErrors) {
        $eventLogCount = $eventLogErrors.Count
        if ($eventLogCount -gt 2) {
            Write-Host "  Event log service errors: $eventLogCount"
            $issues += "Event logging issues detected: $eventLogCount errors"
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host "`nCritical system event issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        Write-Host "`nRecommendation: Investigate hardware, update drivers, run diagnostics"
        exit 1
    }

    Write-Host "`nNo critical system errors detected"
    exit 0

} catch {
    Write-Host "Error checking system event errors: $_"
    exit 1
}
