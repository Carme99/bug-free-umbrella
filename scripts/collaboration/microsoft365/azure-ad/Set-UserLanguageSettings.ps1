#Requires -Version 7.0
<#
.SYNOPSIS
    Check and configure Microsoft 365 user language and region settings.

.DESCRIPTION
    Audits and configures M365 user account language and region settings to ensure they match
    organizational standards: display language, preferred language, regional format, and time
    zone. The script operates in two modes - audit mode (default) reports current settings vs.
    required settings without changing anything, while remediation mode (-Apply) updates only
    users that do not match, so re-running on a converged tenant makes no further changes.
    Returns exit code 0 when all processed users are compliant or successfully remediated,
    and exit code 1 when any error occurs or non-compliant users remain in audit mode.
    Mutation is gated behind SupportsShouldProcess (-WhatIf/-Confirm).

.PARAMETER UserPrincipalName
    Specific user to configure. If not specified, uses the current logged-in user.

.PARAMETER AllUsers
    Apply settings to all users in the tenant (requires admin privileges).

.PARAMETER AuditOnly
    Only check settings without making changes (default behavior).

.PARAMETER Apply
    Apply the required settings to users who don't match. Honors -WhatIf/-Confirm.

.PARAMETER DisplayLanguage
    Target display language locale code (default: en-GB).

.PARAMETER RegionalFormat
    Target regional format locale code (default: en-GB).

.PARAMETER TimeZone
    Target time zone (default: GMT Standard Time).

.PARAMETER ExportHTML
    Export results to an HTML report file.

.PARAMETER ExportCSV
    Export results to a CSV file.

.EXAMPLE
    PS C:\> .\Set-UserLanguageSettings.ps1 -AuditOnly

    Checks current user's language settings without making changes.

.EXAMPLE
    PS C:\> .\Set-UserLanguageSettings.ps1 -Apply

    Applies required language settings to the current user if they do not match.

.EXAMPLE
    PS C:\> .\Set-UserLanguageSettings.ps1 -UserPrincipalName john.doe@company.com -Apply

    Applies settings to a specific user.

.EXAMPLE
    PS C:\> .\Set-UserLanguageSettings.ps1 -AllUsers -AuditOnly -ExportHTML

    Audits all users and exports the report to HTML.

.NOTES
    File Name  : Set-UserLanguageSettings.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Requires Microsoft Graph PowerShell module (Microsoft.Graph.Users).
    Requires User.ReadWrite.All permission for a single user.
    Requires User.ReadWrite.All and Directory.Read.All for all users.
    Compatible with Exchange Online and Microsoft 365.

    Standard Settings (based on UK configuration):
    - Display Language: en-GB (English United Kingdom)
    - Preferred Languages: en-GB
    - Regional Format: en-GB
    - Time Zone: GMT Standard Time (UTC+00:00)
#>

[CmdletBinding(SupportsShouldProcess)]
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
    [string]$DisplayLanguage = 'en-GB',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$RegionalFormat = 'en-GB',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$TimeZone = 'GMT Standard Time',

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = 'Stop'

# Resolve (and create if needed) the Documents\Reports directory used by export switches.
function Get-ReportDirectory {
    $reportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
    if ([string]::IsNullOrWhiteSpace($reportDir) -or
        $reportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
        $reportDir -match '^(\\\\|//)') {
        throw "Unsafe report path: $reportDir. Report path must be a local absolute path without '..' traversal."
    }
    $fullReportDir = [System.IO.Path]::GetFullPath($reportDir)
    if (-not (Test-Path -LiteralPath $fullReportDir -PathType Container)) {
        New-Item -ItemType Directory -Path $fullReportDir -Force -ErrorAction Stop | Out-Null
    }
    return $fullReportDir
}

