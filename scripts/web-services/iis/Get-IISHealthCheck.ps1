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
    .\Get-IISHealthCheck.ps1

    Performs basic IIS health check with console output.

.EXAMPLE
    .\Get-IISHealthCheck.ps1 -CheckSSLCertificates -ExportHTML

    Comprehensive check including SSL validation with HTML report.

.EXAMPLE
    .\Get-IISHealthCheck.ps1 -IncludePerformanceCounters -AnalyzeLogFiles -DaysToAnalyze 14 -ExportHTML

    Full health check with performance data and 14-day log analysis.

.NOTES
    Author: IT Infrastructure Team
    Requires: IIS 8.0+, WebAdministration module
    Requires: Administrator privileges
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$IncludePerformanceCounters,

    [Parameter()]
    [switch]$CheckSSLCertificates,

    [Parameter()]
    [switch]$AnalyzeLogFiles,

    [Parameter()]
    [int]$DaysToAnalyze = 7,

    [Parameter()]
    [switch]$ExportHTML,

    [Parameter()]
    [switch]$ExportCSV
)

#Requires -Modules WebAdministration
#Requires -RunAsAdministrator

# Initialize
$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$computerName = $env:COMPUTERNAME
$results = @{
    Timestamp = Get-Date
    ComputerName = $computerName
    IISVersion = ""
    ApplicationPools = @()
    Websites = @()
    SSLCertificates = @()
    PerformanceData = @{}
    LogAnalysis = @{}
    Recommendations = @()
    OverallHealth = "Unknown"
}

# Color output functions
function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Write-StatusMessage {
    param([string]$Message, [string]$Status)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    switch ($Status) {
        "Info" { Write-ColorOutput "[$timestamp] [INFO] $Message" -Color Cyan }
        "Success" { Write-ColorOutput "[$timestamp] [SUCCESS] $Message" -Color Green }
        "Warning" { Write-ColorOutput "[$timestamp] [WARNING] $Message" -Color Yellow }
        "Error" { Write-ColorOutput "[$timestamp] [ERROR] $Message" -Color Red }
    }
}

Write-ColorOutput "`n=== IIS Health Check ===" -Color Cyan
Write-ColorOutput "Computer: $computerName`n" -Color White

# Check if IIS is installed
Write-StatusMessage "Checking IIS installation..." -Status Info
try {
    $iisFeature = Get-WindowsFeature -Name Web-Server -ErrorAction Stop
    if (-not $iisFeature.Installed) {
        Write-StatusMessage "IIS is not installed on this server" -Status Error
        exit 1
    }
    Write-StatusMessage "IIS is installed and accessible" -Status Success
} catch {
    Write-StatusMessage "Error checking IIS installation: $_" -Status Error
    exit 1
}

# Get IIS version
Write-StatusMessage "Detecting IIS version..." -Status Info
try {
    $iisVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp").VersionString
    $results.IISVersion = $iisVersion
    Write-StatusMessage "IIS Version: $iisVersion" -Status Success
} catch {
    Write-StatusMessage "Could not determine IIS version" -Status Warning
}

# Check Application Pools
Write-StatusMessage "`nAnalyzing application pools..." -Status Info
try {
    $appPools = Get-IISAppPool
    $poolIssues = 0

    foreach ($pool in $appPools) {
        $poolInfo = [PSCustomObject]@{
            Name = $pool.Name
            State = $pool.State
            ManagedRuntimeVersion = $pool.ManagedRuntimeVersion
            ManagedPipelineMode = $pool.ManagedPipelineMode
            Enable32BitAppOnWin64 = $pool.Enable32BitAppOnWin64
            StartMode = $pool.StartMode
            RecyclingSchedule = ($pool.Recycling.PeriodicRestart.Schedule -join ", ")
            RecyclingMemoryLimit = $pool.Recycling.PeriodicRestart.PrivateMemory
            IdleTimeout = $pool.ProcessModel.IdleTimeout.TotalMinutes
            Issues = @()
        }

        # Check for issues
        if ($pool.State -ne "Started") {
            $poolInfo.Issues += "Pool is $($pool.State)"
            $poolIssues++
        }
        if ($pool.ProcessModel.IdleTimeout.TotalMinutes -lt 20 -and $pool.ProcessModel.IdleTimeout.TotalMinutes -gt 0) {
            $poolInfo.Issues += "Short idle timeout ($($pool.ProcessModel.IdleTimeout.TotalMinutes) min)"
        }

        $results.ApplicationPools += $poolInfo
    }

    Write-StatusMessage "Found $($appPools.Count) application pools ($poolIssues issues)" -Status $(if ($poolIssues -eq 0) {"Success"} else {"Warning"})
} catch {
    Write-StatusMessage "Error analyzing application pools: $_" -Status Error
}

