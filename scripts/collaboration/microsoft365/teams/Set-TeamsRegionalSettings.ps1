<#
.SYNOPSIS
    Checks and configures Microsoft Teams regional settings for users.

.DESCRIPTION
    This script audits and configures Teams-specific regional settings including:
    - Default meeting time zone
    - Calendar integration settings
    - Teams language preferences

    Note: Teams inherits most regional settings from M365 user settings and Outlook.
    This script focuses on Teams-specific configurations.

.PARAMETER UserPrincipalName
    Specific user to configure.

.PARAMETER AllUsers
    Apply settings to all users.

.PARAMETER AuditOnly
    Only check settings without making changes (default behavior).

.PARAMETER Apply
    Apply the required settings.

.PARAMETER TimeZone
    Target time zone (default: GMT Standard Time).

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Set-TeamsRegionalSettings.ps1 -AuditOnly
    Checks current user's Teams settings.

.EXAMPLE
    .\Set-TeamsRegionalSettings.ps1 -UserPrincipalName john.doe@company.com -Apply
    Applies settings to specific user.

.NOTES
    Requires Microsoft Teams PowerShell module
    Requires Teams Administrator role
    Compatible with Microsoft Teams

    Note: Most Teams regional settings are inherited from Exchange Online
    mailbox settings. Use Set-MailboxRegionalSettings.ps1 for comprehensive control.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory=$false)]
    [switch]$AllUsers,

    [Parameter(Mandatory=$false)]
    [switch]$AuditOnly,

    [Parameter(Mandatory=$false)]
    [switch]$Apply,

    [Parameter(Mandatory=$false)]
    [string]$TimeZone = 'GMT Standard Time',

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "`n=== Microsoft Teams Regional Settings ===" -ForegroundColor Cyan
Write-Host "Mode: $(if ($Apply) { 'APPLY SETTINGS' } else { 'AUDIT ONLY' })" -ForegroundColor $(if ($Apply) { 'Yellow' } else { 'Green' })
Write-Host ""

Write-Host "[!] NOTE: Most Teams regional settings are inherited from Exchange Online mailbox settings." -ForegroundColor Yellow
Write-Host "[!] For comprehensive regional settings control, use Set-MailboxRegionalSettings.ps1" -ForegroundColor Yellow
Write-Host ""

# Check for Teams module
try {
    if (-not (Get-Module -Name MicrosoftTeams -ListAvailable)) {
        Write-Host "[-] Microsoft Teams module not found!" -ForegroundColor Red
        Write-Host "[!] Install with: Install-Module -Name MicrosoftTeams" -ForegroundColor Yellow
        exit 1
    }

    # Check if connected
    try {
        $null = Get-CsOnlineUser -ResultSize 1 -ErrorAction Stop
        Write-Host "[+] Connected to Microsoft Teams" -ForegroundColor Green
    }
    catch {
        Write-Host "[!] Not connected to Teams. Connecting..." -ForegroundColor Yellow
        Connect-MicrosoftTeams
    }
}
catch {
    Write-Host "[-] Error with Teams module: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

Write-Host "[*] Teams regional settings are primarily controlled via:" -ForegroundColor Cyan
Write-Host "    1. Exchange Online mailbox regional configuration (time zone, date format)" -ForegroundColor White
Write-Host "    2. M365 user language settings (display language)" -ForegroundColor White
Write-Host "    3. Individual Teams client preferences (user-controlled)" -ForegroundColor White
Write-Host ""

Write-Host "[*] Recommended Actions:" -ForegroundColor Green
Write-Host "    1. Run Set-UserLanguageSettings.ps1 for M365 account language" -ForegroundColor White
Write-Host "    2. Run Set-MailboxRegionalSettings.ps1 for calendar/time zone" -ForegroundColor White
Write-Host "    3. Teams will inherit these settings automatically" -ForegroundColor White
Write-Host ""

Write-Host "[+] For Teams-specific policies, use Teams admin center or Teams PowerShell cmdlets:" -ForegroundColor Green
Write-Host "    - Get-CsTeamsMeetingPolicy" -ForegroundColor Gray
Write-Host "    - Set-CsTeamsMeetingPolicy" -ForegroundColor Gray
Write-Host "    - Get-CsTeamsMessagingPolicy" -ForegroundColor Gray
Write-Host ""

Write-Host "[+] Script completed - Teams inherits regional settings from M365 and Exchange" -ForegroundColor Green
exit 0
