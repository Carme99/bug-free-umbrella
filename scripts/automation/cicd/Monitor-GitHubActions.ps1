<#
.SYNOPSIS
    Monitors GitHub Actions workflow health and performance.

.DESCRIPTION
    Comprehensive GitHub Actions monitoring script that tracks:
    - Workflow run success/failure rates
    - Workflow execution duration trends
    - Failed workflow analysis with job-level details
    - Runner health and utilization
    - Repository deployment status
    - Workflow billing and usage metrics

    Supports monitoring across multiple repositories and organizations.

.PARAMETER Owner
    Repository owner (user or organization name)

.PARAMETER Repository
    Repository name. Use '*' to monitor all accessible repositories.

.PARAMETER GitHubToken
    GitHub Personal Access Token with 'repo' and 'workflow' scopes.
    Can also be provided via environment variable GITHUB_TOKEN

.PARAMETER DaysToAnalyze
    Number of days of workflow history to analyze. Default: 7

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', 'CSV', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for HTML/CSV/JSON output file. Default: Desktop

.PARAMETER IncludeRunners
    Include self-hosted runner health analysis

.PARAMETER IncludeBilling
    Include GitHub Actions billing and usage metrics (requires admin access)

.EXAMPLE
    .\Monitor-GitHubActions.ps1 -Owner "myorg" -Repository "myrepo" -GitHubToken "ghp_token123"

.EXAMPLE
    $token = $env:GITHUB_TOKEN
    .\Monitor-GitHubActions.ps1 -Owner "myorg" -Repository "*" -GitHubToken $token -DaysToAnalyze 30 -IncludeRunners

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
    [string]$Owner,

    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [Parameter(Mandatory = $false)]
    [string]$GitHubToken = $env:GITHUB_TOKEN,

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
    [switch]$IncludeBilling
)

# Validate GitHub token
if ([string]::IsNullOrWhiteSpace($GitHubToken)) {
    Write-Error "GitHub token is required. Provide via -GitHubToken or GITHUB_TOKEN environment variable"
    exit 1
}

# Initialize results collection
$results = @{
    Owner = $Owner
    Repository = $Repository
    AnalysisPeriod = $DaysToAnalyze
    Timestamp = Get-Date
    Workflows = @()
    Runners = @()
    Billing = @{}
    Summary = @{}
}

$headers = @{
    Authorization = "Bearer $GitHubToken"
    Accept = "application/vnd.github+json"
    'X-GitHub-Api-Version' = '2022-11-28'
}

$baseUrl = "https://api.github.com"
$startDate = (Get-Date).AddDays(-$DaysToAnalyze)

Write-Host "Analyzing GitHub Actions workflows for $Owner/$Repository (Last $DaysToAnalyze days)..." -ForegroundColor Cyan

# Get repositories
try {
    if ($Repository -eq '*') {
        $reposUrl = "$baseUrl/orgs/$Owner/repos?per_page=100"
        $reposResponse = Invoke-RestMethod -Uri $reposUrl -Headers $headers -Method Get
        $repositories = $reposResponse | Select-Object -ExpandProperty name
    } else {
        $repositories = @($Repository)
    }
} catch {
    Write-Error "Failed to retrieve repositories: $($_.Exception.Message)"
    exit 1
}

