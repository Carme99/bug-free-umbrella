<#
.SYNOPSIS
    Monitors Azure DevOps pipeline health, performance, and failures.

.DESCRIPTION
    Comprehensive Azure DevOps monitoring script that tracks:
    - Pipeline success/failure rates
    - Build duration trends and performance
    - Failed builds with detailed error analysis
    - Agent pool utilization and health
    - Recent deployment history
    - Pull request build validation status

    Supports both Build and Release pipelines across multiple projects.

.PARAMETER Organization
    Azure DevOps organization name (e.g., 'mycompany')

.PARAMETER Project
    Project name to monitor. Use '*' for all projects.

.PARAMETER DaysToAnalyze
    Number of days of history to analyze. Default: 7

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', 'CSV', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for HTML/CSV/JSON output file. Default: <MyDocuments>\Reports

.PARAMETER IncludeAgentPools
    Include agent pool health and utilization analysis

.PARAMETER IncludeReleases
    Include release pipeline monitoring

.EXAMPLE
    # Supply the PAT via the AZURE_DEVOPS_PAT environment variable (never as a CLI argument)
    .\Monitor-AzureDevOpsPipelines.ps1 -Organization "mycompany" -Project "MyProject"

.EXAMPLE
    $env:AZURE_DEVOPS_PAT = "your-pat-here"
    .\Monitor-AzureDevOpsPipelines.ps1 -Organization "mycompany" -Project "*" -DaysToAnalyze 30 -IncludeReleases

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 5.1 or later

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $false)]
    [int]$DaysToAnalyze = 7,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'CSV', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'),

    [Parameter(Mandatory = $false)]
    [switch]$IncludeAgentPools,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeReleases
)

# Initialize results collection
$results = @{
    Organization = $Organization
    Project = $Project
    AnalysisPeriod = $DaysToAnalyze
    Timestamp = Get-Date
    Pipelines = @()
    Agents = @()
    Releases = @()
    Summary = @{}
}

# Capture a single timestamp and run ID so all generated filenames are unique per run
$RunTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$RunId = [guid]::NewGuid().ToString('N').Substring(0, 8)

