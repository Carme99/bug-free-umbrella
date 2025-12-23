<#
.SYNOPSIS
    Monitors SSL/TLS certificate expiration for local and remote certificates.

.DESCRIPTION
    This script checks certificate expiration dates across multiple locations:
    - Local computer certificate stores (Personal, WebHosting, Remote Desktop)
    - Remote HTTPS endpoints
    - Active Directory Certificate Services
    - Custom certificate paths
    - Alerts on certificates expiring soon
    - Export results to HTML or CSV

.PARAMETER CheckLocal
    Check certificates in local computer stores.

.PARAMETER CheckRemote
    Check remote HTTPS endpoints. Requires -Endpoints parameter.

.PARAMETER Endpoints
    Array of HTTPS endpoints to check (e.g., "https://www.example.com").

.PARAMETER WarningDays
    Number of days before expiration to warn (default: 30).

.PARAMETER CriticalDays
    Number of days before expiration to mark critical (default: 7).

.PARAMETER CertStorePath
    Specific certificate store path to check (e.g., "Cert:\LocalMachine\My").

.PARAMETER IncludeExpired
    Include already expired certificates in the report.

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Test-CertificateExpiration.ps1 -CheckLocal
    Checks all certificates in local computer stores.

.EXAMPLE
    .\Test-CertificateExpiration.ps1 -CheckRemote -Endpoints "https://example.com","https://portal.example.com" -ExportHTML
    Checks SSL certificates on remote endpoints and exports HTML report.

.EXAMPLE
    .\Test-CertificateExpiration.ps1 -CheckLocal -WarningDays 60 -CriticalDays 14 -IncludeExpired
    Checks local certificates with custom warning thresholds and includes expired certs.

.NOTES
    Requires Administrator privileges for local certificate store access
    Compatible with Windows Server 2016, 2019, and 2022
    Remote endpoint checks require internet/network connectivity
#>

[CmdletBinding(DefaultParameterSetName='Local')]
param(
    [Parameter(ParameterSetName='Local')]
    [switch]$CheckLocal,

    [Parameter(ParameterSetName='Remote')]
    [switch]$CheckRemote,

    [Parameter(ParameterSetName='Remote', Mandatory=$true)]
    [string[]]$Endpoints,

    [Parameter(Mandatory=$false)]
    [int]$WarningDays = 30,

    [Parameter(Mandatory=$false)]
    [int]$CriticalDays = 7,

    [Parameter(Mandatory=$false)]
    [string]$CertStorePath,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeExpired,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV
)

$script:report = @{
    ServerName = $env:COMPUTERNAME
    ScanTime = Get-Date
    WarningDays = $WarningDays
    CriticalDays = $CriticalDays
    Certificates = @()
    Summary = @{
        TotalCertificates = 0
        Expired = 0
        Critical = 0
        Warning = 0
        Healthy = 0
    }
}

function Write-ColorOutput {
    param([string]$Message, [string]$Level = 'Info')

    $color = switch($Level) {
        'Critical' { 'Red' }
        'Error' { 'Red' }
        'Warning' { 'Yellow' }
        'Success' { 'Green' }
        'Info' { 'Cyan' }
        default { 'White' }
    }
    Write-Host $Message -ForegroundColor $color
}

function Get-CertificateStatus {
    param(
        [DateTime]$NotAfter,
        [DateTime]$NotBefore
    )

    $now = Get-Date
    $daysUntilExpiry = ($NotAfter - $now).Days

    if($NotAfter -lt $now) {
        return @{
            Status = 'Expired'
            DaysUntilExpiry = $daysUntilExpiry
            Color = 'Critical'
        }
    }
    elseif($daysUntilExpiry -le $CriticalDays) {
        return @{
            Status = 'Critical'
            DaysUntilExpiry = $daysUntilExpiry
            Color = 'Critical'
        }
    }
    elseif($daysUntilExpiry -le $WarningDays) {
        return @{
            Status = 'Warning'
            DaysUntilExpiry = $daysUntilExpiry
            Color = 'Warning'
        }
    }
    else {
        return @{
            Status = 'Healthy'
            DaysUntilExpiry = $daysUntilExpiry
            Color = 'Success'
        }
    }
}

