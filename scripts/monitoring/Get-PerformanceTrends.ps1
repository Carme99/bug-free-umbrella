<#
.SYNOPSIS
    Monitors system performance trends over time and identifies anomalies.

.DESCRIPTION
    This script collects performance metrics over a specified duration and analyzes
    trends in CPU, memory, disk, and network usage. Identifies performance spikes,
    baseline deviations, and resource bottlenecks.

.PARAMETER DurationMinutes
    How long to monitor performance (in minutes). Default is 60 minutes.

.PARAMETER SampleInterval
    Interval between samples in seconds. Default is 30 seconds.

.PARAMETER OutputPath
    Path where performance data and reports will be saved.

.PARAMETER MonitorProcesses
    Switch to monitor top resource-consuming processes.

.PARAMETER AlertThresholds
    Hashtable of alert thresholds (CPU=90, Memory=85, Disk=95).

.EXAMPLE
    .\Get-PerformanceTrends.ps1 -DurationMinutes 30 -OutputPath "C:\Reports"
    Monitors performance for 30 minutes and saves report.

.EXAMPLE
    .\Get-PerformanceTrends.ps1 -DurationMinutes 120 -MonitorProcesses -SampleInterval 60
    Monitors for 2 hours with 1-minute intervals, including process monitoring.

.NOTES
    Author: Server Management Team
    Requires: Administrator privileges for full metrics
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$DurationMinutes = 60,

    [Parameter(Mandatory = $false)]
    [int]$SampleInterval = 30,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "$env:TEMP\PerformanceTrends_$(Get-Date -Format 'yyyyMMdd_HHmmss')",

    [Parameter(Mandatory = $false)]
    [switch]$MonitorProcesses,

    [Parameter(Mandatory = $false)]
    [hashtable]$AlertThresholds = @{
        CPU = 90
        Memory = 85
        Disk = 95
    }
)

Write-Host "`n=== Performance Trend Monitor ===" -ForegroundColor Cyan
Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "Duration: $DurationMinutes minutes" -ForegroundColor Cyan
Write-Host "Sample Interval: $SampleInterval seconds" -ForegroundColor Cyan
Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# Create output directory
if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# Initialize data collection
$performanceData = @()
$alerts = @()
$processData = @()

$totalSamples = ($DurationMinutes * 60) / $SampleInterval
$currentSample = 0

$endTime = (Get-Date).AddMinutes($DurationMinutes)

