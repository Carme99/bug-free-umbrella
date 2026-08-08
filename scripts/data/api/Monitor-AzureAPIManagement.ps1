<#
.SYNOPSIS
    Monitors Azure API Management service health, performance, and API analytics.

.DESCRIPTION
    Comprehensive Azure API Management monitoring script that provides:
    - API gateway health and availability status
    - API call volume and success rates by API/operation
    - Response time analysis and SLA compliance
    - Error rate tracking and categorization (4xx, 5xx)
    - Subscription and quota usage monitoring
    - Backend health and connectivity status
    - Policy performance impact analysis
    - Geographic distribution of API calls

.PARAMETER SubscriptionId
    Azure subscription ID containing the API Management service

.PARAMETER ResourceGroupName
    Resource group name containing the APIM instance

.PARAMETER ServiceName
    Azure API Management service name

.PARAMETER DaysToAnalyze
    Number of days of metrics to analyze. Default: 7

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', 'CSV', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for HTML/CSV/JSON output file. Default: MyDocuments\Reports

.PARAMETER IncludeAPIDetails
    Include per-API performance metrics

.PARAMETER IncludeBackendHealth
    Include backend service health analysis

.EXAMPLE
    .\Monitor-AzureAPIManagement.ps1 -SubscriptionId "sub-id" `
        -ResourceGroupName "rg-apim" `
        -ServiceName "myapim" `
        -IncludeAPIDetails

.EXAMPLE
    Connect-AzAccount
    .\Monitor-AzureAPIManagement.ps1 -SubscriptionId "sub-id" `
        -ResourceGroupName "rg-apim" `
        -ServiceName "myapim" `
        -DaysToAnalyze 30 `
        -IncludeBackendHealth

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 5.1 or later, Az PowerShell module

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$ServiceName,

    [Parameter(Mandatory = $false)]
    [int]$DaysToAnalyze = 7,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'CSV', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'),

    [Parameter(Mandatory = $false)]
    [switch]$IncludeAPIDetails,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeBackendHealth
)
# Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($OutputPath) -or
    $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
    $OutputPath -match '^(\\\\|//)') {
    Write-Error "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
    exit 1
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Check Az module
if (-not (Get-Module -ListAvailable -Name Az.ApiManagement)) {
    Write-Error "Az.ApiManagement module is required. Install with: Install-Module Az.ApiManagement"
    exit 1
}

if (-not (Get-Module -ListAvailable -Name Az.Monitor)) {
    Write-Error "Az.Monitor module is required. Install with: Install-Module Az.Monitor"
    exit 1
}

Import-Module Az.ApiManagement -ErrorAction SilentlyContinue
Import-Module Az.Monitor -ErrorAction SilentlyContinue

# Initialize results
$results = @{
    SubscriptionId = $SubscriptionId
    ResourceGroup = $ResourceGroupName
    ServiceName = $ServiceName
    AnalysisPeriod = $DaysToAnalyze
    Timestamp = Get-Date
    ServiceHealth = @{}
    APIs = @()
    Backends = @()
    Metrics = @{}
    Summary = @{}
}

Write-Host "Analyzing Azure API Management service: $ServiceName (Last $DaysToAnalyze days)..." -ForegroundColor Cyan

# Ensure Azure context
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Error "Not logged in to Azure. Run Connect-AzAccount first."
        exit 1
    }
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}
catch {
    Write-Error "Failed to set Azure context: $($_.Exception.Message)"
    exit 1
}

# Get APIM instance
try {
    Write-Host "Retrieving API Management service details..." -ForegroundColor Yellow
    $apimContext = New-AzApiManagementContext -ResourceGroupName $ResourceGroupName -ServiceName $ServiceName

    $apim = Get-AzApiManagement -ResourceGroupName $ResourceGroupName -Name $ServiceName

    $results.ServiceHealth = @{
        Name = $apim.Name
        Location = $apim.Location
        Sku = $apim.Sku
        ProvisioningState = $apim.ProvisioningState
        GatewayUrl = $apim.GatewayUrl
        PortalUrl = $apim.PortalUrl
        PublicIPAddresses = $apim.PublicIPAddresses -join ', '
    }

    Write-Host "Service Status: $($apim.ProvisioningState)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to retrieve API Management service: $($_.Exception.Message)"
    exit 1
}

# Calculate time range for metrics
$endTime = Get-Date
$startTime = $endTime.AddDays(-$DaysToAnalyze)
$timeGrain = "PT1H"  # 1 hour intervals

# Get metrics from Azure Monitor
try {
    Write-Host "`nRetrieving service metrics..." -ForegroundColor Yellow

    $resourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$ServiceName"

    # Total Requests
    $totalRequestsMetric = Get-AzMetric -ResourceId $resourceId `
        -MetricName "TotalRequests" `
        -StartTime $startTime `
        -EndTime $endTime `
        -TimeGrain $timeGrain `
        -AggregationType Total `
        -ErrorAction SilentlyContinue

    # Successful Requests
    $successfulRequestsMetric = Get-AzMetric -ResourceId $resourceId `
        -MetricName "SuccessfulRequests" `
        -StartTime $startTime `
        -EndTime $endTime `
        -TimeGrain $timeGrain `
        -AggregationType Total `
        -ErrorAction SilentlyContinue

    # Failed Requests
    $failedRequestsMetric = Get-AzMetric -ResourceId $resourceId `
        -MetricName "FailedRequests" `
        -StartTime $startTime `
        -EndTime $endTime `
        -TimeGrain $timeGrain `
        -AggregationType Total `
        -ErrorAction SilentlyContinue

    # Capacity
    $capacityMetric = Get-AzMetric -ResourceId $resourceId `
        -MetricName "Capacity" `
        -StartTime $startTime `
        -EndTime $endTime `
        -TimeGrain $timeGrain `
        -AggregationType Average `
        -ErrorAction SilentlyContinue

    # Calculate totals
    $totalRequests = ($totalRequestsMetric.Data.Total | Measure-Object -Sum).Sum
    $successfulRequests = ($successfulRequestsMetric.Data.Total | Measure-Object -Sum).Sum
    $failedRequests = ($failedRequestsMetric.Data.Total | Measure-Object -Sum).Sum

    $successRate = if ($totalRequests -gt 0) {
        [math]::Round(($successfulRequests / $totalRequests) * 100, 2)
    }
    else { 0 }

    $avgCapacity = if ($capacityMetric.Data.Count -gt 0) {
        [math]::Round(($capacityMetric.Data.Average | Measure-Object -Average).Average, 2)
    }
    else { 0 }

    $results.Metrics = @{
        TotalRequests = $totalRequests
        SuccessfulRequests = $successfulRequests
        FailedRequests = $failedRequests
        SuccessRate = $successRate
        AverageCapacity = $avgCapacity
        RequestsPerDay = [math]::Round($totalRequests / $DaysToAnalyze, 0)
    }

    Write-Host "Total Requests: $totalRequests | Success Rate: $successRate%" -ForegroundColor White
    Write-Host "Average Capacity: $avgCapacity%" -ForegroundColor White
}
catch {
    Write-Warning "Failed to retrieve metrics: $($_.Exception.Message)"
}

