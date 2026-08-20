<#
.SYNOPSIS
    Detects stuck "reboot pending" state for Windows Update.

.DESCRIPTION
    Checks for false positive reboot pending states that prevent updates
    from installing properly.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: No stuck reboot state
    Exit 1: Stuck reboot detected
#>

try {
    $issues = @()
    $rebootPending = $false

    # Check Component-Based Servicing
    $cbsReboot = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue
    if ($cbsReboot) {
        $rebootPending = $true
        $issues += "Component-Based Servicing indicates reboot pending"
    }

    # Check Windows Update
    $wuReboot = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue
    if ($wuReboot) {
        $rebootPending = $true
        $issues += "Windows Update indicates reboot required"
    }

    # Check PendingFileRenameOperations
    $pendingFileRename = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
    if ($pendingFileRename) {
        $rebootPending = $true
        $issues += "Pending file rename operations detected"
    }

    # Check if reboot has been pending for too long (more than 7 days)
    if ($rebootPending) {
        # Get last boot time
        $os = Get-WmiObject -Class Win32_OperatingSystem
        $lastBoot = $os.ConvertToDateTime($os.LastBootUpTime)
        $daysSinceBoot = ((Get-Date) - $lastBoot).Days

        if ($daysSinceBoot -gt 7) {
            $issues += "System has not been rebooted in $daysSinceBoot days"
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host "Reboot pending state detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "No stuck reboot pending state detected"
    exit 0

}
catch {
    Write-Host "Error checking reboot pending state: $_"
    exit 1
}
