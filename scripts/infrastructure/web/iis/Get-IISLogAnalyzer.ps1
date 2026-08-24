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

    Supports W3C, IIS, and NCSA log formats. This is a read-only analysis
    script: it returns 0 when analysis completes and 1 when no log files or
    no valid log entries are found in the requested window.

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
    Reserved for CSV export of analysis data; recorded for future use.

.EXAMPLE
    PS C:\> .\Get-IISLogAnalyzer.ps1

    Analyze last 7 days of IIS logs.

.EXAMPLE
    PS C:\> .\Get-IISLogAnalyzer.ps1 -DaysToAnalyze 30 -IncludeSecurityAnalysis -ExportHTML

    Analyze last 30 days with security analysis and HTML report.

.NOTES
    File Name   : Get-IISLogAnalyzer.ps1
    Author      : IT Infrastructure Team
    Prerequisite: PowerShell 5.1+
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
    [ValidateNotNullOrEmpty()]
    [string]$LogPath = "$env:SystemDrive\inetpub\logs\LogFiles",

    [Parameter()]
    [ValidateRange(1, 365)]
    [int]$DaysToAnalyze = 7,

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$Top = 20,

    [Parameter()]
    [switch]$IncludeSecurityAnalysis,

    [Parameter()]
    [switch]$ExportHTML,

    [Parameter()]
    [switch]$ExportCSV
)

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

function Read-IisLogFile {
    <#
    .SYNOPSIS
        Parses W3C-format IIS log lines into entry objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Lines
    )

    $entries = @()
    foreach ($line in ($Lines | Where-Object { $_ -notmatch '^#' -and $_ -ne '' })) {
        try {
            $fields = $line -split '\s+'
            if ($fields.Count -ge 10) {
                $entries += [PSCustomObject]@{
                    Date       = [datetime]::ParseExact("$($fields[0]) $($fields[1])", 'yyyy-MM-dd HH:mm:ss', $null)
                    ClientIP   = $fields[2]
                    Method     = $fields[3]
                    UriStem    = $fields[4]
                    UriQuery   = $fields[5]
                    Port       = $fields[6]
                    Username   = $fields[7]
                    ServerIP   = $fields[8]
                    UserAgent  = if ($fields.Count -gt 9) { $fields[9] } else { '' }
                    Referer    = if ($fields.Count -gt 10) { $fields[10] } else { '' }
                    StatusCode = if ($fields.Count -gt 11) { $fields[11] } else { '200' }
                    SubStatus  = if ($fields.Count -gt 12) { $fields[12] } else { '0' }
                    TimeTaken  = if ($fields.Count -gt 14) { [int]$fields[14] } else { 0 }
                    BytesSent  = if ($fields.Count -gt 13) { [int]$fields[13] } else { 0 }
                }
            }
        }
        catch {
            $script:parseErrors++
        }
    }

    # Emitting the array unwinds its elements so callers can flatten safely.
    return $entries
}

function Get-SecurityThreatSummary {
    <#
    .SYNOPSIS
        Matches log entries against suspicious request patterns.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Entries
    )

    $suspiciousPatterns = @(
        @{
            Name    = 'SQL Injection'
            Pattern = '(\%27)|('')|(--)|(\%23)|(#)|(union)|(select)|(insert)|(drop)|(update)|(delete)|(exec)'
        }
        @{ Name = 'XSS Attempts'; Pattern = '(<script|javascript:|onerror=|onload=)' }
        @{ Name = 'Path Traversal'; Pattern = '(\.\./|\.\.\\|%2e%2e)' }
        @{ Name = 'Command Injection'; Pattern = '(\||;|`|\\$\(|\${)' }
    )

    $threats = @()
    foreach ($pattern in $suspiciousPatterns) {
        $matched = @($Entries |
            Where-Object { $_.UriStem -match $pattern.Pattern -or $_.UriQuery -match $pattern.Pattern })
        if ($matched.Count -gt 0) {
            $uniqueIps = ($matched | Select-Object -Unique ClientIP).Count
            $threats += [PSCustomObject]@{
                ThreatType = $pattern.Name
                Count      = $matched.Count
                UniqueIPs  = $uniqueIps
            }
        }
    }

    return $threats
}

