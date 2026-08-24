<#
.SYNOPSIS
    Checks and configures Power Platform environment regional settings.

.DESCRIPTION
    Audits Power Platform environment regional settings (base language and currency) against the
    required baseline supplied via -BaseLanguage and -CurrencyCode, reporting each environment as
    compliant or non-compliant. By default the script is audit-only and makes no changes; with
    -Apply it walks the remediation path for non-compliant environments behind a ShouldProcess
    gate, so -WhatIf/-Confirm are honored (regional settings are set at environment creation
    time, so the apply path reports the supported remediation guidance rather than mutating the
    tenant). Results can be exported to HTML or CSV; the script is idempotent and safe to re-run.
    Returns exit code 0 on success and exit code 1 on failure.

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
    PS C:\> .\Set-PowerPlatformRegionalSettings.ps1 -EnvironmentName "Default-xxxxx" -AuditOnly
    Checks the specific environment's settings without making changes.

.EXAMPLE
    PS C:\> .\Set-PowerPlatformRegionalSettings.ps1 -AllEnvironments -Apply
    Applies the required settings baseline across all environments (honors -WhatIf/-Confirm).

.NOTES
    File Name   : Set-PowerPlatformRegionalSettings.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23

    Requires the Microsoft.PowerApps.Administration.PowerShell module.
    Requires the Power Platform Administrator role.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$EnvironmentName,

    [Parameter(Mandatory = $false)]
    [switch]$AllEnvironments,

    [Parameter(Mandatory = $false)]
    [switch]$AuditOnly,

    [Parameter(Mandatory = $false)]
    [switch]$Apply,

    [Parameter(Mandatory = $false)]
    [int]$BaseLanguage = 2057,  # English UK

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$CurrencyCode = 'GBP',

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
    [CmdletBinding(SupportsShouldProcess)]
    param()

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
        Write-Host "=== Power Platform Environment Regional Settings ===" -ForegroundColor Cyan
        if ($Apply) {
            Write-Host "[!] Mode: APPLY SETTINGS" -ForegroundColor Yellow
        }
        else {
            Write-Host "[+] Mode: AUDIT ONLY" -ForegroundColor Green
        }
        Write-Host ""

        # Check for Power Platform module
        try {
            if (-not (Get-Module -Name Microsoft.PowerApps.Administration.PowerShell -ListAvailable)) {
                throw ("Microsoft.PowerApps.Administration.PowerShell module not found. Install with: " +
                    "Install-Module -Name Microsoft.PowerApps.Administration.PowerShell")
            }

            Import-Module Microsoft.PowerApps.Administration.PowerShell -ErrorAction Stop

            # Add to Power Apps
            Add-PowerAppsAccount -ErrorAction Stop
            Write-Host "[+] Connected to Power Platform" -ForegroundColor Green
        }
        catch {
            Write-Host "[-] Error with Power Platform module: $($_.Exception.Message)" -ForegroundColor Red
            return 1
        }

        Write-Host ""

        # Get environments
        $environments = @()

        if ($AllEnvironments) {
            Write-Host "[*] Retrieving all environments..." -ForegroundColor Cyan
            $environments = @(Get-AdminPowerAppEnvironment -ErrorAction Stop)
            Write-Host "[+] Found $($environments.Count) environment(s)" -ForegroundColor Green
        }
        elseif ($EnvironmentName) {
            Write-Host "[*] Retrieving environment: $EnvironmentName..." -ForegroundColor Cyan
            $env = Get-AdminPowerAppEnvironment -EnvironmentName $EnvironmentName -ErrorAction Stop
            $environments = @($env)
            Write-Host "[+] Found environment: $($env.DisplayName)" -ForegroundColor Green
        }
        else {
            Write-Host "[-] Please specify either -EnvironmentName or -AllEnvironments" -ForegroundColor Red
            return 1
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
            }
            else { "Not Set" }

            $currentCurrency = if ($props.linkedEnvironmentMetadata.currency) {
                $props.linkedEnvironmentMetadata.currency.code
            }
            else { "Not Set" }

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
                if ($PSCmdlet.ShouldProcess($env.DisplayName, 'Apply regional settings')) {
                    $creationTimeNote = 'Regional settings for Power Platform environments are set at creation time'
                    $recreateNote = 'To change: Recreate environment with correct settings or contact support'
                    Write-Host "    [!] $creationTimeNote" -ForegroundColor Yellow
                    Write-Host "    [!] $recreateNote" -ForegroundColor Yellow
                }
            }

            $result = [PSCustomObject]@{
                EnvironmentName = $env.DisplayName
                EnvironmentId   = $env.EnvironmentName
                BaseLanguage    = $currentLanguage
                RequiredLanguage = $BaseLanguage
                Currency        = $currentCurrency
                RequiredCurrency = $CurrencyCode
                Status          = $status
                Issues          = if ($issues.Count -gt 0) { $issues -join '; ' } else { 'None' }
            }

            $results += $result
        }

        Write-Host ""
        Write-Host "=== Summary ===" -ForegroundColor Cyan
        Write-Host "[*] Total Environments: $($results.Count)" -ForegroundColor Cyan
        Write-Host "[+] Compliant: $compliantCount" -ForegroundColor Green
        if ($nonCompliantCount -gt 0) {
            Write-Host "[!] Non-Compliant: $nonCompliantCount" -ForegroundColor Yellow
        }
        else {
            Write-Host "[+] Non-Compliant: $nonCompliantCount" -ForegroundColor Green
        }
        Write-Host ""

        if ($ExportHTML) {
            $htmlPath = Join-Path $reportDir "PowerPlatformRegionalSettings_$timestamp.html"

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
            Write-ReportTextFile -Path $htmlPath -Content $html
            Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
        }

        if ($ExportCSV) {
            $csvPath = Join-Path $reportDir "PowerPlatformRegionalSettings_$timestamp.csv"
            $results | Export-Csv -Path $csvPath -NoTypeInformation
            Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
        }

        Write-Host "`n[+] Power Platform regional settings check completed!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
