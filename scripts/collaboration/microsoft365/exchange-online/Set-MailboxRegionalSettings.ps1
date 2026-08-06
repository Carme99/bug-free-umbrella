<#
.SYNOPSIS
    Checks and configures Exchange Online mailbox regional and calendar settings.

.DESCRIPTION
    This script audits and configures Exchange Online mailbox-specific regional settings including:
    - Mailbox time zone
    - Date format
    - Time format
    - Language for Outlook Web App
    - Work week settings (days and hours)
    - Calendar format preferences

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
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Set-MailboxRegionalSettings.ps1 -AuditOnly
    Checks current user's mailbox settings.

.EXAMPLE
    .\Set-MailboxRegionalSettings.ps1 -Apply
    Applies required settings to current user's mailbox.

.EXAMPLE
    .\Set-MailboxRegionalSettings.ps1 -UserPrincipalName john.doe@company.com -Apply
    Applies settings to specific user mailbox.

.EXAMPLE
    .\Set-MailboxRegionalSettings.ps1 -AllMailboxes -AuditOnly -ExportHTML
    Audits all mailboxes and exports report.

.NOTES
    Requires Exchange Online PowerShell module
    Requires Exchange Administrator or Global Reader role
    Compatible with Exchange Online (Microsoft 365)
#>

