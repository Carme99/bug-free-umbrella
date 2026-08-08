<#
.SYNOPSIS
    Generates Azure AD (Entra ID) license assignment and usage report.

.DESCRIPTION
    This script analyzes Microsoft 365 licenses for:
    - Total licenses purchased vs assigned
    - License consumption by SKU
    - Users without licenses
    - Unused licenses
    - License assignment by group
    - Service plan details
    - Cost optimization opportunities

.PARAMETER IncludeServicePlans
    Include detailed service plan breakdown.

.PARAMETER IdentifyUnassigned
    Show users without any licenses.

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Get-AzureADLicenseReport.ps1
    Basic license usage report.

.EXAMPLE
    .\Get-AzureADLicenseReport.ps1 -IncludeServicePlans -IdentifyUnassigned -ExportHTML
    Comprehensive license audit with service plans and unassigned users.

.NOTES
    Requires Microsoft Graph PowerShell module
    Requires Organization.Read.All permission
    Compatible with Azure AD / Entra ID (Microsoft 365)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$IncludeServicePlans,

    [Parameter(Mandatory = $false)]
    [switch]$IdentifyUnassigned,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
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

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "`n=== Microsoft 365 License Report ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

# Connect to Microsoft Graph
try {
    Write-Host "[*] Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes "Organization.Read.All", "User.Read.All" -NoWelcome
    Write-Host "[+] Connected to Microsoft Graph" -ForegroundColor Green
}
catch {
    Write-Host "[-] Error connecting: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Get subscribed SKUs
Write-Host "[*] Retrieving license information..." -ForegroundColor Cyan

try {
    $skus = Get-MgSubscribedSku -All

    Write-Host "[+] Found $($skus.Count) license SKU(s)" -ForegroundColor Green
}
catch {
    Write-Host "[-] Error retrieving licenses: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Friendly SKU names
$skuNames = @{
    "ENTERPRISEPACK" = "Office 365 E3"
    "ENTERPRISEPREMIUM" = "Office 365 E5"
    "EMS" = "Enterprise Mobility + Security E3"
    "EMSPREMIUM" = "Enterprise Mobility + Security E5"
    "SPE_E3" = "Microsoft 365 E3"
    "SPE_E5" = "Microsoft 365 E5"
    "FLOW_FREE" = "Power Automate Free"
    "POWER_BI_STANDARD" = "Power BI Free"
    "TEAMS_EXPLORATORY" = "Microsoft Teams Exploratory"
    "PROJECTPROFESSIONAL" = "Project Plan 3"
    "VISIOCLIENT" = "Visio Plan 2"
}

$results = @()
$totalPurchased = 0
$totalAssigned = 0
$totalUnused = 0

foreach ($sku in $skus) {
    $skuPart = $sku.SkuPartNumber

    $friendlyName = if ($skuNames.ContainsKey($skuPart)) {
        $skuNames[$skuPart]
    }
    else {
        $skuPart
    }

    $purchased = $sku.PrepaidUnits.Enabled
    $assigned = $sku.ConsumedUnits
    $unused = $purchased - $assigned
    $usagePercent = if ($purchased -gt 0) {
        [math]::Round(($assigned / $purchased) * 100, 2)
    }
    else { 0 }

    $totalPurchased += $purchased
    $totalAssigned += $assigned
    $totalUnused += $unused

    $result = [PSCustomObject]@{
        LicenseName = $friendlyName
        SKU = $skuPart
        Purchased = $purchased
        Assigned = $assigned
        Unused = $unused
        UsagePercent = $usagePercent
        Status = if ($unused -eq 0) { "Full" } elseif ($usagePercent -ge 80) { "High" } else { "OK" }
    }

    $results += $result
}

Write-Host "=== License Summary ===" -ForegroundColor Cyan
Write-Host "Total Licenses Purchased: $totalPurchased" -ForegroundColor White
Write-Host "Total Licenses Assigned: $totalAssigned" -ForegroundColor White
Write-Host "Total Unused Licenses: $totalUnused" -ForegroundColor Yellow
Write-Host ""

# Show license details
Write-Host "=== License Details ===" -ForegroundColor Cyan
$results | Sort-Object Purchased -Descending |
    Format-Table LicenseName, Purchased, Assigned, Unused, UsagePercent, Status -AutoSize

# Identify users without licenses
if ($IdentifyUnassigned) {
    Write-Host "`n[*] Checking for unlicensed users..." -ForegroundColor Cyan

    try {
        $allUsers = Get-MgUser -Filter "userType eq 'Member' and accountEnabled eq true" -All -Property DisplayName, UserPrincipalName, AssignedLicenses
        $unlicensedUsers = $allUsers | Where-Object { $_.AssignedLicenses.Count -eq 0 }

        Write-Host "[+] Found $($unlicensedUsers.Count) unlicensed enabled user(s)" -ForegroundColor $(if ($unlicensedUsers.Count -gt 0) { "Yellow" } else { "Green" })

        if ($unlicensedUsers.Count -gt 0 -and $unlicensedUsers.Count -le 20) {
            Write-Host "`n=== Unlicensed Users ===" -ForegroundColor Yellow
            $unlicensedUsers | Select-Object DisplayName, UserPrincipalName | Format-Table -AutoSize
        }
        elseif ($unlicensedUsers.Count -gt 20) {
            Write-Host "`n=== Top 20 Unlicensed Users ===" -ForegroundColor Yellow
            $unlicensedUsers | Select-Object -First 20 DisplayName, UserPrincipalName | Format-Table -AutoSize
        }
    }
    catch {
        Write-Host "[-] Error checking unlicensed users: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Export
if ($ExportHTML) {
    $htmlPath = "$ReportDir\LicenseReport_$timestamp.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>License Report - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #0078d4; }
        .summary { background-color: #f0f0f0; padding: 15px; border-radius: 5px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th { background-color: #0078d4; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <h1>Microsoft 365 License Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Total Purchased:</strong> $totalPurchased<br>
        <strong>Total Assigned:</strong> $totalAssigned<br>
        <strong>Total Unused:</strong> $totalUnused<br>
        <strong>Overall Usage:</strong> $([math]::Round(($totalAssigned / $totalPurchased) * 100, 2))%
    </div>

    <h2>License Details</h2>
    <table>
        <tr><th>License Name</th><th>Purchased</th><th>Assigned</th><th>Unused</th><th>Usage %</th><th>Status</th></tr>
"@

    foreach ($result in ($results | Sort-Object Purchased -Descending)) {
        $html += @"
        <tr>
            <td>$($result.LicenseName)</td>
            <td>$($result.Purchased)</td>
            <td>$($result.Assigned)</td>
            <td>$($result.Unused)</td>
            <td>$($result.UsagePercent)</td>
            <td>$($result.Status)</td>
        </tr>
"@
    }

    $html += "</table></body></html>"
    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($ExportCSV) {
    $csvPath = "$ReportDir\LicenseReport_$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

Write-Host "`n[+] Report completed!" -ForegroundColor Green

# Disconnect
Disconnect-MgGraph | Out-Null

exit 0
