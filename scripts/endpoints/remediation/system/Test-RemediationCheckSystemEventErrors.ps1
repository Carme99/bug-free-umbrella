<#
.SYNOPSIS
    Check the System event log for critical errors and hardware failure indicators.

.DESCRIPTION
    Scans the System and Security event logs for critical (Level 1) errors, known fatal
    event IDs (kernel power crashes, bugchecks, disk and NTFS faults) and error-level
    (Level 2) events from critical providers within the analysis window (default 7 days),
    flagging the device when counts exceed the configured thresholds (more than 5 critical
    errors, more than 3 provider errors, more than 2 event log service errors). Intended
    to run in SYSTEM context via Intune Proactive Remediations.
    Exit codes: 0 = compliant/healthy (no critical system errors detected), 1 = issue
    detected (critical errors above threshold, or an unexpected error occurred). The
    script changes no system state, so it is idempotent.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckSystemEventErrors.ps1

    Exits 0 when no critical system errors are found; exits 1 when critical errors exceed
    the configured thresholds.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckSystemEventErrors.ps1 -Verbose

    Runs the same read-only analysis with verbose pipeline output for troubleshooting.

.NOTES
    File Name  : Test-RemediationCheckSystemEventErrors.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Main {
    param()

    try {
        # Configuration
        $daysToCheck = 7
        $maxCriticalErrors = 5

        $issues = @()

        Write-Host "[*] Checking for critical system errors in last $daysToCheck days..." -ForegroundColor Cyan

        # Get all critical (Level 1) errors from System log
        $criticalErrors = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Level     = 1  # Critical
            StartTime = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 100 -ErrorAction SilentlyContinue

        if ($criticalErrors) {
            $criticalCount = $criticalErrors.Count
            Write-Host "[*] Critical errors: $criticalCount" -ForegroundColor Cyan

            if ($criticalCount -gt $maxCriticalErrors) {
                $issues += "Excessive critical system errors: $criticalCount events"

                # Group by provider to identify problem areas
                $errorProviders = $criticalErrors | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 5

                Write-Host "[*] Top error sources:" -ForegroundColor Cyan
                foreach ($provider in $errorProviders) {
                    Write-Host "[*]   - $($provider.Name): $($provider.Count) errors" -ForegroundColor Cyan
                }
            }
        }

        # Check for specific critical event IDs
        $criticalEventIDs = @{
            41    = "Kernel-Power: System crash/unexpected shutdown"
            1001  = "BugCheck: Blue screen of death"
            20    = "Partition Manager: Disk corruption"
            7     = "Disk: Bad block detected"
            11    = "Disk: Controller error"
            51    = "Disk: Page file error"
            153   = "Disk: IO error"
            55    = "NTFS: File system corruption"
        }

        foreach ($eventID in $criticalEventIDs.Keys) {
            $specificErrors = Get-WinEvent -FilterHashtable @{
                LogName   = 'System'
                ID        = $eventID
                StartTime = (Get-Date).AddDays(-$daysToCheck)
            } -MaxEvents 10 -ErrorAction SilentlyContinue

            if ($specificErrors) {
                $errorCount = $specificErrors.Count
                $errorDesc = $criticalEventIDs[$eventID]
                Write-Host "[*] Event ID $eventID ($errorDesc): $errorCount" -ForegroundColor Cyan
                $issues += "Critical event detected: $errorDesc ($errorCount events)"
            }
        }

        # Check for error-level events (Level 2) from critical providers
        $errorsByProvider = @{
            'Microsoft-Windows-Kernel-General'          = 'Kernel errors'
            'Microsoft-Windows-Kernel-Processor-Power'  = 'Processor errors'
            'Microsoft-Windows-Kernel-WHEA'             = 'Hardware error architecture'
            'volsnap'                                   = 'Volume snapshot errors'
            'BTHUSB'                                    = 'Bluetooth USB errors'
        }

        foreach ($provider in $errorsByProvider.Keys) {
            $providerErrors = Get-WinEvent -FilterHashtable @{
                LogName      = 'System'
                ProviderName = $provider
                Level        = 2  # Error
                StartTime    = (Get-Date).AddDays(-$daysToCheck)
            } -MaxEvents 20 -ErrorAction SilentlyContinue

            if ($providerErrors) {
                $errorCount = $providerErrors.Count
                $errorType = $errorsByProvider[$provider]

                if ($errorCount -gt 3) {
                    Write-Host "[*] $errorType`: $errorCount errors" -ForegroundColor Cyan
                    $issues += "Detected $errorType`: $errorCount events"
                }
            }
        }

        # Check Security log for critical security events
        $securityCritical = Get-WinEvent -FilterHashtable @{
            LogName   = 'Security'
            Level     = 1  # Critical
            StartTime = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 20 -ErrorAction SilentlyContinue

        if ($securityCritical) {
            $securityCount = $securityCritical.Count
            Write-Host "[*] Critical security events: $securityCount" -ForegroundColor Cyan

            if ($securityCount -gt 0) {
                $issues += "Critical security events detected: $securityCount events"
            }
        }

        # Check for event log service issues
        $eventLogErrors = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'EventLog'
            Level        = 2
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 10 -ErrorAction SilentlyContinue

        if ($eventLogErrors) {
            $eventLogCount = $eventLogErrors.Count
            if ($eventLogCount -gt 2) {
                Write-Host "[*] Event log service errors: $eventLogCount" -ForegroundColor Cyan
                $issues += "Event logging issues detected: $eventLogCount errors"
            }
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] Critical system event issues detected:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "[!]   - $issue" -ForegroundColor Yellow
            }
            Write-Host "[*] Recommendation: Investigate hardware, update drivers, run diagnostics" -ForegroundColor Cyan
            return 1
        }

        Write-Host "[+] No critical system errors detected" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking system event errors: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
