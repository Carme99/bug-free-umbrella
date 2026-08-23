<#
.SYNOPSIS
    Monitors Windows service failures and crashes.

.DESCRIPTION
    Detects services that fail to start, crash repeatedly, or restart unexpectedly.
    Service instability often indicates underlying system problems.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: No service failures detected
    Exit 1: Service failures found

.CONFIGURATION
    $daysToCheck: Number of days to analyze (default: 7 days)
    $maxServiceFailures: Maximum acceptable service failures (default: 3)
#>

try {
    # Configuration
    $daysToCheck = 7
    $maxServiceFailures = 3

    $issues = @()

    Write-Host "Checking for service failures in last $daysToCheck days..."

    # Event ID 7034: Service crashed unexpectedly
    $serviceCrashes = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Service Control Manager'
        ID = 7034
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 50 -ErrorAction SilentlyContinue

    if ($serviceCrashes) {
        $crashCount = $serviceCrashes.Count
        Write-Host "  Service crashes: $crashCount"

        if ($crashCount -gt $maxServiceFailures) {
            $issues += "Detected $crashCount service crashes (threshold: $maxServiceFailures)"

            # Identify most problematic services
            $crashedServices = $serviceCrashes | ForEach-Object {
                if ($_.Message -match "The (.+?) service terminated unexpectedly") {
                    $matches[1]
                }
            } | Group-Object | Sort-Object Count -Descending | Select-Object -First 5

            Write-Host "  Most frequent crashes:"
            foreach ($svc in $crashedServices) {
                Write-Host "    - $($svc.Name): $($svc.Count) crashes"
            }
        }
    }

    # Event ID 7031: Service terminated unexpectedly (with recovery action)
    $serviceRecoveries = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Service Control Manager'
        ID = 7031
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 50 -ErrorAction SilentlyContinue

    if ($serviceRecoveries) {
        $recoveryCount = $serviceRecoveries.Count
        Write-Host "  Service recoveries: $recoveryCount"

        if ($recoveryCount -gt 5) {
            $issues += "Frequent service recoveries detected: $recoveryCount events"
        }
    }

    # Event ID 7000: Service failed to start
    $serviceStartFailures = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Service Control Manager'
        ID = 7000
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 20 -ErrorAction SilentlyContinue

    if ($serviceStartFailures) {
        $startFailCount = $serviceStartFailures.Count
        Write-Host "  Service start failures: $startFailCount"

        if ($startFailCount -gt $maxServiceFailures) {
            $issues += "Services failing to start: $startFailCount events"
        }
    }

    # Event ID 7011: Service timeout
    $serviceTimeouts = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Service Control Manager'
        ID = 7011
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 20 -ErrorAction SilentlyContinue

    if ($serviceTimeouts) {
        $timeoutCount = $serviceTimeouts.Count
        Write-Host "  Service timeouts: $timeoutCount"

        if ($timeoutCount -gt 3) {
            $issues += "Service timeout errors detected: $timeoutCount events"
        }
    }

    # Check for critical services in stopped state
    $criticalServices = @(
        'wuauserv',      # Windows Update
        'BITS',          # Background Intelligent Transfer
        'Winmgmt',       # Windows Management Instrumentation
        'EventLog',      # Windows Event Log
        'RpcSs',         # Remote Procedure Call
        'Dhcp',          # DHCP Client
        'Dnscache',      # DNS Client
        'mpssvc'         # Windows Defender Firewall
    )

    $stoppedCritical = @()
    foreach ($svcName in $criticalServices) {
        $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -ne 'Running' -and $service.StartType -ne 'Disabled') {
            $stoppedCritical += "$svcName ($($service.Status))"
        }
    }

    if ($stoppedCritical.Count -gt 0) {
        Write-Host "  Critical services not running: $($stoppedCritical.Count)"
        $issues += "Critical services stopped: $($stoppedCritical -join ', ')"
    }

    if ($issues.Count -gt 0) {
        Write-Host "`nService failure issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        Write-Host "`nRecommendation: Review service dependencies, check logs, update software"
        exit 1
    }

    Write-Host "`nNo significant service failures detected"
    exit 0

}
catch {
    Write-Host "Error checking service failures: $_"
    exit 1
}
