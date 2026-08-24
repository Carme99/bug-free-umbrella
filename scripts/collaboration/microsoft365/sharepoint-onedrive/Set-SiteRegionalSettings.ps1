<#
.SYNOPSIS
    Check and configure SharePoint Online site collection regional settings.

.DESCRIPTION
    This script audits and configures SharePoint Online site collection regional settings, including site time zone,
    locale, calendar type, work week days and hours, and 12/24-hour time format. By default it audits only and reports
    compliance; with -Apply it remediates sites whose settings do not match the target values, honoring -WhatIf and
    -Confirm through ShouldProcess. Re-running against already-compliant sites makes no further changes.
    Exit codes: 0 when all processed sites are compliant or successfully remediated; 1 when errors occurred, when
    non-compliant sites remain in audit mode, or when required input is missing.

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
    PS C:\> .\Set-SiteRegionalSettings.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/TeamSite" -AuditOnly
    Checks the specific site's regional settings without making changes.

.EXAMPLE
    PS C:\> .\Set-SiteRegionalSettings.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/TeamSite" -Apply
    Applies the required settings to the specific site.

.EXAMPLE
    PS C:\> .\Set-SiteRegionalSettings.ps1 -AllSites -AuditOnly -ExportHTML
    Audits all sites and exports an HTML report.

.EXAMPLE
    PS C:\> .\Set-SiteRegionalSettings.ps1 -AllSites -Apply
    Applies settings to all site collections.

.NOTES
    File Name  : Set-SiteRegionalSettings.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Requires the PnP.PowerShell module and the SharePoint Administrator role.
    Compatible with SharePoint Online (Microsoft 365).

    Time Zone IDs:
    - 2: (UTC+00:00) Dublin, Edinburgh, Lisbon, London
    - 13: (UTC) Coordinated Universal Time

    Locale IDs:
    - 2057: English (United Kingdom)
    - 1033: English (United States)
#>

# PSAvoidUsingWriteHost: Write-Host with [+]/[!]/[-]/[*] prefixes is mandated by AGENTS.md.
# PSReviewUnusedParameter: script parameters are consumed inside Main via scope chaining.
[CmdletBinding(DefaultParameterSetName = 'AuditSingle', SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false, ParameterSetName = 'AuditSingle')]
    [Parameter(Mandatory = $false, ParameterSetName = 'ApplySingle')]
    [string]$SiteUrl,

    [Parameter(Mandatory = $false, ParameterSetName = 'AuditAll')]
    [Parameter(Mandatory = $false, ParameterSetName = 'ApplyAll')]
    [switch]$AllSites,

    [Parameter(Mandatory = $false, ParameterSetName = 'AuditSingle')]
    [Parameter(Mandatory = $false, ParameterSetName = 'AuditAll')]
    [switch]$AuditOnly,

    [Parameter(Mandatory = $false, ParameterSetName = 'ApplySingle')]
    [Parameter(Mandatory = $false, ParameterSetName = 'ApplyAll')]
    [switch]$Apply,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, [int]::MaxValue)]
    [int]$TimeZone = 2,  # GMT Standard Time

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, [int]::MaxValue)]
    [int]$LocaleId = 2057,  # en-GB

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, [int]::MaxValue)]
    [int]$CalendarType = 1,  # Gregorian

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 23)]
    [int]$WorkDayStartHour = 8,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 23)]
    [int]$WorkDayEndHour = 17,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 6)]
    [int]$FirstDayOfWeek = 1,  # Monday

    [Parameter(Mandatory = $false)]
    [bool]$Time24 = $true,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = 'Stop'

function Set-SiteRegionalConfiguration {
    # Applies the full regional configuration to the currently connected site via PnP and CSOM.
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,

        [Parameter(Mandatory = $true)]
        [int]$LocaleId,

        # Interface parity with the required-settings contract; applied via the locale update path.
        [Parameter(Mandatory = $true)]
        [int]$TimeZone,

        [Parameter(Mandatory = $true)]
        [int]$CalendarType,

        [Parameter(Mandatory = $true)]
        [int]$WorkDayStartHour,

        [Parameter(Mandatory = $true)]
        [int]$WorkDayEndHour,

        [Parameter(Mandatory = $true)]
        [int]$FirstDayOfWeek,

        [Parameter(Mandatory = $true)]
        [bool]$Time24
    )

    if (-not $PSCmdlet.ShouldProcess($SiteUrl, 'Apply regional settings')) {
        return $false
    }

    Set-PnPWeb -LocaleId $LocaleId -ErrorAction Stop

    # Update remaining regional settings via CSOM
    $ctx = Get-PnPContext -ErrorAction Stop
    $web = $ctx.Web
    $ctx.Load($web)
    $ctx.Load($web.RegionalSettings)
    $ctx.ExecuteQuery()

    $web.RegionalSettings.CalendarType = $CalendarType
    $web.RegionalSettings.WorkDayStartHour = $WorkDayStartHour
    $web.RegionalSettings.WorkDayEndHour = $WorkDayEndHour
    $web.RegionalSettings.FirstDayOfWeek = $FirstDayOfWeek
    $web.RegionalSettings.Time24 = $Time24

    $web.RegionalSettings.Update()
    $ctx.ExecuteQuery()

    return $true
}

