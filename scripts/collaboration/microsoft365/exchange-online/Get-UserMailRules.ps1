<#
.SYNOPSIS
    Audit mail forwarding rules, inbox rules, and automatic replies for a specific user.

.DESCRIPTION
    Produces a comprehensive mail rule audit for a single mailbox, covering mailbox-level
    forwarding (internal and external), client-side inbox rules, and automatic reply (Out of
    Office) status. Active forwarding or deletion actions are flagged as security warnings so
    unauthorized redirection is easy to spot. Results are written to the console and can
    optionally be exported as an HTML report. This is a read-only detection script: it never
    modifies mailbox state.

.PARAMETER UserEmail
    Email address of the user to check.

.PARAMETER ShowDisabledRules
    Include disabled rules in the output.

.PARAMETER ExportReport
    Export results to an HTML report under the Documents\Reports folder.

.EXAMPLE
    PS C:\> .\Get-UserMailRules.ps1 -UserEmail "john.doe@contoso.com"

    Audits forwarding, inbox rules, and auto-replies for john.doe@contoso.com.

.EXAMPLE
    PS C:\> .\Get-UserMailRules.ps1 -UserEmail "john.doe@contoso.com" -ShowDisabledRules -ExportReport

    Includes disabled rules in the audit and saves an HTML report.

.NOTES
    File Name  : Get-UserMailRules.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Requires: ExchangeOnlineManagement module
    Permissions: Exchange Administrator or Global Reader
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$UserEmail,

    [Parameter(Mandatory = $false)]
    [switch]$ShowDisabledRules,

    [Parameter(Mandatory = $false)]
    [switch]$ExportReport
)

$ErrorActionPreference = 'Stop'
# ScriptAnalyzer note: PSAvoidUsingWriteHost is accepted by design - the Bug-Free Umbrella output
# standard (RELAUNCH-SPEC section 3 / AGENTS.md) mandates Write-Host with prefix/color output.
# PSReviewUnusedParameter findings are false positives: parameters are read inside Main via the
# script scope. PSUseSingularNouns findings reflect legacy function nouns retained for conformance.

# Helper function to encode HTML and prevent XSS
function ConvertTo-HtmlSafe {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    $Text = $Text.Replace('&', '&amp;')
    $Text = $Text.Replace('<', '&lt;')
    $Text = $Text.Replace('>', '&gt;')
    $Text = $Text.Replace('"', '&quot;')
    $Text = $Text.Replace("'", '&#39;')
    return $Text
}

