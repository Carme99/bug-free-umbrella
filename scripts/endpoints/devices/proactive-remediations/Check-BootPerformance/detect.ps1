<#
.SYNOPSIS
    Monitors Windows boot performance and startup time.

.DESCRIPTION
    Tracks boot duration and identifies slow boot times that impact user experience.
    Uses Windows Performance Diagnostics events to measure boot time accurately.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Boot performance is acceptable
    Exit 1: Slow boot detected

.CONFIGURATION
    $maxBootSeconds: Maximum acceptable boot time (default: 120 seconds)
    $warningBootSeconds: Warning threshold (default: 90 seconds)
#>

try {
    # Configuration
    $maxBootSeconds = 120
    $warningBootSeconds = 90

    $issues = @()

    Write-Host "Analyzing boot performance..."

    # Get last boot time
    $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction SilentlyContinue

    if ($os) {
        $lastBoot = $os.ConvertToDateTime($os.LastBootUpTime)
        Write-Host "  Last Boot: $lastBoot"

        # Get boot performance from Diagnostics-Performance event log
        # Event ID 100: Boot duration
        $bootEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
            ID = 100
        } -MaxEvents 5 -ErrorAction SilentlyContinue

        if ($bootEvents) {
            $latestBootEvent = $bootEvents | Select-Object -First 1

            # Extract boot duration from event (in milliseconds)
            if ($latestBootEvent.Properties.Count -gt 0) {
                $bootTimeMs = $latestBootEvent.Properties[0].Value
                $bootTimeSec = [Math]::Round($bootTimeMs / 1000, 1)

                Write-Host "  Boot Duration: $bootTimeSec seconds"

                if ($bootTimeSec -gt $maxBootSeconds) {
                    $issues += "Boot time is $bootTimeSec seconds (threshold: $maxBootSeconds seconds)"
                }
                elseif ($bootTimeSec -gt $warningBootSeconds) {
                    Write-Host "  Warning: Boot time approaching threshold ($bootTimeSec / $maxBootSeconds seconds)"
                }
            }
        }

        # Check for boot/shutdown performance degradation
        # Event ID 200: Shutdown duration
        $shutdownEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
            ID = 200
        } -MaxEvents 5 -ErrorAction SilentlyContinue

        if ($shutdownEvents) {
            $latestShutdown = $shutdownEvents | Select-Object -First 1
            if ($latestShutdown.Properties.Count -gt 0) {
                $shutdownTimeMs = $latestShutdown.Properties[0].Value
                $shutdownTimeSec = [Math]::Round($shutdownTimeMs / 1000, 1)

                Write-Host "  Last Shutdown Duration: $shutdownTimeSec seconds"

                if ($shutdownTimeSec -gt 120) {
                    $issues += "Shutdown time is excessive: $shutdownTimeSec seconds"
                }
            }
        }

        # Check startup programs count
        $startupItems = Get-CimInstance -ClassName Win32_StartupCommand -ErrorAction SilentlyContinue

        if ($startupItems) {
            $startupCount = ($startupItems | Measure-Object).Count
            Write-Host "  Startup Programs: $startupCount"

            if ($startupCount -gt 20) {
                $issues += "Excessive startup programs detected: $startupCount items"
            }
        }

        # Check for boot-start drivers causing delays
        # Event ID 101: Boot performance degradation
        $bootDegradation = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
            ID = 101
            StartTime = (Get-Date).AddDays(-7)
        } -MaxEvents 5 -ErrorAction SilentlyContinue

        if ($bootDegradation) {
            $issues += "Boot performance degradation events detected in last 7 days"
        }

    }
    else {
        $issues += "Unable to retrieve boot information"
    }

    if ($issues.Count -gt 0) {
        Write-Host "`nBoot performance issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        Write-Host "`nRecommendation: Review startup programs, update drivers, check disk health"
        exit 1
    }

    Write-Host "`nBoot performance is within acceptable limits"
    exit 0

}
catch {
    Write-Host "Error checking boot performance: $_"
    exit 1
}
