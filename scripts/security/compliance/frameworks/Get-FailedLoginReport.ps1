<#
.SYNOPSIS
    Analyze security event logs for failed login attempts and suspicious activity.

.DESCRIPTION
    Analyzes the Windows Security event log to identify failed login attempts (Event ID 4625) and
    account lockouts (Event ID 4740), then summarizes targeted accounts, source IP addresses, and
    potential brute-force patterns.
    - Maps logon types and failure status codes to friendly descriptions
    - Flags accounts and source IPs with five or more failed attempts as possible brute force
    - Optionally exports CSV and HTML reports to a local Documents\Reports directory
    Side effects: writes report files under Documents\Reports when -ExportReport is supplied.
    Requires Administrator privileges and an audit policy that logs logon events.
    Exit codes: 0 = no failed logins or lockouts found; 1 = activity found or the event log
    could not be queried.

.PARAMETER Hours
    Number of hours to look back in the event log. Default is 24.

.PARAMETER TopCount
    Number of top accounts/IPs to display by failure count. Default is 10.

.PARAMETER ExportReport
    Generate HTML and CSV reports in the local Documents\Reports directory.

.EXAMPLE
    PS C:\> .\Get-FailedLoginReport.ps1

    Analyzes the last 24 hours of failed logins; returns 1 if activity was detected.

.EXAMPLE
    PS C:\> .\Get-FailedLoginReport.ps1 -Hours 48 -TopCount 20 -ExportReport

    Analyzes the last 48 hours, shows the top 20 accounts/IPs, and generates HTML/CSV reports.

.NOTES
    File Name   : Get-FailedLoginReport.ps1
    Author      : Security & Compliance Team
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Hours = 24,

    [Parameter()]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$TopCount = 10,

    [Parameter()]
    [switch]$ExportReport
)

