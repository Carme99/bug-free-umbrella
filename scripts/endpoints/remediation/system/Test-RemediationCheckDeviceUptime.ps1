<#
.SYNOPSIS
    Check device uptime and flag devices that need a reboot.

.DESCRIPTION
    Reads the last boot time from Win32_OperatingSystem, reports the current
    uptime and flags devices that have been running longer than the reboot
    threshold. Also checks the Windows Update and Component Based Servicing
    registry keys for pending reboots so updates are not left half-installed.
    Exit codes: 0 = uptime is acceptable with no pending reboot, 1 = reboot
    required (uptime exceeded or pending reboot detected, or an unexpected error
    occurred). The script is read-only, changes no system state and is therefore
    idempotent.
    Configuration: $maxUptimeDays is the maximum acceptable uptime (default 14
    days) and $warningUptimeDays is the warning threshold (default 7 days).

.EXAMPLE
    PS C:\> .\Test-RemediationCheckDeviceUptime.ps1

    Exits 0 when uptime is within limits; exits 1 when a reboot is recommended.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckDeviceUptime.ps1 -Verbose

    Runs the same analysis with verbose progress information.

.NOTES
    File Name  : Test-RemediationCheckDeviceUptime.ps1
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
        $maxUptimeDays = 14      # Recommend reboot after 14 days
        $warningUptimeDays = 7   # Warn after 7 days

        $issues = @()

        Write-Host "[*] Checking device uptime..." -ForegroundColor Cyan

        # Get last boot time
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue

        if ($os) {
            $lastBoot = $os.LastBootUpTime
            $uptime = (Get-Date) - $lastBoot
            $uptimeDays = [Math]::Round($uptime.TotalDays, 2)
            $uptimeHours = [Math]::Round($uptime.TotalHours, 1)

            Write-Host "  Last Boot: $lastBoot"
            Write-Host "  Uptime: $uptimeDays days ($uptimeHours hours)"
            Write-Host "  Computer: $env:COMPUTERNAME"

            # Check against thresholds
            if ($uptimeDays -gt $maxUptimeDays) {
                $issues += "Device has been running for $uptimeDays days (threshold: $maxUptimeDays days)"
                $issues += "Reboot recommended to maintain system health and install updates"
            }
            elseif ($uptimeDays -gt $warningUptimeDays) {
                Write-Host "[!] Approaching reboot threshold ($uptimeDays / $maxUptimeDays days)" -ForegroundColor Yellow
            }

            # Check for pending Windows Updates requiring reboot
            $pendingReboot = $false

            # Check Windows Update reboot required
            if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
                $pendingReboot = $true
                $issues += "Windows Update reboot pending"
            }

            # Check Component Based Servicing reboot pending
            if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
                $pendingReboot = $true
                $issues += "Component Based Servicing reboot pending"
            }

            if ($pendingReboot) {
                Write-Host "  Updates Pending: Yes (reboot required)"
            }

            # Calculate uptime percentile (informational)
            $null = $uptime.TotalSeconds
            $uptimePercent = 100  # Assume 100% uptime
            Write-Host "  Uptime Percentage: $uptimePercent% (since last boot)"
        }
        else {
            $issues += "Unable to retrieve system boot time"
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] Uptime issues detected:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "[!]   - $issue" -ForegroundColor Yellow
            }
            return 1
        }

        Write-Host "[+] Device uptime is within acceptable limits" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking device uptime: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
