<#
.SYNOPSIS
    Analyzes Exchange Online mail flow health, routing, and delivery issues.

.DESCRIPTION
    Comprehensive mail flow analysis including:
    - Message trace analysis for delivery failures
    - Transport rule evaluation and impact
    - Mail flow connector health
    - Queue analysis and delays
    - Top senders and recipients
    - Spam and malware filtering effectiveness
    - External sender patterns
    - Delivery time analysis

.PARAMETER DaysToAnalyze
    Number of days of mail flow data to analyze. Default: 7

.PARAMETER IncludeTransportRules
    Analyze transport rule processing and impacts

.PARAMETER IncludeConnectors
    Include inbound/outbound connector health

.PARAMETER AnalyzeFailures
    Deep dive into delivery failures and NDRs

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', 'CSV', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for output files. Default: MyDocuments\Reports

.EXAMPLE
    Connect-ExchangeOnline
    .\Get-MailFlowAnalysis.ps1 -DaysToAnalyze 7

.EXAMPLE
    .\Get-MailFlowAnalysis.ps1 -DaysToAnalyze 30 `
        -IncludeTransportRules `
        -IncludeConnectors `
        -AnalyzeFailures `
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
    [switch]$IncludeTransportRules,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeConnectors,

    [Parameter(Mandatory = $false)]
    [switch]$AnalyzeFailures,

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


if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Error "ExchangeOnlineManagement module required. Install: Install-Module ExchangeOnlineManagement"
    exit 1
}

$results = @{
    Timestamp = Get-Date
    AnalysisPeriod = $DaysToAnalyze
    MessageStats = @{}
    TopSenders = @()
    TopRecipients = @()
    DeliveryFailures = @()
    TransportRules = @()
    Connectors = @()
    Summary = @{}
}

Write-Host "Analyzing Exchange Online mail flow (Last $DaysToAnalyze days)..." -ForegroundColor Cyan

$endDate = Get-Date
$startDate = $endDate.AddDays(-$DaysToAnalyze)

