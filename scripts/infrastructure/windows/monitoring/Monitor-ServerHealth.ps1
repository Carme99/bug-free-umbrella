<#
.SYNOPSIS
    Comprehensive real-time health monitoring for Windows Server 2016-2022 with optional advanced features.

.DESCRIPTION
    This script performs comprehensive health checks on Windows servers with interactive mode support.

    Core Checks (always enabled):
    - CPU utilization and trending
    - Memory usage and available RAM
    - Disk space availability
    - Critical service status
    - Event log error analysis (last 24 hours)
    - Network adapter status
    - System uptime and information
    - Advanced performance metrics (page file, handles, threads)

    Optional Checks (enabled via parameters or interactive menu):
    - Disk I/O Performance (latency, queue depth, throughput)
    - Windows Update status (pending/failed updates, reboot required)
    - Security monitoring (Firewall, Defender, failed logins)
    - Network connectivity tests (gateway, DNS, internet)
    - Certificate expiration monitoring
    - Scheduled tasks health
    - Application monitoring (IIS, SQL Server, Hyper-V)

    Export Options:
    - HTML report with detailed metrics
    - JSON export for automation/integration
    - Email delivery (requires SMTP configuration)

.PARAMETER ExportReport
    Exports detailed report to HTML file on Desktop.

.PARAMETER AlertThreshold
    Defines alert thresholds. Valid options: 'High', 'Medium' (default), 'Low'.

.PARAMETER CheckServices
    Comma-separated list of additional services to monitor.

.PARAMETER EmailReport
    Send report via email. Requires -SMTPServer, -EmailFrom, and -EmailTo parameters.

.PARAMETER IncludeDiskIO
    Enable disk I/O performance monitoring (latency, IOPS, queue depth).

.PARAMETER IncludeWindowsUpdate
    Check Windows Update status, pending updates, and reboot requirements.

.PARAMETER IncludeSecurity
    Monitor security settings: Firewall profiles, Defender status, failed login attempts.

.PARAMETER IncludeNetworkTests
    Test network connectivity to gateway, DNS servers, and internet.

.PARAMETER IncludeCertificates
    Check certificate expiration in LocalMachine stores.

.PARAMETER IncludeScheduledTasks
    Monitor scheduled tasks for failures and disabled tasks.

.PARAMETER IncludeApplications
    Enable monitoring for IIS, SQL Server, and Hyper-V (if installed).

.PARAMETER CheckIIS
    Specifically monitor IIS application pools and websites.

.PARAMETER CheckSQLServer
    Specifically monitor SQL Server service status.

.PARAMETER CheckHyperV
    Specifically monitor Hyper-V and virtual machines.

.PARAMETER ExportJSON
    Export report in JSON format for automation and integration.

.PARAMETER ShowProgress
    Display progress indicators during health checks.

.PARAMETER SMTPServer
    SMTP server address for email delivery.

.PARAMETER SMTPPort
    SMTP server port (default: 25).

.PARAMETER EmailFrom
    Sender email address.

.PARAMETER EmailTo
    Recipient email address(es).

.PARAMETER EmailSubject
    Email subject line (default: "Server Health Report - SERVERNAME").

.PARAMETER UseSSL
    Use SSL/TLS for SMTP connection.

.PARAMETER SMTPCredential
    PSCredential object for SMTP authentication.

.PARAMETER CertificateWarningDays
    Days before expiration to warn about certificates (default: 30).

.EXAMPLE
    .\Monitor-ServerHealth.ps1
    Runs in interactive mode, prompting for monitoring options.

.EXAMPLE
    .\Monitor-ServerHealth.ps1 -AlertThreshold High -ExportReport
    Performs health check with high sensitivity and exports HTML report.

.EXAMPLE
    .\Monitor-ServerHealth.ps1 -IncludeSecurity -IncludeCertificates -ExportReport
    Monitors security settings and certificates, exports HTML report.

.EXAMPLE
    .\Monitor-ServerHealth.ps1 -IncludeApplications -CheckIIS -CheckSQLServer
    Monitors IIS and SQL Server applications.

.EXAMPLE
    .\Monitor-ServerHealth.ps1 -IncludeDiskIO -IncludeWindowsUpdate -IncludeNetworkTests -ShowProgress -ExportJSON
    Comprehensive monitoring with progress indicators and JSON export.

.EXAMPLE
    .\Monitor-ServerHealth.ps1 -EmailReport -SMTPServer "smtp.example.com" -EmailFrom "monitor@example.com" -EmailTo "admin@example.com" -ExportReport
    Monitors server and emails HTML report.

.NOTES
    Requires Administrator privileges
    Compatible with Windows Server 2016, 2019, and 2022
    Typical execution time: 30 seconds (basic) to 2-3 minutes (full scan)
    Interactive mode available when run without parameters
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
    [switch]$EmailReport,

    # Feature toggles
    [Parameter(Mandatory=$false)]
    [switch]$IncludeDiskIO,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeWindowsUpdate,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeSecurity,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeNetworkTests,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeApplications,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeCertificates,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeScheduledTasks,

    # Export options
    [Parameter(Mandatory=$false)]
    [switch]$ExportJSON,

    [Parameter(Mandatory=$false)]
    [switch]$ShowProgress,

    # Email parameters
    [Parameter(Mandatory=$false)]
    [string]$SMTPServer,

    [Parameter(Mandatory=$false)]
    [int]$SMTPPort = 25,

    [Parameter(Mandatory=$false)]
    [string]$EmailFrom,

    [Parameter(Mandatory=$false)]
    [string[]]$EmailTo,

    [Parameter(Mandatory=$false)]
    [string]$EmailSubject = "Server Health Report - $env:COMPUTERNAME",

    [Parameter(Mandatory=$false)]
    [switch]$UseSSL,

    [Parameter(Mandatory=$false)]
    [PSCredential]$SMTPCredential,

    # Application-specific
    [Parameter(Mandatory=$false)]
    [switch]$CheckIIS,

    [Parameter(Mandatory=$false)]
    [switch]$CheckSQLServer,

    [Parameter(Mandatory=$false)]
    [switch]$CheckHyperV,

    # Certificate warning threshold
    [Parameter(Mandatory=$false)]
    [int]$CertificateWarningDays = 30
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
    DiskIO = @{
        Enabled = $false
        Samples = @()
        AverageReadsPerSec = 0
        AverageWritesPerSec = 0
        AverageReadLatencyMs = 0
        AverageWriteLatencyMs = 0
        AverageQueueLength = 0
        Status = 'OK'
    }
    WindowsUpdate = @{
        Enabled = $false
        LastSuccessfulUpdate = $null
        PendingUpdates = @()
        FailedUpdates = @()
        UpdatesInstalled = 0
        UpdatesPending = 0
        UpdatesFailed = 0
        Status = 'OK'
        RebootRequired = $false
        WindowsUpdateService = 'Unknown'
    }
    Security = @{
        Enabled = $false
        Firewall = @{
            DomainProfile = 'Unknown'
            PrivateProfile = 'Unknown'
            PublicProfile = 'Unknown'
            Status = 'OK'
        }
        Defender = @{
            ServiceRunning = $false
            RealTimeProtection = $false
            SignatureAge = 0
            LastScan = $null
            Status = 'OK'
        }
        FailedLogins = @{
            Last24Hours = 0
            RecentAttempts = @()
            Status = 'OK'
        }
    }
    NetworkTests = @{
        Enabled = $false
        Gateway = @{
            IP = $null
            Reachable = $false
            Latency = 0
        }
        DNS = @{
            PrimaryServer = $null
            Reachable = $false
            ResolutionWorking = $false
        }
        Internet = @{
            Reachable = $false
            Target = '8.8.8.8'
            Latency = 0
        }
        Status = 'OK'
    }
    AdvancedPerformance = @{
        PageFile = @{
            TotalSizeMB = 0
            UsedMB = 0
            UsedPercent = 0
            Status = 'OK'
        }
        Handles = 0
        Threads = 0
        Processes = 0
    }
    Certificates = @{
        Enabled = $false
        Certificates = @()
        Expiring = 0
        Expired = 0
        Status = 'OK'
    }
    ScheduledTasks = @{
        Enabled = $false
        Tasks = @()
        Failed = 0
        Disabled = 0
        Status = 'OK'
    }
    Applications = @{
        IIS = @{
            Enabled = $false
            Installed = $false
            Running = $false
            ApplicationPools = @()
            Websites = @()
            FailedPools = 0
            StoppedSites = 0
            Status = 'OK'
        }
        SQLServer = @{
            Enabled = $false
            Installed = $false
            Running = $false
            Databases = @()
            FailedJobs = @()
            Status = 'OK'
        }
        HyperV = @{
            Enabled = $false
            Installed = $false
            Running = $false
            VirtualMachines = @()
            Status = 'OK'
        }
    }
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

