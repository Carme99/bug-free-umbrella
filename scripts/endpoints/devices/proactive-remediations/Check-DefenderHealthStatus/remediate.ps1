<#
.SYNOPSIS
    Remediates Windows Defender health issues.

.DESCRIPTION
    Attempts to fix common Defender issues including enabling real-time protection,
    updating signatures, and starting required services.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Start Windows Defender service if stopped
    $defenderService = Get-Service -Name "WinDefend" -ErrorAction SilentlyContinue
    if ($defenderService.Status -ne "Running") {
        Start-Service -Name "WinDefend" -ErrorAction SilentlyContinue
        $remediationActions += "Started Windows Defender service"
    }

    # Enable real-time protection
    $mpPreference = Get-MpPreference -ErrorAction SilentlyContinue
    if ($mpPreference.DisableRealtimeMonitoring -eq $true) {
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
        $remediationActions += "Enabled real-time protection"
    }

    # Update Defender signatures
    $mpComputerStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($mpComputerStatus) {
        $signatureAge = (Get-Date) - $mpComputerStatus.AntivirusSignatureLastUpdated
        if ($signatureAge.TotalDays -gt 7) {
            Update-MpSignature -ErrorAction SilentlyContinue
            $remediationActions += "Updated Defender signatures"
        }
    }

    # Enable antivirus if disabled
    if ($mpComputerStatus.AntivirusEnabled -eq $false) {
        Set-MpPreference -DisableAntivirus $false -ErrorAction SilentlyContinue
        $remediationActions += "Enabled Windows Defender antivirus"
    }

    # Trigger quick scan if needed
    $mpComputerStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($mpComputerStatus.QuickScanAge -gt 7) {
        Start-MpScan -ScanType QuickScan -AsJob -ErrorAction SilentlyContinue
        $remediationActions += "Initiated quick scan"
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "Defender remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
    } else {
        Write-Host "No remediation actions were necessary"
    }

    exit 0

} catch {
    Write-Host "Error during Defender remediation: $_"
    exit 1
}
