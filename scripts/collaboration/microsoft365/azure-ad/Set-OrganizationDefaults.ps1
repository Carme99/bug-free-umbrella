<#
.SYNOPSIS
    Audits and configures the organization-wide PreferredLanguage setting in Microsoft 365.

.DESCRIPTION
    This script audits and configures the organization-level PreferredLanguage setting for the
    Microsoft 365 organization (the only organization-level default this script manages).

    Note: There is no organization-level "default usage location" or "preferred data location"
    default. UsageLocation and PreferredDataLocation are per-user attributes and must be set on
    individual user objects (for example, Update-MgUser -UsageLocation). Existing users must be
    configured separately using Set-UserLanguageSettings.ps1 and Set-MailboxRegionalSettings.ps1

.PARAMETER UsageLocation
    Usage location country code (default: GB for United Kingdom). Used for reference only -
    UsageLocation is a per-user attribute and cannot be set at the organization level.

.PARAMETER PreferredLanguage
    Default preferred language (default: en-GB).

.PARAMETER AuditOnly
    Only check current settings without making changes.

.PARAMETER Apply
    Apply the required settings.

.PARAMETER ExportHTML
    Export results to HTML report.

.EXAMPLE
    .\Set-OrganizationDefaults.ps1 -AuditOnly
    Checks current organization default settings.

.EXAMPLE
    .\Set-OrganizationDefaults.ps1 -Apply
    Applies organization default settings.

.NOTES
    Requires Microsoft Graph PowerShell module
    Requires Global Administrator role
    Only the organization PreferredLanguage setting is managed; usage location is a per-user attribute
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$UsageLocation = 'GB',

    [Parameter(Mandatory=$false)]
    [string]$PreferredLanguage = 'en-GB',

    [Parameter(Mandatory=$false)]
    [switch]$AuditOnly,

    [Parameter(Mandatory=$false)]
    [switch]$Apply,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML
)

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "`n=== Microsoft 365 Organization Default Settings ===" -ForegroundColor Cyan
Write-Host "Mode: $(if ($Apply) { 'APPLY SETTINGS' } else { 'AUDIT ONLY' })" -ForegroundColor $(if ($Apply) { 'Yellow' } else { 'Green' })
Write-Host ""

# Check for Microsoft Graph module
try {
    if (-not (Get-Module -Name Microsoft.Graph.Identity.DirectoryManagement -ListAvailable)) {
        Write-Host "[-] Microsoft Graph module not found!" -ForegroundColor Red
        Write-Host "[!] Install with: Install-Module -Name Microsoft.Graph" -ForegroundColor Yellow
        exit 1
    }

    Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop

    $context = Get-MgContext
    if (-not $context) {
        Write-Host "[!] Not connected to Microsoft Graph. Connecting..." -ForegroundColor Yellow
        Connect-MgGraph -Scopes "Organization.ReadWrite.All" -NoWelcome
        $context = Get-MgContext
    }

    Write-Host "[+] Connected to Microsoft Graph" -ForegroundColor Green
    Write-Host "    Account: $($context.Account)" -ForegroundColor Gray
}
catch {
    Write-Host "[-] Error connecting to Microsoft Graph: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Get organization settings
Write-Host "[*] Retrieving organization settings..." -ForegroundColor Cyan

try {
    $org = Get-MgOrganization
    $orgSettings = $org[0]

    Write-Host "[+] Organization: $($orgSettings.DisplayName)" -ForegroundColor Green
    Write-Host ""

    Write-Host "=== Current Organization Settings ===" -ForegroundColor Cyan
    Write-Host "Display Name: $($orgSettings.DisplayName)" -ForegroundColor White
    Write-Host "Country/Region: $($orgSettings.CountryLetterCode)" -ForegroundColor White
    Write-Host "Preferred Language: $($orgSettings.PreferredLanguage)" -ForegroundColor White
    Write-Host ""

    # Expected settings
    Write-Host "=== Expected Organization Settings ===" -ForegroundColor Cyan
    Write-Host "Preferred Language: $PreferredLanguage" -ForegroundColor White
    Write-Host "(Usage location is a per-user attribute and is not managed at the organization level)" -ForegroundColor Gray
    Write-Host ""

    # Check compliance
    $issues = @()
    if ($orgSettings.PreferredLanguage -ne $PreferredLanguage) {
        $issues += "Preferred Language: $($orgSettings.PreferredLanguage) (expected: $PreferredLanguage)"
    }

    $isCompliant = $issues.Count -eq 0

    if ($isCompliant) {
        Write-Host "[+] Organization settings are compliant" -ForegroundColor Green
    }
    else {
        Write-Host "[!] Organization settings non-compliant:" -ForegroundColor Yellow
        foreach ($issue in $issues) {
            Write-Host "    - $issue" -ForegroundColor Yellow
        }
    }

    Write-Host ""

    # Apply if requested
    if ($Apply -and -not $isCompliant) {
        Write-Host "[*] Applying organization settings..." -ForegroundColor Cyan

        try {
            Update-MgOrganization -OrganizationId $orgSettings.Id -PreferredLanguage $PreferredLanguage -ErrorAction Stop
            Write-Host "[+] Organization settings updated successfully!" -ForegroundColor Green
        }
        catch {
            Write-Host "[-] Error updating organization settings: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "=== Important Notes ===" -ForegroundColor Yellow
    Write-Host "[!] Organization-level settings affect NEW users only" -ForegroundColor Yellow
    Write-Host "[!] To configure existing users, use:" -ForegroundColor Yellow
    Write-Host "    - Set-UserLanguageSettings.ps1 for M365 account settings" -ForegroundColor White
    Write-Host "    - Set-MailboxRegionalSettings.ps1 for Exchange mailbox settings" -ForegroundColor White
    Write-Host "    - proactive-remediations/region-language-settings for client devices" -ForegroundColor White
    Write-Host ""

    Write-Host "[!] Usage Location must be set per-user for license assignment:" -ForegroundColor Yellow
    Write-Host "    Get-MgUser -All | Update-MgUser -UsageLocation '$UsageLocation'" -ForegroundColor White
    Write-Host ""
}
catch {
    Write-Host "[-] Error retrieving organization settings: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "[+] Organization defaults check completed!" -ForegroundColor Green
exit 0
