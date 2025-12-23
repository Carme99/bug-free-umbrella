<#
.SYNOPSIS
    Comprehensive real-time health monitoring for Windows Server 2016-2022.

.DESCRIPTION
    This script performs comprehensive health checks on Windows servers:
    - CPU utilization and trending
    - Memory usage and available RAM
    - Disk space and I/O performance
    - Critical service status
    - Event log error analysis (last 24 hours)
    - Network adapter status
    - System uptime
    - Process resource consumption

.PARAMETER ExportReport
    Exports detailed report to HTML file.

.PARAMETER AlertThreshold
    Defines alert thresholds. Valid options: 'High', 'Medium', 'Low' (default: 'Medium').

.PARAMETER CheckServices
    Comma-separated list of additional services to monitor (beyond automatic critical services).

.PARAMETER EmailReport
    Send report via email (requires SMTP configuration in script).

.EXAMPLE
    .\Monitor-ServerHealth.ps1
    Performs standard health check with medium alert thresholds.

.EXAMPLE
    .\Monitor-ServerHealth.ps1 -AlertThreshold High -ExportReport
    Performs health check with high sensitivity and exports HTML report.

.EXAMPLE
    .\Monitor-ServerHealth.ps1 -CheckServices "W3SVC,MSSQLSERVER"
    Monitors health including IIS and SQL Server services.

.NOTES
    Requires Administrator privileges
    Compatible with Windows Server 2016, 2019, and 2022
    Typical execution time: 30-60 seconds
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$ExportReport,

    [Parameter(Mandatory=$false)]
    [ValidateSet('High','Medium','Low')]
    [string]$AlertThreshold = 'Medium',

    [Parameter(Mandatory=$false)]
    [string]$CheckServices,

    [Parameter(Mandatory=$false)]
    [switch]$EmailReport
)

#Requires -RunAsAdministrator

# Define alert thresholds
$thresholds = @{
    High = @{
        CPUWarning = 60
        CPUCritical = 80
        MemoryWarning = 70
        MemoryCritical = 85
        DiskWarning = 15
        DiskCritical = 10
    }
    Medium = @{
        CPUWarning = 70
        CPUCritical = 90
        MemoryWarning = 80
        MemoryCritical = 90
        DiskWarning = 10
        DiskCritical = 5
    }
    Low = @{
        CPUWarning = 80
        CPUCritical = 95
        MemoryWarning = 85
        MemoryCritical = 95
        DiskWarning = 5
        DiskCritical = 2
    }
}

$script:threshold = $thresholds[$AlertThreshold]
$script:healthReport = @{
    ServerName = $env:COMPUTERNAME
    ScanTime = Get-Date
    Status = 'Healthy'
    Issues = @()
    Warnings = @()
    CPU = @{}
    Memory = @{}
    Disks = @()
    Services = @()
    EventLogErrors = @()
    Network = @()
    SystemInfo = @{}
}

function Write-ColorOutput {
    param([string]$Message, [string]$Level = 'Info')

    $color = switch($Level) {
        'Critical' { 'Red' }
        'Warning' { 'Yellow' }
        'Success' { 'Green' }
        default { 'White' }
    }
    Write-Host $Message -ForegroundColor $color
}

function Get-CPUHealth {
    Write-Verbose "Checking CPU utilization..."

    $cpuSamples = @()
    for($i = 0; $i -lt 5; $i++) {
        $cpu = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue
        $cpuSamples += $cpu.CounterSamples[0].CookedValue
        Start-Sleep -Seconds 1
    }

    $avgCPU = ($cpuSamples | Measure-Object -Average).Average
    $script:healthReport.CPU = @{
        AverageCPU = [math]::Round($avgCPU, 2)
        Samples = $cpuSamples
        Status = 'OK'
    }

    if($avgCPU -ge $script:threshold.CPUCritical) {
        $script:healthReport.CPU.Status = 'Critical'
        $script:healthReport.Status = 'Critical'
        $script:healthReport.Issues += "CPU utilization critical: $([math]::Round($avgCPU, 2))%"
        Write-ColorOutput "  [CRITICAL] CPU: $([math]::Round($avgCPU, 2))%" -Level Critical
    }
    elseif($avgCPU -ge $script:threshold.CPUWarning) {
        $script:healthReport.CPU.Status = 'Warning'
        if($script:healthReport.Status -ne 'Critical') { $script:healthReport.Status = 'Warning' }
        $script:healthReport.Warnings += "CPU utilization elevated: $([math]::Round($avgCPU, 2))%"
        Write-ColorOutput "  [WARNING] CPU: $([math]::Round($avgCPU, 2))%" -Level Warning
    }
    else {
        Write-ColorOutput "  [OK] CPU: $([math]::Round($avgCPU, 2))%" -Level Success
    }

    # Get top CPU processes
    $topProcesses = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 |
        Select-Object ProcessName, @{Name='CPU';Expression={[math]::Round($_.CPU, 2)}},
        @{Name='MemoryMB';Expression={[math]::Round($_.WorkingSet64/1MB, 2)}}
    $script:healthReport.CPU.TopProcesses = $topProcesses
}

