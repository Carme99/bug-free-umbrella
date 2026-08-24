<#
.SYNOPSIS
    Check Windows boot performance and flag slow boot or shutdown times.

.DESCRIPTION
    Measures the last boot duration from the Diagnostics-Performance event log,
    checks shutdown duration and boot degradation events from the last 7 days and
    counts registered startup programs to identify devices whose boot experience
    impacts user productivity.
    Exit codes: 0 = boot performance is acceptable, 1 = slow boot, slow shutdown,
    boot degradation events or excessive startup programs detected (or an
    unexpected error occurred). The script is read-only, changes no system state
    and is therefore idempotent.
    Configuration: $maxBootSeconds is the maximum acceptable boot time (default
    120 seconds) and $warningBootSeconds is the warning threshold (default 90).

.EXAMPLE
    PS C:\> .\Test-RemediationCheckBootPerformance.ps1

    Exits 0 when boot performance is within limits; exits 1 when slow boot issues are detected.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckBootPerformance.ps1 -Verbose

    Runs the same analysis with verbose progress information.

.NOTES
    File Name  : Test-RemediationCheckBootPerformance.ps1
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
        # Configuration
        $maxBootSeconds = 120
        $warningBootSeconds = 90

        $issues = @()

        Write-Host "[*] Analyzing boot performance..." -ForegroundColor Cyan

        # Get last boot time
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue

        if ($os) {
            $lastBoot = $os.LastBootUpTime
            Write-Host "  Last Boot: $lastBoot"

            # Get boot performance from Diagnostics-Performance event log
            # Event ID 100: Boot duration
            $bootEvents = Get-WinEvent -FilterHashtable @{
                LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
                ID      = 100
            } -MaxEvents 5 -ErrorAction SilentlyContinue

            if ($bootEvents) {
                $latestBootEvent = @($bootEvents) | Select-Object -First 1

                # Extract boot duration from event (in milliseconds)
                if ($latestBootEvent.Properties.Count -gt 0) {
                    $bootTimeMs = $latestBootEvent.Properties[0].Value
                    $bootTimeSec = [Math]::Round($bootTimeMs / 1000, 1)

                    Write-Host "  Boot Duration: $bootTimeSec seconds"

                    if ($bootTimeSec -gt $maxBootSeconds) {
                        $issues += "Boot time is $bootTimeSec seconds (threshold: $maxBootSeconds seconds)"
                    }
                    elseif ($bootTimeSec -gt $warningBootSeconds) {
                        Write-Host "[!] Boot time approaching threshold ($bootTimeSec / $maxBootSeconds seconds)" -ForegroundColor Yellow
                    }
                }
            }

            # Check for boot/shutdown performance degradation
            # Event ID 200: Shutdown duration
            $shutdownEvents = Get-WinEvent -FilterHashtable @{
                LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
                ID      = 200
            } -MaxEvents 5 -ErrorAction SilentlyContinue

            if ($shutdownEvents) {
                $latestShutdown = @($shutdownEvents) | Select-Object -First 1
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
                $startupCount = @($startupItems).Count
                Write-Host "  Startup Programs: $startupCount"

                if ($startupCount -gt 20) {
                    $issues += "Excessive startup programs detected: $startupCount items"
                }
            }

            # Check for boot-start drivers causing delays
            # Event ID 101: Boot performance degradation
            $bootDegradation = Get-WinEvent -FilterHashtable @{
                LogName   = 'Microsoft-Windows-Diagnostics-Performance/Operational'
                ID        = 101
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
            Write-Host "[!] Boot performance issues detected:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "[!]   - $issue" -ForegroundColor Yellow
            }
            Write-Host "[*] Recommendation: review startup programs, update drivers, check disk health" -ForegroundColor Cyan
            return 1
        }

        Write-Host "[+] Boot performance is within acceptable limits" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking boot performance: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
