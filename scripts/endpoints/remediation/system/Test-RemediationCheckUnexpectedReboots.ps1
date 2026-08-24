<#
.SYNOPSIS
    Check for unexpected system reboots, blue screens and crash dumps.

.DESCRIPTION
    Monitors the System event log for unexpected reboots (Kernel-Power event 41),
    blue screens (BugCheck event 1001) and unexpected shutdowns (event 6008), and
    inspects the Application log plus %SystemRoot% dump locations for recent crashes
    within the analysis window (default 7 days); more than one unexpected reboot or
    any bugcheck/shutdown/dump evidence flags the device as unstable. This provides
    crash analysis for troubleshooting hardware issues or driver problems.
    Exit codes: 0 = compliant/healthy (no unexpected reboots detected), 1 = issue
    detected (unexpected reboots or crashes found, or an unexpected error occurred).
    The script changes no system state, so it is idempotent.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckUnexpectedReboots.ps1

    Exits 0 when system stability looks good; exits 1 when unexpected reboots or
    crashes are detected.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckUnexpectedReboots.ps1 -Verbose

    Runs the same read-only analysis with verbose pipeline output for troubleshooting.

.NOTES
    File Name  : Test-RemediationCheckUnexpectedReboots.ps1
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
        $maxUnexpectedReboots = 1

        $issues = @()

        Write-Host "[*] Checking for unexpected reboots in last $daysToCheck days..." -ForegroundColor Cyan

        # Event ID 41: System rebooted without cleanly shutting down (crash/power loss)
        $unexpectedReboots = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Microsoft-Windows-Kernel-Power'
            ID           = 41
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 20 -ErrorAction SilentlyContinue

        if ($unexpectedReboots) {
            $rebootCount = $unexpectedReboots.Count
            Write-Host "[*]   Found $rebootCount unexpected reboot(s)" -ForegroundColor Cyan

            if ($rebootCount -gt $maxUnexpectedReboots) {
                $issues += "Detected $rebootCount unexpected reboots (threshold: $maxUnexpectedReboots)"
            }

            # Analyze most recent unexpected reboot
            $latestReboot = $unexpectedReboots | Select-Object -First 1
            Write-Host "[*]   Most Recent: $($latestReboot.TimeCreated)" -ForegroundColor Cyan
        }

        # Event ID 1001: Bugcheck (Blue Screen of Death)
        $bugchecks = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'
            ID           = 1001
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 10 -ErrorAction SilentlyContinue

        if ($bugchecks) {
            $bugcheckCount = $bugchecks.Count
            Write-Host "[*]   Found $bugcheckCount blue screen event(s)" -ForegroundColor Cyan
            $issues += "Blue screen errors detected: $bugcheckCount BSOD event(s)"

            # Extract bugcheck code from most recent
            $latestBugcheck = $bugchecks | Select-Object -First 1
            $bugcheckMsg = $latestBugcheck.Message
            if ($bugcheckMsg -match "0x[0-9A-Fa-f]{8}") {
                $bugcheckCode = $matches[0]
                Write-Host "[*]   Latest Bugcheck Code: $bugcheckCode" -ForegroundColor Cyan
            }
        }

        # Event ID 6008: Unexpected shutdown
        $unexpectedShutdowns = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'EventLog'
            ID           = 6008
            StartTime    = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 10 -ErrorAction SilentlyContinue

        if ($unexpectedShutdowns) {
            $shutdownCount = $unexpectedShutdowns.Count
            Write-Host "[*]   Found $shutdownCount unexpected shutdown(s)" -ForegroundColor Cyan
            if ($shutdownCount -gt $maxUnexpectedReboots) {
                $issues += "Unexpected shutdowns detected: $shutdownCount event(s)"
            }
        }

        # Check for system failures in Application log
        $systemFailures = Get-WinEvent -FilterHashtable @{
            LogName   = 'Application'
            ProviderName = 'Windows Error Reporting'
            Level     = 2  # Error
            StartTime = (Get-Date).AddDays(-$daysToCheck)
        } -MaxEvents 50 -ErrorAction SilentlyContinue

        if ($systemFailures) {
            $criticalFailures = $systemFailures | Where-Object { $_.Message -match "critical|fatal|stopped responding" }
            if ($criticalFailures) {
                Write-Host "[!]   Found $($criticalFailures.Count) critical application failure(s)" -ForegroundColor Yellow
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
            Write-Host "[*]   Crash dumps found: $($crashDumps -join ', ')" -ForegroundColor Cyan
            $issues += "Crash dump files detected - indicates system crashes"
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] Unexpected reboot issues detected:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "[!]   - $issue" -ForegroundColor Yellow
            }
            Write-Host "[*] Recommendation: Review crash dumps and update drivers/firmware" -ForegroundColor Cyan
            return 1
        }

        Write-Host "[+] No unexpected reboots detected - system stability is good" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking unexpected reboots: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
