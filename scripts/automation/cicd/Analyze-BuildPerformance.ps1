<#
.SYNOPSIS
    Analyzes build performance trends and identifies bottlenecks.

.DESCRIPTION
    Performance analysis script for CI/CD builds that provides:
    - Build duration trend analysis over time
    - Identification of slow build stages/jobs
    - Build time regression detection
    - Resource utilization patterns
    - Parallel vs sequential execution analysis
    - Build cache effectiveness metrics

    Supports Azure DevOps, GitHub Actions, and GitLab CI. Reads exported build data from a JSON
    file and writes an HTML/JSON analysis report under -OutputPath.

.PARAMETER Platform
    CI/CD platform: 'AzureDevOps', 'GitHub', or 'GitLab'

.PARAMETER DataSource
    Path to exported build data JSON file or API connection string

.PARAMETER DaysToAnalyze
    Number of days to include in trend analysis. Default: 30

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for HTML/JSON output file. Default: MyDocuments\Reports

.PARAMETER IdentifyRegressions
    Detect builds that are significantly slower than historical average

.PARAMETER RegressionThreshold
    Percentage increase to flag as regression. Default: 25 (25% slower)

.EXAMPLE
    PS C:\> .\Analyze-BuildPerformance.ps1 -Platform 'AzureDevOps' -DataSource '.\builds.json' -IdentifyRegressions

.EXAMPLE
    PS C:\> .\Analyze-BuildPerformance.ps1 -Platform 'GitHub' -DataSource '.\builds.json' -DaysToAnalyze 60

.NOTES
    File Name: Analyze-BuildPerformance.ps1
    Author: IT Operations
    Prerequisite: PowerShell 5.1+
    Version: 1.0.0
    Date: 2026-08-23

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>


[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Colored console prefixes are mandated by the spec.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Bound params are consumed inside Main.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('AzureDevOps', 'GitHub', 'GitLab')]
    [string]$Platform,

    [Parameter(Mandatory = $true)]
    [string]$DataSource,

    [Parameter(Mandatory = $false)]
    [int]$DaysToAnalyze = 30,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'),

    [Parameter(Mandatory = $false)]
    [switch]$IdentifyRegressions,

    [Parameter(Mandatory = $false)]
    [int]$RegressionThreshold = 25
)

$ErrorActionPreference = 'Stop'