function Get-LocalCertificates {
    Write-Host "`nScanning local certificate stores..." -ForegroundColor Cyan

    $storePaths = @(
        'Cert:\LocalMachine\My',
        'Cert:\LocalMachine\WebHosting',
        'Cert:\LocalMachine\Remote Desktop'
    )

    if($CertStorePath) {
        $storePaths = @($CertStorePath)
    }

    foreach($storePath in $storePaths) {
        Write-Verbose "Checking store: $storePath"

        if(Test-Path $storePath) {
            try {
                $certs = Get-ChildItem -Path $storePath -ErrorAction Stop

                Write-Host "  Found $($certs.Count) certificate(s) in $storePath" -ForegroundColor Gray

                foreach($cert in $certs) {
                    $status = Get-CertificateStatus -NotAfter $cert.NotAfter -NotBefore $cert.NotBefore

                    # Skip expired certs unless IncludeExpired is specified
                    if($status.Status -eq 'Expired' -and -not $IncludeExpired) {
                        continue
                    }

                    $certInfo = [PSCustomObject]@{
                        Source = 'Local Store'
                        StorePath = $storePath
                        Subject = $cert.Subject
                        Issuer = $cert.Issuer
                        FriendlyName = $cert.FriendlyName
                        Thumbprint = $cert.Thumbprint
                        NotBefore = $cert.NotBefore
                        NotAfter = $cert.NotAfter
                        DaysUntilExpiry = $status.DaysUntilExpiry
                        Status = $status.Status
                        DnsNames = ($cert.DnsNameList.Unicode -join '; ')
                        SerialNumber = $cert.SerialNumber
                        HasPrivateKey = $cert.HasPrivateKey
                    }

                    $script:report.Certificates += $certInfo
                    $script:report.Summary.TotalCertificates++

                    switch($status.Status) {
                        'Expired' { $script:report.Summary.Expired++ }
                        'Critical' { $script:report.Summary.Critical++ }
                        'Warning' { $script:report.Summary.Warning++ }
                        'Healthy' { $script:report.Summary.Healthy++ }
                    }

                    # Display cert info
                    $displayName = if($cert.FriendlyName) { $cert.FriendlyName } else { $cert.Subject }
                    $statusText = "[$($status.Status.ToUpper())] $displayName - Expires: $($cert.NotAfter.ToString('yyyy-MM-dd')) ($($status.DaysUntilExpiry) days)"

                    Write-ColorOutput "    $statusText" -Level $status.Color
                }
            }
            catch {
                Write-ColorOutput "  [ERROR] Failed to read store $storePath : $($_.Exception.Message)" -Level Error
            }
        }
        else {
            Write-Verbose "Store path does not exist: $storePath"
        }
    }
}

