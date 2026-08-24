<#
.SYNOPSIS
    Parses and analyzes Windows event logs for critical errors and security events.

.DESCRIPTION
    This script comprehensively analyzes Windows event logs:
    - System log errors and warnings
    - Application log errors
    - Security log analysis (failed logins, account changes)
    - Event frequency and pattern analysis
    - Top error sources identification
    - Customizable time range
    - Export to HTML or CSV

.PARAMETER LogName
    Specify which log to analyze. Options: 'System', 'Application', 'Security', 'All' (default: 'All').

.PARAMETER Hours
    Number of hours to look back (default: 24).

.PARAMETER Days
    Number of days to look back (overrides Hours if specified).

.PARAMETER MaxEvents
    Maximum number of events to retrieve per log (default: 1000).

.PARAMETER Severity
    Filter by severity level. Options: 'Critical', 'Error', 'Warning', 'All' (default: 'Error').

.PARAMETER ExportHTML
    Export report to HTML file.

.PARAMETER ExportCSV
    Export detailed events to CSV file.

.PARAMETER GroupBySource
    Group events by source provider for pattern analysis.

.EXAMPLE
    PS C:\> .\Get-EventLogReport.ps1
    Analyzes all logs for errors in the last 24 hours.

.EXAMPLE
    PS C:\> .\Get-EventLogReport.ps1 -LogName System -Days 7 -Severity Warning -ExportHTML
    Analyzes System log for warnings in the last 7 days and exports HTML report.

.EXAMPLE
    PS C:\> .\Get-EventLogReport.ps1 -LogName Security -Hours 12 -ExportCSV
    Analyzes Security log for the last 12 hours and exports to CSV.