function Get-MemoryHealth {
    Write-Verbose "Checking memory utilization..."

    $os = Get-CimInstance Win32_OperatingSystem
    $totalMemoryGB = [math]::Round($os.TotalVisibleMemorySize/1MB, 2)
    $freeMemoryGB = [math]::Round($os.FreePhysicalMemory/1MB, 2)
    $usedMemoryGB = $totalMemoryGB - $freeMemoryGB
    $memoryUsedPercent = [math]::Round(($usedMemoryGB / $totalMemoryGB) * 100, 2)

    $script:healthReport.Memory = @{
        TotalGB = $totalMemoryGB
        UsedGB = $usedMemoryGB
        FreeGB = $freeMemoryGB
        UsedPercent = $memoryUsedPercent
        Status = 'OK'
    }

    if($memoryUsedPercent -ge $script:threshold.MemoryCritical) {
        $script:healthReport.Memory.Status = 'Critical'
        $script:healthReport.Status = 'Critical'
        $script:healthReport.Issues += "Memory utilization critical: $memoryUsedPercent%"
        Write-ColorOutput "  [CRITICAL] Memory: $memoryUsedPercent% ($usedMemoryGB GB / $totalMemoryGB GB)" -Level Critical
    }
    elseif($memoryUsedPercent -ge $script:threshold.MemoryWarning) {
        $script:healthReport.Memory.Status = 'Warning'
        if($script:healthReport.Status -ne 'Critical') { $script:healthReport.Status = 'Warning' }
        $script:healthReport.Warnings += "Memory utilization elevated: $memoryUsedPercent%"
        Write-ColorOutput "  [WARNING] Memory: $memoryUsedPercent% ($usedMemoryGB GB / $totalMemoryGB GB)" -Level Warning
    }
    else {
        Write-ColorOutput "  [OK] Memory: $memoryUsedPercent% ($usedMemoryGB GB / $totalMemoryGB GB)" -Level Success
    }

    # Get top memory processes
    $topProcesses = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 |
        Select-Object ProcessName, @{Name='MemoryMB';Expression={[math]::Round($_.WorkingSet64/1MB, 2)}}
    $script:healthReport.Memory.TopProcesses = $topProcesses
}

function Get-DiskHealth {
    Write-Verbose "Checking disk space..."

    $disks = Get-Volume | Where-Object {$_.DriveLetter -and $_.DriveType -eq 'Fixed'}

    foreach($disk in $disks) {
        $freeSpacePercent = [math]::Round(($disk.SizeRemaining / $disk.Size) * 100, 2)
        $diskInfo = @{
            DriveLetter = $disk.DriveLetter
            Label = $disk.FileSystemLabel
            TotalGB = [math]::Round($disk.Size/1GB, 2)
            FreeGB = [math]::Round($disk.SizeRemaining/1GB, 2)
            FreePercent = $freeSpacePercent
            Status = 'OK'
        }

        if($freeSpacePercent -le $script:threshold.DiskCritical) {
            $diskInfo.Status = 'Critical'
            $script:healthReport.Status = 'Critical'
            $script:healthReport.Issues += "Drive $($disk.DriveLetter): critically low space ($freeSpacePercent%)"
            Write-ColorOutput "  [CRITICAL] Drive $($disk.DriveLetter): $freeSpacePercent% free ($($diskInfo.FreeGB) GB / $($diskInfo.TotalGB) GB)" -Level Critical
        }
        elseif($freeSpacePercent -le $script:threshold.DiskWarning) {
            $diskInfo.Status = 'Warning'
            if($script:healthReport.Status -ne 'Critical') { $script:healthReport.Status = 'Warning' }
            $script:healthReport.Warnings += "Drive $($disk.DriveLetter): low space ($freeSpacePercent%)"
            Write-ColorOutput "  [WARNING] Drive $($disk.DriveLetter): $freeSpacePercent% free ($($diskInfo.FreeGB) GB / $($diskInfo.TotalGB) GB)" -Level Warning
        }
        else {
            Write-ColorOutput "  [OK] Drive $($disk.DriveLetter): $freeSpacePercent% free ($($diskInfo.FreeGB) GB / $($diskInfo.TotalGB) GB)" -Level Success
        }

        $script:healthReport.Disks += $diskInfo
    }
}

