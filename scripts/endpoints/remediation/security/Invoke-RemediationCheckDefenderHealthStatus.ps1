<#
.SYNOPSIS
    Remediates common Windows Defender health issues on the local machine.

.DESCRIPTION
    Checks Windows Defender health and applies corrective actions where needed: starts the
    WinDefend service if it is stopped, re-enables real-time protection and antivirus, refreshes
    signatures older than 7 days and triggers a quick scan when the last quick scan is stale.
    Every mutating action is guarded by ShouldProcess, so -WhatIf previews the remediation plan.
    Exit codes:
    - 0: remediation successful, or no remediation actions were necessary.
    - 1: an unexpected error occurred while checking or remediating Defender health.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckDefenderHealthStatus.ps1
    Runs the Defender health remediation in the Intune Proactive Remediation SYSTEM context.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckDefenderHealthStatus.ps1 -WhatIf
    Shows which remediation actions would run without changing anything.

.NOTES
    File Name: Invoke-RemediationCheckDefenderHealthStatus.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]

param()

$ErrorActionPreference = 'Stop'

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        $outputMsg = "[*] Checking Windows Defender health..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $remediationActions = @()

        # Start Windows Defender service if stopped
        $defenderService = Get-Service -Name "WinDefend" -ErrorAction SilentlyContinue
        if ($defenderService.Status -ne "Running") {
            if ($PSCmdlet.ShouldProcess("WinDefend", "Start Windows Defender service")) {
                Start-Service -Name "WinDefend" -ErrorAction Stop
            }
            $remediationActions += "Started Windows Defender service"
        }

        # Enable real-time protection
        $mpPreference = Get-MpPreference -ErrorAction Stop
        if ($mpPreference.DisableRealtimeMonitoring -eq $true) {
            if ($PSCmdlet.ShouldProcess("Windows Defender preferences", "Enable real-time monitoring")) {
                Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
            }
            $remediationActions += "Enabled real-time protection"
        }

        # Update Defender signatures when older than 7 days
        $mpComputerStatus = Get-MpComputerStatus -ErrorAction Stop
        if ($mpComputerStatus) {
            $signatureAge = (Get-Date) - $mpComputerStatus.AntivirusSignatureLastUpdated
            if ($signatureAge.TotalDays -gt 7) {
                if ($PSCmdlet.ShouldProcess("Windows Defender", "Update antivirus signatures")) {
                    Update-MpSignature -ErrorAction Stop
                }
                $remediationActions += "Updated Defender signatures"
            }
        }

        # Enable antivirus if disabled
        if ($mpComputerStatus.AntivirusEnabled -eq $false) {
            if ($PSCmdlet.ShouldProcess("Windows Defender", "Enable antivirus")) {
                Set-MpPreference -DisableAntivirus $false -ErrorAction Stop
            }
            $remediationActions += "Enabled Windows Defender antivirus"
        }

        # Trigger quick scan if the last quick scan is older than 7 days
        $mpComputerStatus = Get-MpComputerStatus -ErrorAction Stop
        if ($mpComputerStatus.QuickScanAge -gt 7) {
            if ($PSCmdlet.ShouldProcess("Windows Defender", "Start quick scan")) {
                Start-MpScan -ScanType QuickScan -AsJob -ErrorAction Stop
            }
            $remediationActions += "Initiated quick scan"
        }

        if ($remediationActions.Count -gt 0) {
            $outputMsg = "[+] Defender remediation completed:"
            Write-Host $outputMsg -ForegroundColor Green
            foreach ($action in $remediationActions) {
                Write-Host "  - $action"
            }
        }
        else {
            $outputMsg = "[*] No remediation actions were necessary"
            Write-Host $outputMsg -ForegroundColor Cyan
        }

        return 0
    }
    catch {
        $outputMsg = "[-] Error during Defender remediation: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