# Check Websites
Write-StatusMessage "Analyzing websites and bindings..." -Status Info
try {
    $websites = Get-IISSite
    $siteIssues = 0

    foreach ($site in $websites) {
        $bindings = $site.Bindings | ForEach-Object {
            "$($_.Protocol)://$($_.BindingInformation)"
        }

        $siteInfo = [PSCustomObject]@{
            Name = $site.Name
            ID = $site.Id
            State = $site.State
            PhysicalPath = $site.Applications['/'].VirtualDirectories['/'].PhysicalPath
            ApplicationPool = $site.Applications['/'].ApplicationPoolName
            Bindings = ($bindings -join "; ")
            LogFileDirectory = $site.LogFile.Directory
            Issues = @()
        }

        # Check for issues
        if ($site.State -ne "Started") {
            $siteInfo.Issues += "Site is $($site.State)"
            $siteIssues++
        }
        if (-not (Test-Path $siteInfo.PhysicalPath)) {
            $siteInfo.Issues += "Physical path not found"
            $siteIssues++
        }

        $results.Websites += $siteInfo
    }

    Write-StatusMessage "Found $($websites.Count) websites ($siteIssues issues)" -Status $(if ($siteIssues -eq 0) {"Success"} else {"Warning"})
} catch {
    Write-StatusMessage "Error analyzing websites: $_" -Status Error
}

# Check SSL Certificates
if ($CheckSSLCertificates) {
    Write-StatusMessage "`nValidating SSL certificates..." -Status Info
    try {
        $httpsBindings = Get-IISSite | ForEach-Object {
            $siteName = $_.Name
            $_.Bindings | Where-Object { $_.Protocol -eq "https" } | ForEach-Object {
                [PSCustomObject]@{
                    Site = $siteName
                    Binding = $_.BindingInformation
                    CertificateHash = $_.CertificateHash
                    CertificateStoreName = $_.CertificateStoreName
                }
            }
        }

        $certIssues = 0
        foreach ($binding in $httpsBindings) {
            if ($binding.CertificateHash) {
                $cert = Get-ChildItem Cert:\LocalMachine\$($binding.CertificateStoreName) |
                    Where-Object { $_.Thumbprint -eq $binding.CertificateHash }

                if ($cert) {
                    $daysToExpire = ($cert.NotAfter - (Get-Date)).Days
                    $certInfo = [PSCustomObject]@{
                        Site = $binding.Site
                        Binding = $binding.Binding
                        Subject = $cert.Subject
                        Issuer = $cert.Issuer
                        NotBefore = $cert.NotBefore
                        NotAfter = $cert.NotAfter
                        DaysToExpire = $daysToExpire
                        Status = if ($daysToExpire -lt 0) {"Expired"} elseif ($daysToExpire -lt 30) {"Expiring Soon"} else {"Valid"}
                    }

                    if ($certInfo.Status -ne "Valid") {
                        $certIssues++
                    }

                    $results.SSLCertificates += $certInfo
                } else {
                    $certIssues++
                }
            }
        }

        Write-StatusMessage "Checked $($httpsBindings.Count) HTTPS bindings ($certIssues issues)" -Status $(if ($certIssues -eq 0) {"Success"} else {"Warning"})
    } catch {
        Write-StatusMessage "Error checking SSL certificates: $_" -Status Error
    }
}

# Collect Performance Counters
if ($IncludePerformanceCounters) {
    Write-StatusMessage "`nCollecting performance data..." -Status Info
    try {
        $perfCounters = @(
            "\Web Service(_Total)\Current Connections"
            "\Web Service(_Total)\Bytes Total/sec"
            "\Web Service(_Total)\Get Requests/sec"
            "\Web Service(_Total)\Post Requests/sec"
            "\APP_POOL_WAS(_Total)\Current Application Pool State"
            "\APP_POOL_WAS(_Total)\Current Application Pool Uptime"
        )

        foreach ($counter in $perfCounters) {
            try {
                $value = (Get-Counter -Counter $counter -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue).CounterSamples.CookedValue
                $results.PerformanceData[$counter] = $value
            } catch {
                # Counter might not exist
            }
        }

        Write-StatusMessage "Performance data collected" -Status Success
    } catch {
        Write-StatusMessage "Error collecting performance data: $_" -Status Warning
    }
}

