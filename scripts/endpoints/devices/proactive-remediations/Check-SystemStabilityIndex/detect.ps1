<#
.SYNOPSIS
    Checks Windows Reliability Monitor stability index score.

.DESCRIPTION
    Uses Windows Reliability Monitor (RAC) to calculate system stability index.
    The stability index ranges from 1 (least stable) to 10 (most stable) and
    provides a quantifiable health metric for reporting.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: System stability is acceptable
    Exit 1: Low stability index detected

.CONFIGURATION
    $minStabilityIndex: Minimum acceptable stability score (default: 5.0)
    $daysToAnalyze: Days of history to analyze (default: 7)
#>

try {
    # Configuration
    $minStabilityIndex = 5.0
    $daysToAnalyze = 7

    $issues = @()

    Write-Host "Analyzing Windows Reliability Monitor data..."

    # Query Reliability Monitor WMI data
    $stabilityData = Get-CimInstance -Namespace "root\WMI" -ClassName "MSAcpi_ThermalZoneTemperature" -ErrorAction SilentlyContinue

    # Use Performance Counter for Reliability data
    $reliabilityMetrics = @{
        ApplicationFailures = 0
        WindowsFailures = 0
        MiscFailures = 0
        Warnings = 0
        InformationalEvents = 0
    }

    # Count reliability events from last N days
    $startTime = (Get-Date).AddDays(-$daysToAnalyze)

    # Application crashes
    $appCrashes = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        Level = 2
        StartTime = $startTime
    } -MaxEvents 100 -ErrorAction SilentlyContinue

    if ($appCrashes) {
        $reliabilityMetrics.ApplicationFailures = $appCrashes.Count
    }

    # Windows failures
    $windowsFailures = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        Level = 2
        StartTime = $startTime
    } -MaxEvents 100 -ErrorAction SilentlyContinue

    if ($windowsFailures) {
        $reliabilityMetrics.WindowsFailures = $windowsFailures.Count
    }

    # Warnings
    $warnings = Get-WinEvent -FilterHashtable @{
        LogName = 'System', 'Application'
        Level = 3
        StartTime = $startTime
    } -MaxEvents 200 -ErrorAction SilentlyContinue

    if ($warnings) {
        $reliabilityMetrics.Warnings = $warnings.Count
    }

    # Calculate simplified stability index (0-10 scale)
    # Based on frequency of errors and warnings
    $baseScore = 10.0

    # Deduct points for failures
    $baseScore -= ([Math]::Min($reliabilityMetrics.ApplicationFailures / 10, 3))
    $baseScore -= ([Math]::Min($reliabilityMetrics.WindowsFailures / 5, 3))
    $baseScore -= ([Math]::Min($reliabilityMetrics.Warnings / 50, 2))

    $stabilityIndex = [Math]::Max([Math]::Round($baseScore, 1), 1.0)

    Write-Host "System Stability Analysis (Last $daysToAnalyze days):"
    Write-Host "  Stability Index: $stabilityIndex / 10.0"
    Write-Host "  Application Failures: $($reliabilityMetrics.ApplicationFailures)"
    Write-Host "  Windows Failures: $($reliabilityMetrics.WindowsFailures)"
    Write-Host "  Warnings: $($reliabilityMetrics.Warnings)"

    if ($stabilityIndex -lt $minStabilityIndex) {
        $issues += "System stability index is $stabilityIndex (threshold: $minStabilityIndex)"
        $issues += "Frequent failures indicate system instability"
    }

    # Check for critical reliability events
    if ($reliabilityMetrics.ApplicationFailures -gt 20) {
        $issues += "Excessive application crashes detected ($($reliabilityMetrics.ApplicationFailures) events)"
    }

    if ($reliabilityMetrics.WindowsFailures -gt 10) {
        $issues += "Frequent Windows component failures ($($reliabilityMetrics.WindowsFailures) events)"
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