function Update-Progress {
    <#
    .SYNOPSIS
        Updates progress bar for health checks.
    #>
    param(
        [int]$Current,
        [int]$Total,
        [string]$Activity,
        [string]$Status
    )

    if(-not $ShowProgress) { return }

    $percentComplete = [math]::Round(($Current / $Total) * 100, 0)

    Write-Progress -Activity $Activity `
                   -Status $Status `
                   -PercentComplete $percentComplete `
                   -CurrentOperation "Step $Current of $Total"
}

function Show-InteractiveMenu {
    <#
    .SYNOPSIS
        Displays interactive menu for selecting monitoring options.
    #>

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Server Health Monitor - Interactive Mode" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    Write-Host "Select monitoring options:`n"

    Write-Host "Quick Presets:" -ForegroundColor Yellow
    Write-Host "  [1] Quick Check (Basic: CPU, Memory, Disk, Services)"
    Write-Host "  [2] Full Scan (All available checks)"
    Write-Host "  [3] Security Audit (Security + Certificates + Updates)"
    Write-Host "  [4] Application Health (IIS + SQL + Hyper-V if installed)"
    Write-Host "  [5] Custom Selection`n"

    $preset = Read-Host "Enter preset number (1-5) or press Enter for custom"

    switch($preset) {
        '1' {
            # Quick Check - just basic monitoring (default behavior)
            $script:ShowProgress = $true
        }
        '2' {
            # Full Scan - enable everything
            $script:IncludeDiskIO = $true
            $script:IncludeWindowsUpdate = $true
            $script:IncludeSecurity = $true
            $script:IncludeNetworkTests = $true
            $script:IncludeCertificates = $true
            $script:IncludeScheduledTasks = $true
            $script:IncludeApplications = $true
            $script:CheckIIS = $true
            $script:CheckSQLServer = $true
            $script:CheckHyperV = $true
            $script:ShowProgress = $true
            $script:ExportReport = $true
        }
        '3' {
            # Security Audit
            $script:IncludeSecurity = $true
            $script:IncludeCertificates = $true
            $script:IncludeWindowsUpdate = $true
            $script:ShowProgress = $true
            $script:ExportReport = $true
        }
        '4' {
            # Application Health
            $script:IncludeApplications = $true
            $script:CheckIIS = $true
            $script:CheckSQLServer = $true
            $script:CheckHyperV = $true
            $script:ShowProgress = $true
            $script:ExportReport = $true
        }
        default {
            # Custom selection
            Write-Host "`nSelect additional checks (comma-separated numbers, or 'all'):" -ForegroundColor Yellow
            Write-Host "  [1] Disk I/O Performance"
            Write-Host "  [2] Windows Update Status"
            Write-Host "  [3] Security Monitoring (Firewall, Defender, Failed Logins)"
            Write-Host "  [4] Network Connectivity Tests"
            Write-Host "  [5] Certificate Expiration"
            Write-Host "  [6] Scheduled Tasks"
            Write-Host "  [7] Advanced Performance Metrics"
            Write-Host "  [8] Application Monitoring (IIS/SQL/Hyper-V)`n"

            $selection = Read-Host "Your selection"

            if($selection -eq 'all') {
                $selection = '1,2,3,4,5,6,7,8'
            }

            $choices = $selection -split ','
            foreach($choice in $choices) {
                switch($choice.Trim()) {
                    '1' { $script:IncludeDiskIO = $true }
                    '2' { $script:IncludeWindowsUpdate = $true }
                    '3' { $script:IncludeSecurity = $true }
                    '4' { $script:IncludeNetworkTests = $true }
                    '5' { $script:IncludeCertificates = $true }
                    '6' { $script:IncludeScheduledTasks = $true }
                    '7' { } # Advanced metrics always run
                    '8' {
                        $script:IncludeApplications = $true
                        $script:CheckIIS = $true
                        $script:CheckSQLServer = $true
                        $script:CheckHyperV = $true
                    }
                }
            }
        }
    }

    # Export options
    Write-Host "`nExport Options:" -ForegroundColor Yellow
    $exportHtml = Read-Host "Export HTML report? (Y/N)"
    if($exportHtml -eq 'Y' -or $exportHtml -eq 'y') {
        $script:ExportReport = $true
    }

    $exportJson = Read-Host "Export JSON report? (Y/N)"
    if($exportJson -eq 'Y' -or $exportJson -eq 'y') {
        $script:ExportJSON = $true
    }

    $showProg = Read-Host "Show progress indicators? (Y/N)"
    if($showProg -eq 'Y' -or $showProg -eq 'y') {
        $script:ShowProgress = $true
    }

    Write-Host "`nPress Enter to start monitoring..." -ForegroundColor Green
    Read-Host
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

function Get-DiskIOHealth {
    <#
    .SYNOPSIS
        Monitors disk I/O performance metrics.
    #>

    if(-not $IncludeDiskIO) { return }

    Write-Verbose "Checking disk I/O performance..."
    $script:healthReport.DiskIO.Enabled = $true

    try {
        $samples = @()
        for($i = 0; $i -lt 3; $i++) {
            $counters = Get-Counter @(
                '\PhysicalDisk(_Total)\Disk Reads/sec',
                '\PhysicalDisk(_Total)\Disk Writes/sec',
                '\PhysicalDisk(_Total)\Avg. Disk sec/Read',
                '\PhysicalDisk(_Total)\Avg. Disk sec/Write',
                '\PhysicalDisk(_Total)\Current Disk Queue Length'
            ) -ErrorAction Stop

            $samples += @{
                ReadsPerSec = $counters.CounterSamples[0].CookedValue
                WritesPerSec = $counters.CounterSamples[1].CookedValue
                ReadLatency = $counters.CounterSamples[2].CookedValue * 1000
                WriteLatency = $counters.CounterSamples[3].CookedValue * 1000
                QueueLength = $counters.CounterSamples[4].CookedValue
            }

            if($i -lt 2) { Start-Sleep -Seconds 2 }
        }

        $script:healthReport.DiskIO.Samples = $samples
        $script:healthReport.DiskIO.AverageReadsPerSec = [math]::Round(($samples | Measure-Object -Property ReadsPerSec -Average).Average, 2)
        $script:healthReport.DiskIO.AverageWritesPerSec = [math]::Round(($samples | Measure-Object -Property WritesPerSec -Average).Average, 2)
        $script:healthReport.DiskIO.AverageReadLatencyMs = [math]::Round(($samples | Measure-Object -Property ReadLatency -Average).Average, 2)
        $script:healthReport.DiskIO.AverageWriteLatencyMs = [math]::Round(($samples | Measure-Object -Property WriteLatency -Average).Average, 2)
        $script:healthReport.DiskIO.AverageQueueLength = [math]::Round(($samples | Measure-Object -Property QueueLength -Average).Average, 2)

        if($script:healthReport.DiskIO.AverageReadLatencyMs -gt 25 -or $script:healthReport.DiskIO.AverageWriteLatencyMs -gt 25) {
            $script:healthReport.DiskIO.Status = 'Warning'
            $script:healthReport.Warnings += "High disk latency detected (Read: $($script:healthReport.DiskIO.AverageReadLatencyMs)ms, Write: $($script:healthReport.DiskIO.AverageWriteLatencyMs)ms)"
            Write-ColorOutput "  [WARNING] Disk I/O: High latency" -Level Warning
        }
        elseif($script:healthReport.DiskIO.AverageQueueLength -gt 2) {
            $script:healthReport.DiskIO.Status = 'Warning'
            $script:healthReport.Warnings += "High disk queue length: $($script:healthReport.DiskIO.AverageQueueLength)"
            Write-ColorOutput "  [WARNING] Disk I/O: High queue length" -Level Warning
        }
        else {
            Write-ColorOutput "  [OK] Disk I/O: Read=$($script:healthReport.DiskIO.AverageReadLatencyMs)ms, Write=$($script:healthReport.DiskIO.AverageWriteLatencyMs)ms" -Level Success
        }
    }
    catch {
        Write-ColorOutput "  [WARNING] Could not collect disk I/O metrics: $($_.Exception.Message)" -Level Warning
    }
}

function Get-AdvancedPerformanceMetrics {
    <#
    .SYNOPSIS
        Collects advanced performance metrics: page file, handles, threads.
    #>

    Write-Verbose "Collecting advanced performance metrics..."

    try {
        $pageFile = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
        if($pageFile) {
            $script:healthReport.AdvancedPerformance.PageFile.TotalSizeMB = $pageFile.AllocatedBaseSize
            $script:healthReport.AdvancedPerformance.PageFile.UsedMB = $pageFile.CurrentUsage
            $script:healthReport.AdvancedPerformance.PageFile.UsedPercent = [math]::Round(($pageFile.CurrentUsage / $pageFile.AllocatedBaseSize) * 100, 2)

            if($script:healthReport.AdvancedPerformance.PageFile.UsedPercent -gt 80) {
                $script:healthReport.AdvancedPerformance.PageFile.Status = 'Warning'
                $script:healthReport.Warnings += "Page file usage high: $($script:healthReport.AdvancedPerformance.PageFile.UsedPercent)%"
            }
        }

        $os = Get-CimInstance Win32_OperatingSystem
        $script:healthReport.AdvancedPerformance.Processes = $os.NumberOfProcesses

        $threadCounter = Get-Counter '\System\Threads' -ErrorAction SilentlyContinue
        if($threadCounter) {
            $script:healthReport.AdvancedPerformance.Threads = [int]$threadCounter.CounterSamples[0].CookedValue
        }

        $handleCounter = Get-Counter '\Process(_Total)\Handle Count' -ErrorAction SilentlyContinue
        if($handleCounter) {
            $script:healthReport.AdvancedPerformance.Handles = [int]$handleCounter.CounterSamples[0].CookedValue
        }

        Write-ColorOutput "  [OK] Page File: $($script:healthReport.AdvancedPerformance.PageFile.UsedPercent)% used" -Level Success
    }
    catch {
        Write-ColorOutput "  [WARNING] Could not collect advanced metrics: $($_.Exception.Message)" -Level Warning
    }
}

function Get-WindowsUpdateHealth {
    <#
    .SYNOPSIS
        Checks Windows Update status and pending updates.
    #>

    if(-not $IncludeWindowsUpdate) { return }

    Write-Verbose "Checking Windows Update status..."
    $script:healthReport.WindowsUpdate.Enabled = $true

    try {
        $wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
        if($wuService) {
            $script:healthReport.WindowsUpdate.WindowsUpdateService = $wuService.Status
            if($wuService.Status -ne 'Running' -and $wuService.StartType -eq 'Automatic') {
                $script:healthReport.Warnings += "Windows Update service is not running"
            }
        }

        $rebootPending = $false
        $rebootKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        )

        foreach($key in $rebootKeys) {
            if(Test-Path $key) {
                $rebootPending = $true
                break
            }
        }
        $script:healthReport.WindowsUpdate.RebootRequired = $rebootPending

        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $searchResult = $updateSearcher.Search("IsInstalled=0 and IsHidden=0")

        $script:healthReport.WindowsUpdate.UpdatesPending = $searchResult.Updates.Count
        foreach($update in $searchResult.Updates) {
            $script:healthReport.WindowsUpdate.PendingUpdates += @{
                Title = $update.Title
                Severity = if($update.MsrcSeverity) { $update.MsrcSeverity } else { 'Unknown' }
                IsDownloaded = $update.IsDownloaded
                IsMandatory = $update.IsMandatory
                KB = if($update.KBArticleIDs.Count -gt 0) { $update.KBArticleIDs[0] } else { 'N/A' }
            }
        }

        $updateHistory = $updateSearcher.QueryHistory(0, 10)
        $successfulUpdates = $updateHistory | Where-Object { $_.ResultCode -eq 2 } | Sort-Object Date -Descending
        if($successfulUpdates) {
            $script:healthReport.WindowsUpdate.LastSuccessfulUpdate = $successfulUpdates[0].Date
            $script:healthReport.WindowsUpdate.UpdatesInstalled = $successfulUpdates.Count
        }

        if($script:healthReport.WindowsUpdate.UpdatesPending -gt 10) {
            $script:healthReport.WindowsUpdate.Status = 'Warning'
            $script:healthReport.Warnings += "Many pending updates: $($script:healthReport.WindowsUpdate.UpdatesPending)"
            Write-ColorOutput "  [WARNING] Windows Update: $($script:healthReport.WindowsUpdate.UpdatesPending) pending updates" -Level Warning
        }
        elseif($rebootPending) {
            $script:healthReport.WindowsUpdate.Status = 'Warning'
            $script:healthReport.Warnings += "Reboot required for updates"
            Write-ColorOutput "  [WARNING] Windows Update: Reboot required" -Level Warning
        }
        else {
            Write-ColorOutput "  [OK] Windows Update: $($script:healthReport.WindowsUpdate.UpdatesPending) pending" -Level Success
        }
    }
    catch {
        Write-ColorOutput "  [WARNING] Could not check Windows Update: $($_.Exception.Message)" -Level Warning
    }
}

