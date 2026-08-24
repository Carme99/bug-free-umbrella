<#
.SYNOPSIS
    Detects if Windows Defender is healthy and properly configured.

.DESCRIPTION
    Checks Windows Defender real-time protection status, signature updates, and service
    health, which is critical for maintaining endpoint security posture. This is a
    read-only detection script: it never modifies anything, so re-running it on a healthy
    device converges to exit 0 (idempotent).
    Exit codes:
    - 0: compliant - Defender is healthy and up to date.
    - 1: non-compliant - one or more Defender health issues were detected, or the check failed.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckDefenderHealthStatus.ps1
    Runs the health check and exits 0 when Defender is healthy, 1 when issues are found.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationCheckDefenderHealthStatus.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.

.NOTES
    File Name: Test-RemediationCheckDefenderHealthStatus.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Checking Windows Defender health status..." -ForegroundColor Cyan

        $issues = @()

        # Check if Defender service is running
        $defenderService = Get-Service -Name "WinDefend" -ErrorAction SilentlyContinue
        if ($defenderService.Status -ne "Running") {
            $issues += "Windows Defender service is not running"
        }

        # Check real-time protection status
        $mpPreference = Get-MpPreference -ErrorAction SilentlyContinue
        if ($mpPreference.DisableRealtimeMonitoring -eq $true) {
            $issues += "Real-time protection is disabled"
        }

        # Check signature age (should be less than 7 days old)
        $mpComputerStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($mpComputerStatus) {
            $signatureAge = (Get-Date) - $mpComputerStatus.AntivirusSignatureLastUpdated
            if ($signatureAge.TotalDays -gt 7) {
                $lastUpdate = $mpComputerStatus.AntivirusSignatureLastUpdated
                $issues += "Defender signatures are outdated (last updated: $lastUpdate)"
            }

            # Check if Defender is enabled
            if ($mpComputerStatus.AntivirusEnabled -eq $false) {
                $issues += "Windows Defender antivirus is disabled"
            }
        }

        # Check for pending full scan (if last full scan > 30 days)
        if ($mpComputerStatus.FullScanAge -gt 30) {
            $issues += "Full scan has not run in $($mpComputerStatus.FullScanAge) days"
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] Defender health issues detected:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "  - $issue" -ForegroundColor Yellow
            }
            return 1
        }

        Write-Host "[+] Windows Defender is healthy and up to date" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking Defender status: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
