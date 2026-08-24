<#
.SYNOPSIS
    Monitors system performance trends over time and identifies anomalies.

.DESCRIPTION
    This script collects performance metrics over a specified duration and analyzes trends in CPU, memory, disk,
    and network usage. It identifies performance spikes, baseline deviations, and resource bottlenecks.
    Side effects: creates the output directory if missing and writes CSV data files plus an HTML trend report
    under -OutputPath.
    Exit codes: 0 on success; 1 on fatal error or unsafe -OutputPath.

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
    PS C:\> .\Get-PerformanceTrends.ps1 -DurationMinutes 30 -OutputPath "C:\Reports"
    Monitors performance for 30 minutes and saves report.

.EXAMPLE
    PS C:\> .\Get-PerformanceTrends.ps1 -DurationMinutes 120 -MonitorProcesses -SampleInterval 60
    Monitors for 2 hours with 1-minute intervals, including process monitoring.

.NOTES
    File Name   : Get-PerformanceTrends.ps1
    Author      : Server Management Team
    Prerequisite: PowerShell 5.1+
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10080)]
    [int]$DurationMinutes = 60,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3600)]
    [int]$SampleInterval = 30,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = '',

    [Parameter(Mandatory = $false)]
    [switch]$MonitorProcesses,

    [Parameter(Mandatory = $false)]
    [hashtable]$AlertThresholds = @{
        CPU = 90
        Memory = 85
        Disk = 95
    }
)

$ErrorActionPreference = 'Stop'

# PSSA note: Write-Host is mandated here for colorized [+]/[!]/[-]/[*] console status prefixes
# (RELAUNCH-SPEC section 3); PSAvoidUsingWriteHost warnings are accepted by design.