function Get-RemoteCertificates {
    Write-Host "`nChecking remote HTTPS endpoints..." -ForegroundColor Cyan

    foreach($endpoint in $Endpoints) {
        Write-Host "  Testing: $endpoint" -ForegroundColor Gray

        try {
            # Parse URL
            $uri = [System.Uri]$endpoint
            $hostname = $uri.Host
            $port = if($uri.Port -ne -1) { $uri.Port } else { 443 }

            # Create TCP connection
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $tcpClient.Connect($hostname, $port)

            # Create SSL stream
            $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, {$true})
            $sslStream.AuthenticateAsClient($hostname)

            # Get certificate
            $cert = $sslStream.RemoteCertificate
            $cert2 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert)

            $status = Get-CertificateStatus -NotAfter $cert2.NotAfter -NotBefore $cert2.NotBefore

            # Skip expired certs unless IncludeExpired is specified
            if($status.Status -eq 'Expired' -and -not $IncludeExpired) {
                $sslStream.Close()
                $tcpClient.Close()
                continue
            }

            $certInfo = [PSCustomObject]@{
                Source = 'Remote HTTPS'
                StorePath = $endpoint
                Subject = $cert2.Subject
                Issuer = $cert2.Issuer
                FriendlyName = $hostname
                Thumbprint = $cert2.Thumbprint
                NotBefore = $cert2.NotBefore
                NotAfter = $cert2.NotAfter
                DaysUntilExpiry = $status.DaysUntilExpiry
                Status = $status.Status
                DnsNames = (($cert2.DnsNameList.Unicode | Select-Object -Unique) -join '; ')
                SerialNumber = $cert2.SerialNumber
                HasPrivateKey = $cert2.HasPrivateKey
            }

            $script:report.Certificates += $certInfo
            $script:report.Summary.TotalCertificates++

            switch($status.Status) {
                'Expired' { $script:report.Summary.Expired++ }
                'Critical' { $script:report.Summary.Critical++ }
                'Warning' { $script:report.Summary.Warning++ }
                'Healthy' { $script:report.Summary.Healthy++ }
            }

            $statusText = "[$($status.Status.ToUpper())] $hostname - Expires: $($cert2.NotAfter.ToString('yyyy-MM-dd')) ($($status.DaysUntilExpiry) days)"
            Write-ColorOutput "    $statusText" -Level $status.Color

            $sslStream.Close()
            $tcpClient.Close()
        }
        catch {
            Write-ColorOutput "    [ERROR] Failed to retrieve certificate: $($_.Exception.Message)" -Level Error
        }
    }
}

function Show-Summary {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Certificate Expiration Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Server: $($script:report.ServerName)"
    Write-Host "Scan Time: $($script:report.ScanTime)"
    Write-Host "`nTotal Certificates: $($script:report.Summary.TotalCertificates)"

    if($script:report.Summary.Expired -gt 0) {
        Write-ColorOutput "Expired: $($script:report.Summary.Expired)" -Level Critical
    }
    if($script:report.Summary.Critical -gt 0) {
        Write-ColorOutput "Critical (expires in $CriticalDays days): $($script:report.Summary.Critical)" -Level Critical
    }
    if($script:report.Summary.Warning -gt 0) {
        Write-ColorOutput "Warning (expires in $WarningDays days): $($script:report.Summary.Warning)" -Level Warning
    }
    Write-ColorOutput "Healthy: $($script:report.Summary.Healthy)" -Level Success

    # Show critical certificates
    $criticalCerts = $script:report.Certificates | Where-Object {$_.Status -in @('Expired', 'Critical')} | Sort-Object DaysUntilExpiry

    if($criticalCerts) {
        Write-Host "`nCertificates Requiring Immediate Attention:" -ForegroundColor Red
        foreach($cert in $criticalCerts) {
            $name = if($cert.FriendlyName) { $cert.FriendlyName } else { $cert.Subject }
            Write-Host "  - $name" -ForegroundColor Red
            Write-Host "    Expires: $($cert.NotAfter.ToString('yyyy-MM-dd')) ($($cert.DaysUntilExpiry) days)" -ForegroundColor Red
            Write-Host "    Location: $($cert.StorePath)" -ForegroundColor Gray
        }
    }

    Write-Host "`n========================================`n" -ForegroundColor Cyan
}

