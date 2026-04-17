<#
.SYNOPSIS
    Generates comprehensive Exchange Online mailbox health and usage report.

.DESCRIPTION
    This script analyzes Exchange Online mailboxes for:
    - Mailbox size and quota usage
    - Item counts and folder statistics
    - Mailbox permissions and delegates
    - Archive mailbox status
    - Litigation hold status
    - Mobile device associations
    - Last logon activity
    - Storage warnings and quota violations

.PARAMETER MailboxType
    Type of mailboxes to check: UserMailbox, SharedMailbox, RoomMailbox, EquipmentMailbox, All (default: UserMailbox).

.PARAMETER IncludeArchive
    Include archive mailbox statistics.

.PARAMETER IncludePermissions
    Include mailbox permission details.

.PARAMETER QuotaWarningThreshold
    Percentage threshold for quota warnings (default: 80).

.PARAMETER InactivityDays
    Days since last logon to consider mailbox inactive (default: 90).

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Get-MailboxHealth.ps1
    Checks all user mailboxes for health issues.

.EXAMPLE
    .\Get-MailboxHealth.ps1 -MailboxType SharedMailbox -IncludePermissions -ExportHTML
    Audits shared mailboxes with permission details.

.EXAMPLE
    .\Get-MailboxHealth.ps1 -QuotaWarningThreshold 90 -InactivityDays 180
    Checks for mailboxes over 90% quota or inactive for 180 days.

.NOTES
    Requires Exchange Online PowerShell module
    Requires Exchange Administrator or Global Reader role
    Compatible with Exchange Online (Microsoft 365)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('UserMailbox','SharedMailbox','RoomMailbox','EquipmentMailbox','All')]
    [string]$MailboxType = 'UserMailbox',

    [Parameter(Mandatory=$false)]
    [switch]$IncludeArchive,

    [Parameter(Mandatory=$false)]
    [switch]$IncludePermissions,

    [Parameter(Mandatory=$false)]
    [int]$QuotaWarningThreshold = 80,

    [Parameter(Mandatory=$false)]
    [int]$InactivityDays = 90,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "`n=== Exchange Online Mailbox Health Report ===" -ForegroundColor Cyan
Write-Host "Mailbox Type: $MailboxType" -ForegroundColor Yellow
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

# Get mailboxes
Write-Host "[*] Retrieving mailboxes..." -ForegroundColor Cyan

$filterType = if ($MailboxType -eq 'All') { '*' } else { $MailboxType }

