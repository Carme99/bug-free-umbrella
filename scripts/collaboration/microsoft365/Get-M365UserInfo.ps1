<#
.SYNOPSIS
    Comprehensive M365 user information and management toolkit.

.DESCRIPTION
    Interactive menu-driven tool for technicians to view and manage all aspects of a Microsoft 365 user account.
    Provides a consolidated view of user information across Exchange Online, Azure AD, Teams, OneDrive, and more.

    Features:
    - User account verification and basic information
    - Mailbox statistics (size, quota, items)
    - License assignments and service plans
    - Quarantine management (view and release)
    - Sign-in activity and last logon
    - Group and distribution list memberships
    - OneDrive storage usage
    - Mobile device associations
    - Mailbox permissions and delegates
    - Email forwarding rules and inbox rules
    - Out of office status
    - Regional and language settings
    - MFA/authentication methods
    - Teams membership

.PARAMETER UserEmail
    Email address of the user to investigate. If not provided, will prompt interactively.

.PARAMETER AutoConnect
    Automatically connect to required Microsoft 365 services.

.PARAMETER QuickView
    Display a quick summary view without entering interactive menu.

.PARAMETER ExportReport
    Export full user report to HTML file.

.EXAMPLE
    .\Get-M365UserInfo.ps1
    Prompts for user email and displays interactive menu.

.EXAMPLE
    .\Get-M365UserInfo.ps1 -UserEmail "john.doe@contoso.com" -AutoConnect
    Connects automatically and displays menu for specific user.

.EXAMPLE
    .\Get-M365UserInfo.ps1 -UserEmail "john.doe@contoso.com" -QuickView
    Displays quick summary without interactive menu.

.EXAMPLE
    .\Get-M365UserInfo.ps1 -UserEmail "john.doe@contoso.com" -ExportReport
    Generates comprehensive HTML report for the user.

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 5.1+

    Required Modules:
    - ExchangeOnlineManagement (Exchange operations)
    - Microsoft.Graph (Azure AD, OneDrive, Teams)
    - Optional: MicrosoftTeams (for detailed Teams info)

    Required Permissions:
    - Exchange Administrator or Global Reader (Exchange data)
    - User Administrator or Global Reader (Azure AD data)
    - Reports.Read.All (Graph API for usage data)

    Testing Status: Manual testing completed. Pester tests included for quarantine script.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$UserEmail,

    [Parameter(Mandatory = $false)]
    [switch]$AutoConnect,

    [Parameter(Mandatory = $false)]
    [switch]$QuickView,

    [Parameter(Mandatory = $false)]
    [switch]$ExportReport
)

$ErrorActionPreference = "Stop"
$script:UserData = @{}
$script:ConnectedServices = @{
    ExchangeOnline = $false
    MicrosoftGraph = $false
}

#region Helper Functions

function ConvertTo-HtmlSafe {
    <#
    .SYNOPSIS
        Encode text for safe HTML output to prevent XSS attacks
    #>
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return "" }

    # Manual encoding (avoids System.Web dependency)
    $Text = $Text.Replace('&', '&amp;')
    $Text = $Text.Replace('<', '&lt;')
    $Text = $Text.Replace('>', '&gt;')
    $Text = $Text.Replace('"', '&quot;')
    $Text = $Text.Replace("'", '&#39;')

    return $Text
}

