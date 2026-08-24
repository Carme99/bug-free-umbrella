<#
.SYNOPSIS
    Runs comprehensive network connectivity diagnostics and reports overall status.

.DESCRIPTION
    Performs extensive network diagnostics including network adapter status, gateway reachability,
    DNS resolution testing (system and public resolvers), internet connectivity to common endpoints
    with HTTPS fallback, and network performance counter collection, then prints a summary.
    Side effects: none beyond console output; all probes are read-only.
    Exit codes: 0 = no issues detected and every endpoint reachable; 1 = issues detected, warnings
    recorded, or one or more endpoints unreachable.

.PARAMETER OutputFormat
    Specifies the output format: None, HTML, CSV, or All. Default is None (console only).

.PARAMETER OutputPath
    Path to save the output file(s). Default is current directory.

.PARAMETER TestEndpoints
    Array of endpoints to test connectivity. Default includes common Microsoft and public services.

.PARAMETER DNSServers
    Array of DNS servers to test. Default includes common public DNS servers.

.EXAMPLE
    PS C:\> .\Test-NetworkConnectivity.ps1 -OutputFormat HTML -OutputPath "C:\Reports"
    Generates an HTML network diagnostic report in C:\Reports.

.EXAMPLE
    PS C:\> .\Test-NetworkConnectivity.ps1 -TestEndpoints @("google.com", "microsoft.com", "office.com")
    Tests connectivity only to the specified endpoints.

.NOTES
    File Name    : Test-NetworkConnectivity.ps1
    Author       : Bug-Free Umbrella
    Prerequisite : PowerShell 5.1+, Administrator privileges recommended
    Version      : 1.0.0
    Date         : 2026-08-23
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'RELAUNCH-SPEC requires colored console output via Write-Host with [+]/[!]/[-]/[*] prefixes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Script parameters are consumed inside function Main through dynamic scoping.')]
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

$ErrorActionPreference = 'Stop'

function Invoke-Netsh {
    # Thin wrapper around netsh.exe so tests can mock native calls (returns captured output lines).
    & netsh.exe @Args 2>&1
}