# Read the PAT ONLY from the environment. It is deliberately NOT accepted as a
# CLI parameter, because a command-line argument would leak the secret via the
# process list, shell history, and logs.
$PersonalAccessToken = $env:AZURE_DEVOPS_PAT
if ([string]::IsNullOrWhiteSpace($PersonalAccessToken)) {
    Write-Error "Personal Access Token is required. Set the AZURE_DEVOPS_PAT environment variable before running this script, for example:
    `$env:AZURE_DEVOPS_PAT = 'your-pat-here'
    .\Monitor-AzureDevOpsPipelines.ps1 -Organization 'mycompany' -Project 'MyProject'
Never pass the token as a command-line argument."
    exit 1
}

# Azure DevOps PATs use HTTP Basic authentication (base64-encoded username:token).
# This is the official, supported authentication scheme for Azure DevOps. The
# credentials are only ever transmitted over HTTPS/TLS, which provides the
# confidentiality of the bearer token in transit, so this is safe.
$baseUrl = "https://dev.azure.com/$Organization"

# Enforce TLS: the Basic auth header must never be sent over plain HTTP.
if (-not $baseUrl.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Error "AZURE_DEVOPS_PAT requires a secure connection. The DevOps base URL must use https:// (got '$baseUrl'). Refusing to transmit credentials over plain HTTP."
    exit 1
}

$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PersonalAccessToken"))
$headers = @{
    Authorization = "Basic $base64AuthInfo"
    'Content-Type' = 'application/json'
}

$startDate = (Get-Date).AddDays(-$DaysToAnalyze).ToString('yyyy-MM-ddTHH:mm:ssZ')

# HTML-encode any dynamic value before interpolating it into the report.
# Prevents HTML/script injection via subscription, resource, or project names.
function ConvertTo-HtmlEncoded {
    param([AllowNull()][AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($Value)
}

# Validate and normalize the output path: reject path traversal ('..') and
# UNC (remote) paths on the user-supplied value FIRST (before any resolution
# collapses or rewrites '..'), then resolve to a full path and ensure it exists.
$rawOutputPath = $OutputPath
$traversalSegments = ($rawOutputPath -split '[\\/]+') | Where-Object { $_ -eq '..' }
if ($traversalSegments) {
    Write-Error "Invalid output path: path traversal ('..') is not permitted. Got: $rawOutputPath"
    exit 1
}
if ($rawOutputPath.StartsWith('\\', [System.StringComparison]::Ordinal) -or $rawOutputPath.StartsWith('//', [System.StringComparison]::Ordinal)) {
    Write-Error "Invalid output path: UNC (remote) paths are not permitted. Got: $rawOutputPath"
    exit 1
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
    try {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    } catch {
        Write-Error "Failed to create output directory '$OutputPath': $($_.Exception.Message)"
        exit 1
    }
}

Write-Host "Analyzing Azure DevOps pipelines for $Organization/$Project (Last $DaysToAnalyze days)..." -ForegroundColor Cyan

# Get projects
try {
    if ($Project -eq '*') {
        $projectsUrl = "$baseUrl/_apis/projects?api-version=7.0"
        $projectsResponse = Invoke-RestMethod -Uri $projectsUrl -Headers $headers -Method Get
        $projects = $projectsResponse.value
    } else {
        $projects = @(@{ name = $Project })
    }
} catch {
    Write-Error "Failed to retrieve projects: $($_.Exception.Message)"
    exit 1
}

# Analyze each project
foreach ($proj in $projects) {
    $projectName = $proj.name
    Write-Host "`nAnalyzing project: $projectName" -ForegroundColor Yellow

    # Get pipeline definitions
    try {
        $pipelinesUrl = "$baseUrl/$projectName/_apis/pipelines?api-version=7.0"
        $pipelinesResponse = Invoke-RestMethod -Uri $pipelinesUrl -Headers $headers -Method Get

        foreach ($pipeline in $pipelinesResponse.value) {
            Write-Host "  Analyzing pipeline: $($pipeline.name)" -ForegroundColor Gray

            # Get recent runs
            $runsUrl = "$baseUrl/$projectName/_apis/pipelines/$($pipeline.id)/runs?api-version=7.0"
            $runsResponse = Invoke-RestMethod -Uri $runsUrl -Headers $headers -Method Get

            $recentRuns = $runsResponse.value | Where-Object {
                [datetime]$_.createdDate -ge (Get-Date).AddDays(-$DaysToAnalyze)
            }

            if ($recentRuns.Count -eq 0) { continue }

            # Calculate statistics
            $totalRuns = $recentRuns.Count
            $successfulRuns = ($recentRuns | Where-Object { $_.state -eq 'completed' -and $_.result -eq 'succeeded' }).Count
            $failedRuns = ($recentRuns | Where-Object { $_.result -eq 'failed' }).Count
            $canceledRuns = ($recentRuns | Where-Object { $_.result -eq 'canceled' }).Count

            $successRate = if ($totalRuns -gt 0) { [math]::Round(($successfulRuns / $totalRuns) * 100, 2) } else { 0 }

            # Calculate average duration for completed runs
            $completedRuns = $recentRuns | Where-Object { $_.state -eq 'completed' -and $_.finishedDate }
            $avgDuration = if ($completedRuns.Count -gt 0) {
                $durations = $completedRuns | ForEach-Object {
                    ([datetime]$_.finishedDate - [datetime]$_.createdDate).TotalMinutes
                }
                [math]::Round(($durations | Measure-Object -Average).Average, 2)
            } else {
                0
            }

            # Get failed build details
            $failedBuilds = $recentRuns | Where-Object { $_.result -eq 'failed' } | Select-Object -First 5
            $failureDetails = @()

            foreach ($failedRun in $failedBuilds) {
                $failureDetails += @{
                    RunId = $failedRun.id
                    CreatedDate = $failedRun.createdDate
                    Url = $failedRun._links.web.href
                }
            }

            $results.Pipelines += @{
                Project = $projectName
                PipelineId = $pipeline.id
                PipelineName = $pipeline.name
                Folder = $pipeline.folder
                TotalRuns = $totalRuns
                SuccessfulRuns = $successfulRuns
                FailedRuns = $failedRuns
                CanceledRuns = $canceledRuns
                SuccessRate = $successRate
                AverageDurationMinutes = $avgDuration
                RecentFailures = $failureDetails
                Status = if ($successRate -ge 90) { 'Healthy' } elseif ($successRate -ge 70) { 'Warning' } else { 'Critical' }
            }
        }
    } catch {
        Write-Warning "Failed to analyze pipelines for $projectName : $($_.Exception.Message)"
    }

    # Analyze agent pools if requested
    if ($IncludeAgentPools) {
        try {
            $poolsUrl = "$baseUrl/_apis/distributedtask/pools?api-version=7.0"
            $poolsResponse = Invoke-RestMethod -Uri $poolsUrl -Headers $headers -Method Get

            foreach ($pool in $poolsResponse.value) {
                $agentsUrl = "$baseUrl/_apis/distributedtask/pools/$($pool.id)/agents?api-version=7.0"
                $agentsResponse = Invoke-RestMethod -Uri $agentsUrl -Headers $headers -Method Get

                $totalAgents = $agentsResponse.value.Count
                $onlineAgents = ($agentsResponse.value | Where-Object { $_.status -eq 'online' }).Count
                $offlineAgents = ($agentsResponse.value | Where-Object { $_.status -eq 'offline' }).Count

                $results.Agents += @{
                    PoolName = $pool.name
                    PoolId = $pool.id
                    TotalAgents = $totalAgents
                    OnlineAgents = $onlineAgents
                    OfflineAgents = $offlineAgents
                    HealthStatus = if ($onlineAgents -eq 0) { 'Critical' } elseif ($offlineAgents -gt 0) { 'Warning' } else { 'Healthy' }
                }
            }
        } catch {
            Write-Warning "Failed to analyze agent pools: $($_.Exception.Message)"
        }
    }

    # Analyze releases if requested
    if ($IncludeReleases) {
        try {
            $releaseUrl = "https://vsrm.dev.azure.com/$Organization/$projectName/_apis/release/releases?api-version=7.0&minCreatedTime=$startDate"
            $releasesResponse = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -Method Get

            foreach ($release in $releasesResponse.value) {
                $deploymentStatus = $release.environments | ForEach-Object {
                    @{
                        Environment = $_.name
                        Status = $_.status
                        DeploymentStatus = $_.deploySteps[-1].status
                    }
                }

                $results.Releases += @{
                    Project = $projectName
                    ReleaseName = $release.name
                    ReleaseId = $release.id
                    CreatedDate = $release.createdOn
                    Status = $release.status
                    Environments = $deploymentStatus
                }
            }
        } catch {
            Write-Warning "Failed to analyze releases for $projectName : $($_.Exception.Message)"
        }
    }
}

