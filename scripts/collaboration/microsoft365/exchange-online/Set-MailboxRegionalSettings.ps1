<#
.SYNOPSIS
    Check and configure Exchange Online mailbox regional and calendar settings.

.DESCRIPTION
    Audits mailbox regional settings (time zone, date/time format, language) against a required
    baseline and, with -Apply, remediates mailboxes that do not match. With -Apply only compliant
    or successfully remediated runs exit 0; any processing error exits 1. Without -Apply the script
    is a pure audit and exits 1 when at least one mailbox is non-compliant (detection semantics),
    so it can be scheduled as a Proactive Remediation detection script. Re-running against a
    converged tenant is a no-op: compliant mailboxes are never written to.

.PARAMETER UserPrincipalName
    Specific user mailbox to configure. If not specified, uses the current logged-in user.

.PARAMETER AllMailboxes
    Apply settings to all user mailboxes in the tenant.

.PARAMETER AuditOnly
    Only check settings without making changes (default behavior).

.PARAMETER Apply
    Apply the required settings to mailboxes that don't match.

.PARAMETER TimeZone
    Target time zone (default: GMT Standard Time).

.PARAMETER DateFormat
    Date format string (default: dd/MM/yyyy).

.PARAMETER TimeFormat
    Time format string (default: HH:mm).

.PARAMETER Language
    Mailbox language (default: en-GB).

.PARAMETER WorkDays
    Work week days (default: Monday-Friday).

.PARAMETER WorkingHoursStartTime
    Work day start time (default: 08:00).

.PARAMETER WorkingHoursEndTime
    Work day end time (default: 17:00).

.PARAMETER ExportHTML
    Export results to an HTML report under the Documents\Reports folder.

.PARAMETER ExportCSV
    Export results to a CSV file under the Documents\Reports folder.

.EXAMPLE
    PS C:\> .\Set-MailboxRegionalSettings.ps1 -AuditOnly

    Checks the current user's mailbox settings without changing anything.

.EXAMPLE
    PS C:\> .\Set-MailboxRegionalSettings.ps1 -Apply

    Applies required settings to the current user's mailbox if non-compliant.

.EXAMPLE
    PS C:\> .\Set-MailboxRegionalSettings.ps1 -UserPrincipalName john.doe@company.com -Apply -WhatIf

    Shows what would be changed on john.doe@company.com without writing anything.

.EXAMPLE
    PS C:\> .\Set-MailboxRegionalSettings.ps1 -AllMailboxes -AuditOnly -ExportHTML

    Audits all mailboxes and exports an HTML report.

.NOTES
    File Name  : Set-MailboxRegionalSettings.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Requires Exchange Online PowerShell module
    Requires Exchange Administrator or Global Reader role
    Compatible with Exchange Online (Microsoft 365)
#>

[CmdletBinding(DefaultParameterSetName = 'AuditSingle', SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false, ParameterSetName = 'AuditSingle')]
    [Parameter(Mandatory = $false, ParameterSetName = 'ApplySingle')]
    [string]$UserPrincipalName,

    [Parameter(Mandatory = $false, ParameterSetName = 'AuditAll')]
    [Parameter(Mandatory = $false, ParameterSetName = 'ApplyAll')]
    [switch]$AllMailboxes,

    [Parameter(Mandatory = $false, ParameterSetName = 'AuditSingle')]
    [Parameter(Mandatory = $false, ParameterSetName = 'AuditAll')]
    [switch]$AuditOnly,

    [Parameter(Mandatory = $false, ParameterSetName = 'ApplySingle')]
    [Parameter(Mandatory = $false, ParameterSetName = 'ApplyAll')]
    [switch]$Apply,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$TimeZone = 'GMT Standard Time',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$DateFormat = 'dd/MM/yyyy',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$TimeFormat = 'HH:mm',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Language = 'en-GB',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$WorkDays = 'Monday, Tuesday, Wednesday, Thursday, Friday',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$WorkingHoursStartTime = '08:00:00',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$WorkingHoursEndTime = '17:00:00',

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = 'Stop'
# ScriptAnalyzer note: PSAvoidUsingWriteHost is accepted by design - the Bug-Free Umbrella output
# standard (RELAUNCH-SPEC section 3 / AGENTS.md) mandates Write-Host with prefix/color output.
# PSReviewUnusedParameter findings are false positives: parameters are read inside Main via the
# script scope. PSUseSingularNouns findings reflect legacy function nouns retained for conformance.

