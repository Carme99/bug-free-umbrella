<#
.SYNOPSIS
    Generates comprehensive performance metrics and bottleneck analysis for Windows Server.

.DESCRIPTION
    This script collects and analyzes historical performance data:
    - CPU usage trends and peak times
    - Memory consumption patterns
    - Disk I/O performance (IOPS, latency, queue length)
    - Network bandwidth utilization
    - Top resource-consuming processes
    - Performance counter analysis
    - Bottleneck identification
    - Export to HTML with graphs

.PARAMETER DurationMinutes
    How long to collect performance data in minutes (default: 5).

.PARAMETER SampleInterval
    Interval between samples in seconds (default: 5).

.PARAMETER IncludeDiskIO
    Include detailed disk I/O analysis.

.PARAMETER IncludeNetworkStats
    Include detailed network statistics.

.PARAMETER ExportHTML
    Export detailed report to HTML file.

.PARAMETER ExportCSV
    Export raw performance data to CSV.

.EXAMPLE
    PS C:\> .\Get-PerformanceReport.ps1
    Collects 5 minutes of performance data with 5-second intervals.

.EXAMPLE
    PS C:\> .\Get-PerformanceReport.ps1 -DurationMinutes 10 -SampleInterval 2 -ExportHTML
    Collects 10 minutes of data with 2-second sampling and exports HTML report.

.EXAMPLE
    PS C:\> .\Get-PerformanceReport.ps1 -IncludeDiskIO -IncludeNetworkStats -ExportHTML
    Performs comprehensive analysis including disk I/O and network stats.

.NOTES
    File Name     : Get-PerformanceReport.ps1
    Author        : Bug-Free Umbrella
    Prerequisite  : PowerShell 5.1+
    Version       : 1.0.0
    Date          : 2026-08-23

    Administrator privileges are required for full performance counter access; the elevation
    check runs inside Main (not via #Requires) so the script can be safely loaded for testing.
    Compatible with Windows Server 2016, 2019, and 2022. Longer durations provide more
    accurate trend analysis.
#>

[CmdletBinding()]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
            Justification = 'Colored Write-Host prefix output is the specified console UX.')]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
            Justification = 'Parameters are consumed by helper functions via dynamic scoping.')]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
            Justification = 'Plural nouns are intentional: functions aggregate collections.')]
param(
    [Parameter(Mandatory = $false)]
    [int]$DurationMinutes = 5,

    [Parameter(Mandatory = $false)]
    [int]$SampleInterval = 5,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDiskIO,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeNetworkStats,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
)
$ErrorActionPreference = 'Stop'