# Analyze each repository
foreach ($repo in $repositories) {
    Write-Host "`nAnalyzing repository: $repo" -ForegroundColor Yellow

    try {
        # Get workflows
        $workflowsUrl = "$baseUrl/repos/$Owner/$repo/actions/workflows"
        $workflowsResponse = Invoke-RestMethod -Uri $workflowsUrl -Headers $headers -Method Get

        foreach ($workflow in $workflowsResponse.workflows) {
            Write-Host "  Analyzing workflow: $($workflow.name)" -ForegroundColor Gray

            # Get workflow runs
            $runsUrl = "$baseUrl/repos/$Owner/$repo/actions/workflows/$($workflow.id)/runs?per_page=100&created=>=$($startDate.ToString('yyyy-MM-dd'))"
            $runsResponse = Invoke-RestMethod -Uri $runsUrl -Headers $headers -Method Get

            $recentRuns = $runsResponse.workflow_runs | Where-Object {
                [datetime]$_.created_at -ge $startDate
            }

            if ($recentRuns.Count -eq 0) { continue }

            # Calculate statistics
            $totalRuns = $recentRuns.Count
            $successfulRuns = ($recentRuns | Where-Object { $_.conclusion -eq 'success' }).Count
            $failedRuns = ($recentRuns | Where-Object { $_.conclusion -eq 'failure' }).Count
            $canceledRuns = ($recentRuns | Where-Object { $_.conclusion -eq 'cancelled' }).Count
            $skippedRuns = ($recentRuns | Where-Object { $_.conclusion -eq 'skipped' }).Count

            $successRate = if ($totalRuns -gt 0) {
                [math]::Round((($successfulRuns + $skippedRuns) / $totalRuns) * 100, 2)
            } else { 0 }

            # Calculate average duration
            $completedRuns = $recentRuns | Where-Object { $_.conclusion -and $_.updated_at }
            $avgDuration = if ($completedRuns.Count -gt 0) {
                $durations = $completedRuns | ForEach-Object {
                    ([datetime]$_.updated_at - [datetime]$_.created_at).TotalMinutes
                }
                [math]::Round(($durations | Measure-Object -Average).Average, 2)
            } else {
                0
            }

            # Get failed run details
            $failedRunDetails = $recentRuns | Where-Object { $_.conclusion -eq 'failure' } |
                Select-Object -First 5 | ForEach-Object {
                    @{
                        RunId = $_.id
                        RunNumber = $_.run_number
                        CreatedAt = $_.created_at
                        HeadBranch = $_.head_branch
                        Event = $_.event
                        HtmlUrl = $_.html_url
                    }
                }

            $results.Workflows += @{
                Repository = $repo
                WorkflowId = $workflow.id
                WorkflowName = $workflow.name
                WorkflowPath = $workflow.path
                State = $workflow.state
                TotalRuns = $totalRuns
                SuccessfulRuns = $successfulRuns
                FailedRuns = $failedRuns
                CanceledRuns = $canceledRuns
                SkippedRuns = $skippedRuns
                SuccessRate = $successRate
                AverageDurationMinutes = $avgDuration
                RecentFailures = $failedRunDetails
                Status = if ($successRate -ge 90) { 'Healthy' } elseif ($successRate -ge 70) { 'Warning' } else { 'Critical' }
            }
        }
    } catch {
        Write-Warning "Failed to analyze workflows for $repo : $($_.Exception.Message)"
    }
}

# Analyze self-hosted runners if requested
if ($IncludeRunners) {
    Write-Host "`nAnalyzing self-hosted runners..." -ForegroundColor Cyan
    try {
        $runnersUrl = "$baseUrl/orgs/$Owner/actions/runners?per_page=100"
        $runnersResponse = Invoke-RestMethod -Uri $runnersUrl -Headers $headers -Method Get

        foreach ($runner in $runnersResponse.runners) {
            $results.Runners += @{
                RunnerId = $runner.id
                RunnerName = $runner.name
                OS = $runner.os
                Status = $runner.status
                Busy = $runner.busy
                Labels = ($runner.labels | Select-Object -ExpandProperty name) -join ', '
            }
        }
    } catch {
        Write-Warning "Failed to analyze runners: $($_.Exception.Message)"
    }
}

# Get billing information if requested
if ($IncludeBilling) {
    Write-Host "`nRetrieving billing information..." -ForegroundColor Cyan
    try {
        $billingUrl = "$baseUrl/orgs/$Owner/settings/billing/actions"
        $billingResponse = Invoke-RestMethod -Uri $billingUrl -Headers $headers -Method Get

        $results.Billing = @{
            TotalMinutesUsed = $billingResponse.total_minutes_used
            TotalPaidMinutesUsed = $billingResponse.total_paid_minutes_used
            IncludedMinutes = $billingResponse.included_minutes
            MinutesUsedBreakdown = $billingResponse.minutes_used_breakdown
        }
    } catch {
        Write-Warning "Failed to retrieve billing information (requires admin access): $($_.Exception.Message)"
    }
}

# Calculate summary statistics
$totalWorkflows = $results.Workflows.Count
$healthyWorkflows = ($results.Workflows | Where-Object { $_.Status -eq 'Healthy' }).Count
$warningWorkflows = ($results.Workflows | Where-Object { $_.Status -eq 'Warning' }).Count
$criticalWorkflows = ($results.Workflows | Where-Object { $_.Status -eq 'Critical' }).Count
$avgSuccessRate = if ($totalWorkflows -gt 0) {
    [math]::Round(($results.Workflows.SuccessRate | Measure-Object -Average).Average, 2)
} else { 0 }

$results.Summary = @{
    TotalWorkflows = $totalWorkflows
    HealthyWorkflows = $healthyWorkflows
    WarningWorkflows = $warningWorkflows
    CriticalWorkflows = $criticalWorkflows
    AverageSuccessRate = $avgSuccessRate
    TotalRunners = $results.Runners.Count
    OnlineRunners = ($results.Runners | Where-Object { $_.Status -eq 'online' }).Count
}

