<#
.SYNOPSIS
    Calculates comprehensive device health score for reporting.

.DESCRIPTION
    Aggregates multiple health metrics (uptime, crashes, errors, hardware) into
    a single 0-100 health score. Provides detailed breakdown for reporting and
    identifies devices needing attention.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Health score calculated successfully
    Exit 1: Poor health score (below threshold)

.CONFIGURATION
    $minHealthScore: Minimum acceptable health score (default: 70/100)
    $daysToAnalyze: Historical period for analysis (default: 7 days)
#>

try {
    # Configuration
    $minHealthScore = 70
    $daysToAnalyze = 7

    # Initialize health score (start at 100, deduct points for issues)
    $healthScore = 100
    $healthReport = @{
        DeviceName = $env:COMPUTERNAME
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        TotalScore = 0
        Categories = @{}
        Issues = @()
        Recommendations = @()
    }

    Write-Host "==================================="
    Write-Host "Device Health Score Analysis"
    Write-Host "==================================="
    Write-Host "Device: $env:COMPUTERNAME"
    Write-Host "Analysis Period: Last $daysToAnalyze days"
    Write-Host ""

    # 1. UPTIME HEALTH (Max deduction: 10 points)
    Write-Host "[1/8] Analyzing Uptime..."
    $uptimeScore = 100
    $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction SilentlyContinue

    if ($os) {
        $lastBoot = $os.ConvertToDateTime($os.LastBootUpTime)
        $uptime = (Get-Date) - $lastBoot
        $uptimeDays = [math]::Round($uptime.TotalDays, 2)

        if ($uptimeDays -gt 30) {
            $uptimeScore -= 10
            $healthReport.Issues += "Excessive uptime: $uptimeDays days"
        } elseif ($uptimeDays -gt 14) {
            $uptimeScore -= 5
            $healthReport.Issues += "High uptime: $uptimeDays days"
        }

        Write-Host "  Uptime: $uptimeDays days | Score: $uptimeScore/100"
        $healthReport.Categories.Uptime = $uptimeScore
    }

    # 2. CRASH/REBOOT STABILITY (Max deduction: 15 points)
    Write-Host "[2/8] Analyzing System Crashes..."
    $crashScore = 100

    $crashes = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Microsoft-Windows-Kernel-Power'
        ID = 41
        StartTime = (Get-Date).AddDays(-$daysToAnalyze)
    } -MaxEvents 20 -ErrorAction SilentlyContinue

    if ($crashes) {
        $crashCount = $crashes.Count
        $crashScore -= [Math]::Min($crashCount * 3, 15)
        $healthReport.Issues += "System crashes: $crashCount events"
        Write-Host "  Crashes: $crashCount | Score: $crashScore/100"
    } else {
        Write-Host "  Crashes: 0 | Score: $crashScore/100"
    }
    $healthReport.Categories.CrashStability = $crashScore

    # 3. APPLICATION STABILITY (Max deduction: 10 points)
    Write-Host "[3/8] Analyzing Application Crashes..."
    $appScore = 100

    $appCrashes = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        ProviderName = 'Application Error'
        ID = 1000
        StartTime = (Get-Date).AddDays(-$daysToAnalyze)
    } -MaxEvents 50 -ErrorAction SilentlyContinue

    if ($appCrashes) {
        $appCrashCount = $appCrashes.Count
        $appScore -= [Math]::Min([Math]::Floor($appCrashCount / 2), 10)
        $healthReport.Issues += "Application crashes: $appCrashCount events"
        Write-Host "  App Crashes: $appCrashCount | Score: $appScore/100"
    } else {
        Write-Host "  App Crashes: 0 | Score: $appScore/100"
    }
    $healthReport.Categories.ApplicationStability = $appScore

    # 4. SERVICE HEALTH (Max deduction: 10 points)
    Write-Host "[4/8] Analyzing Service Failures..."
    $serviceScore = 100

    $serviceFails = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Service Control Manager'
        ID = 7034, 7031
        StartTime = (Get-Date).AddDays(-$daysToAnalyze)
    } -MaxEvents 30 -ErrorAction SilentlyContinue

    if ($serviceFails) {
        $serviceFailCount = $serviceFails.Count
        $serviceScore -= [Math]::Min([Math]::Floor($serviceFailCount / 3), 10)
        $healthReport.Issues += "Service failures: $serviceFailCount events"
        Write-Host "  Service Failures: $serviceFailCount | Score: $serviceScore/100"
    } else {
        Write-Host "  Service Failures: 0 | Score: $serviceScore/100"
    }
    $healthReport.Categories.ServiceHealth = $serviceScore

    # 5. CRITICAL SYSTEM ERRORS (Max deduction: 15 points)
    Write-Host "[5/8] Analyzing Critical Errors..."
    $criticalScore = 100

    $criticalErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        Level = 1
        StartTime = (Get-Date).AddDays(-$daysToAnalyze)
    } -MaxEvents 30 -ErrorAction SilentlyContinue

    if ($criticalErrors) {
        $criticalCount = $criticalErrors.Count
        $criticalScore -= [Math]::Min($criticalCount * 2, 15)
        $healthReport.Issues += "Critical system errors: $criticalCount events"
        Write-Host "  Critical Errors: $criticalCount | Score: $criticalScore/100"
    } else {
        Write-Host "  Critical Errors: 0 | Score: $criticalScore/100"
    }
    $healthReport.Categories.SystemErrors = $criticalScore

    # 6. HARDWARE HEALTH (Max deduction: 20 points)
    Write-Host "[6/8] Analyzing Hardware Health..."
    $hardwareScore = 100

    # Check WHEA errors
    $wheaErrors = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Microsoft-Windows-WHEA-Logger'
        StartTime = (Get-Date).AddDays(-$daysToAnalyze)
    } -MaxEvents 20 -ErrorAction SilentlyContinue

    if ($wheaErrors) {
        $wheaCount = $wheaErrors.Count
        $hardwareScore -= [Math]::Min($wheaCount * 5, 20)
        $healthReport.Issues += "Hardware errors (WHEA): $wheaCount events"
    }

    # Check disk SMART
    $disks = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
    if ($disks) {
        foreach ($disk in $disks) {
            if ($disk.PredictFailure -eq $true) {
                $hardwareScore -= 20
                $healthReport.Issues += "CRITICAL: Disk failure predicted"
                break
            }
        }
    }

    Write-Host "  Hardware Health Score: $hardwareScore/100"
    $healthReport.Categories.HardwareHealth = $hardwareScore

    # 7. BOOT PERFORMANCE (Max deduction: 10 points)
    Write-Host "[7/8] Analyzing Boot Performance..."
    $bootScore = 100

    $bootEvents = Get-WinEvent -FilterHashtable @{
        LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
        ID = 100
    } -MaxEvents 1 -ErrorAction SilentlyContinue

    if ($bootEvents -and $bootEvents[0].Properties.Count -gt 0) {
        $bootTimeMs = $bootEvents[0].Properties[0].Value
        $bootTimeSec = [math]::Round($bootTimeMs / 1000, 1)

        if ($bootTimeSec -gt 180) {
            $bootScore -= 10
            $healthReport.Issues += "Very slow boot: $bootTimeSec seconds"
        } elseif ($bootTimeSec -gt 120) {
            $bootScore -= 5
            $healthReport.Issues += "Slow boot: $bootTimeSec seconds"
        }

        Write-Host "  Boot Time: $bootTimeSec sec | Score: $bootScore/100"
    } else {
        Write-Host "  Boot Time: No data | Score: $bootScore/100"
    }
    $healthReport.Categories.BootPerformance = $bootScore

    # 8. SECURITY POSTURE (Max deduction: 10 points)
    Write-Host "[8/8] Analyzing Security Posture..."
    $securityScore = 100

    # Check Windows Defender status
    $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($defender) {
        if (-not $defender.RealTimeProtectionEnabled) {
            $securityScore -= 5
            $healthReport.Issues += "Real-time protection disabled"
        }
        if ($defender.AntivirusSignatureAge -gt 7) {
            $securityScore -= 3
            $healthReport.Issues += "Antivirus signatures outdated: $($defender.AntivirusSignatureAge) days old"
        }
    }

    Write-Host "  Security Score: $securityScore/100"
    $healthReport.Categories.SecurityPosture = $securityScore

    # Calculate final health score (weighted average)
    $finalScore = [Math]::Round((
        ($healthReport.Categories.Uptime * 0.10) +
        ($healthReport.Categories.CrashStability * 0.20) +
        ($healthReport.Categories.ApplicationStability * 0.10) +
        ($healthReport.Categories.ServiceHealth * 0.10) +
        ($healthReport.Categories.SystemErrors * 0.15) +
        ($healthReport.Categories.HardwareHealth * 0.20) +
        ($healthReport.Categories.BootPerformance * 0.05) +
        ($healthReport.Categories.SecurityPosture * 0.10)
    ), 0)

    $healthReport.TotalScore = $finalScore

    # Determine health status
    $healthStatus = if ($finalScore -ge 90) { "EXCELLENT" }
                    elseif ($finalScore -ge 80) { "GOOD" }
                    elseif ($finalScore -ge 70) { "FAIR" }
                    elseif ($finalScore -ge 50) { "POOR" }
                    else { "CRITICAL" }

    Write-Host ""
    Write-Host "==================================="
    Write-Host "OVERALL DEVICE HEALTH SCORE"
    Write-Host "==================================="
    Write-Host "Score: $finalScore / 100"
    Write-Host "Status: $healthStatus"
    Write-Host ""

    if ($healthReport.Issues.Count -gt 0) {
        Write-Host "Issues Detected ($($healthReport.Issues.Count)):"
        foreach ($issue in $healthReport.Issues) {
            Write-Host "  ⚠ $issue"
        }
        Write-Host ""
    }

    # Provide recommendations based on score
    if ($finalScore -lt 90) {
        Write-Host "Recommendations:"

        if ($healthReport.Categories.Uptime -lt 90) {
            Write-Host "  • Schedule regular reboots (weekly recommended)"
        }
        if ($healthReport.Categories.CrashStability -lt 90) {
            Write-Host "  • Investigate crash dumps and update drivers"
        }
        if ($healthReport.Categories.ApplicationStability -lt 90) {
            Write-Host "  • Update or reinstall frequently crashing applications"
        }
        if ($healthReport.Categories.ServiceHealth -lt 90) {
            Write-Host "  • Review service dependencies and configurations"
        }
        if ($healthReport.Categories.SystemErrors -lt 90) {
            Write-Host "  • Run system diagnostics and check event logs"
        }
        if ($healthReport.Categories.HardwareHealth -lt 90) {
            Write-Host "  • URGENT: Run hardware diagnostics, back up data"
        }
        if ($healthReport.Categories.BootPerformance -lt 90) {
            Write-Host "  • Optimize startup programs and check disk health"
        }
        if ($healthReport.Categories.SecurityPosture -lt 90) {
            Write-Host "  • Enable security features and update definitions"
        }
        Write-Host ""
    }

    Write-Host "==================================="
    Write-Host ""

    # Export report data for Intune collection
    $reportJson = $healthReport | ConvertTo-Json -Depth 3
    Write-Host "Health Report JSON (for reporting):"
    Write-Host $reportJson

    if ($finalScore -lt $minHealthScore) {
        Write-Host "`nDevice health below threshold ($finalScore < $minHealthScore)"
        exit 1
    }

    exit 0

} catch {
    Write-Host "Error calculating device health score: $_"
    exit 1
}