# PSSA note: remaining warnings are intentional/false positives:
# - PSAvoidUsingWriteHost: colored [prefix] console reporting via Write-Host is
#   mandated by the relaunch output standard.
# - PSReviewUnusedParameter: parameters are consumed inside Main (PSSA cannot see
#   through the wrapper).
# - PSShouldProcess on Main: it deliberately uses the script-level CmdletBinding
#   SupportsShouldProcess binding's $PSCmdlet.
$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] ========================================" -ForegroundColor Cyan
        Write-Host "[*]    Failed Login Analysis" -ForegroundColor Cyan
        Write-Host "[*]    Time Range: Last $Hours hours" -ForegroundColor Cyan
        Write-Host "[*] ========================================" -ForegroundColor Cyan

        $StartTime = (Get-Date).AddHours(-$Hours)
        $Results = @()
        $FailedLogins = @()
        $Lockouts = @()

        # Event IDs
        # 4625 = Failed logon
        # 4740 = Account lockout
        # 4624 = Successful logon

        Write-Host "[*] [1/4] Querying Security Event Log..." -ForegroundColor Yellow
        Write-Host "  Searching for events since: $($StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray

        try {
            # Get failed login events (4625)
            Write-Host "[*]   Retrieving failed login attempts..." -ForegroundColor Cyan
            $FailedLoginEvents = @(Get-WinEvent -FilterHashtable @{
                LogName = 'Security'
                ID = 4625
                StartTime = $StartTime
            } -ErrorAction Stop)

            Write-Host "[+]     Found: $($FailedLoginEvents.Count) failed login events" -ForegroundColor Green

        }
        catch {
            if ($_.Exception.Message -like "*No events were found*") {
                Write-Host "[+]     Found: 0 failed login events" -ForegroundColor Green
                $FailedLoginEvents = @()
            }
            else {
                throw ("Unable to query event log: $($_.Exception.Message). Make sure you're running " +
                    "as Administrator and audit policy is enabled.")
            }
        }

        try {
            # Get account lockout events (4740)
            Write-Host "[*]   Retrieving account lockouts..." -ForegroundColor Cyan
            $LockoutEvents = @(Get-WinEvent -FilterHashtable @{
                LogName = 'Security'
                ID = 4740
                StartTime = $StartTime
            } -ErrorAction Stop)

            $lockoutColor = if ($LockoutEvents.Count -gt 0) { 'Red' } else { 'Green' }
            Write-Host "    Found: $($LockoutEvents.Count) lockout events" -ForegroundColor $lockoutColor

        }
        catch {
            if ($_.Exception.Message -like "*No events were found*") {
                Write-Host "[+]     Found: 0 lockout events" -ForegroundColor Green
                $LockoutEvents = @()
            }
            else {
                Write-Verbose "Error querying lockout events: $($_.Exception.Message)"
                $LockoutEvents = @()
            }
        }

        # Parse failed login events
        Write-Host "[*] [2/4] Analyzing failed login attempts..." -ForegroundColor Yellow

        foreach ($Event in $FailedLoginEvents) {
            try {
                $EventXML = [xml]$Event.ToXml()
                $EventData = $EventXML.Event.EventData.Data

                # Extract relevant fields
                $TargetUserName = ($EventData | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
                $TargetDomainName = ($EventData | Where-Object { $_.Name -eq 'TargetDomainName' }).'#text'
                $WorkstationName = ($EventData | Where-Object { $_.Name -eq 'WorkstationName' }).'#text'
                $IpAddress = ($EventData | Where-Object { $_.Name -eq 'IpAddress' }).'#text'
                $LogonType = ($EventData | Where-Object { $_.Name -eq 'LogonType' }).'#text'
                # 4625: the failure status code is documented in 'Status'; 'SubStatus' is
                # retained as supplementary detail (usually the same value).
                $FailureReason = ($EventData | Where-Object { $_.Name -eq 'Status' }).'#text'
                $FailureSubStatus = ($EventData | Where-Object { $_.Name -eq 'SubStatus' }).'#text'

                # Map logon type to friendly name
                $LogonTypeDescription = switch ($LogonType) {
                    '2' { 'Interactive (Console)' }
                    '3' { 'Network (SMB/File Share)' }
                    '4' { 'Batch' }
                    '5' { 'Service' }
                    '7' { 'Unlock' }
                    '8' { 'NetworkCleartext' }
                    '10' { 'Remote Desktop (RDP)' }
                    '11' { 'Cached Credentials' }
                    default { "Unknown ($LogonType)" }
                }

                # Map failure reason to friendly description
                $FailureDescription = switch ($FailureReason) {
                    '0xC0000064' { 'User does not exist' }
                    '0xC000006A' { 'Incorrect password' }
                    '0xC000006D' { 'Bad username or password' }
                    '0xC000006E' { 'Account restriction' }
                    '0xC000006F' { 'Invalid logon hours' }
                    '0xC0000070' { 'Invalid workstation' }
                    '0xC0000071' { 'Password expired' }
                    '0xC0000072' { 'Account disabled' }
                    '0xC0000193' { 'Account expired' }
                    '0xC0000224' { 'Password must change' }
                    '0xC0000234' { 'Account locked out' }
                    default { "Unknown ($FailureReason)" }
                }

                $FailedLogin = [PSCustomObject]@{
                    TimeCreated     = $Event.TimeCreated
                    UserName        = $TargetUserName
                    Domain          = $TargetDomainName
                    Workstation     = $WorkstationName
                    SourceIP        = $IpAddress
                    LogonType       = $LogonTypeDescription
                    FailureReason   = $FailureDescription
                    SubStatus       = $FailureSubStatus
                    EventID         = $Event.Id
                }

                $FailedLogins += $FailedLogin

            }
            catch {
                Write-Verbose "Error parsing event: $($_.Exception.Message)"
            }
        }

        # Parse lockout events
        if ($LockoutEvents.Count -gt 0) {
            Write-Host "[*]   Analyzing account lockouts..." -ForegroundColor Cyan

            foreach ($Event in $LockoutEvents) {
                try {
                    $EventXML = [xml]$Event.ToXml()
                    $EventData = $EventXML.Event.EventData.Data

                    $TargetUserName = ($EventData | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
                    $TargetDomainName = ($EventData | Where-Object { $_.Name -eq 'TargetDomainName' }).'#text'

                    $Lockout = [PSCustomObject]@{
                        TimeCreated = $Event.TimeCreated
                        UserName    = $TargetUserName
                        Domain      = $TargetDomainName
                    }

                    $Lockouts += $Lockout

                }
                catch {
                    Write-Verbose "Error parsing lockout event: $($_.Exception.Message)"
                }
            }
        }

        # Analyze patterns
        Write-Host "[*] [3/4] Identifying patterns and suspicious activity..." -ForegroundColor Yellow

        # Group by username and count failures
        $UserFailureCounts = @($FailedLogins | Group-Object UserName | Sort-Object Count -Descending)

        # Group by source IP
        $IPFailureCounts = @($FailedLogins | Where-Object { $_.SourceIP -and $_.SourceIP -ne '-' } |
            Group-Object SourceIP | Sort-Object Count -Descending)

        # Identify potential brute force (more than 5 failures)
        $BruteForceAccounts = @($UserFailureCounts | Where-Object { $_.Count -ge 5 })
        $BruteForceIPs = @($IPFailureCounts | Where-Object { $_.Count -ge 5 })

        # Display summary
        Write-Host "[*] [4/4] Generating Report..." -ForegroundColor Yellow

        Write-Host "[*] ========================================" -ForegroundColor Cyan
        Write-Host "[*]    Summary" -ForegroundColor Cyan
        Write-Host "[*] ========================================" -ForegroundColor Cyan

        $failedColor = if ($FailedLogins.Count -gt 0) { 'Red' } else { 'Green' }
        $lockoutsColor = if ($Lockouts.Count -gt 0) { 'Red' } else { 'Green' }
        $startText = $StartTime.ToString('yyyy-MM-dd HH:mm')
        $endText = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        Write-Host "Time Period: $startText to $endText" -ForegroundColor White
        Write-Host "Total Failed Login Attempts: $($FailedLogins.Count)" -ForegroundColor $failedColor
        Write-Host "Total Account Lockouts: $($Lockouts.Count)" -ForegroundColor $lockoutsColor
        Write-Host "Unique Accounts Targeted: $($UserFailureCounts.Count)" -ForegroundColor White
        Write-Host "Unique Source IPs: $($IPFailureCounts.Count)" -ForegroundColor White

        # Potential brute force attacks
        if ($BruteForceAccounts.Count -gt 0) {
            Write-Host "[-] ALERT: Potential Brute Force Attack Detected!" -ForegroundColor Red
            Write-Host "  Accounts with >= 5 failed attempts: $($BruteForceAccounts.Count)" -ForegroundColor Yellow
        }

        if ($BruteForceIPs.Count -gt 0) {
            Write-Host "[-] ALERT: Suspicious IP Activity Detected!" -ForegroundColor Red
            Write-Host "  Source IPs with >= 5 failed attempts: $($BruteForceIPs.Count)" -ForegroundColor Yellow
        }

        # Top targeted accounts
        if ($UserFailureCounts.Count -gt 0) {
            Write-Host "[*] ========================================" -ForegroundColor Cyan
            Write-Host "[*]    Top $TopCount Targeted Accounts" -ForegroundColor Cyan
            Write-Host "[*] ========================================" -ForegroundColor Cyan

            $TopUsers = $UserFailureCounts | Select-Object -First $TopCount

            foreach ($User in $TopUsers) {
                $Color = if ($User.Count -ge 10) { 'Red' } elseif ($User.Count -ge 5) { 'Yellow' } else { 'White' }
                Write-Host "  [$($User.Count.ToString().PadLeft(4))] " -ForegroundColor $Color -NoNewline
                Write-Host $User.Name -ForegroundColor White

                # Show recent failures for this user
                $RecentFailures = $FailedLogins | Where-Object { $_.UserName -eq $User.Name } | Select-Object -First 3
                foreach ($Failure in $RecentFailures) {
                    Write-Host "         $($Failure.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')) - "  `
                        -ForegroundColor Gray -NoNewline
                    Write-Host "$($Failure.LogonType) - $($Failure.FailureReason)" -ForegroundColor DarkGray
                }
            }
        }

        # Top source IPs
        if ($IPFailureCounts.Count -gt 0) {
            Write-Host "[*] ========================================" -ForegroundColor Cyan
            Write-Host "[*]    Top Source IP Addresses" -ForegroundColor Cyan
            Write-Host "[*] ========================================" -ForegroundColor Cyan

            $TopIPs = $IPFailureCounts | Select-Object -First $TopCount

            foreach ($IP in $TopIPs) {
                $Color = if ($IP.Count -ge 10) { 'Red' } elseif ($IP.Count -ge 5) { 'Yellow' } else { 'White' }
                Write-Host "  [$($IP.Count.ToString().PadLeft(4))] " -ForegroundColor $Color -NoNewline
                Write-Host $IP.Name -ForegroundColor White
            }
        }

        # Account lockouts
        if ($Lockouts.Count -gt 0) {
            Write-Host "[-] ========================================" -ForegroundColor Red
            Write-Host "[-]    Account Lockouts" -ForegroundColor Red
            Write-Host "[-] ========================================" -ForegroundColor Red

            foreach ($Lockout in $Lockouts) {
                Write-Host "  $($Lockout.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')) - "  `
                    -ForegroundColor Yellow -NoNewline
                Write-Host "$($Lockout.Domain)\$($Lockout.UserName)" -ForegroundColor White
            }
        }

        # Recommendations
        if ($FailedLogins.Count -gt 0 -or $Lockouts.Count -gt 0) {
            Write-Host "[!] ========================================" -ForegroundColor Yellow
            Write-Host "[!]    Recommendations" -ForegroundColor Yellow
            Write-Host "[!] ========================================" -ForegroundColor Yellow

            Write-Host "[-] Immediate Actions:" -ForegroundColor Red
            if ($BruteForceAccounts.Count -gt 0) {
                Write-Host "  Investigate accounts with multiple failed attempts" -ForegroundColor White
                Write-Host "  Consider temporarily disabling heavily targeted accounts" -ForegroundColor White
                Write-Host "  Review recent successful logins for these accounts" -ForegroundColor White
            }

            if ($BruteForceIPs.Count -gt 0) {
                Write-Host "  Block suspicious IP addresses at firewall level" -ForegroundColor White
                Write-Host "  Review RDP/remote access configurations" -ForegroundColor White
                Write-Host "  Enable Network Level Authentication (NLA) for RDP" -ForegroundColor White
            }

            if ($Lockouts.Count -gt 0) {
                Write-Host "  Unlock legitimate user accounts" -ForegroundColor White
                Write-Host "  Investigate source of lockouts" -ForegroundColor White
            }

            Write-Host "[*] Long-term Security Improvements:" -ForegroundColor Cyan
            Write-Host "  Implement multi-factor authentication (MFA)" -ForegroundColor White
            Write-Host "  Use conditional access policies (Azure AD)" -ForegroundColor White
            Write-Host "  Configure account lockout policies (5-10 attempts)" -ForegroundColor White
            Write-Host "  Restrict RDP access via VPN or IP allowlist" -ForegroundColor White
            Write-Host "  Enable Windows Defender Credential Guard" -ForegroundColor White
            Write-Host "  Monitor failed logins regularly (daily/weekly)" -ForegroundColor White
            Write-Host "  Consider using Azure Sentinel or SIEM solution" -ForegroundColor White
        }

        # Export reports if requested
        if ($ExportReport) {
            $ReportPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
            if ($PSCmdlet.ShouldProcess($ReportPath, "Write failed login CSV and HTML reports")) {
                # Validate report directory: reject '..' traversal and UNC remote paths before resolution
                if ([string]::IsNullOrWhiteSpace($ReportPath) -or
                    $ReportPath -match '(^|[\\/])\.\.([\\/]|$)' -or
                    $ReportPath -match '^(\\\\|//)') {
                    throw ("Unsafe report directory: $ReportPath. Report directory must be a local " +
                    "absolute path without '..' traversal.")
                }
                $ReportPath = [System.IO.Path]::GetFullPath($ReportPath)
                if (-not (Test-Path -LiteralPath $ReportPath -PathType Container)) {
                    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
                }

                $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
                $TimestampRunId = "${Timestamp}_${RunId}"

                # CSV Export - Failed Logins
                if ($FailedLogins.Count -gt 0) {
                    $CSVPath = Join-Path $ReportPath "FailedLogins_${TimestampRunId}.csv"
                    $FailedLogins | Export-Csv -Path $CSVPath -NoTypeInformation -ErrorAction Stop
                    Write-Host "[+] CSV Report: $CSVPath" -ForegroundColor Green
                }

                # HTML Export
                $HTMLPath = Join-Path $ReportPath "FailedLoginReport_${TimestampRunId}.html"
                $HTML = @"
<!DOCTYPE html>
<html>
<head>
    <title>Failed Login Report - $Timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .summary-item { margin: 10px 0; font-size: 16px; }
        .alert { background-color: #ffebee; border-left: 4px solid #c62828; padding: 15px; margin: 20px 0; }
        .alert h3 { color: #c62828; margin-top: 0; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px;
            background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); font-size: 13px; }
        th { background-color: #3498db; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .high { background-color: #ffebee; color: #c62828; font-weight: bold; }
        .medium { background-color: #fff3e0; color: #ef6c00; font-weight: bold; }
        .low { background-color: #e8f5e9; color: #2e7d32; }
    </style>
</head>
<body>
    <h1>Failed Login Analysis Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") | <strong>Run ID:</strong> $RunId</p>
    <p><strong>Computer:</strong> $([System.Net.WebUtility]::HtmlEncode("$env:COMPUTERNAME"))</p>
    <p><strong>Time Range:</strong>
        $([System.Net.WebUtility]::HtmlEncode("$($StartTime.ToString('yyyy-MM-dd HH:mm'))")) to
        $([System.Net.WebUtility]::HtmlEncode("$((Get-Date).ToString('yyyy-MM-dd HH:mm'))"))</p>

    <div class="summary">
        <div class="summary-item"><strong>Total Failed Login Attempts:</strong>
            <span style="color: #c62828;">$($FailedLogins.Count)</span></div>
        <div class="summary-item"><strong>Total Account Lockouts:</strong>
            <span style="color: #c62828;">$($Lockouts.Count)</span></div>
        <div class="summary-item"><strong>Unique Accounts Targeted:</strong> $($UserFailureCounts.Count)</div>
        <div class="summary-item"><strong>Unique Source IPs:</strong> $($IPFailureCounts.Count)</div>
    </div>
"@

                if ($BruteForceAccounts.Count -gt 0 -or $BruteForceIPs.Count -gt 0) {
                    $HTML += @"
    <div class="alert">
        <h3>Security Alert</h3>
        <p><strong>Potential brute force attack detected!</strong></p>
"@
                    if ($BruteForceAccounts.Count -gt 0) {
                        $HTML += "<p>Accounts with >= 5 failed attempts: $($BruteForceAccounts.Count)</p>"
                    }
                    if ($BruteForceIPs.Count -gt 0) {
                        $HTML += "<p>Source IPs with >= 5 failed attempts: $($BruteForceIPs.Count)</p>"
                    }
                    $HTML += "</div>"
                }

                if ($UserFailureCounts.Count -gt 0) {
                    $HTML += @"
    <h2>Top Targeted Accounts</h2>
    <table>
        <tr>
            <th>Rank</th>
            <th>Username</th>
            <th>Failed Attempts</th>
            <th>Risk Level</th>
        </tr>
"@
                    $Rank = 1
                    foreach ($User in ($UserFailureCounts | Select-Object -First $TopCount)) {
                        $RiskClass = if ($User.Count -ge 10) { 'high' }
                        elseif ($User.Count -ge 5) { 'medium' } else { 'low' }
                        $RiskText = if ($User.Count -ge 10) { 'High' }
                        elseif ($User.Count -ge 5) { 'Medium' } else { 'Low' }

                        $HTML += @"
        <tr>
            <td>$Rank</td>
            <td><strong>$([System.Net.WebUtility]::HtmlEncode("$($User.Name)"))</strong></td>
            <td>$($User.Count)</td>
            <td class="$RiskClass">$RiskText</td>
        </tr>
"@
                        $Rank++
                    }

                    $HTML += "</table>"
                }

                $HTML += @"
</body>
</html>
"@

                $HTML | Out-File -FilePath $HTMLPath -Encoding UTF8 -ErrorAction Stop
                Write-Host "[+] HTML Report: $HTMLPath" -ForegroundColor Green
            }
        }

        # Exit code contract: 0 = no activity, 1 = failed logins/lockouts detected
        if ($FailedLogins.Count -gt 0 -or $Lockouts.Count -gt 0) {
            Write-Host "[!] Failed login activity detected. Review the report above." -ForegroundColor Yellow
            return 1
        }

        Write-Host "[+] No failed login attempts found in the specified time period." -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
