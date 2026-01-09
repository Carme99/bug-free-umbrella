<#
.SYNOPSIS
    Detects unexpected system reboots and crashes.

.DESCRIPTION
    Monitors event logs for unexpected reboots, blue screens (bugchecks), and
    system crashes that could indicate hardware issues or driver problems.
    Provides crash analysis for troubleshooting.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: No unexpected reboots detected
    Exit 1: Unexpected reboots or crashes found

.CONFIGURATION
    $daysToCheck: Number of days to check event logs (default: 7 days)
    $maxUnexpectedReboots: Maximum acceptable unexpected reboots (default: 1)
#>

try {
    # Configuration
    $daysToCheck = 7
    $maxUnexpectedReboots = 1

    $issues = @()

    Write-Host "Checking for unexpected reboots in last $daysToCheck days..."

    # Event ID 41: System rebooted without cleanly shutting down (crash/power loss)
    $unexpectedReboots = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Microsoft-Windows-Kernel-Power'
        ID = 41
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 20 -ErrorAction SilentlyContinue

    if ($unexpectedReboots) {
        $rebootCount = $unexpectedReboots.Count
        Write-Host "  Found $rebootCount unexpected reboot(s)"

        if ($rebootCount -gt $maxUnexpectedReboots) {
            $issues += "Detected $rebootCount unexpected reboots (threshold: $maxUnexpectedReboots)"
        }

        # Analyze most recent unexpected reboot
        $latestReboot = $unexpectedReboots | Select-Object -First 1
        Write-Host "  Most Recent: $($latestReboot.TimeCreated)"
    }

    # Event ID 1001: Bugcheck (Blue Screen of Death)
    $bugchecks = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'
        ID = 1001
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 10 -ErrorAction SilentlyContinue

    if ($bugchecks) {
        $bugcheckCount = $bugchecks.Count
        Write-Host "  Found $bugcheckCount blue screen event(s)"
        $issues += "Blue screen errors detected: $bugcheckCount BSOD event(s)"

        # Extract bugcheck code from most recent
        $latestBugcheck = $bugchecks | Select-Object -First 1
        $bugcheckMsg = $latestBugcheck.Message
        if ($bugcheckMsg -match "0x[0-9A-Fa-f]{8}") {
            $bugcheckCode = $matches[0]
            Write-Host "  Latest Bugcheck Code: $bugcheckCode"
        }
    }

    # Event ID 6008: Unexpected shutdown
    $unexpectedShutdowns = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'EventLog'
        ID = 6008
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 10 -ErrorAction SilentlyContinue

    if ($unexpectedShutdowns) {
        $shutdownCount = $unexpectedShutdowns.Count
        Write-Host "  Found $shutdownCount unexpected shutdown(s)"
        if ($shutdownCount -gt $maxUnexpectedReboots) {
            $issues += "Unexpected shutdowns detected: $shutdownCount event(s)"
        }
    }

    # Check for system failures in Application log
    $systemFailures = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        ProviderName = 'Windows Error Reporting'
        Level = 2  # Error
        StartTime = (Get-Date).AddDays(-$daysToCheck)
    } -MaxEvents 50 -ErrorAction SilentlyContinue

    if ($systemFailures) {
        $criticalFailures = $systemFailures | Where-Object { $_.Message -match "critical|fatal|stopped responding" }
        if ($criticalFailures) {
            Write-Host "  Found $($criticalFailures.Count) critical application failure(s)"
        }
    }

    # Check for crash dump files
    $crashDumps = @()
    if (Test-Path "$env:SystemRoot\MEMORY.DMP") {
        $dmpFile = Get-Item "$env:SystemRoot\MEMORY.DMP" -ErrorAction SilentlyContinue
        if ($dmpFile -and $dmpFile.LastWriteTime -gt (Get-Date).AddDays(-$daysToCheck)) {
            $crashDumps += "Full memory dump: $($dmpFile.LastWriteTime)"
        }
    }

    if (Test-Path "$env:SystemRoot\Minidump") {
        $minidumps = Get-ChildItem "$env:SystemRoot\Minidump" -Filter "*.dmp" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-$daysToCheck) }
        if ($minidumps) {
            $crashDumps += "$($minidumps.Count) minidump file(s)"
        }
    }

    if ($crashDumps.Count -gt 0) {
        Write-Host "  Crash dumps found: $($crashDumps -join ', ')"
        $issues += "Crash dump files detected - indicates system crashes"
    }

    if ($issues.Count -gt 0) {
        Write-Host "`nUnexpected reboot issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        Write-Host "`nRecommendation: Review crash dumps and update drivers/firmware"
        exit 1
    }

    Write-Host "`nNo unexpected reboots detected - system stability is good"
    exit 0

} catch {
    Write-Host "Error checking unexpected reboots: $_"
    exit 1
}
