<#
.SYNOPSIS
    Audit mailbox permissions and delegates assigned to a specific Exchange Online user mailbox.

.DESCRIPTION
    Performs a comprehensive mailbox permission audit for a single user, covering Full Access,
    Send As, Send on Behalf, and optionally folder-level permissions (Calendar, Inbox, Contacts,
    Tasks). Built-in and inherited permissions are filtered out so only explicit grants are shown.
    Results are written to the console and can optionally be exported as an HTML report. This is
    a read-only detection script: it never modifies mailbox state.

.PARAMETER UserEmail
    Email address of the user whose mailbox permissions are audited.

.PARAMETER IncludeFolderPermissions
    Include detailed folder-level permissions (Calendar, Inbox, Contacts, Tasks) in the audit.

.PARAMETER ExportReport
    Export the audit results to an HTML report under the Documents\Reports folder.

.EXAMPLE
    PS C:\> .\Get-UserMailboxPermissions.ps1 -UserEmail "john.doe@contoso.com"

    Audits mailbox and delegate permissions for john.doe@contoso.com.

.EXAMPLE
    PS C:\> .\Get-UserMailboxPermissions.ps1 -UserEmail "john.doe@contoso.com" -IncludeFolderPermissions -ExportReport

    Audits all permission levels including folder permissions and saves an HTML report.

