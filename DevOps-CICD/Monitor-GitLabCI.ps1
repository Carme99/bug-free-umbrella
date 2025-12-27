<#
.SYNOPSIS
    Monitors GitLab CI/CD pipeline health and performance.

.DESCRIPTION
    Comprehensive GitLab CI monitoring script that tracks:
    - Pipeline success/failure rates across projects
    - Job-level execution analysis and failure patterns
    - Runner health and availability
    - Pipeline duration trends and bottlenecks
    - Deployment frequency and success rates
    - Environment-specific deployment status

.PARAMETER GitLabUrl
    GitLab instance URL (e.g., 'https://gitlab.com' or 'https://gitlab.mycompany.com')

.PARAMETER ProjectId
    GitLab project ID or path (e.g., 'group/project'). Use '*' for all accessible projects.

.PARAMETER PrivateToken
    GitLab Personal Access Token with 'read_api' scope.
    Can also be provided via environment variable GITLAB_TOKEN

.PARAMETER DaysToAnalyze
    Number of days of pipeline history to analyze. Default: 7

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', 'CSV', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for HTML/CSV/JSON output file. Default: Desktop

.PARAMETER IncludeRunners
    Include GitLab Runner health and utilization analysis

.PARAMETER IncludeDeployments
    Include deployment environment analysis

.EXAMPLE
    .\Monitor-GitLabCI.ps1 -GitLabUrl "https://gitlab.com" -ProjectId "mygroup/myproject" -PrivateToken "glpat-token123"

.EXAMPLE
    $token = $env:GITLAB_TOKEN
    .\Monitor-GitLabCI.ps1 -GitLabUrl "https://gitlab.company.com" -ProjectId "*" -PrivateToken $token -DaysToAnalyze 30

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
    [string]$GitLabUrl,

    [Parameter(Mandatory = $true)]
    [string]$ProjectId,

    [Parameter(Mandatory = $false)]
    [string]$PrivateToken = $env:GITLAB_TOKEN,

    [Parameter(Mandatory = $false)]
    [int]$DaysToAnalyze = 7,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'CSV', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = [Environment]::GetFolderPath('Desktop'),

    [Parameter(Mandatory = $false)]
    [switch]$IncludeRunners,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDeployments
)

# Validate token
if ([string]::IsNullOrWhiteSpace($PrivateToken)) {
    Write-Error "GitLab token is required. Provide via -PrivateToken or GITLAB_TOKEN environment variable"
    exit 1
}

# Initialize results
$results = @{
    GitLabUrl = $GitLabUrl
    ProjectId = $ProjectId
    AnalysisPeriod = $DaysToAnalyze
    Timestamp = Get-Date
    Pipelines = @()
    Runners = @()
    Deployments = @()
    Summary = @{}
}

$headers = @{
    'PRIVATE-TOKEN' = $PrivateToken
    'Content-Type' = 'application/json'
}

$apiUrl = "$GitLabUrl/api/v4"
$startDate = (Get-Date).AddDays(-$DaysToAnalyze).ToString('yyyy-MM-ddTHH:mm:ssZ')

Write-Host "Analyzing GitLab CI pipelines for $ProjectId (Last $DaysToAnalyze days)..." -ForegroundColor Cyan

# Get projects
try {
    if ($ProjectId -eq '*') {
        $projectsUrl = "$apiUrl/projects?membership=true&per_page=100"
        $projectsResponse = Invoke-RestMethod -Uri $projectsUrl -Headers $headers -Method Get
        $projects = $projectsResponse | Select-Object id, name, path_with_namespace
    } else {
        $encodedProject = [uri]::EscapeDataString($ProjectId)
        $projectUrl = "$apiUrl/projects/$encodedProject"
        $project = Invoke-RestMethod -Uri $projectUrl -Headers $headers -Method Get
        $projects = @($project | Select-Object id, name, path_with_namespace)
    }
} catch {
    Write-Error "Failed to retrieve projects: $($_.Exception.Message)"
    exit 1
}