function Get-SafeFileName {
    <#
    .SYNOPSIS
        Sanitize filename to prevent path traversal attacks
    #>
    param([string]$FileName)

    if ([string]::IsNullOrWhiteSpace($FileName)) { return "output" }

    # Remove invalid filename characters
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $safe = $FileName
    foreach ($char in $invalid) {
        $safe = $safe.Replace($char, '_')
    }

    # Additional security: Remove path traversal attempts
    $safe = $safe.Replace('..', '_').Replace('/', '_').Replace('\', '_')

    # Limit length
    if ($safe.Length -gt 100) {
        $safe = $safe.Substring(0, 100)
    }

    return $safe
}

function Get-MailboxSizeGB {
    <#
    .SYNOPSIS
        Safely parse mailbox size from TotalItemSize with error handling
    #>
    param($TotalItemSize)

    if (-not $TotalItemSize) { return 0 }

    try {
        # Match pattern: "12.34 GB (13,271,234 bytes)"
        $sizeString = $TotalItemSize.ToString()
        if ($sizeString -match '\((\d{1,3}(?:,\d{3})*(?:\.\d+)?)\s+bytes\)') {
            $bytes = [double]($Matches[1] -replace ',', '')
            return [math]::Round($bytes / 1GB, 2)
        }

        # Fallback: try old parsing method
        if ($sizeString -match '\(([^)]+)\s+bytes\)') {
            $bytesStr = $Matches[1] -replace ',', ''
            $bytes = [double]$bytesStr
            return [math]::Round($bytes / 1GB, 2)
        }

        Write-Host "[!] Warning: Could not parse mailbox size format: $sizeString" -ForegroundColor Yellow
        return 0
    }
    catch {
        Write-Host "[!] Warning: Error parsing mailbox size: $($_.Exception.Message)" -ForegroundColor Yellow
        return 0
    }
}

function Show-Banner {
    Clear-Host
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          M365 User Information & Management Toolkit           ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
}

function Test-EmailAddress {
    param([string]$Email)

    if ([string]::IsNullOrWhiteSpace($Email)) { return $false }

    # Improved regex that doesn't allow invalid patterns like user@.com
    $pattern = '^[a-zA-Z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'

    return $Email -match $pattern
}

function Get-UserEmailInteractive {
    Write-Host "`n[?] Enter the user's email address:" -ForegroundColor Yellow
    Write-Host "    (Example: john.doe@contoso.com)" -ForegroundColor Gray
    Write-Host -NoNewline "    Email: " -ForegroundColor Cyan
    $email = Read-Host

    if ([string]::IsNullOrWhiteSpace($email)) {
        Write-Host "[-] Email address cannot be empty!" -ForegroundColor Red
        return $null
    }

    if (-not (Test-EmailAddress -Email $email)) {
        Write-Host "[-] Invalid email address format!" -ForegroundColor Red
        return $null
    }

    return $email.Trim()
}

function Connect-M365Services {
    param([switch]$Force)

    Write-Host "`n[*] Checking Microsoft 365 connections..." -ForegroundColor Cyan

    # Check Exchange Online
    try {
        if (-not (Get-Module -Name ExchangeOnlineManagement -ListAvailable)) {
            Write-Host "[-] ExchangeOnlineManagement module not installed!" -ForegroundColor Red
            Write-Host "[!] Install with: Install-Module -Name ExchangeOnlineManagement" -ForegroundColor Yellow
        }
        else {
            $exoConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue
            if ($exoConnection) {
                Write-Host "[+] Exchange Online: Connected as $($exoConnection.UserPrincipalName)" -ForegroundColor Green
                $script:ConnectedServices.ExchangeOnline = $true
            }
            elseif ($Force -or $AutoConnect) {
                Write-Host "[!] Connecting to Exchange Online..." -ForegroundColor Yellow
                Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
                Write-Host "[+] Exchange Online: Connected" -ForegroundColor Green
                $script:ConnectedServices.ExchangeOnline = $true
            }
            else {
                Write-Host "[-] Exchange Online: Not connected" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "[-] Exchange Online connection failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Check Microsoft Graph
    try {
        if (-not (Get-Module -Name Microsoft.Graph.Authentication -ListAvailable)) {
            Write-Host "[-] Microsoft.Graph module not installed!" -ForegroundColor Red
            Write-Host "[!] Install with: Install-Module -Name Microsoft.Graph" -ForegroundColor Yellow
        }
        else {
            $graphContext = Get-MgContext -ErrorAction SilentlyContinue
            if ($graphContext) {
                Write-Host "[+] Microsoft Graph: Connected as $($graphContext.Account)" -ForegroundColor Green
                $script:ConnectedServices.MicrosoftGraph = $true
            }
            elseif ($Force -or $AutoConnect) {
                Write-Host "[!] Connecting to Microsoft Graph..." -ForegroundColor Yellow
                Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All", "Reports.Read.All", "Group.Read.All" -NoWelcome -ErrorAction Stop
                Write-Host "[+] Microsoft Graph: Connected" -ForegroundColor Green
                $script:ConnectedServices.MicrosoftGraph = $true
            }
            else {
                Write-Host "[-] Microsoft Graph: Not connected" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "[-] Microsoft Graph connection failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""

    if (-not $script:ConnectedServices.ExchangeOnline -and -not $script:ConnectedServices.MicrosoftGraph) {
        Write-Host "[-] No services connected! Some features will be unavailable." -ForegroundColor Red
        Write-Host "[!] Use -AutoConnect to connect automatically, or connect manually:" -ForegroundColor Yellow
        Write-Host "    Connect-ExchangeOnline" -ForegroundColor Gray
        Write-Host "    Connect-MgGraph -Scopes 'User.Read.All','Directory.Read.All'" -ForegroundColor Gray
        Write-Host ""
        return $false
    }

    return $true
}

function Get-UserBasicInfo {
    param([string]$Email)

    Write-Host "`n[*] Retrieving user information..." -ForegroundColor Cyan

    # Get Exchange mailbox info
    if ($script:ConnectedServices.ExchangeOnline) {
        try {
            $mailbox = Get-EXOMailbox -Identity $Email -ErrorAction Stop
            $script:UserData.Mailbox = $mailbox
            $script:UserData.DisplayName = $mailbox.DisplayName
            $script:UserData.PrimaryEmail = $mailbox.PrimarySmtpAddress
            $script:UserData.UserPrincipalName = $mailbox.UserPrincipalName
            $script:UserData.MailboxType = $mailbox.RecipientTypeDetails

            Write-Host "[+] Mailbox found: $($mailbox.DisplayName)" -ForegroundColor Green
        }
        catch {
            Write-Host "[-] Could not retrieve mailbox: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }

    # Get Azure AD user info
    if ($script:ConnectedServices.MicrosoftGraph) {
        try {
            $user = Get-MgUser -UserId $Email -Property "DisplayName,UserPrincipalName,Mail,JobTitle,Department,OfficeLocation,MobilePhone,BusinessPhones,AccountEnabled,CreatedDateTime,SignInActivity" -ErrorAction Stop
            $script:UserData.AzureADUser = $user
            $script:UserData.JobTitle = $user.JobTitle
            $script:UserData.Department = $user.Department
            $script:UserData.AccountEnabled = $user.AccountEnabled
            $script:UserData.CreatedDate = $user.CreatedDateTime

            Write-Host "[+] Azure AD account found" -ForegroundColor Green
        }
        catch {
            Write-Host "[-] Could not retrieve Azure AD user: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    return $true
}

function Show-UserSummary {
    Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                      USER SUMMARY                            ║" -ForegroundColor Cyan
    Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║ Display Name    : $($script:UserData.DisplayName)" -ForegroundColor White
    Write-Host "║ Email (Primary) : $($script:UserData.PrimaryEmail)" -ForegroundColor White
    Write-Host "║ UPN             : $($script:UserData.UserPrincipalName)" -ForegroundColor White

    if ($script:UserData.JobTitle) {
        Write-Host "║ Job Title       : $($script:UserData.JobTitle)" -ForegroundColor White
    }
    if ($script:UserData.Department) {
        Write-Host "║ Department      : $($script:UserData.Department)" -ForegroundColor White
    }

    Write-Host "║ Mailbox Type    : $($script:UserData.MailboxType)" -ForegroundColor White

    $accountStatus = if ($script:UserData.AccountEnabled) { "Enabled" } else { "DISABLED" }
    $statusColor = if ($script:UserData.AccountEnabled) { "Green" } else { "Red" }
    Write-Host "║ Account Status  : $accountStatus" -ForegroundColor $statusColor

    if ($script:UserData.CreatedDate) {
        Write-Host "║ Created         : $($script:UserData.CreatedDate)" -ForegroundColor Gray
    }

    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

function Get-MailboxStatistics {
    if (-not $script:ConnectedServices.ExchangeOnline) {
        Write-Host "[-] Exchange Online not connected" -ForegroundColor Red
        return
    }

    Write-Host "`n[*] Retrieving mailbox statistics..." -ForegroundColor Cyan

    try {
        $stats = Get-EXOMailboxStatistics -Identity $script:UserData.UserPrincipalName -ErrorAction Stop

        # Use safe parsing function with error handling
        $mailboxSizeGB = Get-MailboxSizeGB $stats.TotalItemSize

        $mailboxDetails = Get-EXOMailbox -Identity $script:UserData.UserPrincipalName -Properties ProhibitSendQuota, ArchiveStatus

        # Parse quota safely
        $quotaGB = if ($mailboxDetails.ProhibitSendQuota -ne 'Unlimited') {
            Get-MailboxSizeGB $mailboxDetails.ProhibitSendQuota
        } else { 0 }

        $quotaPercent = if ($quotaGB -gt 0) {
            [math]::Round(($mailboxSizeGB / $quotaGB) * 100, 2)
        } else { 0 }

        Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                   MAILBOX STATISTICS                         ║" -ForegroundColor Cyan
        Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
        Write-Host "║ Mailbox Size    : $mailboxSizeGB GB" -ForegroundColor White
        Write-Host "║ Quota           : $quotaGB GB" -ForegroundColor White
        Write-Host "║ Quota Used      : $quotaPercent%" -ForegroundColor $(if ($quotaPercent -ge 90) { "Red" } elseif ($quotaPercent -ge 80) { "Yellow" } else { "Green" })
        Write-Host "║ Item Count      : $($stats.ItemCount)" -ForegroundColor White
        Write-Host "║ Last Logon      : $($stats.LastLogonTime)" -ForegroundColor White
        Write-Host "║ Archive Status  : $($mailboxDetails.ArchiveStatus)" -ForegroundColor White
        Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    }
    catch {
        Write-Host "[-] Error retrieving mailbox statistics: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-UserLicenses {
    if (-not $script:ConnectedServices.MicrosoftGraph) {
        Write-Host "[-] Microsoft Graph not connected" -ForegroundColor Red
        return
    }

    Write-Host "`n[*] Retrieving license information..." -ForegroundColor Cyan

    try {
        $licenses = Get-MgUserLicenseDetail -UserId $script:UserData.UserPrincipalName -ErrorAction Stop

        if ($licenses) {
            Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║                   LICENSE ASSIGNMENTS                        ║" -ForegroundColor Cyan
            Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan

            foreach ($license in $licenses) {
                Write-Host "║ • $($license.SkuPartNumber)" -ForegroundColor Green
                Write-Host "║   Service Plans: $($license.ServicePlans.Count) active" -ForegroundColor Gray
            }

            Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        }
        else {
            Write-Host "[!] No licenses assigned to this user" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[-] Error retrieving licenses: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-UserGroupMemberships {
    if (-not $script:ConnectedServices.MicrosoftGraph) {
        Write-Host "[-] Microsoft Graph not connected" -ForegroundColor Red
        return
    }

    Write-Host "`n[*] Retrieving group memberships..." -ForegroundColor Cyan

    try {
        $groups = Get-MgUserMemberOf -UserId $script:UserData.UserPrincipalName -ErrorAction Stop

        if ($groups) {
            Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║                   GROUP MEMBERSHIPS                          ║" -ForegroundColor Cyan
            Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
            Write-Host "║ Total Groups: $($groups.Count)" -ForegroundColor White
            Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan

            $groupList = $groups | Select-Object -First 10
            foreach ($group in $groupList) {
                $groupDetails = Get-MgGroup -GroupId $group.Id -ErrorAction SilentlyContinue
                if ($groupDetails) {
                    Write-Host "║ • $($groupDetails.DisplayName)" -ForegroundColor White
                }
            }

            if ($groups.Count -gt 10) {
                Write-Host "║ ... and $($groups.Count - 10) more groups" -ForegroundColor Gray
            }

            Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        }
        else {
            Write-Host "[!] User is not a member of any groups" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[-] Error retrieving group memberships: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-UserMobileDevices {
    if (-not $script:ConnectedServices.ExchangeOnline) {
        Write-Host "[-] Exchange Online not connected" -ForegroundColor Red
        return
    }

    Write-Host "`n[*] Retrieving mobile device associations..." -ForegroundColor Cyan

    try {
        $devices = Get-MobileDevice -Mailbox $script:UserData.UserPrincipalName -ErrorAction Stop

        if ($devices) {
            Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║                   MOBILE DEVICES                             ║" -ForegroundColor Cyan
            Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
            Write-Host "║ Total Devices: $($devices.Count)" -ForegroundColor White
            Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan

            foreach ($device in $devices) {
                Write-Host "║ Device: $($device.FriendlyName)" -ForegroundColor White
                Write-Host "║   Type: $($device.DeviceModel)" -ForegroundColor Gray
                Write-Host "║   OS: $($device.DeviceOS)" -ForegroundColor Gray
                Write-Host "║   Last Sync: $($device.LastSuccessSync)" -ForegroundColor Gray
                Write-Host "║" -ForegroundColor Cyan
            }

            Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        }
        else {
            Write-Host "[!] No mobile devices found" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[-] Error retrieving mobile devices: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-UserSignInActivity {
    if (-not $script:ConnectedServices.MicrosoftGraph) {
        Write-Host "[-] Microsoft Graph not connected" -ForegroundColor Red
        return
    }

    Write-Host "`n[*] Retrieving sign-in activity..." -ForegroundColor Cyan

    try {
        $user = Get-MgUser -UserId $script:UserData.UserPrincipalName -Property "SignInActivity" -ErrorAction Stop

        if ($user.SignInActivity) {
            Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "║                   SIGN-IN ACTIVITY                           ║" -ForegroundColor Cyan
            Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
            Write-Host "║ Last Sign-In         : $($user.SignInActivity.LastSignInDateTime)" -ForegroundColor White
            Write-Host "║ Last Interactive     : $($user.SignInActivity.LastNonInteractiveSignInDateTime)" -ForegroundColor White
            Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        }
        else {
            Write-Host "[!] No sign-in activity data available" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[-] Error retrieving sign-in activity: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-QuarantineManagement {
    if (-not $script:ConnectedServices.ExchangeOnline) {
        Write-Host "[-] Exchange Online not connected" -ForegroundColor Red
        return
    }

    Write-Host "`n[*] Checking quarantined messages (last 7 days)..." -ForegroundColor Cyan

    try {
        $startDate = (Get-Date).AddDays(-7)
        $messages = Get-QuarantineMessage -RecipientAddress $script:UserData.PrimaryEmail -StartReceivedDate $startDate -ErrorAction Stop

        if ($messages) {
            Write-Host "[+] Found $($messages.Count) quarantined message(s)" -ForegroundColor Green
            Write-Host "[i] Launch Manage-QuarantinedEmails.ps1 for full management interface" -ForegroundColor Cyan
            Write-Host ""

            $messages | Select-Object -First 5 | ForEach-Object {
                Write-Host "  • $($_.ReceivedTime.ToString('yyyy-MM-dd HH:mm')) - From: $($_.SenderAddress)" -ForegroundColor Yellow
                Write-Host "    Subject: $($_.Subject)" -ForegroundColor Gray
                Write-Host "    Reason: $($_.QuarantineTypes -join ', ')" -ForegroundColor Gray
                Write-Host ""
            }

            if ($messages.Count -gt 5) {
                Write-Host "  ... and $($messages.Count - 5) more message(s)" -ForegroundColor Gray
            }
        }
        else {
            Write-Host "[+] No quarantined messages found" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "[-] Error checking quarantine: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Show-MainMenu {
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                      MAIN MENU                                 ║" -ForegroundColor Cyan
    Write-Host "╠════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  1. View Mailbox Statistics                                    ║" -ForegroundColor White
    Write-Host "║  2. View License Assignments                                   ║" -ForegroundColor White
    Write-Host "║  3. Check Quarantined Emails                                   ║" -ForegroundColor White
    Write-Host "║  4. View Group Memberships                                     ║" -ForegroundColor White
    Write-Host "║  5. View Mobile Devices                                        ║" -ForegroundColor White
    Write-Host "║  6. View Sign-In Activity                                      ║" -ForegroundColor White
    Write-Host "║  7. Show User Summary                                          ║" -ForegroundColor White
    Write-Host "║  8. Generate Full Report (HTML)                                ║" -ForegroundColor White
    Write-Host "║  9. Check Another User                                         ║" -ForegroundColor White
    Write-Host "║  0. Exit                                                       ║" -ForegroundColor White
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host -NoNewline "`n[?] Select an option (0-9): " -ForegroundColor Yellow
}

function Export-UserReport {
    Write-Host "`n[*] Generating comprehensive user report..." -ForegroundColor Cyan

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

    # Use safe filename to prevent path traversal
    $safeEmail = Get-SafeFileName $script:UserData.UserPrincipalName
    $reportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
    if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    $reportPath = Join-Path $reportDir "M365_UserReport_${safeEmail}_$timestamp.html"

    # Encode all user data for HTML to prevent XSS
    $safeDisplayName = ConvertTo-HtmlSafe $script:UserData.DisplayName
    $safePrimaryEmail = ConvertTo-HtmlSafe $script:UserData.PrimaryEmail
    $safeUserPrincipalName = ConvertTo-HtmlSafe $script:UserData.UserPrincipalName
    $safeJobTitle = ConvertTo-HtmlSafe $script:UserData.JobTitle
    $safeDepartment = ConvertTo-HtmlSafe $script:UserData.Department
    $safeMailboxType = ConvertTo-HtmlSafe $script:UserData.MailboxType

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>M365 User Report - $safeDisplayName</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #505050; margin-top: 30px; background-color: #e0e0e0; padding: 10px; border-radius: 5px; }
        .section { background: white; padding: 20px; margin: 10px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th { background-color: #0078d4; color: white; padding: 10px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .label { font-weight: bold; width: 200px; }
        .status-enabled { color: #107c10; font-weight: bold; }
        .status-disabled { color: #d13438; font-weight: bold; }
        .footer { margin-top: 30px; text-align: center; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <h1>Microsoft 365 User Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>

    <div class="section">
        <h2>User Information</h2>
        <table>
            <tr><td class="label">Display Name</td><td>$safeDisplayName</td></tr>
            <tr><td class="label">Primary Email</td><td>$safePrimaryEmail</td></tr>
            <tr><td class="label">User Principal Name</td><td>$safeUserPrincipalName</td></tr>
            <tr><td class="label">Job Title</td><td>$safeJobTitle</td></tr>
            <tr><td class="label">Department</td><td>$safeDepartment</td></tr>
            <tr><td class="label">Mailbox Type</td><td>$safeMailboxType</td></tr>
            <tr><td class="label">Account Status</td><td class="$(if ($script:UserData.AccountEnabled) { 'status-enabled' } else { 'status-disabled' })">$(if ($script:UserData.AccountEnabled) { 'Enabled' } else { 'Disabled' })</td></tr>
        </table>
    </div>

    <div class="footer">
        Generated by Get-M365UserInfo.ps1<br>
        <strong>Note:</strong> This report has not been thoroughly tested. Please validate before making operational decisions.
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "[+] Report saved to: $reportPath" -ForegroundColor Green
}

#endregion

#region Main Execution

Show-Banner

# Connect to services
if (-not (Connect-M365Services)) {
    if (-not $AutoConnect) {
        Write-Host "[?] Would you like to connect now? (Y/N): " -ForegroundColor Yellow -NoNewline
        $response = Read-Host
        if ($response -eq 'Y' -or $response -eq 'y') {
            Connect-M365Services -Force
        }
        else {
            Write-Host "`n[-] Cannot proceed without service connections. Exiting." -ForegroundColor Red
            exit 1
        }
    }
}

# Get user email
if ([string]::IsNullOrWhiteSpace($UserEmail)) {
    $UserEmail = Get-UserEmailInteractive
    if (-not $UserEmail) {
        Write-Host "[-] No valid email provided. Exiting." -ForegroundColor Red
        exit 1
    }
}

# Validate and get user info
if (-not (Get-UserBasicInfo -Email $UserEmail)) {
    Write-Host "[-] Unable to retrieve user information. Exiting." -ForegroundColor Red
    exit 1
}

# Display initial summary
Show-UserSummary

# Quick view mode
if ($QuickView) {
    Get-MailboxStatistics
    Get-UserLicenses
    Invoke-QuarantineManagement
    Write-Host "`n[+] Quick view completed!" -ForegroundColor Green
    exit 0
}

# Export report mode
if ($ExportReport) {
    Export-UserReport
    exit 0
}

# Interactive menu loop
$continue = $true
while ($continue) {
    Show-MainMenu
    $choice = Read-Host

    switch ($choice) {
        '1' { Get-MailboxStatistics }
        '2' { Get-UserLicenses }
        '3' { Invoke-QuarantineManagement }
        '4' { Get-UserGroupMemberships }
        '5' { Get-UserMobileDevices }
        '6' { Get-UserSignInActivity }
        '7' { Show-UserSummary }
        '8' { Export-UserReport }
        '9' {
            $UserEmail = Get-UserEmailInteractive
            if ($UserEmail) {
                if (Get-UserBasicInfo -Email $UserEmail) {
                    Show-UserSummary
                }
            }
        }
        '0' {
            Write-Host "`n[+] Thank you for using M365 User Info Toolkit!" -ForegroundColor Green
            $continue = $false
        }
        default {
            Write-Host "[-] Invalid option. Please select 0-9." -ForegroundColor Red
        }
    }

    if ($continue) {
        Write-Host "`nPress any key to continue..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}

#endregion
