<#
.SYNOPSIS
    Documents complete network configuration for Windows Server 2016-2022.

.DESCRIPTION
    This script captures comprehensive network configuration:
    - Network adapter details and status
    - IP configuration (IPv4, IPv6, DNS, DHCP)
    - Routing table
    - DNS resolver configuration
    - Network adapter advanced properties
    - Network bindings and protocols
    - Firewall profile status
    - Network shares
    - Export to HTML or CSV

.PARAMETER IncludeRouting
    Include routing table in the report.

.PARAMETER IncludeShares
    Include network shares in the report.

.PARAMETER IncludeFirewall
    Include firewall profile status.

.PARAMETER ExportHTML
    Export report to HTML file.

.PARAMETER ExportCSV
    Export configuration to CSV.

.EXAMPLE
    .\Get-NetworkConfiguration.ps1
    Documents basic network configuration.

.EXAMPLE
    .\Get-NetworkConfiguration.ps1 -IncludeRouting -IncludeShares -IncludeFirewall -ExportHTML
    Comprehensive network documentation exported to HTML.

.NOTES
    Requires Administrator privileges
    Compatible with Windows Server 2016, 2019, and 2022
    Useful for documentation and troubleshooting
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$IncludeRouting,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeShares,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeFirewall,

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

#Requires -RunAsAdministrator

$script:report = @{
    ServerName = $env:COMPUTERNAME
    ScanTime = Get-Date
    Hostname = [System.Net.Dns]::GetHostName()
    Domain = (Get-CimInstance -ClassName Win32_ComputerSystem).Domain
    Adapters = @()
    IPConfig = @()
    DNS = @()
    Routes = @()
    Shares = @()
    Firewall = @{}
}

function Write-ColorOutput {
    param([string]$Message, [string]$Level = 'Info')

    $color = switch($Level) {
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
        'Info' { 'Cyan' }
        default { 'White' }
    }
    Write-Host $Message -ForegroundColor $color
}

function Get-NetworkAdapters {
    Write-Host "`nGathering network adapter information..." -ForegroundColor Cyan

    $adapters = Get-NetAdapter | Sort-Object InterfaceIndex

    foreach($adapter in $adapters) {
        $adapterInfo = [PSCustomObject]@{
            Name = $adapter.Name
            InterfaceDescription = $adapter.InterfaceDescription
            Status = $adapter.Status
            MacAddress = $adapter.MacAddress
            LinkSpeed = $adapter.LinkSpeed
            MediaType = $adapter.MediaType
            InterfaceIndex = $adapter.InterfaceIndex
            DriverVersion = $adapter.DriverVersion
            DriverDate = $adapter.DriverDate
            DriverProvider = $adapter.DriverProvider
        }

        $script:report.Adapters += $adapterInfo

        $statusColor = if($adapter.Status -eq 'Up') { 'Success' } else { 'Warning' }
        Write-ColorOutput "  $($adapter.Name): $($adapter.Status) - $($adapter.LinkSpeed)" -Level $statusColor
    }

    Write-ColorOutput "  Found $($adapters.Count) network adapter(s)" -Level Info
}

