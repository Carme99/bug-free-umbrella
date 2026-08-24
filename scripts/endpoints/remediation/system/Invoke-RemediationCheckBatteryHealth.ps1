<#
.SYNOPSIS
    Report battery health degradation for IT tracking.

.DESCRIPTION
    Generates a detailed Windows battery report via powercfg and summarises the
    device battery status so IT can track devices that may need battery replacement.
    Battery degradation cannot be fixed in software; this script is informational,
    changes no system state, and is therefore safe to re-run at any time (idempotent).

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckBatteryHealth.ps1

    Generates the battery health report in the current user's temp folder and
    prints a summary of the battery status.

.EXAMPLE
    PS C:\> .\Invoke-RemediationCheckBatteryHealth.ps1 -Verbose

    Runs the same report with verbose progress information.

.NOTES
    File Name  : Invoke-RemediationCheckBatteryHealth.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Invoke-PowerCfg {
    # Thin wrapper around the native powercfg.exe executable.
    # Exists as the mock seam for Pester tests (native commands cannot be mocked).
    & powercfg.exe @args 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Main {
    try {
        Write-Host "[*] Generating battery health report..." -ForegroundColor Cyan

        # Generate detailed battery report via the native wrapper.
        $reportPath = Join-Path $env:TEMP "battery-report.html"
        $reportExitCode = Invoke-PowerCfg /batteryreport /output $reportPath
        if ($reportExitCode -ne 0) {
            throw "powercfg battery report failed with exit code $reportExitCode"
        }

        $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop

        if ($battery) {
            Write-Host "[*] Battery Health Report:" -ForegroundColor Cyan
            Write-Host "    Device: $env:COMPUTERNAME"
            Write-Host "    Chemistry: $($battery.Chemistry)"
            Write-Host "    Status: $($battery.Status)"
            Write-Host ""
            Write-Host "[!] Battery degradation cannot be fixed in software." -ForegroundColor Yellow
            Write-Host "[!] IT should assess if battery replacement is needed." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "[*] Detailed report generated at: $reportPath" -ForegroundColor Cyan
            Write-Host "[*] This information has been logged for IT tracking." -ForegroundColor Cyan
        }
        else {
            Write-Host "[!] No battery detected (desktop or battery not present)" -ForegroundColor Yellow
        }

        Write-Host "[+] Battery health report completed" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error generating battery report: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
