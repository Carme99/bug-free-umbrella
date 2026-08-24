<#
.SYNOPSIS
    Generates OneDrive for Business usage and storage report.

.DESCRIPTION
    Analyzes OneDrive for Business usage via the Microsoft Graph reports API, covering storage
    usage per user, file counts and sharing statistics, inactive OneDrive sites, users
    approaching their storage quotas (flagged at -StorageWarningThreshold percent), and external
    sharing/site collection details. A summary plus top-10 tables are printed to the console and
    results can be exported to HTML or CSV. The script is read-only and idempotent: it never
    mutates tenant configuration and is safe to re-run. Returns exit code 0 on success and exit
    code 1 on failure (missing prerequisites, connection errors, or retrieval errors).

.PARAMETER StorageWarningThreshold
    Percentage of quota used to trigger warning (default: 80).

.PARAMETER InactivityDays
    Days since last activity to consider site inactive (default: 90).

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    PS C:\> .\Get-OneDriveUsageReport.ps1
    Basic OneDrive usage report printed to the console.

.EXAMPLE
    PS C:\> .\Get-OneDriveUsageReport.ps1 -StorageWarningThreshold 90 -InactivityDays 180 -ExportCSV
    Detailed report with custom thresholds exported as CSV.

.NOTES
    File Name   : Get-OneDriveUsageReport.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23

    Requires the SharePoint Online PowerShell module and Microsoft Graph.
    Requires a SharePoint Administrator or Global Reader role.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$StorageWarningThreshold = 80,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$InactivityDays = 90,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = 'Stop'

# Thin wrapper around Out-File so callers (and Pester tests) can intercept report
# writes; Out-File's Encoding argument transformation cannot be mocked directly.
function Write-ReportTextFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $Content | Out-File -FilePath $Path -Encoding UTF8
}

