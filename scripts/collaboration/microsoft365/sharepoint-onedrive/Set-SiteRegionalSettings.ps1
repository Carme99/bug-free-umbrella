<#
.SYNOPSIS
    Checks and configures SharePoint Online site collection regional settings.

.DESCRIPTION
    This script audits and configures SharePoint Online site collection regional settings including:
    - Site time zone
    - Locale (affects date/number formatting)
    - Calendar type
    - Work week days and hours
    - Time format (12/24 hour)

.PARAMETER SiteUrl
    Specific site collection URL to configure.

.PARAMETER AllSites
    Apply settings to all site collections in the tenant.

.PARAMETER AuditOnly
    Only check settings without making changes (default behavior).

.PARAMETER Apply
    Apply the required settings to sites that don't match.

.PARAMETER TimeZone
    Target time zone ID (default: 2 for GMT/Dublin/Edinburgh/Lisbon/London).

.PARAMETER LocaleId
    Locale ID (default: 2057 for English United Kingdom).

.PARAMETER CalendarType
    Calendar type (default: 1 for Gregorian).

.PARAMETER WorkDayStartHour
    Work day start hour (default: 8).

.PARAMETER WorkDayEndHour
    Work day end hour (default: 17).

.PARAMETER FirstDayOfWeek
    First day of week (default: 1 for Monday).

.PARAMETER Time24
    Use 24-hour time format (default: $true).

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Set-SiteRegionalSettings.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/TeamSite" -AuditOnly
    Checks specific site's regional settings.

.EXAMPLE
    .\Set-SiteRegionalSettings.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/TeamSite" -Apply
    Applies required settings to specific site.

.EXAMPLE
    .\Set-SiteRegionalSettings.ps1 -AllSites -AuditOnly -ExportHTML
    Audits all sites and exports report.

.EXAMPLE
    .\Set-SiteRegionalSettings.ps1 -AllSites -Apply
    Applies settings to all site collections.

.NOTES
    Requires PnP.PowerShell module
    Requires SharePoint Administrator role
    Compatible with SharePoint Online (Microsoft 365)

    Time Zone IDs:
    - 2: (UTC+00:00) Dublin, Edinburgh, Lisbon, London
    - 13: (UTC) Coordinated Universal Time

    Locale IDs:
    - 2057: English (United Kingdom)
    - 1033: English (United States)
#>

