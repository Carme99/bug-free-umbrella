<#
.SYNOPSIS
    Checks and configures OneDrive personal site regional settings.

.DESCRIPTION
    This script audits and configures OneDrive for Business personal site regional settings.
    OneDrive personal sites are a special type of SharePoint site collection with regional settings.

    Note: OneDrive inherits regional settings from the user's SharePoint personal site.
    This script configures those site-level settings.

.PARAMETER UserPrincipalName
    Specific user's OneDrive to configure.

.PARAMETER AllOneDriveSites
    Apply settings to all OneDrive sites.

.PARAMETER AuditOnly
    Only check settings without making changes (default behavior).

.PARAMETER Apply
    Apply the required settings.

.PARAMETER TimeZone
    Target time zone ID (default: 2 for GMT).

.PARAMETER LocaleId
    Locale ID (default: 2057 for en-GB).

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Set-OneDriveRegionalSettings.ps1 -UserPrincipalName john.doe@company.com -AuditOnly
    Checks specific user's OneDrive settings.

.EXAMPLE
    .\Set-OneDriveRegionalSettings.ps1 -AllOneDriveSites -Apply
    Applies settings to all OneDrive sites.

.NOTES
    Requires PnP.PowerShell module
    Requires SharePoint Administrator role
    OneDrive sites are user-specific SharePoint site collections
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory=$false)]
    [switch]$AllOneDriveSites,

    [Parameter(Mandatory=$false)]
    [switch]$AuditOnly,

    [Parameter(Mandatory=$false)]
    [switch]$Apply,

    [Parameter(Mandatory=$false)]
    [int]$TimeZone = 2,  # GMT

    [Parameter(Mandatory=$false)]
    [int]$LocaleId = 2057,  # en-GB

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

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "`n=== OneDrive Personal Site Regional Settings ===" -ForegroundColor Cyan
Write-Host "Mode: $(if ($Apply) { 'APPLY SETTINGS' } else { 'AUDIT ONLY' })" -ForegroundColor $(if ($Apply) { 'Yellow' } else { 'Green' })
Write-Host ""

Write-Host "[!] NOTE: OneDrive regional settings are part of SharePoint personal sites" -ForegroundColor Yellow
Write-Host "[!] Use Set-SiteRegionalSettings.ps1 for comprehensive site collection management" -ForegroundColor Yellow
Write-Host ""

# Check for PnP PowerShell
try {
    if (-not (Get-Module -Name PnP.PowerShell -ListAvailable)) {
        Write-Host "[-] PnP PowerShell module not found!" -ForegroundColor Red
        Write-Host "[!] Install with: Install-Module -Name PnP.PowerShell" -ForegroundColor Yellow
        exit 1
    }

    Import-Module PnP.PowerShell -ErrorAction Stop
}
catch {
    Write-Host "[-] Error loading PnP PowerShell: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Get OneDrive sites
$onedriveSites = @()

if ($AllOneDriveSites) {
    Write-Host "[*] Retrieving all OneDrive sites..." -ForegroundColor Cyan
    Write-Host "[!] You will be prompted to connect to SharePoint admin center..." -ForegroundColor Yellow

    $adminUrl = Read-Host "Enter your SharePoint admin URL (e.g., https://contoso-admin.sharepoint.com)"
    Connect-PnPOnline -Url $adminUrl -Interactive

    $allSites = Get-PnPTenantSite -IncludeOneDriveSites -Filter "Url -like '-my.sharepoint.com/personal/'"
    Write-Host "[+] Found $($allSites.Count) OneDrive site(s)" -ForegroundColor Green
    $onedriveSites = $allSites
}
elseif ($UserPrincipalName) {
    Write-Host "[*] Determining OneDrive URL for $UserPrincipalName..." -ForegroundColor Cyan

    # Convert UPN to OneDrive URL format
    $username = $UserPrincipalName.Replace("@", "_").Replace(".", "_")
    $tenant = Read-Host "Enter your tenant name (e.g., 'contoso' from contoso.sharepoint.com)"
    $oneDriveUrl = "https://$tenant-my.sharepoint.com/personal/$username"

    Write-Host "[*] OneDrive URL: $oneDriveUrl" -ForegroundColor Gray
    $onedriveSites = @([PSCustomObject]@{ Url = $oneDriveUrl; Title = "$UserPrincipalName OneDrive" })
}
else {
    Write-Host "[-] Please specify either -UserPrincipalName or -AllOneDriveSites" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Process OneDrive sites using same logic as SharePoint sites
Write-Host "[*] OneDrive sites are SharePoint personal sites" -ForegroundColor Cyan
Write-Host "[*] Processing regional settings..." -ForegroundColor Cyan
Write-Host ""

$results = @()
$compliantCount = 0
$nonCompliantCount = 0

foreach ($site in $onedriveSites) {
    $siteUrl = if ($site.Url) { $site.Url } else { $site }

    try {
        Connect-PnPOnline -Url $siteUrl -Interactive -ErrorAction Stop

        $web = Get-PnPWeb -Includes RegionalSettings
        $regional = $web.RegionalSettings

        $currentTimeZone = $regional.TimeZone.Id
        $currentLocaleId = $regional.LocaleId

        $issues = @()
        if ($currentTimeZone -ne $TimeZone) {
            $issues += "Time zone: $currentTimeZone (expected: $TimeZone)"
        }
        if ($currentLocaleId -ne $LocaleId) {
            $issues += "Locale: $currentLocaleId (expected: $LocaleId)"
        }

        $isCompliant = $issues.Count -eq 0

        if ($isCompliant) {
            $compliantCount++
            Write-Host "[+] $siteUrl - Compliant" -ForegroundColor Green
        }
        else {
            $nonCompliantCount++
            Write-Host "[!] $siteUrl - Non-Compliant: $($issues -join '; ')" -ForegroundColor Yellow

            if ($Apply) {
                Write-Host "    [*] Applying settings..." -ForegroundColor Cyan
                Set-PnPWeb -LocaleId $LocaleId -ErrorAction Stop

                $ctx = Get-PnPContext
                $web = $ctx.Web
                $ctx.Load($web.RegionalSettings)
                $ctx.ExecuteQuery()

                $web.RegionalSettings.Update()
                $ctx.ExecuteQuery()

                Write-Host "    [+] Settings applied!" -ForegroundColor Green
            }
        }

        $results += [PSCustomObject]@{
            OneDriveUrl = $siteUrl
            CurrentTimeZone = $currentTimeZone
            CurrentLocale = $currentLocaleId
            Status = if ($isCompliant) { "Compliant" } else { "Non-Compliant" }
            Issues = if ($issues.Count -gt 0) { $issues -join '; ' } else { 'None' }
        }
    }
    catch {
        Write-Host "[-] Error processing $siteUrl : $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Total OneDrive Sites: $($results.Count)" -ForegroundColor White
Write-Host "Compliant: $compliantCount" -ForegroundColor Green
Write-Host "Non-Compliant: $nonCompliantCount" -ForegroundColor Yellow

if ($ExportCSV) {
    $csvPath = "$ReportDir\OneDriveRegionalSettings_$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

Write-Host "`n[+] OneDrive regional settings check completed!" -ForegroundColor Green
exit 0
