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
        Exit 1 # Non-compliant (trigger remediation)
    }
    else {
        Write-Output "Device has been restarted within the last $UptimeDays days. No action needed."
        Exit 0 # Compliant (no remediation)
    }
}
catch {
    Write-Output "Failed to get uptime: $_"
    Exit 0 # Compliant by default on error (no false positives)
}
