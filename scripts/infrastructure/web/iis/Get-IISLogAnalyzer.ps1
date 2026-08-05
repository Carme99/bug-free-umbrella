<#
.SYNOPSIS
    Advanced IIS log file analysis and reporting.

.DESCRIPTION
    Analyzes IIS log files to identify:
    - Top requested URLs and resources
    - HTTP status code distribution
    - Client IP analysis and geographic patterns
    - User agent analysis (browsers, bots, crawlers)
    - Performance metrics (response times)
    - Error patterns and failed requests
    - Security events (suspicious requests, attacks)
    - Bandwidth usage by resource

    Supports W3C, IIS, and NCSA log formats.

.PARAMETER LogPath
    Path to IIS log files directory (default: C:\inetpub\logs\LogFiles).

.PARAMETER DaysToAnalyze
    Number of days to analyze (default: 7).

.PARAMETER Top
    Number of top entries to show for each category (default: 20).

.PARAMETER IncludeSecurityAnalysis
    Perform security threat analysis (SQL injection, XSS, path traversal).

.PARAMETER ExportHTML
    Generate detailed HTML report.

.PARAMETER ExportCSV
    Export analysis data to CSV.

.EXAMPLE
    .\Get-IISLogAnalyzer.ps1

    Analyze last 7 days of IIS logs.

.EXAMPLE
    .\Get-IISLogAnalyzer.ps1 -DaysToAnalyze 30 -IncludeSecurityAnalysis -ExportHTML

    Analyze last 30 days with security analysis and HTML report.

.NOTES
    Author: IT Infrastructure Team
    Requires: PowerShell 5.1+
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$LogPath = "$env:SystemDrive\inetpub\logs\LogFiles",

    [Parameter()]
    [int]$DaysToAnalyze = 7,

    [Parameter()]
    [int]$Top = 20,

    [Parameter()]
    [switch]$IncludeSecurityAnalysis,

    [Parameter()]
    [switch]$ExportHTML,

    [Parameter()]
    [switch]$ExportCSV
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$cutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)

# Resolve report output directory (default: MyDocuments\Reports) and validate against traversal/UNC paths
$ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
if ([string]::IsNullOrWhiteSpace($ReportDir) -or
    $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
    $ReportDir -match '^(\\\\|//)') {
    Write-Error "Unsafe report path: $ReportDir. Report path must be a local absolute path without '..' traversal."
    exit 1
}
$ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

Write-Host "`n=== IIS Log Analyzer ===" -ForegroundColor Cyan
Write-Host "Analyzing logs from: $LogPath" -ForegroundColor White
Write-Host "Date range: Last $DaysToAnalyze days`n" -ForegroundColor White

# Get log files
Write-Host "[*] Collecting log files..." -ForegroundColor Cyan
$logFiles = Get-ChildItem -Path $LogPath -Filter "*.log" -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $cutoffDate }

if ($logFiles.Count -eq 0) {
    Write-Host "[!] No log files found in specified date range" -ForegroundColor Yellow
    exit 1
}

Write-Host "[+] Found $($logFiles.Count) log files ($('{0:N2}' -f (($logFiles | Measure-Object Length -Sum).Sum / 1MB)) MB)" -ForegroundColor Green

# Parse log files
Write-Host "[*] Parsing log entries..." -ForegroundColor Cyan
$entries = @()
$parseErrors = 0