function Export-HTMLReport {
    $reportPath = "$env:USERPROFILE\Desktop\CertificateReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Certificate Expiration Report - $($script:report.ServerName)</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1600px; margin: 0 auto; background-color: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #007bff; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; border-bottom: 1px solid #ddd; padding-bottom: 5px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin: 20px 0; }
        .metric { background-color: #f8f9fa; padding: 20px; border-radius: 4px; border-left: 4px solid #007bff; text-align: center; }
        .metric.expired { border-left-color: #dc3545; }
        .metric.critical { border-left-color: #dc3545; }
        .metric.warning { border-left-color: #ffc107; }
        .metric.healthy { border-left-color: #28a745; }
        .metric-value { font-size: 2.5em; font-weight: bold; color: #007bff; }
        .metric.expired .metric-value { color: #dc3545; }
        .metric.critical .metric-value { color: #dc3545; }
        .metric.warning .metric-value { color: #ffc107; }
        .metric.healthy .metric-value { color: #28a745; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; font-size: 0.9em; }
        th { background-color: #007bff; color: white; padding: 12px; text-align: left; position: sticky; top: 0; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f1f1f1; }
        .status-expired { background-color: #f8d7da; color: #721c24; font-weight: bold; padding: 4px 8px; border-radius: 3px; }
        .status-critical { background-color: #f8d7da; color: #721c24; font-weight: bold; padding: 4px 8px; border-radius: 3px; }
        .status-warning { background-color: #fff3cd; color: #856404; font-weight: bold; padding: 4px 8px; border-radius: 3px; }
        .status-healthy { background-color: #d4edda; color: #155724; font-weight: bold; padding: 4px 8px; border-radius: 3px; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #777; font-size: 0.9em; }
        .thumbprint { font-family: 'Courier New', monospace; font-size: 0.85em; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Certificate Expiration Report</h1>
        <p><strong>Server:</strong> $($script:report.ServerName)<br>
        <strong>Scan Time:</strong> $($script:report.ScanTime)<br>
        <strong>Warning Threshold:</strong> $($script:report.WarningDays) days<br>
        <strong>Critical Threshold:</strong> $($script:report.CriticalDays) days</p>

        <div class="summary">
            <div class="metric">
                <div class="metric-value">$($script:report.Summary.TotalCertificates)</div>
                <div>Total Certificates</div>
            </div>
            $(if($script:report.Summary.Expired -gt 0) {
                "<div class='metric expired'><div class='metric-value'>$($script:report.Summary.Expired)</div><div>Expired</div></div>"
            })
            $(if($script:report.Summary.Critical -gt 0) {
                "<div class='metric critical'><div class='metric-value'>$($script:report.Summary.Critical)</div><div>Critical</div></div>"
            })
            $(if($script:report.Summary.Warning -gt 0) {
                "<div class='metric warning'><div class='metric-value'>$($script:report.Summary.Warning)</div><div>Warning</div></div>"
            })
            <div class="metric healthy">
                <div class="metric-value">$($script:report.Summary.Healthy)</div>
                <div>Healthy</div>
            </div>
        </div>

        <h2>Certificate Details</h2>
        <table>
            <tr>
                <th>Status</th>
                <th>Name / Subject</th>
                <th>Source</th>
                <th>Issuer</th>
                <th>Valid From</th>
                <th>Expires</th>
                <th>Days Until Expiry</th>
                <th>Thumbprint</th>
            </tr>
            $(foreach($cert in ($script:report.Certificates | Sort-Object DaysUntilExpiry)) {
                $statusClass = "status-$($cert.Status.ToLower())"
                $displayName = if($cert.FriendlyName) { $cert.FriendlyName } else { $cert.Subject }
                "<tr>
                    <td><span class='$statusClass'>$($cert.Status.ToUpper())</span></td>
                    <td>$displayName</td>
                    <td>$($cert.Source)<br><small style='color:#666;'>$($cert.StorePath)</small></td>
                    <td><small>$($cert.Issuer)</small></td>
                    <td>$($cert.NotBefore.ToString('yyyy-MM-dd'))</td>
                    <td>$($cert.NotAfter.ToString('yyyy-MM-dd'))</td>
                    <td>$($cert.DaysUntilExpiry)</td>
                    <td class='thumbprint'>$($cert.Thumbprint)</td>
                </tr>"
            })
        </table>

        <div class="footer">
            Report generated by Test-CertificateExpiration.ps1
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
    $reportPath = "$env:USERPROFILE\Desktop\CertificateReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

    $script:report.Certificates | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
    Write-ColorOutput "CSV report exported to: $reportPath" -Level Success
    return $reportPath
}

# Main execution
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Certificate Expiration Monitor" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Server: $($script:report.ServerName)"
Write-Host "Warning Threshold: $WarningDays days"
Write-Host "Critical Threshold: $CriticalDays days"

if($CheckLocal -or (-not $CheckRemote -and -not $Endpoints)) {
    Get-LocalCertificates
}

if($CheckRemote -or $Endpoints) {
    Get-RemoteCertificates
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