function Main {
    [CmdletBinding()]
    param(
        [int]$DurationMinutes = 0,
        [int]$SampleInterval = 0,
        [string]$OutputPath = '',
        [switch]$MonitorProcesses,
        [hashtable]$AlertThresholds = $null
    )

    try {
        # Normalize unset parameters to their documented defaults
        if ($DurationMinutes -le 0) { $DurationMinutes = 60 }
        if ($SampleInterval -le 0) { $SampleInterval = 30 }
        if (-not $AlertThresholds) { $AlertThresholds = @{ CPU = 90; Memory = 85; Disk = 95 } }
        # Resolve default output location first (MyDocuments is unavailable on non-Windows hosts)
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $documentsDir = [Environment]::GetFolderPath('MyDocuments')
            if ([string]::IsNullOrWhiteSpace($documentsDir)) {
                $documentsDir = (Get-Location).Path
            }
            $OutputPath = Join-Path $documentsDir 'Reports'
        }

        # Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
        if ([string]::IsNullOrWhiteSpace($OutputPath) -or
            $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
            $OutputPath -match '^(\\\\|//)') {
            throw "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
        }
        $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

        Write-Host "`n=== Performance Trend Monitor ===" -ForegroundColor Cyan
        Write-Host "[*] Computer: $env:COMPUTERNAME" -ForegroundColor Cyan
        Write-Host "[*] Duration: $DurationMinutes minutes" -ForegroundColor Cyan
        Write-Host "[*] Sample Interval: $SampleInterval seconds" -ForegroundColor Cyan
        Write-Host "[*] Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan

        # Create output directory
        if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }

        # Initialize data collection
        $performanceData = @()
        $alerts = @()
        $processData = @()

        $totalSamples = [math]::Ceiling(($DurationMinutes * 60) / $SampleInterval)
        $currentSample = 0

        $endTime = (Get-Date).AddMinutes($DurationMinutes)

        Write-Host "[*] Monitoring will run until: $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
        Write-Host "[*] Collecting $totalSamples samples..." -ForegroundColor Cyan
        Write-Host "Press Ctrl+C to stop monitoring early`n" -ForegroundColor Gray

        while ($currentSample -lt $totalSamples -and (Get-Date) -lt $endTime) {
            $currentSample++
            $timestamp = Get-Date
            $timeOfDay = $timestamp.ToString('HH:mm:ss')

            Write-Progress -Activity "Monitoring Performance" `
                -Status "Sample $currentSample of $totalSamples" `
                -PercentComplete (($currentSample / $totalSamples) * 100)

            # Collect CPU usage
            $cpuCounter = (Get-Counter '\Processor(_Total)\% Processor Time' `
                -ErrorAction SilentlyContinue).CounterSamples.CookedValue
            $cpuUsage = [math]::Round($cpuCounter, 2)

            # Collect memory usage
            $computerSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $totalMemory = $computerSystem.TotalVisibleMemorySize
            $freeMemory = $computerSystem.FreePhysicalMemory
            $usedMemory = $totalMemory - $freeMemory
            $memoryUsagePercent = [math]::Round(($usedMemory / $totalMemory) * 100, 2)

            # Collect disk usage
            $diskCounters = Get-Counter '\PhysicalDisk(_Total)\% Disk Time' -ErrorAction SilentlyContinue
            $diskUsage = if ($diskCounters) {
                [math]::Round($diskCounters.CounterSamples.CookedValue, 2)
            }
            else { 0 }

            # Collect network usage
            $networkUsage = 0
            $networkCounters = Get-Counter '\Network Interface(*)\Bytes Total/sec' -ErrorAction SilentlyContinue
            if ($networkCounters) {
                $networkBytesPerSec = ($networkCounters.CounterSamples | Measure-Object -Property CookedValue -Sum).Sum
                $networkUsage = [math]::Round($networkBytesPerSec / 1MB, 2)  # Convert to MB/s
            }

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
                Write-Host "[$timeOfDay] [!] CPU Alert: $cpuUsage%" -ForegroundColor Yellow
            }

            if ($memoryUsagePercent -gt $AlertThresholds.Memory) {
                $alerts += [PSCustomObject]@{
                    Timestamp = $timestamp
                    Type = "Memory"
                    Value = $memoryUsagePercent
                    Threshold = $AlertThresholds.Memory
                    Message = "Memory usage exceeded threshold: $memoryUsagePercent% > $($AlertThresholds.Memory)%"
                }
                Write-Host "[$timeOfDay] [!] Memory Alert: $memoryUsagePercent%" -ForegroundColor Yellow
            }

            if ($diskUsage -gt $AlertThresholds.Disk) {
                $alerts += [PSCustomObject]@{
                    Timestamp = $timestamp
                    Type = "Disk"
                    Value = $diskUsage
                    Threshold = $AlertThresholds.Disk
                    Message = "Disk usage exceeded threshold: $diskUsage% > $($AlertThresholds.Disk)%"
                }
                Write-Host "[$timeOfDay] [!] Disk Alert: $diskUsage%" -ForegroundColor Yellow
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
            $sampleForeground = if ($cpuUsage -gt 80 -or $memoryUsagePercent -gt 80) { 'Yellow' } else { 'Green' }
            $sampleMsg = "[$timeOfDay] [*] CPU: $cpuUsage% | Memory: $memoryUsagePercent% | " +
                "Disk: $diskUsage% | Network: $networkUsage MB/s"
            Write-Host $sampleMsg -ForegroundColor $sampleForeground

            # Wait for next sample
            Start-Sleep -Seconds $SampleInterval
        }

        Write-Progress -Activity "Monitoring Performance" -Completed

        Write-Host "[+] Monitoring complete. Analyzing data..." -ForegroundColor Green

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

        if ($alerts.Count -gt 0) {
            Write-Host "[!] Alerts Triggered: $($alerts.Count)" -ForegroundColor Yellow
        }
        else {
            Write-Host "[+] Alerts Triggered: 0" -ForegroundColor Green
        }

        # Export data
        Write-Host "[*] Exporting data..." -ForegroundColor Cyan

        $csvPath = Join-Path -Path $OutputPath -ChildPath "PerformanceData_${RunTimestamp}_${RunId}.csv"
        $performanceData | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
        Write-Host "[+] Performance data exported to: $csvPath" -ForegroundColor Green

        if ($alerts.Count -gt 0) {
            $alertsPath = Join-Path -Path $OutputPath -ChildPath "Alerts_${RunTimestamp}_${RunId}.csv"
            $alerts | Export-Csv -Path $alertsPath -NoTypeInformation -ErrorAction Stop
            Write-Host "[+] Alerts exported to: $alertsPath" -ForegroundColor Green
        }

        if ($MonitorProcesses -and $processData.Count -gt 0) {
            $processPath = Join-Path -Path $OutputPath -ChildPath "ProcessData_${RunTimestamp}_${RunId}.csv"
            $processData | Export-Csv -Path $processPath -NoTypeInformation -ErrorAction Stop
            Write-Host "[+] Process data exported to: $processPath" -ForegroundColor Green
        }

        # Generate HTML report
        Write-Host "[*] Generating HTML report..." -ForegroundColor Cyan
        $htmlPath = Join-Path -Path $OutputPath -ChildPath "PerformanceTrendReport_${RunTimestamp}_${RunId}.html"

        $alertsHtml = ""
        if ($alerts.Count -gt 0) {
            $alertsHtml = "<h2>Alerts ($($alerts.Count))</h2><table>" +
                "<tr><th>Time</th><th>Type</th><th>Value</th><th>Threshold</th></tr>"
            foreach ($alert in $alerts) {
                $alertTimeEncoded = [System.Net.WebUtility]::HtmlEncode("$($alert.Timestamp.ToString('HH:mm:ss'))")
                $alertTypeEncoded = [System.Net.WebUtility]::HtmlEncode("$($alert.Type)")
                $alertsHtml += "<tr class='warning'><td>$alertTimeEncoded</td><td>$alertTypeEncoded</td>" +
                    "<td>$($alert.Value)%</td><td>$($alert.Threshold)%</td></tr>"
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
        table {
            border-collapse: collapse; width: 100%; background-color: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin: 20px 0;
        }
        th { background-color: #0066cc; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f0f0f0; }
        .warning { background-color: #fff3cd; }
        .info { background-color: #e6f3ff; padding: 15px; border-left: 4px solid #0066cc; margin: 20px 0; }
        .stat-box {
            display: inline-block; background-color: white; padding: 20px; margin: 10px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); min-width: 200px;
        }
        .stat-value { font-size: 32px; font-weight: bold; color: #0066cc; }
        .stat-label { font-size: 14px; color: #666; }
    </style>
</head>
<body>
    <h1>Performance Trend Report</h1>
    <div class="info">
        <strong>Computer:</strong> $([System.Net.WebUtility]::HtmlEncode("$env:COMPUTERNAME"))<br>
        <strong>Monitoring Duration:</strong> $DurationMinutes minutes<br>
        <strong>Samples Collected:</strong> $currentSample<br>
        <strong>Report Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | <strong>Run ID:</strong> $RunId
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
        $avgCpuPct = [math]::Round($cpuStats.Average, 1)
        $avgMemPct = [math]::Round($memStats.Average, 1)
        $avgDiskPct = [math]::Round($diskStats.Average, 1)

        if ($cpuStats.Average -gt 70) {
            $html += "<li><strong>High CPU Usage:</strong> Average CPU usage is $($avgCpuPct)%. " +
                "Investigate CPU-intensive processes and consider optimization.</li>"
        }

        if ($memStats.Average -gt 80) {
            $html += "<li><strong>High Memory Usage:</strong> Average memory usage is $($avgMemPct)%. " +
                "Consider adding more RAM or optimizing memory-intensive applications.</li>"
        }

        if ($diskStats.Average -gt 70) {
            $html += "<li><strong>High Disk Usage:</strong> Average disk usage is $($avgDiskPct)%. " +
                "Check for disk bottlenecks and consider faster storage.</li>"
        }

        if ($alerts.Count -gt 10) {
            $html += "<li><strong>Frequent Alerts:</strong> $($alerts.Count) performance threshold violations " +
                "detected. Review alert details for patterns.</li>"
        }

        if ($cpuStats.Average -lt 50 -and $memStats.Average -lt 50 -and $diskStats.Average -lt 50) {
            $html += "<li><strong>Healthy Performance:</strong> System performance is within normal ranges. " +
                "No immediate action required.</li>"
        }

        $html += @"
    </ul>

    <h2>Data Files</h2>
    <ul>
        <li><a href="PerformanceData_${RunTimestamp}_${RunId}.csv">Performance Data (CSV)</a></li>
"@

        if ($alerts.Count -gt 0) {
            $html += "<li><a href='Alerts_${RunTimestamp}_${RunId}.csv'>Alert Log (CSV)</a></li>"
        }

        if ($MonitorProcesses) {
            $html += "<li><a href='ProcessData_${RunTimestamp}_${RunId}.csv'>Process Data (CSV)</a></li>"
        }

        $html += @"
    </ul>
</body>
</html>
"@

        $html | Out-File -FilePath $htmlPath -Encoding UTF8 -ErrorAction Stop
        Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
        Write-Host "[+] End Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green

        return 0
    }
    catch {
        Write-Host "[-] Error during performance monitoring: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