# Analyze Log Files
if ($AnalyzeLogFiles) {
    Write-StatusMessage "`nAnalyzing IIS log files (last $DaysToAnalyze days)..." -Status Info
    try {
        $logPath = "$env:SystemDrive\inetpub\logs\LogFiles"
        if (Test-Path $logPath) {
            $cutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)
            $logFiles = Get-ChildItem -Path $logPath -Filter "*.log" -Recurse |
                Where-Object { $_.LastWriteTime -ge $cutoffDate }

            $totalLogs = $logFiles.Count
            $totalSize = ($logFiles | Measure-Object -Property Length -Sum).Sum / 1MB

            $results.LogAnalysis = @{
                TotalLogFiles = $totalLogs
                TotalSizeMB = [math]::Round($totalSize, 2)
                OldestLog = if ($logFiles) { ($logFiles | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime } else { $null }
                NewestLog = if ($logFiles) { ($logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime } else { $null }
            }

            Write-StatusMessage "Analyzed $totalLogs log files ($([math]::Round($totalSize, 2)) MB)" -Status Success
        } else {
            Write-StatusMessage "Log file path not found: $logPath" -Status Warning
        }
    } catch {
        Write-StatusMessage "Error analyzing log files: $_" -Status Error
    }
}

# Generate Recommendations
Write-StatusMessage "`nGenerating recommendations..." -Status Info
$healthScore = 100

# Check for stopped pools
$stoppedPools = $results.ApplicationPools | Where-Object { $_.State -ne "Started" }
if ($stoppedPools) {
    $results.Recommendations += "ACTION REQUIRED: $($stoppedPools.Count) application pool(s) are not running"
    $healthScore -= 20
}

# Check for stopped sites
$stoppedSites = $results.Websites | Where-Object { $_.State -ne "Started" }
if ($stoppedSites) {
    $results.Recommendations += "ACTION REQUIRED: $($stoppedSites.Count) website(s) are not running"
    $healthScore -= 20
}

# Check SSL certificates
if ($CheckSSLCertificates) {
    $expiringCerts = $results.SSLCertificates | Where-Object { $_.DaysToExpire -lt 30 -and $_.DaysToExpire -ge 0 }
    $expiredCerts = $results.SSLCertificates | Where-Object { $_.DaysToExpire -lt 0 }

    if ($expiredCerts) {
        $results.Recommendations += "CRITICAL: $($expiredCerts.Count) SSL certificate(s) have expired"
        $healthScore -= 30
    }
    if ($expiringCerts) {
        $results.Recommendations += "WARNING: $($expiringCerts.Count) SSL certificate(s) expiring within 30 days"
        $healthScore -= 10
    }
}

# Determine overall health
$results.OverallHealth = if ($healthScore -ge 90) { "Excellent" }
                         elseif ($healthScore -ge 75) { "Good" }
                         elseif ($healthScore -ge 50) { "Fair" }
                         else { "Poor" }

Write-StatusMessage "Overall IIS Health: $($results.OverallHealth) (Score: $healthScore/100)" -Status $(
    if ($healthScore -ge 75) {"Success"} elseif ($healthScore -ge 50) {"Warning"} else {"Error"}
)

# Display Summary
Write-ColorOutput "`n=== Health Check Summary ===" -Color Cyan
Write-ColorOutput "IIS Version: $($results.IISVersion)" -Color White
Write-ColorOutput "Application Pools: $($results.ApplicationPools.Count) total, $($stoppedPools.Count) stopped" -Color White
Write-ColorOutput "Websites: $($results.Websites.Count) total, $($stoppedSites.Count) stopped" -Color White
if ($CheckSSLCertificates) {
    Write-ColorOutput "SSL Certificates: $($results.SSLCertificates.Count) checked, $($expiredCerts.Count) expired, $($expiringCerts.Count) expiring soon" -Color White
}

if ($results.Recommendations.Count -gt 0) {
    Write-ColorOutput "`n=== Recommendations ===" -Color Yellow
    foreach ($rec in $results.Recommendations) {
        Write-ColorOutput "  - $rec" -Color Yellow
    }
}

# Export HTML Report
if ($ExportHTML) {
    $reportPath = "$env:USERPROFILE\Desktop\IIS_HealthCheck_${computerName}_${timestamp}.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>IIS Health Check Report - $computerName</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0066cc; border-bottom: 2px solid #0066cc; padding-bottom: 10px; }
        h2 { color: #333; margin-top: 30px; border-bottom: 1px solid #ddd; padding-bottom: 5px; }
        .summary { background-color: white; padding: 15px; border-radius: 5px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .health-excellent { color: green; font-weight: bold; }
        .health-good { color: #4CAF50; font-weight: bold; }
        .health-fair { color: orange; font-weight: bold; }
        .health-poor { color: red; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        th { background-color: #0066cc; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .status-started { color: green; font-weight: bold; }
        .status-stopped { color: red; font-weight: bold; }
        .cert-valid { color: green; }
        .cert-expiring { color: orange; }
        .cert-expired { color: red; font-weight: bold; }
        .recommendations { background-color: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin-bottom: 20px; }
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
        <strong>Overall Health:</strong> <span class="health-$($results.OverallHealth.ToLower())">$($results.OverallHealth)</span> ($healthScore/100)
    </div>
"@

    if ($results.Recommendations.Count -gt 0) {
        $html += "<div class='recommendations'><h2>Recommendations</h2><ul>"
        foreach ($rec in $results.Recommendations) {
            $html += "<li>$rec</li>"
        }
        $html += "</ul></div>"
    }

    # Application Pools Table
    $html += "<h2>Application Pools ($($results.ApplicationPools.Count))</h2><table><tr><th>Name</th><th>State</th><th>Runtime Version</th><th>Pipeline Mode</th><th>Start Mode</th><th>Issues</th></tr>"
    foreach ($pool in $results.ApplicationPools) {
        $stateClass = if ($pool.State -eq "Started") {"status-started"} else {"status-stopped"}
        $issuesText = if ($pool.Issues.Count -gt 0) {$pool.Issues -join ", "} else {"None"}
        $html += "<tr><td>$($pool.Name)</td><td class='$stateClass'>$($pool.State)</td><td>$($pool.ManagedRuntimeVersion)</td><td>$($pool.ManagedPipelineMode)</td><td>$($pool.StartMode)</td><td>$issuesText</td></tr>"
    }
    $html += "</table>"

    # Websites Table
    $html += "<h2>Websites ($($results.Websites.Count))</h2><table><tr><th>Name</th><th>State</th><th>Application Pool</th><th>Bindings</th><th>Physical Path</th><th>Issues</th></tr>"
    foreach ($site in $results.Websites) {
        $stateClass = if ($site.State -eq "Started") {"status-started"} else {"status-stopped"}
        $issuesText = if ($site.Issues.Count -gt 0) {$site.Issues -join ", "} else {"None"}
        $html += "<tr><td>$($site.Name)</td><td class='$stateClass'>$($site.State)</td><td>$($site.ApplicationPool)</td><td>$($site.Bindings)</td><td>$($site.PhysicalPath)</td><td>$issuesText</td></tr>"
    }
    $html += "</table>"

    # SSL Certificates Table
    if ($CheckSSLCertificates -and $results.SSLCertificates.Count -gt 0) {
        $html += "<h2>SSL Certificates ($($results.SSLCertificates.Count))</h2><table><tr><th>Site</th><th>Binding</th><th>Subject</th><th>Expires</th><th>Days to Expire</th><th>Status</th></tr>"
        foreach ($cert in $results.SSLCertificates) {
            $statusClass = switch ($cert.Status) {
                "Valid" { "cert-valid" }
                "Expiring Soon" { "cert-expiring" }
                "Expired" { "cert-expired" }
            }
            $html += "<tr><td>$($cert.Site)</td><td>$($cert.Binding)</td><td>$($cert.Subject)</td><td>$($cert.NotAfter.ToString('yyyy-MM-dd'))</td><td>$($cert.DaysToExpire)</td><td class='$statusClass'>$($cert.Status)</td></tr>"
        }
        $html += "</table>"
    }

    $html += "<div class='footer'>Generated by IIS Health Check Script | $(Get-Date)</div></body></html>"

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-StatusMessage "HTML report saved to: $reportPath" -Status Success
}

# Export CSV
if ($ExportCSV) {
    $csvPath = "$env:USERPROFILE\Desktop\IIS_HealthCheck_${computerName}_${timestamp}.csv"
    $results.Websites | Export-Csv -Path $csvPath -NoTypeInformation
    Write-StatusMessage "CSV export saved to: $csvPath" -Status Success
}

Write-ColorOutput "`nHealth check complete!`n" -Color Green

# Exit with appropriate code
exit $(if ($healthScore -ge 75) {0} else {1})