function Main {
    # Advanced so $PSCmdlet.ShouldProcess works regardless of invocation style;
    # script-level -WhatIf/-Confirm propagate here via preference variables.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "`n=== Exchange Online Mailbox Regional Settings ===" -ForegroundColor Cyan
        $modeStatus = if ($Apply) { 'APPLY SETTINGS' } else { 'AUDIT ONLY' }
        $modeColor = if ($Apply) { 'Yellow' } else { 'Green' }
        Write-Host "Mode: $modeStatus" -ForegroundColor $modeColor
        Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
        Write-Host ""

        # Check for Exchange Online module
        try {
            if (-not (Get-Module -Name ExchangeOnlineManagement -ListAvailable)) {
                Write-Host "[-] Exchange Online Management module not found!" -ForegroundColor Red
                Write-Host "[!] Install with: Install-Module -Name ExchangeOnlineManagement" -ForegroundColor Yellow
                return 1
            }

            # Check if connected
            $connectionStatus = Get-ConnectionInformation -ErrorAction SilentlyContinue
            if (-not $connectionStatus) {
                Write-Host "[!] Not connected to Exchange Online. Connecting..." -ForegroundColor Yellow
                Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
            }
            else {
                Write-Host "[+] Connected to Exchange Online: $($connectionStatus.UserPrincipalName)" `
                    -ForegroundColor Green
            }
        }
        catch {
            Write-Host "[-] Error connecting to Exchange Online: $($_.Exception.Message)" -ForegroundColor Red
            return 1
        }

        Write-Host ""

        # Required settings
        $requiredSettings = @{
            TimeZone               = $TimeZone
            DateFormat             = $DateFormat
            TimeFormat             = $TimeFormat
            Language               = $Language
            WorkDays               = $WorkDays
            WorkingHoursStartTime  = $WorkingHoursStartTime
            WorkingHoursEndTime    = $WorkingHoursEndTime
        }

        Write-Host "[*] Required Settings:" -ForegroundColor Cyan
        Write-Host "    Time Zone: $TimeZone" -ForegroundColor White
        Write-Host "    Date Format: $DateFormat" -ForegroundColor White
        Write-Host "    Time Format: $TimeFormat" -ForegroundColor White
        Write-Host "    Language: $Language" -ForegroundColor White
        Write-Host "    Work Days: $WorkDays" -ForegroundColor White
        Write-Host "    Work Hours: $WorkingHoursStartTime - $WorkingHoursEndTime" -ForegroundColor White
        Write-Host ""

        # Get mailboxes to process
        $mailboxesToProcess = @()

        if ($AllMailboxes) {
            Write-Host "[*] Retrieving all user mailboxes..." -ForegroundColor Cyan
            try {
                $allMailboxes = Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox `
                    -Properties DisplayName, UserPrincipalName -ErrorAction Stop
                Write-Host "[+] Found $(@($allMailboxes).Count) mailbox(es)" -ForegroundColor Green
                $mailboxesToProcess = @($allMailboxes)
            }
            catch {
                Write-Host "[-] Error retrieving mailboxes: $($_.Exception.Message)" -ForegroundColor Red
                return 1
            }
        }
        elseif ($UserPrincipalName) {
            Write-Host "[*] Retrieving mailbox: $UserPrincipalName..." -ForegroundColor Cyan
            try {
                $mailbox = Get-EXOMailbox -Identity $UserPrincipalName `
                    -Properties DisplayName, UserPrincipalName -ErrorAction Stop
                Write-Host "[+] Found mailbox: $($mailbox.DisplayName)" -ForegroundColor Green
                $mailboxesToProcess = @($mailbox)
            }
            catch {
                Write-Host "[-] Error retrieving mailbox: $($_.Exception.Message)" -ForegroundColor Red
                return 1
            }
        }
        else {
            Write-Host "[*] Using current logged-in user's mailbox..." -ForegroundColor Cyan
            try {
                $connectionStatus = Get-ConnectionInformation -ErrorAction Stop
                $mailbox = Get-EXOMailbox -Identity $connectionStatus.UserPrincipalName `
                    -Properties DisplayName, UserPrincipalName -ErrorAction Stop
                Write-Host "[+] Current user mailbox: $($mailbox.DisplayName)" -ForegroundColor Green
                $mailboxesToProcess = @($mailbox)
            }
            catch {
                Write-Host "[-] Error retrieving current user mailbox: $($_.Exception.Message)" -ForegroundColor Red
                return 1
            }
        }

        Write-Host ""

        # Process mailboxes
        $results = @()
        $compliantCount = 0
        $nonCompliantCount = 0
        $errorCount = 0

        $i = 0
        foreach ($mbx in $mailboxesToProcess) {
            $i++
            $progressStatus = "$i of $($mailboxesToProcess.Count): $($mbx.DisplayName)"
            $progressPercent = ($i / $mailboxesToProcess.Count) * 100
            Write-Progress -Activity "Processing Mailboxes" -Status $progressStatus -PercentComplete $progressPercent

            try {
                # Get current mailbox regional configuration
                $mailboxConfig = Get-MailboxRegionalConfiguration -Identity $mbx.UserPrincipalName -ErrorAction Stop

                $currentTimeZone = $mailboxConfig.TimeZone
                $currentDateFormat = $mailboxConfig.DateFormat
                $currentTimeFormat = $mailboxConfig.TimeFormat
                $currentLanguage = $mailboxConfig.Language.Name
                $currentWorkDays = $mailboxConfig.WorkDays -join ', '
                $currentWorkingHoursStartTime = $mailboxConfig.WorkingHoursStartTime
                $currentWorkingHoursEndTime = $mailboxConfig.WorkingHoursEndTime

                # Check compliance
                $issues = @()
                if ($currentTimeZone -ne $requiredSettings.TimeZone) {
                    $issues += "Time zone mismatch"
                }
                if ($currentDateFormat -ne $requiredSettings.DateFormat) {
                    $issues += "Date format mismatch"
                }
                if ($currentTimeFormat -ne $requiredSettings.TimeFormat) {
                    $issues += "Time format mismatch"
                }
                if ($currentLanguage -ne $requiredSettings.Language) {
                    $issues += "Language mismatch"
                }

                $isCompliant = $issues.Count -eq 0

                if ($isCompliant) {
                    $compliantCount++
                    $status = "Compliant"
                }
                else {
                    $nonCompliantCount++
                    $status = "Non-Compliant"
                    Write-Host "[!] $($mbx.DisplayName) - Non-Compliant:" -ForegroundColor Yellow
                    Write-Host "    Issues: $($issues -join ', ')" -ForegroundColor Gray
                }

                # Apply settings if requested; already-compliant mailboxes are never touched (idempotent)
                $actionTaken = "None"
                if ($Apply -and -not $isCompliant) {
                    try {
                        Write-Host "    [*] Applying settings..." -ForegroundColor Cyan

                        if ($PSCmdlet.ShouldProcess($mbx.UserPrincipalName, "Apply regional settings")) {
                            Set-MailboxRegionalConfiguration -Identity $mbx.UserPrincipalName `
                                -TimeZone $requiredSettings.TimeZone `
                                -DateFormat $requiredSettings.DateFormat `
                                -TimeFormat $requiredSettings.TimeFormat `
                                -Language $requiredSettings.Language `
                                -LocalizeDefaultFolderName:$true `
                                -ErrorAction Stop

                            $actionTaken = "Settings Applied"
                            $status = "Remediated"
                            Write-Host "    [+] Settings applied successfully!" -ForegroundColor Green
                        }
                        else {
                            $actionTaken = "Skipped (WhatIf)"
                            Write-Host "    [!] Skipped by WhatIf." -ForegroundColor Yellow
                        }
                    }
                    catch {
                        $actionTaken = "Error: $($_.Exception.Message)"
                        $status = "Error"
                        $errorCount++
                        Write-Host "    [-] Error applying settings: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }

                $result = [PSCustomObject]@{
                    DisplayName         = $mbx.DisplayName
                    UserPrincipalName   = $mbx.UserPrincipalName
                    CurrentTimeZone     = $currentTimeZone
                    RequiredTimeZone    = $requiredSettings.TimeZone
                    CurrentDateFormat   = $currentDateFormat
                    RequiredDateFormat  = $requiredSettings.DateFormat
                    CurrentTimeFormat   = $currentTimeFormat
                    RequiredTimeFormat  = $requiredSettings.TimeFormat
                    CurrentLanguage     = $currentLanguage
                    RequiredLanguage    = $requiredSettings.Language
                    WorkDays            = $currentWorkDays
                    WorkHours           = "$currentWorkingHoursStartTime - $currentWorkingHoursEndTime"
                    Status              = $status
                    Issues              = if ($issues.Count -gt 0) { $issues -join '; ' } else { 'None' }
                    ActionTaken         = $actionTaken
                }

                $results += $result
            }
            catch {
                $errorCount++
                Write-Host "[-] Error processing $($mbx.DisplayName): $($_.Exception.Message)" -ForegroundColor Red

                $result = [PSCustomObject]@{
                    DisplayName         = $mbx.DisplayName
                    UserPrincipalName   = $mbx.UserPrincipalName
                    CurrentTimeZone     = "Error"
                    RequiredTimeZone    = $requiredSettings.TimeZone
                    CurrentDateFormat   = "Error"
                    RequiredDateFormat  = $requiredSettings.DateFormat
                    CurrentTimeFormat   = "Error"
                    RequiredTimeFormat  = $requiredSettings.TimeFormat
                    CurrentLanguage     = "Error"
                    RequiredLanguage    = $requiredSettings.Language
                    WorkDays            = "Error"
                    WorkHours           = "Error"
                    Status              = "Error"
                    Issues              = $_.Exception.Message
                    ActionTaken         = "N/A"
                }

                $results += $result
            }
        }

        Write-Progress -Activity "Processing Mailboxes" -Completed

        Write-Host ""

        # Display summary
        Write-Host "=== Summary ===" -ForegroundColor Cyan
        Write-Host "Total Mailboxes Processed: $($results.Count)" -ForegroundColor White
        Write-Host "Compliant: $compliantCount" -ForegroundColor Green
        Write-Host "Non-Compliant: $nonCompliantCount" -ForegroundColor Yellow
        if ($Apply) {
            $remediatedCount = @($results | Where-Object { $_.Status -eq 'Remediated' }).Count
            Write-Host "Remediated: $remediatedCount" -ForegroundColor Green
        }
        Write-Host "Errors: $errorCount" -ForegroundColor Red
        Write-Host ""

        # Show non-compliant mailboxes
        if ($nonCompliantCount -gt 0 -and -not $Apply) {
            Write-Host "=== Non-Compliant Mailboxes ===" -ForegroundColor Yellow
            $results | Where-Object { $_.Status -eq "Non-Compliant" } |
                Select-Object -First 10 DisplayName, CurrentTimeZone, CurrentDateFormat, Issues |
                Format-Table -AutoSize

            if ($nonCompliantCount -gt 10) {
                Write-Host "[!] Showing first 10 of $nonCompliantCount non-compliant mailboxes" -ForegroundColor Yellow
            }
        }

        # Export results
        if ($ExportHTML) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $reportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
            if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
                New-Item -ItemType Directory -Path $reportDir -Force -ErrorAction Stop | Out-Null
            }
            $htmlPath = (Join-Path $reportDir "MailboxRegionalSettings_$timestamp.html")

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Mailbox Regional Settings Report - $timestamp</title>
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
        .settings { background-color: #e6f2ff; padding: 10px; border-left: 4px solid #0078d4; margin: 15px 0; }
    </style>
</head>
<body>
    <h1>Exchange Online Mailbox Regional Settings Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Mode:</strong> $(if ($Apply) { 'APPLY SETTINGS' } else { 'AUDIT ONLY' })<br>
        <strong>Total Mailboxes:</strong> $($results.Count)<br>
        <strong>Compliant:</strong> $compliantCount<br>
        <strong>Non-Compliant:</strong> $nonCompliantCount<br>
        $(if ($Apply) { "<strong>Remediated:</strong> $remediatedCount<br>" })
        <strong>Errors:</strong> $errorCount
    </div>

    <div class="settings">
        <h3>Required Settings</h3>
        <strong>Time Zone:</strong> $($requiredSettings.TimeZone)<br>
        <strong>Date Format:</strong> $($requiredSettings.DateFormat)<br>
        <strong>Time Format:</strong> $($requiredSettings.TimeFormat)<br>
        <strong>Language:</strong> $($requiredSettings.Language)
    </div>

    <h2>Mailbox Details</h2>
    <table>
        <tr>
            <th>Display Name</th>
            <th>UPN</th>
            <th>Current TZ</th>
            <th>Current Date Format</th>
            <th>Current Language</th>
            <th>Status</th>
            <th>Issues</th>
            $(if ($Apply) { "<th>Action Taken</th>" })
        </tr>
"@

            foreach ($result in ($results | Sort-Object Status, DisplayName)) {
                $statusClass = switch ($result.Status) {
                    'Compliant' { 'compliant' }
                    'Non-Compliant' { 'non-compliant' }
                    'Remediated' { 'remediated' }
                    'Error' { 'error' }
                }

                $html += @"
        <tr>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.DisplayName)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.UserPrincipalName)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.CurrentTimeZone)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.CurrentDateFormat)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.CurrentLanguage)"))</td>
            <td><span class="$statusClass">$($result.Status)</span></td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.Issues)"))</td>
            $(if ($Apply) { "<td>$([System.Net.WebUtility]::HtmlEncode("$($result.ActionTaken)"))</td>" })
        </tr>
"@
            }

            $html += "</table></body></html>"

            $html | Out-File -FilePath $htmlPath -Encoding utf8 -ErrorAction Stop
            Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
        }

        if ($ExportCSV) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $reportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
            if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
                New-Item -ItemType Directory -Path $reportDir -Force -ErrorAction Stop | Out-Null
            }
            $csvPath = (Join-Path $reportDir "MailboxRegionalSettings_$timestamp.csv")
            $results | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
            Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
        }

        Write-Host "`n[+] Mailbox regional settings check completed!" -ForegroundColor Green

        # Exit codes: 0 = success (or remediated); 1 = errors occurred, or audit found non-compliant mailboxes
        if ($errorCount -gt 0) {
            return 1
        }
        elseif ($nonCompliantCount -gt 0 -and -not $Apply) {
            return 1
        }
        else {
            return 0
        }
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