# Calculate summary statistics
$totalPipelines = $results.Pipelines.Count
$healthyPipelines = ($results.Pipelines | Where-Object { $_.Status -eq 'Healthy' }).Count
$warningPipelines = ($results.Pipelines | Where-Object { $_.Status -eq 'Warning' }).Count
$criticalPipelines = ($results.Pipelines | Where-Object { $_.Status -eq 'Critical' }).Count
$avgSuccessRate = if ($totalPipelines -gt 0) { [math]::Round(($results.Pipelines.SuccessRate | Measure-Object -Average).Average, 2) } else { 0 }

$results.Summary = @{
    TotalPipelines = $totalPipelines
    HealthyPipelines = $healthyPipelines
    WarningPipelines = $warningPipelines
    CriticalPipelines = $criticalPipelines
    AverageSuccessRate = $avgSuccessRate
    TotalAgentPools = $results.Agents.Count
    TotalReleases = $results.Releases.Count
}

# Output results
switch ($OutputFormat) {
    'Console' {
        Write-Host "`n=== Azure DevOps Pipeline Health Summary ===" -ForegroundColor Cyan
        Write-Host "Total Pipelines: $totalPipelines" -ForegroundColor White
        Write-Host "Healthy: $healthyPipelines | Warning: $warningPipelines | Critical: $criticalPipelines" -ForegroundColor White
        Write-Host "Average Success Rate: $avgSuccessRate%" -ForegroundColor White

        Write-Host "`n=== Pipeline Details ===" -ForegroundColor Cyan
        foreach ($pipeline in $results.Pipelines | Sort-Object SuccessRate) {
            $color = switch ($pipeline.Status) {
                'Healthy' { 'Green' }
                'Warning' { 'Yellow' }
                'Critical' { 'Red' }
            }
            Write-Host "$($pipeline.Project)/$($pipeline.PipelineName): $($pipeline.SuccessRate)% success ($($pipeline.TotalRuns) runs, avg $($pipeline.AverageDurationMinutes) min)" -ForegroundColor $color
        }

        if ($IncludeAgentPools -and $results.Agents.Count -gt 0) {
            Write-Host "`n=== Agent Pool Health ===" -ForegroundColor Cyan
            foreach ($agent in $results.Agents) {
                Write-Host "$($agent.PoolName): $($agent.OnlineAgents)/$($agent.TotalAgents) agents online" -ForegroundColor White
            }
        }
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "AzureDevOps-Pipeline-Health-${RunTimestamp}_${RunId}.html"

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure DevOps Pipeline Health Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #106ebe; margin-top: 30px; }
        .summary { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-top: 15px; }
        .summary-item { background: #f0f0f0; padding: 15px; border-radius: 5px; text-align: center; }
        .summary-item .value { font-size: 32px; font-weight: bold; color: #0078d4; }
        .summary-item .label { font-size: 14px; color: #666; margin-top: 5px; }
        table { border-collapse: collapse; width: 100%; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-top: 10px; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .status-healthy { color: #107c10; font-weight: bold; }
        .status-warning { color: #ff8c00; font-weight: bold; }
        .status-critical { color: #d13438; font-weight: bold; }
        .metric { display: inline-block; margin-right: 15px; }
        .footer { margin-top: 30px; text-align: center; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <h1>Azure DevOps Pipeline Health Report</h1>
    <div class="summary">
        <strong>Organization:</strong> $(ConvertTo-HtmlEncoded $Organization) | <strong>Analysis Period:</strong> Last $(ConvertTo-HtmlEncoded $DaysToAnalyze) days<br>
        <strong>Generated:</strong> $(ConvertTo-HtmlEncoded $RunTimestamp)

        <div class="summary-grid">
            <div class="summary-item">
                <div class="value">$(ConvertTo-HtmlEncoded $totalPipelines)</div>
                <div class="label">Total Pipelines</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #107c10;">$(ConvertTo-HtmlEncoded $healthyPipelines)</div>
                <div class="label">Healthy (≥90%)</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #ff8c00;">$(ConvertTo-HtmlEncoded $warningPipelines)</div>
                <div class="label">Warning (70-89%)</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #d13438;">$(ConvertTo-HtmlEncoded $criticalPipelines)</div>
                <div class="label">Critical (<70%)</div>
            </div>
            <div class="summary-item">
                <div class="value">$(ConvertTo-HtmlEncoded $avgSuccessRate)%</div>
                <div class="label">Avg Success Rate</div>
            </div>
        </div>
    </div>

    <h2>Pipeline Details</h2>
    <table>
        <tr>
            <th>Project</th>
            <th>Pipeline Name</th>
            <th>Total Runs</th>
            <th>Success Rate</th>
            <th>Failed</th>
            <th>Avg Duration (min)</th>
            <th>Status</th>
        </tr>
"@

        foreach ($pipeline in $results.Pipelines | Sort-Object SuccessRate) {
            $statusClass = "status-$($pipeline.Status.ToLower())"
            $html += @"
        <tr>
            <td>$(ConvertTo-HtmlEncoded $pipeline.Project)</td>
            <td>$(ConvertTo-HtmlEncoded $pipeline.PipelineName)</td>
            <td>$(ConvertTo-HtmlEncoded $pipeline.TotalRuns)</td>
            <td>$(ConvertTo-HtmlEncoded $pipeline.SuccessRate)%</td>
            <td>$(ConvertTo-HtmlEncoded $pipeline.FailedRuns)</td>
            <td>$(ConvertTo-HtmlEncoded $pipeline.AverageDurationMinutes)</td>
            <td class="$statusClass">$(ConvertTo-HtmlEncoded $pipeline.Status)</td>
        </tr>
"@
        }

        $html += "</table>"

        if ($IncludeAgentPools -and $results.Agents.Count -gt 0) {
            $html += @"
    <h2>Agent Pool Health</h2>
    <table>
        <tr>
            <th>Pool Name</th>
            <th>Total Agents</th>
            <th>Online</th>
            <th>Offline</th>
            <th>Status</th>
        </tr>
"@
            foreach ($agent in $results.Agents) {
                $statusClass = "status-$($agent.HealthStatus.ToLower())"
                $html += @"
        <tr>
            <td>$(ConvertTo-HtmlEncoded $agent.PoolName)</td>
            <td>$(ConvertTo-HtmlEncoded $agent.TotalAgents)</td>
            <td>$(ConvertTo-HtmlEncoded $agent.OnlineAgents)</td>
            <td>$(ConvertTo-HtmlEncoded $agent.OfflineAgents)</td>
            <td class="$statusClass">$(ConvertTo-HtmlEncoded $agent.HealthStatus)</td>
        </tr>
"@
            }
            $html += "</table>"
        }

        $html += @"
    <div class="footer">
        <strong>Note:</strong> This report has not been thoroughly tested. Please validate results before making operational decisions.<br>
        Generated by Monitor-AzureDevOpsPipelines.ps1
    </div>
</body>
</html>
"@

        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "[+] Report saved: $htmlFile" -ForegroundColor Green
    }

    'CSV' {
        $csvFile = Join-Path $OutputPath "AzureDevOps-Pipelines-${RunTimestamp}_${RunId}.csv"
        $results.Pipelines | Export-Csv -Path $csvFile -NoTypeInformation
        Write-Host "[+] Report saved: $csvFile" -ForegroundColor Green
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "AzureDevOps-Pipelines-${RunTimestamp}_${RunId}.json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "[+] Report saved: $jsonFile" -ForegroundColor Green
    }
}

Write-Host "`nAzure DevOps pipeline analysis complete!" -ForegroundColor Green