function Get-SecurityHealth {
    <#
    .SYNOPSIS
        Monitors security settings: Firewall, Defender, failed logins.
    #>

    if(-not $IncludeSecurity) { return }

    Write-Verbose "Checking security configuration..."
    $script:healthReport.Security.Enabled = $true

    try {
        $fwProfiles = Get-NetFirewallProfile -ErrorAction Stop
        foreach($profile in $fwProfiles) {
            switch($profile.Name) {
                'Domain' { $script:healthReport.Security.Firewall.DomainProfile = $profile.Enabled }
                'Private' { $script:healthReport.Security.Firewall.PrivateProfile = $profile.Enabled }
                'Public' { $script:healthReport.Security.Firewall.PublicProfile = $profile.Enabled }
            }
        }

        $allEnabled = ($script:healthReport.Security.Firewall.DomainProfile -and
                       $script:healthReport.Security.Firewall.PrivateProfile -and
                       $script:healthReport.Security.Firewall.PublicProfile)

        if(-not $allEnabled) {
            $script:healthReport.Security.Firewall.Status = 'Critical'
            $script:healthReport.Status = 'Critical'
            $script:healthReport.Issues += "Windows Firewall is disabled on one or more profiles"
            Write-ColorOutput "  [CRITICAL] Firewall: One or more profiles disabled" -Level Critical
        }
        else {
            Write-ColorOutput "  [OK] Firewall: All profiles enabled" -Level Success
        }
    }
    catch {
        Write-ColorOutput "  [WARNING] Could not check firewall: $($_.Exception.Message)" -Level Warning
    }

    try {
        $defenderService = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
        if($defenderService) {
            $script:healthReport.Security.Defender.ServiceRunning = ($defenderService.Status -eq 'Running')

            $mpPreference = Get-MpPreference -ErrorAction SilentlyContinue
            $mpComputerStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue

            if($mpPreference) {
                $script:healthReport.Security.Defender.RealTimeProtection = $mpPreference.DisableRealtimeMonitoring -eq $false
            }

            if($mpComputerStatus) {
                $script:healthReport.Security.Defender.SignatureAge = $mpComputerStatus.AntivirusSignatureAge
                $script:healthReport.Security.Defender.LastScan = $mpComputerStatus.QuickScanEndTime

                if($mpComputerStatus.AntivirusSignatureAge -gt 7) {
                    $script:healthReport.Security.Defender.Status = 'Warning'
                    $script:healthReport.Warnings += "Defender signatures outdated: $($mpComputerStatus.AntivirusSignatureAge) days"
                    Write-ColorOutput "  [WARNING] Defender: Signatures $($mpComputerStatus.AntivirusSignatureAge) days old" -Level Warning
                }
                elseif(-not $script:healthReport.Security.Defender.RealTimeProtection) {
                    $script:healthReport.Security.Defender.Status = 'Critical'
                    $script:healthReport.Status = 'Critical'
                    $script:healthReport.Issues += "Defender real-time protection is disabled"
                    Write-ColorOutput "  [CRITICAL] Defender: Real-time protection disabled" -Level Critical
                }
                else {
                    Write-ColorOutput "  [OK] Defender: Running, signatures current" -Level Success
                }
            }
        }
    }
    catch {
        Write-ColorOutput "  [WARNING] Could not check Defender: $($_.Exception.Message)" -Level Warning
    }

    try {
        $since = (Get-Date).AddHours(-24)
        $failedLogins = Get-WinEvent -FilterHashtable @{
            LogName = 'Security'
            Id = 4625
            StartTime = $since
        } -MaxEvents 100 -ErrorAction SilentlyContinue

        if($failedLogins) {
            $script:healthReport.Security.FailedLogins.Last24Hours = $failedLogins.Count

            foreach($login in ($failedLogins | Select-Object -First 10)) {
                $xml = [xml]$login.ToXml()
                $script:healthReport.Security.FailedLogins.RecentAttempts += @{
                    TimeCreated = $login.TimeCreated
                    TargetUserName = $xml.Event.EventData.Data[5].'#text'
                    WorkstationName = $xml.Event.EventData.Data[13].'#text'
                    IpAddress = $xml.Event.EventData.Data[19].'#text'
                    FailureReason = $xml.Event.EventData.Data[8].'#text'
                }
            }

            if($failedLogins.Count -gt 50) {
                $script:healthReport.Security.FailedLogins.Status = 'Warning'
                $script:healthReport.Warnings += "High number of failed login attempts: $($failedLogins.Count)"
                Write-ColorOutput "  [WARNING] Security: $($failedLogins.Count) failed logins in 24h" -Level Warning
            }
            else {
                Write-ColorOutput "  [OK] Security: $($failedLogins.Count) failed logins in 24h" -Level Success
            }
        }
        else {
            Write-ColorOutput "  [OK] Security: No failed logins in 24h" -Level Success
        }
    }
    catch {
        Write-ColorOutput "  [WARNING] Could not check failed logins: $($_.Exception.Message)" -Level Warning
    }
}