# Analyze each project
foreach ($project in $projects) {
    Write-Host "`nAnalyzing project: $($project.path_with_namespace)" -ForegroundColor Yellow

    try {
        # Get pipelines
        $pipelinesUrl = "$apiUrl/projects/$($project.id)/pipelines?updated_after=$startDate&per_page=100"
        $pipelinesResponse = Invoke-RestMethod -Uri $pipelinesUrl -Headers $headers -Method Get

        if ($pipelinesResponse.Count -eq 0) {
            Write-Host "  No recent pipelines found" -ForegroundColor Gray
            continue
        }

        # Group pipelines by ref (branch/tag)
        $pipelinesByRef = $pipelinesResponse | Group-Object ref

        foreach ($refGroup in $pipelinesByRef) {
            $refName = $refGroup.Name
            $refPipelines = $refGroup.Group

            # Calculate statistics
            $totalRuns = $refPipelines.Count
            $successfulRuns = ($refPipelines | Where-Object { $_.status -eq 'success' }).Count
            $failedRuns = ($refPipelines | Where-Object { $_.status -eq 'failed' }).Count
            $canceledRuns = ($refPipelines | Where-Object { $_.status -eq 'canceled' }).Count
            $skippedRuns = ($refPipelines | Where-Object { $_.status -eq 'skipped' }).Count
            $runningRuns = ($refPipelines | Where-Object { $_.status -eq 'running' }).Count

            $successRate = if ($totalRuns -gt 0) {
                [math]::Round((($successfulRuns + $skippedRuns) / $totalRuns) * 100, 2)
            } else { 0 }

            # Calculate average duration for completed pipelines
            $completedPipelines = $refPipelines | Where-Object { $_.duration }
            $avgDuration = if ($completedPipelines.Count -gt 0) {
                [math]::Round(($completedPipelines.duration | Measure-Object -Average).Average / 60, 2)
            } else { 0 }

            # Get failed pipeline details
            $failedDetails = $refPipelines | Where-Object { $_.status -eq 'failed' } |
                Select-Object -First 5 | ForEach-Object {
                    @{
                        PipelineId = $_.id
                        Sha = $_.sha.Substring(0, 8)
                        CreatedAt = $_.created_at
                        WebUrl = $_.web_url
                    }
                }

            $results.Pipelines += @{
                Project = $project.path_with_namespace
                ProjectId = $project.id
                Ref = $refName
                TotalRuns = $totalRuns
                SuccessfulRuns = $successfulRuns
                FailedRuns = $failedRuns
                CanceledRuns = $canceledRuns
                SkippedRuns = $skippedRuns
                RunningRuns = $runningRuns
                SuccessRate = $successRate
                AverageDurationMinutes = $avgDuration
                RecentFailures = $failedDetails
                Status = if ($successRate -ge 90) { 'Healthy' } elseif ($successRate -ge 70) { 'Warning' } else { 'Critical' }
            }
        }
    } catch {
        Write-Warning "Failed to analyze pipelines for $($project.path_with_namespace): $($_.Exception.Message)"
    }

    # Analyze deployments if requested
    if ($IncludeDeployments) {
        try {
            $deploymentsUrl = "$apiUrl/projects/$($project.id)/deployments?updated_after=$startDate&per_page=100"
            $deploymentsResponse = Invoke-RestMethod -Uri $deploymentsUrl -Headers $headers -Method Get

            foreach ($deployment in $deploymentsResponse) {
                $results.Deployments += @{
                    Project = $project.path_with_namespace
                    DeploymentId = $deployment.id
                    Environment = $deployment.environment.name
                    Status = $deployment.status
                    Ref = $deployment.ref
                    CreatedAt = $deployment.created_at
                    UpdatedAt = $deployment.updated_at
                }
            }
        } catch {
            Write-Warning "Failed to retrieve deployments for $($project.path_with_namespace): $($_.Exception.Message)"
        }
    }
}

# Analyze runners if requested
if ($IncludeRunners) {
    Write-Host "`nAnalyzing GitLab Runners..." -ForegroundColor Cyan
    try {
        $runnersUrl = "$apiUrl/runners/all?per_page=100"
        $runnersResponse = Invoke-RestMethod -Uri $runnersUrl -Headers $headers -Method Get

        foreach ($runner in $runnersResponse) {
            $results.Runners += @{
                RunnerId = $runner.id
                Description = $runner.description
                Status = $runner.status
                Active = $runner.active
                IsShared = $runner.is_shared
                RunnerType = $runner.runner_type
                Platform = $runner.platform
                Architecture = $runner.architecture
            }
        }
    } catch {
        Write-Warning "Failed to retrieve runners (requires admin access): $($_.Exception.Message)"
    }
}

# Calculate summary statistics
$totalPipelines = $results.Pipelines.Count
$healthyPipelines = ($results.Pipelines | Where-Object { $_.Status -eq 'Healthy' }).Count
$warningPipelines = ($results.Pipelines | Where-Object { $_.Status -eq 'Warning' }).Count
$criticalPipelines = ($results.Pipelines | Where-Object { $_.Status -eq 'Critical' }).Count
$avgSuccessRate = if ($totalPipelines -gt 0) {
    [math]::Round(($results.Pipelines.SuccessRate | Measure-Object -Average).Average, 2)
} else { 0 }

$results.Summary = @{
    TotalPipelines = $totalPipelines
    HealthyPipelines = $healthyPipelines
    WarningPipelines = $warningPipelines
    CriticalPipelines = $criticalPipelines
    AverageSuccessRate = $avgSuccessRate
    TotalRunners = $results.Runners.Count
    ActiveRunners = ($results.Runners | Where-Object { $_.Active -and $_.Status -eq 'online' }).Count
    TotalDeployments = $results.Deployments.Count
}

