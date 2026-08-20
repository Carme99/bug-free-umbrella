<#
.SYNOPSIS
    Detects disk health issues.

.DESCRIPTION
    Checks disk health status using SMART data and disk error counters.
    Early detection of disk issues can prevent data loss.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Disks are healthy
    Exit 1: Disk health issues detected
#>

try {
    $issues = @()

    # Get all physical disks
    $physicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue

    foreach ($disk in $physicalDisks) {
        # Check health status
        if ($disk.HealthStatus -ne "Healthy") {
            $issues += "Disk $($disk.FriendlyName): Health status is $($disk.HealthStatus)"
        }

        # Check operational status
        if ($disk.OperationalStatus -ne "OK") {
            $issues += "Disk $($disk.FriendlyName): Operational status is $($disk.OperationalStatus)"
        }

        # Check for predictive failure
        if ($disk.MediaType -eq "SSD" -or $disk.MediaType -eq "HDD") {
            $reliability = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction SilentlyContinue
            if ($reliability) {
                if ($reliability.ReadErrorsTotal -gt 0) {
                    $issues += "Disk $($disk.FriendlyName): $($reliability.ReadErrorsTotal) read errors detected"
                }
                if ($reliability.WriteErrorsTotal -gt 0) {
                    $issues += "Disk $($disk.FriendlyName): $($reliability.WriteErrorsTotal) write errors detected"
                }
            }
        }
    }

    # Check disk usage and fragmentation
    $volumes = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq "Fixed" }

    foreach ($volume in $volumes) {
        # Check for critically low disk space (less than 5%)
        if ($volume.Size -gt 0) {
            $freePercentage = ($volume.SizeRemaining / $volume.Size) * 100
            if ($freePercentage -lt 5) {
                $issues += "Volume $($volume.DriveLetter): Critically low disk space ($([math]::Round($freePercentage, 2))% free)"
            }
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host "Disk health issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "All disks are healthy"
    exit 0

}
catch {
    Write-Host "Error checking disk health: $_"
    exit 1
}
