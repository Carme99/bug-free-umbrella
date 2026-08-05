<#
.SYNOPSIS
    Performs comprehensive network diagnostics and troubleshooting.

.DESCRIPTION
    This script runs a complete network diagnostic suite including:
    - Network adapter configuration
    - DNS resolution testing
    - Gateway connectivity
    - Internet connectivity
    - Latency and packet loss testing
    - Route tracing
    - Port scanning
    - Network performance metrics

.PARAMETER OutputPath
    Path where the diagnostic report will be saved.

.PARAMETER TestInternetConnectivity
    Switch to test internet connectivity to common sites.

.PARAMETER TraceRoute
    Switch to perform traceroute to specified destinations.

.PARAMETER TestDNS
    Switch to perform comprehensive DNS testing.

.PARAMETER ScanPorts
    Switch to scan common ports on local network.

.EXAMPLE
    .\Test-NetworkDiagnostics.ps1 -OutputPath "C:\Reports"
    Runs basic network diagnostics.

.EXAMPLE
    .\Test-NetworkDiagnostics.ps1 -TestInternetConnectivity -TraceRoute -TestDNS
    Runs comprehensive diagnostics including internet tests.

.NOTES
    Author: Server Management Team
    Requires: Administrator privileges for some tests
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'),

    [Parameter(Mandatory = $false)]
    [switch]$TestInternetConnectivity,

    [Parameter(Mandatory = $false)]
    [switch]$TraceRoute,

    [Parameter(Mandatory = $false)]
    [switch]$TestDNS,

    [Parameter(Mandatory = $false)]
    [switch]$ScanPorts
)

# Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($OutputPath) -or
    $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
    $OutputPath -match '^(\\\\|//)') {
    Write-Error "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
    exit 1
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

$RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

Write-Host "`n=== Network Diagnostics Tool ===" -ForegroundColor Cyan
Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# Create output directory
if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$diagnosticResults = @{
    Adapters = @()
    DNSTests = @()
    ConnectivityTests = @()
    RouteTraces = @()
    PortScans = @()
    Issues = @()
}

try {
    # Get network adapter information
    Write-Host "`n=== Network Adapters ===" -ForegroundColor Cyan

    $adapters = Get-NetAdapter | Where-Object { $_.Status -ne 'Disabled' }

    foreach ($adapter in $adapters) {
        Write-Host "`nAdapter: $($adapter.Name)" -ForegroundColor Yellow
        Write-Host "  Status: $($adapter.Status)" -ForegroundColor $(if ($adapter.Status -eq 'Up') { 'Green' } else { 'Red' })
        Write-Host "  Speed: $($adapter.LinkSpeed)" -ForegroundColor Cyan
        Write-Host "  MAC: $($adapter.MacAddress)" -ForegroundColor Gray

        # Get IP configuration
        $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue |
            Where-Object { $_.AddressFamily -eq 'IPv4' } |
            Select-Object -First 1

        if ($ipConfig) {
            Write-Host "  IP Address: $($ipConfig.IPAddress)" -ForegroundColor Cyan
            Write-Host "  Subnet: $($ipConfig.PrefixLength)" -ForegroundColor Cyan
        }

        # Get default gateway
        $gateway = Get-NetRoute -InterfaceIndex $adapter.InterfaceIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty NextHop -First 1

        if ($gateway) {
            Write-Host "  Gateway: $gateway" -ForegroundColor Cyan

            # Test gateway connectivity
            $gatewayTest = Test-Connection -ComputerName $gateway -Count 2 -Quiet -ErrorAction SilentlyContinue

            if ($gatewayTest) {
                Write-Host "  Gateway Reachable: Yes" -ForegroundColor Green
            }
            else {
                Write-Host "  Gateway Reachable: No" -ForegroundColor Red
                $diagnosticResults.Issues += "Gateway $gateway not reachable on adapter $($adapter.Name)"
            }
        }

        # Get DNS servers
        $dnsServers = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty ServerAddresses

        if ($dnsServers) {
            Write-Host "  DNS Servers: $($dnsServers -join ', ')" -ForegroundColor Cyan
        }

        # Store adapter info
        $diagnosticResults.Adapters += [PSCustomObject]@{
            Name = $adapter.Name
            Status = $adapter.Status
            Speed = $adapter.LinkSpeed
            MacAddress = $adapter.MacAddress
            IPAddress = if ($ipConfig) { $ipConfig.IPAddress } else { "N/A" }
            Gateway = if ($gateway) { $gateway } else { "N/A" }
            DNSServers = if ($dnsServers) { ($dnsServers -join ", ") } else { "N/A" }
            GatewayReachable = $gatewayTest
        }
    }

    # DNS Testing
    if ($TestDNS) {
        Write-Host "`n=== DNS Testing ===" -ForegroundColor Cyan

        $dnsTestTargets = @(
            @{ Name = "Google DNS"; Server = "8.8.8.8"; Hostname = "google.com" }
            @{ Name = "Cloudflare DNS"; Server = "1.1.1.1"; Hostname = "cloudflare.com" }
            @{ Name = "Domain Controller"; Server = (Get-DnsClientServerAddress | Where-Object { $_.ServerAddresses } | Select-Object -First 1 -ExpandProperty ServerAddresses | Select-Object -First 1); Hostname = $env:USERDNSDOMAIN }
        )

        foreach ($target in $dnsTestTargets) {
            if ($target.Server) {
                Write-Host "`nTesting $($target.Name) ($($target.Server))..." -ForegroundColor Yellow

                try {
                    $dnsTest = Resolve-DnsName -Name $target.Hostname -Server $target.Server -ErrorAction Stop -QuickTimeout
                    Write-Host "  ✓ Resolution successful" -ForegroundColor Green
                    Write-Host "  Result: $($dnsTest[0].IPAddress)" -ForegroundColor Cyan

                    $diagnosticResults.DNSTests += [PSCustomObject]@{
                        Server = $target.Server
                        Name = $target.Name
                        TestHostname = $target.Hostname
                        Result = "Success"
                        ResolvedIP = $dnsTest[0].IPAddress
                        ResponseTime = "N/A"
                    }
                }
                catch {
                    Write-Host "  ✗ Resolution failed: $_" -ForegroundColor Red
                    $diagnosticResults.Issues += "DNS resolution failed for $($target.Hostname) using $($target.Server)"

                    $diagnosticResults.DNSTests += [PSCustomObject]@{
                        Server = $target.Server
                        Name = $target.Name
                        TestHostname = $target.Hostname
                        Result = "Failed"
                        ResolvedIP = "N/A"
                        ResponseTime = "N/A"
                    }
                }
            }
        }
    }

    # Internet connectivity testing
    if ($TestInternetConnectivity) {
        Write-Host "`n=== Internet Connectivity ===" -ForegroundColor Cyan

        $internetTargets = @(
            "8.8.8.8",              # Google DNS
            "1.1.1.1",              # Cloudflare DNS
            "www.microsoft.com",    # Microsoft
            "www.google.com"        # Google
        )

        foreach ($target in $internetTargets) {
            Write-Host "`nTesting $target..." -ForegroundColor Yellow

            try {
                $pingTest = Test-Connection -ComputerName $target -Count 4 -ErrorAction Stop

                $avgLatency = ($pingTest | Measure-Object -Property ResponseTime -Average).Average
                $packetLoss = ((4 - $pingTest.Count) / 4) * 100

                Write-Host "  ✓ Reachable" -ForegroundColor Green
                Write-Host "  Average Latency: $([math]::Round($avgLatency, 2)) ms" -ForegroundColor Cyan
                Write-Host "  Packet Loss: $packetLoss%" -ForegroundColor $(if ($packetLoss -eq 0) { 'Green' } else { 'Yellow' })

                $diagnosticResults.ConnectivityTests += [PSCustomObject]@{
                    Target = $target
                    Status = "Reachable"
                    AverageLatency = [math]::Round($avgLatency, 2)
                    PacketLoss = $packetLoss
                }
            }
            catch {
                Write-Host "  ✗ Unreachable: $_" -ForegroundColor Red
                $diagnosticResults.Issues += "Cannot reach $target"

                $diagnosticResults.ConnectivityTests += [PSCustomObject]@{
                    Target = $target
                    Status = "Unreachable"
                    AverageLatency = "N/A"
                    PacketLoss = 100
                }
            }
        }
    }

    # Traceroute testing
    if ($TraceRoute) {
        Write-Host "`n=== Route Tracing ===" -ForegroundColor Cyan

        $traceTargets = @("8.8.8.8", "www.microsoft.com")

        foreach ($target in $traceTargets) {
            Write-Host "`nTracing route to $target..." -ForegroundColor Yellow

            try {
                $traceResult = Test-NetConnection -ComputerName $target -TraceRoute -ErrorAction Stop

                Write-Host "  Hops: $($traceResult.TraceRoute.Count)" -ForegroundColor Cyan

                $hopNumber = 0
                foreach ($hop in $traceResult.TraceRoute) {
                    $hopNumber++
                    Write-Host "    $hopNumber. $hop" -ForegroundColor Gray
                }

                $diagnosticResults.RouteTraces += [PSCustomObject]@{
                    Target = $target
                    HopCount = $traceResult.TraceRoute.Count
                    Route = ($traceResult.TraceRoute -join " -> ")
                }
            }
            catch {
                Write-Host "  ✗ Trace failed: $_" -ForegroundColor Red
                $diagnosticResults.Issues += "Route trace failed to $target"
            }
        }
    }

    # Port scanning
    if ($ScanPorts) {
        Write-Host "`n=== Port Scanning ===" -ForegroundColor Cyan

        $commonPorts = @(
            @{ Port = 80; Service = "HTTP" }
            @{ Port = 443; Service = "HTTPS" }
            @{ Port = 3389; Service = "RDP" }
            @{ Port = 445; Service = "SMB" }
            @{ Port = 389; Service = "LDAP" }
            @{ Port = 53; Service = "DNS" }
        )

        $localhost = "127.0.0.1"

        foreach ($portInfo in $commonPorts) {
            Write-Host "`nTesting port $($portInfo.Port) ($($portInfo.Service))..." -ForegroundColor Yellow

            try {
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $connect = $tcpClient.BeginConnect($localhost, $portInfo.Port, $null, $null)
                $wait = $connect.AsyncWaitHandle.WaitOne(1000, $false)

                if ($wait -and $tcpClient.Connected) {
                    Write-Host "  ✓ Port $($portInfo.Port) is open" -ForegroundColor Green
                    $status = "Open"
                }
                else {
                    Write-Host "  ✗ Port $($portInfo.Port) is closed/filtered" -ForegroundColor Gray
                    $status = "Closed"
                }

                $tcpClient.Close()

                $diagnosticResults.PortScans += [PSCustomObject]@{
                    Port = $portInfo.Port
                    Service = $portInfo.Service
                    Status = $status
                }
            }
            catch {
                Write-Host "  ✗ Port $($portInfo.Port) is closed/filtered" -ForegroundColor Gray

                $diagnosticResults.PortScans += [PSCustomObject]@{
                    Port = $portInfo.Port
                    Service = $portInfo.Service
                    Status = "Closed"
                }
            }
        }
    }

    # Network statistics
    Write-Host "`n=== Network Statistics ===" -ForegroundColor Cyan
    $netStats = Get-NetAdapterStatistics | Where-Object { $_.Name -in $adapters.Name }

    foreach ($stat in $netStats) {
        Write-Host "`n$($stat.Name):" -ForegroundColor Yellow
        Write-Host "  Received: $([math]::Round($stat.ReceivedBytes / 1GB, 2)) GB" -ForegroundColor Cyan
        Write-Host "  Sent: $([math]::Round($stat.SentBytes / 1GB, 2)) GB" -ForegroundColor Cyan
        Write-Host "  Errors: $($stat.ReceivedErrors + $stat.OutboundErrors)" -ForegroundColor $(if (($stat.ReceivedErrors + $stat.OutboundErrors) -eq 0) { 'Green' } else { 'Red' })
    }

    # Summary
    Write-Host "`n=== Diagnostic Summary ===" -ForegroundColor Cyan
    Write-Host "Active Adapters: $($adapters.Count)" -ForegroundColor White
    Write-Host "Issues Found: $($diagnosticResults.Issues.Count)" -ForegroundColor $(if ($diagnosticResults.Issues.Count -eq 0) { 'Green' } else { 'Red' })

    if ($diagnosticResults.Issues.Count -gt 0) {
        Write-Host "`nIssues:" -ForegroundColor Yellow
        foreach ($issue in $diagnosticResults.Issues) {
            Write-Host "  • $issue" -ForegroundColor Yellow
        }
    }

    # Export results
    Write-Host "`nExporting results..." -ForegroundColor Yellow

    $jsonPath = Join-Path -Path $OutputPath -ChildPath "NetworkDiagnostics_${RunTimestamp}_${RunId}.json"
    $diagnosticResults | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding UTF8
    Write-Host "Results saved to: $jsonPath" -ForegroundColor Green

    # Generate HTML report
    $htmlPath = Join-Path -Path $OutputPath -ChildPath "NetworkDiagnosticReport_${RunTimestamp}_${RunId}.html"

    $issuesHtml = ""
    if ($diagnosticResults.Issues.Count -gt 0) {
        $issuesHtml = "<h2>Issues Detected</h2><ul>"
        foreach ($issue in $diagnosticResults.Issues) {
            $issuesHtml += "<li>$([System.Net.WebUtility]::HtmlEncode("$issue"))</li>"
        }
        $issuesHtml += "</ul>"
    } else {
        $issuesHtml = "<p style='color: green;'><strong>No issues detected</strong></p>"
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Network Diagnostic Report - $env:COMPUTERNAME</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0066cc; }
        h2 { color: #0099cc; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin: 20px 0; }
        th { background-color: #0066cc; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f0f0f0; }
        .success { color: #009900; font-weight: bold; }
        .failed { color: #cc0000; font-weight: bold; }
        .info { background-color: #e6f3ff; padding: 15px; border-left: 4px solid #0066cc; margin: 20px 0; }
        ul { line-height: 1.8; }
    </style>
</head>
<body>
    <h1>Network Diagnostic Report</h1>
    <div class="info">
        <strong>Computer:</strong> $([System.Net.WebUtility]::HtmlEncode("$env:COMPUTERNAME"))<br>
        <strong>Report Time:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | <strong>Run ID:</strong> $RunId<br>
        <strong>Active Adapters:</strong> $($adapters.Count)<br>
        <strong>Issues Found:</strong> $($diagnosticResults.Issues.Count)
    </div>

    <h2>Network Adapters</h2>
    <table>
        <tr>
            <th>Name</th>
            <th>Status</th>
            <th>IP Address</th>
            <th>Gateway</th>
            <th>DNS Servers</th>
            <th>Speed</th>
        </tr>
"@

    foreach ($adapter in $diagnosticResults.Adapters) {
        $statusClass = if ($adapter.Status -eq 'Up') { 'success' } else { 'failed' }
        $html += @"
        <tr>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($adapter.Name)"))</td>
            <td class="$statusClass">$([System.Net.WebUtility]::HtmlEncode("$($adapter.Status)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($adapter.IPAddress)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($adapter.Gateway)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($adapter.DNSServers)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($adapter.Speed)"))</td>
        </tr>
"@
    }

    $html += "</table>"

    # Add connectivity tests if performed
    if ($diagnosticResults.ConnectivityTests.Count -gt 0) {
        $html += "<h2>Connectivity Tests</h2><table><tr><th>Target</th><th>Status</th><th>Avg Latency</th><th>Packet Loss</th></tr>"
        foreach ($test in $diagnosticResults.ConnectivityTests) {
            $statusClass = if ($test.Status -eq 'Reachable') { 'success' } else { 'failed' }
            $html += "<tr><td>$([System.Net.WebUtility]::HtmlEncode("$($test.Target)"))</td><td class='$statusClass'>$([System.Net.WebUtility]::HtmlEncode("$($test.Status)"))</td><td>$($test.AverageLatency) ms</td><td>$($test.PacketLoss)%</td></tr>"
        }
        $html += "</table>"
    }

    $html += $issuesHtml

    $html += @"
</body>
</html>
"@

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "HTML report saved to: $htmlPath" -ForegroundColor Green

}
catch {
    Write-Error "Error during network diagnostics: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}

Write-Host "`nEnd Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
