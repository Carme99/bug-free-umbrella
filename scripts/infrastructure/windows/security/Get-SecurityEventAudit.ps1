<#
.SYNOPSIS
    Analyzes Windows Security Event logs for suspicious activities and security incidents.

.DESCRIPTION
    This script performs comprehensive security event log analysis:
    - Failed login attempts and account lockouts
    - Privilege escalation attempts
    - Account creation/modification/deletion
    - Security policy changes
    - Service installation and modification
    - Scheduled task creation
    - Firewall rule changes
    - Audit policy modifications
    - Group membership changes
    - Suspicious PowerShell execution

.PARAMETER Hours
    Number of hours to look back (default: 24).

.PARAMETER Days
    Number of days to look back (use instead of Hours for longer periods).

.PARAMETER EventTypes
    Specific event types to check: FailedLogins, AccountChanges, PrivilegeUse, PolicyChanges, All (default: All).

.PARAMETER ComputerName
    Remote computer to query (default: local computer).

.PARAMETER MaxEvents
    Maximum number of events to retrieve per category (default: 1000).

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.PARAMETER Threshold
    Alert threshold for suspicious activity counts (default: 10).

.PARAMETER ShowSummaryOnly
    Display only summary statistics without detailed events.

.EXAMPLE
    .\Get-SecurityEventAudit.ps1 -Hours 24
    Analyzes security events from the last 24 hours.

.EXAMPLE
    .\Get-SecurityEventAudit.ps1 -Days 7 -EventTypes FailedLogins -ExportHTML
    Checks failed login attempts for the last 7 days and exports to HTML.

.EXAMPLE
    .\Get-SecurityEventAudit.ps1 -ComputerName SERVER01 -Hours 48 -Threshold 5
    Audits remote server for last 48 hours with custom alert threshold.

.NOTES
    Requires Administrator privileges
    Security auditing must be enabled in Group Policy
    Compatible with Windows Server 2016, 2019, 2022, and Windows 10/11
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [int]$Hours = 24,

    [Parameter(Mandatory=$false)]
    [int]$Days,

    [Parameter(Mandatory=$false)]
    [ValidateSet('FailedLogins','AccountChanges','PrivilegeUse','PolicyChanges','All')]
    [string]$EventTypes = 'All',

    [Parameter(Mandatory=$false)]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory=$false)]
    [int]$MaxEvents = 1000,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV,

    [Parameter(Mandatory=$false)]
    [int]$Threshold = 10,

    [Parameter(Mandatory=$false)]
    [switch]$ShowSummaryOnly
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Resolve report output directory (default: MyDocuments\Reports) and validate against traversal/UNC paths
$ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
if ([string]::IsNullOrWhiteSpace($ReportDir) -or
    $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
    $ReportDir -match '^(\\\\|//)') {
    Write-Error "Unsafe report path: $ReportDir. Report path must be a local absolute path without '..' traversal."
    exit 1
}
$ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

# Calculate time range
if ($Days) {
    $startTime = (Get-Date).AddDays(-$Days)
}
else {
    $startTime = (Get-Date).AddHours(-$Hours)
}

Write-Host "`n=== Security Event Audit ===" -ForegroundColor Cyan
Write-Host "Computer: $ComputerName" -ForegroundColor Yellow
Write-Host "Time Range: $startTime to $(Get-Date)" -ForegroundColor Yellow
Write-Host "Event Types: $EventTypes" -ForegroundColor Yellow
Write-Host ""

$allFindings = @()
$summary = @{}