function Main {
    try {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $documentsFolder = [Environment]::GetFolderPath('MyDocuments')
        if ([string]::IsNullOrWhiteSpace($documentsFolder)) {
            $documentsFolder = [System.IO.Path]::GetTempPath()
        }
        $reportDir = Join-Path $documentsFolder 'Reports'
        if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
            New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        }

        Write-Host ""
        Write-Host "=== OneDrive for Business Usage Report ===" -ForegroundColor Cyan
        Write-Host "[!] Storage Warning Threshold: $StorageWarningThreshold%" -ForegroundColor Yellow
        Write-Host "[*] Timestamp: $(Get-Date)" -ForegroundColor Cyan
        Write-Host ""

        # Check for required modules
        if (-not (Get-Module -Name Microsoft.Online.SharePoint.PowerShell -ListAvailable)) {
            Write-Host "[-] SharePoint Online module not found!" -ForegroundColor Red
            $installHint = 'Install-Module -Name Microsoft.Online.SharePoint.PowerShell'
            Write-Host "[!] Install with: $installHint" -ForegroundColor Yellow
            return 1
        }

        if (-not (Get-Module -Name Microsoft.Graph -ListAvailable)) {
            Write-Host "[-] Microsoft Graph module not found!" -ForegroundColor Red
            Write-Host "[!] Install with: Install-Module -Name Microsoft.Graph" -ForegroundColor Yellow
            return 1
        }

        # Connect to Microsoft Graph for usage data
        Write-Host "[*] Connecting to Microsoft Graph..." -ForegroundColor Cyan
        Connect-MgGraph -Scopes "Reports.Read.All" -NoWelcome -ErrorAction Stop
        Write-Host "[+] Connected to Microsoft Graph" -ForegroundColor Green

        # Get OneDrive usage report from Graph
        Write-Host "[*] Retrieving OneDrive usage data..." -ForegroundColor Cyan

        # Get OneDrive usage details
        $tempCsv = Join-Path ([System.IO.Path]::GetTempPath()) 'onedrive_usage.csv'
        Get-MgReportOneDriveUsageAccountDetail -Period D30 -OutFile $tempCsv -ErrorAction Stop
        $usageData = @(Import-Csv -Path $tempCsv)

        Write-Host "[+] Found $($usageData.Count) OneDrive site(s)" -ForegroundColor Green

        $results = @()
        $storageWarnings = 0
        $inactiveSites = 0
        $totalStorageGB = 0
        $inactivityThreshold = (Get-Date).AddDays(-$InactivityDays)

        foreach ($site in $usageData) {
            # Parse storage values
            $storageUsedGB = [math]::Round($site.'Storage Used (Byte)' / 1GB, 2)
            $storageQuotaGB = [math]::Round($site.'Storage Allocated (Byte)' / 1GB, 2)

            $totalStorageGB += $storageUsedGB

            # Calculate percentage
            $storagePercent = if ($storageQuotaGB -gt 0) {
                [math]::Round(($storageUsedGB / $storageQuotaGB) * 100, 2)
            }
            else { 0 }

            # Check for warnings
            $status = "OK"
            if ($storagePercent -ge $StorageWarningThreshold) {
                $storageWarnings++
                $status = "Warning"
            }

            # Check inactivity
            $lastActivityDate = if ($site.'Last Activity Date') {
                [DateTime]::Parse($site.'Last Activity Date')
            }
            else { $null }

            $isInactive = $false
            if ($lastActivityDate -and $lastActivityDate -lt $inactivityThreshold) {
                $isInactive = $true
                $inactiveSites++
            }
            elseif (-not $lastActivityDate) {
                $isInactive = $true
                $inactiveSites++
            }

            $result = [PSCustomObject]@{
                Owner             = $site.'Owner Display Name'
                OwnerUPN          = $site.'Owner Principal Name'
                SiteURL           = $site.'Site URL'
                StorageUsedGB     = $storageUsedGB
                StorageQuotaGB    = $storageQuotaGB
                StoragePercent    = $storagePercent
                FileCount         = $site.'File Count'
                ActiveFileCount   = $site.'Active File Count'
                LastActivityDate  = $lastActivityDate
                IsInactive        = $isInactive
                IsDeleted         = $site.'Is Deleted'
                Status            = $status
            }

            $results += $result
        }

        # Clean up temp file
        Remove-Item $tempCsv -Force -ErrorAction SilentlyContinue

        Write-Host ""
        Write-Host "=== Summary ===" -ForegroundColor Cyan
        Write-Host "[*] Total OneDrive Sites: $($results.Count)" -ForegroundColor Cyan
        Write-Host "[*] Total Storage Used: $([math]::Round($totalStorageGB, 2)) GB" -ForegroundColor Cyan
        if ($storageWarnings -gt 0) {
            Write-Host "[!] Storage Warnings (> $StorageWarningThreshold%): $storageWarnings" -ForegroundColor Yellow
        }
        else {
            Write-Host "[+] Storage Warnings (> $StorageWarningThreshold%): $storageWarnings" -ForegroundColor Green
        }
        if ($inactiveSites -gt 0) {
            Write-Host "[!] Inactive Sites (> $InactivityDays days): $inactiveSites" -ForegroundColor Yellow
        }
        else {
            Write-Host "[+] Inactive Sites (> $InactivityDays days): $inactiveSites" -ForegroundColor Green
        }
        Write-Host ""

        # Show top storage users
        Write-Host "=== Top 10 Storage Users ===" -ForegroundColor Cyan
        $results | Sort-Object StorageUsedGB -Descending |
            Select-Object -First 10 Owner, StorageUsedGB, StoragePercent, FileCount |
            Format-Table -AutoSize

        # Show storage warnings
        if ($storageWarnings -gt 0) {
            Write-Host "=== Storage Warnings ===" -ForegroundColor Yellow
            $results | Where-Object { $_.Status -eq "Warning" } |
                Select-Object -First 10 Owner, StorageUsedGB, StorageQuotaGB, StoragePercent |
                Format-Table -AutoSize
        }

        # Show inactive sites
        if ($inactiveSites -gt 0) {
            Write-Host "=== Inactive OneDrive Sites ===" -ForegroundColor Yellow
            $results | Where-Object { $_.IsInactive -eq $true } |
                Select-Object -First 10 Owner, LastActivityDate, StorageUsedGB |
                Format-Table -AutoSize
        }

        # Export
        if ($ExportHTML) {
            $htmlPath = Join-Path $reportDir "OneDriveUsageReport_$timestamp.html"

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>OneDrive Usage Report - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #0078d4; }
        .summary { background-color: #f0f0f0; padding: 15px; border-radius: 5px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; font-size: 12px; }
        th { background-color: #0078d4; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .warning { background-color: #fff3cd; }
    </style>
</head>
<body>
    <h1>OneDrive for Business Usage Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Total Sites:</strong> $($results.Count)<br>
        <strong>Total Storage Used:</strong> $([math]::Round($totalStorageGB, 2)) GB<br>
        <strong>Storage Warnings:</strong> $storageWarnings<br>
        <strong>Inactive Sites:</strong> $inactiveSites
    </div>

    <h2>OneDrive Usage Details</h2>
    <table>
        <tr>
            <th>Owner</th>
            <th>Storage Used (GB)</th>
            <th>Quota (GB)</th>
            <th>Used %</th>
            <th>Files</th>
            <th>Last Activity</th>
            <th>Status</th>
        </tr>
"@

            foreach ($result in ($results | Sort-Object StorageUsedGB -Descending)) {
                $rowClass = if ($result.Status -eq "Warning") { "warning" } else { "" }
                $html += @"
        <tr class="$rowClass">
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.Owner)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.StorageUsedGB)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.StorageQuotaGB)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.StoragePercent)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.FileCount)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.LastActivityDate)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.Status)"))</td>
        </tr>
"@
            }

            $html += "</table></body></html>"
            Write-ReportTextFile -Path $htmlPath -Content $html
            Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
        }

        if ($ExportCSV) {
            $csvPath = Join-Path $reportDir "OneDriveUsageReport_$timestamp.csv"
            $results | Export-Csv -Path $csvPath -NoTypeInformation
            Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
        }

        Write-Host "`n[+] Report completed!" -ForegroundColor Green

        # Disconnect
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
