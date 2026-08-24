<#
.SYNOPSIS
    Detects Print Spooler service problems for Intune Proactive Remediations.

.DESCRIPTION
    Verifies that the Print Spooler service exists, is running, and starts automatically,
    that the spool directory is accessible, and that stuck or stale print jobs are absent.
    This is a read-only detection script; it makes no changes to the system.
    Exit codes:
    - 0: Print Spooler is functioning properly.
    - 1: an issue was detected (service missing/stopped/not automatic, spool directory
      inaccessible, stuck or stale jobs) or the check itself failed; triggers remediation.
    Re-running against an unchanged system yields the same result (idempotent).

.NOTES
    File Name: Test-RemediationFixPrintSpooler.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

.EXAMPLE
    PS C:\> .\Test-RemediationFixPrintSpooler.ps1
    Runs the checks; exits 0 when the spooler is healthy, 1 when an issue is found.

.EXAMPLE
    PS C:\> .\Test-RemediationFixPrintSpooler.ps1; $LASTEXITCODE
    Runs the checks and prints the resulting exit code for pipeline consumption.
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

function Main {
    try {
        $outputMsg = "[*] Checking Print Spooler service status..."
        Write-Host $outputMsg -ForegroundColor Cyan

        # Check Print Spooler service
        $spoolerService = Get-Service -Name 'Spooler' -ErrorAction SilentlyContinue

        if (-not $spoolerService) {
            $outputMsg = "[-] Print Spooler service not found!"
            Write-Host $outputMsg -ForegroundColor Red
            return 1
        }

        # Check if service is running
        if ($spoolerService.Status -ne 'Running') {
            $outputMsg = "[!] Print Spooler service is not running. Current status: $($spoolerService.Status)"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        # Check if service startup type is Automatic
        if ($spoolerService.StartType -ne 'Automatic') {
            $outputMsg = "[!] Print Spooler service startup type is not Automatic. "
            $outputMsg += "Current: $($spoolerService.StartType)"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        # Check spool directory
        $spoolPath = "$env:SystemRoot\System32\spool\PRINTERS"
        if (-not (Test-Path $spoolPath)) {
            $outputMsg = "[!] Spool directory not found: $spoolPath"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        # Check for stuck print jobs
        try {
            $printJobs = @(Get-ChildItem -Path $spoolPath -Filter '*.spl' -ErrorAction SilentlyContinue)
            if ($printJobs.Count -gt 10) {
                $outputMsg = "[!] Detected $($printJobs.Count) files in spool directory - possible stuck jobs"
                Write-Host $outputMsg -ForegroundColor Yellow
                return 1
            }

            # Check for very old spool files (> 24 hours)
            $oldJobs = @($printJobs | Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-24) })
            if ($oldJobs.Count -gt 0) {
                $outputMsg = "[!] Detected $($oldJobs.Count) old print jobs (> 24 hours)"
                Write-Host $outputMsg -ForegroundColor Yellow
                return 1
            }
        }
        catch {
            # If we can't check, assume there might be an issue
            $outputMsg = "[!] Could not access spool directory: $($_.Exception.Message)"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        $outputMsg = "[+] Print Spooler is functioning properly"

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking Print Spooler: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
