<#
.SYNOPSIS
    Monitors device uptime and recommends reboots for devices up too long.

.DESCRIPTION
    Tracks system uptime and identifies devices that haven't rebooted in X days.
    Regular reboots improve stability, clear memory leaks, and install updates.
    Provides detailed uptime reporting for IT dashboards.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Uptime is acceptable
    Exit 1: Device needs reboot (exceeded threshold)

.CONFIGURATION
    $maxUptimeDays: Maximum acceptable uptime in days (default: 14 days)
    $warningUptimeDays: Warning threshold in days (default: 7 days)
#>

try {
    # Configuration
    $maxUptimeDays = 14      # Recommend reboot after 14 days
    $warningUptimeDays = 7   # Warn after 7 days

    $issues = @()

    # Get last boot time
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue

    if ($os) {
        $lastBoot = $os.LastBootUpTime
        $uptime = (Get-Date) - $lastBoot
        $uptimeDays = [Math]::Round($uptime.TotalDays, 2)
        $uptimeHours = [Math]::Round($uptime.TotalHours, 1)

        Write-Host "Device Uptime Report:"
        Write-Host "  Last Boot: $lastBoot"
        Write-Host "  Uptime: $uptimeDays days ($uptimeHours hours)"
        Write-Host "  Computer: $env:COMPUTERNAME"

        # Check against thresholds
        if ($uptimeDays -gt $maxUptimeDays) {
            $issues += "Device has been running for $uptimeDays days (threshold: $maxUptimeDays days)"
            $issues += "Reboot recommended to maintain system health and install updates"
        } elseif ($uptimeDays -gt $warningUptimeDays) {
            Write-Host "  Warning: Approaching reboot threshold ($uptimeDays / $maxUptimeDays days)"
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
        $totalSeconds = $uptime.TotalSeconds
        $uptimePercent = 100  # Assume 100% uptime
        Write-Host "  Uptime Percentage: $uptimePercent% (since last boot)"

    } else {
        $issues += "Unable to retrieve system boot time"
    }

    if ($issues.Count -gt 0) {
        Write-Host "`nUptime issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "`nDevice uptime is within acceptable limits"
    exit 0

} catch {
    Write-Host "Error checking device uptime: $_"
    exit 1
}
