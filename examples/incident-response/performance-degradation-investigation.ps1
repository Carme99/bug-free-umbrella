<#
.SYNOPSIS
    Performance degradation investigation and diagnostics workflow

.DESCRIPTION
    This example demonstrates a comprehensive performance investigation workflow for
    troubleshooting slow systems, high resource usage, and service degradation issues.
    Collects performance metrics, event logs, disk space, and process information.

.NOTES
    Copyright (c) 2025 bug-free-umbrella contributors
    Licensed under Apache License 2.0
    https://github.com/Carme99/bug-free-umbrella

.EXAMPLE
    .\performance-degradation-investigation.ps1 -ComputerName "SERVER01" -IncidentId "PERF-2025-001"

.EXAMPLE
    .\performance-degradation-investigation.ps1 -ComputerName "DESKTOP-ABC" -CollectDuration 120 -EmailReport -To "it-support@company.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [string]$IncidentId = "PERF-$(Get-Date -Format 'yyyyMMdd-HHmmss')",

    [Parameter(Mandatory = $false)]
    [int]$CollectDuration = 60,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath = "C:\PerformanceReports",

    [Parameter(Mandatory = $false)]
    [switch]$EmailReport,

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer,

    [Parameter(Mandatory = $false)]
    [string]$To
)

# Define the root path to the scripts directory
$ScriptRoot = Join-Path -Path $PSScriptRoot -ChildPath "..\..\scripts"