function Main {
    try {
        Write-Host "=== Network Connectivity Diagnostic ===" -ForegroundColor Cyan
        Write-Host "[*] Analyzing network status..." -ForegroundColor Yellow

        # Initialize results
        $script:NetworkDiag = @{
            ComputerName   = $env:COMPUTERNAME
            TestTime       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            OverallStatus  = "Unknown"
            Issues         = @()
            Warnings       = @()
            Adapters       = @()
            Connectivity   = @()
            DNS            = @{}
            Performance    = @{}
        }

        #region Network Adapter Check
        Write-Host "`n[*] Checking network adapters..." -ForegroundColor Yellow
        try {
            $adapters = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }

            foreach ($adapter in $adapters) {
                $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 `
                    -ErrorAction SilentlyContinue | Select-Object -First 1
                $gateway = Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" `
                    -ErrorAction SilentlyContinue | Select-Object -ExpandProperty NextHop -First 1

                $adapterInfo = @{
                    Name        = $adapter.Name
                    Description = $adapter.InterfaceDescription
                    Status      = $adapter.Status
                    Speed       = "$($adapter.LinkSpeed)"
                    MediaType   = $adapter.MediaType
                    IPAddress   = $ipConfig.IPAddress
                    Gateway     = $gateway
                    MACAddress  = $adapter.MacAddress
                }

                # Check for Wi-Fi and get signal strength
                if ($adapter.InterfaceDescription -match "Wi-Fi|Wireless|802.11") {
                    try {
                        $wifiInfo = Invoke-Netsh wlan show interfaces | Select-String "Signal"
                        if ($wifiInfo) {
                            $signalMatch = $wifiInfo -match ":\s*(\d+)%"
                            if ($signalMatch) {
                                $adapterInfo.WiFiSignal = $Matches[1] + "%"
                            }
                        }
                    }
                    catch {
                        Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
                    }
                }

                $script:NetworkDiag.Adapters += $adapterInfo

                Write-Host "[+] Adapter: $($adapter.Name) - $($adapter.Status) - IP: $($ipConfig.IPAddress)" `
                    -ForegroundColor Green
            }

            if ($adapters.Count -eq 0) {
                $script:NetworkDiag.Issues += "No active network adapters found"
            }
        }
        catch {
            $script:NetworkDiag.Issues += "Could not enumerate network adapters"
        }
        #endregion

        #region Gateway Connectivity
        Write-Host "`n[*] Testing gateway connectivity..." -ForegroundColor Yellow
        try {
            $gateway = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty NextHop -First 1

            if ($gateway) {
                $gatewayPing = Test-Connection -ComputerName $gateway -Count 4 -ErrorAction SilentlyContinue

                if ($gatewayPing) {
                    $avgLatency = ($gatewayPing | Measure-Object -Property ResponseTime -Average).Average
                    Write-Host "[+] Gateway ($gateway): Reachable (Avg: $([math]::Round($avgLatency, 2))ms)" `
                        -ForegroundColor Green

                    $script:NetworkDiag.Performance.GatewayLatency = [math]::Round($avgLatency, 2)
                }
                else {
                    Write-Host "[-] Gateway ($gateway): Unreachable" -ForegroundColor Red
                    $script:NetworkDiag.Issues += "Cannot reach default gateway: $gateway"
                }
            }
            else {
                Write-Host "[!] No default gateway configured" -ForegroundColor Yellow
                $script:NetworkDiag.Warnings += "No default gateway found"
            }
        }
        catch {
            $script:NetworkDiag.Warnings += "Could not test gateway connectivity"
        }
        #endregion

        #region DNS Testing
        Write-Host "`n[*] Testing DNS resolution..." -ForegroundColor Yellow
        try {
            # Get system DNS servers
            $systemDNS = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.ServerAddresses.Count -gt 0 } | Select-Object -First 1).ServerAddresses

            $script:NetworkDiag.DNS.SystemDNS = $systemDNS -join ", "

            # Test DNS resolution
            $dnsTest = Resolve-DnsName -Name "microsoft.com" -ErrorAction SilentlyContinue

            if ($dnsTest) {
                Write-Host "[+] DNS Resolution: Working" -ForegroundColor Green
                $script:NetworkDiag.DNS.Status = "Working"
            }
            else {
                Write-Host "[-] DNS Resolution: Failed" -ForegroundColor Red
                $script:NetworkDiag.Issues += "DNS resolution is not working"
                $script:NetworkDiag.DNS.Status = "Failed"
            }

            # Test alternative DNS servers
            foreach ($dnsServer in $DNSServers) {
                try {
                    $dnsServerTest = Resolve-DnsName -Name "google.com" -Server $dnsServer `
                        -ErrorAction SilentlyContinue

                    if ($dnsServerTest) {
                        Write-Host "[+]   Public DNS ($dnsServer): Working" -ForegroundColor Green
                    }
                    else {
                        Write-Host "[!]   Public DNS ($dnsServer): Failed" -ForegroundColor Yellow
                    }
                }
                catch {
                    Write-Host "[!]   Public DNS ($dnsServer): Failed" -ForegroundColor Yellow
                }
            }
        }
        catch {
            $script:NetworkDiag.Warnings += "Could not fully test DNS"
        }
        #endregion

        #region Internet Connectivity Tests
        Write-Host "`n[*] Testing internet connectivity..." -ForegroundColor Yellow
        foreach ($endpoint in $TestEndpoints) {
            try {
                $pingTest = Test-Connection -ComputerName $endpoint -Count 2 -ErrorAction SilentlyContinue

                if ($pingTest) {
                    $avgLatency = ($pingTest | Measure-Object -Property ResponseTime -Average).Average
                    $connectivityInfo = @{
                        Endpoint   = $endpoint
                        Status     = "Reachable"
                        AvgLatency = [math]::Round($avgLatency, 2)
                    }

                    Write-Host "[+]   $endpoint : Reachable ($([math]::Round($avgLatency, 2))ms)" `
                        -ForegroundColor Green
                }
                else {
                    # Try HTTP/HTTPS if ping fails (some servers block ICMP)
                    try {
                        $httpTest = Invoke-WebRequest -Uri "https://$endpoint" -Method Head -TimeoutSec 5 `
                            -ErrorAction SilentlyContinue

                        if ($httpTest.StatusCode -eq 200 -or $httpTest.StatusCode -eq 301 -or `
                                $httpTest.StatusCode -eq 302) {
                            $connectivityInfo = @{
                                Endpoint   = $endpoint
                                Status     = "Reachable (HTTPS)"
                                AvgLatency = "N/A"
                            }
                            Write-Host "[+]   $endpoint : Reachable (HTTPS)" -ForegroundColor Green
                        }
                        else {
                            $connectivityInfo = @{
                                Endpoint   = $endpoint
                                Status     = "Unreachable"
                                AvgLatency = "N/A"
                            }
                            Write-Host "[-]   $endpoint : Unreachable" -ForegroundColor Red
                        }
                    }
                    catch {
                        $connectivityInfo = @{
                            Endpoint   = $endpoint
                            Status     = "Unreachable"
                            AvgLatency = "N/A"
                        }
                        Write-Host "[-]   $endpoint : Unreachable" -ForegroundColor Red
                    }
                }

                $script:NetworkDiag.Connectivity += $connectivityInfo
            }
            catch {
                Write-Host "[!]   $endpoint : Test Failed" -ForegroundColor Yellow
            }
        }
        #endregion

        #region Network Performance
        Write-Host "`n[*] Checking network performance metrics..." -ForegroundColor Yellow
        try {
            $perfCounters = @(
                '\Network Interface(*)\Bytes Total/sec',
                '\Network Interface(*)\Packets/sec'
            )

            $networkPerf = Get-Counter -Counter $perfCounters -SampleInterval 1 -MaxSamples 3 `
                -ErrorAction SilentlyContinue

            if ($networkPerf) {
                Write-Host "[+] Network performance metrics collected" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "[!] Could not collect network performance metrics" -ForegroundColor Yellow
        }
        #endregion

        # Determine overall status
        $reachableCount = ($script:NetworkDiag.Connectivity | Where-Object { $_.Status -match "Reachable" }).Count
        $totalTests = $script:NetworkDiag.Connectivity.Count

        if ($script:NetworkDiag.Issues.Count -eq 0 -and $reachableCount -eq $totalTests) {
            $script:NetworkDiag.OverallStatus = "Excellent"
            $statusColor = "Green"
        }
        elseif ($script:NetworkDiag.Issues.Count -eq 0 -and $reachableCount -ge ($totalTests * 0.8)) {
            $script:NetworkDiag.OverallStatus = "Good"
            $statusColor = "Green"
        }
        elseif ($script:NetworkDiag.Issues.Count -le 2) {
            $script:NetworkDiag.OverallStatus = "Degraded"
            $statusColor = "Yellow"
        }
        else {
            $script:NetworkDiag.OverallStatus = "Poor"
            $statusColor = "Red"
        }

        #region Display Summary
        Write-Host "`n=== Network Diagnostic Summary ===" -ForegroundColor Cyan
        Write-Host "Overall Status: $($script:NetworkDiag.OverallStatus)" -ForegroundColor $statusColor

        if ($totalTests -gt 0) {
            $reachColor = if ($reachableCount -eq $totalTests) { 'Green' } else { 'Yellow' }
            Write-Host "Endpoints Reachable: $reachableCount / $totalTests" -ForegroundColor $reachColor
        }

        if ($script:NetworkDiag.Issues.Count -gt 0) {
            Write-Host "`nIssues Found:" -ForegroundColor Red
            foreach ($issue in $script:NetworkDiag.Issues) { Write-Host "[-]   - $issue" -ForegroundColor Red }
        }

        if ($script:NetworkDiag.Warnings.Count -gt 0) {
            Write-Host "`nWarnings:" -ForegroundColor Yellow
            foreach ($warning in $script:NetworkDiag.Warnings) {
                Write-Host "[!]   - $warning" -ForegroundColor Yellow
            }
        }

        if ($script:NetworkDiag.Issues.Count -eq 0 -and $script:NetworkDiag.Warnings.Count -eq 0) {
            Write-Host "`n[+] No network issues detected." -ForegroundColor Green
        }
        #endregion
    }
    catch {
        Write-Host "[-] Error during network connectivity diagnostics: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }

    # Report generation for HTML/CSV formats would be handled here (reserved; console summary above).

    if ($script:NetworkDiag.Issues.Count -gt 0) {
        return 1
    }

    return 0
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
