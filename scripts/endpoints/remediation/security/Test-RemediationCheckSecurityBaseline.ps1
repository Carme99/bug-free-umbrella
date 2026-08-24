<#
.SYNOPSIS
    Detects security baseline drift on core Windows hardening settings.

.DESCRIPTION
    Checks core security baseline settings: Windows Firewall profiles enabled, Windows
    Defender real-time protection and signature age, UAC (EnableLUA), and the automatic
    updates policy. This is a read-only detection script: it never modifies anything,
    so re-running it on a compliant device converges to exit 0 (idempotent).
    Exit codes:
    - 0: compliant - all baseline settings match the expected values.
    - 1: non-compliant - baseline drift was found (or the check failed) so remediation can run.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckSecurityBaseline.ps1
    Runs the baseline check and exits 1 when firewall, Defender, UAC or update-policy drift is found.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationCheckSecurityBaseline.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.

.NOTES
    File Name: Test-RemediationCheckSecurityBaseline.ps1
    Author: Intune / Proactive Remediations
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Checking security baseline..." -ForegroundColor Cyan

        $issues = @()

        # Check Windows Firewall
        $firewallProfiles = Get-NetFirewallProfile -ErrorAction Stop
        foreach ($profile in $firewallProfiles) {
            if (-not $profile.Enabled) {
                $issues += "Firewall $($profile.Name) profile is disabled"
            }
        }

        # Check Windows Defender
        $defenderStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($defenderStatus) {
            if (-not $defenderStatus.RealTimeProtectionEnabled) {
                $issues += "Real-time protection disabled"
            }
            if ($defenderStatus.AntivirusSignatureAge -gt 7) {
                $issues += "Antivirus signatures outdated ($($defenderStatus.AntivirusSignatureAge) days)"
            }
        }

        # Check UAC
        $uacKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        $uacKey = Get-ItemProperty $uacKeyPath -ErrorAction SilentlyContinue
        if ($uacKey.EnableLUA -ne 1) {
            $issues += "UAC is disabled"
        }

        # Check automatic updates
        $wuKeyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        $wuKey = Get-ItemProperty $wuKeyPath -ErrorAction SilentlyContinue
        if ($wuKey.NoAutoUpdate -eq 1) {
            $issues += "Automatic updates disabled"
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] Security baseline issues: $($issues -join '; ')" -ForegroundColor Yellow
            return 1
        }

        Write-Host "[+] Security baseline compliant" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking security baseline: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
