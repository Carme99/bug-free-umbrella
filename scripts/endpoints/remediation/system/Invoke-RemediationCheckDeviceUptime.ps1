<#
.SYNOPSIS
    Assess device uptime and pending-reboot state.

.DESCRIPTION
    Reads the current uptime from Win32_OperatingSystem and checks the Windows Update and
    Component Based Servicing registry markers for pending reboots, then logs recommended
    actions for IT review when uptime exceeds 14 days or a reboot is pending. The script
    changes no system state - it only reads and reports - so it is idempotent and safe to
    re-run at any time.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckDeviceUptime.ps1

    Prints the current uptime, any pending reboot reasons and recommended actions.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckDeviceUptime.ps1 -Verbose

    Runs the same assessment with verbose progress information.

.NOTES
    File Name  : Invoke-RemediationCheckDeviceUptime.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Device Uptime Remediation:" -ForegroundColor Cyan

        # Get uptime info.
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop

        if (-not $os) {
            Write-Host "[!] Unable to determine uptime: Win32_OperatingSystem returned no data" -ForegroundColor Yellow
            return 0
        }

        $uptime = (Get-Date) - $os.LastBootUpTime
        $uptimeDays = [Math]::Round($uptime.TotalDays, 2)
        Write-Host "    Current Uptime: $uptimeDays days"
        Write-Host "    Last Boot: $($os.LastBootUpTime)"

        $remediationActions = @()
        $rebootReasons = @()

        # Check for pending reboots.
        $windowsUpdateKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        $cbsKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'

        if (Test-Path $windowsUpdateKey -ErrorAction SilentlyContinue) {
            $rebootReasons += 'Windows Update'
        }

        if (Test-Path $cbsKey -ErrorAction SilentlyContinue) {
            $rebootReasons += 'Component Based Servicing'
        }

        if ($rebootReasons.Count -gt 0) {
            Write-Host "[!] Pending Reboot Reasons: $($rebootReasons -join ', ')" -ForegroundColor Yellow
            $remediationActions += "Pending reboot detected for: $($rebootReasons -join ', ')"
        }

        if ($uptimeDays -gt 14) {
            Write-Host "[!] Uptime of $uptimeDays days exceeds the 14 day threshold" -ForegroundColor Yellow
            $remediationActions += 'Device uptime exceeds 14 days - reboot recommended for system health'
        }

        if ($remediationActions.Count -eq 0) {
            Write-Host "[+] Already compliant: uptime within policy and no pending reboot" -ForegroundColor Green
            return 0
        }

        # Create a record of the remediation for Intune reporting (no user notification is
        # possible from SYSTEM context, so IT reviews the logged output instead).
        Write-Host ""
        Write-Host "[*] Remediation logged in Intune for IT review." -ForegroundColor Cyan
        Write-Host "    IT should contact user to schedule reboot if needed."
        Write-Host "Recommended actions:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
        Write-Host "[+] Device uptime assessment completed" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error during uptime remediation: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