# Output results
switch ($OutputFormat) {
    'Console' {
        Write-Host "`n=== GitLab CI Pipeline Health Summary ===" -ForegroundColor Cyan
        Write-Host "Total Pipeline Refs: $totalPipelines" -ForegroundColor White
        Write-Host "Healthy: $healthyPipelines | Warning: $warningPipelines | Critical: $criticalPipelines" -ForegroundColor White
        Write-Host "Average Success Rate: $avgSuccessRate%" -ForegroundColor White

        Write-Host "`n=== Pipeline Details ===" -ForegroundColor Cyan
        foreach ($pipeline in $results.Pipelines | Sort-Object SuccessRate) {
            $color = switch ($pipeline.Status) {
                'Healthy' { 'Green' }
                'Warning' { 'Yellow' }
                'Critical' { 'Red' }
            }
            Write-Host "$($pipeline.Project)@$($pipeline.Ref): $($pipeline.SuccessRate)% success ($($pipeline.TotalRuns) runs)" -ForegroundColor $color
        }

        if ($IncludeRunners -and $results.Runners.Count -gt 0) {
            Write-Host "`n=== GitLab Runners ===" -ForegroundColor Cyan
            foreach ($runner in $results.Runners) {
                $status = if ($runner.Active) { "Active ($($runner.Status))" } else { "Inactive" }
                Write-Host "$($runner.Description): $status - $($runner.Platform)/$($runner.Architecture)" -ForegroundColor White
            }
        }
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "GitLab-CI-Health-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>GitLab CI Pipeline Health Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #fafafa; }
        h1 { color: #fc6d26; border-bottom: 3px solid #fc6d26; padding-bottom: 10px; }
        h2 { color: #554488; margin-top: 30px; }
        .summary { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-top: 15px; }
        .summary-item { background: #f5f5f5; padding: 15px; border-radius: 5px; text-align: center; }
        .summary-item .value { font-size: 32px; font-weight: bold; color: #fc6d26; }
        .summary-item .label { font-size: 14px; color: #666; margin-top: 5px; }
        table { border-collapse: collapse; width: 100%; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #554488; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #fafafa; }
        .status-healthy { color: #1aaa55; font-weight: bold; }
        .status-warning { color: #fc9403; font-weight: bold; }
        .status-critical { color: #db3b21; font-weight: bold; }
        .footer { margin-top: 30px; text-align: center; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <h1>GitLab CI Pipeline Health Report</h1>
    <div class="summary">
        <strong>GitLab URL:</strong> $GitLabUrl | <strong>Analysis Period:</strong> Last $DaysToAnalyze days<br>
        <strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

        <div class="summary-grid">
            <div class="summary-item">
                <div class="value">$totalPipelines</div>
                <div class="label">Total Pipeline Refs</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #1aaa55;">$healthyPipelines</div>
                <div class="label">Healthy (≥90%)</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #fc9403;">$warningPipelines</div>
                <div class="label">Warning (70-89%)</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #db3b21;">$criticalPipelines</div>
                <div class="label">Critical (<70%)</div>
            </div>
            <div class="summary-item">
                <div class="value">$avgSuccessRate%</div>
                <div class="label">Avg Success Rate</div>
            </div>
        </div>
    </div>

    <h2>Pipeline Details</h2>
    <table>
        <tr>
            <th>Project</th>
            <th>Branch/Tag</th>
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
            <td>$($pipeline.Project)</td>
            <td>$($pipeline.Ref)</td>
            <td>$($pipeline.TotalRuns)</td>
            <td>$($pipeline.SuccessRate)%</td>
            <td>$($pipeline.FailedRuns)</td>
            <td>$($pipeline.AverageDurationMinutes)</td>
            <td class="$statusClass">$($pipeline.Status)</td>
        </tr>
"@
        }

        $html += "</table>"
        $html += @"
    <div class="footer">
        <strong>Note:</strong> This report has not been thoroughly tested. Please validate results before making operational decisions.<br>
        Generated by Monitor-GitLabCI.ps1
    </div>
</body>
</html>
"@

        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "`nHTML report saved to: $htmlFile" -ForegroundColor Green
        Start-Process $htmlFile
    }

    'CSV' {
        $csvFile = Join-Path $OutputPath "GitLab-Pipelines-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
        $results.Pipelines | Export-Csv -Path $csvFile -NoTypeInformation
        Write-Host "`nCSV report saved to: $csvFile" -ForegroundColor Green
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "GitLab-Pipelines-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "`nJSON report saved to: $jsonFile" -ForegroundColor Green
    }
}

Write-Host "`nGitLab CI pipeline analysis complete!" -ForegroundColor Green
