<#
.SYNOPSIS
    Monitor Azure API Management service health, performance, and API analytics.
.DESCRIPTION
    Collects Azure API Management service health and Azure Monitor metrics for the requested
    analysis window: request volume, success rates, failed-request counts, and unit capacity,
    with optional per-API details and backend service inventory. Results are printed to the
    console or written to an HTML/CSV/JSON report under -OutputPath.
    The script is read-only: it never mutates the API Management service or its APIs and is
    idempotent to re-run against the same subscription, resource group, and service.
.PARAMETER SubscriptionId
    Azure subscription ID containing the API Management service.
.PARAMETER ResourceGroupName
    Resource group name containing the APIM instance.
.PARAMETER ServiceName
    Azure API Management service name.
.PARAMETER DaysToAnalyze
    Number of days of metrics to analyze. Default: 7.
.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', 'CSV', or 'JSON'. Default: 'HTML'.
.PARAMETER OutputPath
    Directory where HTML/CSV/JSON report files are written. Default: MyDocuments\Reports.
.PARAMETER IncludeAPIDetails
    Include per-API performance metrics.
.PARAMETER IncludeBackendHealth
    Include backend service health analysis.
.EXAMPLE
    PS C:\> .\Monitor-AzureAPIManagement.ps1 -SubscriptionId "sub-id" `
        -ResourceGroupName "rg-apim" -ServiceName "myapim" -IncludeAPIDetails
    Monitors myapim including per-API detail metrics.
.EXAMPLE
    PS C:\> Connect-AzAccount
    PS C:\> .\Monitor-AzureAPIManagement.ps1 -SubscriptionId "sub-id" `
        -ResourceGroupName "rg-apim" -ServiceName "myapim" -DaysToAnalyze 30 -IncludeBackendHealth
    Authenticates to Azure, then analyzes 30 days of metrics including backend services.
.NOTES
    File Name   : Monitor-AzureAPIManagement.ps1
    Author      : IT Operations
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceName,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
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

$ErrorActionPreference = 'Stop'

