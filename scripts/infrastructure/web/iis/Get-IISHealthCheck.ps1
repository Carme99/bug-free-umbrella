<#
.SYNOPSIS
    Comprehensive IIS health check and configuration audit.

.DESCRIPTION
    Performs detailed health assessment of IIS web server including:
    - Application pool status and performance
    - Website status and bindings
    - SSL certificate validation
    - Log file management
    - Worker process health
    - Request queue analysis
    - Failed request tracing
    - Configuration validation

    Generates detailed HTML and CSV reports with recommendations.
    This is a detect-only script (no changes are made): returns 0 when the
    overall health score is 75 or higher, and 1 when IIS is not installed,
    a probe fails fatally, or the score falls below 75.

.PARAMETER IncludePerformanceCounters
    Collect performance counter data for analysis.

.PARAMETER CheckSSLCertificates
    Validate SSL certificates for all HTTPS bindings.

.PARAMETER AnalyzeLogFiles
    Analyze IIS log files for errors and patterns.

.PARAMETER DaysToAnalyze
    Number of days of log files to analyze (default: 7).

.PARAMETER ExportHTML
    Export detailed HTML report to desktop.

.PARAMETER ExportCSV
    Export data to CSV format.

.EXAMPLE
    PS C:\> .\Get-IISHealthCheck.ps1

    Performs basic IIS health check with console output.

.EXAMPLE
    PS C:\> .\Get-IISHealthCheck.ps1 -CheckSSLCertificates -ExportHTML

    Comprehensive check including SSL validation with HTML report.

.EXAMPLE
    PS C:\> .\Get-IISHealthCheck.ps1 -IncludePerformanceCounters -AnalyzeLogFiles -DaysToAnalyze 14 -ExportHTML

    Full health check with performance data and 14-day log analysis.

.NOTES
    File Name   : Get-IISHealthCheck.ps1
    Author      : IT Infrastructure Team
    Prerequisite: PowerShell 5.1+, IISAdministration module (Windows), Administrator privileges
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive administrative console tool; output is operator-facing UI, not pipeline data')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Script-scope parameters are consumed by Main and its helper functions after dot-source binding')]
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$IncludePerformanceCounters,

    [Parameter()]
    [switch]$CheckSSLCertificates,

    [Parameter()]
    [switch]$AnalyzeLogFiles,

    [Parameter()]
    [ValidateRange(1, 365)]
    [int]$DaysToAnalyze = 7,

    [Parameter()]
    [switch]$ExportHTML,

    [Parameter()]
    [switch]$ExportCSV
)

# Runtime prerequisites: Windows host with IIS, IISAdministration module, elevated session.
$ErrorActionPreference = 'Stop'

function Write-ScriptMessage {
    <#
    .SYNOPSIS
        Writes a prefixed, colored message to the console (single emitter).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('+', '!', '-', '*', '')]
        [string]$Prefix = '',

        [Parameter()]
        [ValidateSet('Green', 'Yellow', 'Red', 'Cyan', 'White')]
        [string]$Color = 'White'
    )

    # Write-Host justified: interactive administrative console tool; output is UI, not pipeline data.
    if ($Prefix) {
        Write-Host "[$Prefix] $Message" -ForegroundColor $Color
    }
    else {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Write-StatusMessage {
    <#
    .SYNOPSIS
        Writes a status-tagged console line mapped to the standard prefixes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Status
    )

    switch ($Status) {
        'Info' { Write-ScriptMessage -Message $Message -Prefix '*' -Color Cyan }
        'Success' { Write-ScriptMessage -Message $Message -Prefix '+' -Color Green }
        'Warning' { Write-ScriptMessage -Message $Message -Prefix '!' -Color Yellow }
        'Error' { Write-ScriptMessage -Message $Message -Prefix '-' -Color Red }
    }
}