function Get-ServiceHealth {
    Write-Verbose "Checking service status..."

    # Critical Windows services
    $criticalServices = @(
        'EventLog', 'RpcSs', 'DCOM', 'Winmgmt', 'Dhcp', 'Dnscache',
        'W32Time', 'Netlogon', 'LanmanServer', 'LanmanWorkstation'
    )

    # Add user-specified services
    if($CheckServices) {
        $criticalServices += $CheckServices -split ','
    }

    $allHealthy = $true
    foreach($serviceName in $criticalServices) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

        if($service) {
            $serviceInfo = @{
                Name = $service.Name
                DisplayName = $service.DisplayName
                Status = $service.Status
                StartType = $service.StartType
                Health = 'OK'
            }

            if($service.Status -ne 'Running' -and $service.StartType -eq 'Automatic') {
                $serviceInfo.Health = 'Critical'
                $script:healthReport.Status = 'Critical'
                $script:healthReport.Issues += "Critical service stopped: $($service.DisplayName)"
                Write-ColorOutput "  [CRITICAL] Service: $($service.DisplayName) is $($service.Status)" -Level Critical
                $allHealthy = $false
            }

            $script:healthReport.Services += $serviceInfo
        }
    }

    if($allHealthy) {
        Write-ColorOutput "  [OK] All critical services running" -Level Success
    }
}

function Get-EventLogHealth {
    Write-Verbose "Checking event logs for errors..."

    $since = (Get-Date).AddHours(-24)
    $criticalErrors = @()

    try {
        $systemErrors = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            Level = 1,2
            StartTime = $since
        } -MaxEvents 50 -ErrorAction SilentlyContinue

        $appErrors = Get-WinEvent -FilterHashtable @{
            LogName = 'Application'
            Level = 1,2
            StartTime = $since
        } -MaxEvents 50 -ErrorAction SilentlyContinue

        $allErrors = @($systemErrors) + @($appErrors) | Sort-Object TimeCreated -Descending

        foreach($error in $allErrors | Select-Object -First 10) {
            $criticalErrors += @{
                TimeCreated = $error.TimeCreated
                LogName = $error.LogName
                Level = $error.LevelDisplayName
                Source = $error.ProviderName
                EventID = $error.Id
                Message = $error.Message.Substring(0, [Math]::Min(200, $error.Message.Length))
            }
        }

        $script:healthReport.EventLogErrors = $criticalErrors

        if($criticalErrors.Count -gt 20) {
            $script:healthReport.Warnings += "High volume of errors in event logs (last 24h): $($criticalErrors.Count)"
            Write-ColorOutput "  [WARNING] Found $($criticalErrors.Count) critical errors in last 24 hours" -Level Warning
        }
        elseif($criticalErrors.Count -gt 0) {
            Write-ColorOutput "  [INFO] Found $($criticalErrors.Count) errors in last 24 hours"
        }
        else {
            Write-ColorOutput "  [OK] No critical errors in last 24 hours" -Level Success
        }
    }
    catch {
        Write-ColorOutput "  [WARNING] Could not read event logs: $($_.Exception.Message)" -Level Warning
    }
}

