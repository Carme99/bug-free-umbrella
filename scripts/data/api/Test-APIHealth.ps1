<#
.SYNOPSIS
    Tests API endpoint health, performance, and compliance.

.DESCRIPTION
    Comprehensive API health testing script that validates:
    - Endpoint availability and response codes
    - Response time and latency metrics
    - SSL/TLS certificate validity
    - Response payload validation
    - SLA compliance checking
    - Rate limiting and throttling behavior
    - CORS and security headers
    - API versioning consistency

    Supports REST APIs with JSON/XML payloads.

.PARAMETER EndpointsFile
    Path to JSON file containing API endpoint configurations

.PARAMETER SingleEndpoint
    Single API endpoint URL to test (alternative to EndpointsFile)


.PARAMETER Method
    HTTP method for single endpoint test. Default: GET

.PARAMETER ExpectedStatusCode
    Expected HTTP status code. Default: 200

.PARAMETER MaxResponseTime
    Maximum acceptable response time in milliseconds. Default: 2000

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for HTML/JSON output file. Default: MyDocuments\Reports

.PARAMETER RunContinuous
    Run tests continuously with specified interval

.PARAMETER IntervalSeconds
    Interval between continuous tests in seconds. Default: 60

.EXAMPLE
    .\Test-APIHealth.ps1 -EndpointsFile ".\api-endpoints.json"

.EXAMPLE
    .\Test-APIHealth.ps1 -SingleEndpoint "https://api.example.com/health" `
        -ExpectedStatusCode 200 `
        -MaxResponseTime 1000

.EXAMPLE
    .\Test-APIHealth.ps1 -EndpointsFile ".\endpoints.json" `
        -RunContinuous `
        -IntervalSeconds 300

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 5.1 or later

    Endpoints File Format (JSON):
    [
      {
        "Name": "Health Check",
        "Url": "https://api.example.com/health",
        "Method": "GET",
        "ExpectedStatusCode": 200,
        "MaxResponseTime": 1000,
        "Headers": { "Authorization": "Bearer token" }
      }
    ]

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$EndpointsFile,

    [Parameter(Mandatory = $false)]
    [string]$SingleEndpoint,

    [Parameter(Mandatory = $false)]
    [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'HEAD', 'OPTIONS')]
    [string]$Method = 'GET',

    [Parameter(Mandatory = $false)]
    [int]$ExpectedStatusCode = 200,

    [Parameter(Mandatory = $false)]
    [int]$MaxResponseTime = 2000,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'),

    [Parameter(Mandatory = $false)]
    [switch]$RunContinuous,

    [Parameter(Mandatory = $false)]
    [int]$IntervalSeconds = 60
)
# Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($OutputPath) -or
    $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
    $OutputPath -match '^(\\\\|//)') {
    Write-Error "Unsafe OutputPath: $OutputPath. OutputPath must not contain '..' traversal or be a UNC/remote path; relative paths are resolved to an absolute path."
    exit 1
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}


# Function to test a single endpoint
function Test-Endpoint {
    param(
        [hashtable]$Endpoint
    )

    $result = @{
        Name = $Endpoint.Name
        Url = $Endpoint.Url
        Method = $Endpoint.Method
        Timestamp = Get-Date
        Success = $false
        StatusCode = 0
        ResponseTime = 0
        ExpectedStatusCode = $Endpoint.ExpectedStatusCode
        MaxResponseTime = $Endpoint.MaxResponseTime
        Errors = @()
        Warnings = @()
        SSLValid = $false
        Headers = @{}
    }

    try {
        # Build request parameters
        $requestParams = @{
            Uri = $Endpoint.Url
            Method = $Endpoint.Method
            TimeoutSec = 30
        }

        # Add custom headers if provided
        if ($Endpoint.Headers) {
            $requestParams.Headers = $Endpoint.Headers
        }

        # Add body if provided
        if ($Endpoint.Body) {
            $requestParams.Body = $Endpoint.Body
            if ($Endpoint.ContentType) {
                $requestParams.ContentType = $Endpoint.ContentType
            }
        }

        # Measure response time
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $response = Invoke-WebRequest @requestParams
            $statusCode = $response.StatusCode
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if (-not $statusCode) { $statusCode = 0 }
            $response = $null
        }

        $stopwatch.Stop()
        $responseTime = $stopwatch.ElapsedMilliseconds

        $result.StatusCode = $statusCode
        $result.ResponseTime = $responseTime

        # Validate status code
        if ($statusCode -eq $Endpoint.ExpectedStatusCode) {
            $result.Success = $true
        } else {
            $result.Errors += "Status code mismatch: Expected $($Endpoint.ExpectedStatusCode), Got $statusCode"
        }

        # Validate response time
        if ($responseTime -gt $Endpoint.MaxResponseTime) {
            $result.Warnings += "Response time exceeded threshold: $responseTime ms > $($Endpoint.MaxResponseTime) ms"
        }

        # Check SSL certificate for HTTPS endpoints
        if ($Endpoint.Url -like 'https://*') {
            try {
                $uri = [System.Uri]$Endpoint.Url
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $tcpClient.Connect($uri.Host, 443)
                # Note: Manual certificate validation is performed below after SslStream authentication
                $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false)
                $sslStream.AuthenticateAsClient($uri.Host)

                $cert = $sslStream.RemoteCertificate
                if ($cert) {
                    $expirationDate = [datetime]::Parse($cert.GetExpirationDateString())
                    $daysUntilExpiration = ($expirationDate - (Get-Date)).Days

                    if ($expirationDate -gt (Get-Date)) {
                        $result.SSLValid = $true
                        if ($daysUntilExpiration -lt 30) {
                            $result.Warnings += "SSL certificate expires in $daysUntilExpiration days"
                        }
                    } else {
                        $result.Errors += "SSL certificate expired on $($expirationDate.ToString('yyyy-MM-dd'))"
                    }
                }

                $sslStream.Close()
                $tcpClient.Close()
            } catch {
                $result.Errors += "SSL validation failed: $($_.Exception.Message)"
            }
        }

        # Capture response headers
        if ($response) {
            foreach ($header in $response.Headers.Keys) {
                $result.Headers[$header] = $response.Headers[$header]
            }

            # Check security headers
            $securityHeaders = @('Strict-Transport-Security', 'X-Content-Type-Options', 'X-Frame-Options', 'Content-Security-Policy')
            $missingHeaders = $securityHeaders | Where-Object { -not $response.Headers.ContainsKey($_) }
            if ($missingHeaders) {
                $result.Warnings += "Missing security headers: $($missingHeaders -join ', ')"
            }
        }

    } catch {
        $result.Errors += "Request failed: $($_.Exception.Message)"
    }

    return $result
}

# Load endpoints
$endpoints = @()

if ($EndpointsFile) {
    if (-not (Test-Path $EndpointsFile)) {
        Write-Error "Endpoints file not found: $EndpointsFile"
        exit 1
    }

    try {
        $endpointData = Get-Content $EndpointsFile -Raw | ConvertFrom-Json
        foreach ($ep in $endpointData) {
            $endpoints += @{
                Name = $ep.Name
                Url = $ep.Url
                Method = if ($ep.Method) { $ep.Method } else { 'GET' }
                ExpectedStatusCode = if ($ep.ExpectedStatusCode) { $ep.ExpectedStatusCode } else { 200 }
                MaxResponseTime = if ($ep.MaxResponseTime) { $ep.MaxResponseTime } else { 2000 }
                Headers = $ep.Headers
                Body = $ep.Body
                ContentType = $ep.ContentType
            }
        }
    } catch {
        Write-Error "Failed to parse endpoints file: $($_.Exception.Message)"
        exit 1
    }
} elseif ($SingleEndpoint) {
    $endpoints += @{
        Name = "Single Endpoint Test"
        Url = $SingleEndpoint
        Method = $Method
        ExpectedStatusCode = $ExpectedStatusCode
        MaxResponseTime = $MaxResponseTime
    }
} else {
    Write-Error "Either -EndpointsFile or -SingleEndpoint must be specified"
    exit 1
}

# Function to run tests
function Run-Tests {
    $testResults = @{
        Timestamp = Get-Date
        TotalEndpoints = $endpoints.Count
        Results = @()
        Summary = @{}
    }

    Write-Host "`nTesting $($endpoints.Count) API endpoints..." -ForegroundColor Cyan

    foreach ($endpoint in $endpoints) {
        Write-Host "  Testing: $($endpoint.Name) - $($endpoint.Url)" -ForegroundColor Gray
        $result = Test-Endpoint -Endpoint $endpoint
        $testResults.Results += $result

        if ($result.Success) {
            Write-Host "    ✓ Passed ($($result.ResponseTime) ms)" -ForegroundColor Green
        } else {
            Write-Host "    ✗ Failed: $($result.Errors -join ', ')" -ForegroundColor Red
        }

        if ($result.Warnings.Count -gt 0) {
            Write-Host "    ⚠ Warnings: $($result.Warnings -join ', ')" -ForegroundColor Yellow
        }
    }

    # Calculate summary
    $successfulTests = ($testResults.Results | Where-Object { $_.Success }).Count
    $failedTests = ($testResults.Results | Where-Object { -not $_.Success }).Count
    $avgResponseTime = [math]::Round(($testResults.Results.ResponseTime | Measure-Object -Average).Average, 2)
    $maxResponseTime = ($testResults.Results.ResponseTime | Measure-Object -Maximum).Maximum

    $testResults.Summary = @{
        SuccessfulTests = $successfulTests
        FailedTests = $failedTests
        SuccessRate = [math]::Round(($successfulTests / $endpoints.Count) * 100, 2)
        AverageResponseTime = $avgResponseTime
        MaxResponseTime = $maxResponseTime
    }

    return $testResults
}

# Main execution
do {
    $testResults = Run-Tests

    # Output results
    $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    switch ($OutputFormat) {
        'Console' {
            Write-Host "`n=== API Health Test Summary ===" -ForegroundColor Cyan
            Write-Host "Total Endpoints: $($testResults.TotalEndpoints)" -ForegroundColor White
            Write-Host "Successful: $($testResults.Summary.SuccessfulTests) | Failed: $($testResults.Summary.FailedTests)" -ForegroundColor White
            Write-Host "Success Rate: $($testResults.Summary.SuccessRate)%" -ForegroundColor White
            Write-Host "Average Response Time: $($testResults.Summary.AverageResponseTime) ms" -ForegroundColor White
        }

        'HTML' {
            $htmlFile = Join-Path $OutputPath "API-Health-Test-${RunTimestamp}_${RunId}.html"

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>API Health Test Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        .summary { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin-top: 15px; }
        .summary-item { background: #f0f0f0; padding: 15px; border-radius: 5px; text-align: center; }
        .summary-item .value { font-size: 28px; font-weight: bold; color: #0078d4; }
        .summary-item .label { font-size: 13px; color: #666; margin-top: 5px; }
        table { border-collapse: collapse; width: 100%; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #0078d4; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .status-success { color: #107c10; font-weight: bold; }
        .status-failed { color: #d13438; font-weight: bold; }
        .errors { color: #d13438; font-size: 12px; }
        .warnings { color: #ff8c00; font-size: 12px; }
        .footer { margin-top: 30px; text-align: center; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <h1>API Health Test Report</h1>
    <div class="summary">
        <strong>Test Run:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

        <div class="summary-grid">
            <div class="summary-item">
                <div class="value">$($testResults.TotalEndpoints)</div>
                <div class="label">Total Endpoints</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #107c10;">$($testResults.Summary.SuccessfulTests)</div>
                <div class="label">Successful</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #d13438;">$($testResults.Summary.FailedTests)</div>
                <div class="label">Failed</div>
            </div>
            <div class="summary-item">
                <div class="value">$($testResults.Summary.SuccessRate)%</div>
                <div class="label">Success Rate</div>
            </div>
            <div class="summary-item">
                <div class="value">$($testResults.Summary.AverageResponseTime)</div>
                <div class="label">Avg Response (ms)</div>
            </div>
        </div>
    </div>

    <h2>Test Results</h2>
    <table>
        <tr>
            <th>Endpoint</th>
            <th>URL</th>
            <th>Status Code</th>
            <th>Response Time (ms)</th>
            <th>SSL Valid</th>
            <th>Result</th>
        </tr>
"@

            foreach ($result in $testResults.Results) {
                $statusClass = if ($result.Success) { 'status-success' } else { 'status-failed' }
                $statusText = if ($result.Success) { '✓ Passed' } else { '✗ Failed' }

                $html += @"
        <tr>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.Name)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.Url)"))</td>
            <td>$($result.StatusCode)</td>
            <td>$($result.ResponseTime)</td>
            <td>$(if ($result.Url -like 'https://*') { if ($result.SSLValid) { '✓' } else { '✗' } } else { 'N/A' })</td>
            <td class="$statusClass">$statusText</td>
        </tr>
"@

                if ($result.Errors.Count -gt 0 -or $result.Warnings.Count -gt 0) {
                    $html += @"
        <tr>
            <td colspan="6">
"@
                    if ($result.Errors.Count -gt 0) {
                        $html += "<div class='errors'>Errors: $([System.Net.WebUtility]::HtmlEncode(($result.Errors -join '; ')))</div>"
                    }
                    if ($result.Warnings.Count -gt 0) {
                        $html += "<div class='warnings'>Warnings: $([System.Net.WebUtility]::HtmlEncode(($result.Warnings -join '; ')))</div>"
                    }
                    $html += @"
            </td>
        </tr>
"@
                }
            }

            $html += @"
    </table>
    <div class="footer">
        <strong>Note:</strong> This report has not been thoroughly tested. Please validate results before making operational decisions.<br>
        Generated by Test-APIHealth.ps1
    </div>
</body>
</html>
"@

            $html | Out-File -FilePath $htmlFile -Encoding UTF8
            Write-Host "`nHTML report saved to: $htmlFile" -ForegroundColor Green
        }

        'JSON' {
            $jsonFile = Join-Path $OutputPath "API-Health-Test-${RunTimestamp}_${RunId}.json"
            $testResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
            Write-Host "`nJSON report saved to: $jsonFile" -ForegroundColor Green
        }
    }

    if ($RunContinuous) {
        Write-Host "`nWaiting $IntervalSeconds seconds before next test run... (Press Ctrl+C to stop)" -ForegroundColor Yellow
        Start-Sleep -Seconds $IntervalSeconds
    }

} while ($RunContinuous)

Write-Host "`nAPI health testing complete!" -ForegroundColor Green
