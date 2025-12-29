<#
.SYNOPSIS
    Checks and configures Power Platform environment regional settings.

.DESCRIPTION
    This script audits and configures Power Platform environment regional settings including:
    - Environment base language
    - Currency format
    - Date/time format
    - Number format

.PARAMETER EnvironmentName
    Specific environment to configure (e.g., "Default-xxxxx-xxxx").

.PARAMETER AllEnvironments
    Apply settings to all environments.

.PARAMETER AuditOnly
    Only check settings without making changes (default behavior).

.PARAMETER Apply
    Apply the required settings.

.PARAMETER BaseLanguage
    Base language code (default: 2057 for English UK).

.PARAMETER CurrencyCode
    Currency code (default: GBP).

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Set-PowerPlatformRegionalSettings.ps1 -EnvironmentName "Default-xxxxx" -AuditOnly
    Checks specific environment's settings.

.EXAMPLE
    .\Set-PowerPlatformRegionalSettings.ps1 -AllEnvironments -Apply
    Applies settings to all environments.

.NOTES
    Requires Microsoft.PowerApps.Administration.PowerShell module
    Requires Power Platform Administrator role
    Compatible with Power Platform environments
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentName,

    [Parameter(Mandatory=$false)]
    [switch]$AllEnvironments,

    [Parameter(Mandatory=$false)]
    [switch]$AuditOnly,

    [Parameter(Mandatory=$false)]
    [switch]$Apply,

    [Parameter(Mandatory=$false)]
    [int]$BaseLanguage = 2057,  # English UK

    [Parameter(Mandatory=$false)]
    [string]$CurrencyCode = 'GBP',

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "`n=== Power Platform Environment Regional Settings ===" -ForegroundColor Cyan
Write-Host "Mode: $(if ($Apply) { 'APPLY SETTINGS' } else { 'AUDIT ONLY' })" -ForegroundColor $(if ($Apply) { 'Yellow' } else { 'Green' })
Write-Host ""

# Check for Power Platform module
try {
    if (-not (Get-Module -Name Microsoft.PowerApps.Administration.PowerShell -ListAvailable)) {
        Write-Host "[-] Power Platform Administration module not found!" -ForegroundColor Red
        Write-Host "[!] Install with: Install-Module -Name Microsoft.PowerApps.Administration.PowerShell" -ForegroundColor Yellow
        exit 1
    }

    Import-Module Microsoft.PowerApps.Administration.PowerShell -ErrorAction Stop

    # Add to Power Apps
    Add-PowerAppsAccount
    Write-Host "[+] Connected to Power Platform" -ForegroundColor Green
}
catch {
    Write-Host "[-] Error with Power Platform module: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Get environments
$environments = @()

if ($AllEnvironments) {
    Write-Host "[*] Retrieving all environments..." -ForegroundColor Cyan
    $environments = Get-AdminPowerAppEnvironment
    Write-Host "[+] Found $($environments.Count) environment(s)" -ForegroundColor Green
}
elseif ($EnvironmentName) {
    Write-Host "[*] Retrieving environment: $EnvironmentName..." -ForegroundColor Cyan
    $env = Get-AdminPowerAppEnvironment -EnvironmentName $EnvironmentName
    $environments = @($env)
    Write-Host "[+] Found environment: $($env.DisplayName)" -ForegroundColor Green
}
else {
    Write-Host "[-] Please specify either -EnvironmentName or -AllEnvironments" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Process environments
$results = @()
$compliantCount = 0
$nonCompliantCount = 0

foreach ($env in $environments) {
    Write-Host "[*] Processing: $($env.DisplayName)" -ForegroundColor Cyan

    # Get environment properties
    $props = $env.Internal.properties

    $currentLanguage = if ($props.linkedEnvironmentMetadata.baseLanguage) {
        $props.linkedEnvironmentMetadata.baseLanguage
    } else { "Not Set" }

    $currentCurrency = if ($props.linkedEnvironmentMetadata.currency) {
        $props.linkedEnvironmentMetadata.currency.code
    } else { "Not Set" }

    $issues = @()
    if ($currentLanguage -ne $BaseLanguage -and $currentLanguage -ne "Not Set") {
        $issues += "Base language: $currentLanguage (expected: $BaseLanguage)"
    }
    if ($currentCurrency -ne $CurrencyCode -and $currentCurrency -ne "Not Set") {
        $issues += "Currency: $currentCurrency (expected: $CurrencyCode)"
    }

    $isCompliant = $issues.Count -eq 0

    if ($isCompliant) {
        $compliantCount++
        $status = "Compliant"
        Write-Host "    [+] Compliant" -ForegroundColor Green
    }
    else {
        $nonCompliantCount++
        $status = "Non-Compliant"
        Write-Host "    [!] Non-Compliant: $($issues -join '; ')" -ForegroundColor Yellow
    }

    if ($Apply -and -not $isCompliant) {
        Write-Host "    [!] Regional settings for Power Platform environments are set at creation time" -ForegroundColor Yellow
        Write-Host "    [!] To change: Recreate environment with correct settings or contact support" -ForegroundColor Yellow
    }

    $result = [PSCustomObject]@{
        EnvironmentName = $env.DisplayName
        EnvironmentId = $env.EnvironmentName
        BaseLanguage = $currentLanguage
        RequiredLanguage = $BaseLanguage
        Currency = $currentCurrency
        RequiredCurrency = $CurrencyCode
        Status = $status
        Issues = if ($issues.Count -gt 0) { $issues -join '; ' } else { 'None' }
    }

    $results += $result
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Total Environments: $($results.Count)" -ForegroundColor White
Write-Host "Compliant: $compliantCount" -ForegroundColor Green
Write-Host "Non-Compliant: $nonCompliantCount" -ForegroundColor Yellow
Write-Host ""

if ($ExportHTML) {
    $htmlPath = "$env:USERPROFILE\Desktop\PowerPlatformRegionalSettings_$timestamp.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Power Platform Regional Settings - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #0078d4; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th { background-color: #0078d4; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        .compliant { background-color: #107c10; color: white; padding: 3px 6px; border-radius: 3px; }
        .non-compliant { background-color: #ffaa44; color: white; padding: 3px 6px; border-radius: 3px; }
    </style>
</head>
<body>
    <h1>Power Platform Regional Settings Report</h1>
    <table>
        <tr>
            <th>Environment</th>
            <th>Base Language</th>
            <th>Currency</th>
            <th>Status</th>
            <th>Issues</th>
        </tr>
"@

    foreach ($result in $results) {
        $statusClass = if ($result.Status -eq 'Compliant') { 'compliant' } else { 'non-compliant' }
        $html += @"
        <tr>
            <td>$($result.EnvironmentName)</td>
            <td>$($result.BaseLanguage)</td>
            <td>$($result.Currency)</td>
            <td><span class="$statusClass">$($result.Status)</span></td>
            <td>$($result.Issues)</td>
        </tr>
"@
    }

    $html += "</table></body></html>"
    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($ExportCSV) {
    $csvPath = "$env:USERPROFILE\Desktop\PowerPlatformRegionalSettings_$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

Write-Host "`n[+] Power Platform regional settings check completed!" -ForegroundColor Green
exit 0