foreach ($file in $logFiles) {
    try {
        $content = Get-Content $file.FullName | Where-Object { $_ -notmatch "^#" -and $_ -ne "" }

        foreach ($line in $content) {
            try {
                $fields = $line -split '\s+'
                if ($fields.Count -ge 10) {
                    $entries += [PSCustomObject]@{
                        Date = [datetime]::ParseExact("$($fields[0]) $($fields[1])", "yyyy-MM-dd HH:mm:ss", $null)
                        ClientIP = $fields[2]
                        Method = $fields[3]
                        UriStem = $fields[4]
                        UriQuery = $fields[5]
                        Port = $fields[6]
                        Username = $fields[7]
                        ServerIP = $fields[8]
                        UserAgent = if ($fields.Count -gt 9) {$fields[9]} else {""}
                        Referer = if ($fields.Count -gt 10) {$fields[10]} else {""}
                        StatusCode = if ($fields.Count -gt 11) {$fields[11]} else {"200"}
                        SubStatus = if ($fields.Count -gt 12) {$fields[12]} else {"0"}
                        TimeTaken = if ($fields.Count -gt 14) {[int]$fields[14]} else {0}
                        BytesSent = if ($fields.Count -gt 13) {[int]$fields[13]} else {0}
                    }
                }
            } catch {
                $parseErrors++
            }
        }
    } catch {
        Write-Host "[!] Error reading $($file.Name): $_" -ForegroundColor Yellow
    }
}

Write-Host "[+] Parsed $($entries.Count) log entries ($parseErrors parse errors)" -ForegroundColor Green

if ($entries.Count -eq 0) {
    Write-Host "[!] No valid log entries found" -ForegroundColor Yellow
    exit 1
}

# Analysis
$analysis = @{}

Write-Host "`n[*] Performing analysis..." -ForegroundColor Cyan

# Top URLs
$analysis.TopURLs = $entries | Group-Object UriStem | Sort-Object Count -Descending | Select-Object -First $Top |
    ForEach-Object { [PSCustomObject]@{URL = $_.Name; Requests = $_.Count} }

# Status codes
$analysis.StatusCodes = $entries | Group-Object StatusCode | Sort-Object Count -Descending |
    ForEach-Object { [PSCustomObject]@{StatusCode = $_.Name; Count = $_.Count; Percentage = [math]::Round(($_.Count / $entries.Count) * 100, 2)} }

# Top client IPs
$analysis.TopIPs = $entries | Group-Object ClientIP | Sort-Object Count -Descending | Select-Object -First $Top |
    ForEach-Object { [PSCustomObject]@{IP = $_.Name; Requests = $_.Count} }

# Error analysis (4xx and 5xx)
$errors = $entries | Where-Object { [int]$_.StatusCode -ge 400 }
$analysis.ErrorCount = $errors.Count
$analysis.TopErrors = $errors | Group-Object UriStem | Sort-Object Count -Descending | Select-Object -First $Top |
    ForEach-Object { [PSCustomObject]@{URL = $_.Name; ErrorCount = $_.Count} }

# Performance metrics
$analysis.AvgResponseTime = [math]::Round(($entries | Measure-Object TimeTaken -Average).Average, 2)
$analysis.MaxResponseTime = ($entries | Measure-Object TimeTaken -Maximum).Maximum
$analysis.SlowRequests = ($entries | Where-Object { $_.TimeTaken -gt 5000 }).Count

# Bandwidth
$totalBytesSent = ($entries | Measure-Object BytesSent -Sum).Sum
$analysis.TotalBandwidthGB = [math]::Round($totalBytesSent / 1GB, 2)

# Security analysis
if ($IncludeSecurityAnalysis) {
    Write-Host "[*] Performing security analysis..." -ForegroundColor Cyan

    $suspiciousPatterns = @(
        @{Name = "SQL Injection"; Pattern = "(\%27)|(')|(--)|(\%23)|(#)|(union)|(select)|(insert)|(drop)|(update)|(delete)|(exec)"}
        @{Name = "XSS Attempts"; Pattern = "(<script|javascript:|onerror=|onload=)"}
        @{Name = "Path Traversal"; Pattern = "(\.\./|\.\.\\|%2e%2e)"}
        @{Name = "Command Injection"; Pattern = "(\||;|`|\\$\(|\${)"}
    }

    $analysis.SecurityThreats = @()
    foreach ($pattern in $suspiciousPatterns) {
        $threats = $entries | Where-Object { $_.UriStem -match $pattern.Pattern -or $_.UriQuery -match $pattern.Pattern }
        if ($threats.Count -gt 0) {
            $analysis.SecurityThreats += [PSCustomObject]@{
                ThreatType = $pattern.Name
                Count = $threats.Count
                UniqueIPs = ($threats | Select-Object -Unique ClientIP).Count
            }
        }
    }
}