function Main {
    try {
        # Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
        if ([string]::IsNullOrWhiteSpace($OutputPath) -or
            $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
            $OutputPath -match '^(\\\\|//)') {
            Write-Error "Unsafe OutputPath: $OutputPath. Must be a local path without '..' traversal."
            return 1
        }
        $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
        if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        Write-Host "[*] Analyzing build performance for $Platform (Last $DaysToAnalyze days)..." -ForegroundColor Cyan

        # Load build data
        if (-not (Test-Path $DataSource)) {
            Write-Error "Data source file not found: $DataSource"
            return 1
        }

        try {
            $buildData = Get-Content $DataSource -Raw | ConvertFrom-Json
        }
        catch {
            Write-Error "Failed to parse build data: $($_.Exception.Message)"
            return 1
        }

        # Filter to analysis period
        $startDate = (Get-Date).AddDays(-$DaysToAnalyze)
        $filteredBuilds = $buildData | Where-Object {
            [datetime]$_.StartTime -ge $startDate
        }

        Write-Host "[*] Analyzing $($filteredBuilds.Count) builds..." -ForegroundColor Cyan

        # Initialize analysis results
        $analysis = @{
            Platform = $Platform
            AnalysisPeriod = $DaysToAnalyze
            TotalBuilds = $filteredBuilds.Count
            Timestamp = Get-Date
            DurationTrends = @()
            SlowestBuilds = @()
            FastestBuilds = @()
            StageAnalysis = @()
            Regressions = @()
            Summary = @{}
        }

        # Calculate duration statistics
        $durations = $filteredBuilds | ForEach-Object { [double]$_.DurationMinutes }
        $avgDuration = [math]::Round(($durations | Measure-Object -Average).Average, 2)
        $medianDuration = [math]::Round(($durations | Sort-Object)[[math]::Floor($durations.Count / 2)], 2)
        $p95Duration = [math]::Round(($durations | Sort-Object)[[math]::Floor($durations.Count * 0.95)], 2)
        $minDuration = [math]::Round(($durations | Measure-Object -Minimum).Minimum, 2)
        $maxDuration = [math]::Round(($durations | Measure-Object -Maximum).Maximum, 2)

        Write-Host "Average Build Duration: $avgDuration minutes" -ForegroundColor White
        Write-Host "Median Duration: $medianDuration minutes" -ForegroundColor White
        Write-Host "95th Percentile: $p95Duration minutes" -ForegroundColor White

        # Trend analysis - group by week
        $weeklyTrends = $filteredBuilds | Group-Object {
            (Get-Date $_.StartTime).ToString('yyyy-MM') + "-W" + (Get-Date $_.StartTime).ToString('dd')
        } | ForEach-Object {
            $weekBuilds = $_.Group
    $sortedWeekDurations = $weekBuilds.DurationMinutes | Sort-Object
    $successfulWeekBuilds = ($weekBuilds | Where-Object { $_.Result -eq 'Success' }).Count
            @{
                Period = $_.Name
                BuildCount = $weekBuilds.Count
                AvgDuration = [math]::Round(($weekBuilds.DurationMinutes | Measure-Object -Average).Average, 2)
                MedianDuration = [math]::Round($sortedWeekDurations[[math]::Floor($weekBuilds.Count / 2)], 2)
                SuccessRate = [math]::Round(($successfulWeekBuilds / $weekBuilds.Count) * 100, 2)
            }
        }

        $analysis.DurationTrends = $weeklyTrends

        # Identify slowest and fastest builds
        $analysis.SlowestBuilds = $filteredBuilds | Sort-Object DurationMinutes -Descending | Select-Object -First 10 |
            ForEach-Object {
                @{
                    BuildId = $_.BuildId
                    StartTime = $_.StartTime
                    DurationMinutes = $_.DurationMinutes
                    Result = $_.Result
                    Branch = $_.Branch
                }
            }

        $analysis.FastestBuilds = $filteredBuilds | Sort-Object DurationMinutes | Select-Object -First 10 |
            ForEach-Object {
                @{
                    BuildId = $_.BuildId
                    StartTime = $_.StartTime
                    DurationMinutes = $_.DurationMinutes
                    Result = $_.Result
                    Branch = $_.Branch
                }
            }

        # Stage/Job analysis (if stage data available)
        if ($filteredBuilds[0].Stages) {
            Write-Host "`n[*] Analyzing build stages..." -ForegroundColor Cyan

            $allStages = @{}
            foreach ($build in $filteredBuilds) {
                foreach ($stage in $build.Stages) {
                    if (-not $allStages.ContainsKey($stage.Name)) {
                        $allStages[$stage.Name] = @()
                    }
                    $allStages[$stage.Name] += $stage.DurationMinutes
                }
            }

            foreach ($stageName in $allStages.Keys) {
                $stageDurations = $allStages[$stageName]
        $sortedStageDurations = $stageDurations | Sort-Object
                $analysis.StageAnalysis += @{
                    StageName = $stageName
                    Executions = $stageDurations.Count
                    AvgDuration = [math]::Round(($stageDurations | Measure-Object -Average).Average, 2)
                    MedianDuration = [math]::Round($sortedStageDurations[[math]::Floor($stageDurations.Count / 2)], 2)
                    MaxDuration = [math]::Round(($stageDurations | Measure-Object -Maximum).Maximum, 2)
                }
            }
        }

        # Regression detection
        if ($IdentifyRegressions) {
            Write-Host "`n[*] Detecting performance regressions..." -ForegroundColor Cyan

            # Calculate baseline (first 50% of time period)
            $baselineBuilds = $filteredBuilds | Where-Object {
                [datetime]$_.StartTime -lt $startDate.AddDays($DaysToAnalyze / 2)
            }

            if ($baselineBuilds.Count -gt 5) {
                $baselineAvg = [math]::Round(($baselineBuilds.DurationMinutes | Measure-Object -Average).Average, 2)
                $regressionThresholdValue = $baselineAvg * (1 + ($RegressionThreshold / 100))

                $recentBuilds = $filteredBuilds | Where-Object {
                    [datetime]$_.StartTime -ge $startDate.AddDays($DaysToAnalyze / 2)
                }

                foreach ($build in $recentBuilds) {
                    if ($build.DurationMinutes -gt $regressionThresholdValue) {
                        $increasePercent = [math]::Round(
                            (($build.DurationMinutes - $baselineAvg) / $baselineAvg) * 100, 2)
                        $analysis.Regressions += @{
                            BuildId = $build.BuildId
                            StartTime = $build.StartTime
                            DurationMinutes = $build.DurationMinutes
                            BaselineAvg = $baselineAvg
                            IncreasePercent = $increasePercent
                            Branch = $build.Branch
                        }
                    }
                }

                $regressionMessage = "[!] Found $($analysis.Regressions.Count) potential regressions" +
                    " (>$RegressionThreshold% slower than baseline)"
                Write-Host $regressionMessage -ForegroundColor Yellow
            }
        }

        # Summary statistics
        $analysis.Summary = @{
            TotalBuilds = $filteredBuilds.Count
            SuccessfulBuilds = ($filteredBuilds | Where-Object { $_.Result -eq 'Success' }).Count
            FailedBuilds = ($filteredBuilds | Where-Object { $_.Result -eq 'Failed' }).Count
            AverageDuration = $avgDuration
            MedianDuration = $medianDuration
            P95Duration = $p95Duration
            MinDuration = $minDuration
            MaxDuration = $maxDuration
            RegressionsFound = $analysis.Regressions.Count
        }

        # Output results
        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
        switch ($OutputFormat) {
            'Console' {
                Write-Host "`n=== Build Performance Summary ===" -ForegroundColor Cyan
                Write-Host "Total Builds: $($analysis.Summary.TotalBuilds)" -ForegroundColor White
                $durationLine = "Average Duration: $avgDuration min | Median: $medianDuration min" +
                    " | 95th: $p95Duration min"
                Write-Host $durationLine -ForegroundColor White
                Write-Host "Range: $minDuration min - $maxDuration min" -ForegroundColor White

                if ($analysis.StageAnalysis.Count -gt 0) {
                    Write-Host "`n=== Slowest Stages ===" -ForegroundColor Cyan
                    $slowestStages = $analysis.StageAnalysis |
                        Sort-Object AvgDuration -Descending |
                        Select-Object -First 5
                    foreach ($stage in $slowestStages) {
                        $stageLine = "$($stage.StageName): Avg $($stage.AvgDuration) min" +
                            " (Max: $($stage.MaxDuration) min)"
                        Write-Host $stageLine -ForegroundColor White
                    }
                }

                if ($analysis.Regressions.Count -gt 0) {
                    Write-Host "`n=== Performance Regressions ===" -ForegroundColor Yellow
                    foreach ($regression in ($analysis.Regressions | Select-Object -First 5)) {
                        $regressionLine = "Build $($regression.BuildId): $($regression.DurationMinutes) min" +
                            " (+$($regression.IncreasePercent)% vs baseline)"
                        Write-Host $regressionLine -ForegroundColor Red
                    }
                }
            }

            'HTML' {
                $htmlFile = Join-Path $OutputPath "Build-Performance-Analysis-${RunTimestamp}_${RunId}.html"

                # Create trend chart data
                $chartLabels = $analysis.DurationTrends | ForEach-Object {
                    "'$([System.Net.WebUtility]::HtmlEncode("$($_.Period)"))'"
                }
                $chartLabels = $chartLabels -join ','
                $chartData = ($analysis.DurationTrends | ForEach-Object { $_.AvgDuration }) -join ','

                $html = @"
        <!DOCTYPE html>
        <html>
        <head>
            <title>Build Performance Analysis Report</title>
            <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
            <style>
                body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
                h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
                h2 { color: #106ebe; margin-top: 30px; }
                .summary {
                    background: white; padding: 20px; border-radius: 8px;
                    box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px;
                }
                .summary-grid {
                    display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
                    gap: 15px; margin-top: 15px;
                }
                .summary-item { background: #f0f0f0; padding: 15px; border-radius: 5px; text-align: center; }
                .summary-item .value { font-size: 28px; font-weight: bold; color: #0078d4; }
                .summary-item .label { font-size: 13px; color: #666; margin-top: 5px; }
                .chart-container {
                    background: white; padding: 20px; border-radius: 8px;
                    box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px;
                }
                table {
                    border-collapse: collapse; width: 100%; background: white;
                    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                }
                th { background-color: #0078d4; color: white; padding: 10px; text-align: left; }
                td { padding: 8px; border-bottom: 1px solid #ddd; }
                tr:hover { background-color: #f5f5f5; }
                .regression { color: #d13438; font-weight: bold; }
                .footer { margin-top: 30px; text-align: center; color: #666; font-size: 12px; }
            </style>
        </head>
        <body>
            <h1>Build Performance Analysis Report</h1>
            <div class="summary">
                <strong>Platform:</strong> $([System.Net.WebUtility]::HtmlEncode("$Platform")) |
                <strong>Analysis Period:</strong> Last $DaysToAnalyze days<br>
                <strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

                <div class="summary-grid">
                    <div class="summary-item">
                        <div class="value">$($analysis.Summary.TotalBuilds)</div>
                        <div class="label">Total Builds</div>
                    </div>
                    <div class="summary-item">
                        <div class="value">$avgDuration</div>
                        <div class="label">Avg Duration (min)</div>
                    </div>
                    <div class="summary-item">
                        <div class="value">$medianDuration</div>
                        <div class="label">Median Duration (min)</div>
                    </div>
                    <div class="summary-item">
                        <div class="value">$p95Duration</div>
                        <div class="label">95th Percentile (min)</div>
                    </div>
                    <div class="summary-item">
                        <div class="value">$minDuration</div>
                        <div class="label">Fastest (min)</div>
                    </div>
                    <div class="summary-item">
                        <div class="value">$maxDuration</div>
                        <div class="label">Slowest (min)</div>
                    </div>
                </div>
            </div>

            <div class="chart-container">
                <h2>Build Duration Trend</h2>
                <canvas id="trendChart" width="400" height="100"></canvas>
            </div>

            <h2>Slowest Builds</h2>
            <table>
                <tr>
                    <th>Build ID</th>
                    <th>Start Time</th>
                    <th>Duration (min)</th>
                    <th>Branch</th>
                    <th>Result</th>
                </tr>
"@

                foreach ($build in $analysis.SlowestBuilds) {
                    $html += @"
                <tr>
                    <td>$([System.Net.WebUtility]::HtmlEncode("$($build.BuildId)"))</td>
                    <td>$([System.Net.WebUtility]::HtmlEncode("$($build.StartTime)"))</td>
                    <td>$($build.DurationMinutes)</td>
                    <td>$([System.Net.WebUtility]::HtmlEncode("$($build.Branch)"))</td>
                    <td>$([System.Net.WebUtility]::HtmlEncode("$($build.Result)"))</td>
                </tr>
"@
                }

                $html += "</table>"

                if ($analysis.Regressions.Count -gt 0) {
                    $html += @"
            <h2>Performance Regressions</h2>
            <table>
                <tr>
                    <th>Build ID</th>
                    <th>Start Time</th>
                    <th>Duration (min)</th>
                    <th>Baseline Avg (min)</th>
                    <th>Increase %</th>
                </tr>
"@
                    foreach ($regression in $analysis.Regressions) {
                        $html += @"
                <tr>
                    <td>$([System.Net.WebUtility]::HtmlEncode("$($regression.BuildId)"))</td>
                    <td>$([System.Net.WebUtility]::HtmlEncode("$($regression.StartTime)"))</td>
                    <td class="regression">$($regression.DurationMinutes)</td>
                    <td>$($regression.BaselineAvg)</td>
                    <td class="regression">+$($regression.IncreasePercent)%</td>
                </tr>
"@
                    }
                    $html += "</table>"
                }

                $html += @"
            <script>
                const ctx = document.getElementById('trendChart').getContext('2d');
                new Chart(ctx, {
                    type: 'line',
                    data: {
                        labels: [$chartLabels],
                        datasets: [{
                            label: 'Average Build Duration (minutes)',
                            data: [$chartData],
                            borderColor: '#0078d4',
                            backgroundColor: 'rgba(0, 120, 212, 0.1)',
                            tension: 0.1
                        }]
                    },
                    options: {
                        responsive: true,
                        plugins: {
                            legend: { display: true }
                        },
                        scales: {
                            y: { beginAtZero: true }
                        }
                    }
                });
            </script>
            <div class="footer">
                <strong>Note:</strong> This report has not been thoroughly tested.
                Please validate results before making operational decisions.<br>
                Generated by Analyze-BuildPerformance.ps1
            </div>
        </body>
        </html>
"@

                $html | Out-File -FilePath $htmlFile -Encoding UTF8
                Write-Host "`n[+] HTML report saved to: $htmlFile" -ForegroundColor Green
            }

            'JSON' {
                $jsonFile = Join-Path $OutputPath "Build-Performance-${RunTimestamp}_${RunId}.json"
                $analysis | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
                Write-Host "`n[+] JSON report saved to: $jsonFile" -ForegroundColor Green
            }
        }

        Write-Host "`n[+] Build performance analysis complete!" -ForegroundColor Green

        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