function Get-NetworkConnectivityHealth {
    <#
    .SYNOPSIS
        Tests network connectivity to gateway, DNS, and internet.
    #>

    if(-not $IncludeNetworkTests) { return }

    Write-Verbose "Testing network connectivity..."
    $script:healthReport.NetworkTests.Enabled = $true

    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Select-Object -First 1
        $gatewayIP = $route.NextHop
        $script:healthReport.NetworkTests.Gateway.IP = $gatewayIP

        $ping = Test-Connection -ComputerName $gatewayIP -Count 2 -ErrorAction SilentlyContinue
        if($ping) {
            $script:healthReport.NetworkTests.Gateway.Reachable = $true
            $script:healthReport.NetworkTests.Gateway.Latency = [math]::Round(($ping.ResponseTime | Measure-Object -Average).Average, 2)
            Write-ColorOutput "  [OK] Gateway: $gatewayIP ($($script:healthReport.NetworkTests.Gateway.Latency)ms)" -Level Success
        }
        else {
            $script:healthReport.NetworkTests.Status = 'Critical'
            $script:healthReport.Status = 'Critical'
            $script:healthReport.Issues += "Cannot reach default gateway: $gatewayIP"
            Write-ColorOutput "  [CRITICAL] Gateway: Unreachable" -Level Critical
        }
    }
    catch {
        Write-ColorOutput "  [WARNING] Could not determine gateway: $($_.Exception.Message)" -Level Warning
    }

    try {
        $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 |
            Where-Object {$_.ServerAddresses.Count -gt 0} |
            Select-Object -First 1

        if($dnsServers) {
            $dnsIP = $dnsServers.ServerAddresses[0]
            $script:healthReport.NetworkTests.DNS.PrimaryServer = $dnsIP

            $dnsPing = Test-Connection -ComputerName $dnsIP -Count 2 -ErrorAction SilentlyContinue
            $script:healthReport.NetworkTests.DNS.Reachable = ($dnsPing -ne $null)

            $dnsTest = Resolve-DnsName -Name 'www.microsoft.com' -ErrorAction SilentlyContinue
            $script:healthReport.NetworkTests.DNS.ResolutionWorking = ($dnsTest -ne $null)

            if($script:healthReport.NetworkTests.DNS.ResolutionWorking) {
                Write-ColorOutput "  [OK] DNS: Server $dnsIP, resolution working" -Level Success
            }
            else {
                $script:healthReport.NetworkTests.Status = 'Warning'
                $script:healthReport.Warnings += "DNS resolution not working"
                Write-ColorOutput "  [WARNING] DNS: Resolution failing" -Level Warning
            }
        }
    }
    catch {
        Write-ColorOutput "  [WARNING] Could not test DNS: $($_.Exception.Message)" -Level Warning
    }

    try {
        $internetTarget = '8.8.8.8'
        $script:healthReport.NetworkTests.Internet.Target = $internetTarget

        $internetPing = Test-Connection -ComputerName $internetTarget -Count 2 -ErrorAction SilentlyContinue
        if($internetPing) {
            $script:healthReport.NetworkTests.Internet.Reachable = $true
            $script:healthReport.NetworkTests.Internet.Latency = [math]::Round(($internetPing.ResponseTime | Measure-Object -Average).Average, 2)
            Write-ColorOutput "  [OK] Internet: Reachable ($($script:healthReport.NetworkTests.Internet.Latency)ms)" -Level Success
        }
        else {
            $script:healthReport.Warnings += "Internet connectivity test failed"
            Write-ColorOutput "  [WARNING] Internet: Unreachable (may be firewalled)" -Level Warning
        }
    }
    catch {
        Write-ColorOutput "  [WARNING] Could not test internet: $($_.Exception.Message)" -Level Warning
    }
}