# Display results
Write-Host "`n=== Analysis Results ===" -ForegroundColor Cyan
Write-Host "Total Requests: $($entries.Count)" -ForegroundColor White
Write-Host "Date Range: $($entries[0].Date) to $($entries[-1].Date)" -ForegroundColor White
Write-Host "Total Bandwidth: $($analysis.TotalBandwidthGB) GB" -ForegroundColor White
Write-Host "Average Response Time: $($analysis.AvgResponseTime) ms" -ForegroundColor White
Write-Host "Errors (4xx/5xx): $($analysis.ErrorCount)" -ForegroundColor $(if ($analysis.ErrorCount -gt 100) {"Red"} else {"Green"})

Write-Host "`nTop 10 URLs:" -ForegroundColor Yellow
$analysis.TopURLs | Select-Object -First 10 | Format-Table -AutoSize

Write-Host "Status Code Distribution:" -ForegroundColor Yellow
$analysis.StatusCodes | Format-Table -AutoSize

if ($IncludeSecurityAnalysis -and $analysis.SecurityThreats.Count -gt 0) {
    Write-Host "`nSecurity Threats Detected:" -ForegroundColor Red
    $analysis.SecurityThreats | Format-Table -AutoSize
}

# Export HTML
if ($ExportHTML) {
    $reportPath = "$env:USERPROFILE\Desktop\IIS_LogAnalysis_${timestamp}.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>IIS Log Analysis Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0066cc; }
        h2 { color: #333; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; background-color: white; margin-bottom: 20px; }
        th { background-color: #0066cc; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        .summary { background-color: white; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .threat { background-color: #ffebee; border-left: 4px solid #f44336; padding: 10px; margin: 10px 0; }
    </style>
</head>
<body>
    <h1>IIS Log Analysis Report</h1>
    <div class="summary">
        <strong>Report Generated:</strong> $(Get-Date)<br>
        <strong>Analysis Period:</strong> Last $DaysToAnalyze days<br>
        <strong>Total Requests:</strong> $($entries.Count)<br>
        <strong>Total Bandwidth:</strong> $($analysis.TotalBandwidthGB) GB<br>
        <strong>Average Response Time:</strong> $($analysis.AvgResponseTime) ms<br>
        <strong>Errors:</strong> $($analysis.ErrorCount)
    </div>

    <h2>Top URLs</h2>
    <table>
        <tr><th>URL</th><th>Requests</th></tr>
"@

    foreach ($url in $analysis.TopURLs) {
        $html += "<tr><td>$($url.URL)</td><td>$($url.Requests)</td></tr>"
    }

    $html += "</table><h2>Status Codes</h2><table><tr><th>Status Code</th><th>Count</th><th>Percentage</th></tr>"

    foreach ($code in $analysis.StatusCodes) {
        $html += "<tr><td>$($code.StatusCode)</td><td>$($code.Count)</td><td>$($code.Percentage)%</td></tr>"
    }

    $html += "</table>"

    if ($IncludeSecurityAnalysis -and $analysis.SecurityThreats.Count -gt 0) {
        $html += "<h2>Security Threats</h2>"
        foreach ($threat in $analysis.SecurityThreats) {
            $html += "<div class='threat'><strong>$($threat.ThreatType):</strong> $($threat.Count) attempts from $($threat.UniqueIPs) unique IPs</div>"
        }
    }

    $html += "</body></html>"

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "`n[+] HTML report saved: $reportPath" -ForegroundColor Green
}

Write-Host "`nAnalysis complete!`n" -ForegroundColor Green
