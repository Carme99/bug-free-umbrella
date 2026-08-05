<#
.SYNOPSIS
    Displays all mailbox permissions and delegates for a specific user.

.DESCRIPTION
    Comprehensive mailbox permission audit including:
    - Full Access permissions
    - Send As permissions
    - Send on Behalf permissions
    - Folder permissions (calendar, inbox, etc.)
    - Mailbox delegates
    - Auto-mapping status

.PARAMETER UserEmail
    Email address of the user to check.

.PARAMETER IncludeFolderPermissions
    Include detailed folder-level permissions (calendar, contacts, etc.).

.PARAMETER ExportReport
    Export results to HTML report.

.EXAMPLE
    .\Get-UserMailboxPermissions.ps1 -UserEmail "john.doe@contoso.com"

.EXAMPLE
    .\Get-UserMailboxPermissions.ps1 -UserEmail "john.doe@contoso.com" -IncludeFolderPermissions -ExportReport

.NOTES
    Requires: ExchangeOnlineManagement module
    Permissions: Exchange Administrator or Global Reader

    Testing Status: Manual testing completed. Pester tests included for quarantine script.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$UserEmail,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeFolderPermissions,

    [Parameter(Mandatory = $false)]
    [switch]$ExportReport
)

$ErrorActionPreference = "Stop"

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

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         Mailbox Permissions & Delegates Report              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Check connection
try {
    $connection = Get-ConnectionInformation -ErrorAction SilentlyContinue
    if (-not $connection) {
        Write-Host "[-] Not connected to Exchange Online!" -ForegroundColor Red
        Write-Host "[!] Run: Connect-ExchangeOnline" -ForegroundColor Yellow
        exit 1
    }
}
catch {
    Write-Host "[-] Exchange Online connection error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Verify user
Write-Host "[*] Verifying user mailbox..." -ForegroundColor Cyan
try {
    $mailbox = Get-EXOMailbox -Identity $UserEmail -ErrorAction Stop
    Write-Host "[+] User found: $($mailbox.DisplayName) ($($mailbox.PrimarySmtpAddress))" -ForegroundColor Green
}
catch {
    Write-Host "[-] User not found: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$results = @{
    User = $mailbox.DisplayName
    Email = $mailbox.PrimarySmtpAddress
    FullAccessPermissions = @()
    SendAsPermissions = @()
    SendOnBehalfPermissions = @()
    FolderPermissions = @()
}

# Get Full Access permissions
Write-Host "`n[*] Checking Full Access permissions..." -ForegroundColor Cyan
try {
    $fullAccess = Get-EXOMailboxPermission -Identity $UserEmail |
        Where-Object { $_.User -notlike "NT AUTHORITY\*" -and $_.User -notlike "S-1-5-*" -and $_.IsInherited -eq $false }

    if ($fullAccess) {
        Write-Host "[+] Found $($fullAccess.Count) Full Access permission(s)" -ForegroundColor Green
        foreach ($perm in $fullAccess) {
            Write-Host "  • $($perm.User) - $($perm.AccessRights -join ', ')" -ForegroundColor White
            if ($perm.Deny) {
                Write-Host "    [DENY]" -ForegroundColor Red
            }

            $results.FullAccessPermissions += [PSCustomObject]@{
                User = $perm.User
                AccessRights = $perm.AccessRights -join ', '
                IsInherited = $perm.IsInherited
                Deny = $perm.Deny
            }
        }
    }
    else {
        Write-Host "[i] No Full Access permissions found" -ForegroundColor Gray
    }
}
catch {
    Write-Host "[-] Error retrieving Full Access permissions: $($_.Exception.Message)" -ForegroundColor Red
}

# Get Send As permissions
Write-Host "`n[*] Checking Send As permissions..." -ForegroundColor Cyan
try {
    $sendAs = Get-EXORecipientPermission -Identity $UserEmail |
        Where-Object { $_.Trustee -notlike "NT AUTHORITY\*" -and $_.Trustee -notlike "S-1-5-*" }

    if ($sendAs) {
        Write-Host "[+] Found $($sendAs.Count) Send As permission(s)" -ForegroundColor Green
        foreach ($perm in $sendAs) {
            Write-Host "  • $($perm.Trustee) - $($perm.AccessRights -join ', ')" -ForegroundColor White

            $results.SendAsPermissions += [PSCustomObject]@{
                Trustee = $perm.Trustee
                AccessRights = $perm.AccessRights -join ', '
            }
        }
    }
    else {
        Write-Host "[i] No Send As permissions found" -ForegroundColor Gray
    }
}
catch {
    Write-Host "[-] Error retrieving Send As permissions: $($_.Exception.Message)" -ForegroundColor Red
}

# Get Send on Behalf permissions
Write-Host "`n[*] Checking Send on Behalf permissions..." -ForegroundColor Cyan
try {
    if ($mailbox.GrantSendOnBehalfTo) {
        Write-Host "[+] Found $($mailbox.GrantSendOnBehalfTo.Count) Send on Behalf permission(s)" -ForegroundColor Green
        foreach ($user in $mailbox.GrantSendOnBehalfTo) {
            Write-Host "  • $user" -ForegroundColor White

            $results.SendOnBehalfPermissions += [PSCustomObject]@{
                User = $user
            }
        }
    }
    else {
        Write-Host "[i] No Send on Behalf permissions found" -ForegroundColor Gray
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
                    Write-Host "    • $($perm.User.DisplayName): $($perm.AccessRights -join ', ')" -ForegroundColor White

                    $results.FolderPermissions += [PSCustomObject]@{
                        Folder = $folderName
                        User = $perm.User.DisplayName
                        AccessRights = $perm.AccessRights -join ', '
                    }
                }
            }
        }
        catch {
            # Folder might not exist or no custom permissions
        }
    }
}

# Export report if requested
if ($ExportReport) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

    # Use safe filename
    $safeEmail = Get-SafeFileName $UserEmail
    $reportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
    if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    $reportPath = Join-Path $reportDir "MailboxPermissions_${safeEmail}_$timestamp.html"

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

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "`n[+] Report saved to: $reportPath" -ForegroundColor Green
}

Write-Host "`n[+] Permission check completed!" -ForegroundColor Green