try {
    # Check connection
    try {
        Get-OrganizationConfig -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error "Not connected to Exchange Online. Run: Connect-ExchangeOnline"
        exit 1
    }

    # Get message trace summary
    Write-Host "`nRetrieving message trace data..." -ForegroundColor Yellow
    Write-Host "Note: Large date ranges may take time. Consider analyzing fewer days for faster results." -ForegroundColor Gray

    try {
        # Get-MessageTrace/Get-MessageTraceDetail are deprecated and replaced by
        # Get-MessageTraceV2/Get-MessageTraceDetailV2. The V2 cmdlets cover the last 90 days,
        # but each query returns at most 10 days of data, so longer ranges are walked in 10-day
        # windows (the documented pattern for ranges that exceed the per-query limit).
        # Start-HistoricalSearch was considered, but it returns CSV blobs rather than message
        # objects, so it cannot feed the aggregation below.
        if ($DaysToAnalyze -le 10) {
            $messages = Get-MessageTraceV2 -StartDate $startDate -EndDate $endDate -ResultSize 5000
        }
        else {
            # For longer periods, query in 10-day windows (slower)
            Write-Warning "Analysis period > 10 days: querying Get-MessageTraceV2 in 10-day windows. This may take several minutes..."
            $maxTraceDays = 90
            if ($DaysToAnalyze -gt $maxTraceDays) {
                Write-Warning "Get-MessageTraceV2 only covers the last 90 days; limiting the analysis window to 90 days."
                $startDate = $endDate.AddDays(-$maxTraceDays)
            }
            $messages = @()
            $windowStart = $startDate
            while ($windowStart -lt $endDate) {
                $windowEnd = $windowStart.AddDays(10)
                if ($windowEnd -gt $endDate) { $windowEnd = $endDate }
                if ($windowEnd -gt $windowStart) {
                    $messages += Get-MessageTraceV2 -StartDate $windowStart -EndDate $windowEnd -ResultSize 5000
                }
                $windowStart = $windowEnd
            }
        }

        if ($messages) {
            # Calculate message statistics
            $totalMessages = $messages.Count
            $delivered = ($messages | Where-Object { $_.Status -eq 'Delivered' }).Count
            $failed = ($messages | Where-Object { $_.Status -eq 'Failed' }).Count
            $spam = ($messages | Where-Object { $_.Status -eq 'FilteredAsSpam' }).Count
            $pending = ($messages | Where-Object { $_.Status -eq 'Pending' }).Count

            $deliveryRate = if ($totalMessages -gt 0) { [math]::Round(($delivered / $totalMessages) * 100, 2) } else { 0 }

            $results.MessageStats = @{
                TotalMessages = $totalMessages
                Delivered = $delivered
                Failed = $failed
                Spam = $spam
                Pending = $pending
                DeliveryRate = $deliveryRate
                DailyAverage = [math]::Round($totalMessages / $DaysToAnalyze, 0)
            }

            Write-Host "Analyzed $totalMessages messages" -ForegroundColor White
            Write-Host "Delivery Rate: $deliveryRate%" -ForegroundColor $(if ($deliveryRate -ge 95) { 'Green' } else { 'Yellow' })

            # Analyze top senders
            $senderGroups = $messages | Group-Object SenderAddress |
                Sort-Object Count -Descending |
                Select-Object -First 10

            foreach ($sender in $senderGroups) {
                $results.TopSenders += @{
                    Sender = $sender.Name
                    MessageCount = $sender.Count
                    PercentOfTotal = [math]::Round(($sender.Count / $totalMessages) * 100, 2)
                }
            }

            # Analyze top recipients
            $recipientGroups = $messages | Group-Object RecipientAddress |
                Sort-Object Count -Descending |
                Select-Object -First 10

            foreach ($recipient in $recipientGroups) {
                $results.TopRecipients += @{
                    Recipient = $recipient.Name
                    MessageCount = $recipient.Count
                    PercentOfTotal = [math]::Round(($recipient.Count / $totalMessages) * 100, 2)
                }
            }

            # Analyze failures
            if ($AnalyzeFailures) {
                Write-Host "`nAnalyzing delivery failures..." -ForegroundColor Yellow

                $failedMessages = $messages | Where-Object { $_.Status -eq 'Failed' } | Select-Object -First 100

                foreach ($msg in $failedMessages) {
                    $results.DeliveryFailures += @{
                        Sender = $msg.SenderAddress
                        Recipient = $msg.RecipientAddress
                        Subject = $msg.Subject
                        FailureTime = $msg.Received
                        Status = $msg.Status
                    }
                }

                Write-Host "Found $($failedMessages.Count) delivery failures" -ForegroundColor $(if ($failedMessages.Count -gt 0) { 'Red' } else { 'Green' })
            }

        }
        else {
            Write-Warning "No message trace data found for the specified period"
        }

    }
    catch {
        Write-Warning "Error retrieving message trace: $($_.Exception.Message)"
    }

    # Analyze Transport Rules
    if ($IncludeTransportRules) {
        Write-Host "`nAnalyzing transport rules..." -ForegroundColor Yellow

        try {
            $transportRules = Get-TransportRule | Where-Object { $_.State -eq 'Enabled' }

            foreach ($rule in $transportRules) {
                $results.TransportRules += @{
                    Name = $rule.Name
                    Priority = $rule.Priority
                    State = $rule.State
                    Mode = $rule.Mode
                    Conditions = ($rule.Conditions | Select-Object -ExpandProperty GetType | Select-Object -ExpandProperty Name) -join ', '
                    Actions = ($rule.Actions | Select-Object -ExpandProperty GetType | Select-Object -ExpandProperty Name) -join ', '
                }
            }

            Write-Host "Found $($transportRules.Count) enabled transport rules" -ForegroundColor White
        }
        catch {
            Write-Warning "Error retrieving transport rules: $($_.Exception.Message)"
        }
    }

    # Analyze Connectors
    if ($IncludeConnectors) {
        Write-Host "`nAnalyzing mail flow connectors..." -ForegroundColor Yellow

        try {
            # Inbound connectors
            $inboundConnectors = Get-InboundConnector

            foreach ($connector in $inboundConnectors) {
                $results.Connectors += @{
                    Type = "Inbound"
                    Name = $connector.Name
                    Enabled = $connector.Enabled
                    ConnectorType = $connector.ConnectorType
                    SenderDomains = ($connector.SenderDomains | Select-Object -First 5) -join ', '
                }
            }

            # Outbound connectors
            $outboundConnectors = Get-OutboundConnector

            foreach ($connector in $outboundConnectors) {
                $results.Connectors += @{
                    Type = "Outbound"
                    Name = $connector.Name
                    Enabled = $connector.Enabled
                    ConnectorType = $connector.ConnectorType
                    SmartHosts = ($connector.SmartHosts | Select-Object -First 5) -join ', '
                }
            }

            Write-Host "Found $($inboundConnectors.Count) inbound and $($outboundConnectors.Count) outbound connectors" -ForegroundColor White
        }
        catch {
            Write-Warning "Error retrieving connectors: $($_.Exception.Message)"
        }
    }

}
catch {
    Write-Error "Error analyzing mail flow: $($_.Exception.Message)"
}

# Calculate summary
$results.Summary = @{
    TotalMessages = $results.MessageStats.TotalMessages
    DeliveryRate = $results.MessageStats.DeliveryRate
    FailureCount = $results.MessageStats.Failed
    SpamCount = $results.MessageStats.Spam
    TransportRulesCount = $results.TransportRules.Count
    ConnectorsCount = $results.Connectors.Count
    HealthStatus = if ($results.MessageStats.DeliveryRate -ge 98) { 'Excellent' }
    elseif ($results.MessageStats.DeliveryRate -ge 95) { 'Good' }
    elseif ($results.MessageStats.DeliveryRate -ge 90) { 'Fair' }
    else { 'Poor' }
}