.NOTES
    File Name  : Get-UserMailboxPermissions.ps1
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
    [switch]$IncludeFolderPermissions,

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
        Write-Host "║         Mailbox Permissions & Delegates Report              ║" -ForegroundColor Cyan
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
            $mailbox = Get-EXOMailbox -Identity $UserEmail -ErrorAction Stop
            Write-Host "[+] User found: $($mailbox.DisplayName) ($($mailbox.PrimarySmtpAddress))" -ForegroundColor Green
        }
        catch {
            Write-Host "[-] User not found: $($_.Exception.Message)" -ForegroundColor Red
            return 1
        }

        $results = @{
            User                    = $mailbox.DisplayName
            Email                   = $mailbox.PrimarySmtpAddress
            FullAccessPermissions   = @()
            SendAsPermissions       = @()
            SendOnBehalfPermissions = @()
            FolderPermissions       = @()
        }

        # Get Full Access permissions
        Write-Host "`n[*] Checking Full Access permissions..." -ForegroundColor Cyan
        try {
            $fullAccess = Get-EXOMailboxPermission -Identity $UserEmail -ErrorAction Stop |
                Where-Object {
                    $_.User -notlike "NT AUTHORITY\*" -and
                    $_.User -notlike "S-1-5-*" -and
                    $_.IsInherited -eq $false
                }

            if ($fullAccess) {
                Write-Host "[+] Found $($fullAccess.Count) Full Access permission(s)" -ForegroundColor Green
                foreach ($perm in $fullAccess) {
                    Write-Host "  • $($perm.User) - $($perm.AccessRights -join ', ')" -ForegroundColor White
                    if ($perm.Deny) {
                        Write-Host "    [DENY]" -ForegroundColor Red
                    }

                    $results.FullAccessPermissions += [PSCustomObject]@{
                        User         = $perm.User
                        AccessRights = $perm.AccessRights -join ', '
                        IsInherited  = $perm.IsInherited
                        Deny         = $perm.Deny
                    }
                }
            }
            else {
                Write-Host "[*] No Full Access permissions found" -ForegroundColor Cyan
            }
        }
        catch {
            Write-Host "[-] Error retrieving Full Access permissions: $($_.Exception.Message)" -ForegroundColor Red
        }

        # Get Send As permissions
        Write-Host "`n[*] Checking Send As permissions..." -ForegroundColor Cyan
        try {
            $sendAs = Get-EXORecipientPermission -Identity $UserEmail -ErrorAction Stop |
                Where-Object { $_.Trustee -notlike "NT AUTHORITY\*" -and $_.Trustee -notlike "S-1-5-*" }

            if ($sendAs) {
                Write-Host "[+] Found $($sendAs.Count) Send As permission(s)" -ForegroundColor Green
                foreach ($perm in $sendAs) {
                    Write-Host "  • $($perm.Trustee) - $($perm.AccessRights -join ', ')" -ForegroundColor White

                    $results.SendAsPermissions += [PSCustomObject]@{
                        Trustee      = $perm.Trustee
                        AccessRights = $perm.AccessRights -join ', '
                    }
                }
            }
            else {
                Write-Host "[*] No Send As permissions found" -ForegroundColor Cyan
            }
        }
        catch {
            Write-Host "[-] Error retrieving Send As permissions: $($_.Exception.Message)" -ForegroundColor Red
        }

        # Get Send on Behalf permissions
        Write-Host "`n[*] Checking Send on Behalf permissions..." -ForegroundColor Cyan
        try {
            if ($mailbox.GrantSendOnBehalfTo) {
                Write-Host "[+] Found $($mailbox.GrantSendOnBehalfTo.Count) Send on Behalf permission(s)" `
                    -ForegroundColor Green
                foreach ($user in $mailbox.GrantSendOnBehalfTo) {
                    Write-Host "  • $user" -ForegroundColor White

                    $results.SendOnBehalfPermissions += [PSCustomObject]@{
                        User = $user
                    }
                }
            }
            else {
                Write-Host "[*] No Send on Behalf permissions found" -ForegroundColor Cyan
            }
        }
        catch {
            Write-Host "[-] Error retrieving Send on Behalf permissions: $($_.Exception.Message)" -ForegroundColor Red
        }

        # Get folder permissions if requested
        if ($IncludeFolderPermissions) {
            Write-Host "`n[*] Checking folder-level permissions..." -ForegroundColor Cyan

            # Note: Folder names are in English. Non-English mailboxes may require localized names.
            $folders = @("Calendar", "Inbox", "Contacts", "Tasks")

            foreach ($folderName in $folders) {
                try {
                    $folderPath = "${UserEmail}:\$folderName"
                    $folderPerms = Get-EXOMailboxFolderPermission -Identity $folderPath -ErrorAction Stop |
                        Where-Object { $_.User -notlike "Default" -and $_.User -notlike "Anonymous" }

                    if ($folderPerms) {
                        Write-Host "`n  [$folderName]" -ForegroundColor Yellow
                        foreach ($perm in $folderPerms) {
                            Write-Host "    • $($perm.User.DisplayName): $($perm.AccessRights -join ', ')" `
                                -ForegroundColor White

                            $results.FolderPermissions += [PSCustomObject]@{
                                Folder       = $folderName
                                User         = $perm.User.DisplayName
                                AccessRights = $perm.AccessRights -join ', '
                            }
                        }
                    }
                }
                catch {
                    Write-Verbose "Handled exception: $($_.Exception.Message)"
                }
            }
        }

        # Export report if requested
        if ($ExportReport) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

            # Use safe filename
            $safeEmailFile = Get-SafeFileName $UserEmail
            $reportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
            if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
                New-Item -ItemType Directory -Path $reportDir -Force -ErrorAction Stop | Out-Null
            }
            $reportPath = Join-Path $reportDir "MailboxPermissions_${safeEmailFile}_$timestamp.html"

            # Encode user data
            $safeDisplayName = ConvertTo-HtmlSafe $mailbox.DisplayName
            $safeEmail = ConvertTo-HtmlSafe $mailbox.PrimarySmtpAddress

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Mailbox Permissions Report - $safeDisplayName</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; }
        h1 { color: #0078d4; }
        h2 { color: #505050; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th { background-color: #0078d4; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <h1>Mailbox Permissions Report</h1>
    <p><strong>User:</strong> $safeDisplayName ($safeEmail)</p>
    <p><strong>Generated:</strong> $(Get-Date)</p>

    <h2>Full Access Permissions</h2>
    <table>
        <tr><th>User</th><th>Access Rights</th></tr>
"@

            foreach ($perm in $results.FullAccessPermissions) {
                $safeUser = ConvertTo-HtmlSafe $perm.User
                $safeRights = ConvertTo-HtmlSafe $perm.AccessRights
                $html += "<tr><td>$safeUser</td><td>$safeRights</td></tr>"
            }

            $html += @"
    </table>

    <h2>Send As Permissions</h2>
    <table>
        <tr><th>Trustee</th><th>Access Rights</th></tr>
"@

            foreach ($perm in $results.SendAsPermissions) {
                $safeTrustee = ConvertTo-HtmlSafe $perm.Trustee
                $safeRights = ConvertTo-HtmlSafe $perm.AccessRights
                $html += "<tr><td>$safeTrustee</td><td>$safeRights</td></tr>"
            }

            $html += "</table></body></html>"

            $html | Out-File -FilePath $reportPath -Encoding utf8 -ErrorAction Stop
            Write-Host "`n[+] Report saved to: $reportPath" -ForegroundColor Green
        }

        Write-Host "`n[+] Permission check completed!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