function Get-CertificateHealth {
    <#
    .SYNOPSIS
        Checks certificate expiration in local computer stores.
    #>

    if(-not $IncludeCertificates) { return }

    Write-Verbose "Checking certificate expiration..."
    $script:healthReport.Certificates.Enabled = $true

    try {
        $storePaths = @(
            'Cert:\LocalMachine\My',
            'Cert:\LocalMachine\WebHosting',
            'Cert:\LocalMachine\Remote Desktop'
        )

        $now = Get-Date
        $warningDate = $now.AddDays($CertificateWarningDays)

        foreach($storePath in $storePaths) {
            if(Test-Path $storePath) {
                $certs = Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue

                foreach($cert in $certs) {
                    $daysUntilExpiry = ($cert.NotAfter - $now).Days

                    $certInfo = @{
                        Subject = $cert.Subject
                        Issuer = $cert.Issuer
                        NotAfter = $cert.NotAfter
                        DaysUntilExpiry = $daysUntilExpiry
                        Thumbprint = $cert.Thumbprint
                        StorePath = $storePath
                        Status = 'OK'
                    }

                    if($cert.NotAfter -lt $now) {
                        $certInfo.Status = 'Expired'
                        $script:healthReport.Certificates.Expired++
                    }
                    elseif($cert.NotAfter -lt $warningDate) {
                        $certInfo.Status = 'Expiring'
                        $script:healthReport.Certificates.Expiring++
                    }

                    $script:healthReport.Certificates.Certificates += $certInfo
                }
            }
        }

        if($script:healthReport.Certificates.Expired -gt 0) {
            $script:healthReport.Certificates.Status = 'Critical'
            $script:healthReport.Status = 'Critical'
            $script:healthReport.Issues += "Expired certificates found: $($script:healthReport.Certificates.Expired)"
            Write-ColorOutput "  [CRITICAL] Certificates: $($script:healthReport.Certificates.Expired) expired" -Level Critical
        }
        elseif($script:healthReport.Certificates.Expiring -gt 0) {
            $script:healthReport.Certificates.Status = 'Warning'
            $script:healthReport.Warnings += "Certificates expiring soon: $($script:healthReport.Certificates.Expiring)"
            Write-ColorOutput "  [WARNING] Certificates: $($script:healthReport.Certificates.Expiring) expiring within $CertificateWarningDays days" -Level Warning
        }
        else {
            Write-ColorOutput "  [OK] Certificates: All valid" -Level Success
        }
    }
    catch {
        Write-ColorOutput "  [WARNING] Could not check certificates: $($_.Exception.Message)" -Level Warning
    }
}

function Get-ScheduledTasksHealth {
    <#
    .SYNOPSIS
        Monitors scheduled tasks for failures and disabled tasks.
    #>

    if(-not $IncludeScheduledTasks) { return }

    Write-Verbose "Checking scheduled tasks..."
    $script:healthReport.ScheduledTasks.Enabled = $true

    try {
        $tasks = Get-ScheduledTask -ErrorAction Stop |
            Where-Object {$_.TaskPath -notlike '\Microsoft\*'}

        foreach($task in $tasks) {
            $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue

            $taskData = @{
                Name = $task.TaskName
                Path = $task.TaskPath
                State = $task.State
                LastRunTime = $taskInfo.LastRunTime
                LastResult = $taskInfo.LastTaskResult
                NextRunTime = $taskInfo.NextRunTime
                Status = 'OK'
            }

            if($taskInfo.LastTaskResult -ne 0 -and $taskInfo.LastTaskResult -ne $null) {
                $taskData.Status = 'Failed'
                $script:healthReport.ScheduledTasks.Failed++
            }

            if($task.State -eq 'Disabled') {
                $taskData.Status = 'Disabled'
                $script:healthReport.ScheduledTasks.Disabled++
            }

            $script:healthReport.ScheduledTasks.Tasks += $taskData
        }

        if($script:healthReport.ScheduledTasks.Failed -gt 0) {
            $script:healthReport.ScheduledTasks.Status = 'Warning'
            $script:healthReport.Warnings += "Failed scheduled tasks: $($script:healthReport.ScheduledTasks.Failed)"
            Write-ColorOutput "  [WARNING] Scheduled Tasks: $($script:healthReport.ScheduledTasks.Failed) failed" -Level Warning
        }
        else {
            Write-ColorOutput "  [OK] Scheduled Tasks: $($tasks.Count) monitored, none failed" -Level Success
        }
    }
    catch {
        Write-ColorOutput "  [WARNING] Could not check scheduled tasks: $($_.Exception.Message)" -Level Warning
    }
}

function Get-IISHealth {
    <#
    .SYNOPSIS
        Monitors IIS application pools and websites (if IIS is installed).
    #>

    if(-not $CheckIIS -and -not $IncludeApplications) { return }

    Write-Verbose "Checking IIS health..."
    $script:healthReport.Applications.IIS.Enabled = $true

    try {
        Import-Module WebAdministration -ErrorAction Stop
        $script:healthReport.Applications.IIS.Installed = $true
    }
    catch {
        Write-ColorOutput "  [INFO] IIS not installed or WebAdministration module unavailable" -Level Info
        return
    }

    try {
        $iisService = Get-Service -Name W3SVC -ErrorAction SilentlyContinue
        if($iisService) {
            $script:healthReport.Applications.IIS.Running = ($iisService.Status -eq 'Running')
        }

        $appPools = Get-ChildItem IIS:\AppPools -ErrorAction Stop
        foreach($pool in $appPools) {
            $poolInfo = @{
                Name = $pool.Name
                State = $pool.State
                RuntimeVersion = $pool.ManagedRuntimeVersion
                PipelineMode = $pool.ManagedPipelineMode
                StartMode = $pool.StartMode
                Status = 'OK'
            }

            if($pool.State -ne 'Started') {
                $script:healthReport.Applications.IIS.FailedPools++
                $poolInfo.Status = 'Stopped'
            }

            $script:healthReport.Applications.IIS.ApplicationPools += $poolInfo
        }

        $sites = Get-ChildItem IIS:\Sites -ErrorAction Stop
        foreach($site in $sites) {
            $siteInfo = @{
                Name = $site.Name
                State = $site.State
                Bindings = ($site.Bindings.Collection | ForEach-Object { $_.BindingInformation }) -join '; '
                PhysicalPath = $site.PhysicalPath
                ApplicationPool = $site.ApplicationPool
                Status = 'OK'
            }

            if($site.State -ne 'Started') {
                $script:healthReport.Applications.IIS.StoppedSites++
                $siteInfo.Status = 'Stopped'
            }

            $script:healthReport.Applications.IIS.Websites += $siteInfo
        }

        if($script:healthReport.Applications.IIS.FailedPools -gt 0 -or
           $script:healthReport.Applications.IIS.StoppedSites -gt 0) {
            $script:healthReport.Applications.IIS.Status = 'Critical'
            $script:healthReport.Status = 'Critical'
            $script:healthReport.Issues += "IIS: $($script:healthReport.Applications.IIS.FailedPools) stopped pools, $($script:healthReport.Applications.IIS.StoppedSites) stopped sites"
            Write-ColorOutput "  [CRITICAL] IIS: Stopped application pools or websites detected" -Level Critical
        }
        elseif(-not $script:healthReport.Applications.IIS.Running) {
            $script:healthReport.Applications.IIS.Status = 'Critical'
            $script:healthReport.Status = 'Critical'
            $script:healthReport.Issues += "IIS service is not running"
            Write-ColorOutput "  [CRITICAL] IIS: Service not running" -Level Critical
        }
        else {
            Write-ColorOutput "  [OK] IIS: $($appPools.Count) pools, $($sites.Count) sites, all running" -Level Success
        }
    }
    catch {
        Write-ColorOutput "  [WARNING] Could not check IIS: $($_.Exception.Message)" -Level Warning
    }
}