# Create report directory if it doesn't exist
if (-not (Test-Path -Path $ReportPath)) {
    New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$ReportFile = Join-Path -Path $ReportPath -ChildPath "PerformanceInvestigation_${IncidentId}_$Timestamp.html"
$LogFile = Join-Path -Path $ReportPath -ChildPath "PerformanceInvestigation_${IncidentId}_$Timestamp.log"

function Write-Log {
    param([string]$Message)
    $LogMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Write-Host $LogMessage
    Add-Content -Path $LogFile -Value $LogMessage
}

Write-Host "=== PERFORMANCE DEGRADATION INVESTIGATION ===" -ForegroundColor Cyan
Write-Host "Incident ID: $IncidentId" -ForegroundColor Yellow
Write-Host "Target System: $ComputerName" -ForegroundColor Yellow
Write-Host "Collection Duration: $CollectDuration seconds" -ForegroundColor Yellow
Write-Host "Investigation Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host ""

Write-Log "=== PERFORMANCE INVESTIGATION INITIATED ==="
Write-Log "Incident ID: $IncidentId"
Write-Log "Target System: $ComputerName"

$Diagnostics = @()
$PerformanceIssues = @()

# Step 1: System Information
Write-Host "[1/9] Collecting system information..." -ForegroundColor Cyan
Write-Log "Step 1: Collecting system information"
try {
    $OS = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $ComputerName
    $CS = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $ComputerName
    $CPU = Get-CimInstance -ClassName Win32_Processor -ComputerName $ComputerName | Select-Object -First 1

    $SystemInfo = @{
        OS = "$($OS.Caption) $($OS.Version)"
        Uptime = (Get-Date) - $OS.LastBootUpTime
        TotalMemoryGB = [math]::Round($CS.TotalPhysicalMemory / 1GB, 2)
        Manufacturer = $CS.Manufacturer
        Model = $CS.Model
        CPUName = $CPU.Name
        CPUCores = $CPU.NumberOfCores
        CPULogicalProcessors = $CPU.NumberOfLogicalProcessors
    }

    Write-Host "✓ System: $($SystemInfo.OS)" -ForegroundColor Green
    Write-Host "  Uptime: $([math]::Round($SystemInfo.Uptime.TotalHours, 2)) hours" -ForegroundColor Gray
    Write-Host "  RAM: $($SystemInfo.TotalMemoryGB) GB" -ForegroundColor Gray
    Write-Host "  CPU: $($SystemInfo.CPUName)" -ForegroundColor Gray
    Write-Log "SUCCESS: System information collected"

    $Diagnostics += @{
        Category = "System Info"
        Status = "Collected"
        Details = "$($SystemInfo.OS), $($SystemInfo.TotalMemoryGB)GB RAM"
    }
} catch {
    Write-Warning "Failed to collect system info: $_"
    Write-Log "ERROR: System info collection failed: $_"
    $Diagnostics += @{
        Category = "System Info"
        Status = "Failed"
        Details = "Error: $_"
    }
}

# Step 2: Current Resource Usage Snapshot
Write-Host "`n[2/9] Capturing current resource usage..." -ForegroundColor Cyan
Write-Log "Step 2: Capturing resource usage snapshot"
try {
    $PerfData = @{
        CPUUsage = (Get-Counter -Counter "\Processor(_Total)\% Processor Time" -ComputerName $ComputerName -SampleInterval 1 -MaxSamples 3 |
            Select-Object -ExpandProperty CounterSamples |
            Measure-Object -Property CookedValue -Average).Average

        MemoryAvailableMB = (Get-Counter -Counter "\Memory\Available MBytes" -ComputerName $ComputerName).CounterSamples.CookedValue

        DiskQueue = (Get-Counter -Counter "\PhysicalDisk(_Total)\Current Disk Queue Length" -ComputerName $ComputerName -SampleInterval 1 -MaxSamples 3 |
            Select-Object -ExpandProperty CounterSamples |
            Measure-Object -Property CookedValue -Average).Average
    }

    $MemoryUsedPercent = [math]::Round((($SystemInfo.TotalMemoryGB * 1024 - $PerfData.MemoryAvailableMB) / ($SystemInfo.TotalMemoryGB * 1024)) * 100, 2)
    $PerfData.MemoryUsedPercent = $MemoryUsedPercent

    Write-Host "  CPU Usage: $([math]::Round($PerfData.CPUUsage, 2))%" -ForegroundColor $(if ($PerfData.CPUUsage -gt 80) { "Red" } elseif ($PerfData.CPUUsage -gt 60) { "Yellow" } else { "Green" })
    Write-Host "  Memory Used: $MemoryUsedPercent%" -ForegroundColor $(if ($MemoryUsedPercent -gt 90) { "Red" } elseif ($MemoryUsedPercent -gt 80) { "Yellow" } else { "Green" })
    Write-Host "  Disk Queue: $([math]::Round($PerfData.DiskQueue, 2))" -ForegroundColor $(if ($PerfData.DiskQueue -gt 2) { "Red" } elseif ($PerfData.DiskQueue -gt 1) { "Yellow" } else { "Green" })

    if ($PerfData.CPUUsage -gt 80) {
        $PerformanceIssues += "High CPU usage: $([math]::Round($PerfData.CPUUsage, 2))%"
    }
    if ($MemoryUsedPercent -gt 90) {
        $PerformanceIssues += "Critical memory usage: $MemoryUsedPercent%"
    }
    if ($PerfData.DiskQueue -gt 2) {
        $PerformanceIssues += "High disk queue length: $([math]::Round($PerfData.DiskQueue, 2))"
    }

    Write-Log "SUCCESS: Resource usage captured - CPU: $([math]::Round($PerfData.CPUUsage, 2))%, Memory: $MemoryUsedPercent%"

    $Diagnostics += @{
        Category = "Resource Usage"
        Status = "Analyzed"
        Details = "CPU: $([math]::Round($PerfData.CPUUsage, 2))%, Memory: $MemoryUsedPercent%"
    }
} catch {
    Write-Warning "Failed to capture performance data: $_"
    Write-Log "ERROR: Performance data capture failed: $_"
    $Diagnostics += @{
        Category = "Resource Usage"
        Status = "Failed"
        Details = "Error: $_"
    }
}

# Step 3: Top CPU Consumers
Write-Host "`n[3/9] Identifying top CPU consumers..." -ForegroundColor Cyan
Write-Log "Step 3: Identifying top CPU consumers"
try {
    $TopCPU = Get-Process -ComputerName $ComputerName |
        Sort-Object CPU -Descending |
        Select-Object -First 5 -Property ProcessName, CPU, WorkingSet, Id

    Write-Host "  Top 5 CPU Consumers:" -ForegroundColor Yellow
    foreach ($Process in $TopCPU) {
        $WSMB = [math]::Round($Process.WorkingSet / 1MB, 2)
        Write-Host "    • $($Process.ProcessName) (PID: $($Process.Id)) - CPU: $([math]::Round($Process.CPU, 2))s, RAM: ${WSMB}MB" -ForegroundColor Gray
    }

    Write-Log "SUCCESS: Top CPU consumers identified: $($TopCPU.ProcessName -join ', ')"

    $Diagnostics += @{
        Category = "CPU Consumers"
        Status = "Identified"
        Details = "Top: $($TopCPU[0].ProcessName)"
    }
} catch {
    Write-Warning "Failed to identify CPU consumers: $_"
    Write-Log "ERROR: CPU consumer identification failed: $_"
    $Diagnostics += @{
        Category = "CPU Consumers"
        Status = "Failed"
        Details = "Error: $_"
    }
}

# Step 4: Top Memory Consumers
Write-Host "`n[4/9] Identifying top memory consumers..." -ForegroundColor Cyan
Write-Log "Step 4: Identifying top memory consumers"
try {
    $TopMemory = Get-Process -ComputerName $ComputerName |
        Sort-Object WorkingSet -Descending |
        Select-Object -First 5 -Property ProcessName, WorkingSet, CPU, Id

    Write-Host "  Top 5 Memory Consumers:" -ForegroundColor Yellow
    foreach ($Process in $TopMemory) {
        $WSMB = [math]::Round($Process.WorkingSet / 1MB, 2)
        Write-Host "    • $($Process.ProcessName) (PID: $($Process.Id)) - RAM: ${WSMB}MB, CPU: $([math]::Round($Process.CPU, 2))s" -ForegroundColor Gray
    }

    Write-Log "SUCCESS: Top memory consumers identified: $($TopMemory.ProcessName -join ', ')"

    $Diagnostics += @{
        Category = "Memory Consumers"
        Status = "Identified"
        Details = "Top: $($TopMemory[0].ProcessName)"
    }
} catch {
    Write-Warning "Failed to identify memory consumers: $_"
    Write-Log "ERROR: Memory consumer identification failed: $_"
    $Diagnostics += @{
        Category = "Memory Consumers"
        Status = "Failed"
        Details = "Error: $_"
    }
}

# Step 5: Disk Space Analysis
Write-Host "`n[5/9] Analyzing disk space..." -ForegroundColor Cyan
Write-Log "Step 5: Analyzing disk space"
try {
    $Disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ComputerName $ComputerName

    Write-Host "  Disk Space Status:" -ForegroundColor Yellow
    foreach ($Disk in $Disks) {
        $PercentFree = [math]::Round(($Disk.FreeSpace / $Disk.Size) * 100, 2)
        $FreeGB = [math]::Round($Disk.FreeSpace / 1GB, 2)
        $SizeGB = [math]::Round($Disk.Size / 1GB, 2)

        $DiskColor = if ($PercentFree -lt 10) { "Red" } elseif ($PercentFree -lt 20) { "Yellow" } else { "Green" }

        Write-Host "    • $($Disk.DeviceID) ${FreeGB}GB free of ${SizeGB}GB ($PercentFree% free)" -ForegroundColor $DiskColor

        if ($PercentFree -lt 20) {
            $PerformanceIssues += "Low disk space on $($Disk.DeviceID): Only $PercentFree% free"
        }
    }

    Write-Log "SUCCESS: Disk space analyzed"

    $Diagnostics += @{
        Category = "Disk Space"
        Status = "Analyzed"
        Details = "$($Disks.Count) drives checked"
    }
} catch {
    Write-Warning "Failed to analyze disk space: $_"
    Write-Log "ERROR: Disk space analysis failed: $_"
    $Diagnostics += @{
        Category = "Disk Space"
        Status = "Failed"
        Details = "Error: $_"
    }
}

# Step 6: Performance Report (using existing script)
Write-Host "`n[6/9] Collecting detailed performance metrics ($CollectDuration seconds)..." -ForegroundColor Cyan
Write-Log "Step 6: Collecting detailed performance metrics"
try {
    & "$ScriptRoot\infrastructure\windows\monitoring\Get-PerformanceReport.ps1" `
        -ComputerName $ComputerName `
        -Duration $CollectDuration `
        -Verbose:$false

    Write-Host "✓ Performance metrics collected" -ForegroundColor Green
    Write-Log "SUCCESS: Performance metrics collected"

    $Diagnostics += @{
        Category = "Performance Metrics"
        Status = "Collected"
        Details = "$CollectDuration second sampling"
    }
} catch {
    Write-Warning "Failed to collect performance metrics: $_"
    Write-Log "ERROR: Performance metrics collection failed: $_"
    $Diagnostics += @{
        Category = "Performance Metrics"
        Status = "Failed"
        Details = "Error: $_"
    }
}

# Step 7: Event Log Analysis
Write-Host "`n[7/9] Analyzing event logs for errors (last 24 hours)..." -ForegroundColor Cyan
Write-Log "Step 7: Analyzing event logs"
try {
    $ErrorEvents = & "$ScriptRoot\infrastructure\windows\monitoring\Get-EventLogReport.ps1" `
        -ComputerName $ComputerName `
        -Hours 24 `
        -Level Error,Critical `
        -Verbose:$false

    $ErrorCount = if ($ErrorEvents) { $ErrorEvents.Count } else { 0 }

    if ($ErrorCount -gt 0) {
        Write-Warning "Found $ErrorCount critical/error events in last 24 hours"
        $PerformanceIssues += "Found $ErrorCount error events in event logs"
    } else {
        Write-Host "✓ No critical errors in event logs" -ForegroundColor Green
    }

    Write-Log "INFO: Found $ErrorCount error events"

    $Diagnostics += @{
        Category = "Event Logs"
        Status = "Analyzed"
        Details = "$ErrorCount errors/critical events"
    }
} catch {
    Write-Warning "Failed to analyze event logs: $_"
    Write-Log "ERROR: Event log analysis failed: $_"
    $Diagnostics += @{
        Category = "Event Logs"
        Status = "Failed"
        Details = "Error: $_"
    }
}

# Step 8: Server Health Check
Write-Host "`n[8/9] Running comprehensive health check..." -ForegroundColor Cyan
Write-Log "Step 8: Running health check"
try {
    & "$ScriptRoot\infrastructure\windows\monitoring\Monitor-ServerHealth.ps1" `
        -ComputerName $ComputerName `
        -CheckAll `
        -Verbose:$false

    Write-Host "✓ Health check completed" -ForegroundColor Green
    Write-Log "SUCCESS: Health check completed"

    $Diagnostics += @{
        Category = "Health Check"
        Status = "Completed"
        Details = "Full system health check"
    }
} catch {
    Write-Warning "Health check failed: $_"
    Write-Log "ERROR: Health check failed: $_"
    $Diagnostics += @{
        Category = "Health Check"
        Status = "Failed"
        Details = "Error: $_"
    }
}

# Step 9: Windows Update Status
Write-Host "`n[9/9] Checking Windows Update status..." -ForegroundColor Cyan
Write-Log "Step 9: Checking Windows Update status"
try {
    & "$ScriptRoot\infrastructure\windows\monitoring\Monitor-ServerHealth.ps1" `
        -ComputerName $ComputerName `
        -CheckWindowsUpdate `
        -Verbose:$false

    Write-Host "✓ Windows Update status checked" -ForegroundColor Green
    Write-Log "SUCCESS: Windows Update status checked"

    $Diagnostics += @{
        Category = "Windows Updates"
        Status = "Checked"
        Details = "Update status verified"
    }
} catch {
    Write-Warning "Windows Update check failed: $_"
    Write-Log "ERROR: Windows Update check failed: $_"
    $Diagnostics += @{
        Category = "Windows Updates"
        Status = "Failed"
        Details = "Error: $_"
    }
}

# Generate HTML Report
Write-Host "`nGenerating performance investigation report..." -ForegroundColor Cyan
Write-Log "Generating investigation report"

$SeverityColor = if ($PerformanceIssues.Count -gt 0) { "red" } else { "green" }
$SeverityText = if ($PerformanceIssues.Count -gt 0) { "ISSUES DETECTED" } else { "HEALTHY" }

$HtmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Performance Investigation Report - $IncidentId</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 30px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #1976d2; border-bottom: 3px solid #1976d2; padding-bottom: 10px; }
        h2 { color: #0066cc; margin-top: 30px; }
        .header-info { background-color: #e3f2fd; border-left: 5px solid #1976d2; padding: 15px; margin: 20px 0; }
        .issues { background-color: #ffebee; border-left: 5px solid #d32f2f; padding: 15px; margin: 20px 0; }
        .healthy { background-color: #e8f5e9; border-left: 5px solid #4caf50; padding: 15px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th { background-color: #1976d2; color: white; padding: 12px; text-align: left; }
        td { border: 1px solid #ddd; padding: 10px; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .recommendations { background-color: #fff3cd; padding: 20px; margin-top: 30px; border-radius: 5px; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 0.9em; }
        .metric { display: inline-block; padding: 10px 20px; margin: 5px; background-color: #e3f2fd; border-radius: 5px; }
        .metric-value { font-size: 1.5em; font-weight: bold; color: #1976d2; }
        .metric-label { font-size: 0.9em; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <h1>📊 PERFORMANCE DEGRADATION INVESTIGATION</h1>

        <div class="header-info">
            <p><strong>Incident ID:</strong> $IncidentId</p>
            <p><strong>System:</strong> $ComputerName</p>
            <p><strong>Investigation Time:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
            <p><strong>Status:</strong> <span style="color: $SeverityColor; font-weight: bold;">$SeverityText</span></p>
            <p><strong>Uptime:</strong> $([math]::Round($SystemInfo.Uptime.TotalHours, 2)) hours</p>
        </div>

        <h2>Current Performance Metrics</h2>
        <div style="text-align: center; margin: 20px 0;">
            <div class="metric">
                <div class="metric-value">$([math]::Round($PerfData.CPUUsage, 2))%</div>
                <div class="metric-label">CPU Usage</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($PerfData.MemoryUsedPercent)%</div>
                <div class="metric-label">Memory Used</div>
            </div>
            <div class="metric">
                <div class="metric-value">$([math]::Round($PerfData.DiskQueue, 2))</div>
                <div class="metric-label">Disk Queue</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($Disks.Count)</div>
                <div class="metric-label">Drives</div>
            </div>
        </div>
"@

if ($PerformanceIssues.Count -gt 0) {
    $HtmlReport += @"
        <div class="issues">
            <h2>⚠ Performance Issues Detected</h2>
            <ul>
"@
    foreach ($Issue in $PerformanceIssues) {
        $HtmlReport += "                <li>$Issue</li>`n"
    }
    $HtmlReport += @"
            </ul>
        </div>
"@
} else {
    $HtmlReport += @"
        <div class="healthy">
            <h2>✓ No Critical Performance Issues Detected</h2>
            <p>System is operating within normal parameters.</p>
        </div>
"@
}

$HtmlReport += @"
        <h2>Diagnostic Results</h2>
        <table>
            <tr>
                <th>Category</th>
                <th>Status</th>
                <th>Details</th>
            </tr>
"@

foreach ($Diag in $Diagnostics) {
    $HtmlReport += @"
            <tr>
                <td>$($Diag.Category)</td>
                <td>$($Diag.Status)</td>
                <td>$($Diag.Details)</td>
            </tr>
"@
}

$HtmlReport += @"
        </table>

        <div class="recommendations">
            <h2>🔧 Recommendations</h2>
            <ol>
"@

if ($PerfData.CPUUsage -gt 80) {
    $HtmlReport += "                <li><strong>HIGH CPU:</strong> Review top CPU consumers and consider terminating unnecessary processes</li>`n"
}
if ($PerfData.MemoryUsedPercent -gt 90) {
    $HtmlReport += "                <li><strong>HIGH MEMORY:</strong> Consider adding RAM or closing memory-intensive applications</li>`n"
}
if ($PerfData.DiskQueue -gt 2) {
    $HtmlReport += "                <li><strong>DISK BOTTLENECK:</strong> Check disk performance, consider upgrading to SSD or reviewing I/O intensive processes</li>`n"
}
foreach ($Disk in $Disks) {
    $PercentFree = [math]::Round(($Disk.FreeSpace / $Disk.Size) * 100, 2)
    if ($PercentFree -lt 20) {
        $HtmlReport += "                <li><strong>LOW DISK SPACE ($($Disk.DeviceID)):</strong> Clean up disk space or expand volume</li>`n"
    }
}
if ($ErrorCount -gt 10) {
    $HtmlReport += "                <li><strong>EVENT LOG ERRORS:</strong> Review event logs for recurring errors that may impact performance</li>`n"
}
if ($SystemInfo.Uptime.TotalDays -gt 30) {
    $HtmlReport += "                <li><strong>LONG UPTIME:</strong> Consider scheduling a maintenance reboot</li>`n"
}

if ($PerformanceIssues.Count -eq 0) {
    $HtmlReport += "                <li>Continue monitoring system performance</li>`n"
    $HtmlReport += "                <li>Schedule regular health checks</li>`n"
    $HtmlReport += "                <li>Review Windows Update compliance</li>`n"
}

$HtmlReport += @"
            </ol>
        </div>

        <div class="footer">
            <p><strong>Generated by:</strong> bug-free-umbrella Performance Investigation Workflow</p>
            <p><strong>Repository:</strong> <a href="https://github.com/Carme99/bug-free-umbrella">https://github.com/Carme99/bug-free-umbrella</a></p>
            <p><strong>Log File:</strong> $LogFile</p>
        </div>
    </div>
</body>
</html>
"@

$HtmlReport | Out-File -FilePath $ReportFile -Encoding UTF8
Write-Host "✓ Report saved: $ReportFile" -ForegroundColor Green
Write-Host "✓ Log saved: $LogFile" -ForegroundColor Green
Write-Log "Report generated: $ReportFile"

# Email Report (if requested)
if ($EmailReport -and $SMTPServer -and $To) {
    Write-Host "`nSending performance report via email..." -ForegroundColor Cyan
    Write-Log "Sending email report to $To"
    try {
        $MailParams = @{
            To         = $To
            From       = "performance-monitoring@$env:USERDNSDOMAIN"
            Subject    = "📊 Performance Investigation Report - $IncidentId - $ComputerName"
            Body       = $HtmlReport
            BodyAsHtml = $true
            SmtpServer = $SMTPServer
        }
        Send-MailMessage @MailParams
        Write-Host "✓ Email sent successfully to $To" -ForegroundColor Green
        Write-Log "Email sent successfully"
    } catch {
        Write-Warning "Failed to send email: $_"
        Write-Log "ERROR: Failed to send email: $_"
    }
}

Write-Host "`n=== PERFORMANCE INVESTIGATION COMPLETE ===" -ForegroundColor Cyan
Write-Host "Incident ID: $IncidentId" -ForegroundColor Yellow

if ($PerformanceIssues.Count -gt 0) {
    Write-Host "`n⚠ $($PerformanceIssues.Count) performance issue(s) detected - review report for details" -ForegroundColor Yellow
} else {
    Write-Host "`n✓ No critical performance issues detected" -ForegroundColor Green
}

Write-Log "=== INVESTIGATION COMPLETED ==="
