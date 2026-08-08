<#
.SYNOPSIS
    Checks Windows Reliability Monitor stability index score.

.DESCRIPTION
    Uses the documented Reliability Analysis Component (RAC) metric
    Win32_ReliabilityStabilityMetrics.SystemStabilityIndex (namespace
    root\cimv2, RacWmiProv provider). The stability index ranges from 1
    (least stable) to 10 (most stable) and provides a quantifiable health
    metric for reporting.

    If RAC data is unavailable (for example the "Configure Reliability WMI
    Providers" policy is disabled, which is the default on Windows Server),
    the check reports that no index can be calculated and exits compliant.

.NOTES
    Author: Intune Admin
    Version: 1.1
    Intune Context: SYSTEM
    Exit 0: System stability is acceptable
    Exit 1: Low stability index detected

.CONFIGURATION
    $minStabilityIndex: Minimum acceptable stability score (default: 5.0)
#>

try {
    # Configuration
    $minStabilityIndex = 5.0

    $issues = @()

    Write-Host "Analyzing Windows Reliability Monitor data..."

    # Documented RAC metric (Win32_ReliabilityStabilityMetrics, root\cimv2).
    # See https://learn.microsoft.com/en-us/previous-versions/windows/desktop/racwmiprov/win32-reliabilitystabilitymetrics
    $stabilityData = Get-CimInstance -Namespace "root\cimv2" -ClassName "Win32_ReliabilityStabilityMetrics" -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $stabilityData) {
        # RAC data unavailable - report and exit compliant instead of fabricating a score.
        Write-Host "Reliability Monitor (RAC) stability data is not available on this system."
        Write-Host "No stability index can be calculated - treating as compliant."
        exit 0
    }

    $stabilityIndex = [double]$stabilityData.SystemStabilityIndex

    Write-Host "System Stability (Reliability Monitor):"
    Write-Host "  Stability Index: $stabilityIndex / 10.0"
    Write-Host "  Measurement period: $($stabilityData.StartMeasurementDate) to $($stabilityData.EndMeasurementDate)"

    if ($stabilityIndex -lt $minStabilityIndex) {
        $issues += "System stability index is $stabilityIndex (threshold: $minStabilityIndex)"
        $issues += "Frequent failures indicate system instability"
    }

    if ($issues.Count -gt 0) {
        Write-Host "`nStability issues detected:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
        Write-Host "`nRecommendation: Investigate recent changes, update drivers, check for malware"
        exit 1
    }

    Write-Host "`nSystem stability is within acceptable range"
    exit 0

} catch {
    Write-Host "Error checking system stability: $_"
    exit 1
}
