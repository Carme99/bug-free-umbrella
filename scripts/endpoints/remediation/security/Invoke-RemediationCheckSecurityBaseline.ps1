<#
.SYNOPSIS
    Remediate security baseline drift on the local machine.

.DESCRIPTION
    Re-applies the security baseline detected by the companion security baseline check: enables
    disabled Windows Firewall profiles, re-enables Defender real-time protection, updates Defender
    signatures and re-enables UAC (EnableLUA) when policy drift is found.
    Every change is guarded by ShouldProcess, so -WhatIf previews the applied settings.
    Exit codes:
    - 0: remediation successful, or no remediation was needed.
    - 1: an unexpected error occurred while applying the security baseline.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckSecurityBaseline.ps1
    Applies firewall, Defender, signature and UAC baseline settings where drift is detected.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckSecurityBaseline.ps1 -WhatIf
    Lists the baseline changes that would be applied without modifying the system.

.NOTES
    File Name: Invoke-RemediationCheckSecurityBaseline.ps1
    Author: Intune / Proactive Remediations
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
        $outputMsg = "[*] Checking security baseline..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $remediated = @()
        $uacRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

        # Enable Windows Firewall
        $firewallProfiles = Get-NetFirewallProfile -ErrorAction Stop
        foreach ($fwProfile in $firewallProfiles) {
            if (-not $fwProfile.Enabled) {
                if ($PSCmdlet.ShouldProcess($fwProfile.Name, "Enable $($fwProfile.Name) firewall profile")) {
                    Set-NetFirewallProfile -Profile $fwProfile.Name -Enabled True -ErrorAction Stop
                }
                $remediated += "Enabled $($fwProfile.Name) firewall profile"
            }
        }

        # Enable Windows Defender real-time protection
        $defenderStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($defenderStatus -and -not $defenderStatus.RealTimeProtectionEnabled) {
            if ($PSCmdlet.ShouldProcess("Windows Defender", "Enable real-time protection")) {
                Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
            }
            $remediated += "Enabled real-time protection"
        }

        # Update Defender signatures
        if ($PSCmdlet.ShouldProcess("Windows Defender", "Update antivirus signatures")) {
            Update-MpSignature -ErrorAction Stop
        }
        $remediated += "Updated antivirus signatures"

        # Enable UAC
        $uacKey = Get-ItemProperty -Path $uacRegistryPath -ErrorAction SilentlyContinue
        if ($uacKey.EnableLUA -ne 1) {
            if ($PSCmdlet.ShouldProcess($uacRegistryPath, "Set EnableLUA to 1 (enable UAC)")) {
                Set-ItemProperty -Path $uacRegistryPath -Name "EnableLUA" -Value 1 -ErrorAction Stop
            }
            $remediated += "Enabled UAC"
        }

        if ($remediated.Count -gt 0) {
            $outputMsg = "[+] Remediated $($remediated.Count) issues: $($remediated -join '; ')"
            Write-Host $outputMsg -ForegroundColor Green
        }
        else {
            $outputMsg = "[*] No remediation needed"
            Write-Host $outputMsg -ForegroundColor Cyan
        }

        return 0
    }
    catch {
        $outputMsg = "[-] Error remediating security baseline: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