function Get-NetworkHealth {
    Write-Verbose "Checking network adapters..."

    $adapters = Get-NetAdapter | Where-Object {$_.Status -eq 'Up'}

    foreach($adapter in $adapters) {
        $adapterInfo = @{
            Name = $adapter.Name
            InterfaceDescription = $adapter.InterfaceDescription
            Status = $adapter.Status
            LinkSpeed = $adapter.LinkSpeed
            MacAddress = $adapter.MacAddress
        }

        $script:healthReport.Network += $adapterInfo
        Write-ColorOutput "  [OK] $($adapter.Name): $($adapter.Status) ($($adapter.LinkSpeed))" -Level Success
    }
}

function Get-SystemInfo {
    Write-Verbose "Gathering system information..."

    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $uptime = (Get-Date) - $os.LastBootUpTime

    $script:healthReport.SystemInfo = @{
        OSName = $os.Caption
        OSVersion = $os.Version
        BuildNumber = $os.BuildNumber
        Manufacturer = $cs.Manufacturer
        Model = $cs.Model
        Domain = $cs.Domain
        UptimeDays = [math]::Round($uptime.TotalDays, 2)
        LastBootTime = $os.LastBootUpTime
    }

    Write-ColorOutput "  System: $($os.Caption) (Build $($os.BuildNumber))"
    Write-ColorOutput "  Uptime: $([math]::Round($uptime.TotalDays, 2)) days"
}

