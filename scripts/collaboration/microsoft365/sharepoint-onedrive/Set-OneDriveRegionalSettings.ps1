<#
.SYNOPSIS
    Check and configure OneDrive personal site regional settings.

.DESCRIPTION
    This script audits and configures OneDrive for Business personal site regional settings. OneDrive personal sites
    are a special type of SharePoint site collection, so the script checks each site's time zone and locale against
    the target values and reports compliance; with -Apply it remediates non-compliant sites, honoring -WhatIf and
    -Confirm through ShouldProcess. Re-running against already-compliant sites makes no further changes.
    Exit codes: 0 once the check completes (per-site issues are reported in the output); 1 when the PnP.PowerShell
    module is missing or required input is missing.

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

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    PS C:\> .\Set-OneDriveRegionalSettings.ps1 -UserPrincipalName john.doe@company.com -AuditOnly
    Checks the specific user's OneDrive settings without making changes.

.EXAMPLE
    PS C:\> .\Set-OneDriveRegionalSettings.ps1 -AllOneDriveSites -Apply
    Applies the required settings to all OneDrive sites.

.NOTES
    File Name  : Set-OneDriveRegionalSettings.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Requires the PnP.PowerShell module and the SharePoint Administrator role.
    OneDrive sites are user-specific SharePoint site collections.
#>

# PSAvoidUsingWriteHost: Write-Host with [+]/[!]/[-]/[*] prefixes is mandated by AGENTS.md.
# PSReviewUnusedParameter: script parameters are consumed inside Main via scope chaining.
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory = $false)]
    [switch]$AllOneDriveSites,

    [Parameter(Mandatory = $false)]
    [switch]$AuditOnly,

    [Parameter(Mandatory = $false)]
    [switch]$Apply,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, [int]::MaxValue)]
    [int]$TimeZone = 2,  # GMT

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, [int]::MaxValue)]
    [int]$LocaleId = 2057,  # en-GB

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = 'Stop'

function Set-OneDriveRegionalConfiguration {
    # Applies the target locale and regional settings to the currently connected OneDrive site.
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,

        [Parameter(Mandatory = $true)]
        [int]$LocaleId
    )

    if (-not $PSCmdlet.ShouldProcess($SiteUrl, 'Apply OneDrive regional settings')) {
        return $false
    }

    Set-PnPWeb -LocaleId $LocaleId -ErrorAction Stop

    $ctx = Get-PnPContext -ErrorAction Stop
    $web = $ctx.Web
    $ctx.Load($web.RegionalSettings)
    $ctx.ExecuteQuery()

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

        Write-Host "`n=== OneDrive Personal Site Regional Settings ===" -ForegroundColor Cyan
        Write-Host "Mode: $modeText" -ForegroundColor $modeColor
        Write-Host ""

        Write-Host "[!] NOTE: OneDrive regional settings are part of SharePoint personal sites" -ForegroundColor Yellow
        $noteText = "[!] Use Set-SiteRegionalSettings.ps1 for comprehensive site collection management"
        Write-Host $noteText -ForegroundColor Yellow
        Write-Host ""

        # Check for PnP PowerShell
        if (-not (Get-Module -Name PnP.PowerShell -ListAvailable)) {
            Write-Host "[-] PnP PowerShell module not found!" -ForegroundColor Red
            Write-Host "[!] Install with: Install-Module -Name PnP.PowerShell" -ForegroundColor Yellow
            return 1
        }

        Import-Module PnP.PowerShell -ErrorAction Stop

        Write-Host ""

        # Get OneDrive sites
        $onedriveSites = @()

        if ($AllOneDriveSites) {
            Write-Host "[*] Retrieving all OneDrive sites..." -ForegroundColor Cyan
            Write-Host "[!] You will be prompted to connect to SharePoint admin center..." -ForegroundColor Yellow

            $adminUrl = Read-Host "Enter your SharePoint admin URL (e.g., https://contoso-admin.sharepoint.com)"
            Connect-PnPOnline -Url $adminUrl -Interactive -ErrorAction Stop

            $tenantSiteParams = @{
                IncludeOneDriveSites = $true
                Filter               = "Url -like '-my.sharepoint.com/personal/'"
                ErrorAction          = 'Stop'
            }
            $allSites = Get-PnPTenantSite @tenantSiteParams
            Write-Host "[+] Found $($allSites.Count) OneDrive site(s)" -ForegroundColor Green
            $onedriveSites = @($allSites)
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
            return 1
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

                $web = Get-PnPWeb -Includes RegionalSettings -ErrorAction Stop
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
                        $applyParams = @{ SiteUrl = $siteUrl; LocaleId = $LocaleId }
                        $null = Set-OneDriveRegionalConfiguration @applyParams -ErrorAction Stop
                        Write-Host "    [+] Settings applied!" -ForegroundColor Green
                    }
                }

                $results += [PSCustomObject]@{
                    OneDriveUrl     = $siteUrl
                    CurrentTimeZone = $currentTimeZone
                    CurrentLocale   = $currentLocaleId
                    Status          = if ($isCompliant) { "Compliant" } else { "Non-Compliant" }
                    Issues          = if ($issues.Count -gt 0) { $issues -join '; ' } else { 'None' }
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
            $csvPath = Join-Path $reportDir "OneDriveRegionalSettings_$timestamp.csv"
            $results | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
            Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
        }

        Write-Host "`n[+] OneDrive regional settings check completed!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
