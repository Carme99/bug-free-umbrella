<#
.SYNOPSIS
    Attempts to remediate disk health issues.

.DESCRIPTION
    Runs disk maintenance tasks including disk cleanup and error checking.
    Severe disk failures cannot be fixed and require hardware replacement.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Run disk cleanup for system files on C: drive
    try {
        Write-Host "Running disk cleanup..."
        # Configure disk cleanup to run automatically
        $volumeCachesPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"

        # Enable common cleanup items
        $cleanupItems = @(
            "Temporary Files",
            "Temporary Setup Files",
            "Downloaded Program Files",
            "Recycle Bin",
            "Temporary Internet Files"
        )

        foreach ($item in $cleanupItems) {
            $itemPath = Join-Path $volumeCachesPath $item
            if (Test-Path $itemPath) {
                Set-ItemProperty -Path $itemPath -Name "StateFlags0001" -Value 2 -Type DWord -ErrorAction SilentlyContinue
            }
        }

        # Run cleanmgr
        Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:1" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
        $remediationActions += "Executed disk cleanup"
    } catch {
        Write-Host "Warning: Could not complete disk cleanup: $_"
    }

    # Schedule disk check for next reboot on system drive
    try {
        $systemDrive = $env:SystemDrive
        Write-Host "Scheduling disk check for $systemDrive on next reboot..."
        chkdsk $systemDrive /F /R /X 2>&1 | Out-Null
        $remediationActions += "Scheduled disk check for next reboot"
    } catch {
        Write-Host "Warning: Could not schedule disk check: $_"
    }

    # Optimize/defragment drives (SSD = trim, HDD = defrag)
    $volumes = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq "Fixed" -and $_.DriveLetter }

    foreach ($volume in $volumes) {
        try {
            Optimize-Volume -DriveLetter $volume.DriveLetter -Verbose -ErrorAction SilentlyContinue
            $remediationActions += "Optimized volume $($volume.DriveLetter):"
        } catch {
            Write-Host "Warning: Could not optimize volume $($volume.DriveLetter): $_"
        }
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "Disk health remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
        Write-Host ""
        Write-Host "Note: Disk errors may require a system restart to fully repair"
        Write-Host "Hardware failures require physical disk replacement"
    } else {
        Write-Host "No disk maintenance actions were necessary"
    }

    exit 0

} catch {
    Write-Host "Error during disk health remediation: $_"
    exit 1
}