function Main {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only creates fresh timestamped report files; never mutates Azure resources.')]
    param()

    try {
        # Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
        if ([string]::IsNullOrWhiteSpace($OutputPath) -or
            $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
            $OutputPath -match '^(\\\\|//)') {
            throw "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
        }
        $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
        if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        # Check Az module
        if (-not (Get-Module -ListAvailable -Name Az.ApiManagement)) {
            throw "Az.ApiManagement module is required. Install with: Install-Module Az.ApiManagement"
        }
        if (-not (Get-Module -ListAvailable -Name Az.Monitor)) {
            throw "Az.Monitor module is required. Install with: Install-Module Az.Monitor"
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

        $analysisBanner = "[*] Analyzing Azure API Management service: $ServiceName (Last $DaysToAnalyze days)..."
        Write-Host $analysisBanner -ForegroundColor Cyan

        # Ensure Azure context
        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            throw "Not logged in to Azure. Run Connect-AzAccount first."
        }
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null

        # Get APIM instance
        Write-Host "[*] Retrieving API Management service details..." -ForegroundColor Cyan
        $apimContext = New-AzApiManagementContext -ResourceGroupName $ResourceGroupName `
            -ServiceName $ServiceName -ErrorAction Stop

        $apim = Get-AzApiManagement -ResourceGroupName $ResourceGroupName `
            -Name $ServiceName -ErrorAction Stop

        $results.ServiceHealth = @{
            Name = $apim.Name
            Location = $apim.Location
            Sku = $apim.Sku
            ProvisioningState = $apim.ProvisioningState
            GatewayUrl = $apim.GatewayUrl
            PortalUrl = $apim.PortalUrl
            PublicIPAddresses = $apim.PublicIPAddresses -join ', '
        }

        Write-Host "[+] Service Status: $($apim.ProvisioningState)" -ForegroundColor Green

        # Calculate time range for metrics
        $endTime = Get-Date
        $startTime = $endTime.AddDays(-$DaysToAnalyze)
        $timeGrain = "PT1H"  # 1 hour intervals
        $totalRequests = 0
        $successRate = 0
        $avgCapacity = 0

        # Get metrics from Azure Monitor
        try {
            Write-Host "[*] Retrieving service metrics..." -ForegroundColor Cyan

            $resourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/" +
                "providers/Microsoft.ApiManagement/service/$ServiceName"

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

            $avgCapacity = if (@($capacityMetric.Data).Count -gt 0) {
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

            Write-Host "[+] Total Requests: $totalRequests | Success Rate: $successRate%" -ForegroundColor White
            Write-Host "[+] Average Capacity: $avgCapacity%" -ForegroundColor White
        }
        catch {
            Write-Host "[!] Failed to retrieve metrics: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Get API details if requested
        if ($IncludeAPIDetails) {
            Write-Host "[*] Analyzing individual APIs..." -ForegroundColor Cyan

            try {
                $apis = Get-AzApiManagementApi -Context $apimContext -ErrorAction Stop

                foreach ($api in $apis) {
                    # Get operations for this API
                    $operations = Get-AzApiManagementOperation -Context $apimContext `
                        -ApiId $api.ApiId -ErrorAction Stop

                    $results.APIs += @{
                        ApiId = $api.ApiId
                        Name = $api.Name
                        Path = $api.Path
                        Protocols = $api.Protocols -join ', '
                        ServiceUrl = $api.ServiceUrl
                        IsCurrent = $api.IsCurrent
                        OperationCount = @($operations).Count
                        Description = $api.Description
                    }
                }

                $operationTotal = ($results.APIs.OperationCount | Measure-Object -Sum).Sum
                Write-Host "[+] Found $(@($apis).Count) APIs with $operationTotal operations" -ForegroundColor White
            }
            catch {
                Write-Host "[!] Failed to retrieve API details: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        # Get backend health if requested
        if ($IncludeBackendHealth) {
            Write-Host "[*] Analyzing backend services..." -ForegroundColor Cyan

            try {
                $backends = Get-AzApiManagementBackend -Context $apimContext -ErrorAction Stop

                foreach ($backend in $backends) {
                    $results.Backends += @{
                        BackendId = $backend.BackendId
                        Title = $backend.Title
                        Url = $backend.Url
                        Protocol = $backend.Protocol
                        Description = $backend.Description
                    }
                }

                Write-Host "[+] Found $(@($backends).Count) backend services" -ForegroundColor White
            }
            catch {
                Write-Host "[!] Failed to retrieve backend details: $($_.Exception.Message)" -ForegroundColor Yellow
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
            TotalAPIs = @($results.APIs).Count
            TotalBackends = @($results.Backends).Count
            DailyRequestVolume = $results.Metrics.RequestsPerDay
        }

        # Output results
        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
        switch ($OutputFormat) {
            'Console' {
                Write-Host ""
                Write-Host "=== Azure API Management Health Summary ===" -ForegroundColor Cyan
                Write-Host "Service: $ServiceName ($($results.ServiceHealth.Sku))" -ForegroundColor White
                Write-Host "Health Status: $healthStatus |" `
                    "Capacity: $avgCapacity% ($capacityStatus)" -ForegroundColor White
                Write-Host "Success Rate: $successRate% | Total Requests: $totalRequests" -ForegroundColor White
                Write-Host "Average Daily Volume: $($results.Metrics.RequestsPerDay) requests/day" `
                    -ForegroundColor White

                if (@($results.APIs).Count -gt 0) {
                    Write-Host ""
                    Write-Host "=== Published APIs ===" -ForegroundColor Cyan
                    foreach ($api in $results.APIs) {
                        Write-Host "$($api.Name) - $($api.Path) [$($api.Protocols)]" -ForegroundColor White
                    }
                }

                if (@($results.Backends).Count -gt 0) {
                    Write-Host ""
                    Write-Host "=== Backend Services ===" -ForegroundColor Cyan
                    foreach ($backend in $results.Backends) {
                        Write-Host "$($backend.Title): $($backend.Url) ($($backend.Protocol))" -ForegroundColor White
                    }
                }
            }

            'HTML' {
                $htmlFile = Join-Path $OutputPath "Azure-APIM-Health-${RunTimestamp}_${RunId}.html"

                $encodedService = [System.Net.WebUtility]::HtmlEncode("$ServiceName")
                $encodedLocation = [System.Net.WebUtility]::HtmlEncode("$($results.ServiceHealth.Location)")
                $encodedSku = [System.Net.WebUtility]::HtmlEncode("$($results.ServiceHealth.Sku)")
                $encodedGatewayUrl = [System.Net.WebUtility]::HtmlEncode("$($results.ServiceHealth.GatewayUrl)")

                $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure API Management Health Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #106ebe; margin-top: 30px; }
        .summary { background: white; padding: 20px; border-radius: 8px;
                   box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                        gap: 15px; margin-top: 15px; }
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
        <strong>Service:</strong> $encodedService | <strong>Location:</strong> $encodedLocation |
        <strong>SKU:</strong> $encodedSku<br>
        <strong>Gateway URL:</strong> $encodedGatewayUrl<br>
        <strong>Analysis Period:</strong> Last $DaysToAnalyze days |
        <strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

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
                <div class="value">$(@($results.APIs).Count)</div>
                <div class="label">Published APIs</div>
            </div>
        </div>
    </div>
"@

                if (@($results.APIs).Count -gt 0) {
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
                        $encodedApiName = [System.Net.WebUtility]::HtmlEncode("$($api.Name)")
                        $encodedApiPath = [System.Net.WebUtility]::HtmlEncode("$($api.Path)")
                        $encodedProtocols = [System.Net.WebUtility]::HtmlEncode("$($api.Protocols)")
                        $encodedServiceUrl = [System.Net.WebUtility]::HtmlEncode("$($api.ServiceUrl)")
                        $html += @"
        <tr>
            <td>$encodedApiName</td>
            <td>$encodedApiPath</td>
            <td>$encodedProtocols</td>
            <td>$($api.OperationCount)</td>
            <td>$encodedServiceUrl</td>
        </tr>
"@
                    }
                    $html += "</table>"
                }

                if (@($results.Backends).Count -gt 0) {
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
                        $encodedTitle = [System.Net.WebUtility]::HtmlEncode("$($backend.Title)")
                        $encodedUrl = [System.Net.WebUtility]::HtmlEncode("$($backend.Url)")
                        $encodedProtocol = [System.Net.WebUtility]::HtmlEncode("$($backend.Protocol)")
                        $encodedDescription = [System.Net.WebUtility]::HtmlEncode("$($backend.Description)")
                        $html += @"
        <tr>
            <td>$encodedTitle</td>
            <td>$encodedUrl</td>
            <td>$encodedProtocol</td>
            <td>$encodedDescription</td>
        </tr>
"@
                    }
                    $html += "</table>"
                }

                $html += @"
    <div class="footer">
        <strong>Note:</strong> This report has not been thoroughly tested.<br>
        Please validate results before making operational decisions.<br>
        Generated by Monitor-AzureAPIManagement.ps1
    </div>
</body>
</html>
"@

                $html | Out-File -FilePath $htmlFile -Encoding UTF8
                Write-Host "[+] HTML report saved to: $htmlFile" -ForegroundColor Green
            }

            'CSV' {
                $csvFile = Join-Path $OutputPath "Azure-APIM-APIs-${RunTimestamp}_${RunId}.csv"
                $results.APIs | Export-Csv -Path $csvFile -NoTypeInformation
                Write-Host "[+] CSV report saved to: $csvFile" -ForegroundColor Green
            }

            'JSON' {
                $jsonFile = Join-Path $OutputPath "Azure-APIM-Health-${RunTimestamp}_${RunId}.json"
                $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
                Write-Host "[+] JSON report saved to: $jsonFile" -ForegroundColor Green
            }
        }

        Write-Host "[+] Azure API Management analysis complete!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