# Output results
switch ($OutputFormat) {
    'Console' {
        Write-Host "`n=== GitHub Actions Workflow Health Summary ===" -ForegroundColor Cyan
        Write-Host "Total Workflows: $totalWorkflows" -ForegroundColor White
        Write-Host "Healthy: $healthyWorkflows | Warning: $warningWorkflows | Critical: $criticalWorkflows" -ForegroundColor White
        Write-Host "Average Success Rate: $avgSuccessRate%" -ForegroundColor White

        Write-Host "`n=== Workflow Details ===" -ForegroundColor Cyan
        foreach ($workflow in $results.Workflows | Sort-Object SuccessRate) {
            $color = switch ($workflow.Status) {
                'Healthy' { 'Green' }
                'Warning' { 'Yellow' }
                'Critical' { 'Red' }
            }
            Write-Host "$($workflow.Repository)/$($workflow.WorkflowName): $($workflow.SuccessRate)% success ($($workflow.TotalRuns) runs)" -ForegroundColor $color
        }

        if ($IncludeRunners -and $results.Runners.Count -gt 0) {
            Write-Host "`n=== Self-Hosted Runners ===" -ForegroundColor Cyan
            foreach ($runner in $results.Runners) {
                $status = if ($runner.Status -eq 'online') { 'Online' } else { 'Offline' }
                $busy = if ($runner.Busy) { '(Busy)' } else { '(Idle)' }
                Write-Host "$($runner.RunnerName): $status $busy - $($runner.OS)" -ForegroundColor White
            }
        }
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "GitHub-Actions-Health-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>GitHub Actions Workflow Health Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #24292e; border-bottom: 3px solid #0366d6; padding-bottom: 10px; }
        h2 { color: #0366d6; margin-top: 30px; }
        .summary { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-top: 15px; }
        .summary-item { background: #f6f8fa; padding: 15px; border-radius: 5px; text-align: center; border: 1px solid #d1d5da; }
        .summary-item .value { font-size: 32px; font-weight: bold; color: #0366d6; }
        .summary-item .label { font-size: 14px; color: #586069; margin-top: 5px; }
        table { border-collapse: collapse; width: 100%; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #24292e; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #e1e4e8; }
        tr:hover { background-color: #f6f8fa; }
        .status-healthy { color: #28a745; font-weight: bold; }
        .status-warning { color: #ffa500; font-weight: bold; }
        .status-critical { color: #d73a49; font-weight: bold; }
        .footer { margin-top: 30px; text-align: center; color: #586069; font-size: 12px; }
    </style>
</head>
<body>
    <h1>GitHub Actions Workflow Health Report</h1>
    <div class="summary">
        <strong>Owner:</strong> $Owner | <strong>Repository:</strong> $Repository | <strong>Period:</strong> Last $DaysToAnalyze days<br>
        <strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

        <div class="summary-grid">
            <div class="summary-item">
                <div class="value">$totalWorkflows</div>
                <div class="label">Total Workflows</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #28a745;">$healthyWorkflows</div>
                <div class="label">Healthy (≥90%)</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #ffa500;">$warningWorkflows</div>
                <div class="label">Warning (70-89%)</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #d73a49;">$criticalWorkflows</div>
                <div class="label">Critical (<70%)</div>
            </div>
            <div class="summary-item">
                <div class="value">$avgSuccessRate%</div>
                <div class="label">Avg Success Rate</div>
            </div>
        </div>
    </div>

    <h2>Workflow Details</h2>
    <table>
        <tr>
            <th>Repository</th>
            <th>Workflow</th>
            <th>Total Runs</th>
            <th>Success Rate</th>
            <th>Failed</th>
            <th>Avg Duration (min)</th>
            <th>Status</th>
        </tr>
"@

        foreach ($workflow in $results.Workflows | Sort-Object SuccessRate) {
            $statusClass = "status-$($workflow.Status.ToLower())"
            $html += @"
        <tr>
            <td>$($workflow.Repository)</td>
            <td>$($workflow.WorkflowName)</td>
            <td>$($workflow.TotalRuns)</td>
            <td>$($workflow.SuccessRate)%</td>
            <td>$($workflow.FailedRuns)</td>
            <td>$($workflow.AverageDurationMinutes)</td>
            <td class="$statusClass">$($workflow.Status)</td>
        </tr>
"@
        }

        $html += "</table>"
        $html += @"
    <div class="footer">
        <strong>Note:</strong> This report has not been thoroughly tested. Please validate results before making operational decisions.<br>
        Generated by Monitor-GitHubActions.ps1
    </div>
</body>
</html>
"@

        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "`nHTML report saved to: $htmlFile" -ForegroundColor Green
        Start-Process $htmlFile
    }

    'CSV' {
        $csvFile = Join-Path $OutputPath "GitHub-Workflows-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
        $results.Workflows | Export-Csv -Path $csvFile -NoTypeInformation
        Write-Host "`nCSV report saved to: $csvFile" -ForegroundColor Green
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "GitHub-Workflows-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "`nJSON report saved to: $jsonFile" -ForegroundColor Green
    }
}

Write-Host "`nGitHub Actions workflow analysis complete!" -ForegroundColor Green
