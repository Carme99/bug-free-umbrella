<#
.SYNOPSIS
    Detects if Windows Defender is healthy and properly configured.

.DESCRIPTION
    Checks Windows Defender real-time protection status, signature updates,
    and service health. Critical for maintaining endpoint security posture.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Defender is healthy
    Exit 1: Issues detected - remediation needed
#>

try {
    $issues = @()

    # Check if Defender service is running
    $defenderService = Get-Service -Name "WinDefend" -ErrorAction SilentlyContinue
    if ($defenderService.Status -ne "Running") {
        $issues += "Windows Defender service is not running"
    }

    # Check real-time protection status
    $mpPreference = Get-MpPreference -ErrorAction SilentlyContinue
    if ($mpPreference.DisableRealtimeMonitoring -eq $true) {
        $issues += "Real-time protection is disabled"
    }

    # Check signature age (should be less than 7 days old)
    $mpComputerStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($mpComputerStatus) {
        $signatureAge = (Get-Date) - $mpComputerStatus.AntivirusSignatureLastUpdated
        if ($signatureAge.TotalDays -gt 7) {
            $issues += "Defender signatures are outdated (last updated: $($mpComputerStatus.AntivirusSignatureLastUpdated))"
        }

        # Check if Defender is enabled
        if ($mpComputerStatus.AntivirusEnabled -eq $false) {
            $issues += "Windows Defender antivirus is disabled"
        }
    }

    # Check for pending full scan (if last full scan > 30 days)
    if ($mpComputerStatus.FullScanAge -gt 30) {
        $issues += "Full scan has not run in $($mpComputerStatus.FullScanAge) days"
    }

    if ($issues.Count -gt 0) {
        Write-Host "Defender health issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        exit 1
    }

    Write-Host "Windows Defender is healthy and up to date"
    exit 0

}
catch {
    Write-Host "Error checking Defender status: $_"
    exit 1
}