function Get-SQLServerHealth {
    <#
    .SYNOPSIS
        Monitors SQL Server instances and databases (if SQL Server is installed).
    #>

    if(-not $CheckSQLServer -and -not $IncludeApplications) { return }

    Write-Verbose "Checking SQL Server health..."
    $script:healthReport.Applications.SQLServer.Enabled = $true

    $sqlService = Get-Service -Name 'MSSQLSERVER','MSSQL$*' -ErrorAction SilentlyContinue
    if(-not $sqlService) {
        Write-ColorOutput "  [INFO] SQL Server not installed" -Level Info
        return
    }

    $script:healthReport.Applications.SQLServer.Installed = $true
    $script:healthReport.Applications.SQLServer.Running = ($sqlService[0].Status -eq 'Running')

    if(-not $script:healthReport.Applications.SQLServer.Running) {
        $script:healthReport.Applications.SQLServer.Status = 'Critical'
        $script:healthReport.Status = 'Critical'
        $script:healthReport.Issues += "SQL Server service is not running"
        Write-ColorOutput "  [CRITICAL] SQL Server: Service not running" -Level Critical
        return
    }

    try {
        Write-ColorOutput "  [OK] SQL Server: Service running (detailed checks require SQL module)" -Level Success
    }
    catch {
        Write-ColorOutput "  [WARNING] Could not check SQL Server details: $($_.Exception.Message)" -Level Warning
    }
}

function Get-HyperVHealth {
    <#
    .SYNOPSIS
        Monitors Hyper-V host and virtual machines (if Hyper-V is installed).
    #>

    if(-not $CheckHyperV -and -not $IncludeApplications) { return }

    Write-Verbose "Checking Hyper-V health..."
    $script:healthReport.Applications.HyperV.Enabled = $true

    try {
        Import-Module Hyper-V -ErrorAction Stop
        $script:healthReport.Applications.HyperV.Installed = $true
    }
    catch {
        Write-ColorOutput "  [INFO] Hyper-V not installed" -Level Info
        return
    }

    try {
        $vmmsService = Get-Service -Name vmms -ErrorAction SilentlyContinue
        if($vmmsService) {
            $script:healthReport.Applications.HyperV.Running = ($vmmsService.Status -eq 'Running')
        }

        if(-not $script:healthReport.Applications.HyperV.Running) {
            $script:healthReport.Applications.HyperV.Status = 'Critical'
            $script:healthReport.Status = 'Critical'
            $script:healthReport.Issues += "Hyper-V service is not running"
            Write-ColorOutput "  [CRITICAL] Hyper-V: Service not running" -Level Critical
            return
        }

        $vms = Get-VM -ErrorAction Stop
        foreach($vm in $vms) {
            $vmInfo = @{
                Name = $vm.Name
                State = $vm.State
                CPUUsage = $vm.CPUUsage
                MemoryMB = [math]::Round($vm.MemoryAssigned / 1MB, 0)
                Uptime = $vm.Uptime
                Status = if($vm.State -eq 'Running') { 'OK' } else { 'Stopped' }
            }

            $script:healthReport.Applications.HyperV.VirtualMachines += $vmInfo
        }

        $runningVMs = ($vms | Where-Object {$_.State -eq 'Running'}).Count
        Write-ColorOutput "  [OK] Hyper-V: $($vms.Count) VMs ($runningVMs running)" -Level Success
    }
    catch {
        Write-ColorOutput "  [WARNING] Could not check Hyper-V: $($_.Exception.Message)" -Level Warning
    }
}

function Export-JSONReport {
    <#
    .SYNOPSIS
        Exports health report to JSON format.
    #>

    $reportPath = "$env:USERPROFILE\Desktop\ServerHealth_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"

    try {
        $json = $script:healthReport | ConvertTo-Json -Depth 10
        $json | Out-File -FilePath $reportPath -Encoding UTF8

        Write-ColorOutput "`nJSON report exported to: $reportPath" -Level Success
        return $reportPath
    }
    catch {
        Write-ColorOutput "Failed to export JSON: $($_.Exception.Message)" -Level Error
    }
}