function Get-IPConfiguration {
    Write-Host "`nGathering IP configuration..." -ForegroundColor Cyan

    $ipConfigs = Get-NetIPConfiguration

    foreach($config in $ipConfigs) {
        # IPv4 addresses
        $ipv4Addresses = $config.IPv4Address.IPAddress -join ', '
        $ipv4DefaultGateway = $config.IPv4DefaultGateway.NextHop -join ', '

        # IPv6 addresses
        $ipv6Addresses = $config.IPv6Address.IPAddress -join ', '
        $ipv6DefaultGateway = $config.IPv6DefaultGateway.NextHop -join ', '

        # DNS servers
        $dnsServers = $config.DNSServer.ServerAddresses -join ', '

        $ipInfo = [PSCustomObject]@{
            InterfaceAlias = $config.InterfaceAlias
            InterfaceIndex = $config.InterfaceIndex
            InterfaceDescription = $config.InterfaceDescription
            IPv4Address = $ipv4Addresses
            IPv4Subnet = ($config.IPv4Address.PrefixLength -join ', ')
            IPv4Gateway = $ipv4DefaultGateway
            IPv6Address = $ipv6Addresses
            IPv6Gateway = $ipv6DefaultGateway
            DNSServers = $dnsServers
            NetProfile = $config.NetProfile.Name
            NetworkCategory = $config.NetProfile.NetworkCategory
        }

        $script:report.IPConfig += $ipInfo

        Write-Host "  $($config.InterfaceAlias):"
        if($ipv4Addresses) {
            Write-Host "    IPv4: $ipv4Addresses" -ForegroundColor Gray
            if($ipv4DefaultGateway) {
                Write-Host "    Gateway: $ipv4DefaultGateway" -ForegroundColor Gray
            }
        }
        if($dnsServers) {
            Write-Host "    DNS: $dnsServers" -ForegroundColor Gray
        }
    }
}

function Get-DNSConfiguration {
    Write-Host "`nGathering DNS configuration..." -ForegroundColor Cyan

    $dnsClientConfig = Get-DnsClient

    foreach($dns in $dnsClientConfig) {
        $dnsServers = (Get-DnsClientServerAddress -InterfaceIndex $dns.InterfaceIndex -ErrorAction SilentlyContinue).ServerAddresses -join ', '

        $dnsInfo = [PSCustomObject]@{
            InterfaceAlias = $dns.InterfaceAlias
            InterfaceIndex = $dns.InterfaceIndex
            ConnectionSpecificSuffix = $dns.ConnectionSpecificSuffix
            RegisterThisConnection = $dns.RegisterThisConnectionsAddress
            UseSuffixWhenRegistering = $dns.UseSuffixWhenRegistering
            DNSServers = $dnsServers
        }

        $script:report.DNS += $dnsInfo
    }

    Write-ColorOutput "  Documented DNS configuration for $($dnsClientConfig.Count) adapter(s)" -Level Info
}

function Get-RoutingTable {
    Write-Host "`nGathering routing table..." -ForegroundColor Cyan

    $routes = Get-NetRoute | Where-Object {$_.DestinationPrefix -ne '::/0'} | Sort-Object RouteMetric

    foreach($route in $routes) {
        $routeInfo = [PSCustomObject]@{
            DestinationPrefix = $route.DestinationPrefix
            NextHop = $route.NextHop
            InterfaceAlias = $route.InterfaceAlias
            InterfaceIndex = $route.InterfaceIndex
            RouteMetric = $route.RouteMetric
            Protocol = $route.Protocol
            AddressFamily = $route.AddressFamily
        }

        $script:report.Routes += $routeInfo
    }

    Write-ColorOutput "  Found $($routes.Count) route(s)" -Level Info
}

function Get-NetworkShares {
    Write-Host "`nGathering network shares..." -ForegroundColor Cyan

    try {
        $shares = Get-SmbShare -ErrorAction Stop

        foreach($share in $shares) {
            $shareInfo = [PSCustomObject]@{
                Name = $share.Name
                Path = $share.Path
                Description = $share.Description
                ShareType = $share.ShareType
                CurrentUsers = $share.CurrentUsers
                EncryptData = $share.EncryptData
                FolderEnumerationMode = $share.FolderEnumerationMode
                CachingMode = $share.CachingMode
            }

            $script:report.Shares += $shareInfo
            Write-Host "  $($share.Name): $($share.Path)" -ForegroundColor Gray
        }

        Write-ColorOutput "  Found $($shares.Count) share(s)" -Level Info
    }
    catch {
        Write-ColorOutput "  Could not retrieve network shares: $($_.Exception.Message)" -Level Warning
    }
}

