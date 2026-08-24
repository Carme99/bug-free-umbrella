<#
.SYNOPSIS
    Check the system for service failures, crashes and stopped critical services.

.DESCRIPTION
    Scans the System event log over the last 7 days for Service Control Manager
    events indicating service crashes (7034), unexpected terminations with
    recovery (7031), start failures (7000) and timeouts (7011), and verifies that
    a set of critical services (Windows Update, BITS, WMI, Event Log, RPC, DHCP,
    DNS Client, Defender Firewall) are not stuck in a stopped state.
    Exit codes: 0 = no significant service failures detected, 1 = service
    failures found (or an unexpected error occurred). The script changes no
    system state, so it is safe to re-run at any time (idempotent).
    Intune Context: SYSTEM. Configuration lives inline: $daysToCheck controls how
    many days of event logs are analyzed (default: 7) and $maxServiceFailures is
    the maximum acceptable service failure count (default: 3).

.EXAMPLE
    PS C:\> .\Test-RemediationCheckServiceFailures.ps1

    Exits 0 when no significant service failures are detected; exits 1 when
    service failures are found.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckServiceFailures.ps1 -Verbose

    Runs the same service failure check with verbose progress information.

.NOTES
    File Name  : Test-RemediationCheckServiceFailures.ps1
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
        $daysToCheck = 7
        $maxServiceFailures = 3

        $issues = @()

        Write-Host "[*] Checking for service failures in last $daysToCheck days..." -ForegroundColor Cyan

        # Event ID 7034: Service crashed unexpectedly
        $serviceCrashes = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Service Control Manager'
            ID           = 7034
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 50 -ErrorAction SilentlyContinue

        if ($serviceCrashes) {
            $crashCount = $serviceCrashes.Count
            Write-Host "[*] Service crashes: $crashCount" -ForegroundColor Cyan

            if ($crashCount -gt $maxServiceFailures) {
                $issues += "Detected $crashCount service crashes (threshold: $maxServiceFailures)"

                # Identify most problematic services
                $crashedServices = $serviceCrashes | ForEach-Object {
                    if ($_.Message -match "The (.+?) service terminated unexpectedly") {
                        $matches[1]
                    }
                } | Group-Object | Sort-Object Count -Descending | Select-Object -First 5

                Write-Host "[*] Most frequent crashes:" -ForegroundColor Cyan
                foreach ($svc in $crashedServices) {
                    Write-Host "[*]   - $($svc.Name): $($svc.Count) crashes" -ForegroundColor Cyan
                }
            }
        }

        # Event ID 7031: Service terminated unexpectedly (with recovery action)
        $serviceRecoveries = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Service Control Manager'
            ID           = 7031
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 50 -ErrorAction SilentlyContinue

        if ($serviceRecoveries) {
            $recoveryCount = $serviceRecoveries.Count
            Write-Host "[*] Service recoveries: $recoveryCount" -ForegroundColor Cyan

            if ($recoveryCount -gt 5) {
                $issues += "Frequent service recoveries detected: $recoveryCount events"
            }
        }

        # Event ID 7000: Service failed to start
        $serviceStartFailures = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Service Control Manager'
            ID           = 7000
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 20 -ErrorAction SilentlyContinue

        if ($serviceStartFailures) {
            $startFailCount = $serviceStartFailures.Count
            Write-Host "[*] Service start failures: $startFailCount" -ForegroundColor Cyan

            if ($startFailCount -gt $maxServiceFailures) {
                $issues += "Services failing to start: $startFailCount events"
            }
        }

        # Event ID 7011: Service timeout
        $serviceTimeouts = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Service Control Manager'
            ID           = 7011
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 20 -ErrorAction SilentlyContinue

        if ($serviceTimeouts) {
            $timeoutCount = $serviceTimeouts.Count
            Write-Host "[*] Service timeouts: $timeoutCount" -ForegroundColor Cyan

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
            Write-Host "[*] Critical services not running: $($stoppedCritical.Count)" -ForegroundColor Cyan
            $issues += "Critical services stopped: $($stoppedCritical -join ', ')"
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] Service failure issues detected:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "[!]   - $issue" -ForegroundColor Yellow
            }
            Write-Host "[!] Recommendation: Review service dependencies, check logs, update software" -ForegroundColor Yellow
            return 1
        }

        Write-Host "[+] No significant service failures detected" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking service failures: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
