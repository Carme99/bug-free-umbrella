<#
.SYNOPSIS
    Detects a stuck reboot-pending state caused by Windows Update.

.DESCRIPTION
    Checks the three standard reboot-pending indicators: the Component Based Servicing
    RebootPending key, the Windows Update RebootRequired key, and PendingFileRenameOperations.
    When any indicator is present, the script also measures system uptime and flags devices that
    have not been rebooted for more than 7 days, because stale reboot-pending states prevent
    updates from installing properly.
    Exit codes:
    - 0: compliant - no stuck reboot-pending state detected.
    - 1: non-compliant or failure - a reboot-pending state was detected, the system has not been
      rebooted within 7 days while a reboot is pending, or the check itself failed.

.EXAMPLE
    PS C:\> .\Test-RemediationFixWindowsUpdateRebootPending.ps1
    Runs the detection check and exits 0 when no stuck reboot state exists, 1 when one is found.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\Test-RemediationFixWindowsUpdateRebootPending.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.

.NOTES
    File Name: Test-RemediationFixWindowsUpdateRebootPending.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

#region Functions

function Main {
    try {
        $outputMsg = "[*] Checking reboot-pending state..."
        Write-Host $outputMsg -ForegroundColor Cyan

        $issues = @()
        $rebootPending = $false

        # Check Component-Based Servicing
        $cbsPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
        $cbsReboot = Get-ItemProperty -Path $cbsPath -ErrorAction SilentlyContinue
        if ($cbsReboot) {
            $rebootPending = $true
            $issues += "Component-Based Servicing indicates reboot pending"
        }

        # Check Windows Update
        $wuPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
        $wuReboot = Get-ItemProperty -Path $wuPath -ErrorAction SilentlyContinue
        if ($wuReboot) {
            $rebootPending = $true
            $issues += "Windows Update indicates reboot required"
        }

        # Check PendingFileRenameOperations
        $sessionMgrPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        $pendingFileRename = Get-ItemProperty -Path $sessionMgrPath -Name "PendingFileRenameOperations" `
            -ErrorAction SilentlyContinue
        if ($pendingFileRename) {
            $rebootPending = $true
            $issues += "Pending file rename operations detected"
        }

        # Check if reboot has been pending for too long (more than 7 days)
        if ($rebootPending) {
            # Get last boot time
            $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
            $lastBoot = $os.ConvertToDateTime($os.LastBootUpTime)
            $daysSinceBoot = ((Get-Date) - $lastBoot).Days

            if ($daysSinceBoot -gt 7) {
                $issues += "System has not been rebooted in $daysSinceBoot days"
            }
        }

        if ($issues.Count -gt 0) {
            $outputMsg = "[!] Reboot pending state detected:"
            Write-Host $outputMsg -ForegroundColor Yellow
            foreach ($issue in $issues) {
                $outputMsg = "[!]   - $issue"
                Write-Host $outputMsg -ForegroundColor Yellow
            }
            return 1
        }

        $outputMsg = "[+] No stuck reboot-pending state detected"

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking reboot-pending state: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