function Get-FirewallStatus {
    Write-Host "`nGathering firewall status..." -ForegroundColor Cyan

    $profiles = Get-NetFirewallProfile

    foreach($profile in $profiles) {
        $script:report.Firewall[$profile.Name] = @{
            Enabled = $profile.Enabled
            DefaultInboundAction = $profile.DefaultInboundAction
            DefaultOutboundAction = $profile.DefaultOutboundAction
            AllowInboundRules = $profile.AllowInboundRules
            AllowLocalFirewallRules = $profile.AllowLocalFirewallRules
            AllowLocalIPsecRules = $profile.AllowLocalIPsecRules
            LogFileName = $profile.LogFileName
            LogMaxSizeKilobytes = $profile.LogMaxSizeKilobytes
        }

        $statusText = if($profile.Enabled) { "Enabled" } else { "Disabled" }
        $statusColor = if($profile.Enabled) { 'Success' } else { 'Warning' }
        Write-ColorOutput "  $($profile.Name): $statusText" -Level $statusColor
    }
}

function Show-Summary {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Network Configuration Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Server: $($script:report.ServerName)"
    Write-Host "Hostname: $($script:report.Hostname)"
    Write-Host "Domain: $($script:report.Domain)"
    Write-Host "Scan Time: $($script:report.ScanTime)"

    Write-Host "`nNetwork Adapters: $($script:report.Adapters.Count)" -ForegroundColor Cyan
    $script:report.Adapters | Format-Table Name, Status, LinkSpeed, MacAddress -AutoSize

    Write-Host "`nIP Configuration:" -ForegroundColor Cyan
    $script:report.IPConfig | Format-Table InterfaceAlias, IPv4Address, IPv4Gateway, DNSServers -AutoSize

    if($script:report.Routes.Count -gt 0) {
        Write-Host "`nTop 10 Routes:" -ForegroundColor Cyan
        $script:report.Routes | Select-Object -First 10 | Format-Table DestinationPrefix, NextHop, InterfaceAlias, RouteMetric -AutoSize
    }

    if($script:report.Shares.Count -gt 0) {
        Write-Host "`nNetwork Shares:" -ForegroundColor Cyan
        $script:report.Shares | Format-Table Name, Path, Description, CurrentUsers -AutoSize
    }

    Write-Host "`n========================================`n" -ForegroundColor Cyan
}