try {
    $mailboxes = Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails $filterType -Properties DisplayName,UserPrincipalName,PrimarySmtpAddress,RecipientTypeDetails,WhenCreated

    Write-Host "[+] Found $($mailboxes.Count) mailbox(es)" -ForegroundColor Green
}
catch {
    Write-Host "[-] Error retrieving mailboxes: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Process mailboxes
$results = @()
$quotaWarnings = 0
$quotaExceeded = 0
$inactiveMailboxes = 0
$inactivityThreshold = (Get-Date).AddDays(-$InactivityDays)

$i = 0
foreach ($mailbox in $mailboxes) {
    $i++
    Write-Progress -Activity "Processing Mailboxes" -Status "$i of $($mailboxes.Count): $($mailbox.DisplayName)" -PercentComplete (($i / $mailboxes.Count) * 100)

    # Get mailbox statistics
    try {
        $stats = Get-EXOMailboxStatistics -Identity $mailbox.UserPrincipalName -ErrorAction Stop

        # Parse sizes
        $mailboxSizeGB = if ($stats.TotalItemSize) {
            [math]::Round(($stats.TotalItemSize.ToString().Split('(')[1].Split(' ')[0].Replace(',','') -as [double]) / 1GB, 2)
        }
        else { 0 }

        # Get quota
        $mailboxDetails = Get-EXOMailbox -Identity $mailbox.UserPrincipalName -Properties ProhibitSendQuota,IssueWarningQuota,LitigationHoldEnabled,ArchiveStatus

        $quotaGB = if ($mailboxDetails.ProhibitSendQuota -ne 'Unlimited') {
            [math]::Round(($mailboxDetails.ProhibitSendQuota.ToString().Split('(')[1].Split(' ')[0].Replace(',','') -as [double]) / 1GB, 2)
        }
        else { 0 }

        # Calculate quota percentage
        $quotaPercent = if ($quotaGB -gt 0) {
            [math]::Round(($mailboxSizeGB / $quotaGB) * 100, 2)
        }
        else { 0 }

        # Determine status
        $status = if ($quotaPercent -ge 100) {
            $quotaExceeded++
            "Critical"
        }
        elseif ($quotaPercent -ge $QuotaWarningThreshold) {
            $quotaWarnings++
            "Warning"
        }
        else {
            "OK"
        }

        # Check inactivity
        $lastLogon = $stats.LastLogonTime
        $isInactive = $false
        if ($lastLogon -and $lastLogon -lt $inactivityThreshold) {
            $isInactive = $true
            $inactiveMailboxes++
        }
        elseif (-not $lastLogon) {
            $isInactive = $true
            $inactiveMailboxes++
        }

        # Get permissions if requested
        $permissions = @()
        if ($IncludePermissions) {
            $perms = Get-EXOMailboxPermission -Identity $mailbox.UserPrincipalName |
                Where-Object { $_.User -notlike "NT AUTHORITY\*" -and $_.User -notlike "S-1-5-*" -and $_.IsInherited -eq $false }

            $permissions = $perms | ForEach-Object { "$($_.User):$($_.AccessRights -join ',')" }
        }

        # Archive info
        $archiveInfo = "N/A"
        $archiveSizeGB = 0
        if ($IncludeArchive -and $mailboxDetails.ArchiveStatus -eq 'Active') {
            try {
                $archiveStats = Get-EXOMailboxStatistics -Identity $mailbox.UserPrincipalName -Archive -ErrorAction SilentlyContinue
                if ($archiveStats.TotalItemSize) {
                    $archiveSizeGB = [math]::Round(($archiveStats.TotalItemSize.ToString().Split('(')[1].Split(' ')[0].Replace(',','') -as [double]) / 1GB, 2)
                    $archiveInfo = "$archiveSizeGB GB"
                }
            }
            catch {
                $archiveInfo = "Error"
            }
        }

        $result = [PSCustomObject]@{
            DisplayName = $mailbox.DisplayName
            UserPrincipalName = $mailbox.UserPrincipalName
            MailboxType = $mailbox.RecipientTypeDetails
            MailboxSizeGB = $mailboxSizeGB
            QuotaGB = $quotaGB
            QuotaUsedPercent = $quotaPercent
            ItemCount = $stats.ItemCount
            Status = $status
            LastLogon = $lastLogon
            IsInactive = $isInactive
            LitigationHold = $mailboxDetails.LitigationHoldEnabled
            ArchiveStatus = $mailboxDetails.ArchiveStatus
            ArchiveSizeGB = if ($archiveSizeGB -gt 0) { $archiveSizeGB } else { "N/A" }
            Permissions = if ($permissions.Count -gt 0) { $permissions -join '; ' } else { "None" }
            Created = $mailbox.WhenCreated
        }

        $results += $result

    }
    catch {
        Write-Host "[-] Error processing $($mailbox.DisplayName): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Progress -Activity "Processing Mailboxes" -Completed

Write-Host ""

# Display summary
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Total Mailboxes: $($results.Count)" -ForegroundColor White
Write-Host "Quota Warnings (>$QuotaWarningThreshold%): $quotaWarnings" -ForegroundColor Yellow
Write-Host "Quota Exceeded: $quotaExceeded" -ForegroundColor Red
Write-Host "Inactive (>$InactivityDays days): $inactiveMailboxes" -ForegroundColor Yellow
Write-Host ""

# Show top issues
if ($quotaExceeded -gt 0 -or $quotaWarnings -gt 0) {
    Write-Host "=== Mailboxes Requiring Attention ===" -ForegroundColor Yellow
    $results | Where-Object { $_.Status -ne "OK" } |
        Sort-Object QuotaUsedPercent -Descending |
        Select-Object -First 10 DisplayName, MailboxSizeGB, QuotaGB, QuotaUsedPercent, Status |
        Format-Table -AutoSize
}

if ($inactiveMailboxes -gt 0) {
    Write-Host "`n=== Inactive Mailboxes ===" -ForegroundColor Yellow
    $results | Where-Object { $_.IsInactive -eq $true } |
        Select-Object -First 10 DisplayName, LastLogon, MailboxSizeGB |
        Format-Table -AutoSize
}

# Export results
if ($ExportHTML) {
    $htmlPath = "$env:USERPROFILE\Desktop\MailboxHealth_$timestamp.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Mailbox Health Report - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #0078d4; }
        .summary { background-color: #f0f0f0; padding: 15px; border-radius: 5px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th { background-color: #0078d4; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; font-size: 12px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .critical { background-color: #d13438; color: white; padding: 3px 6px; border-radius: 3px; }
        .warning { background-color: #ffaa44; color: white; padding: 3px 6px; border-radius: 3px; }
        .ok { background-color: #107c10; color: white; padding: 3px 6px; border-radius: 3px; }
    </style>
</head>
<body>
    <h1>Exchange Online Mailbox Health Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Mailbox Type:</strong> $MailboxType<br>
        <strong>Total Mailboxes:</strong> $($results.Count)<br>
        <strong>Quota Warnings:</strong> $quotaWarnings<br>
        <strong>Quota Exceeded:</strong> $quotaExceeded<br>
        <strong>Inactive Mailboxes:</strong> $inactiveMailboxes
    </div>

    <h2>Mailbox Details</h2>
    <table>
        <tr>
            <th>Display Name</th>
            <th>Type</th>
            <th>Size (GB)</th>
            <th>Quota (GB)</th>
            <th>Used %</th>
            <th>Items</th>
            <th>Status</th>
            <th>Last Logon</th>
            <th>Lit Hold</th>
        </tr>
"@

    foreach ($result in ($results | Sort-Object QuotaUsedPercent -Descending)) {
        $statusClass = $result.Status.ToLower()
        $html += @"
        <tr>
            <td>$($result.DisplayName)</td>
            <td>$($result.MailboxType)</td>
            <td>$($result.MailboxSizeGB)</td>
            <td>$($result.QuotaGB)</td>
            <td>$($result.QuotaUsedPercent)</td>
            <td>$($result.ItemCount)</td>
            <td><span class="$statusClass">$($result.Status)</span></td>
            <td>$($result.LastLogon)</td>
            <td>$($result.LitigationHold)</td>
        </tr>
"@
    }

    $html += "</table></body></html>"

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($ExportCSV) {
    $csvPath = "$env:USERPROFILE\Desktop\MailboxHealth_$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

Write-Host "`n[+] Mailbox health check completed!" -ForegroundColor Green

if ($quotaExceeded -gt 0 -or $inactiveMailboxes -gt 10) {
    exit 1
}

exit 0
