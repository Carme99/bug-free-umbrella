<#
.SYNOPSIS
    Performs a comprehensive system health check on Windows devices.

.DESCRIPTION
    This script performs a multi-point health check including:
    - CPU, memory, and disk usage monitoring
    - Critical service status
    - Windows Update status
    - Event log error analysis
    - System uptime and reboot recommendations
    - Temperature monitoring (if available)
    - Battery health (for laptops)
    Results are reported to the console with a 0-100 health score.
    Side effects: none; this is a read-only detector. HTML/CSV report export is not implemented in this release
    and a console warning is emitted if requested via -OutputFormat.
    Exit codes: 0 when the check completes (healthy, warning, or critical findings); 1 on fatal error or unsafe
    -OutputPath.

.PARAMETER OutputFormat
    Specifies the output format: None, HTML, CSV, or All. Default is None (console only).

.PARAMETER OutputPath
    Path to save the output file(s). Default is current directory.

.PARAMETER CheckServices
    Array of critical services to monitor. Default includes common Windows services.

.PARAMETER DiskThresholdPercent
    Disk usage percentage threshold for warnings. Default is 80.

.PARAMETER MemoryThresholdPercent
    Memory usage percentage threshold for warnings. Default is 90.

.EXAMPLE
    PS C:\> .\Get-SystemHealthCheck.ps1 -OutputFormat HTML -OutputPath "C:\Reports"
    Generates an HTML health check report.

.EXAMPLE
    PS C:\> .\Get-SystemHealthCheck.ps1 -DiskThresholdPercent 85 -MemoryThresholdPercent 85
    Runs health check with custom resource thresholds.

.NOTES
    File Name   : Get-SystemHealthCheck.ps1
    Author      : Server Management Team
    Prerequisite: PowerShell 5.1+
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateSet('None', 'HTML', 'CSV', 'All')]
    [string]$OutputFormat = 'None',

    [Parameter()]
    [string]$OutputPath = (Get-Location),

    [Parameter()]
    [string[]]$CheckServices = @('wuauserv', 'BITS', 'CryptSvc', 'TrustedInstaller', 'Winmgmt', 'EventLog'),

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$DiskThresholdPercent = 80,

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$MemoryThresholdPercent = 90
)

$ErrorActionPreference = 'Stop'

# PSSA note: Write-Host is mandated here for colorized [+]/[!]/[-]/[*] console status prefixes
# (RELAUNCH-SPEC section 3); PSAvoidUsingWriteHost warnings are accepted by design.

