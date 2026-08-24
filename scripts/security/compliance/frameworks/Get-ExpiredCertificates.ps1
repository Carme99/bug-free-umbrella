<#
.SYNOPSIS
    Find expired or expiring certificates across the machine and user certificate stores.

.DESCRIPTION
    Scans certificate stores (LocalMachine by default, plus CurrentUser with -AllStores) to identify
    expired certificates, certificates expiring within the -DaysToExpire threshold, and self-signed
    certificates among the findings.
    - Reports per-certificate detail: subject, issuer, thumbprint, store, days until expiry
    - Appends remediation recommendations when issues are found
    - Optionally exports CSV and HTML reports to a local Documents\Reports directory
    Side effects: creates report files under Documents\Reports when -ExportReport is supplied.
    Requires Administrator privileges for LocalMachine stores.
    Exit codes: 0 = no expired or expiring certificates found; 1 = issues found or a fatal error.

.PARAMETER DaysToExpire
    Number of days to look ahead for expiring certificates. Default is 30.

.PARAMETER AllStores
    Scan all certificate stores, including CurrentUser. Default scans only LocalMachine stores.

.PARAMETER ExportReport
    Generate HTML and CSV reports in the local Documents\Reports directory.

.EXAMPLE
    PS C:\> .\Get-ExpiredCertificates.ps1

    Finds certificates expired or expiring within 30 days; returns 1 if any are found.

.EXAMPLE
    PS C:\> .\Get-ExpiredCertificates.ps1 -DaysToExpire 60 -AllStores -ExportReport

    Scans LocalMachine and CurrentUser stores with a 60-day threshold and generates HTML/CSV reports.

.NOTES
    File Name   : Get-ExpiredCertificates.ps1
    Author      : Security & Compliance Team
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateRange(0, [int]::MaxValue)]
    [int]$DaysToExpire = 30,

    [Parameter()]
    [switch]$AllStores,

    [Parameter()]
    [switch]$ExportReport
)

