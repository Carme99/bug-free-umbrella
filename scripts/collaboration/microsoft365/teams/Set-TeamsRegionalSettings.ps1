<#
.SYNOPSIS
    Check Microsoft Teams regional settings prerequisites and report inheritance guidance.

.DESCRIPTION
    This script verifies that the MicrosoftTeams PowerShell module is installed and that a Teams connection can be
    established, connecting interactively when needed. Teams inherits most regional settings from the Exchange Online
    mailbox regional configuration and M365 user language settings, so the script makes no configuration changes and
    instead prints recommended follow-up actions using companion scripts.
    Exit codes: 0 when the module and connection checks complete; 1 when the module is missing or the connection
    cannot be established.

.PARAMETER UserPrincipalName
    Specific user to configure. Reserved for context; the current release reports tenant-wide guidance only.

.PARAMETER AllUsers
    Apply settings to all users. Reserved for context; no per-user changes are made by this script.

.PARAMETER AuditOnly
    Only check settings without making changes (default behavior).

.PARAMETER Apply
    Apply the required settings. Reserved for context; no configuration changes are made by this script.

.PARAMETER TimeZone
    Target time zone (default: GMT Standard Time). Reported for reference; not applied to any user.

.PARAMETER ExportHTML
    Export results to HTML report. Reserved for context; this script produces console output only.

.PARAMETER ExportCSV
    Export results to CSV file. Reserved for context; this script produces console output only.

.EXAMPLE
    PS C:\> .\Set-TeamsRegionalSettings.ps1 -AuditOnly
    Checks the Teams module and connection state and prints inheritance guidance.

.EXAMPLE
    PS C:\> .\Set-TeamsRegionalSettings.ps1 -UserPrincipalName john.doe@company.com -Apply
    Runs the same check in a per-user context without making changes.

.NOTES
    File Name  : Set-TeamsRegionalSettings.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Requires the MicrosoftTeams module and the Teams Administrator role.
    Most Teams regional settings are inherited from Exchange Online mailbox settings;
    use Set-MailboxRegionalSettings.ps1 for comprehensive control.
#>

# PSAvoidUsingWriteHost: Write-Host with [+]/[!]/[-]/[*] prefixes is mandated by AGENTS.md.
# PSReviewUnusedParameter: reserved-context parameters preserved per relaunch naming rules.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory = $false)]
    [switch]$AllUsers,

    [Parameter(Mandatory = $false)]
    [switch]$AuditOnly,

    [Parameter(Mandatory = $false)]
    [switch]$Apply,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$TimeZone = 'GMT Standard Time',

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "`n=== Microsoft Teams Regional Settings ===" -ForegroundColor Cyan
        $modeText = if ($Apply) { 'APPLY SETTINGS' } else { 'AUDIT ONLY' }
        $modeColor = if ($Apply) { 'Yellow' } else { 'Green' }
        Write-Host "Mode: $modeText" -ForegroundColor $modeColor
        Write-Host ""

        $noteText = "[!] NOTE: Most Teams regional settings are inherited from Exchange Online mailbox settings."
        Write-Host $noteText -ForegroundColor Yellow
        $controlText = "[!] For comprehensive regional settings control, use Set-MailboxRegionalSettings.ps1"
        Write-Host $controlText -ForegroundColor Yellow
        Write-Host ""

        # Check for Teams module
        if (-not (Get-Module -Name MicrosoftTeams -ListAvailable)) {
            Write-Host "[-] Microsoft Teams module not found!" -ForegroundColor Red
            Write-Host "[!] Install with: Install-Module -Name MicrosoftTeams" -ForegroundColor Yellow
            return 1
        }

        # Check if connected
        try {
            $null = Get-CsOnlineUser -ResultSize 1 -ErrorAction Stop
            Write-Host "[+] Connected to Microsoft Teams" -ForegroundColor Green
        }
        catch {
            Write-Host "[!] Not connected to Teams. Connecting..." -ForegroundColor Yellow
            Connect-MicrosoftTeams -ErrorAction Stop
            Write-Host "[+] Connected to Microsoft Teams" -ForegroundColor Green
        }

        Write-Host ""

        Write-Host "[*] Teams regional settings are primarily controlled via:" -ForegroundColor Cyan
        $mailboxText = "    1. Exchange Online mailbox regional configuration (time zone, date format)"
        Write-Host $mailboxText -ForegroundColor White
        Write-Host "    2. M365 user language settings (display language)" -ForegroundColor White
        Write-Host "    3. Individual Teams client preferences (user-controlled)" -ForegroundColor White
        Write-Host ""

        Write-Host "[*] Recommended Actions:" -ForegroundColor Green
        Write-Host "    1. Run Set-UserLanguageSettings.ps1 for M365 account language" -ForegroundColor White
        Write-Host "    2. Run Set-MailboxRegionalSettings.ps1 for calendar/time zone" -ForegroundColor White
        Write-Host "    3. Teams will inherit these settings automatically" -ForegroundColor White
        Write-Host ""

        $policyText = "[+] For Teams-specific policies, use Teams admin center or Teams PowerShell cmdlets:"
        Write-Host $policyText -ForegroundColor Green
        Write-Host "    - Get-CsTeamsMeetingPolicy" -ForegroundColor Gray
        Write-Host "    - Set-CsTeamsMeetingPolicy" -ForegroundColor Gray
        Write-Host "    - Get-CsTeamsMessagingPolicy" -ForegroundColor Gray
        Write-Host ""

        $doneText = "[+] Script completed - Teams inherits regional settings from M365 and Exchange"
        Write-Host $doneText -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error with Teams module: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