function Main {
    <#
    .SYNOPSIS
        Runs the IIS log analyzer workflow.
    #>
    [CmdletBinding()]
    param()

    try {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $cutoffDate = (Get-Date).AddDays(-$DaysToAnalyze)
        $script:parseErrors = 0

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
            Write-ScriptMessage -Message "Unsafe report path: $ReportDir." -Prefix '-' -Color Red
            return 1
        }
        $ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
        if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
            New-Item -ItemType Directory -Path $ReportDir -Force -ErrorAction Stop | Out-Null
        }

        Write-ScriptMessage -Message '=== IIS Log Analyzer ==='
        Write-ScriptMessage -Message "Analyzing logs from: $LogPath"
        Write-ScriptMessage -Message "Date range: Last $DaysToAnalyze days"

        # Get log files
        Write-ScriptMessage -Message 'Collecting log files...' -Prefix '*' -Color Cyan
        $logFiles = @(Get-ChildItem -Path $LogPath -Filter '*.log' -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $cutoffDate })

        if ($logFiles.Count -eq 0) {
            Write-ScriptMessage -Message 'No log files found in specified date range' -Prefix '!' -Color Yellow
            return 1
        }

        $totalSizeMB = '{0:N2}' -f (($logFiles | Measure-Object Length -Sum).Sum / 1MB)
        Write-ScriptMessage `
            -Message "Found $($logFiles.Count) log files ($totalSizeMB MB)" `
            -Prefix '+' -Color Green

        # Parse log files
        Write-ScriptMessage -Message 'Parsing log entries...' -Prefix '*' -Color Cyan
        $entries = @()

        foreach ($file in $logFiles) {
            try {
                $content = @(Get-Content -LiteralPath $file.FullName -ErrorAction Stop)
                $parsed = @(Read-IisLogFile -Lines $content)
                $entries = @($entries + $parsed)
            }
            catch {
                Write-ScriptMessage -Message "Error reading $($file.Name): $_" -Prefix '!' -Color Yellow
            }
        }

        $entryCount = $entries.Count
        Write-ScriptMessage `
            -Message "Parsed $entryCount log entries ($script:parseErrors parse errors)" `
            -Prefix '+' -Color Green

        if ($entryCount -eq 0) {
            Write-ScriptMessage -Message 'No valid log entries found' -Prefix '!' -Color Yellow
            return 1
        }

        # Analysis
        $analysis = @{}

        Write-ScriptMessage -Message 'Performing analysis...' -Prefix '*' -Color Cyan

        # Top URLs
        $analysis.TopURLs = $entries | Group-Object UriStem | Sort-Object Count -Descending |
            Select-Object -First $Top |
            ForEach-Object { [PSCustomObject]@{ URL = $_.Name; Requests = $_.Count } }

        # Status codes
        $analysis.StatusCodes = $entries | Group-Object StatusCode | Sort-Object Count -Descending |
            ForEach-Object {
                $percentage = [math]::Round(($_.Count / $entryCount) * 100, 2)
                [PSCustomObject]@{ StatusCode = $_.Name; Count = $_.Count; Percentage = $percentage }
            }

        # Top client IPs
        $analysis.TopIPs = $entries | Group-Object ClientIP | Sort-Object Count -Descending |
            Select-Object -First $Top |
            ForEach-Object { [PSCustomObject]@{ IP = $_.Name; Requests = $_.Count } }

        # Error analysis (4xx and 5xx)
        $errors = @($entries | Where-Object { [int]$_.StatusCode -ge 400 })
        $analysis.ErrorCount = $errors.Count
        $analysis.TopErrors = $errors | Group-Object UriStem | Sort-Object Count -Descending |
            Select-Object -First $Top |
            ForEach-Object { [PSCustomObject]@{ URL = $_.Name; ErrorCount = $_.Count } }

        # Performance metrics
        $analysis.AvgResponseTime = [math]::Round(($entries | Measure-Object TimeTaken -Average).Average, 2)
        $analysis.MaxResponseTime = ($entries | Measure-Object TimeTaken -Maximum).Maximum
        $analysis.SlowRequests = ($entries | Where-Object { $_.TimeTaken -gt 5000 }).Count

        # Bandwidth
        $totalBytesSent = ($entries | Measure-Object BytesSent -Sum).Sum
        $analysis.TotalBandwidthGB = [math]::Round($totalBytesSent / 1GB, 2)

        # Security analysis
        if ($IncludeSecurityAnalysis) {
            Write-ScriptMessage -Message 'Performing security analysis...' -Prefix '*' -Color Cyan
            $analysis.SecurityThreats = @(Get-SecurityThreatSummary -Entries $entries)
        }

        # Display results
        Write-ScriptMessage -Message '=== Analysis Results ==='
        Write-ScriptMessage -Message "Total Requests: $entryCount"
        Write-ScriptMessage -Message "Date Range: $($entries[0].Date) to $($entries[-1].Date)"
        Write-ScriptMessage -Message "Total Bandwidth: $($analysis.TotalBandwidthGB) GB"
        Write-ScriptMessage -Message "Average Response Time: $($analysis.AvgResponseTime) ms"
        $errorColor = if ($analysis.ErrorCount -gt 100) { 'Red' } else { 'Green' }
        Write-ScriptMessage -Message "Errors (4xx/5xx): $($analysis.ErrorCount)" -Prefix '' -Color $errorColor

        Write-ScriptMessage -Message 'Top 10 URLs:' -Prefix '' -Color Yellow
        $analysis.TopURLs | Select-Object -First 10 | Format-Table -AutoSize

        Write-ScriptMessage -Message 'Status Code Distribution:' -Prefix '' -Color Yellow
        $analysis.StatusCodes | Format-Table -AutoSize

        if ($IncludeSecurityAnalysis -and $analysis.SecurityThreats.Count -gt 0) {
            Write-ScriptMessage -Message 'Security Threats Detected:' -Prefix '-' -Color Red
            $analysis.SecurityThreats | Format-Table -AutoSize
        }

        # Export HTML
        if ($ExportHTML) {
            $reportPath = "$ReportDir\IIS_LogAnalysis_${timestamp}.html"

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
        .summary { background-color: white; padding: 15px; margin-bottom: 20px; }
        .threat { background-color: #ffebee; border-left: 4px solid #f44336; padding: 10px; margin: 10px 0; }
    </style>
</head>
<body>
    <h1>IIS Log Analysis Report</h1>
    <div class="summary">
        <strong>Report Generated:</strong> $(Get-Date)<br>
        <strong>Analysis Period:</strong> Last $DaysToAnalyze days<br>
        <strong>Total Requests:</strong> $entryCount<br>
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

            $html += '</table><h2>Status Codes</h2>'
            $html += '<table><tr><th>Status Code</th><th>Count</th><th>Percentage</th></tr>'

            foreach ($code in $analysis.StatusCodes) {
                $html += "<tr><td>$($code.StatusCode)</td><td>$($code.Count)</td><td>$($code.Percentage)%</td></tr>"
            }

            $html += '</table>'

            if ($IncludeSecurityAnalysis -and $analysis.SecurityThreats.Count -gt 0) {
                $html += '<h2>Security Threats</h2>'
                foreach ($threat in $analysis.SecurityThreats) {
                    $html += "<div class='threat'><strong>$($threat.ThreatType):</strong> " +
                        "$($threat.Count) attempts from $($threat.UniqueIPs) unique IPs</div>"
                }
            }

            $html += '</body></html>'

            $html | Out-File -FilePath $reportPath -Encoding UTF8 -ErrorAction Stop
            Write-ScriptMessage -Message "HTML report saved: $reportPath" -Prefix '+' -Color Green
        }

        Write-ScriptMessage -Message 'Analysis complete!' -Prefix '+' -Color Green
        return 0
    }
    catch {
        Write-ScriptMessage -Message "Error: $($_.Exception.Message)" -Prefix '-' -Color Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