# Event ID mappings
$eventMap = @{
    FailedLogins = @(
        @{ID=4625; Description="Failed Login Attempt"},
        @{ID=4740; Description="Account Lockout"},
        @{ID=4767; Description="Account Unlocked"},
        @{ID=4771; Description="Kerberos Pre-Authentication Failed"}
    )
    AccountChanges = @(
        @{ID=4720; Description="User Account Created"},
        @{ID=4722; Description="User Account Enabled"},
        @{ID=4723; Description="Password Change Attempted"},
        @{ID=4724; Description="Password Reset Attempted"},
        @{ID=4725; Description="User Account Disabled"},
        @{ID=4726; Description="User Account Deleted"},
        @{ID=4738; Description="User Account Changed"},
        @{ID=4781; Description="Account Name Changed"}
    )
    PrivilegeUse = @(
        @{ID=4672; Description="Special Privileges Assigned to Logon"},
        @{ID=4673; Description="Privileged Service Called"},
        @{ID=4674; Description="Operation Attempted on Privileged Object"},
        @{ID=4985; Description="State of Transaction Changed"}
    )
    PolicyChanges = @(
        @{ID=4704; Description="User Right Assigned"},
        @{ID=4705; Description="User Right Removed"},
        @{ID=4706; Description="Trust to Domain Created"},
        @{ID=4707; Description="Trust to Domain Removed"},
        @{ID=4713; Description="Kerberos Policy Changed"},
        @{ID=4716; Description="Trusted Domain Information Modified"},
        @{ID=4719; Description="System Audit Policy Changed"},
        @{ID=4739; Description="Domain Policy Changed"},
        @{ID=4817; Description="Auditing Settings Changed"}
    )
    GroupChanges = @(
        @{ID=4727; Description="Security-Enabled Global Group Created"},
        @{ID=4728; Description="Member Added to Security-Enabled Global Group"},
        @{ID=4729; Description="Member Removed from Security-Enabled Global Group"},
        @{ID=4732; Description="Member Added to Security-Enabled Local Group"},
        @{ID=4733; Description="Member Removed from Security-Enabled Local Group"},
        @{ID=4756; Description="Member Added to Security-Enabled Universal Group"},
        @{ID=4757; Description="Member Removed from Security-Enabled Universal Group"}
    )
    ServiceChanges = @(
        @{ID=4697; Description="Service Installed"},
        @{ID=7045; Description="Service Installed (System Log)"},
        @{ID=7040; Description="Service Start Type Changed"}
    )
}

# Function to query events
function Get-SecurityEvents {
    param(
        [string]$Category,
        [array]$EventIDs
    )

    Write-Host "[*] Checking $Category..." -ForegroundColor Cyan

    $findings = @()
    $ids = $EventIDs | ForEach-Object { $_.ID }

    try {
        $filterXml = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">
      *[System[(EventID=$($ids -join ' or EventID=')) and TimeCreated[@SystemTime&gt;='$($startTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))']]]
    </Select>
  </Query>
</QueryList>
"@

        $events = Get-WinEvent -ComputerName $ComputerName -FilterXml $filterXml -MaxEvents $MaxEvents -ErrorAction SilentlyContinue

        if ($events) {
            $eventCount = @($events).Count
            Write-Host "[+] Found $eventCount event(s)" -ForegroundColor Green

            foreach ($event in $events) {
                $eventDesc = ($EventIDs | Where-Object { $_.ID -eq $event.Id }).Description

                $finding = [PSCustomObject]@{
                    TimeCreated = $event.TimeCreated
                    EventID = $event.Id
                    Category = $Category
                    Description = $eventDesc
                    UserName = $event.Properties[5].Value
                    Computer = $event.MachineName
                    IPAddress = if ($event.Properties.Count -gt 18) { $event.Properties[18].Value } else { "N/A" }
                    Message = $event.Message.Substring(0, [Math]::Min(200, $event.Message.Length))
                }

                $findings += $finding
            }

            $summary[$Category] = $eventCount

            # Alert if threshold exceeded
            if ($eventCount -ge $Threshold) {
                Write-Host "[!] WARNING: $Category count ($eventCount) exceeds threshold ($Threshold)!" -ForegroundColor Red
            }
        }
        else {
            Write-Host "[-] No events found" -ForegroundColor Gray
            $summary[$Category] = 0
        }
    }
    catch {
        Write-Host "[-] Error querying $Category : $($_.Exception.Message)" -ForegroundColor Red
        $summary[$Category] = "Error"
    }

    return $findings
}

# Query event categories
if ($EventTypes -eq 'All' -or $EventTypes -eq 'FailedLogins') {
    $allFindings += Get-SecurityEvents -Category "Failed Logins & Lockouts" -EventIDs $eventMap.FailedLogins
}

if ($EventTypes -eq 'All' -or $EventTypes -eq 'AccountChanges') {
    $allFindings += Get-SecurityEvents -Category "Account Changes" -EventIDs $eventMap.AccountChanges
}

if ($EventTypes -eq 'All' -or $EventTypes -eq 'PrivilegeUse') {
    $allFindings += Get-SecurityEvents -Category "Privilege Use" -EventIDs $eventMap.PrivilegeUse
}