function Export-HTMLReport {
    $reportPath = "$ReportDir\NetworkConfig_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Network Configuration - $($script:report.ServerName)</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1600px; margin: 0 auto; background-color: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #007bff; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; border-bottom: 1px solid #ddd; padding-bottom: 5px; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; font-size: 0.9em; }
        th { background-color: #007bff; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f1f1f1; }
        .info-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin: 20px 0; }
        .info-box { background-color: #f8f9fa; padding: 15px; border-radius: 4px; border-left: 4px solid #007bff; }
        .status-up { color: #28a745; font-weight: bold; }
        .status-down { color: #dc3545; font-weight: bold; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #777; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Network Configuration Report</h1>
        <div class="info-grid">
            <div class="info-box">
                <strong>Server Name:</strong><br>$($script:report.ServerName)
            </div>
            <div class="info-box">
                <strong>Hostname:</strong><br>$($script:report.Hostname)
            </div>
            <div class="info-box">
                <strong>Domain:</strong><br>$($script:report.Domain)
            </div>
            <div class="info-box">
                <strong>Report Date:</strong><br>$($script:report.ScanTime)
            </div>
        </div>

        <h2>Network Adapters</h2>
        <table>
            <tr><th>Name</th><th>Description</th><th>Status</th><th>Link Speed</th><th>MAC Address</th><th>Driver Version</th></tr>
            $(foreach($adapter in $script:report.Adapters) {
                $statusClass = if($adapter.Status -eq 'Up') { 'status-up' } else { 'status-down' }
                "<tr>
                    <td>$($adapter.Name)</td>
                    <td>$($adapter.InterfaceDescription)</td>
                    <td class='$statusClass'>$($adapter.Status)</td>
                    <td>$($adapter.LinkSpeed)</td>
                    <td>$($adapter.MacAddress)</td>
                    <td>$($adapter.DriverVersion)</td>
                </tr>"
            })
        </table>

        <h2>IP Configuration</h2>
        <table>
            <tr><th>Interface</th><th>IPv4 Address</th><th>Subnet</th><th>Gateway</th><th>DNS Servers</th><th>Network Category</th></tr>
            $(foreach($ip in $script:report.IPConfig) {
                "<tr>
                    <td>$($ip.InterfaceAlias)</td>
                    <td>$($ip.IPv4Address)</td>
                    <td>$($ip.IPv4Subnet)</td>
                    <td>$($ip.IPv4Gateway)</td>
                    <td>$($ip.DNSServers)</td>
                    <td>$($ip.NetworkCategory)</td>
                </tr>"
            })
        </table>

        <h2>DNS Configuration</h2>
        <table>
            <tr><th>Interface</th><th>DNS Suffix</th><th>DNS Servers</th><th>Register Connection</th></tr>
            $(foreach($dns in $script:report.DNS) {
                "<tr>
                    <td>$($dns.InterfaceAlias)</td>
                    <td>$($dns.ConnectionSpecificSuffix)</td>
                    <td>$($dns.DNSServers)</td>
                    <td>$($dns.RegisterThisConnection)</td>
                </tr>"
            })
        </table>

        $(if($script:report.Routes.Count -gt 0) {
            "<h2>Routing Table</h2>"
            "<table><tr><th>Destination</th><th>Next Hop</th><th>Interface</th><th>Metric</th><th>Protocol</th></tr>"
            foreach($route in ($script:report.Routes | Select-Object -First 50)) {
                "<tr>
                    <td>$($route.DestinationPrefix)</td>
                    <td>$($route.NextHop)</td>
                    <td>$($route.InterfaceAlias)</td>
                    <td>$($route.RouteMetric)</td>
                    <td>$($route.Protocol)</td>
                </tr>"
            }
            "</table>"
        })

        $(if($script:report.Shares.Count -gt 0) {
            "<h2>Network Shares</h2>"
            "<table><tr><th>Share Name</th><th>Path</th><th>Description</th><th>Current Users</th><th>Encryption</th></tr>"
            foreach($share in $script:report.Shares) {
                "<tr>
                    <td>$($share.Name)</td>
                    <td>$($share.Path)</td>
                    <td>$($share.Description)</td>
                    <td>$($share.CurrentUsers)</td>
                    <td>$($share.EncryptData)</td>
                </tr>"
            }
            "</table>"
        })

        $(if($script:report.Firewall.Count -gt 0) {
            "<h2>Firewall Status</h2>"
            "<table><tr><th>Profile</th><th>Enabled</th><th>Inbound Default</th><th>Outbound Default</th></tr>"
            foreach($profile in $script:report.Firewall.GetEnumerator()) {
                "<tr>
                    <td>$($profile.Key)</td>
                    <td>$($profile.Value.Enabled)</td>
                    <td>$($profile.Value.DefaultInboundAction)</td>
                    <td>$($profile.Value.DefaultOutboundAction)</td>
                </tr>"
            }
            "</table>"
        })

        <div class="footer">
            Report generated by Get-NetworkConfiguration.ps1
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
    $reportPath = "$ReportDir\NetworkConfig_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

    $script:report.IPConfig | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
    Write-ColorOutput "CSV report exported to: $reportPath" -Level Success
    return $reportPath
}

# Main execution
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Network Configuration Documentation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Get-NetworkAdapters
Get-IPConfiguration
Get-DNSConfiguration

if($IncludeRouting) {
    Get-RoutingTable
}

if($IncludeShares) {
    Get-NetworkShares
}

if($IncludeFirewall) {
    Get-FirewallStatus
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
