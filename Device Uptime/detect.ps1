try {
    # Using Get-Uptime for faster performance
    $Uptime = (Get-Uptime).Days
} catch {
    Write-Output "Unable to determine system uptime."
    Exit 0
}

if ($Uptime -ge 4) {
    Write-Output "Device has not rebooted in $Uptime days, notify user to reboot"
    Exit 1
} else {
    Write-Output "Device has rebooted $Uptime days ago, all good"
    Exit 0
}