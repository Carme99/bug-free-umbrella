<#
.SYNOPSIS
    Detect low disk space on fixed drives

.DESCRIPTION
    Checks all fixed disk volumes for low disk space conditions.
    Reports non-compliant if any volume has less than the configured
    percentage or absolute GB threshold remaining.

.NOTES
    For Intune Proactive Remediations
    Exit 0 = Compliant (sufficient disk space)
    Exit 1 = Non-compliant (low disk space detected)

    Default Thresholds:
    - Less than 10% free space, OR
    - Less than 10 GB free space
#>

[CmdletBinding()]
param()

# Configuration - Named constants for clarity
$DISK_SPACE_WARNING_PERCENT = 10  # Minimum acceptable free space percentage
$DISK_SPACE_WARNING_GB = 10       # Minimum acceptable free space in GB

$volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
$issues = @()

foreach ($vol in $volumes) {
    $freePercent = ($vol.SizeRemaining / $vol.Size) * 100
    $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 2)

    if ($freePercent -lt $DISK_SPACE_WARNING_PERCENT -or $freeGB -lt $DISK_SPACE_WARNING_GB) {
        $issues += "$($vol.DriveLetter): $freeGB GB free ($([math]::Round($freePercent, 1))%)"
    }
}

if ($issues.Count -gt 0) {
    Write-Host "Low disk space detected: $($issues -join ', ')"
    exit 1
}

Write-Host "Disk space healthy"
exit 0