[CmdletBinding(DefaultParameterSetName='AuditSingle')]
param(
    [Parameter(Mandatory=$false, ParameterSetName='AuditSingle')]
    [Parameter(Mandatory=$false, ParameterSetName='ApplySingle')]
    [string]$SiteUrl,

    [Parameter(Mandatory=$false, ParameterSetName='AuditAll')]
    [Parameter(Mandatory=$false, ParameterSetName='ApplyAll')]
    [switch]$AllSites,

    [Parameter(Mandatory=$false, ParameterSetName='AuditSingle')]
    [Parameter(Mandatory=$false, ParameterSetName='AuditAll')]
    [switch]$AuditOnly,

    [Parameter(Mandatory=$false, ParameterSetName='ApplySingle')]
    [Parameter(Mandatory=$false, ParameterSetName='ApplyAll')]
    [switch]$Apply,

    [Parameter(Mandatory=$false)]
    [int]$TimeZone = 2,  # GMT Standard Time

    [Parameter(Mandatory=$false)]
    [int]$LocaleId = 2057,  # en-GB

    [Parameter(Mandatory=$false)]
    [int]$CalendarType = 1,  # Gregorian

    [Parameter(Mandatory=$false)]
    [int]$WorkDayStartHour = 8,

    [Parameter(Mandatory=$false)]
    [int]$WorkDayEndHour = 17,

    [Parameter(Mandatory=$false)]
    [int]$FirstDayOfWeek = 1,  # Monday

    [Parameter(Mandatory=$false)]
    [bool]$Time24 = $true,

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

Write-Host "`n=== SharePoint Online Site Regional Settings ===" -ForegroundColor Cyan
Write-Host "Mode: $(if ($Apply) { 'APPLY SETTINGS' } else { 'AUDIT ONLY' })" -ForegroundColor $(if ($Apply) { 'Yellow' } else { 'Green' })
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

# Check for PnP PowerShell module
try {
    if (-not (Get-Module -Name PnP.PowerShell -ListAvailable)) {
        Write-Host "[-] PnP PowerShell module not found!" -ForegroundColor Red
        Write-Host "[!] Install with: Install-Module -Name PnP.PowerShell" -ForegroundColor Yellow
        exit 1
    }

    Import-Module PnP.PowerShell -ErrorAction Stop
}
catch {
    Write-Host "[-] Error loading PnP PowerShell module: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Required settings
$requiredSettings = @{
    TimeZone = $TimeZone
    LocaleId = $LocaleId
    CalendarType = $CalendarType
    WorkDayStartHour = $WorkDayStartHour
    WorkDayEndHour = $WorkDayEndHour
    FirstDayOfWeek = $FirstDayOfWeek
    Time24 = $Time24
}

Write-Host "[*] Required Settings:" -ForegroundColor Cyan
Write-Host "    Time Zone ID: $TimeZone (GMT Standard Time)" -ForegroundColor White
Write-Host "    Locale ID: $LocaleId (en-GB)" -ForegroundColor White
Write-Host "    Calendar Type: $CalendarType (Gregorian)" -ForegroundColor White
Write-Host "    Work Hours: $WorkDayStartHour:00 - $WorkDayEndHour:00" -ForegroundColor White
Write-Host "    First Day of Week: $FirstDayOfWeek (Monday)" -ForegroundColor White
Write-Host "    24-Hour Time: $Time24" -ForegroundColor White
Write-Host ""

# Get sites to process
$sitesToProcess = @()

if ($AllSites) {
    Write-Host "[*] Retrieving all site collections..." -ForegroundColor Cyan
    Write-Host "[!] You will be prompted to connect to SharePoint admin center..." -ForegroundColor Yellow

    try {
        # Connect to SharePoint admin (user will be prompted)
        $adminUrl = Read-Host "Enter your SharePoint admin URL (e.g., https://contoso-admin.sharepoint.com)"
        Connect-PnPOnline -Url $adminUrl -Interactive

        $allSites = Get-PnPTenantSite | Where-Object { $_.Template -notlike '*APP*' -and $_.Template -ne 'SRCHCEN#0' }
        Write-Host "[+] Found $($allSites.Count) site collection(s)" -ForegroundColor Green
        $sitesToProcess = $allSites
    }
    catch {
        Write-Host "[-] Error retrieving sites: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
elseif ($SiteUrl) {
    Write-Host "[*] Processing site: $SiteUrl..." -ForegroundColor Cyan
    $sitesToProcess = @([PSCustomObject]@{ Url = $SiteUrl; Title = "Specified Site" })
}
else {
    Write-Host "[-] Please specify either -SiteUrl or -AllSites" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Process sites
$results = @()
$compliantCount = 0
$nonCompliantCount = 0
$errorCount = 0

$i = 0
foreach ($site in $sitesToProcess) {
    $i++
    $siteUrl = if ($site.Url) { $site.Url } else { $site }
    $siteTitle = if ($site.Title) { $site.Title } else { "Site" }

    Write-Progress -Activity "Processing Sites" -Status "$i of $($sitesToProcess.Count): $siteTitle" -PercentComplete (($i / $sitesToProcess.Count) * 100)

    try {
        # Connect to the site
        Connect-PnPOnline -Url $siteUrl -Interactive -ErrorAction Stop

        # Get current regional settings
        $web = Get-PnPWeb -Includes RegionalSettings
        $regional = $web.RegionalSettings

        $currentTimeZone = $regional.TimeZone.Id
        $currentLocaleId = $regional.LocaleId
        $currentCalendarType = $regional.CalendarType
        $currentWorkDayStartHour = $regional.WorkDayStartHour
        $currentWorkDayEndHour = $regional.WorkDayEndHour
        $currentFirstDayOfWeek = $regional.FirstDayOfWeek
        $currentTime24 = $regional.Time24

        # Check compliance
        $issues = @()
        if ($currentTimeZone -ne $requiredSettings.TimeZone) {
            $issues += "Time zone: $currentTimeZone (expected: $($requiredSettings.TimeZone))"
        }
        if ($currentLocaleId -ne $requiredSettings.LocaleId) {
            $issues += "Locale: $currentLocaleId (expected: $($requiredSettings.LocaleId))"
        }
        if ($currentCalendarType -ne $requiredSettings.CalendarType) {
            $issues += "Calendar type mismatch"
        }
        if ($currentTime24 -ne $requiredSettings.Time24) {
            $issues += "Time format mismatch"
        }

        $isCompliant = $issues.Count -eq 0

        if ($isCompliant) {
            $compliantCount++
            $status = "Compliant"
        }
        else {
            $nonCompliantCount++
            $status = "Non-Compliant"
            Write-Host "[!] $siteTitle - Non-Compliant:" -ForegroundColor Yellow
            Write-Host "    URL: $siteUrl" -ForegroundColor Gray
            Write-Host "    Issues: $($issues -join ', ')" -ForegroundColor Gray
        }

        # Apply settings if requested
        $actionTaken = "None"
        if ($Apply -and -not $isCompliant) {
            try {
                Write-Host "    [*] Applying settings..." -ForegroundColor Cyan

                # Build settings hashtable
                $settings = @{
                    LocaleId = $requiredSettings.LocaleId
                    TimeZone = $requiredSettings.TimeZone
                }

                Set-PnPWeb -LocaleId $requiredSettings.LocaleId -ErrorAction Stop

                # Update regional settings via CSOM
                $ctx = Get-PnPContext
                $web = $ctx.Web
                $ctx.Load($web)
                $ctx.Load($web.RegionalSettings)
                $ctx.ExecuteQuery()

                $web.RegionalSettings.CalendarType = $requiredSettings.CalendarType
                $web.RegionalSettings.WorkDayStartHour = $requiredSettings.WorkDayStartHour
                $web.RegionalSettings.WorkDayEndHour = $requiredSettings.WorkDayEndHour
                $web.RegionalSettings.FirstDayOfWeek = $requiredSettings.FirstDayOfWeek
                $web.RegionalSettings.Time24 = $requiredSettings.Time24

                $web.RegionalSettings.Update()
                $ctx.ExecuteQuery()

                $actionTaken = "Settings Applied"
                $status = "Remediated"
                Write-Host "    [+] Settings applied successfully!" -ForegroundColor Green
            }
            catch {
                $actionTaken = "Error: $($_.Exception.Message)"
                $status = "Error"
                $errorCount++
                Write-Host "    [-] Error applying settings: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        $result = [PSCustomObject]@{
            SiteTitle = $siteTitle
            SiteUrl = $siteUrl
            CurrentTimeZone = $currentTimeZone
            RequiredTimeZone = $requiredSettings.TimeZone
            CurrentLocale = $currentLocaleId
            RequiredLocale = $requiredSettings.LocaleId
            CurrentCalendar = $currentCalendarType
            Time24Hour = $currentTime24
            WorkHours = "$currentWorkDayStartHour:00 - $currentWorkDayEndHour:00"
            Status = $status
            Issues = if ($issues.Count -gt 0) { $issues -join '; ' } else { 'None' }
            ActionTaken = $actionTaken
        }

        $results += $result
    }
    catch {
        $errorCount++
        Write-Host "[-] Error processing $siteTitle : $($_.Exception.Message)" -ForegroundColor Red

        $result = [PSCustomObject]@{
            SiteTitle = $siteTitle
            SiteUrl = $siteUrl
            CurrentTimeZone = "Error"
            RequiredTimeZone = $requiredSettings.TimeZone
            CurrentLocale = "Error"
            RequiredLocale = $requiredSettings.LocaleId
            CurrentCalendar = "Error"
            Time24Hour = "Error"
            WorkHours = "Error"
            Status = "Error"
            Issues = $_.Exception.Message
            ActionTaken = "N/A"
        }

        $results += $result
    }
}

Write-Progress -Activity "Processing Sites" -Completed

Write-Host ""

# Display summary
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Total Sites Processed: $($results.Count)" -ForegroundColor White
Write-Host "Compliant: $compliantCount" -ForegroundColor Green
Write-Host "Non-Compliant: $nonCompliantCount" -ForegroundColor Yellow
if ($Apply) {
    $remediatedCount = ($results | Where-Object { $_.Status -eq 'Remediated' }).Count
    Write-Host "Remediated: $remediatedCount" -ForegroundColor Green
}
Write-Host "Errors: $errorCount" -ForegroundColor Red
Write-Host ""

# Show non-compliant sites
if ($nonCompliantCount -gt 0 -and -not $Apply) {
    Write-Host "=== Non-Compliant Sites ===" -ForegroundColor Yellow
    $results | Where-Object { $_.Status -eq "Non-Compliant" } |
        Select-Object -First 10 SiteTitle, CurrentTimeZone, CurrentLocale, Issues |
        Format-Table -AutoSize

    if ($nonCompliantCount -gt 10) {
        Write-Host "[!] Showing first 10 of $nonCompliantCount non-compliant sites" -ForegroundColor Gray
    }
}

# Export results
if ($ExportHTML) {
    $htmlPath = "$ReportDir\SiteRegionalSettings_$timestamp.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>SharePoint Site Regional Settings Report - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #0078d4; }
        .summary { background-color: #f0f0f0; padding: 15px; border-radius: 5px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; font-size: 11px; }
        th { background-color: #0078d4; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .compliant { background-color: #107c10; color: white; padding: 3px 6px; border-radius: 3px; }
        .non-compliant { background-color: #ffaa44; color: white; padding: 3px 6px; border-radius: 3px; }
        .remediated { background-color: #0078d4; color: white; padding: 3px 6px; border-radius: 3px; }
        .error { background-color: #d13438; color: white; padding: 3px 6px; border-radius: 3px; }
    </style>
</head>
<body>
    <h1>SharePoint Site Regional Settings Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Mode:</strong> $(if ($Apply) { 'APPLY SETTINGS' } else { 'AUDIT ONLY' })<br>
        <strong>Total Sites:</strong> $($results.Count)<br>
        <strong>Compliant:</strong> $compliantCount<br>
        <strong>Non-Compliant:</strong> $nonCompliantCount<br>
        $(if ($Apply) { "<strong>Remediated:</strong> $(($results | Where-Object { $_.Status -eq 'Remediated' }).Count)<br>" })
        <strong>Errors:</strong> $errorCount
    </div>

    <h2>Site Details</h2>
    <table>
        <tr>
            <th>Site Title</th>
            <th>URL</th>
            <th>Current TZ</th>
            <th>Current Locale</th>
            <th>Status</th>
            <th>Issues</th>
            $(if ($Apply) { "<th>Action Taken</th>" })
        </tr>
"@

    foreach ($result in ($results | Sort-Object Status, SiteTitle)) {
        $statusClass = switch ($result.Status) {
            'Compliant' { 'compliant' }
            'Non-Compliant' { 'non-compliant' }
            'Remediated' { 'remediated' }
            'Error' { 'error' }
        }

        $html += @"
        <tr>
            <td>$($result.SiteTitle)</td>
            <td style="font-size:10px;">$($result.SiteUrl)</td>
            <td>$($result.CurrentTimeZone)</td>
            <td>$($result.CurrentLocale)</td>
            <td><span class="$statusClass">$($result.Status)</span></td>
            <td>$($result.Issues)</td>
            $(if ($Apply) { "<td>$($result.ActionTaken)</td>" })
        </tr>
"@
    }

    $html += "</table></body></html>"

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($ExportCSV) {
    $csvPath = "$ReportDir\SiteRegionalSettings_$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

Write-Host "`n[+] Site regional settings check completed!" -ForegroundColor Green

# Exit with appropriate code
if ($errorCount -gt 0) {
    exit 1
}
elseif ($nonCompliantCount -gt 0 -and -not $Apply) {
    exit 1
}
else {
    exit 0
}
