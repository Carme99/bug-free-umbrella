<#
.SYNOPSIS
    Check laptop battery health and capacity degradation.

.DESCRIPTION
    Monitors battery design capacity vs current full charge capacity (via a
    powercfg XML battery report) and scans the System event log for battery
    capacity warnings to detect battery degradation on laptops.
    Exit codes: 0 = battery healthy or not applicable, 1 = battery degradation
    detected (or an unexpected error occurred). The script changes no system
    state apart from deleting its own temporary report file, so it is idempotent.
    The temporary report deletion is gated behind -WhatIf/-Confirm.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckBatteryHealth.ps1

    Exits 0 when the battery is healthy or absent; exits 1 when degradation is detected.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckBatteryHealth.ps1 -WhatIf

    Runs the health evaluation but keeps the temporary XML report file.

.NOTES
    File Name  : Test-RemediationCheckBatteryHealth.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

function Invoke-PowerCfg {
    # Thin wrapper around the native powercfg.exe executable.
    # Exists as the mock seam for Pester tests (native commands cannot be mocked).
    & powercfg.exe @args 2>&1 | Out-Null
    return $LASTEXITCODE
}

function Main {
    # Advanced function so $PSCmdlet (and thus ShouldProcess) resolves inside Main.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Checking battery health..." -ForegroundColor Cyan

        # Configuration
        $degradationThreshold = 70  # Percentage

        # Check if device has a battery
        $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue

        if (-not $battery) {
            Write-Host "[+] No battery detected (desktop or battery not present)" -ForegroundColor Green
            return 0
        }

        $issues = @()
        $reportPath = Join-Path $env:TEMP "battery-report.xml"

        # Get battery report via the native wrapper.
        $powercfgExitCode = Invoke-PowerCfg /batteryreport /output $reportPath /xml
        $powercfgSuccess = ($powercfgExitCode -eq 0)
        if ($powercfgSuccess -and (Test-Path $reportPath)) {
            [xml]$batteryReport = Get-Content $reportPath -ErrorAction Stop

            # Validate XML structure exists
            if ($batteryReport.BatteryReport.Batteries.Battery) {
                # Handle multi-battery systems - get first battery or single battery
                $reportBattery = if ($batteryReport.BatteryReport.Batteries.Battery -is [array]) {
                    $batteryReport.BatteryReport.Batteries.Battery[0]
                }
                else {
                    $batteryReport.BatteryReport.Batteries.Battery
                }

                # Validate properties exist before casting
                if ($reportBattery.DesignCapacity -and $reportBattery.FullChargeCapacity) {
                    $designCapacity = [int]$reportBattery.DesignCapacity
                    $fullChargeCapacity = [int]$reportBattery.FullChargeCapacity
                }
                else {
                    $designCapacity = 0
                    $fullChargeCapacity = 0
                }
            }
            else {
                $designCapacity = 0
                $fullChargeCapacity = 0
            }

            if ($designCapacity -gt 0) {
                $healthPercentage = [math]::Round(($fullChargeCapacity / $designCapacity) * 100, 1)

                if ($healthPercentage -lt $degradationThreshold) {
                    $issues += "Battery capacity degraded to $healthPercentage% (design: $designCapacity mWh, current: $fullChargeCapacity mWh)"
                }

                Write-Host "[*] Battery Health: $healthPercentage%" -ForegroundColor Cyan
                Write-Host "[*] Design Capacity: $designCapacity mWh" -ForegroundColor Cyan
                Write-Host "[*] Full Charge Capacity: $fullChargeCapacity mWh" -ForegroundColor Cyan
            }

            # Clean up the temporary report
            if ($PSCmdlet.ShouldProcess($reportPath, "Delete temporary battery report")) {
                Remove-Item $reportPath -Force -ErrorAction SilentlyContinue
            }
        }

        # Check for battery warnings in event log
        $batteryEvents = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Microsoft-Windows-Kernel-Power'
            ID           = 105, 106  # Battery capacity warnings
            StartTime    = (Get-Date).AddDays(-30)
        } -MaxEvents 5 -ErrorAction SilentlyContinue

        if ($batteryEvents) {
            $issues += "Battery capacity warnings detected in event log"
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] Battery health issues detected:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "[!]   - $issue" -ForegroundColor Yellow
            }
            return 1
        }

        Write-Host "[+] Battery health is acceptable" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking battery health: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