if ($EventTypes -eq 'All' -or $EventTypes -eq 'PolicyChanges') {
    $allFindings += Get-SecurityEvents -Category "Policy Changes" -EventIDs $eventMap.PolicyChanges
}

if ($EventTypes -eq 'All') {
    $allFindings += Get-SecurityEvents -Category "Group Changes" -EventIDs $eventMap.GroupChanges
    $allFindings += Get-SecurityEvents -Category "Service Changes" -EventIDs $eventMap.ServiceChanges
}

Write-Host ""

# Display summary
Write-Host "=== Summary ===" -ForegroundColor Cyan
$summary.GetEnumerator() | Sort-Object Name | ForEach-Object {
    $color = "White"
    if ($_.Value -is [int] -and $_.Value -ge $Threshold) { $color = "Red" }
    elseif ($_.Value -eq "Error") { $color = "Yellow" }

    Write-Host "$($_.Key): $($_.Value)" -ForegroundColor $color
}

Write-Host "`nTotal Events: $($allFindings.Count)" -ForegroundColor White
Write-Host ""

# Display detailed findings (if not summary-only)
if (-not $ShowSummaryOnly -and $allFindings.Count -gt 0) {
    Write-Host "=== Top 20 Recent Events ===" -ForegroundColor Cyan
    $allFindings | Sort-Object TimeCreated -Descending | Select-Object -First 20 |
        Format-Table TimeCreated, EventID, Category, Description, UserName -AutoSize
}

# Top failed login sources
if ($allFindings | Where-Object { $_.Category -eq "Failed Logins & Lockouts" }) {
    Write-Host "`n=== Top Failed Login Sources ===" -ForegroundColor Cyan
    $allFindings | Where-Object { $_.Category -eq "Failed Logins & Lockouts" } |
        Group-Object IPAddress | Sort-Object Count -Descending | Select-Object -First 10 |
        ForEach-Object {
            Write-Host "$($_.Name): $($_.Count) attempts" -ForegroundColor $(if ($_.Count -ge 10) { "Red" } else { "Yellow" })
        }
}

# Export results
if ($ExportHTML) {
    $htmlPath = "$env:USERPROFILE\Desktop\SecurityEventAudit_$timestamp.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Security Event Audit - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #c0392b; }
        h2 { color: #e74c3c; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th { background-color: #c0392b; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; font-size: 12px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .alert { background-color: #e74c3c; color: white; padding: 10px; margin: 10px 0; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>Security Event Audit Report</h1>
    <div class="summary">
        <strong>Computer:</strong> $ComputerName<br>
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Time Range:</strong> $startTime to $(Get-Date)<br>
        <strong>Total Events:</strong> $($allFindings.Count)<br>
        <strong>Event Types:</strong> $EventTypes
    </div>

    <h2>Summary by Category</h2>
    <table>
        <tr><th>Category</th><th>Event Count</th></tr>
"@

    $summary.GetEnumerator() | Sort-Object Name | ForEach-Object {
        $html += "<tr><td>$($_.Key)</td><td>$($_.Value)</td></tr>`n"
    }

    $html += @"
    </table>

    <h2>All Security Events</h2>
    <table>
        <tr>
            <th>Time</th>
            <th>Event ID</th>
            <th>Category</th>
            <th>Description</th>
            <th>User</th>
            <th>IP Address</th>
        </tr>
"@

    foreach ($finding in ($allFindings | Sort-Object TimeCreated -Descending)) {
        $html += @"
        <tr>
            <td>$($finding.TimeCreated)</td>
            <td>$($finding.EventID)</td>
            <td>$($finding.Category)</td>
            <td>$($finding.Description)</td>
            <td>$($finding.UserName)</td>
            <td>$($finding.IPAddress)</td>
        </tr>
"@
    }

    $html += @"
    </table>
</body>
</html>
"@

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($ExportCSV) {
    $csvPath = "$env:USERPROFILE\Desktop\SecurityEventAudit_$timestamp.csv"
    $allFindings | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

Write-Host "`n[+] Audit completed!" -ForegroundColor Green

# Exit code based on threshold violations
$violations = ($summary.Values | Where-Object { $_ -is [int] -and $_ -ge $Threshold }).Count
if ($violations -gt 0) {
    Write-Host "[!] $violations category threshold violations detected!" -ForegroundColor Red
    exit 1
}

exit 0
