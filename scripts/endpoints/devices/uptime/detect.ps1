# Detection Script - Check if machine has been on for 4 or more days

try {
    $Uptime = (Get-ComputerInfo).OSUptime
    $UptimeDays = [math]::Floor($Uptime.TotalDays)
    
    if ($UptimeDays -ge 4) {
        Write-Output "Device has been on for $UptimeDays days. Needs restart."
        Exit 1 # Non-compliant (trigger remediation)
    }
    else {
        Write-Output "Device has only been on for $UptimeDays days. No action needed."
        Exit 0 # Compliant (no remediation)
    }
}
catch {
    Write-Output "Failed to get uptime: $_"
    Exit 0 # Compliant by default on error (no false positives)
}
