<#
.SYNOPSIS
    Interactive tool for managing quarantined emails for a specific M365 user.

.DESCRIPTION
    This script allows a technician to:
    - Search for quarantined emails for a specific user
    - View quarantined messages from the last 7 days (or custom timeframe)
    - Display detailed information about each quarantined message
    - Select and release quarantined messages for delivery
    - Release messages to specific recipients or original recipients

.PARAMETER UserEmail
    Email address of the user whose quarantine to check. If not provided, will prompt interactively.

.PARAMETER Days
    Number of days to search back for quarantined messages. Default: 7

.PARAMETER AutoConnect
    Automatically connect to Exchange Online if not already connected.


.EXAMPLE
    .\Manage-QuarantinedEmails.ps1
    Prompts for user email and displays quarantined messages interactively.

.EXAMPLE
    .\Manage-QuarantinedEmails.ps1 -UserEmail "john.doe@contoso.com"
    Checks quarantine for specific user.

.EXAMPLE
    .\Manage-QuarantinedEmails.ps1 -UserEmail "john.doe@contoso.com" -Days 14
    Checks quarantine for the last 14 days.

.EXAMPLE
    .\Manage-QuarantinedEmails.ps1 -AutoConnect
    Automatically connects to Exchange Online before running.

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 7, ExchangeOnlineManagement module
    Requires: Security & Compliance Center permissions (Quarantine role)

    Permissions Required:
    - View-Only Recipients or higher in Exchange Online
    - Quarantine role in Security & Compliance Center

    Testing Status: Manual testing completed. Pester tests included for quarantine script.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$UserEmail,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 30)]
    [int]$Days = 7,

    [Parameter(Mandatory = $false)]
    [switch]$AutoConnect
)

$ErrorActionPreference = "Stop"

