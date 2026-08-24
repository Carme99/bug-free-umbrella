<#
.SYNOPSIS
    Check the Windows Reliability Monitor stability index score.

.DESCRIPTION
    Uses the documented Reliability Analysis Component (RAC) metric
    Win32_ReliabilityStabilityMetrics.SystemStabilityIndex (namespace root\cimv2,
    RacWmiProv provider). The stability index ranges from 1 (least stable) to 10 (most
    stable) and provides a quantifiable health metric for reporting; the device is
    flagged when the index falls below the minimum acceptable score (default 5.0).
    If RAC data is unavailable (for example the "Configure Reliability WMI Providers"
    policy is disabled, which is the default on Windows Server), the check reports that
    no index can be calculated and exits compliant.
    Exit codes: 0 = compliant/healthy (stability acceptable or not calculable), 1 =
    issue detected (low stability index, or an unexpected error occurred). The script
    changes no system state, so it is idempotent.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckSystemStabilityIndex.ps1

    Exits 0 when the stability index is acceptable or unavailable; exits 1 when a low
    stability index is detected.

.EXAMPLE
    PS C:\> .\Test-RemediationCheckSystemStabilityIndex.ps1 -Verbose

    Runs the same read-only analysis with verbose pipeline output for troubleshooting.

.NOTES
    File Name  : Test-RemediationCheckSystemStabilityIndex.ps1
    Author     : Intune Admin
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Main {
    param()

    try {
        # Configuration
        $minStabilityIndex = 5.0

        $issues = @()

        Write-Host "[*] Analyzing Windows Reliability Monitor data..." -ForegroundColor Cyan

        # Documented RAC metric (Win32_ReliabilityStabilityMetrics, root\cimv2).
        # See https://learn.microsoft.com/en-us/previous-versions/windows/desktop/racwmiprov/win32-reliabilitystabilitymetrics
        $stabilityData = Get-CimInstance -Namespace "root\cimv2" -ClassName "Win32_ReliabilityStabilityMetrics" -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if (-not $stabilityData) {
            # RAC data unavailable - report and exit compliant instead of fabricating a score.
            Write-Host "[+] RAC stability data is not available on this system" -ForegroundColor Green
            Write-Host "[+] No stability index can be calculated - treating as compliant" -ForegroundColor Green
            return 0
        }

        $stabilityIndex = [double]$stabilityData.SystemStabilityIndex

        Write-Host "[*] System Stability (Reliability Monitor):" -ForegroundColor Cyan
        Write-Host "[*]   Stability Index: $stabilityIndex / 10.0" -ForegroundColor Cyan
        Write-Host "[*]   Measurement period: $($stabilityData.StartMeasurementDate) to $($stabilityData.EndMeasurementDate)" -ForegroundColor Cyan

        if ($stabilityIndex -lt $minStabilityIndex) {
            $issues += "System stability index is $stabilityIndex (threshold: $minStabilityIndex)"
            $issues += "Frequent failures indicate system instability"
        }

        if ($issues.Count -gt 0) {
            Write-Host "[!] Stability issues detected:" -ForegroundColor Yellow
            foreach ($issue in $issues) {
                Write-Host "[!]   - $issue" -ForegroundColor Yellow
            }
            Write-Host "[*] Recommendation: Investigate recent changes, update drivers, check for malware" -ForegroundColor Cyan
            return 1
        }

        Write-Host "[+] System stability is within acceptable range" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error checking system stability: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