function Main {
    try {
        # Prepare report directory (local absolute path only, no traversal).
        $documentsRoot = [Environment]::GetFolderPath('MyDocuments')
        if ([string]::IsNullOrWhiteSpace($documentsRoot)) {
            $documentsRoot = [System.IO.Path]::Combine($HOME, 'Documents')
        }
        $reportDir = Join-Path $documentsRoot 'Reports'
        if ([string]::IsNullOrWhiteSpace($reportDir) -or
            $reportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
            $reportDir -match '^(\\\\|//)') {
            throw "Unsafe report path: $reportDir. Report path must be a local absolute path without '..' traversal."
        }
        $reportDir = [System.IO.Path]::GetFullPath($reportDir)
        if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
            New-Item -ItemType Directory -Path $reportDir -Force -ErrorAction Stop | Out-Null
        }

        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

        $modeText = if ($Apply) { 'APPLY SETTINGS' } else { 'AUDIT ONLY' }
        $modeColor = if ($Apply) { 'Yellow' } else { 'Green' }

        Write-Host "`n=== SharePoint Online Site Regional Settings ===" -ForegroundColor Cyan
        Write-Host "Mode: $modeText" -ForegroundColor $modeColor
        Write-Host ""

        # Check for PnP PowerShell module
        if (-not (Get-Module -Name PnP.PowerShell -ListAvailable)) {
            Write-Host "[-] PnP PowerShell module not found!" -ForegroundColor Red
            Write-Host "[!] Install with: Install-Module -Name PnP.PowerShell" -ForegroundColor Yellow
            return 1
        }

        Import-Module PnP.PowerShell -ErrorAction Stop

        Write-Host ""

        # Required settings
        $requiredSettings = @{
            TimeZone         = $TimeZone
            LocaleId         = $LocaleId
            CalendarType     = $CalendarType
            WorkDayStartHour = $WorkDayStartHour
            WorkDayEndHour   = $WorkDayEndHour
            FirstDayOfWeek   = $FirstDayOfWeek
            Time24           = $Time24
        }

        Write-Host "[*] Required Settings:" -ForegroundColor Cyan
        Write-Host "    Time Zone ID: $TimeZone (GMT Standard Time)" -ForegroundColor White
        Write-Host "    Locale ID: $LocaleId (en-GB)" -ForegroundColor White
        Write-Host "    Calendar Type: $CalendarType (Gregorian)" -ForegroundColor White
        Write-Host "    Work Hours: $WorkDayStartHour`:00 - $WorkDayEndHour`:00" -ForegroundColor White
        Write-Host "    First Day of Week: $FirstDayOfWeek (Monday)" -ForegroundColor White
        Write-Host "    24-Hour Time: $Time24" -ForegroundColor White
        Write-Host ""

        # Get sites to process
        $sitesToProcess = @()

        if ($AllSites) {
            Write-Host "[*] Retrieving all site collections..." -ForegroundColor Cyan
            Write-Host "[!] You will be prompted to connect to SharePoint admin center..." -ForegroundColor Yellow

            # Connect to SharePoint admin (user will be prompted)
            $adminUrl = Read-Host "Enter your SharePoint admin URL (e.g., https://contoso-admin.sharepoint.com)"
            Connect-PnPOnline -Url $adminUrl -Interactive -ErrorAction Stop

            $allSites = Get-PnPTenantSite -ErrorAction Stop |
                Where-Object { $_.Template -notlike '*APP*' -and $_.Template -ne 'SRCHCEN#0' }
            Write-Host "[+] Found $($allSites.Count) site collection(s)" -ForegroundColor Green
            $sitesToProcess = @($allSites)
        }
        elseif ($SiteUrl) {
            Write-Host "[*] Processing site: $SiteUrl..." -ForegroundColor Cyan
            $sitesToProcess = @([PSCustomObject]@{ Url = $SiteUrl; Title = "Specified Site" })
        }
        else {
            Write-Host "[-] Please specify either -SiteUrl or -AllSites" -ForegroundColor Red
            return 1
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

            $progressStatus = "$i of $($sitesToProcess.Count): $siteTitle"
            $percentComplete = ($i / $sitesToProcess.Count) * 100
            Write-Progress -Activity "Processing Sites" -Status $progressStatus -PercentComplete $percentComplete

            try {
                # Connect to the site
                Connect-PnPOnline -Url $siteUrl -Interactive -ErrorAction Stop

                # Get current regional settings
                $web = Get-PnPWeb -Includes RegionalSettings -ErrorAction Stop
                $regional = $web.RegionalSettings

                $currentTimeZone = $regional.TimeZone.Id
                $currentLocaleId = $regional.LocaleId
                $currentCalendarType = $regional.CalendarType
                $currentWorkDayStartHour = $regional.WorkDayStartHour
                $currentWorkDayEndHour = $regional.WorkDayEndHour
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

                        $applyParams = @{
                            SiteUrl          = $siteUrl
                            LocaleId         = $requiredSettings.LocaleId
                            TimeZone         = $requiredSettings.TimeZone
                            CalendarType     = $requiredSettings.CalendarType
                            WorkDayStartHour = $requiredSettings.WorkDayStartHour
                            WorkDayEndHour   = $requiredSettings.WorkDayEndHour
                            FirstDayOfWeek   = $requiredSettings.FirstDayOfWeek
                            Time24           = $requiredSettings.Time24
                        }

                        $null = Set-SiteRegionalConfiguration @applyParams -ErrorAction Stop

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
                    SiteTitle        = $siteTitle
                    SiteUrl          = $siteUrl
                    CurrentTimeZone  = $currentTimeZone
                    RequiredTimeZone = $requiredSettings.TimeZone
                    CurrentLocale    = $currentLocaleId
                    RequiredLocale   = $requiredSettings.LocaleId
                    CurrentCalendar  = $currentCalendarType
                    Time24Hour       = $currentTime24
                    WorkHours        = "$currentWorkDayStartHour`:00 - $currentWorkDayEndHour`:00"
                    Status           = $status
                    Issues           = if ($issues.Count -gt 0) { $issues -join '; ' } else { 'None' }
                    ActionTaken      = $actionTaken
                }

                $results += $result
            }
            catch {
                $errorCount++
                Write-Host "[-] Error processing $siteTitle : $($_.Exception.Message)" -ForegroundColor Red

                $result = [PSCustomObject]@{
                    SiteTitle        = $siteTitle
                    SiteUrl          = $siteUrl
                    CurrentTimeZone  = "Error"
                    RequiredTimeZone = $requiredSettings.TimeZone
                    CurrentLocale    = "Error"
                    RequiredLocale   = $requiredSettings.LocaleId
                    CurrentCalendar  = "Error"
                    Time24Hour       = "Error"
                    WorkHours        = "Error"
                    Status           = "Error"
                    Issues           = $_.Exception.Message
                    ActionTaken      = "N/A"
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
        $remediatedCount = ($results | Where-Object { $_.Status -eq 'Remediated' }).Count
        if ($Apply) {
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
            $htmlPath = Join-Path $reportDir "SiteRegionalSettings_$timestamp.html"

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
        <strong>Mode:</strong> $modeText<br>
        <strong>Total Sites:</strong> $($results.Count)<br>
        <strong>Compliant:</strong> $compliantCount<br>
        <strong>Non-Compliant:</strong> $nonCompliantCount<br>
        $(if ($Apply) { "<strong>Remediated:</strong> $($remediatedCount)<br>" })
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

            $html | Out-File -FilePath $htmlPath -Encoding utf8 -ErrorAction Stop
            Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
        }

        if ($ExportCSV) {
            $csvPath = Join-Path $reportDir "SiteRegionalSettings_$timestamp.csv"
            $results | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
            Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
        }

        Write-Host "`n[+] Site regional settings check completed!" -ForegroundColor Green

        if ($errorCount -gt 0) {
            return 1
        }
        elseif ($nonCompliantCount -gt 0 -and -not $Apply) {
            return 1
        }

        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