Write-Host "`nMonitoring will run until: $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Yellow
Write-Host "Collecting $totalSamples samples..." -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop monitoring early`n" -ForegroundColor Gray

try {
    while ((Get-Date) -lt $endTime) {
        $currentSample++
        $timestamp = Get-Date

        Write-Progress -Activity "Monitoring Performance" `
            -Status "Sample $currentSample of $totalSamples" `
            -PercentComplete (($currentSample / $totalSamples) * 100)

        # Collect CPU usage
        $cpuCounter = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
        $cpuUsage = [math]::Round($cpuCounter, 2)

        # Collect memory usage
        $computerSystem = Get-CimInstance Win32_OperatingSystem
        $totalMemory = $computerSystem.TotalVisibleMemorySize
        $freeMemory = $computerSystem.FreePhysicalMemory
        $usedMemory = $totalMemory - $freeMemory
        $memoryUsagePercent = [math]::Round(($usedMemory / $totalMemory) * 100, 2)

        # Collect disk usage
        $diskCounters = Get-Counter '\PhysicalDisk(_Total)\% Disk Time' -ErrorAction SilentlyContinue
        $diskUsage = if ($diskCounters) {
            [math]::Round($diskCounters.CounterSamples.CookedValue, 2)
        } else { 0 }

        # Collect network usage
        $networkCounters = Get-Counter '\Network Interface(*)\Bytes Total/sec' -ErrorAction SilentlyContinue
        $networkUsage = if ($networkCounters) {
            ($networkCounters.CounterSamples | Measure-Object -Property CookedValue -Sum).Sum
            [math]::Round($networkUsage / 1MB, 2)  # Convert to MB/s
        } else { 0 }

        # Create performance record
        $record = [PSCustomObject]@{
            Timestamp = $timestamp
            CPU = $cpuUsage
            MemoryPercent = $memoryUsagePercent
            MemoryUsedGB = [math]::Round($usedMemory / 1MB, 2)
            DiskPercent = $diskUsage
            NetworkMBps = $networkUsage
        }

        $performanceData += $record

        # Check for alerts
        if ($cpuUsage -gt $AlertThresholds.CPU) {
            $alerts += [PSCustomObject]@{
                Timestamp = $timestamp
                Type = "CPU"
                Value = $cpuUsage
                Threshold = $AlertThresholds.CPU
                Message = "CPU usage exceeded threshold: $cpuUsage% > $($AlertThresholds.CPU)%"
            }
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ⚠ CPU Alert: $cpuUsage%" -ForegroundColor Red
        }

        if ($memoryUsagePercent -gt $AlertThresholds.Memory) {
            $alerts += [PSCustomObject]@{
                Timestamp = $timestamp
                Type = "Memory"
                Value = $memoryUsagePercent
                Threshold = $AlertThresholds.Memory
                Message = "Memory usage exceeded threshold: $memoryUsagePercent% > $($AlertThresholds.Memory)%"
            }
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ⚠ Memory Alert: $memoryUsagePercent%" -ForegroundColor Red
        }

        if ($diskUsage -gt $AlertThresholds.Disk) {
            $alerts += [PSCustomObject]@{
                Timestamp = $timestamp
                Type = "Disk"
                Value = $diskUsage
                Threshold = $AlertThresholds.Disk
                Message = "Disk usage exceeded threshold: $diskUsage% > $($AlertThresholds.Disk)%"
            }
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ⚠ Disk Alert: $diskUsage%" -ForegroundColor Red
        }

        # Monitor top processes if requested
        if ($MonitorProcesses) {
            $topProcesses = Get-Process | Sort-Object -Property CPU -Descending | Select-Object -First 5

            foreach ($proc in $topProcesses) {
                $processData += [PSCustomObject]@{
                    Timestamp = $timestamp
                    ProcessName = $proc.ProcessName
                    ProcessId = $proc.Id
                    CPU = [math]::Round($proc.CPU, 2)
                    MemoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
                }
            }
        }

        # Display current metrics
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] CPU: $cpuUsage% | Memory: $memoryUsagePercent% | Disk: $diskUsage% | Network: $networkUsage MB/s" -ForegroundColor $(if ($cpuUsage -gt 80 -or $memoryUsagePercent -gt 80) { 'Yellow' } else { 'Green' })

        # Wait for next sample
        Start-Sleep -Seconds $SampleInterval
    }

    Write-Progress -Activity "Monitoring Performance" -Completed

    Write-Host "`nMonitoring complete. Analyzing data..." -ForegroundColor Yellow

    # Calculate statistics
    $cpuStats = $performanceData | Measure-Object -Property CPU -Average -Maximum -Minimum
    $memStats = $performanceData | Measure-Object -Property MemoryPercent -Average -Maximum -Minimum
    $diskStats = $performanceData | Measure-Object -Property DiskPercent -Average -Maximum -Minimum

    # Display summary
    Write-Host "`n=== Performance Summary ===" -ForegroundColor Cyan
    Write-Host "CPU:" -ForegroundColor White
    Write-Host "  Average: $([math]::Round($cpuStats.Average, 2))%" -ForegroundColor Cyan
    Write-Host "  Maximum: $([math]::Round($cpuStats.Maximum, 2))%" -ForegroundColor Cyan
    Write-Host "  Minimum: $([math]::Round($cpuStats.Minimum, 2))%" -ForegroundColor Cyan

    Write-Host "`nMemory:" -ForegroundColor White
    Write-Host "  Average: $([math]::Round($memStats.Average, 2))%" -ForegroundColor Cyan
    Write-Host "  Maximum: $([math]::Round($memStats.Maximum, 2))%" -ForegroundColor Cyan
    Write-Host "  Minimum: $([math]::Round($memStats.Minimum, 2))%" -ForegroundColor Cyan

    Write-Host "`nDisk:" -ForegroundColor White
    Write-Host "  Average: $([math]::Round($diskStats.Average, 2))%" -ForegroundColor Cyan
    Write-Host "  Maximum: $([math]::Round($diskStats.Maximum, 2))%" -ForegroundColor Cyan
    Write-Host "  Minimum: $([math]::Round($diskStats.Minimum, 2))%" -ForegroundColor Cyan

    Write-Host "`nAlerts Triggered: $($alerts.Count)" -ForegroundColor $(if ($alerts.Count -gt 0) { 'Red' } else { 'Green' })

    # Export data
    Write-Host "`nExporting data..." -ForegroundColor Yellow

    $csvPath = Join-Path -Path $OutputPath -ChildPath "PerformanceData.csv"
    $performanceData | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "Performance data exported to: $csvPath" -ForegroundColor Green

    if ($alerts.Count -gt 0) {
        $alertsPath = Join-Path -Path $OutputPath -ChildPath "Alerts.csv"
        $alerts | Export-Csv -Path $alertsPath -NoTypeInformation
        Write-Host "Alerts exported to: $alertsPath" -ForegroundColor Green
    }

    if ($MonitorProcesses -and $processData.Count -gt 0) {
        $processPath = Join-Path -Path $OutputPath -ChildPath "ProcessData.csv"
        $processData | Export-Csv -Path $processPath -NoTypeInformation
        Write-Host "Process data exported to: $processPath" -ForegroundColor Green
    }

    # Generate HTML report
    Write-Host "`nGenerating HTML report..." -ForegroundColor Yellow
    $htmlPath = Join-Path -Path $OutputPath -ChildPath "PerformanceTrendReport.html"

    $alertsHtml = ""
    if ($alerts.Count -gt 0) {
        $alertsHtml = "<h2>Alerts ($($alerts.Count))</h2><table><tr><th>Time</th><th>Type</th><th>Value</th><th>Threshold</th></tr>"
        foreach ($alert in $alerts) {
            $alertsHtml += "<tr class='warning'><td>$($alert.Timestamp.ToString('HH:mm:ss'))</td><td>$($alert.Type)</td><td>$($alert.Value)%</td><td>$($alert.Threshold)%</td></tr>"
        }
        $alertsHtml += "</table>"
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Performance Trend Report - $env:COMPUTERNAME</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0066cc; }
        h2 { color: #0099cc; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin: 20px 0; }
        th { background-color: #0066cc; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f0f0f0; }
        .warning { background-color: #fff3cd; }
        .info { background-color: #e6f3ff; padding: 15px; border-left: 4px solid #0066cc; margin: 20px 0; }
        .stat-box { display: inline-block; background-color: white; padding: 20px; margin: 10px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); min-width: 200px; }
        .stat-value { font-size: 32px; font-weight: bold; color: #0066cc; }
        .stat-label { font-size: 14px; color: #666; }
    </style>
</head>
<body>
    <h1>Performance Trend Report</h1>
    <div class="info">
        <strong>Computer:</strong> $env:COMPUTERNAME<br>
        <strong>Monitoring Duration:</strong> $DurationMinutes minutes<br>
        <strong>Samples Collected:</strong> $currentSample<br>
        <strong>Report Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    </div>

    <h2>Performance Statistics</h2>

    <div class="stat-box">
        <div class="stat-label">Average CPU</div>
        <div class="stat-value">$([math]::Round($cpuStats.Average, 1))%</div>
    </div>

    <div class="stat-box">
        <div class="stat-label">Max CPU</div>
        <div class="stat-value">$([math]::Round($cpuStats.Maximum, 1))%</div>
    </div>

    <div class="stat-box">
        <div class="stat-label">Average Memory</div>
        <div class="stat-value">$([math]::Round($memStats.Average, 1))%</div>
    </div>

    <div class="stat-box">
        <div class="stat-label">Max Memory</div>
        <div class="stat-value">$([math]::Round($memStats.Maximum, 1))%</div>
    </div>

    <h2>Detailed Metrics</h2>
    <table>
        <tr>
            <th>Metric</th>
            <th>Average</th>
            <th>Maximum</th>
            <th>Minimum</th>
        </tr>
        <tr>
            <td><strong>CPU Usage</strong></td>
            <td>$([math]::Round($cpuStats.Average, 2))%</td>
            <td>$([math]::Round($cpuStats.Maximum, 2))%</td>
            <td>$([math]::Round($cpuStats.Minimum, 2))%</td>
        </tr>
        <tr>
            <td><strong>Memory Usage</strong></td>
            <td>$([math]::Round($memStats.Average, 2))%</td>
            <td>$([math]::Round($memStats.Maximum, 2))%</td>
            <td>$([math]::Round($memStats.Minimum, 2))%</td>
        </tr>
        <tr>
            <td><strong>Disk Usage</strong></td>
            <td>$([math]::Round($diskStats.Average, 2))%</td>
            <td>$([math]::Round($diskStats.Maximum, 2))%</td>
            <td>$([math]::Round($diskStats.Minimum, 2))%</td>
        </tr>
    </table>

    $alertsHtml

    <h2>Recommendations</h2>
    <ul>
"@

    # Add recommendations based on findings
    if ($cpuStats.Average -gt 70) {
        $html += "<li><strong>High CPU Usage:</strong> Average CPU usage is $([math]::Round($cpuStats.Average, 1))%. Investigate CPU-intensive processes and consider optimization.</li>"
    }

    if ($memStats.Average -gt 80) {
        $html += "<li><strong>High Memory Usage:</strong> Average memory usage is $([math]::Round($memStats.Average, 1))%. Consider adding more RAM or optimizing memory-intensive applications.</li>"
    }

    if ($diskStats.Average -gt 70) {
        $html += "<li><strong>High Disk Usage:</strong> Average disk usage is $([math]::Round($diskStats.Average, 1))%. Check for disk bottlenecks and consider faster storage.</li>"
    }

    if ($alerts.Count -gt 10) {
        $html += "<li><strong>Frequent Alerts:</strong> $($alerts.Count) performance threshold violations detected. Review alert details for patterns.</li>"
    }

    if ($cpuStats.Average -lt 50 -and $memStats.Average -lt 50 -and $diskStats.Average -lt 50) {
        $html += "<li><strong>Healthy Performance:</strong> System performance is within normal ranges. No immediate action required.</li>"
    }

    $html += @"
    </ul>

    <h2>Data Files</h2>
    <ul>
        <li><a href="PerformanceData.csv">Performance Data (CSV)</a></li>
"@

    if ($alerts.Count -gt 0) {
        $html += "<li><a href='Alerts.csv'>Alert Log (CSV)</a></li>"
    }

    if ($MonitorProcesses) {
        $html += "<li><a href='ProcessData.csv'>Process Data (CSV)</a></li>"
    }

    $html += @"
    </ul>
</body>
</html>
"@

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "HTML report saved to: $htmlPath" -ForegroundColor Green

    # Open report
    Start-Process $htmlPath

}
catch {
    Write-Error "Error during performance monitoring: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}

Write-Host "`nEnd Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
