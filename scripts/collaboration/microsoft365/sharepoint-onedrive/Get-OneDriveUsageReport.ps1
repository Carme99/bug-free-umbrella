<#
.SYNOPSIS
    Generates OneDrive for Business usage and storage report.

.DESCRIPTION
    This script analyzes OneDrive usage for:
    - Storage usage per user
    - File counts and sharing statistics
    - Inactive OneDrive sites
    - Users approaching storage quotas
    - External sharing configuration
    - Site collection details

.PARAMETER StorageWarningThreshold
    Percentage of quota used to trigger warning (default: 80).

.PARAMETER InactivityDays
    Days since last activity to consider site inactive (default: 90).

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Get-OneDriveUsageReport.ps1
    Basic OneDrive usage report.

.EXAMPLE
    .\Get-OneDriveUsageReport.ps1 -StorageWarningThreshold 90 -InactivityDays 180 -ExportHTML
    Detailed report with custom thresholds.

.NOTES
    Requires SharePoint Online PowerShell module and Microsoft Graph
    Requires SharePoint Administrator or Global Reader role
    Compatible with SharePoint Online (Microsoft 365)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [int]$StorageWarningThreshold = 80,

    [Parameter(Mandatory=$false)]
    [int]$InactivityDays = 90,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "`n=== OneDrive for Business Usage Report ===" -ForegroundColor Cyan
Write-Host "Storage Warning Threshold: $StorageWarningThreshold%" -ForegroundColor Yellow
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

# Check for required modules
try {
    if (-not (Get-Module -Name Microsoft.Online.SharePoint.PowerShell -ListAvailable)) {
        Write-Host "[-] SharePoint Online module not found!" -ForegroundColor Red
        Write-Host "[!] Install with: Install-Module -Name Microsoft.Online.SharePoint.PowerShell" -ForegroundColor Yellow
        exit 1
    }

    if (-not (Get-Module -Name Microsoft.Graph -ListAvailable)) {
        Write-Host "[-] Microsoft Graph module not found!" -ForegroundColor Red
        Write-Host "[!] Install with: Install-Module -Name Microsoft.Graph" -ForegroundColor Yellow
        exit 1
    }

    # Connect to Microsoft Graph for usage data
    Write-Host "[*] Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes "Reports.Read.All" -NoWelcome

    Write-Host "[+] Connected to Microsoft Graph" -ForegroundColor Green
}
catch {
    Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Get OneDrive usage report from Graph
Write-Host "[*] Retrieving OneDrive usage data..." -ForegroundColor Cyan

try {
    # Get OneDrive usage details
    $oneDriveUsage = Get-MgReportOneDriveUsageAccountDetail -Period D30 -OutFile "$env:TEMP\onedrive_usage.csv"
    $usageData = Import-Csv "$env:TEMP\onedrive_usage.csv"

    Write-Host "[+] Found $($usageData.Count) OneDrive site(s)" -ForegroundColor Green
}
catch {
    Write-Host "[-] Error retrieving usage data: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

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
        Owner = $site.'Owner Display Name'
        OwnerUPN = $site.'Owner Principal Name'
        SiteURL = $site.'Site URL'
        StorageUsedGB = $storageUsedGB
        StorageQuotaGB = $storageQuotaGB
        StoragePercent = $storagePercent
        FileCount = $site.'File Count'
        ActiveFileCount = $site.'Active File Count'
        LastActivityDate = $lastActivityDate
        IsInactive = $isInactive
        IsDeleted = $site.'Is Deleted'
        Status = $status
    }

    $results += $result
}

# Clean up temp file
Remove-Item "$env:TEMP\onedrive_usage.csv" -Force -ErrorAction SilentlyContinue

Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Total OneDrive Sites: $($results.Count)" -ForegroundColor White
Write-Host "Total Storage Used: $([math]::Round($totalStorageGB, 2)) GB" -ForegroundColor White
Write-Host "Storage Warnings (>$StorageWarningThreshold%): $storageWarnings" -ForegroundColor Yellow
Write-Host "Inactive Sites (>$InactivityDays days): $inactiveSites" -ForegroundColor Yellow
Write-Host ""

# Show top storage users
Write-Host "=== Top 10 Storage Users ===" -ForegroundColor Cyan
$results | Sort-Object StorageUsedGB -Descending |
    Select-Object -First 10 Owner, StorageUsedGB, StoragePercent, FileCount |
    Format-Table -AutoSize

# Show storage warnings
if ($storageWarnings -gt 0) {
    Write-Host "`n=== Storage Warnings ===" -ForegroundColor Yellow
    $results | Where-Object { $_.Status -eq "Warning" } |
        Select-Object -First 10 Owner, StorageUsedGB, StorageQuotaGB, StoragePercent |
        Format-Table -AutoSize
}

# Show inactive sites
if ($inactiveSites -gt 0) {
    Write-Host "`n=== Inactive OneDrive Sites ===" -ForegroundColor Yellow
    $results | Where-Object { $_.IsInactive -eq $true } |
        Select-Object -First 10 Owner, LastActivityDate, StorageUsedGB |
        Format-Table -AutoSize
}

# Export
if ($ExportHTML) {
    $htmlPath = "$env:USERPROFILE\Desktop\OneDriveUsageReport_$timestamp.html"

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
            <td>$($result.Owner)</td>
            <td>$($result.StorageUsedGB)</td>
            <td>$($result.StorageQuotaGB)</td>
            <td>$($result.StoragePercent)</td>
            <td>$($result.FileCount)</td>
            <td>$($result.LastActivityDate)</td>
            <td>$($result.Status)</td>
        </tr>
"@
    }

    $html += "</table></body></html>"
    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($ExportCSV) {
    $csvPath = "$env:USERPROFILE\Desktop\OneDriveUsageReport_$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

Write-Host "`n[+] Report completed!" -ForegroundColor Green

# Disconnect
Disconnect-MgGraph | Out-Null

exit 0