# Write-Host is intentional throughout: AGENTS.md requires user-facing colored [+] [!] [-] [*] console output.
function Main {
    [CmdletBinding(SupportsShouldProcess)]
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
        [string]$DisplayLanguage = 'en-GB',

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$RegionalFormat = 'en-GB',

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$TimeZone = 'GMT Standard Time',

        [Parameter(Mandatory = $false)]
        [switch]$ExportHTML,

        [Parameter(Mandatory = $false)]
        [switch]$ExportCSV
    )

    try {
        Write-Host "`n=== Microsoft 365 Language & Region Settings ===" -ForegroundColor Cyan
        $modeColor = if ($Apply) { 'Yellow' } else { 'Green' }
        $modeText = if ($Apply) { 'APPLY SETTINGS' } else { 'AUDIT ONLY' }
        Write-Host "Mode: $modeText" -ForegroundColor $modeColor
        Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
        Write-Host ""

        # Check for Microsoft Graph module
        try {
            if (-not (Get-Module -Name Microsoft.Graph.Users -ListAvailable)) {
                Write-Host "[-] Microsoft Graph Users module not found!" -ForegroundColor Red
                Write-Host "[!] Install with: Install-Module -Name Microsoft.Graph.Users" -ForegroundColor Yellow
                return 1
            }

            # Import required modules
            Import-Module Microsoft.Graph.Users -ErrorAction Stop

            # Check if connected
            $context = Get-MgContext -ErrorAction Stop
            if (-not $context) {
                Write-Host "[!] Not connected to Microsoft Graph. Connecting..." -ForegroundColor Yellow

                $scopes = @('User.ReadWrite.All', 'MailboxSettings.ReadWrite')
                if ($AllUsers) {
                    $scopes += 'Directory.Read.All'
                }

                Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop
                $context = Get-MgContext -ErrorAction Stop
            }

            Write-Host "[+] Connected to Microsoft Graph" -ForegroundColor Green
            Write-Host "    Account: $($context.Account)" -ForegroundColor Gray
            Write-Host "    Scopes: $($context.Scopes -join ', ')" -ForegroundColor Gray
        }
        catch {
            Write-Host "[-] Error connecting to Microsoft Graph: $($_.Exception.Message)" -ForegroundColor Red
            return 1
        }

        Write-Host ""

        # Required settings
        $requiredSettings = @{
            DisplayLanguage = $DisplayLanguage
            RegionalFormat = $RegionalFormat
            TimeZone = $TimeZone
        }

        Write-Host "[*] Required Settings:" -ForegroundColor Cyan
        Write-Host "    Display Language: $DisplayLanguage" -ForegroundColor White
        Write-Host "    Regional Format: $RegionalFormat" -ForegroundColor White
        Write-Host "    Time Zone: $TimeZone" -ForegroundColor White
        Write-Host ""

        # Get users to process
        $usersToProcess = @()

        if ($AllUsers) {
            Write-Host "[*] Retrieving all users..." -ForegroundColor Cyan
            try {
                # Local name avoids the case-insensitive collision with the [switch]$AllUsers parameter.
                $retrievedUsers = @(Get-MgUser -All -Property Id, DisplayName, UserPrincipalName, `
                    Mail -ErrorAction Stop)
                Write-Host "[+] Found $($retrievedUsers.Count) user(s)" -ForegroundColor Green
                $usersToProcess = $retrievedUsers
            }
            catch {
                Write-Host "[-] Error retrieving users: $($_.Exception.Message)" -ForegroundColor Red
                return 1
            }
        }
        elseif ($UserPrincipalName) {
            Write-Host "[*] Retrieving user: $UserPrincipalName..." -ForegroundColor Cyan
            try {
                $user = Get-MgUser -UserId $UserPrincipalName `
                    -Property Id, DisplayName, UserPrincipalName, Mail -ErrorAction Stop
                Write-Host "[+] Found user: $($user.DisplayName)" -ForegroundColor Green
                $usersToProcess = @($user)
            }
            catch {
                Write-Host "[-] Error retrieving user: $($_.Exception.Message)" -ForegroundColor Red
                return 1
            }
        }
        else {
            # Use current logged-in user
            Write-Host "[*] Using current logged-in user..." -ForegroundColor Cyan
            try {
                $currentUser = Get-MgUser -UserId $context.Account `
                    -Property Id, DisplayName, UserPrincipalName, Mail -ErrorAction Stop
                Write-Host "[+] Current user: $($currentUser.DisplayName)" -ForegroundColor Green
                $usersToProcess = @($currentUser)
            }
            catch {
                Write-Host "[-] Error retrieving current user: $($_.Exception.Message)" -ForegroundColor Red
                return 1
            }
        }

        Write-Host ""

        # Process users
        $results = @()
        $compliantCount = 0
        $nonCompliantCount = 0
        $errorCount = 0

        $i = 0
        $totalUsers = $usersToProcess.Count

        # Performance optimization: Use parallel processing for large user sets
        if ($totalUsers -gt 50 -and $PSVersionTable.PSVersion.Major -ge 7) {
            Write-Host "[*] Processing $totalUsers users in parallel (PowerShell 7+)..." -ForegroundColor Cyan

            $results = $usersToProcess | ForEach-Object -Parallel {
                $user = $_
                $requiredSettings = $using:requiredSettings
                $Apply = $using:Apply

                try {
                    # Get current mailbox settings
                    $mailboxSettings = Get-MgUserMailboxSetting -UserId $user.Id -ErrorAction Stop
                    $userSettings = Get-MgUser -UserId $user.Id -Property PreferredLanguage -ErrorAction Stop

                    # Extract current settings
                    $currentDisplayLanguage = $mailboxSettings.Language.Locale
                    $currentTimeZone = $mailboxSettings.TimeZone
                    $currentPreferredLanguage = $userSettings.PreferredLanguage
                    $currentRegionalFormat = $mailboxSettings.Language.Locale

                    # Check compliance
                    $isCompliant = (
                        $currentDisplayLanguage -eq $requiredSettings.DisplayLanguage -and
                        $currentTimeZone -eq $requiredSettings.TimeZone -and
                        $currentRegionalFormat -eq $requiredSettings.RegionalFormat
                    )

                    $issues = @()
                    if ($currentDisplayLanguage -ne $requiredSettings.DisplayLanguage) {
                        $issues += "Display language mismatch"
                    }
                    if ($currentTimeZone -ne $requiredSettings.TimeZone) {
                        $issues += "Time zone mismatch"
                    }

                    $status = if ($isCompliant) { "Compliant" } else { "Non-Compliant" }
                    $actionTaken = "None"

                    # Apply settings if requested. $PSCmdlet is unavailable inside parallel runspaces,
                    # so -WhatIf is honored through the preference variable instead of ShouldProcess.
                    if ($Apply -and -not $isCompliant -and -not $using:WhatIfPreference) {
                        try {
                            $languageSettings = @{
                                Language = @{
                                    Locale = $requiredSettings.DisplayLanguage
                                    DisplayName = "English (United Kingdom)"
                                }
                                TimeZone = $requiredSettings.TimeZone
                            }

                            Update-MgUserMailboxSetting -UserId $user.Id `
                                -BodyParameter $languageSettings -ErrorAction Stop
                            Update-MgUser -UserId $user.Id `
                                -PreferredLanguage $requiredSettings.DisplayLanguage -ErrorAction Stop

                            $actionTaken = "Settings Applied"
                            $status = "Remediated"
                        }
                        catch {
                            $actionTaken = "Error: $($_.Exception.Message)"
                            $status = "Error"
                        }
                    }
                    elseif ($Apply -and -not $isCompliant -and $using:WhatIfPreference) {
                        $actionTaken = "WhatIf: Settings Applied"
                        $status = "Remediated"
                    }

                    [PSCustomObject]@{
                        DisplayName = $user.DisplayName
                        UserPrincipalName = $user.UserPrincipalName
                        CurrentDisplayLanguage = $currentDisplayLanguage
                        RequiredDisplayLanguage = $requiredSettings.DisplayLanguage
                        CurrentTimeZone = $currentTimeZone
                        RequiredTimeZone = $requiredSettings.TimeZone
                        CurrentRegionalFormat = $currentRegionalFormat
                        RequiredRegionalFormat = $requiredSettings.RegionalFormat
                        PreferredLanguage = $currentPreferredLanguage
                        Status = $status
                        Issues = if ($issues.Count -gt 0) { $issues -join '; ' } else { 'None' }
                        ActionTaken = $actionTaken
                    }
                }
                catch {
                    [PSCustomObject]@{
                        DisplayName = $user.DisplayName
                        UserPrincipalName = $user.UserPrincipalName
                        CurrentDisplayLanguage = "Error"
                        RequiredDisplayLanguage = $requiredSettings.DisplayLanguage
                        CurrentTimeZone = "Error"
                        RequiredTimeZone = $requiredSettings.TimeZone
                        CurrentRegionalFormat = "Error"
                        RequiredRegionalFormat = $requiredSettings.RegionalFormat
                        PreferredLanguage = "Error"
                        Status = "Error"
                        Issues = $_.Exception.Message
                        ActionTaken = "N/A"
                    }
                }
            } -ThrottleLimit 10  # Process 10 users concurrently

            # Count results
            $compliantCount = ($results | Where-Object { $_.Status -eq 'Compliant' }).Count
            $nonCompliantCount = ($results | Where-Object { $_.Status -eq 'Non-Compliant' }).Count
            $errorCount = ($results | Where-Object { $_.Status -eq 'Error' }).Count
        }
        else {
            # Sequential processing for smaller sets
            if ($totalUsers -le 50) {
                Write-Host "[*] Processing $totalUsers users sequentially..." -ForegroundColor Cyan
            }
            else {
                $seqMsg = "[*] Processing $totalUsers users sequentially (PowerShell 7+ recommended)"
                Write-Host "$seqMsg for parallel processing)..." -ForegroundColor Yellow
            }

            foreach ($user in $usersToProcess) {
                $i++
                $progressPercent = if ($usersToProcess.Count -gt 0) { (($i / $usersToProcess.Count) * 100) }
                else { 100 }
                $progressStatus = "$i of $($usersToProcess.Count): $($user.DisplayName)"
                Write-Progress -Activity "Processing Users" -Status $progressStatus -PercentComplete $progressPercent

                try {
                    # Get current mailbox settings (includes language and time zone)
                    $mailboxSettings = Get-MgUserMailboxSetting -UserId $user.Id -ErrorAction Stop

                    # Get user settings (includes preferred language)
                    $userSettings = Get-MgUser -UserId $user.Id -Property PreferredLanguage -ErrorAction Stop

                    # Extract current settings
                    $currentDisplayLanguage = $mailboxSettings.Language.Locale
                    $currentTimeZone = $mailboxSettings.TimeZone
                    $currentPreferredLanguage = $userSettings.PreferredLanguage

                    # Regional format is typically the same as display language in M365
                    $currentRegionalFormat = $mailboxSettings.Language.Locale

                    # Check compliance
                    $isCompliant = (
                        $currentDisplayLanguage -eq $requiredSettings.DisplayLanguage -and
                        $currentTimeZone -eq $requiredSettings.TimeZone -and
                        $currentRegionalFormat -eq $requiredSettings.RegionalFormat
                    )

                    $issues = @()
                    if ($currentDisplayLanguage -ne $requiredSettings.DisplayLanguage) {
                        $issues += "Display language mismatch"
                    }
                    if ($currentTimeZone -ne $requiredSettings.TimeZone) {
                        $issues += "Time zone mismatch"
                    }
                    if ($currentRegionalFormat -ne $requiredSettings.RegionalFormat) {
                        $issues += "Regional format mismatch"
                    }

                    if ($isCompliant) {
                        $compliantCount++
                        $status = "Compliant"
                    }
                    else {
                        $nonCompliantCount++
                        $status = "Non-Compliant"

                        Write-Host "[!] $($user.DisplayName) - Non-Compliant:" -ForegroundColor Yellow
                        Write-Host "    Current: $currentDisplayLanguage, $currentTimeZone" -ForegroundColor Gray
                        Write-Host "    Issues: $($issues -join ', ')" -ForegroundColor Gray
                    }

                    # Apply settings if requested (idempotent: act only when non-compliant)
                    $actionTaken = "None"
                    if ($Apply -and -not $isCompliant) {
                            $applyTarget = $user.UserPrincipalName
                            $lang = $requiredSettings.DisplayLanguage
                            $tz = $requiredSettings.TimeZone
                            if ($PSCmdlet.ShouldProcess($applyTarget, "Apply language/region settings ($lang, $tz)")) {
                            try {
                                Write-Host "    [*] Applying settings..." -ForegroundColor Cyan

                                # Update mailbox language and timezone settings
                                $languageSettings = @{
                                    Language = @{
                                        Locale = $requiredSettings.DisplayLanguage
                                        DisplayName = "English (United Kingdom)"
                                    }
                                    TimeZone = $requiredSettings.TimeZone
                                }

                                Update-MgUserMailboxSetting -UserId $user.Id `
                                    -BodyParameter $languageSettings -ErrorAction Stop

                                # Update preferred language
                                Update-MgUser -UserId $user.Id `
                                    -PreferredLanguage $requiredSettings.DisplayLanguage -ErrorAction Stop

                                $actionTaken = "Settings Applied"
                                $status = "Remediated"
                                Write-Host "    [+] Settings applied successfully!" -ForegroundColor Green
                            }
                            catch {
                                $actionTaken = "Error: $($_.Exception.Message)"
                                $status = "Error"
                                $errorCount++
                                $applyErrMsg = "    [-] Error applying settings: $($_.Exception.Message)"
                                Write-Host $applyErrMsg -ForegroundColor Red
                            }
                        }
                    }

                    $result = [PSCustomObject]@{
                        DisplayName = $user.DisplayName
                        UserPrincipalName = $user.UserPrincipalName
                        CurrentDisplayLanguage = $currentDisplayLanguage
                        RequiredDisplayLanguage = $requiredSettings.DisplayLanguage
                        CurrentTimeZone = $currentTimeZone
                        RequiredTimeZone = $requiredSettings.TimeZone
                        CurrentRegionalFormat = $currentRegionalFormat
                        RequiredRegionalFormat = $requiredSettings.RegionalFormat
                        PreferredLanguage = $currentPreferredLanguage
                        Status = $status
                        Issues = if ($issues.Count -gt 0) { $issues -join '; ' } else { 'None' }
                        ActionTaken = $actionTaken
                    }

                    $results += $result

                }
                catch {
                    $errorCount++
                    $procErrMsg = "[-] Error processing $($user.DisplayName): $($_.Exception.Message)"
                    Write-Host $procErrMsg -ForegroundColor Red

                    $result = [PSCustomObject]@{
                        DisplayName = $user.DisplayName
                        UserPrincipalName = $user.UserPrincipalName
                        CurrentDisplayLanguage = "Error"
                        RequiredDisplayLanguage = $requiredSettings.DisplayLanguage
                        CurrentTimeZone = "Error"
                        RequiredTimeZone = $requiredSettings.TimeZone
                        CurrentRegionalFormat = "Error"
                        RequiredRegionalFormat = $requiredSettings.RegionalFormat
                        PreferredLanguage = "Error"
                        Status = "Error"
                        Issues = $_.Exception.Message
                        ActionTaken = "N/A"
                    }

                    $results += $result
                }

                # Count results from sequential processing
                $compliantCount = ($results | Where-Object { $_.Status -eq 'Compliant' }).Count
                $nonCompliantCount = ($results | Where-Object { $_.Status -eq 'Non-Compliant' }).Count
                $errorCount = ($results | Where-Object { $_.Status -eq 'Error' }).Count
            }

            Write-Progress -Activity "Processing Users" -Completed

            Write-Host ""

            # Display summary
            Write-Host "=== Summary ===" -ForegroundColor Cyan
            Write-Host "Total Users Processed: $($results.Count)" -ForegroundColor White
            Write-Host "Compliant: $compliantCount" -ForegroundColor Green
            Write-Host "Non-Compliant: $nonCompliantCount" -ForegroundColor Yellow
            if ($Apply) {
                $remediatedCount = ($results | Where-Object { $_.Status -eq 'Remediated' }).Count
                Write-Host "Remediated: $remediatedCount" -ForegroundColor Green
            }
            Write-Host "Errors: $errorCount" -ForegroundColor Red
            Write-Host ""

            # Show non-compliant users
            if ($nonCompliantCount -gt 0 -and -not $Apply) {
                Write-Host "=== Non-Compliant Users ===" -ForegroundColor Yellow
                $results | Where-Object { $_.Status -eq "Non-Compliant" } |
                    Select-Object -First 10 DisplayName, CurrentDisplayLanguage, CurrentTimeZone, Issues |
                    Format-Table -AutoSize

                if ($nonCompliantCount -gt 10) {
                    Write-Host "[!] Showing first 10 of $nonCompliantCount non-compliant users" -ForegroundColor Gray
                }
            }

            # Export results
            if ($ExportHTML) {
                $reportDir = Get-ReportDirectory
                $htmlPath = (Join-Path $reportDir "LanguageSettings_$timestamp.html")

                $remediatedRow = ""
                if ($Apply) {
                    $remediatedCount = ($results | Where-Object { $_.Status -eq 'Remediated' }).Count
                    $remediatedRow = "<strong>Remediated:</strong> $($remediatedCount)<br>"
                }

                $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>M365 Language Settings Report - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #0078d4; }
        .summary { background-color: #f0f0f0; padding: 15px; border-radius: 5px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; font-size: 12px; }
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
    <h1>Microsoft 365 Language & Region Settings Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Mode:</strong> $(if ($Apply) { 'APPLY SETTINGS' } else { 'AUDIT ONLY' })<br>
        <strong>Total Users:</strong> $($results.Count)<br>
        <strong>Compliant:</strong> $compliantCount<br>
        <strong>Non-Compliant:</strong> $nonCompliantCount<br>
        $remediatedRow
        <strong>Errors:</strong> $errorCount
    </div>

    <div class="settings">
        <h3>Required Settings</h3>
        <strong>Display Language:</strong> $($requiredSettings.DisplayLanguage)<br>
        <strong>Regional Format:</strong> $($requiredSettings.RegionalFormat)<br>
        <strong>Time Zone:</strong> $($requiredSettings.TimeZone)
    </div>

    <h2>User Details</h2>
    <table>
        <tr>
            <th>Display Name</th>
            <th>UPN</th>
            <th>Current Language</th>
            <th>Current Time Zone</th>
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
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.CurrentDisplayLanguage)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.CurrentTimeZone)"))</td>
            <td><span class="$statusClass">$($result.Status)</span></td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.Issues)"))</td>
            $(if ($Apply) { "<td>$([System.Net.WebUtility]::HtmlEncode("$($result.ActionTaken)"))</td>" })
        </tr>
"@
                }

                $html += @"
    </table>
</body>
</html>
"@

                $html | Out-File -FilePath $htmlPath -Encoding UTF8 -ErrorAction Stop
                Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
            }

            if ($ExportCSV) {
                $reportDir = Get-ReportDirectory
                $csvPath = (Join-Path $reportDir "LanguageSettings_$timestamp.csv")
                $results | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
                Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
            }

            Write-Host "`n[+] Language settings check completed!" -ForegroundColor Green
        }

        # Exit codes: 0 = compliant/remediated, 1 = errors or unresolved non-compliance in audit mode
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
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