function Send-EmailReport {
    <#
    .SYNOPSIS
        Sends health report via email with HTML body and optional attachments.
    #>
    param(
        [string]$HTMLReportPath
    )

    if(-not $EmailReport) { return }

    if(-not $SMTPServer -or -not $EmailFrom -or -not $EmailTo) {
        Write-ColorOutput "`n[WARNING] Email reporting requires -SMTPServer, -EmailFrom, and -EmailTo parameters" -Level Warning
        return
    }

    Write-Verbose "Sending email report..."

    try {
        $emailBody = @"
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; }
        .status-critical { color: red; font-weight: bold; }
        .status-warning { color: orange; font-weight: bold; }
        .status-healthy { color: green; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th { background-color: #4CAF50; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
    </style>
</head>
<body>
    <h2>Server Health Report - $($script:healthReport.ServerName)</h2>
    <p><strong>Status:</strong> <span class="status-$($script:healthReport.Status.ToLower())">$($script:healthReport.Status.ToUpper())</span></p>
    <p><strong>Scan Time:</strong> $($script:healthReport.ScanTime)</p>

    <h3>Summary</h3>
    <table>
        <tr><th>Component</th><th>Status</th><th>Details</th></tr>
        <tr><td>CPU</td><td>$($script:healthReport.CPU.Status)</td><td>$($script:healthReport.CPU.AverageCPU)% average</td></tr>
        <tr><td>Memory</td><td>$($script:healthReport.Memory.Status)</td><td>$($script:healthReport.Memory.UsedPercent)% used</td></tr>
        <tr><td>Disks</td><td>$(($script:healthReport.Disks | Where-Object {$_.Status -ne 'OK'}).Count) issues</td><td>$($script:healthReport.Disks.Count) volumes</td></tr>
        <tr><td>Services</td><td>$(($script:healthReport.Services | Where-Object {$_.Health -ne 'OK'}).Count) issues</td><td>$($script:healthReport.Services.Count) monitored</td></tr>
    </table>

    $(if($script:healthReport.Issues.Count -gt 0) {
        "<h3>Critical Issues</h3><ul>"
        $script:healthReport.Issues | ForEach-Object { "<li>$_</li>" }
        "</ul>"
    })

    $(if($script:healthReport.Warnings.Count -gt 0) {
        "<h3>Warnings</h3><ul>"
        $script:healthReport.Warnings | ForEach-Object { "<li>$_</li>" }
        "</ul>"
    })

    <p><em>Full report attached. Generated by Monitor-ServerHealth.ps1</em></p>
</body>
</html>
"@

        $mailParams = @{
            SmtpServer = $SMTPServer
            Port = $SMTPPort
            From = $EmailFrom
            To = $EmailTo
            Subject = $EmailSubject
            Body = $emailBody
            BodyAsHtml = $true
        }

        if($UseSSL) {
            $mailParams.UseSsl = $true
        }

        if($SMTPCredential) {
            $mailParams.Credential = $SMTPCredential
        }

        if($HTMLReportPath -and (Test-Path $HTMLReportPath)) {
            $mailParams.Attachments = $HTMLReportPath
        }

        Send-MailMessage @mailParams -ErrorAction Stop

        Write-ColorOutput "`nEmail report sent to: $($EmailTo -join ', ')" -Level Success
    }
    catch {
        Write-ColorOutput "`n[ERROR] Failed to send email: $($_.Exception.Message)" -Level Error
    }
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

        $(if($script:healthReport.DiskIO.Enabled) {
            "<h2>Disk I/O Performance</h2>
            <div class='metric'>
                <strong>Average Reads/sec:</strong> $($script:healthReport.DiskIO.AverageReadsPerSec)<br>
                <strong>Average Writes/sec:</strong> $($script:healthReport.DiskIO.AverageWritesPerSec)<br>
                <strong>Read Latency:</strong> $($script:healthReport.DiskIO.AverageReadLatencyMs) ms<br>
                <strong>Write Latency:</strong> $($script:healthReport.DiskIO.AverageWriteLatencyMs) ms<br>
                <strong>Queue Length:</strong> $($script:healthReport.DiskIO.AverageQueueLength)<br>
                <strong>Status:</strong> <span class='$($script:healthReport.DiskIO.Status.ToLower())'>$($script:healthReport.DiskIO.Status)</span>
            </div>"
        })

        $(if($script:healthReport.WindowsUpdate.Enabled) {
            "<h2>Windows Update</h2>
            <div class='metric'>
                <strong>Pending Updates:</strong> $($script:healthReport.WindowsUpdate.UpdatesPending)<br>
                <strong>Failed Updates:</strong> $($script:healthReport.WindowsUpdate.UpdatesFailed)<br>
                <strong>Reboot Required:</strong> $($script:healthReport.WindowsUpdate.RebootRequired)<br>
                <strong>Service Status:</strong> $($script:healthReport.WindowsUpdate.WindowsUpdateService)<br>
                <strong>Last Update:</strong> $($script:healthReport.WindowsUpdate.LastSuccessfulUpdate)
            </div>"
            if($script:healthReport.WindowsUpdate.PendingUpdates.Count -gt 0) {
                "<h3>Pending Updates</h3><table><tr><th>Title</th><th>Severity</th><th>KB</th></tr>"
                foreach($update in ($script:healthReport.WindowsUpdate.PendingUpdates | Select-Object -First 10)) {
                    "<tr><td>$($update.Title)</td><td>$($update.Severity)</td><td>$($update.KB)</td></tr>"
                }
                "</table>"
            }
        })

        $(if($script:healthReport.Security.Enabled) {
            "<h2>Security Status</h2>
            <h3>Windows Firewall</h3>
            <div class='metric'>
                <strong>Domain Profile:</strong> $($script:healthReport.Security.Firewall.DomainProfile)<br>
                <strong>Private Profile:</strong> $($script:healthReport.Security.Firewall.PrivateProfile)<br>
                <strong>Public Profile:</strong> $($script:healthReport.Security.Firewall.PublicProfile)
            </div>
            <h3>Windows Defender</h3>
            <div class='metric'>
                <strong>Service Running:</strong> $($script:healthReport.Security.Defender.ServiceRunning)<br>
                <strong>Real-Time Protection:</strong> $($script:healthReport.Security.Defender.RealTimeProtection)<br>
                <strong>Signature Age:</strong> $($script:healthReport.Security.Defender.SignatureAge) days<br>
                <strong>Last Scan:</strong> $($script:healthReport.Security.Defender.LastScan)
            </div>
            <h3>Failed Login Attempts (24h)</h3>
            <div class='metric'><strong>Total:</strong> $($script:healthReport.Security.FailedLogins.Last24Hours)</div>"
            if($script:healthReport.Security.FailedLogins.RecentAttempts.Count -gt 0) {
                "<table><tr><th>Time</th><th>User</th><th>Workstation</th><th>IP</th></tr>"
                foreach($login in $script:healthReport.Security.FailedLogins.RecentAttempts) {
                    "<tr><td>$($login.TimeCreated)</td><td>$($login.TargetUserName)</td><td>$($login.WorkstationName)</td><td>$($login.IpAddress)</td></tr>"
                }
                "</table>"
            }
        })

        $(if($script:healthReport.NetworkTests.Enabled) {
            "<h2>Network Connectivity</h2>
            <table>
                <tr><th>Test</th><th>Target</th><th>Status</th><th>Latency</th></tr>
                <tr>
                    <td>Gateway</td>
                    <td>$($script:healthReport.NetworkTests.Gateway.IP)</td>
                    <td class='$(if($script:healthReport.NetworkTests.Gateway.Reachable){'success'}else{'error'})'>
                        $(if($script:healthReport.NetworkTests.Gateway.Reachable){'Reachable'}else{'Unreachable'})
                    </td>
                    <td>$($script:healthReport.NetworkTests.Gateway.Latency) ms</td>
                </tr>
                <tr>
                    <td>DNS</td>
                    <td>$($script:healthReport.NetworkTests.DNS.PrimaryServer)</td>
                    <td class='$(if($script:healthReport.NetworkTests.DNS.ResolutionWorking){'success'}else{'error'})'>
                        $(if($script:healthReport.NetworkTests.DNS.ResolutionWorking){'Working'}else{'Failing'})
                    </td>
                    <td>-</td>
                </tr>
                <tr>
                    <td>Internet</td>
                    <td>$($script:healthReport.NetworkTests.Internet.Target)</td>
                    <td class='$(if($script:healthReport.NetworkTests.Internet.Reachable){'success'}else{'warning'})'>
                        $(if($script:healthReport.NetworkTests.Internet.Reachable){'Reachable'}else{'Unreachable'})
                    </td>
                    <td>$($script:healthReport.NetworkTests.Internet.Latency) ms</td>
                </tr>
            </table>"
        })

        $(if($script:healthReport.Certificates.Enabled -and $script:healthReport.Certificates.Certificates.Count -gt 0) {
            "<h2>Certificate Status</h2>
            <div class='metric'>
                <strong>Expired:</strong> $($script:healthReport.Certificates.Expired)<br>
                <strong>Expiring Soon:</strong> $($script:healthReport.Certificates.Expiring)
            </div>
            <table>
                <tr><th>Subject</th><th>Expires</th><th>Days</th><th>Status</th></tr>"
                foreach($cert in ($script:healthReport.Certificates.Certificates | Sort-Object DaysUntilExpiry | Select-Object -First 10)) {
                    $statusClass = switch($cert.Status) {
                        'Expired' { 'critical' }
                        'Expiring' { 'warning' }
                        default { 'success' }
                    }
                    "<tr>
                        <td>$($cert.Subject)</td>
                        <td>$($cert.NotAfter.ToString('yyyy-MM-dd'))</td>
                        <td>$($cert.DaysUntilExpiry)</td>
                        <td class='$statusClass'>$($cert.Status)</td>
                    </tr>"
                }
                "</table>"
        })

        $(if($script:healthReport.ScheduledTasks.Enabled -and $script:healthReport.ScheduledTasks.Tasks.Count -gt 0) {
            "<h2>Scheduled Tasks</h2>
            <div class='metric'>
                <strong>Total Tasks:</strong> $($script:healthReport.ScheduledTasks.Tasks.Count)<br>
                <strong>Failed:</strong> $($script:healthReport.ScheduledTasks.Failed)<br>
                <strong>Disabled:</strong> $($script:healthReport.ScheduledTasks.Disabled)
            </div>"
            $failedTasks = $script:healthReport.ScheduledTasks.Tasks | Where-Object {$_.Status -eq 'Failed'}
            if($failedTasks.Count -gt 0) {
                "<h3>Failed Tasks</h3>
                <table><tr><th>Name</th><th>Last Run</th><th>Result</th></tr>"
                foreach($task in $failedTasks) {
                    "<tr><td>$($task.Name)</td><td>$($task.LastRunTime)</td><td>$($task.LastResult)</td></tr>"
                }
                "</table>"
            }
        })

        $(if($script:healthReport.Applications.IIS.Enabled) {
            "<h2>IIS Application Pools & Websites</h2>
            <div class='metric'>
                <strong>Application Pools:</strong> $($script:healthReport.Applications.IIS.ApplicationPools.Count)<br>
                <strong>Stopped Pools:</strong> $($script:healthReport.Applications.IIS.FailedPools)<br>
                <strong>Websites:</strong> $($script:healthReport.Applications.IIS.Websites.Count)<br>
                <strong>Stopped Sites:</strong> $($script:healthReport.Applications.IIS.StoppedSites)
            </div>"
        })

        $(if($script:healthReport.Applications.SQLServer.Enabled) {
            "<h2>SQL Server</h2>
            <div class='metric'>
                <strong>Installed:</strong> $($script:healthReport.Applications.SQLServer.Installed)<br>
                <strong>Running:</strong> $($script:healthReport.Applications.SQLServer.Running)<br>
                <strong>Status:</strong> <span class='$($script:healthReport.Applications.SQLServer.Status.ToLower())'>$($script:healthReport.Applications.SQLServer.Status)</span>
            </div>"
        })

        $(if($script:healthReport.Applications.HyperV.Enabled) {
            "<h2>Hyper-V</h2>
            <div class='metric'>
                <strong>Total VMs:</strong> $($script:healthReport.Applications.HyperV.VirtualMachines.Count)<br>
                <strong>Running VMs:</strong> $(($script:healthReport.Applications.HyperV.VirtualMachines | Where-Object {$_.State -eq 'Running'}).Count)
            </div>"
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

# Check if running in interactive mode (no significant parameters provided)
$interactiveModeParams = @('IncludeDiskIO', 'IncludeWindowsUpdate', 'IncludeSecurity', 'IncludeNetworkTests',
                           'IncludeApplications', 'IncludeCertificates', 'IncludeScheduledTasks',
                           'CheckIIS', 'CheckSQLServer', 'CheckHyperV', 'ExportJSON', 'ShowProgress')

$hasOptionalParams = $false
foreach($param in $interactiveModeParams) {
    if(Get-Variable -Name $param -ValueOnly -ErrorAction SilentlyContinue) {
        $hasOptionalParams = $true
        break
    }
}

if(-not $hasOptionalParams -and -not $ExportReport -and -not $EmailReport) {
    Show-InteractiveMenu
}

# Calculate total steps for progress tracking
$totalSteps = 7  # Base checks (CPU, Memory, Disk, Services, Events, Network, SystemInfo)
if($IncludeDiskIO) { $totalSteps++ }
if($IncludeWindowsUpdate) { $totalSteps++ }
if($IncludeSecurity) { $totalSteps++ }
if($IncludeNetworkTests) { $totalSteps++ }
if($IncludeCertificates) { $totalSteps++ }
if($IncludeScheduledTasks) { $totalSteps++ }
if($CheckIIS -or $IncludeApplications) { $totalSteps += 3 }  # IIS, SQL, Hyper-V
$totalSteps++  # Advanced metrics (always runs)

$currentStep = 0

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Server Health Monitor" -ForegroundColor Cyan
Write-Host "  Alert Threshold: $AlertThreshold" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Core checks
Write-Host "Checking CPU..." -ForegroundColor Cyan
Update-Progress -Current (++$currentStep) -Total $totalSteps -Activity "Server Health Check" -Status "Checking CPU..."
Get-CPUHealth

Write-Host "`nChecking Memory..." -ForegroundColor Cyan
Update-Progress -Current (++$currentStep) -Total $totalSteps -Activity "Server Health Check" -Status "Checking Memory..."
Get-MemoryHealth

Write-Host "`nChecking Disk Space..." -ForegroundColor Cyan
Update-Progress -Current (++$currentStep) -Total $totalSteps -Activity "Server Health Check" -Status "Checking Disks..."
Get-DiskHealth

# Optional: Disk I/O
if($IncludeDiskIO) {
    Write-Host "`nChecking Disk I/O..." -ForegroundColor Cyan
    Update-Progress -Current (++$currentStep) -Total $totalSteps -Activity "Server Health Check" -Status "Checking Disk I/O..."
    Get-DiskIOHealth
}

Write-Host "`nChecking Services..." -ForegroundColor Cyan
Update-Progress -Current (++$currentStep) -Total $totalSteps -Activity "Server Health Check" -Status "Checking Services..."
Get-ServiceHealth

Write-Host "`nChecking Event Logs..." -ForegroundColor Cyan
Update-Progress -Current (++$currentStep) -Total $totalSteps -Activity "Server Health Check" -Status "Checking Event Logs..."
Get-EventLogHealth

Write-Host "`nChecking Network..." -ForegroundColor Cyan
Update-Progress -Current (++$currentStep) -Total $totalSteps -Activity "Server Health Check" -Status "Checking Network..."
Get-NetworkHealth

# Advanced performance metrics (always run)
Get-AdvancedPerformanceMetrics

# Optional: Windows Update
if($IncludeWindowsUpdate) {
    Write-Host "`nChecking Windows Update..." -ForegroundColor Cyan
    Update-Progress -Current (++$currentStep) -Total $totalSteps -Activity "Server Health Check" -Status "Checking Windows Update..."
    Get-WindowsUpdateHealth
}

# Optional: Security
if($IncludeSecurity) {
    Write-Host "`nChecking Security..." -ForegroundColor Cyan
    Update-Progress -Current (++$currentStep) -Total $totalSteps -Activity "Server Health Check" -Status "Checking Security..."
    Get-SecurityHealth
}

# Optional: Network Tests
if($IncludeNetworkTests) {
    Write-Host "`nTesting Network Connectivity..." -ForegroundColor Cyan
    Update-Progress -Current (++$currentStep) -Total $totalSteps -Activity "Server Health Check" -Status "Testing Network..."
    Get-NetworkConnectivityHealth
}

# Optional: Certificates
if($IncludeCertificates) {
    Write-Host "`nChecking Certificates..." -ForegroundColor Cyan
    Update-Progress -Current (++$currentStep) -Total $totalSteps -Activity "Server Health Check" -Status "Checking Certificates..."
    Get-CertificateHealth
}

# Optional: Scheduled Tasks
if($IncludeScheduledTasks) {
    Write-Host "`nChecking Scheduled Tasks..." -ForegroundColor Cyan
    Update-Progress -Current (++$currentStep) -Total $totalSteps -Activity "Server Health Check" -Status "Checking Scheduled Tasks..."
    Get-ScheduledTasksHealth
}

# Optional: Applications
if($CheckIIS -or $IncludeApplications) {
    Write-Host "`nChecking IIS..." -ForegroundColor Cyan
    Update-Progress -Current (++$currentStep) -Total $totalSteps -Activity "Server Health Check" -Status "Checking IIS..."
    Get-IISHealth
}

if($CheckSQLServer -or $IncludeApplications) {
    Write-Host "`nChecking SQL Server..." -ForegroundColor Cyan
    Update-Progress -Current (++$currentStep) -Total $totalSteps -Activity "Server Health Check" -Status "Checking SQL Server..."
    Get-SQLServerHealth
}

if($CheckHyperV -or $IncludeApplications) {
    Write-Host "`nChecking Hyper-V..." -ForegroundColor Cyan
    Update-Progress -Current (++$currentStep) -Total $totalSteps -Activity "Server Health Check" -Status "Checking Hyper-V..."
    Get-HyperVHealth
}

Write-Host "`nGathering System Info..." -ForegroundColor Cyan
Update-Progress -Current (++$currentStep) -Total $totalSteps -Activity "Server Health Check" -Status "Gathering System Info..."
Get-SystemInfo

# Complete progress
if($ShowProgress) {
    Write-Progress -Activity "Server Health Check" -Completed
}

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

# Export reports
$htmlPath = $null
if($ExportReport) {
    Write-Host "`nGenerating HTML report..." -ForegroundColor Cyan
    $htmlPath = Export-HTMLReport
}

if($ExportJSON) {
    Write-Host "Generating JSON report..." -ForegroundColor Cyan
    Export-JSONReport
}

if($EmailReport) {
    Write-Host "Sending email report..." -ForegroundColor Cyan
    Send-EmailReport -HTMLReportPath $htmlPath
}

Write-Host "`n========================================`n" -ForegroundColor Cyan