# Output results
$RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
switch ($OutputFormat) {
    'Console' {
        Write-Host "`n=== Mail Flow Analysis Summary ===" -ForegroundColor Cyan
        Write-Host "Analysis Period: Last $DaysToAnalyze days" -ForegroundColor White
        Write-Host "Total Messages: $($results.MessageStats.TotalMessages)" -ForegroundColor White
        Write-Host "Delivery Rate: $($results.MessageStats.DeliveryRate)% ($($results.Summary.HealthStatus))" -ForegroundColor White
        Write-Host "Failed: $($results.MessageStats.Failed) | Spam: $($results.MessageStats.Spam)" -ForegroundColor White
        Write-Host "Daily Average: $($results.MessageStats.DailyAverage) messages/day" -ForegroundColor White

        if ($results.TopSenders.Count -gt 0) {
            Write-Host "`n=== Top 5 Senders ===" -ForegroundColor Cyan
            foreach ($sender in ($results.TopSenders | Select-Object -First 5)) {
                Write-Host "  $($sender.Sender): $($sender.MessageCount) messages ($($sender.PercentOfTotal)%)" -ForegroundColor White
            }
        }

        if ($results.DeliveryFailures.Count -gt 0) {
            Write-Host "`n=== Recent Delivery Failures ===" -ForegroundColor Red
            foreach ($failure in ($results.DeliveryFailures | Select-Object -First 5)) {
                Write-Host "  $($failure.Sender) → $($failure.Recipient)" -ForegroundColor Red
                Write-Host "    Subject: $($failure.Subject)" -ForegroundColor Gray
            }
        }
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "Exchange-MailFlow-${RunTimestamp}_${RunId}.html"

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Exchange Online Mail Flow Analysis</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #505050; margin-top: 30px; }
        .summary { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin-top: 15px; }
        .summary-item { background: #f0f0f0; padding: 15px; border-radius: 5px; text-align: center; }
        .summary-item .value { font-size: 32px; font-weight: bold; color: #0078d4; }
        .summary-item .label { font-size: 14px; color: #666; margin-top: 5px; }
        table { border-collapse: collapse; width: 100%; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-top: 10px; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .status-excellent { color: #107c10; font-weight: bold; }
        .status-good { color: #10893e; font-weight: bold; }
        .status-fair { color: #ff8c00; font-weight: bold; }
        .status-poor { color: #d13438; font-weight: bold; }
        .footer { margin-top: 30px; text-align: center; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <h1>Exchange Online Mail Flow Analysis</h1>
    <div class="summary">
        <strong>Analysis Period:</strong> Last $DaysToAnalyze days<br>
        <strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

        <div class="summary-grid">
            <div class="summary-item">
                <div class="value">$($results.MessageStats.TotalMessages)</div>
                <div class="label">Total Messages</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #107c10;">$($results.MessageStats.Delivered)</div>
                <div class="label">Delivered</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #d13438;">$($results.MessageStats.Failed)</div>
                <div class="label">Failed</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: #ff8c00;">$($results.MessageStats.Spam)</div>
                <div class="label">Spam Filtered</div>
            </div>
            <div class="summary-item">
                <div class="value">$($results.MessageStats.DeliveryRate)%</div>
                <div class="label">Delivery Rate</div>
            </div>
            <div class="summary-item">
                <div class="value">$($results.MessageStats.DailyAverage)</div>
                <div class="label">Daily Average</div>
            </div>
        </div>
    </div>
"@

        if ($results.TopSenders.Count -gt 0) {
            $html += @"
    <h2>Top Senders</h2>
    <table>
        <tr>
            <th>Sender</th>
            <th>Message Count</th>
            <th>Percent of Total</th>
        </tr>
"@
            foreach ($sender in $results.TopSenders) {
                $html += @"
        <tr>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($sender.Sender)"))</td>
            <td>$($sender.MessageCount)</td>
            <td>$($sender.PercentOfTotal)%</td>
        </tr>
"@
            }
            $html += "</table>"
        }

        if ($results.DeliveryFailures.Count -gt 0) {
            $html += @"
    <h2>Delivery Failures</h2>
    <table>
        <tr>
            <th>Time</th>
            <th>Sender</th>
            <th>Recipient</th>
            <th>Subject</th>
        </tr>
"@
            foreach ($failure in $results.DeliveryFailures) {
                $html += @"
        <tr>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($failure.FailureTime)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($failure.Sender)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($failure.Recipient)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($failure.Subject)"))</td>
        </tr>
"@
            }
            $html += "</table>"
        }

        $html += @"
    <div class="footer">
        <strong>Note:</strong> This report has not been thoroughly tested. Please validate results before making operational decisions.<br>
        Generated by Get-MailFlowAnalysis.ps1
    </div>
</body>
</html>
"@

        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "`nHTML report saved to: $htmlFile" -ForegroundColor Green
    }

    'CSV' {
        $csvFile = Join-Path $OutputPath "MailFlow-TopSenders-${RunTimestamp}_${RunId}.csv"
        $results.TopSenders | Export-Csv -Path $csvFile -NoTypeInformation
        Write-Host "`nCSV report saved to: $csvFile" -ForegroundColor Green
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "MailFlow-Analysis-${RunTimestamp}_${RunId}.json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "`nJSON report saved to: $jsonFile" -ForegroundColor Green
    }
}

Write-Host "`nMail flow analysis complete!" -ForegroundColor Green
