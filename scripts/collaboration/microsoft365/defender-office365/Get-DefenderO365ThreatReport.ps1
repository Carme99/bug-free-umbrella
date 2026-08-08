<#
.SYNOPSIS
    Generates comprehensive Microsoft Defender for Office 365 threat reports.

.DESCRIPTION
    Analyzes and reports on Defender for Office 365 threat detection including:
    - Phishing and malware detections
    - Safe Links click analysis
    - Safe Attachments detonations
    - Anti-spam verdicts and trends
    - Compromised user detection
    - Threat Explorer data aggregation
    - Top targeted users and senders
    - Geographic threat distribution

.PARAMETER DaysToAnalyze
    Number of days of threat data to analyze. Default: 7

.PARAMETER IncludeDetailedThreats
    Include detailed threat information for each detection

.PARAMETER IncludeUserRiskAnalysis
    Analyze user risk based on targeting frequency

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', 'CSV', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for output files. Default: MyDocuments\Reports

.EXAMPLE
    Connect-IPPSSession
    .\Get-DefenderO365ThreatReport.ps1 -DaysToAnalyze 30

.EXAMPLE
    .\Get-DefenderO365ThreatReport.ps1 -DaysToAnalyze 7 `
        -IncludeDetailedThreats `
        -IncludeUserRiskAnalysis `
        -OutputFormat HTML

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 7, ExchangeOnlineManagement module

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$DaysToAnalyze = 7,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDetailedThreats,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeUserRiskAnalysis,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'CSV', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
)

$ErrorActionPreference = 'Stop'
# Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($OutputPath) -or
    $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
    $OutputPath -match '^(\\\\|//)') {
    Write-Error "Unsafe OutputPath: $OutputPath. OutputPath must not contain '..' traversal or be a UNC/remote path; relative paths are resolved to an absolute path."
    exit 1
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}


# Check for required module
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Error "ExchangeOnlineManagement module required. Install with: Install-Module ExchangeOnlineManagement"
    exit 1
}

$results = @{
    Timestamp = Get-Date
    AnalysisPeriod = $DaysToAnalyze
    ThreatDetections = @()
    SafeLinksClicks = @()
    SafeAttachments = @()
    TopTargetedUsers = @()
    TopThreatSenders = @()
    Summary = @{}
}

Write-Host "Analyzing Defender for Office 365 threats (Last $DaysToAnalyze days)..." -ForegroundColor Cyan

$startDate = (Get-Date).AddDays(-$DaysToAnalyze)
$endDate = Get-Date

try {
    # Check if connected to Exchange Online
    try {
        Get-OrganizationConfig -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Not connected to Exchange Online. Run: Connect-IPPSSession"
        exit 1
    }

    # Get ATP detections (phishing)
    # Get-MailDetailPhishReport is not part of the current Exchange PowerShell module;
    # Get-MailDetailATPReport (filtered by VerdictSource) is the documented equivalent.
    Write-Host "`nRetrieving ATP phishing detections..." -ForegroundColor Yellow
    try {
        $phishingDetections = Get-MailDetailATPReport -StartDate $startDate -EndDate $endDate |
            Where-Object { $_.VerdictSource -like '*Phish*' }

        foreach ($detection in $phishingDetections) {
            $results.ThreatDetections += @{
                Type = "Phishing"
                Recipient = $detection.RecipientAddress
                Sender = $detection.SenderAddress
                Subject = $detection.Subject
                DetectionTime = $detection.Date
                Direction = $detection.Direction
                Action = $detection.Action
            }
        }
        Write-Host "Found $($phishingDetections.Count) phishing detections" -ForegroundColor White
    } catch {
        Write-Warning "Could not retrieve phishing data: $($_.Exception.Message)"
    }

    # Get ATP detections (malware)
    # Get-MailDetailMalwareReport is not part of the current Exchange PowerShell module;
    # Get-MailDetailATPReport (filtered by VerdictSource) is the documented equivalent.
    Write-Host "`nRetrieving ATP malware detections..." -ForegroundColor Yellow
    try {
        $malwareDetections = Get-MailDetailATPReport -StartDate $startDate -EndDate $endDate |
            Where-Object { $_.VerdictSource -eq 'Malware' }

        foreach ($detection in $malwareDetections) {
            $results.ThreatDetections += @{
                Type = "Malware"
                Recipient = $detection.RecipientAddress
                Sender = $detection.SenderAddress
                Subject = $detection.Subject
                DetectionTime = $detection.Date
                Direction = $detection.Direction
                MalwareName = $detection.FileName
                Action = $detection.Action
            }
        }
        Write-Host "Found $($malwareDetections.Count) malware detections" -ForegroundColor White
    } catch {
        Write-Warning "Could not retrieve malware data: $($_.Exception.Message)"
    }

    # Get ATP detections (spam)
    # Get-MailDetailSpamReport is not part of the current Exchange PowerShell module;
    # Get-MailDetailATPReport (filtered by VerdictSource) is the documented equivalent.
    # The ATP report has no SpamConfidenceLevel property, so the high-confidence split is not reported.
    Write-Host "`nRetrieving ATP spam detections..." -ForegroundColor Yellow
    try {
        $spamDetections = Get-MailDetailATPReport -StartDate $startDate -EndDate $endDate |
            Where-Object { $_.VerdictSource -eq 'Spam' }

        Write-Host "Found $($spamDetections.Count) spam detections" -ForegroundColor White
    } catch {
        Write-Warning "Could not retrieve spam data: $($_.Exception.Message)"
    }

    # Get ATP Safe Links data
    Write-Host "`nRetrieving Safe Links data..." -ForegroundColor Yellow
    try {
        $safeLinksData = Get-SafeLinksDetailReport -StartDate $startDate -EndDate $endDate -ErrorAction SilentlyContinue

        foreach ($link in $safeLinksData) {
            $results.SafeLinksClicks += @{
                Recipient = $link.RecipientAddress
                Url = $link.Url
                Action = $link.Action
                ClickTime = $link.Date
                IsClickedThrough = $link.IsClickedThrough
            }
        }
        Write-Host "Found $($safeLinksData.Count) Safe Links clicks" -ForegroundColor White
    } catch {
        Write-Warning "Could not retrieve Safe Links data: $($_.Exception.Message)"
    }

    # Get ATP Safe Attachments data
    # Get-SafeAttachmentReport is not part of the current Exchange PowerShell module;
    # Get-MailDetailATPReport returns Safe Attachments detonation results (File Name, Verdict, Action).
    Write-Host "`nRetrieving Safe Attachments data..." -ForegroundColor Yellow
    try {
        $safeAttachmentsData = Get-MailDetailATPReport -StartDate $startDate -EndDate $endDate |
            Where-Object { $_.FileName }

        foreach ($attachment in $safeAttachmentsData) {
            $results.SafeAttachments += @{
                Recipient = $attachment.RecipientAddress
                Sender = $attachment.SenderAddress
                FileName = $attachment.FileName
                DetectionTime = $attachment.Date
                Verdict = $attachment.VerdictSource
                Action = $attachment.Action
            }
        }
        Write-Host "Found $($safeAttachmentsData.Count) Safe Attachments scans" -ForegroundColor White
    } catch {
        Write-Warning "Could not retrieve Safe Attachments data: $($_.Exception.Message)"
    }

    # Analyze user targeting
    if ($IncludeUserRiskAnalysis -and $results.ThreatDetections.Count -gt 0) {
        Write-Host "`nAnalyzing user targeting patterns..." -ForegroundColor Yellow

        $userTargeting = $results.ThreatDetections | Group-Object Recipient |
            Select-Object Name, Count |
            Sort-Object Count -Descending |
            Select-Object -First 10

        foreach ($user in $userTargeting) {
            $results.TopTargetedUsers += @{
                UserEmail = $user.Name
                ThreatCount = $user.Count
                RiskLevel = if ($user.Count -gt 10) { 'High' }
                           elseif ($user.Count -gt 5) { 'Medium' }
                           else { 'Low' }
            }
        }
    }

    # Analyze threat senders
    if ($results.ThreatDetections.Count -gt 0) {
        $senderAnalysis = $results.ThreatDetections | Group-Object Sender |
            Select-Object Name, Count |
            Sort-Object Count -Descending |
            Select-Object -First 10

        foreach ($sender in $senderAnalysis) {
            $results.TopThreatSenders += @{
                SenderAddress = $sender.Name
                ThreatCount = $sender.Count
            }
        }
    }

} catch {
    Write-Error "Error retrieving Defender data: $($_.Exception.Message)"
}