# PSSA note: remaining warnings are intentional/false positives:
# - PSAvoidUsingWriteHost: colored [prefix] console reporting via Write-Host is
#   mandated by the relaunch output standard.
# - PSReviewUnusedParameter: parameters are consumed inside Main (PSSA cannot see
#   through the wrapper).
# - PSShouldProcess on Main: it deliberately uses the script-level CmdletBinding
#   SupportsShouldProcess binding's $PSCmdlet.
$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] ========================================" -ForegroundColor Cyan
        Write-Host "[*]    Certificate Expiration Check" -ForegroundColor Cyan
        Write-Host "[*]    Threshold: $DaysToExpire days" -ForegroundColor Cyan
        Write-Host "[*] ========================================" -ForegroundColor Cyan

        $Results = @()
        $IssuesFound = $false
        $ThresholdDate = (Get-Date).AddDays($DaysToExpire)

        # Define certificate store locations to scan
        $StoreLocations = @('LocalMachine')
        if ($AllStores) {
            $StoreLocations += 'CurrentUser'
        }

        Write-Host "[*] [1/3] Scanning certificate stores..." -ForegroundColor Yellow

        $TotalCertsScanned = 0

        foreach ($Location in $StoreLocations) {
            Write-Host "[*]   Scanning $Location stores..." -ForegroundColor Cyan

            # Get all certificate stores for this location
            $Stores = @('My', 'Root', 'CA', 'TrustedPublisher', 'TrustedPeople', 'AuthRoot')

            foreach ($StoreName in $Stores) {
                try {
                    $Store = Get-Item "Cert:\$Location\$StoreName" -ErrorAction SilentlyContinue
                    if (-not $Store) { continue }

                    $Certificates = Get-ChildItem "Cert:\$Location\$StoreName" -ErrorAction SilentlyContinue
                    if (-not $Certificates) { continue }

                    Write-Host "    Checking $StoreName ($($Certificates.Count) certificates)..." -ForegroundColor Gray
                    $TotalCertsScanned += $Certificates.Count

                    foreach ($Cert in $Certificates) {
                        $Status = "Valid"
                        $DaysUntilExpiry = ($Cert.NotAfter - (Get-Date)).Days
                        $Issue = ""

                        # Check if expired
                        if ($Cert.NotAfter -lt (Get-Date)) {
                            $Status = "Expired"
                            $Issue = "Certificate expired $([math]::Abs($DaysUntilExpiry)) days ago"
                            $IssuesFound = $true
                        }
                        # Check if expiring soon
                        elseif ($Cert.NotAfter -lt $ThresholdDate) {
                            $Status = "Expiring Soon"
                            $Issue = "Expires in $DaysUntilExpiry days"
                            $IssuesFound = $true
                        }
                        # Skip valid certificates that aren't expiring soon
                        else {
                            continue
                        }

                        # Check if self-signed
                        $SelfSigned = $Cert.Issuer -eq $Cert.Subject

                        # Get certificate details
                        $CertInfo = [PSCustomObject]@{
                            Subject         = $Cert.Subject
                            Issuer          = $Cert.Issuer
                            Thumbprint      = $Cert.Thumbprint
                            FriendlyName    = $Cert.FriendlyName
                            NotBefore       = $Cert.NotBefore.ToString("yyyy-MM-dd")
                            NotAfter        = $Cert.NotAfter.ToString("yyyy-MM-dd")
                            DaysUntilExpiry = $DaysUntilExpiry
                            Status          = $Status
                            Issue           = $Issue
                            SelfSigned      = $SelfSigned
                            StoreLocation   = $Location
                            StoreName       = $StoreName
                            HasPrivateKey   = $Cert.HasPrivateKey
                        }

                        $Results += $CertInfo
                    }

                }
                catch {
                    Write-Verbose "Error scanning $Location\$StoreName : $($_.Exception.Message)"
                }
            }
        }

        Write-Host "[+]   Total certificates scanned: $TotalCertsScanned" -ForegroundColor Green

        # Analyze and display results
        Write-Host "[*] [2/3] Analyzing certificates..." -ForegroundColor Yellow

        $ExpiredCerts = $Results | Where-Object { $_.Status -eq 'Expired' }
        $ExpiringSoonCerts = $Results | Where-Object { $_.Status -eq 'Expiring Soon' }

        $expiredColor = if ($ExpiredCerts.Count -gt 0) { 'Red' } else { 'Green' }
        $expiringColor = if ($ExpiringSoonCerts.Count -gt 0) { 'Yellow' } else { 'Green' }
        Write-Host "  Expired certificates: $($ExpiredCerts.Count)" -ForegroundColor $expiredColor
        Write-Host "  Expiring soon: $($ExpiringSoonCerts.Count)" -ForegroundColor $expiringColor

        # Display detailed results
        Write-Host "[*] [3/3] Certificate Details..." -ForegroundColor Yellow

        if ($Results.Count -eq 0) {
            Write-Host "[+] No expired or expiring certificates found!" -ForegroundColor Green
        }
        else {
            # Sort by days until expiry (expired first)
            $Results = @($Results | Sort-Object DaysUntilExpiry)

            foreach ($Cert in $Results) {
                $StatusColor = switch ($Cert.Status) {
                    "Expired" { "Red" }
                    "Expiring Soon" { "Yellow" }
                    default { "Green" }
                }

                Write-Host "[$($Cert.Status.PadRight(13))] " -ForegroundColor $StatusColor -NoNewline
                Write-Host $Cert.Subject -ForegroundColor White

                Write-Host "  Store:      $($Cert.StoreLocation)\$($Cert.StoreName)" -ForegroundColor Gray
                Write-Host "  Issuer:     $($Cert.Issuer)" -ForegroundColor Gray
                Write-Host "  Expires:    $($Cert.NotAfter)" -ForegroundColor Gray
                Write-Host "  Issue:      $($Cert.Issue)" -ForegroundColor $StatusColor

                if ($Cert.SelfSigned) {
                    Write-Host "[!] WARNING:    Self-signed certificate" -ForegroundColor Yellow
                }

                if ($Cert.FriendlyName) {
                    Write-Host "  Name:       $($Cert.FriendlyName)" -ForegroundColor Gray
                }

                Write-Host "  Thumbprint: $($Cert.Thumbprint)" -ForegroundColor DarkGray
            }
        }

        # Summary
        Write-Host "[*] ========================================" -ForegroundColor Cyan
        Write-Host "[*]    Summary" -ForegroundColor Cyan
        Write-Host "[*] ========================================" -ForegroundColor Cyan

        $selfSignedCount = @($Results | Where-Object { $_.SelfSigned }).Count
        Write-Host "Total Certificates Scanned: $TotalCertsScanned" -ForegroundColor White
        Write-Host "Certificates with Issues: $($Results.Count)" -ForegroundColor White
        Write-Host "  Expired: $($ExpiredCerts.Count)" -ForegroundColor Red
        Write-Host "  Expiring Soon (<= $DaysToExpire days): $($ExpiringSoonCerts.Count)" -ForegroundColor Yellow
        Write-Host "  Self-Signed: $selfSignedCount" -ForegroundColor Yellow

        # Recommendations
        if ($Results.Count -gt 0) {
            Write-Host "[!] ========================================" -ForegroundColor Yellow
            Write-Host "[!]    Recommendations" -ForegroundColor Yellow
            Write-Host "[!] ========================================" -ForegroundColor Yellow

            if ($ExpiredCerts.Count -gt 0) {
                Write-Host "[-] Expired Certificates:" -ForegroundColor Red
                Write-Host "  Remove or renew expired certificates immediately" -ForegroundColor White
                Write-Host "  Check if any services are affected" -ForegroundColor White
                Write-Host "  Review certificate revocation lists (CRL)" -ForegroundColor White
            }

            if ($ExpiringSoonCerts.Count -gt 0) {
                Write-Host "[!] Expiring Soon:" -ForegroundColor Yellow
                Write-Host "  Plan certificate renewal before expiration" -ForegroundColor White
                Write-Host "  Coordinate with service owners" -ForegroundColor White
                Write-Host "  Test certificate replacement in non-production first" -ForegroundColor White
            }

            Write-Host "[*] General Best Practices:" -ForegroundColor Cyan
            Write-Host "  Implement automated certificate monitoring" -ForegroundColor White
            Write-Host "  Use certificate auto-enrollment where possible" -ForegroundColor White
            Write-Host "  Maintain a certificate inventory" -ForegroundColor White
            Write-Host "  Set up alerts for certificates expiring in 30-60 days" -ForegroundColor White
            Write-Host "  Remove unused/expired certificates regularly" -ForegroundColor White

            # Certificate removal guidance
            Write-Host "[*] To Remove a Certificate:" -ForegroundColor Cyan
            Write-Host "  1. Open Certificate Manager (certmgr.msc for CurrentUser, certlm.msc for LocalMachine)"  `
                -ForegroundColor White
            Write-Host "  2. Navigate to the appropriate store" -ForegroundColor White
            Write-Host "  3. Right-click the certificate and select Delete" -ForegroundColor White
            Write-Host "  4. Or use PowerShell:" -ForegroundColor White
            Write-Host "     Remove-Item Cert:\LocalMachine\My\<Thumbprint>" -ForegroundColor DarkGray
        }

        # Export reports if requested
        if ($ExportReport) {
            if ($PSCmdlet.ShouldProcess($Results, "Write certificate expiration CSV and HTML reports")) {
                $ReportPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
                # Validate report directory: reject '..' traversal and UNC remote paths before resolution
                if ([string]::IsNullOrWhiteSpace($ReportPath) -or
                    $ReportPath -match '(^|[\\/])\.\.([\\/]|$)' -or
                    $ReportPath -match '^(\\\\|//)') {
                    throw ("Unsafe report directory: $ReportPath. Report directory must be a local " +
                    "absolute path without '..' traversal.")
                }
                $ReportPath = [System.IO.Path]::GetFullPath($ReportPath)
                if (-not (Test-Path -LiteralPath $ReportPath -PathType Container)) {
                    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
                }

                $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
                $TimestampRunId = "${Timestamp}_${RunId}"

                # CSV Export
                $CSVPath = Join-Path $ReportPath "ExpiredCertificates_${TimestampRunId}.csv"
                $Results | Export-Csv -Path $CSVPath -NoTypeInformation -ErrorAction Stop
                Write-Host "[+] CSV Report: $CSVPath" -ForegroundColor Green

                # HTML Export
                $HTMLPath = Join-Path $ReportPath "ExpiredCertificates_${TimestampRunId}.html"
                $HTML = @"
<!DOCTYPE html>
<html>
<head>
    <title>Certificate Expiration Report - $Timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .summary-item { margin: 10px 0; font-size: 16px; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px;
            background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); font-size: 13px; }
        th { background-color: #3498db; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .expired { background-color: #ffebee; color: #c62828; font-weight: bold; }
        .expiring { background-color: #fff3e0; color: #ef6c00; font-weight: bold; }
        .self-signed { color: #f57c00; font-weight: bold; }
        .thumbprint { font-family: monospace; font-size: 11px; color: #666; }
    </style>
</head>
<body>
    <h1>Certificate Expiration Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") | <strong>Run ID:</strong> $RunId</p>
    <p><strong>Computer:</strong> $([System.Net.WebUtility]::HtmlEncode("$env:COMPUTERNAME"))</p>
    <p><strong>Expiration Threshold:</strong> $DaysToExpire days</p>

    <div class="summary">
        <div class="summary-item"><strong>Total Certificates Scanned:</strong> $TotalCertsScanned</div>
        <div class="summary-item"><strong>Certificates with Issues:</strong> $($Results.Count)</div>
        <div class="summary-item"><strong>Expired:</strong>
            <span style="color: #c62828;">$($ExpiredCerts.Count)</span></div>
        <div class="summary-item"><strong>Expiring Soon:</strong>
            <span style="color: #ef6c00;">$($ExpiringSoonCerts.Count)</span></div>
        <div class="summary-item"><strong>Self-Signed:</strong>
            <span style="color: #f57c00;">$selfSignedCount</span></div>
    </div>
"@

                if ($Results.Count -gt 0) {
                    $HTML += @"
    <h2>Certificate Details</h2>
    <table>
        <tr>
            <th>Status</th>
            <th>Subject</th>
            <th>Issuer</th>
            <th>Expires</th>
            <th>Days</th>
            <th>Store</th>
            <th>Self-Signed</th>
            <th>Thumbprint</th>
        </tr>
"@

                    foreach ($Cert in $Results) {
                        $StatusClass = if ($Cert.Status -eq "Expired") { "expired" } else { "expiring" }
                        $SelfSignedText = if ($Cert.SelfSigned) { "Yes" } else { "No" }
                        $SelfSignedClass = if ($Cert.SelfSigned) { "self-signed" } else { "" }

                        $HTML += @"
        <tr>
            <td class="$StatusClass">$([System.Net.WebUtility]::HtmlEncode("$($Cert.Status)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($Cert.Subject)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($Cert.Issuer)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($Cert.NotAfter)"))</td>
            <td>$($Cert.DaysUntilExpiry)</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($Cert.StoreLocation)"))\
            $([System.Net.WebUtility]::HtmlEncode("$($Cert.StoreName)"))</td>
            <td class="$SelfSignedClass">$SelfSignedText</td>
            <td class="thumbprint">$([System.Net.WebUtility]::HtmlEncode("$($Cert.Thumbprint)"))</td>
        </tr>
"@
                    }

                    $HTML += "</table>"
                }
                else {
                    $HTML += "<p style='color: #27ae60; font-size: 18px; font-weight: bold;'>" +
                        "No expired or expiring certificates found!</p>"
                }

                $HTML += @"
    <h2>Recommendations</h2>
    <ul>
        <li>Remove or renew expired certificates immediately</li>
        <li>Plan renewal for certificates expiring soon</li>
        <li>Implement automated certificate monitoring and alerts</li>
        <li>Maintain a certificate inventory and renewal schedule</li>
        <li>Remove unused or expired certificates regularly</li>
        <li>Use certificate auto-enrollment where possible</li>
    </ul>
</body>
</html>
"@

                $HTML | Out-File -FilePath $HTMLPath -Encoding UTF8 -ErrorAction Stop
                Write-Host "[+] HTML Report: $HTMLPath" -ForegroundColor Green
            }
        }

        # Exit code contract: 0 = clean scan, 1 = expired/expiring certificates found
        if ($IssuesFound) {
            Write-Host "[!] Certificate scan completed with issues found." -ForegroundColor Yellow
            return 1
        }

        Write-Host "[+] Certificate scan completed. No issues found." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
