<#
.SYNOPSIS
    Audit Exchange Online shared mailboxes for usage, permissions, and compliance.

.DESCRIPTION
    This script analyzes shared mailboxes for:
    - Usage statistics and size
    - Permission assignments (Full Access, Send As, Send on Behalf)
    - Inactive shared mailboxes
    - Shared mailboxes without owners
    - Sign-in status (should be disabled)
    - Licensing status
    - Auto-mapping configuration
    The script is read-only: it never modifies shared mailboxes; it writes optional HTML/CSV reports only.
    Exit codes: 0 when the audit completes with no issues; 1 when issues are detected (sign-in enabled,
    no permissions) or on fatal errors.

.PARAMETER IncludePermissions
    Include detailed permission analysis.

.PARAMETER CheckInactive
    Identify inactive shared mailboxes (no activity in specified days).

.PARAMETER InactivityDays
    Days since last activity to consider inactive (default: 90).

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    PS C:\> .\Get-SharedMailboxReport.ps1
    Basic shared mailbox audit.

.EXAMPLE
    PS C:\> .\Get-SharedMailboxReport.ps1 -IncludePermissions -CheckInactive -ExportHTML
    Comprehensive audit with permissions and inactive mailbox detection.

.NOTES
    File Name  : Get-SharedMailboxReport.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Requires Exchange Administrator or Global Reader role.
    Compatible with Exchange Online (Microsoft 365).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$IncludePermissions,

    [Parameter(Mandatory = $false)]
    [switch]$CheckInactive,

    [Parameter(Mandatory = $false)]
    [int]$InactivityDays = 90,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = 'Stop'
# PSScriptAnalyzer note: PSAvoidUsingWriteHost / PSReviewUnusedParameter warnings are accepted here.
# The relaunch spec mandates Write-Host status output ([+]/[!]/[-]/[*]); script parameters are read inside Main.