function Test-AdminPrivilege {
    # Runtime replacement for the former '#Requires -RunAsAdministrator' directive.
    # Unix platforms (offline test runners) have no elevation concept, so the check
    # passes through there; Windows hosts still require an elevated session.
    if ($PSVersionTable.ContainsKey('Platform') -and $PSVersionTable.Platform -eq 'Unix') {
        return $true
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}


function Write-ColorOutput {
    param([string]$Message, [string]$Level = 'Info')

    # Mandated console prefixes: [-] error/critical, [!] warning, [+] success, [*] info.
    $prefix = switch ($Level) {
        'Critical' { '[-]' }
        'Error' { '[-]' }
        'Warning' { '[!]' }
        'Success' { '[+]' }
        default { '[*]' }
    }

    $color = switch ($Level) {
        'Critical' { 'Red' }
        'Error' { 'Red' }
        'Warning' { 'Yellow' }
        'Success' { 'Green' }
        default { 'Cyan' }
    }

    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Read-PerformanceSamples {
    $sampleCount = ($DurationMinutes * 60) / $SampleInterval
    $script:report.TotalSamples = $sampleCount

    Write-Host "`nCollecting performance data..." -ForegroundColor Cyan
    Write-Host "  Duration: $DurationMinutes minutes"
    Write-Host "  Sample Interval: $SampleInterval seconds"
    Write-Host "  Total Samples: $sampleCount"
    Write-Host "`nProgress:" -ForegroundColor Cyan

    # Performance counters to collect
    $counters = @(
        '\Processor(_Total)\% Processor Time',
        '\Memory\Available MBytes',
        '\Memory\% Committed Bytes In Use'
    )

    if ($IncludeDiskIO) {
        $counters += '\PhysicalDisk(_Total)\Disk Reads/sec'
        $counters += '\PhysicalDisk(_Total)\Disk Writes/sec'
        $counters += '\PhysicalDisk(_Total)\Avg. Disk sec/Read'
        $counters += '\PhysicalDisk(_Total)\Avg. Disk sec/Write'
        $counters += '\PhysicalDisk(_Total)\Current Disk Queue Length'
    }

    if ($IncludeNetworkStats) {
        $counters += '\Network Interface(*)\Bytes Total/sec'
    }

    # Get total memory for calculations
    $os = Get-CimInstance Win32_OperatingSystem
    $totalMemoryMB = [math]::Round($os.TotalVisibleMemorySize / 1KB, 2)
    $script:report.Memory.TotalGB = [math]::Round($totalMemoryMB / 1024, 2)

    # Collect samples
    for ($i = 1; $i -le $sampleCount; $i++) {
        $percentComplete = [math]::Round(($i / $sampleCount) * 100, 0)
        Write-Progress -Activity "Collecting Performance Data" -Status "$percentComplete% Complete" `
            -PercentComplete $percentComplete

        try {
            $sample = Get-Counter -Counter $counters -ErrorAction Stop

            # CPU
            $cpuSample = $sample.CounterSamples | Where-Object { $_.Path -like '*Processor(_Total)*' }
            $cpuValue = [math]::Round($cpuSample.CookedValue, 2)
            $script:report.CPU.Samples += $cpuValue

            # Memory
            $availableMemMB = ($sample.CounterSamples |
                Where-Object { $_.Path -like '*Available MBytes*' }).CookedValue
            $usedMemoryMB = $totalMemoryMB - $availableMemMB
            $usedMemoryGB = [math]::Round($usedMemoryMB / 1024, 2)
            $usedMemoryPercent = [math]::Round(($usedMemoryMB / $totalMemoryMB) * 100, 2)

            $script:report.Memory.Samples += @{
                UsedGB = $usedMemoryGB
                UsedPercent = $usedMemoryPercent
                Timestamp = Get-Date
            }

            # Disk I/O (if enabled)
            if ($IncludeDiskIO) {
                $diskReads = ($sample.CounterSamples |
                    Where-Object { $_.Path -like '*Disk Reads/sec*' }).CookedValue
                $diskWrites = ($sample.CounterSamples |
                    Where-Object { $_.Path -like '*Disk Writes/sec*' }).CookedValue
                $diskReadLatency = ($sample.CounterSamples |
                    Where-Object { $_.Path -like '*Avg. Disk sec/Read*' }).CookedValue
                $diskWriteLatency = ($sample.CounterSamples |
                    Where-Object { $_.Path -like '*Avg. Disk sec/Write*' }).CookedValue
                $diskQueue = ($sample.CounterSamples |
                    Where-Object { $_.Path -like '*Current Disk Queue*' }).CookedValue

                $script:report.DiskIO += @{
                    Timestamp = Get-Date
                    ReadsPerSec = [math]::Round($diskReads, 2)
                    WritesPerSec = [math]::Round($diskWrites, 2)
                    ReadLatencyMs = [math]::Round($diskReadLatency * 1000, 2)
                    WriteLatencyMs = [math]::Round($diskWriteLatency * 1000, 2)
                    QueueLength = [math]::Round($diskQueue, 2)
                }
            }

            # Network (if enabled)
            if ($IncludeNetworkStats) {
                $networkSamples = $sample.CounterSamples |
                    Where-Object { $_.Path -like '*Network Interface*Bytes Total*' }
                foreach ($netSample in $networkSamples) {
                    $adapterName = $netSample.InstanceName
                    $bytesPerSec = $netSample.CookedValue

                    $existing = $script:report.Network | Where-Object { $_.AdapterName -eq $adapterName }
                    if (-not $existing) {
                        $script:report.Network += @{
                            AdapterName = $adapterName
                            Samples = @()
                        }
                        $existing = $script:report.Network | Where-Object { $_.AdapterName -eq $adapterName }
                    }

                    $existing.Samples += @{
                        Timestamp = Get-Date
                        BytesPerSec = $bytesPerSec
                        MbitsPerSec = [math]::Round(($bytesPerSec * 8) / 1MB, 2)
                    }
                }
            }
        }
        catch {
            Write-Warning "Error collecting sample $i : $($_.Exception.Message)"
        }

        if ($i -lt $sampleCount) {
            Start-Sleep -Seconds $SampleInterval
        }
    }

    Write-Progress -Activity "Collecting Performance Data" -Completed
    $script:report.EndTime = Get-Date
}

function Measure-PerformanceStats {
    Write-Host "`nAnalyzing performance data..." -ForegroundColor Cyan

    # CPU Analysis
    if ($script:report.CPU.Samples.Count -gt 0) {
        $cpuStats = $script:report.CPU.Samples | Measure-Object -Average -Minimum -Maximum
        $script:report.CPU.Average = [math]::Round($cpuStats.Average, 2)
        $script:report.CPU.Min = [math]::Round($cpuStats.Minimum, 2)
        $script:report.CPU.Max = [math]::Round($cpuStats.Maximum, 2)

        # Calculate 95th percentile
        $sortedCPU = $script:report.CPU.Samples | Sort-Object
        $p95Index = [math]::Floor($sortedCPU.Count * 0.95)
        $script:report.CPU.Peak95Percentile = [math]::Round($sortedCPU[$p95Index], 2)

        Write-Host ("  CPU: Avg={0}%, Min={1}%, Max={2}%, 95th=%{3}%" -f `
            $script:report.CPU.Average, $script:report.CPU.Min, $script:report.CPU.Max, `
            $script:report.CPU.Peak95Percentile)

        # CPU Bottleneck detection
        if ($script:report.CPU.Average -gt 80) {
            $script:report.Bottlenecks += "High average CPU utilization ($($script:report.CPU.Average)%)"
        }
        if ($script:report.CPU.Peak95Percentile -gt 90) {
            $script:report.Bottlenecks +=
                "CPU spikes detected (95th percentile: $($script:report.CPU.Peak95Percentile)%)"
        }
    }

    # Memory Analysis
    if ($script:report.Memory.Samples.Count -gt 0) {
        $avgUsedGB = ($script:report.Memory.Samples |
            ForEach-Object { $_.UsedGB } | Measure-Object -Average).Average
        $avgUsedPercent = ($script:report.Memory.Samples |
            ForEach-Object { $_.UsedPercent } | Measure-Object -Average).Average
        $peakSample = $script:report.Memory.Samples |
            Sort-Object { $_.UsedPercent } -Descending | Select-Object -First 1

        $script:report.Memory.AverageUsedGB = [math]::Round($avgUsedGB, 2)
        $script:report.Memory.AverageUsedPercent = [math]::Round($avgUsedPercent, 2)
        $script:report.Memory.PeakUsedGB = $peakSample.UsedGB
        $script:report.Memory.PeakUsedPercent = $peakSample.UsedPercent

        Write-Host ("  Memory: Avg={0}%, Peak={1}%" -f `
            $script:report.Memory.AverageUsedPercent, $script:report.Memory.PeakUsedPercent)

        # Memory bottleneck detection
        if ($script:report.Memory.AverageUsedPercent -gt 85) {
            $script:report.Bottlenecks +=
                "High memory utilization ($($script:report.Memory.AverageUsedPercent)%)"
        }
    }

    # Disk I/O Analysis
    if ($script:report.DiskIO.Count -gt 0) {
        $avgReads = ($script:report.DiskIO |
            ForEach-Object { $_.ReadsPerSec } | Measure-Object -Average).Average
        $avgWrites = ($script:report.DiskIO |
            ForEach-Object { $_.WritesPerSec } | Measure-Object -Average).Average
        $avgReadLatency = ($script:report.DiskIO |
            ForEach-Object { $_.ReadLatencyMs } | Measure-Object -Average).Average
        $avgWriteLatency = ($script:report.DiskIO |
            ForEach-Object { $_.WriteLatencyMs } | Measure-Object -Average).Average
        $avgQueue = ($script:report.DiskIO |
            ForEach-Object { $_.QueueLength } | Measure-Object -Average).Average

        Write-Host "  Disk I/O: Reads=$([math]::Round($avgReads, 2))/s, Writes=$([math]::Round($avgWrites, 2))/s"
        Write-Host ("  Disk Latency: Read={0}ms, Write={1}ms" -f `
            [math]::Round($avgReadLatency, 2), [math]::Round($avgWriteLatency, 2))
        Write-Host "  Disk Queue: Avg=$([math]::Round($avgQueue, 2))"

        # Disk bottleneck detection
        if ($avgReadLatency -gt 25 -or $avgWriteLatency -gt 25) {
            $script:report.Bottlenecks += ("High disk latency detected " +
                "(Read: $([math]::Round($avgReadLatency, 2))ms, Write: $([math]::Round($avgWriteLatency, 2))ms)")
        }
        if ($avgQueue -gt 2) {
            $script:report.Bottlenecks += "High disk queue length ($([math]::Round($avgQueue, 2)))"
        }
    }

    # Network Analysis
    if ($script:report.Network.Count -gt 0) {
        Write-Host "  Network Adapters:"
        foreach ($adapter in $script:report.Network) {
            if ($adapter.Samples.Count -gt 0) {
                $avgMbps = ($adapter.Samples |
                    ForEach-Object { $_.MbitsPerSec } | Measure-Object -Average).Average
                $peakMbps = ($adapter.Samples |
                    ForEach-Object { $_.MbitsPerSec } | Measure-Object -Maximum).Maximum
                Write-Host ("    {0}: Avg={1} Mbps, Peak={2} Mbps" -f $adapter.AdapterName, `
                    [math]::Round($avgMbps, 2), [math]::Round($peakMbps, 2))
            }
        }
    }
}

function Get-TopProcesses {
    Write-Host "`nIdentifying top resource consumers..." -ForegroundColor Cyan

    # Top CPU processes
    $script:report.TopProcesses.ByCPU = Get-Process |
        Sort-Object CPU -Descending |
        Select-Object -First 10 ProcessName, Id,
        @{Name = 'CPU(s)'; Expression = { [math]::Round($_.CPU, 2) } },
        @{Name = 'MemoryMB'; Expression = { [math]::Round($_.WorkingSet64 / 1MB, 2) } },
        @{Name = 'Threads'; Expression = { $_.Threads.Count } }

    # Top Memory processes
    $script:report.TopProcesses.ByMemory = Get-Process |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 10 ProcessName, Id,
        @{Name = 'MemoryMB'; Expression = { [math]::Round($_.WorkingSet64 / 1MB, 2) } },
        @{Name = 'CPU(s)'; Expression = { [math]::Round($_.CPU, 2) } }

    Write-Host "  Captured top 10 processes by CPU and Memory"
}

function Show-Summary {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Performance Analysis Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Server: $($script:report.ServerName)"
    Write-Host "Analysis Period: $($script:report.StartTime) to $($script:report.EndTime)"
    Write-Host "Duration: $($script:report.Duration)"
    Write-Host "Samples Collected: $($script:report.TotalSamples)"

    Write-Host "`nCPU Performance:" -ForegroundColor Cyan
    Write-Host "  Average: $($script:report.CPU.Average)%"
    Write-Host "  Min/Max: $($script:report.CPU.Min)% / $($script:report.CPU.Max)%"
    Write-Host "  95th Percentile: $($script:report.CPU.Peak95Percentile)%"

    Write-Host "`nMemory Performance:" -ForegroundColor Cyan
    Write-Host "  Total: $($script:report.Memory.TotalGB) GB"
    Write-Host ("  Average Used: {0} GB ({1}%)" -f `
        $script:report.Memory.AverageUsedGB, $script:report.Memory.AverageUsedPercent)
    Write-Host "  Peak Used: $($script:report.Memory.PeakUsedGB) GB ($($script:report.Memory.PeakUsedPercent)%)"

    if ($script:report.Bottlenecks.Count -gt 0) {
        Write-Host "`nPerformance Bottlenecks Detected:" -ForegroundColor Yellow
        foreach ($bottleneck in $script:report.Bottlenecks) {
            Write-ColorOutput "  ! $bottleneck" -Level Warning
        }
    }
    else {
        Write-ColorOutput "`nNo significant performance bottlenecks detected." -Level Success
    }

    Write-Host "`nTop CPU Consumers:" -ForegroundColor Cyan
    $script:report.TopProcesses.ByCPU | Select-Object -First 5 | Format-Table -AutoSize

    Write-Host "`n========================================`n" -ForegroundColor Cyan
}

function Export-HTMLReport {
    $reportPath = "$ReportDir\PerformanceReport_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Performance Report - $($script:report.ServerName)</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1600px; margin: 0 auto; background-color: white; padding: 30px;
            border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #007bff; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; border-bottom: 1px solid #ddd; padding-bottom: 5px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 15px; margin: 20px 0; }
        .metric { background-color: #f8f9fa; padding: 20px; border-radius: 4px; border-left: 4px solid #007bff; }
        .metric-value { font-size: 2em; font-weight: bold; color: #007bff; }
        .metric-label { color: #666; margin-top: 5px; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th { background-color: #007bff; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f1f1f1; }
        .warning { background-color: #fff3cd; padding: 15px; border-left: 4px solid #ffc107; margin: 15px 0; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #777; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Performance Analysis Report</h1>
        <p><strong>Server:</strong> $($script:report.ServerName)<br>
        <strong>Start Time:</strong> $($script:report.StartTime)<br>
        <strong>End Time:</strong> $($script:report.EndTime)<br>
        <strong>Duration:</strong> $($script:report.Duration)<br>
        <strong>Samples:</strong> $($script:report.TotalSamples)</p>

        <div class="summary">
            <div class="metric">
                <div class="metric-value">$($script:report.CPU.Average)%</div>
                <div class="metric-label">Average CPU</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($script:report.CPU.Max)%</div>
                <div class="metric-label">Peak CPU</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($script:report.Memory.AverageUsedPercent)%</div>
                <div class="metric-label">Average Memory Used</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($script:report.Memory.TotalGB) GB</div>
                <div class="metric-label">Total Memory</div>
            </div>
        </div>

        $(if($script:report.Bottlenecks.Count -gt 0) {
            "<div class='warning'><h3>Performance Bottlenecks Detected</h3><ul>"
            foreach($bottleneck in $script:report.Bottlenecks) {
                "<li>$bottleneck</li>"
            }
            "</ul></div>"
        })

        <h2>CPU Performance</h2>
        <p>Average: $($script:report.CPU.Average)% | Min: $($script:report.CPU.Min)% |
        Max: $($script:report.CPU.Max)% | 95th Percentile: $($script:report.CPU.Peak95Percentile)%</p>

        <h2>Memory Performance</h2>
        <p>Total: $($script:report.Memory.TotalGB) GB<br>
        Average Used: $($script:report.Memory.AverageUsedGB) GB ($($script:report.Memory.AverageUsedPercent)%)<br>
        Peak Used: $($script:report.Memory.PeakUsedGB) GB ($($script:report.Memory.PeakUsedPercent)%)</p>

        <h2>Top CPU Consumers</h2>
        <table>
            <tr><th>Process</th><th>PID</th><th>CPU (s)</th><th>Memory (MB)</th><th>Threads</th></tr>
            $(foreach($proc in $script:report.TopProcesses.ByCPU) {
                "<tr><td>$($proc.ProcessName)</td><td>$($proc.Id)</td><td>$($proc.'CPU(s)')</td>" +
                "<td>$($proc.MemoryMB)</td><td>$($proc.Threads)</td></tr>"
            })
        </table>

        <h2>Top Memory Consumers</h2>
        <table>
            <tr><th>Process</th><th>PID</th><th>Memory (MB)</th><th>CPU (s)</th></tr>
            $(foreach($proc in $script:report.TopProcesses.ByMemory) {
                "<tr><td>$($proc.ProcessName)</td><td>$($proc.Id)</td><td>$($proc.MemoryMB)</td>" +
                "<td>$($proc.'CPU(s)')</td></tr>"
            })
        </table>

        $(if($script:report.DiskIO.Count -gt 0) {
            $avgReads = [math]::Round(($script:report.DiskIO |
                ForEach-Object {$_.ReadsPerSec} | Measure-Object -Average).Average, 2)
            $avgWrites = [math]::Round(($script:report.DiskIO |
                ForEach-Object {$_.WritesPerSec} | Measure-Object -Average).Average, 2)
            $avgReadLatency = [math]::Round(($script:report.DiskIO |
                ForEach-Object {$_.ReadLatencyMs} | Measure-Object -Average).Average, 2)
            $avgWriteLatency = [math]::Round(($script:report.DiskIO |
                ForEach-Object {$_.WriteLatencyMs} | Measure-Object -Average).Average, 2)

            "<h2>Disk I/O Performance</h2>"
            "<p>Average Reads/sec: $avgReads<br>"
            "Average Writes/sec: $avgWrites<br>"
            "Average Read Latency: $avgReadLatency ms<br>"
            "Average Write Latency: $avgWriteLatency ms</p>"
        })

        <div class="footer">
            Report generated by Get-PerformanceReport.ps1
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-ColorOutput "`nHTML report exported to: $reportPath" -Level Success
    return $reportPath
}

function Export-CSVReport {
    $reportPath = "$ReportDir\PerformanceData_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

    $csvData = @()
    for ($i = 0; $i -lt $script:report.CPU.Samples.Count; $i++) {
        $csvData += [PSCustomObject]@{
            Sample = $i + 1
            CPU = $script:report.CPU.Samples[$i]
            MemoryUsedGB = $script:report.Memory.Samples[$i].UsedGB
            MemoryUsedPercent = $script:report.Memory.Samples[$i].UsedPercent
        }
    }

    $csvData | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
    Write-ColorOutput "CSV data exported to: $reportPath" -Level Success
    return $reportPath
}

function Main {
    try {
        if (-not (Test-AdminPrivilege)) {
            Write-Host "[-] Administrator privileges are required for performance counter access." -ForegroundColor Red
            return 1
        }

        $myDocs = [Environment]::GetFolderPath('MyDocuments')
        if ([string]::IsNullOrWhiteSpace($myDocs)) {
            # Profile-less contexts (CI runners, SYSTEM services): MyDocuments resolves empty;
            # fall back so report writing degrades gracefully instead of crashing.
            $myDocs = [Environment]::GetFolderPath('UserProfile')
        }
        $script:ReportDir = Join-Path $myDocs 'Reports'
        if ([string]::IsNullOrWhiteSpace($script:ReportDir) -or
            $script:ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
            $script:ReportDir -match '^(\\\\|//)') {
            throw "Unsafe report path: $script:ReportDir. Report path must be a local absolute " +
                "path without '..' traversal."
        }
        $script:ReportDir = [System.IO.Path]::GetFullPath($script:ReportDir)
        if (-not (Test-Path -LiteralPath $script:ReportDir -PathType Container)) {
            New-Item -ItemType Directory -Path $script:ReportDir -Force -ErrorAction Stop | Out-Null
        }

        $script:report = @{
            ServerName = $env:COMPUTERNAME
            StartTime = Get-Date
            EndTime = $null
            Duration = "$DurationMinutes minutes"
            SampleInterval = "$SampleInterval seconds"
            TotalSamples = 0
            CPU = @{
                Samples = @()
                Average = 0
                Min = 0
                Max = 0
                Peak95Percentile = 0
            }
            Memory = @{
                Samples = @()
                TotalGB = 0
                AverageUsedGB = 0
                AverageUsedPercent = 0
                PeakUsedGB = 0
                PeakUsedPercent = 0
            }
            DiskIO = @()
            Network = @()
            TopProcesses = @{
                ByCPU = @()
                ByMemory = @()
                ByDiskIO = @()
            }
            Bottlenecks = @()
        }

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  Performance Monitor & Analysis" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan

        Read-PerformanceSamples
        Measure-PerformanceStats
        Get-TopProcesses
        Show-Summary

        if ($ExportHTML) {
            Write-Host "Generating HTML report..." -ForegroundColor Cyan
            Export-HTMLReport | Out-Null
        }

        if ($ExportCSV) {
            Write-Host "Generating CSV report..." -ForegroundColor Cyan
            Export-CSVReport | Out-Null
        }

        Write-Host "[+] Performance analysis completed." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }

