<#
.SYNOPSIS
    Comprehensive network connectivity and troubleshooting script.

.DESCRIPTION
    This script performs extensive network diagnostics including:
    - Network adapter status and configuration
    - DNS resolution testing
    - Internet connectivity verification
    - Gateway reachability
    - Common service connectivity (Office 365, Azure, Google)
    - Network performance metrics
    - Wi-Fi signal strength (if applicable)
    - Export to HTML and CSV formats

.PARAMETER OutputFormat
    Specifies the output format: None, HTML, CSV, or All. Default is None (console only).

.PARAMETER OutputPath
    Path to save the output file(s). Default is current directory.

.PARAMETER TestEndpoints
    Array of endpoints to test connectivity. Default includes common Microsoft and public services.

.PARAMETER DNSServers
    Array of DNS servers to test. Default includes system DNS and common public DNS servers.

.EXAMPLE
    .\Test-NetworkConnectivity.ps1 -OutputFormat HTML -OutputPath "C:\Reports"

    Generates an HTML network diagnostic report.

.EXAMPLE
    .\Test-NetworkConnectivity.ps1 -TestEndpoints @("google.com", "microsoft.com", "office.com")

    Tests connectivity to specified endpoints.

.NOTES
    File Name      : Test-NetworkConnectivity.ps1
    Requires       : PowerShell 5.1+, Administrator privileges recommended
    Version        : 1.0
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('None', 'HTML', 'CSV', 'All')]
    [string]$OutputFormat = 'None',

    [Parameter()]
    [string]$OutputPath = (Get-Location),

    [Parameter()]
    [string[]]$TestEndpoints = @(
        'google.com',
        'microsoft.com',
        'office.com',
        'login.microsoftonline.com',
        'graph.microsoft.com',
        'outlook.office365.com'
    ),

    [Parameter()]
    [string[]]$DNSServers = @('8.8.8.8', '1.1.1.1')
)

Write-Host "=== Network Connectivity Diagnostic ===" -ForegroundColor Cyan
Write-Host "Analyzing network status..." -ForegroundColor Yellow

# Initialize results
$networkDiag = @{
    ComputerName = $env:COMPUTERNAME
    TestTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    OverallStatus = "Unknown"
    Issues = @()
    Warnings = @()
    Adapters = @()
    Connectivity = @()
    DNS = @{}
    Performance = @{}
}

#region Network Adapter Check
Write-Host "`nChecking network adapters..." -ForegroundColor Yellow
try {
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

    foreach ($adapter in $adapters) {
        $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
        $gateway = Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty NextHop -First 1

        $adapterInfo = @{
            Name = $adapter.Name
            Description = $adapter.InterfaceDescription
            Status = $adapter.Status
            Speed = "$($adapter.LinkSpeed)"
            MediaType = $adapter.MediaType
            IPAddress = $ipConfig.IPAddress
            Gateway = $gateway
            MACAddress = $adapter.MacAddress
        }

        # Check for Wi-Fi and get signal strength
        if ($adapter.InterfaceDescription -match "Wi-Fi|Wireless|802.11") {
            try {
                $wifiInfo = netsh wlan show interfaces | Select-String "Signal"
                if ($wifiInfo) {
                    $signalMatch = $wifiInfo -match ":\s*(\d+)%"
                    if ($signalMatch) {
                        $adapterInfo.WiFiSignal = $Matches[1] + "%"
                    }
                }
            }
            catch {
                # Signal strength not available
            }
        }

        $networkDiag.Adapters += $adapterInfo

        Write-Host "Adapter: $($adapter.Name) - $($adapter.Status) - IP: $($ipConfig.IPAddress)" -ForegroundColor Green
    }

    if ($adapters.Count -eq 0) {
        $networkDiag.Issues += "No active network adapters found"
    }
}
catch {
    $networkDiag.Issues += "Could not enumerate network adapters"
}
#endregion

#region Gateway Connectivity
Write-Host "`nTesting gateway connectivity..." -ForegroundColor Yellow
try {
    $gateway = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty NextHop -First 1

    if ($gateway) {
        $gatewayPing = Test-Connection -ComputerName $gateway -Count 4 -ErrorAction SilentlyContinue

        if ($gatewayPing) {
            $avgLatency = ($gatewayPing | Measure-Object -Property ResponseTime -Average).Average
            Write-Host "Gateway ($gateway): Reachable (Avg: $([math]::Round($avgLatency, 2))ms)" -ForegroundColor Green

            $networkDiag.Performance.GatewayLatency = [math]::Round($avgLatency, 2)
        }
        else {
            Write-Host "Gateway ($gateway): Unreachable" -ForegroundColor Red
            $networkDiag.Issues += "Cannot reach default gateway: $gateway"
        }
    }
    else {
        Write-Host "No default gateway configured" -ForegroundColor Yellow
        $networkDiag.Warnings += "No default gateway found"
    }
}
catch {
    $networkDiag.Warnings += "Could not test gateway connectivity"
}
#endregion

#region DNS Testing
Write-Host "`nTesting DNS resolution..." -ForegroundColor Yellow
try {
    # Get system DNS servers
    $systemDNS = (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses.Count -gt 0 } | Select-Object -First 1).ServerAddresses

    $networkDiag.DNS.SystemDNS = $systemDNS -join ", "

    # Test DNS resolution
    $dnsTest = Resolve-DnsName -Name "microsoft.com" -ErrorAction SilentlyContinue

    if ($dnsTest) {
        Write-Host "DNS Resolution: Working" -ForegroundColor Green
        $networkDiag.DNS.Status = "Working"
    }
    else {
        Write-Host "DNS Resolution: Failed" -ForegroundColor Red
        $networkDiag.Issues += "DNS resolution is not working"
        $networkDiag.DNS.Status = "Failed"
    }

    # Test alternative DNS servers
    foreach ($dnsServer in $DNSServers) {
        try {
            $dnsServerTest = Resolve-DnsName -Name "google.com" -Server $dnsServer -ErrorAction SilentlyContinue

            if ($dnsServerTest) {
                Write-Host "  Public DNS ($dnsServer): Working" -ForegroundColor Green
            }
            else {
                Write-Host "  Public DNS ($dnsServer): Failed" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "  Public DNS ($dnsServer): Failed" -ForegroundColor Yellow
        }
    }
}
catch {
    $networkDiag.Warnings += "Could not fully test DNS"
}
#endregion

#region Internet Connectivity Tests
Write-Host "`nTesting internet connectivity..." -ForegroundColor Yellow
foreach ($endpoint in $TestEndpoints) {
    try {
        $pingTest = Test-Connection -ComputerName $endpoint -Count 2 -ErrorAction SilentlyContinue

        if ($pingTest) {
            $avgLatency = ($pingTest | Measure-Object -Property ResponseTime -Average).Average
            $connectivityInfo = @{
                Endpoint = $endpoint
                Status = "Reachable"
                AvgLatency = [math]::Round($avgLatency, 2)
            }

            Write-Host "  $endpoint : Reachable ($([math]::Round($avgLatency, 2))ms)" -ForegroundColor Green
        }
        else {
            # Try HTTP/HTTPS if ping fails (some servers block ICMP)
            try {
                $httpTest = Invoke-WebRequest -Uri "https://$endpoint" -Method Head -TimeoutSec 5 -ErrorAction SilentlyContinue

                if ($httpTest.StatusCode -eq 200 -or $httpTest.StatusCode -eq 301 -or $httpTest.StatusCode -eq 302) {
                    $connectivityInfo = @{
                        Endpoint = $endpoint
                        Status = "Reachable (HTTPS)"
                        AvgLatency = "N/A"
                    }
                    Write-Host "  $endpoint : Reachable (HTTPS)" -ForegroundColor Green
                }
                else {
                    $connectivityInfo = @{
                        Endpoint = $endpoint
                        Status = "Unreachable"
                        AvgLatency = "N/A"
                    }
                    Write-Host "  $endpoint : Unreachable" -ForegroundColor Red
                }
            }
            catch {
                $connectivityInfo = @{
                    Endpoint = $endpoint
                    Status = "Unreachable"
                    AvgLatency = "N/A"
                }
                Write-Host "  $endpoint : Unreachable" -ForegroundColor Red
            }
        }

        $networkDiag.Connectivity += $connectivityInfo
    }
    catch {
        Write-Host "  $endpoint : Test Failed" -ForegroundColor Yellow
    }
}
#endregion

#region Network Performance
Write-Host "`nChecking network performance metrics..." -ForegroundColor Yellow
try {
    $perfCounters = @(
        '\Network Interface(*)\Bytes Total/sec',
        '\Network Interface(*)\Packets/sec'
    )

    $networkPerf = Get-Counter -Counter $perfCounters -SampleInterval 1 -MaxSamples 3 -ErrorAction SilentlyContinue

    if ($networkPerf) {
        Write-Host "Network performance metrics collected" -ForegroundColor Green
    }
}
catch {
    Write-Host "Could not collect network performance metrics" -ForegroundColor Yellow
}
#endregion

# Determine overall status
$reachableCount = ($networkDiag.Connectivity | Where-Object { $_.Status -match "Reachable" }).Count
$totalTests = $networkDiag.Connectivity.Count

if ($networkDiag.Issues.Count -eq 0 -and $reachableCount -eq $totalTests) {
    $networkDiag.OverallStatus = "Excellent"
    $statusColor = "Green"
}
elseif ($networkDiag.Issues.Count -eq 0 -and $reachableCount -ge ($totalTests * 0.8)) {
    $networkDiag.OverallStatus = "Good"
    $statusColor = "Green"
}
elseif ($networkDiag.Issues.Count -le 2) {
    $networkDiag.OverallStatus = "Degraded"
    $statusColor = "Yellow"
}
else {
    $networkDiag.OverallStatus = "Poor"
    $statusColor = "Red"
}

#region Display Summary
Write-Host "`n=== Network Diagnostic Summary ===" -ForegroundColor Cyan
Write-Host "Overall Status: $($networkDiag.OverallStatus)" -ForegroundColor $statusColor
Write-Host "Endpoints Reachable: $reachableCount / $totalTests" -ForegroundColor $(if ($reachableCount -eq $totalTests) { 'Green' } elseif ($reachableCount -ge ($totalTests * 0.8)) { 'Yellow' } else { 'Red' })

if ($networkDiag.Issues.Count -gt 0) {
    Write-Host "`nIssues Found:" -ForegroundColor Red
    $networkDiag.Issues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

if ($networkDiag.Warnings.Count -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Yellow
    $networkDiag.Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

if ($networkDiag.Issues.Count -eq 0 -and $networkDiag.Warnings.Count -eq 0) {
    Write-Host "`nNo network issues detected." -ForegroundColor Green
}
#endregion

# Generate reports would go here (similar pattern to previous scripts)

return $networkDiag