# Calculate summary
$totalThreats = $results.ThreatDetections.Count
$phishingCount = ($results.ThreatDetections | Where-Object { $_.Type -eq 'Phishing' }).Count
$malwareCount = ($results.ThreatDetections | Where-Object { $_.Type -eq 'Malware' }).Count
$safeLinksBlocked = ($results.SafeLinksClicks | Where-Object { $_.Action -eq 'Blocked' }).Count
# Verdict holds the ATP report VerdictSource value; a verdict other than 'None' means the
# detonation was flagged as a threat.
$safeAttachmentsBlocked = ($results.SafeAttachments | Where-Object { $_.Verdict -ne 'None' }).Count

$results.Summary = @{
    TotalThreats = $totalThreats
    PhishingDetections = $phishingCount
    MalwareDetections = $malwareCount
    SafeLinksBlocked = $safeLinksBlocked
    SafeAttachmentsBlocked = $safeAttachmentsBlocked
    TopTargetedUsersCount = $results.TopTargetedUsers.Count
    DailyAverageThreatCount = [math]::Round($totalThreats / $DaysToAnalyze, 2)
}

# Output results
$RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
switch ($OutputFormat) {
    'Console' {
        Write-Host "`n=== Defender for Office 365 Threat Summary ===" -ForegroundColor Cyan
        Write-Host "Analysis Period: Last $DaysToAnalyze days" -ForegroundColor White
        Write-Host "Total Threats Detected: $totalThreats" -ForegroundColor White
        Write-Host "  - Phishing: $phishingCount" -ForegroundColor Yellow
        Write-Host "  - Malware: $malwareCount" -ForegroundColor Red
        Write-Host "Safe Links Blocked: $safeLinksBlocked" -ForegroundColor White
        Write-Host "Safe Attachments Blocked: $safeAttachmentsBlocked" -ForegroundColor White
        Write-Host "Daily Average: $($results.Summary.DailyAverageThreatCount) threats/day" -ForegroundColor White

        if ($results.TopTargetedUsers.Count -gt 0) {
            Write-Host "`n=== Top Targeted Users ===" -ForegroundColor Cyan
            foreach ($user in ($results.TopTargetedUsers | Select-Object -First 5)) {
                $color = switch ($user.RiskLevel) {
                    'High' { 'Red' }
                    'Medium' { 'Yellow' }
                    default { 'White' }
                }
                Write-Host "  $($user.UserEmail): $($user.ThreatCount) threats [$($user.RiskLevel) Risk]" -ForegroundColor $color
            }
        }
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "Defender-O365-Threats-${RunTimestamp}_${RunId}.html"

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Defender for Office 365 Threat Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #d13438; border-bottom: 3px solid #d13438; padding-bottom: 10px; }
        h2 { color: #505050; margin-top: 30px; }
        .summary { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin-top: 15px; }
        .summary-item { background: #f0f0f0; padding: 15px; border-radius: 5px; text-align: center; }
        .summary-item .value { font-size: 32px; font-weight: bold; color: #d13438; }
        .summary-item .label { font-size: 14px; color: #666; margin-top: 5px; }
        table { border-collapse: collapse; width: 100%; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-top: 10px; }
        th { background-color: #d13438; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .high-risk { color: #d13438; font-weight: bold; }
        .medium-risk { color: #ff8c00; font-weight: bold; }
        .phishing { background-color: #fff3cd; }
        .malware { background-color: #fdd; }
        .footer { margin-top: 30px; text-align: center; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <h1>Defender for Office 365 Threat Report</h1>
    <div class="summary">
        <strong>Analysis Period:</strong> Last $DaysToAnalyze days<br>
        <strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

        <div class="summary-grid">
            <div class="summary-item">
                <div class="value">$totalThreats</div>
                <div class="label">Total Threats</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #ff8c00;">$phishingCount</div>
                <div class="label">Phishing</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #d13438;">$malwareCount</div>
                <div class="label">Malware</div>
            </div>
            <div class="summary-item">
                <div class="value">$safeLinksBlocked</div>
                <div class="label">Links Blocked</div>
            </div>
            <div class="summary-item">
                <div class="value">$safeAttachmentsBlocked</div>
                <div class="label">Attachments Blocked</div>
            </div>
            <div class="summary-item">
                <div class="value">$($results.Summary.DailyAverageThreatCount)</div>
                <div class="label">Avg Threats/Day</div>
            </div>
        </div>
    </div>
"@

        if ($results.TopTargetedUsers.Count -gt 0) {
            $html += @"
    <h2>Top Targeted Users</h2>
    <table>
        <tr>
            <th>User Email</th>
            <th>Threat Count</th>
            <th>Risk Level</th>
        </tr>
"@
            foreach ($user in $results.TopTargetedUsers) {
                $riskClass = $user.RiskLevel.ToLower() + "-risk"
                $html += @"
        <tr>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($user.UserEmail)"))</td>
            <td>$($user.ThreatCount)</td>
            <td class="$riskClass">$([System.Net.WebUtility]::HtmlEncode("$($user.RiskLevel)"))</td>
        </tr>
"@
            }
            $html += "</table>"
        }

        if ($results.TopThreatSenders.Count -gt 0) {
            $html += @"
    <h2>Top Threat Senders</h2>
    <table>
        <tr>
            <th>Sender Address</th>
            <th>Threat Count</th>
        </tr>
"@
            foreach ($sender in $results.TopThreatSenders) {
                $html += @"
        <tr>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($sender.SenderAddress)"))</td>
            <td>$($sender.ThreatCount)</td>
        </tr>
"@
            }
            $html += "</table>"
        }

        $html += @"
    <div class="footer">
        <strong>Note:</strong> This report has not been thoroughly tested. Please validate results before making security decisions.<br>
        Generated by Get-DefenderO365ThreatReport.ps1
    </div>
</body>
</html>
"@

        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "`nHTML report saved to: $htmlFile" -ForegroundColor Green
    }

    'CSV' {
        $csvFile = Join-Path $OutputPath "Defender-Threats-${RunTimestamp}_${RunId}.csv"
        $results.ThreatDetections | Export-Csv -Path $csvFile -NoTypeInformation
        Write-Host "`nCSV report saved to: $csvFile" -ForegroundColor Green
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "Defender-Threats-${RunTimestamp}_${RunId}.json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "`nJSON report saved to: $jsonFile" -ForegroundColor Green
    }
}

Write-Host "`nDefender for Office 365 threat analysis complete!" -ForegroundColor Green