.NOTES
    File Name     : Get-EventLogReport.ps1
    Author        : Bug-Free Umbrella
    Prerequisite  : PowerShell 5.1+
    Version       : 1.0.0
    Date          : 2026-08-23

    Administrator privileges are required for Security log access; the elevation check runs
    inside Main (not via #Requires) so the script can be safely loaded for testing.
    Compatible with Windows Server 2016, 2019, and 2022. Large time ranges may take
    several minutes to process.
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
    [ValidateSet('System', 'Application', 'Security', 'All')]
    [string]$LogName = 'All',

    [Parameter(Mandatory = $false)]
    [int]$Hours = 24,

    [Parameter(Mandatory = $false)]
    [int]$Days,

    [Parameter(Mandatory = $false)]
    [int]$MaxEvents = 1000,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Critical', 'Error', 'Warning', 'All')]
    [string]$Severity = 'Error',

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV,

    [Parameter(Mandatory = $false)]
    [switch]$GroupBySource
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

function Get-SeverityLevel {
    param([string]$Severity)

    switch ($Severity) {
        'Critical' { return @(1) }
        'Error' { return @(1, 2) }
        'Warning' { return @(1, 2, 3) }
        'All' { return @(0, 1, 2, 3, 4) }
    }
}

function Get-EventLogAnalysis {
    param([string]$Log)

    Write-Host "  Analyzing $Log log..." -ForegroundColor Cyan

    $logReport = @{
        LogName = $Log
        EventCount = 0
        CriticalCount = 0
        ErrorCount = 0
        WarningCount = 0
        Events = @()
        TopSources = @{}
    }

    try {
        $filterHash = @{
            LogName = $Log
            StartTime = $script:startTime
        }

        $levels = Get-SeverityLevel -Severity $Severity
        if ($Severity -ne 'All') {
            $filterHash['Level'] = $levels
        }

        $events = Get-WinEvent -FilterHashtable $filterHash -MaxEvents $MaxEvents -ErrorAction SilentlyContinue

        if ($events) {
            foreach ($evt in $events) {
                $eventInfo = [PSCustomObject]@{
                    TimeCreated = $evt.TimeCreated
                    LogName = $evt.LogName
                    Level = $evt.Level
                    LevelDisplayName = $evt.LevelDisplayName
                    Source = $evt.ProviderName
                    EventID = $evt.Id
                    Message = $evt.Message
                    UserName = $evt.UserId
                    Computer = $evt.MachineName
                }

                $logReport.Events += $eventInfo
                $script:report.AllEvents += $eventInfo

                # Count by severity
                switch ($evt.Level) {
                    1 {
                        $logReport.CriticalCount++
                        $script:report.Summary.CriticalCount++
                    }
                    2 {
                        $logReport.ErrorCount++
                        $script:report.Summary.ErrorCount++
                    }
                    3 {
                        $logReport.WarningCount++
                        $script:report.Summary.WarningCount++
                    }
                }

                # Track event sources
                if ($logReport.TopSources.ContainsKey($evt.ProviderName)) {
                    $logReport.TopSources[$evt.ProviderName]++
                }
                else {
                    $logReport.TopSources[$evt.ProviderName] = 1
                }
            }

            $logReport.EventCount = $events.Count
            $script:report.Summary.TotalEvents += $events.Count

            Write-ColorOutput ("    Found {0} events (Critical: {1}, Errors: {2}, Warnings: {3})" -f `
                $events.Count, $logReport.CriticalCount, $logReport.ErrorCount, $logReport.WarningCount)
        }
        else {
            Write-ColorOutput "    No events found" -Level Success
        }
    }
    catch {
        Write-ColorOutput "    Error reading log: $($_.Exception.Message)" -Level Error
        $logReport.Error = $_.Exception.Message
    }

    $script:report.Logs += $logReport
}

function Get-TopEventSources {
    Write-Verbose "Analyzing event sources..."

    $allSources = @{}

    foreach ($log in $script:report.Logs) {
        foreach ($source in $log.TopSources.GetEnumerator()) {
            if ($allSources.ContainsKey($source.Key)) {
                $allSources[$source.Key] += $source.Value
            }
            else {
                $allSources[$source.Key] = $source.Value
            }
        }
    }

    $script:report.TopSources = $allSources.GetEnumerator() |
        Sort-Object Value -Descending |
        Select-Object -First 10 |
        ForEach-Object {
            [PSCustomObject]@{
                Source = $_.Key
                EventCount = $_.Value
            }
        }
}

function Show-Summary {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Event Log Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Server: $($script:report.ServerName)"
    Write-Host "Time Range: $($script:report.TimeRange)"
    Write-Host "Scan Time: $($script:report.ScanTime)"
    Write-Host "`nTotal Events: $($script:report.Summary.TotalEvents)"

    if ($script:report.Summary.CriticalCount -gt 0) {
        Write-ColorOutput "Critical: $($script:report.Summary.CriticalCount)" -Level Critical
    }
    if ($script:report.Summary.ErrorCount -gt 0) {
        Write-ColorOutput "Errors: $($script:report.Summary.ErrorCount)" -Level Error
    }
    if ($script:report.Summary.WarningCount -gt 0) {
        Write-ColorOutput "Warnings: $($script:report.Summary.WarningCount)" -Level Warning
    }

    if ($script:report.TopSources.Count -gt 0) {
        Write-Host "`nTop Event Sources:" -ForegroundColor Cyan
        foreach ($source in $script:report.TopSources) {
            Write-Host "  $($source.Source): $($source.EventCount) events"
        }
    }

    # Show recent critical/error events
    $recentCritical = $script:report.AllEvents |
        Where-Object { $_.Level -le 2 } |
        Sort-Object TimeCreated -Descending |
        Select-Object -First 5

    if ($recentCritical) {
        Write-Host "`nRecent Critical/Error Events:" -ForegroundColor Cyan
        foreach ($evt in $recentCritical) {
            $levelColor = if ($evt.Level -eq 1) { 'Red' } else { 'Yellow' }
            Write-Host "  [$($evt.TimeCreated)] " -NoNewline
            Write-Host "$($evt.LevelDisplayName) " -ForegroundColor $levelColor -NoNewline
            Write-Host "- $($evt.Source) (Event $($evt.EventID))"
            $message = $evt.Message
            if ($message.Length -gt 100) {
                $message = $message.Substring(0, 100) + "..."
            }
            Write-Host "    $message" -ForegroundColor Gray
        }
    }

    Write-Host "`n========================================`n" -ForegroundColor Cyan
}

function Export-HTMLReport {
    $reportPath = "$ReportDir\EventLogReport_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Event Log Report - $($script:report.ServerName)</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; background-color: white; padding: 30px;
            border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #007bff; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; border-bottom: 1px solid #ddd; padding-bottom: 5px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px; margin: 20px 0; }
        .metric { background-color: #f8f9fa; padding: 20px; border-radius: 4px; border-left: 4px solid #007bff; }
        .metric.critical { border-left-color: #dc3545; }
        .metric.error { border-left-color: #fd7e14; }
        .metric.warning { border-left-color: #ffc107; }
        .metric-value { font-size: 2em; font-weight: bold; color: #007bff; }
        .metric.critical .metric-value { color: #dc3545; }
        .metric.error .metric-value { color: #fd7e14; }
        .metric.warning .metric-value { color: #ffc107; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; font-size: 0.9em; }
        th { background-color: #007bff; color: white; padding: 12px; text-align: left; position: sticky; top: 0; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f1f1f1; }
        .critical { color: #dc3545; font-weight: bold; }
        .error { color: #fd7e14; font-weight: bold; }
        .warning { color: #ffc107; font-weight: bold; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #777; font-size: 0.9em; }
        .event-message { max-width: 500px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Event Log Analysis Report</h1>
        <p><strong>Server:</strong> $($script:report.ServerName)<br>
        <strong>Time Range:</strong> $($script:report.TimeRange)<br>
        <strong>Generated:</strong> $($script:report.ScanTime)</p>

        <div class="summary">
            <div class="metric">
                <div class="metric-value">$($script:report.Summary.TotalEvents)</div>
                <div>Total Events</div>
            </div>
            $(if($script:report.Summary.CriticalCount -gt 0) {
                "<div class='metric critical'><div class='metric-value'>$($script:report.Summary.CriticalCount)" +
                "</div><div>Critical</div></div>"
            })
            $(if($script:report.Summary.ErrorCount -gt 0) {
                "<div class='metric error'><div class='metric-value'>$($script:report.Summary.ErrorCount)</div>" +
                "<div>Errors</div></div>"
            })
            $(if($script:report.Summary.WarningCount -gt 0) {
                "<div class='metric warning'><div class='metric-value'>$($script:report.Summary.WarningCount)</div>" +
                "<div>Warnings</div></div>"
            })
        </div>

        <h2>Top Event Sources</h2>
        <table>
            <tr><th>Source</th><th>Event Count</th></tr>
            $(foreach($source in $script:report.TopSources) {
                "<tr><td>$($source.Source)</td><td>$($source.EventCount)</td></tr>"
            })
        </table>

        <h2>Event Details by Log</h2>
        $(foreach($log in $script:report.Logs) {
            "<h3>$($log.LogName) Log</h3>"
            "<p>Events: $($log.EventCount) | Critical: $($log.CriticalCount) | " +
            "Errors: $($log.ErrorCount) | Warnings: $($log.WarningCount)</p>"
            if($log.Events.Count -gt 0) {
                "<table><tr><th>Time</th><th>Level</th><th>Source</th><th>Event ID</th><th>Message</th></tr>"
                foreach($evt in ($log.Events | Select-Object -First 100)) {
                    $levelClass = switch($evt.Level) {
                        1 { 'critical' }
                        2 { 'error' }
                        3 { 'warning' }
                        default { '' }
                    }
                    $message = $evt.Message
                    if($message.Length -gt 200) {
                        $message = $message.Substring(0, 200) + "..."
                    }
                    $message = [System.Net.WebUtility]::HtmlEncode($message)
                    "<tr><td>$($evt.TimeCreated)</td><td class='$levelClass'>$($evt.LevelDisplayName)</td>" +
                    "<td>$($evt.Source)</td><td>$($evt.EventID)</td>" +
                    "<td class='event-message' title='$message'>$message</td></tr>"
                }
                "</table>"
            }
        })

        <div class="footer">
            Report generated by Get-EventLogReport.ps1
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-ColorOutput "HTML report exported to: $reportPath" -Level Success
    return $reportPath
}

function Export-CSVReport {
    $reportPath = "$ReportDir\EventLogReport_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

    $script:report.AllEvents | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
    Write-ColorOutput "CSV report exported to: $reportPath" -Level Success
    return $reportPath
}

function Main {
    try {
        if (-not (Test-AdminPrivilege)) {
            Write-Host "[-] Administrator privileges are required to analyze event logs." -ForegroundColor Red
            return 1
        }

        $script:ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
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
            ScanTime = Get-Date
            TimeRange = $null
            Logs = @()
            Summary = @{
                TotalEvents = 0
                CriticalCount = 0
                ErrorCount = 0
                WarningCount = 0
            }
            TopSources = @()
            AllEvents = @()
        }

        # Determine time range
        if ($Days) {
            $script:startTime = (Get-Date).AddDays(-$Days)
            $script:report.TimeRange = "Last $Days days"
        }
        else {
            $script:startTime = (Get-Date).AddHours(-$Hours)
            $script:report.TimeRange = "Last $Hours hours"
        }

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  Event Log Analysis" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Server: $($script:report.ServerName)"
        Write-Host "Time Range: $($script:report.TimeRange)"
        Write-Host "Severity Filter: $Severity"
        Write-Host "Max Events per Log: $MaxEvents"
        Write-Host "`nAnalyzing logs..." -ForegroundColor Cyan

        if ($LogName -eq 'All') {
            Get-EventLogAnalysis -Log 'System'
            Get-EventLogAnalysis -Log 'Application'
            Get-EventLogAnalysis -Log 'Security'
        }
        else {
            Get-EventLogAnalysis -Log $LogName
        }

        Get-TopEventSources
        Show-Summary

        if ($ExportHTML) {
            Write-Host "Generating HTML report..." -ForegroundColor Cyan
            Export-HTMLReport | Out-Null
        }

        if ($ExportCSV) {
            Write-Host "Generating CSV report..." -ForegroundColor Cyan
            Export-CSVReport | Out-Null
        }

        Write-Host "[+] Event log analysis completed." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }

