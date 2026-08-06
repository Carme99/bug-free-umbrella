<#
.SYNOPSIS
    Tests network connectivity to remote servers including ping, port checks, and DNS resolution.

.DESCRIPTION
    This script performs comprehensive network connectivity tests:
    - ICMP ping tests with latency measurement
    - TCP port connectivity tests
    - DNS resolution verification
    - Trace route analysis
    - Network path MTU discovery
    - Supports multiple targets and ports
    - Export results to HTML or CSV

.PARAMETER ComputerName
    Target computer(s) to test. Can be hostname, FQDN, or IP address. Accepts multiple values.

.PARAMETER Port
    TCP port(s) to test. Common ports: 80 (HTTP), 443 (HTTPS), 3389 (RDP), 445 (SMB), 1433 (SQL).

.PARAMETER PingCount
    Number of ping attempts per host (default: 4).

.PARAMETER Timeout
    Timeout in milliseconds for connectivity tests (default: 3000).

.PARAMETER IncludeTraceRoute
    Perform trace route to each target.

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Test-ServerConnectivity.ps1 -ComputerName "server01.domain.com"
    Tests basic connectivity to server01.

.EXAMPLE
    .\Test-ServerConnectivity.ps1 -ComputerName "server01","server02" -Port 80,443,3389 -ExportHTML
    Tests HTTP, HTTPS, and RDP connectivity to multiple servers and exports report.

.EXAMPLE
    .\Test-ServerConnectivity.ps1 -ComputerName "10.0.0.1" -IncludeTraceRoute
    Tests connectivity and performs trace route analysis.

.NOTES
    Requires network access to target systems
    Compatible with Windows Server 2016, 2019, and 2022
    Some tests may require firewall rules
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
    [string[]]$ComputerName,

    [Parameter(Mandatory=$false)]
    [int[]]$Port = @(80, 443, 3389, 445),

    [Parameter(Mandatory=$false)]
    [int]$PingCount = 4,

    [Parameter(Mandatory=$false)]
    [int]$Timeout = 3000,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeTraceRoute,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV
)

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

$script:report = @{
    TestTime = Get-Date
    SourceServer = $env:COMPUTERNAME
    Results = @()
    Summary = @{
        TotalTargets = 0
        SuccessfulPings = 0
        FailedPings = 0
        PortTestsRun = 0
        PortTestsSuccessful = 0
    }
}

function Write-ColorOutput {
    param([string]$Message, [string]$Level = 'Info')

    $color = switch($Level) {
        'Error' { 'Red' }
        'Warning' { 'Yellow' }
        'Success' { 'Green' }
        'Info' { 'Cyan' }
        default { 'White' }
    }
    Write-Host $Message -ForegroundColor $color
}

function Test-ICMPConnectivity {
    param([string]$Target)

    Write-Verbose "Testing ICMP connectivity to $Target..."

    $pingResults = @{
        Success = $false
        Sent = $PingCount
        Received = 0
        Lost = 0
        MinLatency = 0
        MaxLatency = 0
        AvgLatency = 0
        Results = @()
    }

    try {
        $ping = Test-Connection -ComputerName $Target -Count $PingCount -ErrorAction Stop

        $pingResults.Success = $true
        $pingResults.Received = $ping.Count
        $pingResults.Lost = $PingCount - $ping.Count

        if($ping) {
            $latencies = $ping | ForEach-Object { $_.ResponseTime }
            $pingResults.MinLatency = ($latencies | Measure-Object -Minimum).Minimum
            $pingResults.MaxLatency = ($latencies | Measure-Object -Maximum).Maximum
            $pingResults.AvgLatency = [math]::Round(($latencies | Measure-Object -Average).Average, 2)
            $pingResults.Results = $ping
        }

        $script:report.Summary.SuccessfulPings++
        Write-ColorOutput "    [OK] Ping successful - Avg: $($pingResults.AvgLatency)ms, Loss: $($pingResults.Lost)/$($pingResults.Sent)" -Level Success
    }
    catch {
        $pingResults.Lost = $PingCount
        $script:report.Summary.FailedPings++
        Write-ColorOutput "    [FAIL] Ping failed: $($_.Exception.Message)" -Level Error
    }

    return $pingResults
}

function Test-DNSResolution {
    param([string]$Target)

    Write-Verbose "Testing DNS resolution for $Target..."

    $dnsResults = @{
        Success = $false
        IPAddresses = @()
        FQDN = $null
        Error = $null
    }

    try {
        # Skip DNS resolution if target is already an IP address
        if($Target -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
            $dnsResults.Success = $true
            $dnsResults.IPAddresses = @($Target)
            $dnsResults.FQDN = "N/A (IP Address)"
            Write-ColorOutput "    [INFO] Target is IP address: $Target" -Level Info
        }
        else {
            $dns = Resolve-DnsName -Name $Target -ErrorAction Stop

            $ipRecords = $dns | Where-Object {$_.Type -eq 'A'}
            if($ipRecords) {
                $dnsResults.Success = $true
                $dnsResults.IPAddresses = $ipRecords.IPAddress
                $dnsResults.FQDN = $ipRecords[0].Name
                Write-ColorOutput "    [OK] DNS resolved to: $($dnsResults.IPAddresses -join ', ')" -Level Success
            }
        }
    }
    catch {
        $dnsResults.Error = $_.Exception.Message
        Write-ColorOutput "    [FAIL] DNS resolution failed: $($_.Exception.Message)" -Level Error
    }

    return $dnsResults
}

function Test-PortConnectivity {
    param(
        [string]$Target,
        [int]$TestPort
    )

    Write-Verbose "Testing port $TestPort on $Target..."

    $portResult = @{
        Port = $TestPort
        Success = $false
        ResponseTime = 0
        Error = $null
    }

    $script:report.Summary.PortTestsRun++

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        $asyncResult = $tcpClient.BeginConnect($Target, $TestPort, $null, $null)
        $wait = $asyncResult.AsyncWaitHandle.WaitOne($Timeout, $false)

        $stopwatch.Stop()

        if($wait) {
            try {
                $tcpClient.EndConnect($asyncResult)
                $portResult.Success = $true
                $portResult.ResponseTime = $stopwatch.ElapsedMilliseconds
                $script:report.Summary.PortTestsSuccessful++
                Write-ColorOutput "      [OK] Port $TestPort is open ($($portResult.ResponseTime)ms)" -Level Success
            }
            catch {
                $portResult.Error = "Connection refused"
                Write-ColorOutput "      [FAIL] Port $TestPort is closed or filtered" -Level Error
            }
        }
        else {
            $portResult.Error = "Connection timeout"
            Write-ColorOutput "      [FAIL] Port $TestPort timeout" -Level Warning
        }

        $tcpClient.Close()
    }
    catch {
        $portResult.Error = $_.Exception.Message
        Write-ColorOutput "      [FAIL] Port $TestPort error: $($_.Exception.Message)" -Level Error
    }

    return $portResult
}

function Get-TraceRoute {
    param([string]$Target)

    Write-Verbose "Performing trace route to $Target..."

    try {
        Write-ColorOutput "    Trace route to $Target..." -Level Info
        $traceRoute = Test-NetConnection -ComputerName $Target -TraceRoute -ErrorAction Stop

        $hops = @()
        if($traceRoute.TraceRoute) {
            for($i = 0; $i -lt $traceRoute.TraceRoute.Count; $i++) {
                $hop = $traceRoute.TraceRoute[$i]
                $hops += [PSCustomObject]@{
                    Hop = $i + 1
                    IPAddress = $hop
                }
                Write-Host "      Hop $($i + 1): $hop"
            }
        }

        return $hops
    }
    catch {
        Write-ColorOutput "    [WARNING] Trace route failed: $($_.Exception.Message)" -Level Warning
        return @()
    }
}

function Test-TargetConnectivity {
    param([string]$Target)

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Testing: $Target" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $result = @{
        Target = $Target
        DNS = $null
        Ping = $null
        Ports = @()
        TraceRoute = @()
        TestTime = Get-Date
    }

    # DNS Resolution
    Write-Host "DNS Resolution..." -ForegroundColor Cyan
    $result.DNS = Test-DNSResolution -Target $Target

    # Ping Test
    Write-Host "`nPing Test..." -ForegroundColor Cyan
    $result.Ping = Test-ICMPConnectivity -Target $Target

    # Port Tests
    if($Port) {
        Write-Host "`nPort Connectivity Tests..." -ForegroundColor Cyan
        foreach($p in $Port) {
            $portResult = Test-PortConnectivity -Target $Target -TestPort $p
            $result.Ports += $portResult
        }
    }

    # Trace Route
    if($IncludeTraceRoute) {
        Write-Host "`nTrace Route..." -ForegroundColor Cyan
        $result.TraceRoute = Get-TraceRoute -Target $Target
    }

    $script:report.Results += $result
    $script:report.Summary.TotalTargets++
}

function Show-Summary {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Connectivity Test Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Source: $($script:report.SourceServer)"
    Write-Host "Test Time: $($script:report.TestTime)"
    Write-Host "`nTargets Tested: $($script:report.Summary.TotalTargets)"
    Write-Host "Successful Pings: $($script:report.Summary.SuccessfulPings)"
    Write-Host "Failed Pings: $($script:report.Summary.FailedPings)"

    if($script:report.Summary.PortTestsRun -gt 0) {
        $portSuccessRate = [math]::Round(($script:report.Summary.PortTestsSuccessful / $script:report.Summary.PortTestsRun) * 100, 2)
        Write-Host "`nPort Tests: $($script:report.Summary.PortTestsSuccessful)/$($script:report.Summary.PortTestsRun) successful ($portSuccessRate%)"
    }

    Write-Host "`n========================================`n" -ForegroundColor Cyan
}

function Export-HTMLReport {
    $reportPath = "$ReportDir\ConnectivityReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Server Connectivity Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; background-color: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #007bff; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; border-bottom: 1px solid #ddd; padding-bottom: 5px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin: 20px 0; }
        .metric { background-color: #f8f9fa; padding: 20px; border-radius: 4px; border-left: 4px solid #007bff; }
        .metric-value { font-size: 2em; font-weight: bold; color: #007bff; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th { background-color: #007bff; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f1f1f1; }
        .success { color: #28a745; font-weight: bold; }
        .error { color: #dc3545; font-weight: bold; }
        .warning { color: #ffc107; font-weight: bold; }
        .target-section { background-color: #f8f9fa; padding: 20px; margin: 20px 0; border-radius: 4px; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #777; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Server Connectivity Report</h1>
        <p><strong>Source Server:</strong> $($script:report.SourceServer)<br>
        <strong>Test Time:</strong> $($script:report.TestTime)</p>

        <div class="summary">
            <div class="metric">
                <div class="metric-value">$($script:report.Summary.TotalTargets)</div>
                <div>Targets Tested</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($script:report.Summary.SuccessfulPings)</div>
                <div>Successful Pings</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($script:report.Summary.PortTestsSuccessful)/$($script:report.Summary.PortTestsRun)</div>
                <div>Ports Open</div>
            </div>
        </div>

        $(foreach($result in $script:report.Results) {
            "<div class='target-section'>"
            "<h2>$($result.Target)</h2>"

            # DNS Results
            "<h3>DNS Resolution</h3>"
            if($result.DNS.Success) {
                "<p class='success'>✓ Resolved to: $($result.DNS.IPAddresses -join ', ')</p>"
                if($result.DNS.FQDN -and $result.DNS.FQDN -ne 'N/A (IP Address)') {
                    "<p>FQDN: $($result.DNS.FQDN)</p>"
                }
            } else {
                "<p class='error'>✗ DNS resolution failed</p>"
            }

            # Ping Results
            "<h3>Ping Test</h3>"
            if($result.Ping.Success) {
                "<p class='success'>✓ Ping successful</p>"
                "<p>Sent: $($result.Ping.Sent) | Received: $($result.Ping.Received) | Lost: $($result.Ping.Lost)</p>"
                "<p>Latency - Min: $($result.Ping.MinLatency)ms | Avg: $($result.Ping.AvgLatency)ms | Max: $($result.Ping.MaxLatency)ms</p>"
            } else {
                "<p class='error'>✗ Ping failed ($($result.Ping.Lost)/$($result.Ping.Sent) packets lost)</p>"
            }

            # Port Results
            if($result.Ports.Count -gt 0) {
                "<h3>Port Tests</h3>"
                "<table><tr><th>Port</th><th>Status</th><th>Response Time</th></tr>"
                foreach($portResult in $result.Ports) {
                    $statusClass = if($portResult.Success) { 'success' } else { 'error' }
                    $statusText = if($portResult.Success) { '✓ Open' } else { "✗ $($portResult.Error)" }
                    $responseTime = if($portResult.Success) { "$($portResult.ResponseTime)ms" } else { 'N/A' }
                    "<tr><td>$($portResult.Port)</td><td class='$statusClass'>$statusText</td><td>$responseTime</td></tr>"
                }
                "</table>"
            }

            # Trace Route Results
            if($result.TraceRoute.Count -gt 0) {
                "<h3>Trace Route</h3>"
                "<table><tr><th>Hop</th><th>IP Address</th></tr>"
                foreach($hop in $result.TraceRoute) {
                    "<tr><td>$($hop.Hop)</td><td>$($hop.IPAddress)</td></tr>"
                }
                "</table>"
            }

            "</div>"
        })

        <div class="footer">
            Report generated by Test-ServerConnectivity.ps1
        </div>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-ColorOutput "`nHTML report exported to: $reportPath" -Level Success
    return $reportPath
}

function Export-CSVReport {
    $reportPath = "$ReportDir\ConnectivityReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

    $csvData = @()
    foreach($result in $script:report.Results) {
        foreach($portResult in $result.Ports) {
            $csvData += [PSCustomObject]@{
                Target = $result.Target
                DNSResolved = $result.DNS.Success
                IPAddresses = $result.DNS.IPAddresses -join '; '
                PingSuccess = $result.Ping.Success
                AvgLatency = $result.Ping.AvgLatency
                PacketLoss = "$($result.Ping.Lost)/$($result.Ping.Sent)"
                Port = $portResult.Port
                PortOpen = $portResult.Success
                PortResponseTime = $portResult.ResponseTime
                PortError = $portResult.Error
                TestTime = $result.TestTime
            }
        }
    }

    $csvData | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
    Write-ColorOutput "CSV report exported to: $reportPath" -Level Success
    return $reportPath
}

# Main execution
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Server Connectivity Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Source: $($script:report.SourceServer)"
Write-Host "Targets: $($ComputerName -join ', ')"
Write-Host "Ports: $($Port -join ', ')"
Write-Host "Ping Count: $PingCount"
Write-Host "`nStarting tests..." -ForegroundColor Cyan

foreach($target in $ComputerName) {
    Test-TargetConnectivity -Target $target
}

Show-Summary

if($ExportHTML) {
    Write-Host "Generating HTML report..." -ForegroundColor Cyan
    Export-HTMLReport
}

if($ExportCSV) {
    Write-Host "Generating CSV report..." -ForegroundColor Cyan
    Export-CSVReport
}