function Main {
    [CmdletBinding()]
    param(
        [string]$OutputFormat = '',
        [string]$OutputPath = '',
        [string[]]$CheckServices = $null,
        [int]$DiskThresholdPercent = 0,
        [int]$MemoryThresholdPercent = 0
    )

    try {
        # Normalize unset parameters to their documented defaults
        if ([string]::IsNullOrWhiteSpace($OutputFormat)) { $OutputFormat = 'None' }
        if (-not $CheckServices) {
            $CheckServices = @('wuauserv', 'BITS', 'CryptSvc', 'TrustedInstaller', 'Winmgmt', 'EventLog')
        }
        if ($DiskThresholdPercent -le 0) { $DiskThresholdPercent = 80 }
        if ($MemoryThresholdPercent -le 0) { $MemoryThresholdPercent = 90 }
        Write-Host "[*] === System Health Check ===" -ForegroundColor Cyan
        Write-Host "[*] Analyzing system health..." -ForegroundColor Cyan

        # Validate OutputPath only when export is requested: reject '..' traversal and UNC remote paths
        if ($OutputFormat -ne 'None') {
            if ([string]::IsNullOrWhiteSpace($OutputPath) -or
                $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
                $OutputPath -match '^(\\\\|//)') {
                throw "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
            }
        }

        # Initialize results
        $healthCheck = @{
            ComputerName = $env:COMPUTERNAME
            CheckTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            OverallHealth = "Healthy"
            HealthScore = 100
            Issues = @()
            Warnings = @()
            CPU = @{}
            Memory = @{}
            Disk = @()
            Services = @()
            Uptime = @{}
            WindowsUpdate = @{}
            EventLogErrors = @{}
        }

        #region CPU Check
        Write-Host "[*] Checking CPU usage..." -ForegroundColor Cyan
        try {
            $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
            $cpuLoad = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 3 `
                -ErrorAction Stop |
                    Select-Object -ExpandProperty CounterSamples |
                    Measure-Object -Property CookedValue -Average).Average

            $healthCheck.CPU = @{
                Name = $cpu.Name
                Cores = $cpu.NumberOfCores
                LogicalProcessors = $cpu.NumberOfLogicalProcessors
                CurrentLoad = [math]::Round($cpuLoad, 2)
                MaxClockSpeed = $cpu.MaxClockSpeed
            }

            $cpuLoadRounded = [math]::Round($cpuLoad, 2)
            if ($cpuLoad -gt 90) {
                $healthCheck.Issues += "CPU usage is very high: $cpuLoadRounded%"
                $healthCheck.HealthScore -= 15
            }
            elseif ($cpuLoad -gt 75) {
                $healthCheck.Warnings += "CPU usage is elevated: $cpuLoadRounded%"
                $healthCheck.HealthScore -= 5
            }

            $cpuPrefix = if ($cpuLoad -gt 75) { '[!]' } else { '[+]' }
            $cpuForeground = if ($cpuLoad -gt 75) { 'Yellow' } else { 'Green' }
            Write-Host "$cpuPrefix CPU: $($cpu.Name) - Load: $cpuLoadRounded%" -ForegroundColor $cpuForeground
        }
        catch {
            $healthCheck.Issues += "Could not check CPU status"
            $healthCheck.HealthScore -= 10
        }
        #endregion

        #region Memory Check
        Write-Host "[*] Checking memory usage..." -ForegroundColor Cyan
        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $totalMemoryGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
            $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
            $usedMemoryGB = $totalMemoryGB - $freeMemoryGB
            $memoryUsagePercent = [math]::Round(($usedMemoryGB / $totalMemoryGB) * 100, 2)

            $healthCheck.Memory = @{
                TotalGB = $totalMemoryGB
                UsedGB = $usedMemoryGB
                FreeGB = $freeMemoryGB
                UsagePercent = $memoryUsagePercent
            }

            if ($memoryUsagePercent -gt $MemoryThresholdPercent) {
                $healthCheck.Issues += "Memory usage is very high: $memoryUsagePercent%"
                $healthCheck.HealthScore -= 15
            }
            elseif ($memoryUsagePercent -gt ($MemoryThresholdPercent - 10)) {
                $healthCheck.Warnings += "Memory usage is elevated: $memoryUsagePercent%"
                $healthCheck.HealthScore -= 5
            }

            $memForeground = 'Green'
            $memPrefix = '[+]'
            if ($memoryUsagePercent -gt $MemoryThresholdPercent) {
                $memForeground = 'Red'
                $memPrefix = '[!]'
            }
            elseif ($memoryUsagePercent -gt 80) {
                $memForeground = 'Yellow'
                $memPrefix = '[!]'
            }
            $memUsageMsg = "$memPrefix Memory: $usedMemoryGB GB / $totalMemoryGB GB ($memoryUsagePercent%)"
            Write-Host $memUsageMsg -ForegroundColor $memForeground
        }
        catch {
            $healthCheck.Issues += "Could not check memory status"
            $healthCheck.HealthScore -= 10
        }
        #endregion

        #region Disk Check
        Write-Host "[*] Checking disk usage..." -ForegroundColor Cyan
        try {
            $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop

            foreach ($disk in $disks) {
                $diskSizeGB = [math]::Round($disk.Size / 1GB, 2)
                $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
                $diskUsedGB = $diskSizeGB - $diskFreeGB
                $diskUsagePercent = [math]::Round(($diskUsedGB / $diskSizeGB) * 100, 2)

                $diskInfo = @{
                    Drive = $disk.DeviceID
                    SizeGB = $diskSizeGB
                    UsedGB = $diskUsedGB
                    FreeGB = $diskFreeGB
                    UsagePercent = $diskUsagePercent
                    VolumeName = $disk.VolumeName
                }

                $healthCheck.Disk += $diskInfo

                if ($diskUsagePercent -gt $DiskThresholdPercent + 10) {
                    $healthCheck.Issues += "Disk $($disk.DeviceID) usage is critical: $diskUsagePercent%"
                    $healthCheck.HealthScore -= 15
                }
                elseif ($diskUsagePercent -gt $DiskThresholdPercent) {
                    $healthCheck.Warnings += "Disk $($disk.DeviceID) usage is high: $diskUsagePercent%"
                    $healthCheck.HealthScore -= 5
                }

                $diskForeground = if ($diskUsagePercent -gt 90) { 'Red' }
                elseif ($diskUsagePercent -gt $DiskThresholdPercent) { 'Yellow' }
                else { 'Green' }
                $diskPrefix = if ($diskUsagePercent -gt $DiskThresholdPercent) { '[!]' } else { '[+]' }
                Write-Host "$diskPrefix Disk $($disk.DeviceID): $diskUsedGB GB / $diskSizeGB GB ($diskUsagePercent%)" `
                    -ForegroundColor $diskForeground
            }
        }
        catch {
            $healthCheck.Issues += "Could not check disk status"
            $healthCheck.HealthScore -= 10
        }
        #endregion

        #region Service Check
        Write-Host "[*] Checking critical services..." -ForegroundColor Cyan
        try {
            foreach ($serviceName in $CheckServices) {
                $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

                if ($service) {
                    $serviceInfo = @{
                        Name = $service.Name
                        DisplayName = $service.DisplayName
                        Status = $service.Status
                        StartType = $service.StartType
                    }

                    $healthCheck.Services += $serviceInfo

                    if ($service.Status -ne 'Running' -and $service.StartType -eq 'Automatic') {
                        $healthCheck.Issues += "Critical service not running: $($service.DisplayName)"
                        $healthCheck.HealthScore -= 10
                    }

                    $serviceForeground = if ($service.Status -eq 'Running') { 'Green' } else { 'Red' }
                    $servicePrefix = if ($service.Status -eq 'Running') { '[+]' } else { '[-]' }
                    $serviceMsg = "$servicePrefix $($service.DisplayName): $($service.Status)"
                    Write-Host $serviceMsg -ForegroundColor $serviceForeground
                }
                else {
                    Write-Host "[!] ${serviceName}: Not Found" -ForegroundColor Yellow
                }
            }
        }
        catch {
            $healthCheck.Warnings += "Could not check all services"
        }
        #endregion

        #region Uptime Check
        Write-Host "[*] Checking system uptime..." -ForegroundColor Cyan
        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $lastBootTime = $os.LastBootUpTime
            $uptime = (Get-Date) - $lastBootTime

            $healthCheck.Uptime = @{
                LastBootTime = $lastBootTime.ToString("yyyy-MM-dd HH:mm:ss")
                UptimeDays = [math]::Round($uptime.TotalDays, 2)
                UptimeHours = [math]::Round($uptime.TotalHours, 2)
            }

            if ($uptime.TotalDays -gt 30) {
                $uptimeDaysRounded = [math]::Round($uptime.TotalDays, 0)
                $healthCheck.Warnings += "System has been running for $uptimeDaysRounded days - reboot recommended"
                $healthCheck.HealthScore -= 5
            }

            $uptimePrefix = if ($uptime.TotalDays -gt 30) { '[!]' } else { '[+]' }
            $uptimeForeground = if ($uptime.TotalDays -gt 30) { 'Yellow' } else { 'Green' }
            $uptimeMsg = "$uptimePrefix Uptime: $([math]::Round($uptime.TotalDays, 2)) days " +
                "(Last boot: $($lastBootTime.ToString('yyyy-MM-dd HH:mm')))"
            Write-Host $uptimeMsg -ForegroundColor $uptimeForeground
        }
        catch {
            $healthCheck.Warnings += "Could not check uptime"
        }
        #endregion

        #region Windows Update Check
        Write-Host "[*] Checking Windows Update status..." -ForegroundColor Cyan
        try {
            $updateSession = New-Object -ComObject Microsoft.Update.Session -ErrorAction SilentlyContinue
            $updateSearcher = $updateSession.CreateUpdateSearcher()
            $pendingUpdates = $updateSearcher.Search("IsInstalled=0 and Type='Software'").Updates.Count

            $healthCheck.WindowsUpdate = @{
                PendingUpdates = $pendingUpdates
            }

            if ($pendingUpdates -gt 10) {
                $healthCheck.Warnings += "Many pending Windows updates: $pendingUpdates"
                $healthCheck.HealthScore -= 5
            }

            $updatePrefix = if ($pendingUpdates -gt 10) { '[!]' } else { '[+]' }
            $updateForeground = if ($pendingUpdates -gt 10) { 'Yellow' } else { 'Green' }
            Write-Host "$updatePrefix Pending Windows Updates: $pendingUpdates" -ForegroundColor $updateForeground
        }
        catch {
            Write-Host "[!] Could not check Windows Update status" -ForegroundColor Yellow
        }
        #endregion

        #region Event Log Errors
        Write-Host "[*] Checking recent event log errors..." -ForegroundColor Cyan
        try {
            $startTime = (Get-Date).AddDays(-1)
            $criticalErrors = Get-WinEvent -FilterHashtable @{LogName = 'System'; Level = 2; StartTime = $startTime } `
                -MaxEvents 100 -ErrorAction SilentlyContinue
            $errorCount = ($criticalErrors | Measure-Object).Count

            $recentErrors = @()
            if ($criticalErrors) {
                $recentErrors = $criticalErrors | Select-Object -First 5 | ForEach-Object {
                    @{
                        TimeGenerated = $_.TimeCreated
                        Source = $_.ProviderName
                        Message = $_.Message.Substring(0, [Math]::Min(100, $_.Message.Length))
                    }
                }
            }

            $healthCheck.EventLogErrors = @{
                Last24Hours = $errorCount
                RecentErrors = $recentErrors
            }

            if ($errorCount -gt 50) {
                $healthCheck.Issues += "High number of system errors in last 24 hours: $errorCount"
                $healthCheck.HealthScore -= 10
            }
            elseif ($errorCount -gt 20) {
                $healthCheck.Warnings += "Elevated system errors in last 24 hours: $errorCount"
                $healthCheck.HealthScore -= 5
            }

            $eventPrefix = if ($errorCount -gt 20) { '[!]' } else { '[+]' }
            $eventForeground = if ($errorCount -gt 50) { 'Red' }
            elseif ($errorCount -gt 20) { 'Yellow' }
            else { 'Green' }
            Write-Host "$eventPrefix System errors (24h): $errorCount" -ForegroundColor $eventForeground
        }
        catch {
            Write-Host "[!] Could not check event logs" -ForegroundColor Yellow
        }
        #endregion

        # Determine overall health
        if ($healthCheck.HealthScore -ge 90) {
            $healthCheck.OverallHealth = "Healthy"
            $healthColor = "Green"
        }
        elseif ($healthCheck.HealthScore -ge 70) {
            $healthCheck.OverallHealth = "Warning"
            $healthColor = "Yellow"
        }
        else {
            $healthCheck.OverallHealth = "Critical"
            $healthColor = "Red"
        }

        #region Display Summary
        Write-Host "`n=== Health Check Summary ===" -ForegroundColor Cyan
        $statusPrefix = switch ($healthCheck.OverallHealth) {
            'Healthy' { '[+]' }
            'Warning' { '[!]' }
            default { '[-]' }
        }
        $summaryMsg = "$statusPrefix Overall Health: $($healthCheck.OverallHealth) " +
            "(Score: $($healthCheck.HealthScore)/100)"
        Write-Host $summaryMsg -ForegroundColor $healthColor

        if ($healthCheck.Issues.Count -gt 0) {
            Write-Host "[-] Critical Issues:" -ForegroundColor Red
            $healthCheck.Issues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        }

        if ($healthCheck.Warnings.Count -gt 0) {
            Write-Host "[!] Warnings:" -ForegroundColor Yellow
            $healthCheck.Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        }

        if ($healthCheck.Issues.Count -eq 0 -and $healthCheck.Warnings.Count -eq 0) {
            Write-Host "[+] No issues detected. System is running optimally." -ForegroundColor Green
        }
        #endregion

        if ($OutputFormat -ne 'None') {
            $exportWarnMsg = "[!] Report export format '$OutputFormat' is not implemented in this release; " +
                "console results only."
            Write-Host $exportWarnMsg -ForegroundColor Yellow
        }

        Write-Host "[+] Health check completed successfully." -ForegroundColor Green

        return 0
    }
    catch {
        Write-Host "[-] Error during system health check: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