# Function to display banner
function Show-Banner {
    Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     M365 Quarantine Management Tool                         ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

# Function to check and connect to Exchange Online
function Connect-ToExchangeOnline {
    Write-Host "[*] Checking Exchange Online connection..." -ForegroundColor Cyan

    # Check if module is installed
    if (-not (Get-Module -Name ExchangeOnlineManagement -ListAvailable)) {
        Write-Host "[-] Exchange Online Management module not found!" -ForegroundColor Red
        Write-Host "[!] Install with: Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser" -ForegroundColor Yellow
        exit 1
    }

    # Import module if not already loaded
    if (-not (Get-Module -Name ExchangeOnlineManagement)) {
        Import-Module ExchangeOnlineManagement -ErrorAction SilentlyContinue
    }

    # Check if connected
    try {
        $connectionInfo = Get-ConnectionInformation -ErrorAction SilentlyContinue
        if ($connectionInfo) {
            Write-Host "[+] Connected to Exchange Online: $($connectionInfo.UserPrincipalName)" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Verbose "Handled exception: $($_.Exception.Message)" -Verbose:$false
    }

    # Attempt connection if AutoConnect is specified
    if ($AutoConnect) {
        Write-Host "[!] Not connected. Attempting to connect..." -ForegroundColor Yellow
        try {
            Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
            Write-Host "[+] Successfully connected to Exchange Online" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "[-] Failed to connect: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "[-] Not connected to Exchange Online!" -ForegroundColor Red
        Write-Host "[!] Run: Connect-ExchangeOnline" -ForegroundColor Yellow
        Write-Host "[!] Or use -AutoConnect parameter" -ForegroundColor Yellow
        return $false
    }
}

# Function to validate email address
function Test-EmailAddress {
    param([string]$Email)

    if ([string]::IsNullOrWhiteSpace($Email)) { return $false }

    # Improved regex that doesn't allow invalid patterns like user@.com
    $pattern = '^[a-zA-Z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'

    return $Email -match $pattern
}

# Function to get user email interactively
function Get-UserEmailInteractive {
    Write-Host "`n[?] Enter the user's email address to check their quarantine:" -ForegroundColor Yellow
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

# Function to retrieve quarantined messages
function Get-QuarantinedMessages {
    param(
        [string]$RecipientAddress,
        [int]$DaysBack
    )

    $startDate = (Get-Date).AddDays(-$DaysBack)
    $endDate = Get-Date

    Write-Host "`n[*] Searching for quarantined messages..." -ForegroundColor Cyan
    Write-Host "    User: $RecipientAddress" -ForegroundColor Gray
    Write-Host "    Period: Last $DaysBack days" -ForegroundColor Gray
    Write-Host ""

    try {
        # Get quarantine messages for the user
        $messages = Get-QuarantineMessage -RecipientAddress $RecipientAddress `
            -StartReceivedDate $startDate `
            -EndReceivedDate $endDate `
            -ErrorAction Stop

        return $messages
    }
    catch {
        Write-Host "[-] Error retrieving quarantined messages: $($_.Exception.Message)" -ForegroundColor Red

        # Check if it's a permissions issue
        if ($_.Exception.Message -like "*not authorized*" -or $_.Exception.Message -like "*permission*") {
            Write-Host "`n[!] Insufficient permissions. You need:" -ForegroundColor Yellow
            Write-Host "    - Quarantine role in Security & Compliance Center" -ForegroundColor Yellow
            Write-Host "    - Or Global Administrator role" -ForegroundColor Yellow
        }

        return $null
    }
}

# Function to display quarantined messages
function Show-QuarantinedMessages {
    param($Messages)

    if (-not $Messages -or $Messages.Count -eq 0) {
        Write-Host "[i] No quarantined messages found for this user." -ForegroundColor Green
        return $false
    }

    Write-Host "[+] Found $($Messages.Count) quarantined message(s):" -ForegroundColor Green
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  #  │ Received          │ From                          │ Subject           ║" -ForegroundColor Cyan
    Write-Host "╠════════════════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan

    $index = 1
    foreach ($msg in $Messages) {
        $receivedDate = $msg.ReceivedTime.ToString("yyyy-MM-dd HH:mm")
        $from = $msg.SenderAddress
        $subject = $msg.Subject

        # Truncate long values for display
        if ($from.Length -gt 28) { $from = $from.Substring(0, 25) + "..." }
        if ($subject.Length -gt 16) { $subject = $subject.Substring(0, 13) + "..." }

        Write-Host ("║ {0,2} │ {1,-17} │ {2,-29} │ {3,-17} ║" -f $index, $receivedDate, $from, $subject) -ForegroundColor White
        $index++
    }

    Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    return $true
}

# Function to show detailed message information
function Show-MessageDetails {
    param($Message, $Index)

    Write-Host "`n╔═══ Message Details (Item #$Index) ═══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  Message ID       : $($Message.Identity)" -ForegroundColor Gray
    Write-Host "  Received         : $($Message.ReceivedTime)" -ForegroundColor White
    Write-Host "  From             : $($Message.SenderAddress)" -ForegroundColor White
    Write-Host "  To               : $($Message.RecipientAddress -join ', ')" -ForegroundColor White
    Write-Host "  Subject          : $($Message.Subject)" -ForegroundColor Yellow
    Write-Host "  Quarantine Reason: $($Message.QuarantineTypes -join ', ')" -ForegroundColor $(if ($Message.QuarantineTypes -like '*Spam*') { 'Red' } else { 'Yellow' })
    Write-Host "  Direction        : $($Message.Direction)" -ForegroundColor Gray
    Write-Host "  Size (KB)        : $([math]::Round($Message.Size / 1KB, 2))" -ForegroundColor Gray

    if ($Message.PolicyName) {
        Write-Host "  Policy           : $($Message.PolicyName)" -ForegroundColor Gray
    }

    Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

# Function to release a quarantined message
function Release-QuarantinedMessage {
    param($Message)

    Write-Host "`n[*] Preparing to release message..." -ForegroundColor Cyan

    # Validate message has recipients (array bounds check)
    if ($null -eq $Message.RecipientAddress -or $Message.RecipientAddress.Count -eq 0) {
        Write-Host "[-] Message has no recipients! Cannot release." -ForegroundColor Red
        return $false
    }

    $targetRecipient = $Message.RecipientAddress[0]

    Write-Host "`n[!] Confirm release:" -ForegroundColor Yellow
    Write-Host "    From    : $($Message.SenderAddress)" -ForegroundColor Gray
    Write-Host "    To      : $targetRecipient" -ForegroundColor Gray
    Write-Host "    Subject : $($Message.Subject)" -ForegroundColor Gray
    Write-Host "    Reason  : $($Message.QuarantineTypes -join ', ')" -ForegroundColor Gray
    Write-Host ""
    Write-Host -NoNewline "[?] Release this message to original recipient? (Y/N): " -ForegroundColor Yellow

    $confirm = Read-Host

    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host "[!] Release cancelled." -ForegroundColor Yellow
        return $false
    }

    try {
        Write-Host "`n[*] Releasing message..." -ForegroundColor Cyan

        # Release the message to original recipient
        # Note: Release-QuarantineMessage only supports releasing to original recipients
        Release-QuarantineMessage -Identity $Message.Identity `
            -ReleaseToAll:$false `
            -ErrorAction Stop

        Write-Host "[+] Message successfully released to: $targetRecipient" -ForegroundColor Green
        Write-Host "[i] The message should be delivered to the original recipient shortly." -ForegroundColor Green

        return $true
    }
    catch {
        Write-Host "[-] Failed to release message: $($_.Exception.Message)" -ForegroundColor Red

        if ($_.Exception.Message -like "*not authorized*") {
            Write-Host "[!] You may not have permission to release this message type." -ForegroundColor Yellow
        }

        return $false
    }
}

# Function to handle message selection
function Select-MessageToRelease {
    param($Messages)

    Write-Host "[?] Select a message to view/release (1-$($Messages.Count)), or 0 to exit:" -ForegroundColor Yellow
    Write-Host -NoNewline "    Selection: " -ForegroundColor Cyan

    $selection = Read-Host

    # Validate input
    if ($selection -notmatch '^\d+$') {
        Write-Host "[-] Invalid input! Please enter a number." -ForegroundColor Red
        return $null
    }

    $selectionNum = [int]$selection

    if ($selectionNum -eq 0) {
        return 0
    }

    if ($selectionNum -lt 1 -or $selectionNum -gt $Messages.Count) {
        Write-Host "[-] Invalid selection! Please choose between 1 and $($Messages.Count)." -ForegroundColor Red
        return $null
    }

    return $selectionNum
}

# Function to handle message actions menu
function Show-MessageActionMenu {
    param($Message, $Index)

    Show-MessageDetails -Message $Message -Index $Index

    Write-Host "`n[?] What would you like to do?" -ForegroundColor Yellow
    Write-Host "    1. Release message to original recipient" -ForegroundColor White
    Write-Host "    2. Go back to list" -ForegroundColor White
    Write-Host "    0. Exit" -ForegroundColor White
    Write-Host -NoNewline "`n    Choice: " -ForegroundColor Cyan

    $action = Read-Host

    switch ($action) {
        '1' {
            $result = Release-QuarantinedMessage -Message $Message
            return @{ Action = 'Released'; Success = $result }
        }
        '2' {
            return @{ Action = 'Back'; Success = $true }
        }
        '0' {
            return @{ Action = 'Exit'; Success = $true }
        }
        default {
            Write-Host "[-] Invalid choice!" -ForegroundColor Red
            return @{ Action = 'Invalid'; Success = $false }
        }
    }
}

#
# Main Script Execution
#

# Only execute if not dot-sourced (for Pester tests)
if ($MyInvocation.InvocationName -ne '.') {

    Show-Banner

    # Check Exchange Online connection
    if (-not (Connect-ToExchangeOnline)) {
        exit 1
    }

    # Get user email address
    if ([string]::IsNullOrWhiteSpace($UserEmail)) {
        $UserEmail = Get-UserEmailInteractive
        if (-not $UserEmail) {
            exit 1
        }
    }
    else {
        # Validate provided email
        if (-not (Test-EmailAddress -Email $UserEmail)) {
            Write-Host "[-] Invalid email address format: $UserEmail" -ForegroundColor Red
            exit 1
        }
    }

    # Verify user exists
    Write-Host "`n[*] Verifying user account..." -ForegroundColor Cyan
    try {
        $user = Get-EXOMailbox -Identity $UserEmail -ErrorAction Stop
        Write-Host "[+] User found: $($user.DisplayName) ($($user.PrimarySmtpAddress))" -ForegroundColor Green
        $UserEmail = $user.PrimarySmtpAddress  # Use primary SMTP address
    }
    catch {
        Write-Host "[-] User not found or error accessing mailbox: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[!] Please verify the email address is correct." -ForegroundColor Yellow
        exit 1
    }

    # Get quarantined messages
    $quarantinedMessages = Get-QuarantinedMessages -RecipientAddress $UserEmail -DaysBack $Days

    if (-not $quarantinedMessages) {
        exit 0
    }

    # Convert to array if single item
    if ($quarantinedMessages -isnot [array]) {
        $quarantinedMessages = @($quarantinedMessages)
    }

    # Display messages
    if (-not (Show-QuarantinedMessages -Messages $quarantinedMessages)) {
        exit 0
    }

    # Interactive message selection loop
    $continue = $true
    while ($continue) {
        $selection = Select-MessageToRelease -Messages $quarantinedMessages

        if ($null -eq $selection) {
            # Invalid input, try again
            continue
        }

        if ($selection -eq 0) {
            Write-Host "`n[+] Exiting quarantine manager." -ForegroundColor Green
            $continue = $false
            break
        }

        # Get selected message
        $selectedMessage = $quarantinedMessages[$selection - 1]

        # Show action menu
        $actionResult = Show-MessageActionMenu -Message $selectedMessage -Index $selection

        if ($actionResult.Action -eq 'Exit') {
            Write-Host "`n[+] Exiting quarantine manager." -ForegroundColor Green
            $continue = $false
        }
        elseif ($actionResult.Action -eq 'Released' -and $actionResult.Success) {
            # Message was released, refresh the list
            Write-Host "`n[*] Refreshing quarantine list..." -ForegroundColor Cyan
            $quarantinedMessages = Get-QuarantinedMessages -RecipientAddress $UserEmail -DaysBack $Days

            if (-not $quarantinedMessages -or $quarantinedMessages.Count -eq 0) {
                Write-Host "[i] No more quarantined messages for this user." -ForegroundColor Green
                $continue = $false
            }
            else {
                if ($quarantinedMessages -isnot [array]) {
                    $quarantinedMessages = @($quarantinedMessages)
                }
                Show-QuarantinedMessages -Messages $quarantinedMessages
            }
        }
        elseif ($actionResult.Action -eq 'Back') {
            # Return to message list
            Show-QuarantinedMessages -Messages $quarantinedMessages
        }
    }

    Write-Host "`n[+] Quarantine management session completed." -ForegroundColor Green
    exit 0

} # End of invocation check