# Helper function to sanitize filenames
function Get-SafeFileName {
    param([string]$FileName)
    if ([string]::IsNullOrWhiteSpace($FileName)) { return "output" }
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $safe = $FileName
    foreach ($char in $invalid) {
        $safe = $safe.Replace($char, '_')
    }
    $safe = $safe.Replace('..', '_').Replace('/', '_').Replace('\', '_')
    if ($safe.Length -gt 100) {
        $safe = $safe.Substring(0, 100)
    }
    return $safe
}

function Main {
    try {
        Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║            Mail Rules & Forwarding Report                   ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

        # Check connection
        try {
            $connection = Get-ConnectionInformation -ErrorAction SilentlyContinue
            if (-not $connection) {
                Write-Host "[-] Not connected to Exchange Online!" -ForegroundColor Red
                Write-Host "[!] Run: Connect-ExchangeOnline" -ForegroundColor Yellow
                return 1
            }
        }
        catch {
            Write-Host "[-] Exchange Online connection error: $($_.Exception.Message)" -ForegroundColor Red
            return 1
        }

        # Verify user
        Write-Host "[*] Verifying user mailbox..." -ForegroundColor Cyan
        try {
            $mailbox = Get-EXOMailbox -Identity $UserEmail `
                -Properties ForwardingAddress, ForwardingSmtpAddress, DeliverToMailboxAndForward `
                -ErrorAction Stop
            Write-Host "[+] User found: $($mailbox.DisplayName) ($($mailbox.PrimarySmtpAddress))" -ForegroundColor Green
        }
        catch {
            Write-Host "[-] User not found: $($_.Exception.Message)" -ForegroundColor Red
            return 1
        }

        $results = @{
            User             = $mailbox.DisplayName
            Email            = $mailbox.PrimarySmtpAddress
            MailboxForwarding = @()
            InboxRules       = @()
            AutoReply        = @{}
        }

        # Check mailbox-level forwarding
        Write-Host "`n[*] Checking mailbox forwarding settings..." -ForegroundColor Cyan

        $forwardingEnabled = $false

        if ($mailbox.ForwardingAddress) {
            Write-Host "[!] FORWARDING DETECTED - Internal Address" -ForegroundColor Yellow
            Write-Host "  • Forwarding To: $($mailbox.ForwardingAddress)" -ForegroundColor Yellow
            Write-Host "  • Deliver to Mailbox: $($mailbox.DeliverToMailboxAndForward)" -ForegroundColor White

            $results.MailboxForwarding += [PSCustomObject]@{
                Type              = "Internal"
                ForwardTo         = $mailbox.ForwardingAddress
                DeliverToMailbox  = $mailbox.DeliverToMailboxAndForward
            }
            $forwardingEnabled = $true
        }

        if ($mailbox.ForwardingSmtpAddress) {
            Write-Host "[!] FORWARDING DETECTED - External Address" -ForegroundColor Yellow
            Write-Host "  • Forwarding To: $($mailbox.ForwardingSmtpAddress)" -ForegroundColor Yellow
            Write-Host "  • Deliver to Mailbox: $($mailbox.DeliverToMailboxAndForward)" -ForegroundColor White

            $results.MailboxForwarding += [PSCustomObject]@{
                Type              = "External"
                ForwardTo         = $mailbox.ForwardingSmtpAddress
                DeliverToMailbox  = $mailbox.DeliverToMailboxAndForward
            }
            $forwardingEnabled = $true
        }

        if (-not $forwardingEnabled) {
            Write-Host "[+] No mailbox-level forwarding configured" -ForegroundColor Green
        }

        # Check inbox rules
        Write-Host "`n[*] Checking inbox rules..." -ForegroundColor Cyan
        try {
            $inboxRules = Get-InboxRule -Mailbox $UserEmail -ErrorAction Stop

            if ($inboxRules) {
                $activeRules = @($inboxRules | Where-Object { $_.Enabled -eq $true })
                $disabledRules = @($inboxRules | Where-Object { $_.Enabled -eq $false })

                $ruleTotal = @($inboxRules).Count
                $ruleSummary = "[+] Found $($ruleTotal) inbox rule(s) " +
                    "($($activeRules.Count) enabled, $($disabledRules.Count) disabled)"
                Write-Host $ruleSummary -ForegroundColor Green

                foreach ($rule in $inboxRules) {
                    if (-not $rule.Enabled -and -not $ShowDisabledRules) {
                        continue
                    }

                    $ruleColor = if ($rule.Enabled) { "White" } else { "Gray" }
                    $statusText = if ($rule.Enabled) { "" } else { " [DISABLED]" }

                    Write-Host "`n  Rule: $($rule.Name)$statusText" -ForegroundColor $ruleColor

                    # Show conditions
                    if ($rule.From) {
                        Write-Host "    Condition: From $($rule.From -join ', ')" -ForegroundColor Gray
                    }
                    if ($rule.SubjectContainsWords) {
                        Write-Host "    Condition: Subject contains '$($rule.SubjectContainsWords -join ', ')'" `
                            -ForegroundColor Gray
                    }
                    if ($rule.BodyContainsWords) {
                        Write-Host "    Condition: Body contains '$($rule.BodyContainsWords -join ', ')'" `
                            -ForegroundColor Gray
                    }

                    # Show actions
                    if ($rule.ForwardTo) {
                        Write-Host "    Action: Forward to $($rule.ForwardTo -join ', ')" -ForegroundColor Yellow
                    }
                    if ($rule.ForwardAsAttachmentTo) {
                        Write-Host "    Action: Forward as attachment to $($rule.ForwardAsAttachmentTo -join ', ')" `
                            -ForegroundColor Yellow
                    }
                    if ($rule.RedirectTo) {
                        Write-Host "    Action: Redirect to $($rule.RedirectTo -join ', ')" -ForegroundColor Yellow
                    }
                    if ($rule.MoveToFolder) {
                        Write-Host "    Action: Move to folder '$($rule.MoveToFolder)'" -ForegroundColor Gray
                    }
                    if ($rule.DeleteMessage) {
                        Write-Host "    Action: Delete message" -ForegroundColor Red
                    }
                    if ($rule.MarkAsRead) {
                        Write-Host "    Action: Mark as read" -ForegroundColor Gray
                    }

                    $results.InboxRules += [PSCustomObject]@{
                        Name       = $rule.Name
                        Enabled    = $rule.Enabled
                        Priority   = $rule.Priority
                        Conditions = (@($rule.From) + @($rule.SubjectContainsWords) +
                            @($rule.BodyContainsWords) | Where-Object { $_ } | Out-String).Trim()
                        Actions    = @(
                            if ($rule.ForwardTo) { "Forward to: $($rule.ForwardTo -join ', ')" }
                            if ($rule.RedirectTo) { "Redirect to: $($rule.RedirectTo -join ', ')" }
                            if ($rule.MoveToFolder) { "Move to: $($rule.MoveToFolder)" }
                            if ($rule.DeleteMessage) { "Delete" }
                        ) -join '; '
                    }
                }

                # Warning for potential security issues
                $suspiciousRules = @($inboxRules | Where-Object {
                    $_.Enabled -and (
                        $_.ForwardTo -or
                        $_.ForwardAsAttachmentTo -or
                        $_.RedirectTo -or
                        $_.DeleteMessage
                    )
                })

                if ($suspiciousRules.Count -gt 0) {
                    Write-Host "`n[!] WARNING: Found $($suspiciousRules.Count) active rule(s) with" `
                        "forwarding or deletion actions" -ForegroundColor Yellow
                    Write-Host "[!] Review these rules for potential security concerns" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "[*] No inbox rules found" -ForegroundColor Cyan
            }
        }
        catch {
            Write-Host "[-] Error retrieving inbox rules: $($_.Exception.Message)" -ForegroundColor Red
        }

        # Check automatic replies (Out of Office)
        Write-Host "`n[*] Checking automatic reply settings..." -ForegroundColor Cyan
        try {
            $autoReply = Get-MailboxAutoReplyConfiguration -Identity $UserEmail -ErrorAction Stop

            if ($autoReply.AutoReplyState -ne "Disabled") {
                Write-Host "[!] Automatic Replies: ENABLED" -ForegroundColor Yellow
                Write-Host "  • State: $($autoReply.AutoReplyState)" -ForegroundColor White
                Write-Host "  • Start Time: $($autoReply.StartTime)" -ForegroundColor White
                Write-Host "  • End Time: $($autoReply.EndTime)" -ForegroundColor White

                if ($autoReply.InternalMessage) {
                    Write-Host "  • Internal Message Set: Yes" -ForegroundColor Gray
                }
                if ($autoReply.ExternalMessage) {
                    Write-Host "  • External Message Set: Yes" -ForegroundColor Gray
                }

                $results.AutoReply = @{
                    Enabled   = $true
                    State     = $autoReply.AutoReplyState
                    StartTime = $autoReply.StartTime
                    EndTime   = $autoReply.EndTime
                }
            }
            else {
                Write-Host "[+] Automatic Replies: Disabled" -ForegroundColor Green
                $results.AutoReply = @{
                    Enabled = $false
                }
            }
        }
        catch {
            Write-Host "[-] Error retrieving automatic reply settings: $($_.Exception.Message)" -ForegroundColor Red
        }

        # Summary
        Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                         SUMMARY                              ║" -ForegroundColor Cyan
        Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
        $forwardingStatus = if ($forwardingEnabled) { 'ACTIVE' } else { 'None' }

        $forwardingColor = if ($forwardingEnabled) { 'Yellow' } else { 'Green' }

        Write-Host "║ Mailbox Forwarding : $forwardingStatus" -ForegroundColor $forwardingColor
        Write-Host "║ Active Inbox Rules : $($results.InboxRules.Count)" -ForegroundColor White
        $autoReplyStatus = if ($results.AutoReply.Enabled) { 'Enabled' } else { 'Disabled' }

        $autoReplyColor = if ($results.AutoReply.Enabled) { 'Yellow' } else { 'Green' }

        Write-Host "║ Auto-Reply Status  : $autoReplyStatus" -ForegroundColor $autoReplyColor
        Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

        # Export report if requested
        if ($ExportReport) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

            # Use safe filename
            $safeEmailFile = Get-SafeFileName $UserEmail
            $reportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
            if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
                New-Item -ItemType Directory -Path $reportDir -Force -ErrorAction Stop | Out-Null
            }
            $reportPath = Join-Path $reportDir "MailRules_${safeEmailFile}_$timestamp.html"

            # Encode user data
            $safeDisplayName = ConvertTo-HtmlSafe $mailbox.DisplayName
            $safeEmail = ConvertTo-HtmlSafe $mailbox.PrimarySmtpAddress

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Mail Rules Report - $safeDisplayName</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; }
        h1 { color: #0078d4; }
        h2 { color: #505050; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th { background-color: #0078d4; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .warning { background-color: #fff4e5; border-left: 4px solid #ff8c00; padding: 10px; margin: 10px 0; }
        .enabled { color: #107c10; font-weight: bold; }
        .disabled { color: #666; }
    </style>
</head>
<body>
    <h1>Mail Rules & Forwarding Report</h1>
    <p><strong>User:</strong> $($mailbox.DisplayName) ($($mailbox.PrimarySmtpAddress))</p>
    <p><strong>Generated:</strong> $(Get-Date)</p>

    <h2>Mailbox Forwarding</h2>
"@

            if ($results.MailboxForwarding.Count -gt 0) {
                $html += "<div class='warning'><strong>⚠ Forwarding Enabled</strong></div>"
                $html += "<table><tr><th>Type</th><th>Forward To</th><th>Deliver to Mailbox</th></tr>"
                foreach ($fwd in $results.MailboxForwarding) {
                    $safeType = ConvertTo-HtmlSafe $fwd.Type
                    $safeForwardTo = ConvertTo-HtmlSafe $fwd.ForwardTo
                    $safeDeliver = ConvertTo-HtmlSafe $fwd.DeliverToMailbox
                    $html += "<tr><td>$safeType</td><td>$safeForwardTo</td><td>$safeDeliver</td></tr>"
                }
                $html += "</table>"
            }
            else {
                $html += "<p>No mailbox forwarding configured</p>"
            }

            $html += "<h2>Inbox Rules</h2>"

            if ($results.InboxRules.Count -gt 0) {
                $html += "<table><tr><th>Rule Name</th><th>Status</th><th>Priority</th><th>Actions</th></tr>"
                foreach ($rule in $results.InboxRules) {
                    $statusClass = if ($rule.Enabled) { "enabled" } else { "disabled" }
                    $statusText = if ($rule.Enabled) { "Enabled" } else { "Disabled" }
                    $safeName = ConvertTo-HtmlSafe $rule.Name
                    $safePriority = ConvertTo-HtmlSafe $rule.Priority
                    $safeActions = ConvertTo-HtmlSafe $rule.Actions
                    $html += "<tr><td>$safeName</td><td class='$statusClass'>$statusText</td>" +
                        "<td>$safePriority</td><td>$safeActions</td></tr>"
                }
                $html += "</table>"
            }
            else {
                $html += "<p>No inbox rules found</p>"
            }

            $html += "</body></html>"

            $html | Out-File -FilePath $reportPath -Encoding utf8 -ErrorAction Stop
            Write-Host "`n[+] Report saved to: $reportPath" -ForegroundColor Green
        }

        Write-Host "`n[+] Mail rules check completed!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