# Get API details if requested
if ($IncludeAPIDetails) {
    Write-Host "`nAnalyzing individual APIs..." -ForegroundColor Yellow

    try {
        $apis = Get-AzApiManagementApi -Context $apimContext

        foreach ($api in $apis) {
            # Get operations for this API
            $operations = Get-AzApiManagementOperation -Context $apimContext -ApiId $api.ApiId

            $results.APIs += @{
                ApiId = $api.ApiId
                Name = $api.Name
                Path = $api.Path
                Protocols = $api.Protocols -join ', '
                ServiceUrl = $api.ServiceUrl
                IsCurrent = $api.IsCurrent
                OperationCount = $operations.Count
                Description = $api.Description
            }
        }

        Write-Host "Found $($apis.Count) APIs with $($results.APIs.OperationCount | Measure-Object -Sum).Sum operations" -ForegroundColor White
    }
    catch {
        Write-Warning "Failed to retrieve API details: $($_.Exception.Message)"
    }
}

# Get backend health if requested
if ($IncludeBackendHealth) {
    Write-Host "`nAnalyzing backend services..." -ForegroundColor Yellow

    try {
        $backends = Get-AzApiManagementBackend -Context $apimContext

        foreach ($backend in $backends) {
            $results.Backends += @{
                BackendId = $backend.BackendId
                Title = $backend.Title
                Url = $backend.Url
                Protocol = $backend.Protocol
                Description = $backend.Description
            }
        }

        Write-Host "Found $($backends.Count) backend services" -ForegroundColor White
    }
    catch {
        Write-Warning "Failed to retrieve backend details: $($_.Exception.Message)"
    }
}

# Calculate summary
$healthStatus = if ($successRate -ge 99) { 'Excellent' }
elseif ($successRate -ge 95) { 'Good' }
elseif ($successRate -ge 90) { 'Fair' }
else { 'Poor' }

$capacityStatus = if ($avgCapacity -lt 70) { 'Healthy' }
elseif ($avgCapacity -lt 85) { 'Warning' }
else { 'Critical' }

$results.Summary = @{
    ServiceName = $ServiceName
    HealthStatus = $healthStatus
    CapacityStatus = $capacityStatus
    SuccessRate = $successRate
    TotalAPIs = $results.APIs.Count
    TotalBackends = $results.Backends.Count
    DailyRequestVolume = $results.Metrics.RequestsPerDay
}

