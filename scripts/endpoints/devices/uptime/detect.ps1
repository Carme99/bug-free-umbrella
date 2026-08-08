<#
.SYNOPSIS
    Detect if the device has not been restarted for 4 or more days

.DESCRIPTION
    Checks the OS uptime (time since last restart, derived from Win32_OperatingSystem.LastBootUpTime) and exits 1 when the device has not been restarted for 4 or more days so the uptime/remediate.ps1 restart notification can run. Sleep/hibernate time does not count towards uptime. Errors default to compliant (exit 0) to avoid false positives.

.EXAMPLE
    ./detect.ps1

.NOTES
    File Name  : detect.ps1
    Author     : Intune / Proactive Remediations
    Prerequisite: PowerShell 5.1 or later, run in the Intune Proactive Remediation context
    Version    : 1.0.0
    Date       : 2026-08-08
#>

# Detection Script - Check if machine has not been restarted for 4 or more days
# NOTE: OSUptime derives from Win32_OperatingSystem.LastBootUpTime, i.e. time since the
# OS was last restarted. Sleep/hibernate time does not count, so this measures "time since
# last restart", not cumulative time powered on.
# See https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem

try {
    $Uptime = (Get-ComputerInfo).OSUptime
    $UptimeDays = [math]::Floor($Uptime.TotalDays)
    
    if ($UptimeDays -ge 4) {
        Write-Output "Device has not been restarted in $UptimeDays days. Needs restart."
        exit 1 # Non-compliant (trigger remediation)
    }
    else {
        Write-Output "Device has been restarted within the last $UptimeDays days. No action needed."
        exit 0 # Compliant (no remediation)
    }
}
catch {
    Write-Output "Failed to get uptime: $_"
    exit 0 # Compliant by default on error (no false positives)
}