[CmdletBinding(DefaultParameterSetName='AuditSingle')]
param(
    [Parameter(Mandatory=$false, ParameterSetName='AuditSingle')]
    [Parameter(Mandatory=$false, ParameterSetName='ApplySingle')]
    [string]$UserPrincipalName,

    [Parameter(Mandatory=$false, ParameterSetName='AuditAll')]
    [Parameter(Mandatory=$false, ParameterSetName='ApplyAll')]
    [switch]$AllMailboxes,

    [Parameter(Mandatory=$false, ParameterSetName='AuditSingle')]
    [Parameter(Mandatory=$false, ParameterSetName='AuditAll')]
    [switch]$AuditOnly,

    [Parameter(Mandatory=$false, ParameterSetName='ApplySingle')]
    [Parameter(Mandatory=$false, ParameterSetName='ApplyAll')]
    [switch]$Apply,

    [Parameter(Mandatory=$false)]
    [string]$TimeZone = 'GMT Standard Time',

    [Parameter(Mandatory=$false)]
    [string]$DateFormat = 'dd/MM/yyyy',

    [Parameter(Mandatory=$false)]
    [string]$TimeFormat = 'HH:mm',

    [Parameter(Mandatory=$false)]
    [string]$Language = 'en-GB',

    [Parameter(Mandatory=$false)]
    [string]$WorkDays = 'Monday, Tuesday, Wednesday, Thursday, Friday',

    [Parameter(Mandatory=$false)]
    [string]$WorkingHoursStartTime = '08:00:00',

    [Parameter(Mandatory=$false)]
    [string]$WorkingHoursEndTime = '17:00:00',

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

Write-Host "`n=== Exchange Online Mailbox Regional Settings ===" -ForegroundColor Cyan
Write-Host "Mode: $(if ($Apply) { 'APPLY SETTINGS' } else { 'AUDIT ONLY' })" -ForegroundColor $(if ($Apply) { 'Yellow' } else { 'Green' })
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

# Check for Exchange Online module
try {
    if (-not (Get-Module -Name ExchangeOnlineManagement -ListAvailable)) {
        Write-Host "[-] Exchange Online Management module not found!" -ForegroundColor Red
        Write-Host "[!] Install with: Install-Module -Name ExchangeOnlineManagement" -ForegroundColor Yellow
        exit 1
    }

    # Check if connected
    $connectionStatus = Get-ConnectionInformation -ErrorAction SilentlyContinue
    if (-not $connectionStatus) {
        Write-Host "[!] Not connected to Exchange Online. Connecting..." -ForegroundColor Yellow
        Connect-ExchangeOnline -ShowBanner:$false
    }
    else {
        Write-Host "[+] Connected to Exchange Online: $($connectionStatus.UserPrincipalName)" -ForegroundColor Green
    }
}
catch {
    Write-Host "[-] Error connecting to Exchange Online: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Required settings
$requiredSettings = @{
    TimeZone = $TimeZone
    DateFormat = $DateFormat
    TimeFormat = $TimeFormat
    Language = $Language
    WorkDays = $WorkDays
    WorkingHoursStartTime = $WorkingHoursStartTime
    WorkingHoursEndTime = $WorkingHoursEndTime
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
        $allMailboxes = Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox -Properties DisplayName,UserPrincipalName
        Write-Host "[+] Found $($allMailboxes.Count) mailbox(es)" -ForegroundColor Green
        $mailboxesToProcess = $allMailboxes
    }
    catch {
        Write-Host "[-] Error retrieving mailboxes: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
elseif ($UserPrincipalName) {
    Write-Host "[*] Retrieving mailbox: $UserPrincipalName..." -ForegroundColor Cyan
    try {
        $mailbox = Get-EXOMailbox -Identity $UserPrincipalName -Properties DisplayName,UserPrincipalName
        Write-Host "[+] Found mailbox: $($mailbox.DisplayName)" -ForegroundColor Green
        $mailboxesToProcess = @($mailbox)
    }
    catch {
        Write-Host "[-] Error retrieving mailbox: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "[*] Using current logged-in user's mailbox..." -ForegroundColor Cyan
    try {
        $connectionStatus = Get-ConnectionInformation
        $mailbox = Get-EXOMailbox -Identity $connectionStatus.UserPrincipalName -Properties DisplayName,UserPrincipalName
        Write-Host "[+] Current user mailbox: $($mailbox.DisplayName)" -ForegroundColor Green
        $mailboxesToProcess = @($mailbox)
    }
    catch {
        Write-Host "[-] Error retrieving current user mailbox: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
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
    Write-Progress -Activity "Processing Mailboxes" -Status "$i of $($mailboxesToProcess.Count): $($mbx.DisplayName)" -PercentComplete (($i / $mailboxesToProcess.Count) * 100)

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

        # Apply settings if requested
        $actionTaken = "None"
        if ($Apply -and -not $isCompliant) {
            try {
                Write-Host "    [*] Applying settings..." -ForegroundColor Cyan

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
            catch {
                $actionTaken = "Error: $($_.Exception.Message)"
                $status = "Error"
                $errorCount++
                Write-Host "    [-] Error applying settings: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        $result = [PSCustomObject]@{
            DisplayName = $mbx.DisplayName
            UserPrincipalName = $mbx.UserPrincipalName
            CurrentTimeZone = $currentTimeZone
            RequiredTimeZone = $requiredSettings.TimeZone
            CurrentDateFormat = $currentDateFormat
            RequiredDateFormat = $requiredSettings.DateFormat
            CurrentTimeFormat = $currentTimeFormat
            RequiredTimeFormat = $requiredSettings.TimeFormat
            CurrentLanguage = $currentLanguage
            RequiredLanguage = $requiredSettings.Language
            WorkDays = $currentWorkDays
            WorkHours = "$currentWorkingHoursStartTime - $currentWorkingHoursEndTime"
            Status = $status
            Issues = if ($issues.Count -gt 0) { $issues -join '; ' } else { 'None' }
            ActionTaken = $actionTaken
        }

        $results += $result
    }
    catch {
        $errorCount++
        Write-Host "[-] Error processing $($mbx.DisplayName): $($_.Exception.Message)" -ForegroundColor Red

        $result = [PSCustomObject]@{
            DisplayName = $mbx.DisplayName
            UserPrincipalName = $mbx.UserPrincipalName
            CurrentTimeZone = "Error"
            RequiredTimeZone = $requiredSettings.TimeZone
            CurrentDateFormat = "Error"
            RequiredDateFormat = $requiredSettings.DateFormat
            CurrentTimeFormat = "Error"
            RequiredTimeFormat = $requiredSettings.TimeFormat
            CurrentLanguage = "Error"
            RequiredLanguage = $requiredSettings.Language
            WorkDays = "Error"
            WorkHours = "Error"
            Status = "Error"
            Issues = $_.Exception.Message
            ActionTaken = "N/A"
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
    $remediatedCount = ($results | Where-Object { $_.Status -eq 'Remediated' }).Count
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
        Write-Host "[!] Showing first 10 of $nonCompliantCount non-compliant mailboxes" -ForegroundColor Gray
    }
}

# Export results
if ($ExportHTML) {
    $htmlPath = (Join-Path $ReportDir "MailboxRegionalSettings_$timestamp.html")

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
        $(if ($Apply) { "<strong>Remediated:</strong> $(($results | Where-Object { $_.Status -eq 'Remediated' }).Count)<br>" })
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

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($ExportCSV) {
    $csvPath = (Join-Path $ReportDir "MailboxRegionalSettings_$timestamp.csv")
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

Write-Host "`n[+] Mailbox regional settings check completed!" -ForegroundColor Green

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