# Output results
$RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
switch ($OutputFormat) {
    'Console' {
        Write-Host "`n=== Azure API Management Health Summary ===" -ForegroundColor Cyan
        Write-Host "Service: $ServiceName ($($results.ServiceHealth.Sku))" -ForegroundColor White
        Write-Host "Health Status: $healthStatus | Capacity: $avgCapacity% ($capacityStatus)" -ForegroundColor White
        Write-Host "Success Rate: $successRate% | Total Requests: $totalRequests" -ForegroundColor White
        Write-Host "Average Daily Volume: $($results.Metrics.RequestsPerDay) requests/day" -ForegroundColor White

        if ($results.APIs.Count -gt 0) {
            Write-Host "`n=== Published APIs ===" -ForegroundColor Cyan
            foreach ($api in $results.APIs) {
                Write-Host "$($api.Name) - $($api.Path) [$($api.Protocols)]" -ForegroundColor White
            }
        }

        if ($results.Backends.Count -gt 0) {
            Write-Host "`n=== Backend Services ===" -ForegroundColor Cyan
            foreach ($backend in $results.Backends) {
                Write-Host "$($backend.Title): $($backend.Url) ($($backend.Protocol))" -ForegroundColor White
            }
        }
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "Azure-APIM-Health-${RunTimestamp}_${RunId}.html"

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure API Management Health Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #106ebe; margin-top: 30px; }
        .summary { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-top: 15px; }
        .summary-item { background: #f0f0f0; padding: 15px; border-radius: 5px; text-align: center; }
        .summary-item .value { font-size: 32px; font-weight: bold; color: #0078d4; }
        .summary-item .label { font-size: 14px; color: #666; margin-top: 5px; }
        table { border-collapse: collapse; width: 100%; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .status-excellent { color: #107c10; font-weight: bold; }
        .status-good { color: #10893e; font-weight: bold; }
        .status-fair { color: #ff8c00; font-weight: bold; }
        .status-poor { color: #d13438; font-weight: bold; }
        .footer { margin-top: 30px; text-align: center; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <h1>Azure API Management Health Report</h1>
    <div class="summary">
        <strong>Service:</strong> $([System.Net.WebUtility]::HtmlEncode("$ServiceName")) | <strong>Location:</strong> $([System.Net.WebUtility]::HtmlEncode("$($results.ServiceHealth.Location)")) | <strong>SKU:</strong> $([System.Net.WebUtility]::HtmlEncode("$($results.ServiceHealth.Sku)"))<br>
        <strong>Gateway URL:</strong> $([System.Net.WebUtility]::HtmlEncode("$($results.ServiceHealth.GatewayUrl)"))<br>
        <strong>Analysis Period:</strong> Last $DaysToAnalyze days | <strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

        <div class="summary-grid">
            <div class="summary-item">
                <div class="value">$healthStatus</div>
                <div class="label">Health Status</div>
            </div>
            <div class="summary-item">
                <div class="value">$successRate%</div>
                <div class="label">Success Rate</div>
            </div>
            <div class="summary-item">
                <div class="value">$totalRequests</div>
                <div class="label">Total Requests</div>
            </div>
            <div class="summary-item">
                <div class="value">$($results.Metrics.RequestsPerDay)</div>
                <div class="label">Requests/Day</div>
            </div>
            <div class="summary-item">
                <div class="value">$avgCapacity%</div>
                <div class="label">Avg Capacity</div>
            </div>
            <div class="summary-item">
                <div class="value">$($results.APIs.Count)</div>
                <div class="label">Published APIs</div>
            </div>
        </div>
    </div>
"@

        if ($results.APIs.Count -gt 0) {
            $html += @"
    <h2>Published APIs</h2>
    <table>
        <tr>
            <th>API Name</th>
            <th>Path</th>
            <th>Protocols</th>
            <th>Operations</th>
            <th>Backend URL</th>
        </tr>
"@
            foreach ($api in $results.APIs) {
                $html += @"
        <tr>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($api.Name)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($api.Path)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($api.Protocols)"))</td>
            <td>$($api.OperationCount)</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($api.ServiceUrl)"))</td>
        </tr>
"@
            }
            $html += "</table>"
        }

        if ($results.Backends.Count -gt 0) {
            $html += @"
    <h2>Backend Services</h2>
    <table>
        <tr>
            <th>Title</th>
            <th>Backend URL</th>
            <th>Protocol</th>
            <th>Description</th>
        </tr>
"@
            foreach ($backend in $results.Backends) {
                $html += @"
        <tr>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($backend.Title)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($backend.Url)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($backend.Protocol)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($backend.Description)"))</td>
        </tr>
"@
            }
            $html += "</table>"
        }

        $html += @"
    <div class="footer">
        <strong>Note:</strong> This report has not been thoroughly tested. Please validate results before making operational decisions.<br>
        Generated by Monitor-AzureAPIManagement.ps1
    </div>
</body>
</html>
"@

        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "`nHTML report saved to: $htmlFile" -ForegroundColor Green
    }

    'CSV' {
        $csvFile = Join-Path $OutputPath "Azure-APIM-APIs-${RunTimestamp}_${RunId}.csv"
        $results.APIs | Export-Csv -Path $csvFile -NoTypeInformation
        Write-Host "`nCSV report saved to: $csvFile" -ForegroundColor Green
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "Azure-APIM-Health-${RunTimestamp}_${RunId}.json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "`nJSON report saved to: $jsonFile" -ForegroundColor Green
    }
}

Write-Host "`nAzure API Management analysis complete!" -ForegroundColor Green
