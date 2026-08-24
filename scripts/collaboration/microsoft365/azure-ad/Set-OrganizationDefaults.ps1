<#
.SYNOPSIS
    Audit and configure the organization-wide PreferredLanguage setting in Microsoft 365.

.DESCRIPTION
    Connects to Microsoft Graph and audits the organization-level PreferredLanguage setting for
    the Microsoft 365 organization (the only organization-level default this script manages).
    In audit mode it reports the current value against the required value without changing
    anything; with -Apply it updates the organization only when the setting is non-compliant,
    so re-running on a converged tenant makes no further changes. Returns exit code 0 when the
    check or apply completes, and exit code 1 on module, connection, or retrieval failure.

    Note: There is no organization-level "default usage location" or "preferred data location"
    default. UsageLocation and PreferredDataLocation are per-user attributes and must be set on
    individual user objects (for example, Update-MgUser -UsageLocation). Existing users must be
    configured separately using Set-UserLanguageSettings.ps1 and Set-MailboxRegionalSettings.ps1.

.PARAMETER UsageLocation
    Usage location country code (default: GB for United Kingdom). Used for reference only -
    UsageLocation is a per-user attribute and cannot be set at the organization level.

.PARAMETER PreferredLanguage
    Default preferred language to enforce at the organization level (default: en-GB).

.PARAMETER AuditOnly
    Only check current settings without making changes (default behavior).

.PARAMETER Apply
    Apply the required PreferredLanguage setting when the organization is non-compliant.
    Honors -WhatIf/-Confirm via SupportsShouldProcess.

.PARAMETER ExportHTML
    Reserved switch retained for interface compatibility; results are reported to the console
    only and no HTML file is written.

.EXAMPLE
    PS C:\> .\Set-OrganizationDefaults.ps1 -AuditOnly

    Checks current organization default settings without making changes.

.EXAMPLE
    PS C:\> .\Set-OrganizationDefaults.ps1 -Apply

    Applies the organization PreferredLanguage default if it does not already match en-GB.

.NOTES
    File Name  : Set-OrganizationDefaults.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Requires Microsoft Graph PowerShell module.
    Requires Organization.ReadWrite.All permission (Global Administrator role).
    Only the organization PreferredLanguage setting is managed; usage location is a per-user attribute.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$UsageLocation = 'GB',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PreferredLanguage = 'en-GB',

    [Parameter(Mandatory = $false)]
    [switch]$AuditOnly,

    [Parameter(Mandatory = $false)]
    [switch]$Apply,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML
)

$ErrorActionPreference = 'Stop'

# Write-Host is intentional throughout: AGENTS.md requires user-facing colored [+] [!] [-] [*] console output.
function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$UsageLocation = 'GB',

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$PreferredLanguage = 'en-GB',

        [Parameter(Mandatory = $false)]
        [switch]$AuditOnly,

        [Parameter(Mandatory = $false)]
        [switch]$Apply,

        [Parameter(Mandatory = $false)]
        [switch]$ExportHTML
    )

    try {
        Write-Host "`n=== Microsoft 365 Organization Default Settings ===" -ForegroundColor Cyan
        $modeColor = if ($Apply) { 'Yellow' } else { 'Green' }
        $modeText = if ($Apply) { 'APPLY SETTINGS' } else { 'AUDIT ONLY' }
        Write-Host "Mode: $modeText" -ForegroundColor $modeColor
        Write-Host ""

        # Check for Microsoft Graph module
        try {
            if (-not (Get-Module -Name Microsoft.Graph.Identity.DirectoryManagement -ListAvailable)) {
                Write-Host "[-] Microsoft Graph module not found!" -ForegroundColor Red
                Write-Host "[!] Install with: Install-Module -Name Microsoft.Graph" -ForegroundColor Yellow
                return 1
            }

            Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop

            $context = Get-MgContext -ErrorAction Stop
            if (-not $context) {
                Write-Host "[!] Not connected to Microsoft Graph. Connecting..." -ForegroundColor Yellow
                Connect-MgGraph -Scopes "Organization.ReadWrite.All" -NoWelcome -ErrorAction Stop
                $context = Get-MgContext -ErrorAction Stop
            }

            Write-Host "[+] Connected to Microsoft Graph" -ForegroundColor Green
            Write-Host "    Account: $($context.Account)" -ForegroundColor Gray
        }
        catch {
            Write-Host "[-] Error connecting to Microsoft Graph: $($_.Exception.Message)" -ForegroundColor Red
            return 1
        }

        Write-Host ""

        # Get organization settings
        Write-Host "[*] Retrieving organization settings..." -ForegroundColor Cyan

        try {
            $org = @(Get-MgOrganization -ErrorAction Stop)
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
            Write-Host ("(Usage location is a per-user attribute and is not managed " +
                "at the organization level)") -ForegroundColor Gray
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

            # Apply if requested (idempotent: act only when non-compliant)
            if ($Apply -and -not $isCompliant) {
                $orgAction = "Set organization PreferredLanguage to '$PreferredLanguage'"
                if ($PSCmdlet.ShouldProcess($orgSettings.DisplayName, $orgAction)) {
                    Write-Host "[*] Applying organization settings..." -ForegroundColor Cyan

                    try {
                        Update-MgOrganization -OrganizationId $orgSettings.Id `
                            -PreferredLanguage $PreferredLanguage -ErrorAction Stop
                        Write-Host "[+] Organization settings updated successfully!" -ForegroundColor Green
                    }
                    catch {
                        $updateErrMsg = "[-] Error updating organization settings: $($_.Exception.Message)"
                        Write-Host $updateErrMsg -ForegroundColor Red
                    }
                }
            }
            elseif ($Apply -and $isCompliant) {
                Write-Host "[+] Already compliant; no changes made" -ForegroundColor Green
            }

            Write-Host ""
            Write-Host "=== Important Notes ===" -ForegroundColor Yellow
            Write-Host "[!] Organization-level settings affect NEW users only" -ForegroundColor Yellow
            Write-Host "[!] To configure existing users, use:" -ForegroundColor Yellow
            Write-Host "    - Set-UserLanguageSettings.ps1 for M365 account settings" -ForegroundColor White
            Write-Host "    - Set-MailboxRegionalSettings.ps1 for Exchange mailbox settings" -ForegroundColor White
            $orgNoteMsg = "    - proactive-remediations/region-language-settings for client devices"
            Write-Host $orgNoteMsg -ForegroundColor White
            Write-Host ""

            Write-Host "[!] Usage Location must be set per-user for license assignment:" -ForegroundColor Yellow
            Write-Host "    Get-MgUser -All | Update-MgUser -UsageLocation '$UsageLocation'" -ForegroundColor White
            Write-Host ""
        }
        catch {
            Write-Host "[-] Error retrieving organization settings: $($_.Exception.Message)" -ForegroundColor Red
            return 1
        }

        Write-Host "[+] Organization defaults check completed!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