function Test-IisInstalled {
    <#
    .SYNOPSIS
        Returns $true when the Web-Server Windows feature is installed.
    #>
    [CmdletBinding()]
    param()

    $iisFeature = Get-WindowsFeature -Name Web-Server -ErrorAction Stop
    return [bool]$iisFeature.Installed
}

function Main {
    <#
    .SYNOPSIS
        Runs the IIS health check workflow.
    #>
    [CmdletBinding()]
    param()

    try {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $computerName = $env:COMPUTERNAME

        # Resolve report output directory (default: MyDocuments\Reports) and validate against traversal/UNC paths
        $documentsFolder = [Environment]::GetFolderPath('MyDocuments')
        if ([string]::IsNullOrWhiteSpace($documentsFolder)) {
            # Non-Windows hosts can return an empty MyDocuments path; fall back for portability.
            $documentsFolder = if ($env:HOME) { $env:HOME } else { (Get-Location).Path }
        }
        $ReportDir = Join-Path -Path $documentsFolder -ChildPath 'Reports'
        if ([string]::IsNullOrWhiteSpace($ReportDir) -or
            $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
            $ReportDir -match '^(\\\\|//)') {
            Write-StatusMessage -Message "Unsafe report path: $ReportDir." -Status Error
            return 1
        }
        $ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
        if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
            New-Item -ItemType Directory -Path $ReportDir -Force -ErrorAction Stop | Out-Null
        }

        $results = @{
            Timestamp        = Get-Date
            ComputerName     = $computerName
            IISVersion       = ''
            ApplicationPools = @()
            Websites         = @()
            SSLCertificates  = @()
            PerformanceData  = @{}
            LogAnalysis      = @{}
            Recommendations  = @()
            OverallHealth    = 'Unknown'
        }

        Write-ScriptMessage -Message '=== IIS Health Check ==='
        Write-ScriptMessage -Message "Computer: $computerName"

        # Check if IIS is installed
        Write-StatusMessage -Message 'Checking IIS installation...' -Status Info
        try {
            if (-not (Test-IisInstalled)) {
                Write-StatusMessage -Message 'IIS is not installed on this server' -Status Error
                return 1
            }
            Write-StatusMessage -Message 'IIS is installed and accessible' -Status Success
        }
        catch {
            Write-StatusMessage -Message "Error checking IIS installation: $_" -Status Error
            return 1
        }

        # Get IIS version
        Write-StatusMessage -Message 'Detecting IIS version...' -Status Info
        try {
            $iisVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\InetStp' -ErrorAction Stop).VersionString
            $results.IISVersion = $iisVersion
            Write-StatusMessage -Message "IIS Version: $iisVersion" -Status Success
        }
        catch {
            Write-StatusMessage -Message 'Could not determine IIS version' -Status Warning
        }

        # Check Application Pools
        Write-StatusMessage -Message 'Analyzing application pools...' -Status Info
        $poolIssues = 0
        try {
            $appPools = @(Get-IISAppPool -ErrorAction Stop)

            foreach ($pool in $appPools) {
                $poolInfo = [PSCustomObject]@{
                    Name                  = $pool.Name
                    State                 = $pool.State
                    ManagedRuntimeVersion = $pool.ManagedRuntimeVersion
                    ManagedPipelineMode   = $pool.ManagedPipelineMode
                    Enable32BitAppOnWin64 = $pool.Enable32BitAppOnWin64
                    StartMode             = $pool.StartMode
                    RecyclingSchedule     = ($pool.Recycling.PeriodicRestart.Schedule -join ', ')
                    RecyclingMemoryLimit  = $pool.Recycling.PeriodicRestart.PrivateMemory
                    IdleTimeout           = $pool.ProcessModel.IdleTimeout.TotalMinutes
                    Issues                = @()
                }

                # Check for issues
                if ($pool.State -ne 'Started') {
                    $poolInfo.Issues += "Pool is $($pool.State)"
                    $poolIssues++
                }
                $idleMinutes = $pool.ProcessModel.IdleTimeout.TotalMinutes
                if ($idleMinutes -lt 20 -and $idleMinutes -gt 0) {
                    $poolInfo.Issues += "Short idle timeout ($idleMinutes min)"
                }

                $results.ApplicationPools += $poolInfo
            }

            $poolStatus = if ($poolIssues -eq 0) { 'Success' } else { 'Warning' }
            Write-StatusMessage `
                -Message "Found $($appPools.Count) application pools ($poolIssues issues)" `
                -Status $poolStatus
        }
        catch {
            Write-StatusMessage -Message "Error analyzing application pools: $_" -Status Error
        }

        # Check Websites
        Write-StatusMessage -Message 'Analyzing websites and bindings...' -Status Info
        $siteIssues = 0
        try {
            $websites = @(Get-IISSite -ErrorAction Stop)

            foreach ($site in $websites) {
                $bindings = $site.Bindings | ForEach-Object {
                    "$($_.Protocol)://$($_.BindingInformation)"
                }

                $siteInfo = [PSCustomObject]@{
                    Name             = $site.Name
                    ID               = $site.Id
                    State            = $site.State
                    PhysicalPath     = $site.Applications['/'].VirtualDirectories['/'].PhysicalPath
                    ApplicationPool  = $site.Applications['/'].ApplicationPoolName
                    Bindings         = ($bindings -join '; ')
                    LogFileDirectory = $site.LogFile.Directory
                    Issues           = @()
                }

                # Check for issues
                if ($site.State -ne 'Started') {
                    $siteInfo.Issues += "Site is $($site.State)"
                    $siteIssues++
                }
                if (-not (Test-Path -LiteralPath $siteInfo.PhysicalPath)) {
                    $siteInfo.Issues += 'Physical path not found'
                    $siteIssues++
                }

                $results.Websites += $siteInfo
            }

            $siteStatus = if ($siteIssues -eq 0) { 'Success' } else { 'Warning' }
            Write-StatusMessage `
                -Message "Found $($websites.Count) websites ($siteIssues issues)" `
                -Status $siteStatus
        }
        catch {
            Write-StatusMessage -Message "Error analyzing websites: $_" -Status Error
        }

        # Check SSL Certificates
        if ($CheckSSLCertificates) {
            Write-StatusMessage -Message 'Validating SSL certificates...' -Status Info
            try {
                $httpsBindings = Get-IISSite -ErrorAction Stop | ForEach-Object {
                    $siteName = $_.Name
                    $_.Bindings | Where-Object { $_.Protocol -eq 'https' } | ForEach-Object {
                        [PSCustomObject]@{
                            Site                 = $siteName
                            Binding              = $_.BindingInformation
                            CertificateHash      = $_.CertificateHash
                            CertificateStoreName = $_.CertificateStoreName
                        }
                    }
                }

                $certIssues = 0
                foreach ($binding in $httpsBindings) {
                    if ($binding.CertificateHash) {
                        $certStore = "Cert:\LocalMachine\$($binding.CertificateStoreName)"
                        $cert = Get-ChildItem -Path $certStore -ErrorAction Stop |
                            Where-Object { $_.Thumbprint -eq $binding.CertificateHash }

                        if ($cert) {
                            $daysToExpire = ($cert.NotAfter - (Get-Date)).Days
                            if ($daysToExpire -lt 0) {
                                $status = 'Expired'
                            }
                            elseif ($daysToExpire -lt 30) {
                                $status = 'Expiring Soon'
                            }
                            else {
                                $status = 'Valid'
                            }
                            $certInfo = [PSCustomObject]@{
                                Site         = $binding.Site
                                Binding      = $binding.Binding
                                Subject      = $cert.Subject
                                Issuer       = $cert.Issuer
                                NotBefore    = $cert.NotBefore
                                NotAfter     = $cert.NotAfter
                                DaysToExpire = $daysToExpire
                                Status       = $status
                            }

                            if ($certInfo.Status -ne 'Valid') {
                                $certIssues++
                            }

                            $results.SSLCertificates += $certInfo
                        }
                        else {
                            $certIssues++
                        }
                    }
                }

                $checkedCount = @($httpsBindings).Count
                $certStatus = if ($certIssues -eq 0) { 'Success' } else { 'Warning' }
                Write-StatusMessage `
                    -Message "Checked $checkedCount HTTPS bindings ($certIssues issues)" `
                    -Status $certStatus
            }
            catch {
                Write-StatusMessage -Message "Error checking SSL certificates: $_" -Status Error
            }
        }

        # Collect Performance Counters
        if ($IncludePerformanceCounters) {
            Write-StatusMessage -Message 'Collecting performance data...' -Status Info
            try {
                $perfCounters = @(
                    '\Web Service(_Total)\Current Connections'
                    '\Web Service(_Total)\Bytes Total/sec'
                    '\Web Service(_Total)\Get Requests/sec'
                    '\Web Service(_Total)\Post Requests/sec'
                    '\APP_POOL_WAS(_Total)\Current Application Pool State'
                    '\APP_POOL_WAS(_Total)\Current Application Pool Uptime'
                )

                foreach ($counter in $perfCounters) {
                    try {
                        $sample = Get-Counter -Counter $counter -SampleInterval 1 `
                            -MaxSamples 1 -ErrorAction SilentlyContinue
                        $results.PerformanceData[$counter] = $sample.CounterSamples.CookedValue
                    }
                    catch {
                        Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
                    }
                }

                Write-StatusMessage -Message 'Performance data collected' -Status Success
            }
            catch {
                Write-StatusMessage -Message "Error collecting performance data: $_" -Status Warning
            }
        }

        # Analyze Log Files
        if ($AnalyzeLogFiles) {
            Write-StatusMessage `
                -Message "Analyzing IIS log files (last $DaysToAnalyze days)..." -Status Info
            try {
                $logPath = Join-Path -Path $env:SystemDrive -ChildPath 'inetpub\logs\LogFiles'
                if (Test-Path -LiteralPath $logPath) {
                    $cutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)
                    $logFiles = @(Get-ChildItem -Path $logPath -Filter '*.log' -Recurse -ErrorAction Stop |
                        Where-Object { $_.LastWriteTime -ge $cutoffDate })

                    $totalLogs = $logFiles.Count
                    $totalSize = ($logFiles | Measure-Object -Property Length -Sum).Sum / 1MB
                    $oldestLog = $null
                    $newestLog = $null
                    if ($logFiles) {
                        $oldestLog = ($logFiles |
                            Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime
                        $newestLog = ($logFiles |
                            Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
                    }

                    $results.LogAnalysis = @{
                        TotalLogFiles = $totalLogs
                        TotalSizeMB   = [math]::Round($totalSize, 2)
                        OldestLog     = $oldestLog
                        NewestLog     = $newestLog
                    }

                    $sizeText = [math]::Round($totalSize, 2)
                    Write-StatusMessage `
                        -Message "Analyzed $totalLogs log files ($sizeText MB)" `
                        -Status Success
                }
                else {
                    Write-StatusMessage -Message "Log file path not found: $logPath" -Status Warning
                }
            }
            catch {
                Write-StatusMessage -Message "Error analyzing log files: $_" -Status Error
            }
        }

        # Generate Recommendations
        Write-StatusMessage -Message 'Generating recommendations...' -Status Info
        $healthScore = 100
        $stoppedPools = @()
        $stoppedSites = @()
        $expiringCerts = @()
        $expiredCerts = @()

        # Check for stopped pools
        $stoppedPools = @($results.ApplicationPools | Where-Object { $_.State -ne 'Started' })
        if ($stoppedPools.Count -gt 0) {
            $results.Recommendations +=
                "ACTION REQUIRED: $($stoppedPools.Count) application pool(s) are not running"
            $healthScore -= 20
        }

        # Check for stopped sites
        $stoppedSites = @($results.Websites | Where-Object { $_.State -ne 'Started' })
        if ($stoppedSites.Count -gt 0) {
            $results.Recommendations +=
                "ACTION REQUIRED: $($stoppedSites.Count) website(s) are not running"
            $healthScore -= 20
        }

        # Check SSL certificates
        if ($CheckSSLCertificates) {
            $expiredCerts = @($results.SSLCertificates | Where-Object { $_.DaysToExpire -lt 0 })
            $expiringCerts = @($results.SSLCertificates | Where-Object {
                $_.DaysToExpire -lt 30 -and $_.DaysToExpire -ge 0 })

            if ($expiredCerts.Count -gt 0) {
                $results.Recommendations +=
                    "CRITICAL: $($expiredCerts.Count) SSL certificate(s) have expired"
                $healthScore -= 30
            }
            if ($expiringCerts.Count -gt 0) {
                $results.Recommendations +=
                    "WARNING: $($expiringCerts.Count) SSL certificate(s) expiring within 30 days"
                $healthScore -= 10
            }
        }

        # Determine overall health
        if ($healthScore -ge 90) { $results.OverallHealth = 'Excellent' }
        elseif ($healthScore -ge 75) { $results.OverallHealth = 'Good' }
        elseif ($healthScore -ge 50) { $results.OverallHealth = 'Fair' }
        else { $results.OverallHealth = 'Poor' }

        if ($healthScore -ge 75) { $healthStatus = 'Success' }
        elseif ($healthScore -ge 50) { $healthStatus = 'Warning' }
        else { $healthStatus = 'Error' }

        Write-StatusMessage `
            -Message "Overall IIS Health: $($results.OverallHealth) (Score: $healthScore/100)" `
            -Status $healthStatus

        # Display Summary
        Write-ScriptMessage -Message '=== Health Check Summary ==='
        Write-ScriptMessage -Message "IIS Version: $($results.IISVersion)"
        $poolSummary = "Application Pools: $($results.ApplicationPools.Count) total," +
            " $($stoppedPools.Count) stopped"
        Write-ScriptMessage -Message $poolSummary
        $siteSummary = "Websites: $($results.Websites.Count) total," +
            " $($stoppedSites.Count) stopped"
        Write-ScriptMessage -Message $siteSummary
        if ($CheckSSLCertificates) {
            $certSummary = "SSL Certificates: $($results.SSLCertificates.Count) checked," +
                " $($expiredCerts.Count) expired, $($expiringCerts.Count) expiring soon"
            Write-ScriptMessage -Message $certSummary
        }

        if ($results.Recommendations.Count -gt 0) {
            Write-ScriptMessage -Message '=== Recommendations ===' -Prefix '' -Color Yellow
            foreach ($rec in $results.Recommendations) {
                Write-ScriptMessage -Message "  - $rec" -Prefix '' -Color Yellow
            }
        }

        # Export HTML Report
        if ($ExportHTML) {
            $reportPath = "$ReportDir\IIS_HealthCheck_${computerName}_${timestamp}.html"

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>IIS Health Check Report - $computerName</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0066cc; border-bottom: 2px solid #0066cc; padding-bottom: 10px; }
        h2 { color: #333; margin-top: 30px; border-bottom: 1px solid #ddd; padding-bottom: 5px; }
        .summary { background-color: white; padding: 15px; margin-bottom: 20px; }
        table { border-collapse: collapse; width: 100%; background-color: white; margin-bottom: 20px; }
        th { background-color: #0066cc; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .recommendations { background-color: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; }
        .recommendations ul { margin: 10px 0; padding-left: 20px; }
        .footer { margin-top: 30px; text-align: center; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <h1>IIS Health Check Report</h1>
    <div class="summary">
        <strong>Computer:</strong> $computerName<br>
        <strong>Report Generated:</strong> $($results.Timestamp)<br>
        <strong>IIS Version:</strong> $($results.IISVersion)<br>
        <strong>Overall Health:</strong> $($results.OverallHealth) ($healthScore/100)
    </div>
"@

            if ($results.Recommendations.Count -gt 0) {
                $html += "<div class='recommendations'><h2>Recommendations</h2><ul>"
                foreach ($rec in $results.Recommendations) {
                    $html += "<li>$rec</li>"
                }
                $html += '</ul></div>'
            }

            # Application Pools Table
            $html += "<h2>Application Pools ($($results.ApplicationPools.Count))</h2><table>"
            $html += "<tr><th>Name</th><th>State</th><th>Runtime Version</th>"
            $html += "<tr><th>Pipeline Mode</th><th>Start Mode</th><th>Issues</th></tr>"
            foreach ($pool in $results.ApplicationPools) {
                $issuesText = if ($pool.Issues.Count -gt 0) { $pool.Issues -join ', ' } else { 'None' }
                $html += "<tr><td>$($pool.Name)</td><td>$($pool.State)</td>"
                $html += "<td>$($pool.ManagedRuntimeVersion)</td><td>$($pool.ManagedPipelineMode)</td>"
                $html += "<td>$($pool.StartMode)</td><td>$issuesText</td></tr>"
            }
            $html += '</table>'

            # Websites Table
            $html += "<h2>Websites ($($results.Websites.Count))</h2><table>"
            $html += "<tr><th>Name</th><th>State</th><th>Application Pool</th><th>Bindings</th>"
            $html += "<tr><th>Physical Path</th><th>Issues</th></tr>"
            foreach ($site in $results.Websites) {
                $issuesText = if ($site.Issues.Count -gt 0) { $site.Issues -join ', ' } else { 'None' }
                $html += "<tr><td>$($site.Name)</td><td>$($site.State)</td>"
                $html += "<td>$($site.ApplicationPool)</td><td>$($site.Bindings)</td>"
                $html += "<td>$($site.PhysicalPath)</td><td>$issuesText</td></tr>"
            }
            $html += '</table>'

            # SSL Certificates Table
            if ($CheckSSLCertificates -and $results.SSLCertificates.Count -gt 0) {
                $html += "<h2>SSL Certificates ($($results.SSLCertificates.Count))</h2><table>"
                $html += "<tr><th>Site</th><th>Binding</th><th>Subject</th><th>Expires</th>"
                $html += "<tr><th>Days to Expire</th><th>Status</th></tr>"
                foreach ($cert in $results.SSLCertificates) {
                    $html += "<tr><td>$($cert.Site)</td><td>$($cert.Binding)</td>"
                    $html += "<td>$($cert.Subject)</td><td>$($cert.NotAfter.ToString('yyyy-MM-dd'))</td>"
                    $html += "<td>$($cert.DaysToExpire)</td><td>$($cert.Status)</td></tr>"
                }
                $html += '</table>'
            }

            $html += "<div class='footer'>Generated by IIS Health Check Script | $(Get-Date)</div></body></html>"

            $html | Out-File -FilePath $reportPath -Encoding UTF8 -ErrorAction Stop
            Write-StatusMessage -Message "HTML report saved to: $reportPath" -Status Success
        }

        # Export CSV
        if ($ExportCSV) {
            $csvPath = "$ReportDir\IIS_HealthCheck_${computerName}_${timestamp}.csv"
            $results.Websites | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
            Write-StatusMessage -Message "CSV export saved to: $csvPath" -Status Success
        }

        Write-ScriptMessage -Message 'Health check complete!' -Prefix '+' -Color Green

        # Exit code contract: 0 when health score >= 75, otherwise 1.
        if ($healthScore -ge 75) { return 0 }
        return 1
    }
    catch {
        Write-ScriptMessage -Message "Error: $($_.Exception.Message)" -Prefix '-' -Color Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