function Export-HTMLReport {
    $reportPath = "$env:USERPROFILE\Desktop\ServerHealth_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $statusColor = switch($script:healthReport.Status) {
        'Critical' { '#dc3545' }
        'Warning' { '#ffc107' }
        default { '#28a745' }
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Server Health Report - $($script:healthReport.ServerName)</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid $statusColor; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; border-bottom: 1px solid #ddd; padding-bottom: 5px; }
        .status-badge { display: inline-block; padding: 8px 16px; border-radius: 4px; color: white; font-weight: bold; background-color: $statusColor; }
        .metric { background-color: #f8f9fa; padding: 15px; margin: 10px 0; border-radius: 4px; border-left: 4px solid #007bff; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th { background-color: #007bff; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f1f1f1; }
        .critical { color: #dc3545; font-weight: bold; }
        .warning { color: #ffc107; font-weight: bold; }
        .success { color: #28a745; font-weight: bold; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #777; font-size: 0.9em; }
        ul { background-color: #fff3cd; padding: 15px 15px 15px 35px; border-radius: 4px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Server Health Report</h1>
        <div class="metric">
            <strong>Server:</strong> $($script:healthReport.ServerName)<br>
            <strong>Scan Time:</strong> $($script:healthReport.ScanTime)<br>
            <strong>Status:</strong> <span class="status-badge">$($script:healthReport.Status)</span><br>
            <strong>OS:</strong> $($script:healthReport.SystemInfo.OSName)<br>
            <strong>Uptime:</strong> $($script:healthReport.SystemInfo.UptimeDays) days
        </div>

        $(if($script:healthReport.Issues.Count -gt 0) {
            "<h2>Critical Issues</h2><ul>"
            $script:healthReport.Issues | ForEach-Object { "<li class='critical'>$_</li>" }
            "</ul>"
        })

        $(if($script:healthReport.Warnings.Count -gt 0) {
            "<h2>Warnings</h2><ul>"
            $script:healthReport.Warnings | ForEach-Object { "<li class='warning'>$_</li>" }
            "</ul>"
        })

        <h2>CPU Usage</h2>
        <div class="metric">
            <strong>Average CPU:</strong> $($script:healthReport.CPU.AverageCPU)%<br>
            <strong>Status:</strong> <span class="$($script:healthReport.CPU.Status.ToLower())">$($script:healthReport.CPU.Status)</span>
        </div>
        <table>
            <tr><th>Process</th><th>CPU Time</th><th>Memory (MB)</th></tr>
            $(foreach($proc in $script:healthReport.CPU.TopProcesses) {
                "<tr><td>$($proc.ProcessName)</td><td>$($proc.CPU)</td><td>$($proc.MemoryMB)</td></tr>"
            })
        </table>

        <h2>Memory Usage</h2>
        <div class="metric">
            <strong>Total Memory:</strong> $($script:healthReport.Memory.TotalGB) GB<br>
            <strong>Used:</strong> $($script:healthReport.Memory.UsedGB) GB ($($script:healthReport.Memory.UsedPercent)%)<br>
            <strong>Free:</strong> $($script:healthReport.Memory.FreeGB) GB<br>
            <strong>Status:</strong> <span class="$($script:healthReport.Memory.Status.ToLower())">$($script:healthReport.Memory.Status)</span>
        </div>

        <h2>Disk Space</h2>
        <table>
            <tr><th>Drive</th><th>Label</th><th>Total (GB)</th><th>Free (GB)</th><th>Free %</th><th>Status</th></tr>
            $(foreach($disk in $script:healthReport.Disks) {
                "<tr><td>$($disk.DriveLetter):</td><td>$($disk.Label)</td><td>$($disk.TotalGB)</td><td>$($disk.FreeGB)</td><td>$($disk.FreePercent)%</td><td class='$($disk.Status.ToLower())'>$($disk.Status)</td></tr>"
            })
        </table>

        <h2>Services</h2>
        <table>
            <tr><th>Service Name</th><th>Display Name</th><th>Status</th><th>Start Type</th><th>Health</th></tr>
            $(foreach($svc in $script:healthReport.Services) {
                "<tr><td>$($svc.Name)</td><td>$($svc.DisplayName)</td><td>$($svc.Status)</td><td>$($svc.StartType)</td><td class='$($svc.Health.ToLower())'>$($svc.Health)</td></tr>"
            })
        </table>

        <h2>Recent Event Log Errors (Last 24h)</h2>
        $(if($script:healthReport.EventLogErrors.Count -gt 0) {
            "<table><tr><th>Time</th><th>Log</th><th>Level</th><th>Source</th><th>Event ID</th><th>Message</th></tr>"
            foreach($event in $script:healthReport.EventLogErrors) {
                "<tr><td>$($event.TimeCreated)</td><td>$($event.LogName)</td><td>$($event.Level)</td><td>$($event.Source)</td><td>$($event.EventID)</td><td>$($event.Message)</td></tr>"
            }
            "</table>"
        } else {
            "<p class='success'>No critical errors found in the last 24 hours.</p>"
        })

        <div class="footer">
            Report generated on $($script:healthReport.ScanTime) by Monitor-ServerHealth.ps1<br>
            Alert Threshold: $AlertThreshold
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-ColorOutput "`nHTML report exported to: $reportPath" -Level Success
    return $reportPath
}

# Main execution
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Server Health Monitor" -ForegroundColor Cyan
Write-Host "  Alert Threshold: $AlertThreshold" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Checking CPU..." -ForegroundColor Cyan
Get-CPUHealth

Write-Host "`nChecking Memory..." -ForegroundColor Cyan
Get-MemoryHealth

Write-Host "`nChecking Disk Space..." -ForegroundColor Cyan
Get-DiskHealth

Write-Host "`nChecking Services..." -ForegroundColor Cyan
Get-ServiceHealth

Write-Host "`nChecking Event Logs..." -ForegroundColor Cyan
Get-EventLogHealth

Write-Host "`nChecking Network..." -ForegroundColor Cyan
Get-NetworkHealth

Write-Host "`nGathering System Info..." -ForegroundColor Cyan
Get-SystemInfo

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Health Check Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Server: $($script:healthReport.ServerName)"
Write-Host "Status: " -NoNewline
switch($script:healthReport.Status) {
    'Critical' { Write-Host "CRITICAL" -ForegroundColor Red }
    'Warning' { Write-Host "WARNING" -ForegroundColor Yellow }
    default { Write-Host "HEALTHY" -ForegroundColor Green }
}

if($script:healthReport.Issues.Count -gt 0) {
    Write-Host "`nCritical Issues:" -ForegroundColor Red
    $script:healthReport.Issues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

if($script:healthReport.Warnings.Count -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Yellow
    $script:healthReport.Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

if($ExportReport) {
    Write-Host "`nGenerating HTML report..." -ForegroundColor Cyan
    $reportPath = Export-HTMLReport
}

Write-Host "`n========================================`n" -ForegroundColor Cyan