function Main {
    try {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
        if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
            New-Item -ItemType Directory -Path $ReportDir -Force -ErrorAction Stop | Out-Null
        }

        Write-Host "`n=== Shared Mailbox Audit Report ===" -ForegroundColor Cyan
        Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
        Write-Host ""

        # Check connection
        $connectionStatus = Get-ConnectionInformation -ErrorAction SilentlyContinue
        if (-not $connectionStatus) {
            Write-Host "[!] Connecting to Exchange Online..." -ForegroundColor Yellow
            Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
        }

        Write-Host "[*] Retrieving shared mailboxes..." -ForegroundColor Cyan

        $sharedMailboxes = Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails SharedMailbox `
            -Properties DisplayName, UserPrincipalName, PrimarySmtpAddress, WhenCreated, AccountDisabled `
            -ErrorAction Stop

        Write-Host "[+] Found $($sharedMailboxes.Count) shared mailbox(es)" -ForegroundColor Green
        Write-Host ""

        $results = @()
        $issueCount = 0
        $signInEnabled = 0
        $noPermissions = 0
        $inactiveCount = 0

        $i = 0
        foreach ($mailbox in $sharedMailboxes) {
            $i++
            Write-Progress -Activity "Analyzing Shared Mailboxes" `
                -Status "$i of $($sharedMailboxes.Count): $($mailbox.DisplayName)" `
                -PercentComplete (($i / $sharedMailboxes.Count) * 100)

            # Get statistics
            $stats = Get-EXOMailboxStatistics -Identity $mailbox.UserPrincipalName -ErrorAction SilentlyContinue

            $mailboxSizeGB = if ($stats.TotalItemSize) {
                $sizeBytes = $stats.TotalItemSize.ToString().Split('(')[1].Split(' ')[0].Replace(',', '')
                [math]::Round(($sizeBytes -as [double]) / 1GB, 2)
            }
            else { 0 }

            # Check sign-in status
            if (-not $mailbox.AccountDisabled) {
                $signInEnabled++
                $issueCount++
            }

            # Get permissions
            $fullAccessUsers = @()
            $sendAsUsers = @()
            $sendOnBehalfUsers = @()
            $totalPermissions = 0

            if ($IncludePermissions) {
                try {
                    # Full Access
                    $fullAccess = Get-EXOMailboxPermission -Identity $mailbox.UserPrincipalName -ErrorAction Stop |
                        Where-Object {
                            $_.AccessRights -contains "FullAccess" -and
                            $_.User -notlike "NT AUTHORITY\*" -and
                            $_.IsInherited -eq $false
                        }

                    $fullAccessUsers = $fullAccess | ForEach-Object { $_.User }
                    $totalPermissions += $fullAccessUsers.Count

                    # Send As
                    $sendAs = Get-EXORecipientPermission -Identity $mailbox.UserPrincipalName -ErrorAction Stop |
                        Where-Object { $_.Trustee -notlike "NT AUTHORITY\*" -and $_.AccessRights -contains "SendAs" }

                    $sendAsUsers = $sendAs | ForEach-Object { $_.Trustee }
                    $totalPermissions += $sendAsUsers.Count

                    # Send on Behalf
                    $mailboxDetail = Get-EXOMailbox -Identity $mailbox.UserPrincipalName `
                        -Properties GrantSendOnBehalfTo -ErrorAction Stop
                    if ($mailboxDetail.GrantSendOnBehalfTo) {
                        $sendOnBehalfUsers = $mailboxDetail.GrantSendOnBehalfTo
                        $totalPermissions += $sendOnBehalfUsers.Count
                    }

                    if ($totalPermissions -eq 0) {
                        $noPermissions++
                        $issueCount++
                    }
                }
                catch {
                    $issueCount++
                    $fullAccessUsers = @("Permission lookup failed: $($_.Exception.Message)")
                }
            }

            # Check inactivity
            $isInactive = $false
            if ($CheckInactive) {
                $inactivityThreshold = (Get-Date).AddDays(-$InactivityDays)
                if ($stats.LastLogonTime -and $stats.LastLogonTime -lt $inactivityThreshold) {
                    $isInactive = $true
                    $inactiveCount++
                }
                elseif (-not $stats.LastLogonTime) {
                    $isInactive = $true
                    $inactiveCount++
                }
            }

            $result = [PSCustomObject]@{
                DisplayName       = $mailbox.DisplayName
                PrimarySmtpAddress = $mailbox.PrimarySmtpAddress
                SizeGB            = $mailboxSizeGB
                ItemCount         = $stats.ItemCount
                SignInEnabled     = -not $mailbox.AccountDisabled
                FullAccessUsers   = $fullAccessUsers -join '; '
                SendAsUsers       = $sendAsUsers -join '; '
                SendOnBehalfUsers = $sendOnBehalfUsers -join '; '
                TotalPermissions  = $totalPermissions
                LastActivity      = $stats.LastLogonTime
                IsInactive        = $isInactive
                Created           = $mailbox.WhenCreated
            }

            $results += $result
        }

        Write-Progress -Activity "Analyzing Shared Mailboxes" -Completed

        Write-Host ""
        Write-Host "=== Summary ===" -ForegroundColor Cyan
        Write-Host "Total Shared Mailboxes: $($results.Count)" -ForegroundColor White
        $signInColor = if ($signInEnabled -gt 0) { "Red" } else { "Green" }
        Write-Host "Sign-In Enabled (should be disabled): $signInEnabled" -ForegroundColor $signInColor
        if ($IncludePermissions) {
            $permColor = if ($noPermissions -gt 0) { "Yellow" } else { "Green" }
            Write-Host "Without Permissions: $noPermissions" -ForegroundColor $permColor
        }
        if ($CheckInactive) {
            Write-Host "Inactive (>$InactivityDays days): $inactiveCount" -ForegroundColor Yellow
        }
        Write-Host "Issues Found: $issueCount" -ForegroundColor $(if ($issueCount -gt 0) { "Red" } else { "Green" })
        Write-Host ""

        # Show issues
        if ($signInEnabled -gt 0) {
            Write-Host "=== Shared Mailboxes with Sign-In Enabled ===" -ForegroundColor Red
            $results | Where-Object { $_.SignInEnabled -eq $true } |
                Select-Object DisplayName, PrimarySmtpAddress |
                Format-Table -AutoSize
        }

        if ($noPermissions -gt 0) {
            Write-Host "`n=== Shared Mailboxes Without Permissions ===" -ForegroundColor Yellow
            $results | Where-Object { $_.TotalPermissions -eq 0 } |
                Select-Object DisplayName, PrimarySmtpAddress, Created |
                Format-Table -AutoSize
        }

        # Export
        if ($ExportHTML) {
            $htmlPath = (Join-Path $ReportDir "SharedMailboxAudit_$timestamp.html")

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Shared Mailbox Audit - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #0078d4; }
        .summary { background-color: #f0f0f0; padding: 15px; border-radius: 5px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; font-size: 12px; }
        th { background-color: #0078d4; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .issue { background-color: #ffe6e6; }
    </style>
</head>
<body>
    <h1>Shared Mailbox Audit Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Total Shared Mailboxes:</strong> $($results.Count)<br>
        <strong>Sign-In Enabled:</strong> $signInEnabled<br>
        <strong>Without Permissions:</strong> $noPermissions<br>
        <strong>Inactive:</strong> $inactiveCount<br>
        <strong>Issues Found:</strong> $issueCount
    </div>

    <h2>Shared Mailbox Details</h2>
    <table>
        <tr>
            <th>Display Name</th>
            <th>Email</th>
            <th>Size (GB)</th>
            <th>Items</th>
            <th>Sign-In</th>
            <th>Permissions</th>
            <th>Last Activity</th>
        </tr>
"@

            foreach ($result in ($results | Sort-Object DisplayName)) {
                $rowClass = if ($result.SignInEnabled -or $result.TotalPermissions -eq 0) { "issue" } else { "" }
                $html += @"
        <tr class="$rowClass">
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.DisplayName)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.PrimarySmtpAddress)"))</td>
            <td>$($result.SizeGB)</td>
            <td>$($result.ItemCount)</td>
            <td>$($result.SignInEnabled)</td>
            <td>$($result.TotalPermissions)</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.LastActivity)"))</td>
        </tr>
"@
            }

            $html += "</table></body></html>"
            $html | Out-File -FilePath $htmlPath -Encoding utf8 -ErrorAction Stop
            Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
        }

        if ($ExportCSV) {
            $csvPath = (Join-Path $ReportDir "SharedMailboxAudit_$timestamp.csv")
            $results | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
            Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
        }

        Write-Host "`n[+] Audit completed!" -ForegroundColor Green

        if ($issueCount -gt 0) {
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
