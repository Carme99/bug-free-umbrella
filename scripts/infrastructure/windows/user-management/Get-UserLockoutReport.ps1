<#
.SYNOPSIS
    Reports on user account lockouts and analyzes lockout sources.

.DESCRIPTION
    This script provides comprehensive user account lockout analysis:
    - Recent account lockouts
    - Lockout sources (computers/IPs)
    - Failed authentication attempts
    - Password spray detection
    - Lockout patterns and trends
    - Top targeted accounts

.PARAMETER Hours
    Number of hours to analyze (default: 24).

.PARAMETER Days
    Number of days to analyze (use instead of Hours for longer periods).

.PARAMETER Username
    Specific username to analyze.

.PARAMETER IncludeSource
    Include detailed source information (computers/IPs).

.PARAMETER DetectBruteForce
    Attempt to detect brute force/password spray attacks.

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Get-UserLockoutReport.ps1 -Hours 24
    Analyzes lockouts from the last 24 hours.

.EXAMPLE
    .\Get-UserLockoutReport.ps1 -Username "jdoe" -Days 7 -IncludeSource
    Analyzes specific user's lockouts for 7 days with source details.

.EXAMPLE
    .\Get-UserLockoutReport.ps1 -DetectBruteForce -ExportHTML
    Detects brute force attempts and exports report.

.NOTES
    Requires Administrator privileges
    Requires access to Domain Controllers for full analysis
    Compatible with Windows Server 2016, 2019, 2022
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [int]$Hours = 24,

    [Parameter(Mandatory=$false)]
    [int]$Days,

    [Parameter(Mandatory=$false)]
    [string]$Username,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeSource,

    [Parameter(Mandatory=$false)]
    [switch]$DetectBruteForce,

    [Parameter(Mandatory=$false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory=$false)]
    [switch]$ExportCSV
)

#Requires -Modules ActiveDirectory

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Reports directory (internal output location)
$ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
# Validate report directory: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($ReportDir) -or
    $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
    $ReportDir -match '^(\\\\|//)') {
    Write-Error "Unsafe report directory: $ReportDir. Report directory must be a local absolute path without '..' traversal."
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

Write-Host "`n=== User Account Lockout Report ===" -ForegroundColor Cyan
Write-Host "Time Range: $startTime to $(Get-Date)" -ForegroundColor Yellow
if ($Username) {
    Write-Host "Username Filter: $Username" -ForegroundColor Yellow
}
Write-Host ""

$lockouts = @()
$failedLogins = @()

# Get domain controllers
Write-Host "[*] Retrieving domain controllers..." -ForegroundColor Cyan
$dcs = Get-ADDomainController -Filter *

Write-Host "[+] Found $($dcs.Count) domain controller(s)" -ForegroundColor Green
Write-Host ""

# Query each DC for lockout events
foreach ($dc in $dcs) {
    Write-Host "[*] Querying $($dc.HostName)..." -ForegroundColor Cyan

    try {
        # Event ID 4740 = Account Lockout
        $filterXml = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">
      *[System[(EventID=4740 or EventID=4625) and TimeCreated[@SystemTime&gt;='$($startTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))']]]
    </Select>
  </Query>
</QueryList>
"@

        $eventErrors = @()
        $events = Get-WinEvent -ComputerName $dc.HostName -FilterXml $filterXml -ErrorAction SilentlyContinue -ErrorVariable eventErrors

        $unexpectedErrors = $eventErrors | Where-Object {
            $_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*'
        }
        if ($unexpectedErrors) {
            throw $unexpectedErrors[0]
        }

        if ($events) {
            Write-Host "[+] Found $($events.Count) events on $($dc.HostName)" -ForegroundColor Green

            foreach ($event in $events) {
                $eventXml = [xml]$event.ToXml()

                if ($event.Id -eq 4740) {
                    # Lockout event
                    $targetUser = $eventXml.Event.EventData.Data | Where-Object { $_.Name -eq 'TargetUserName' } | Select-Object -ExpandProperty '#text'
                    $callerComputer = $eventXml.Event.EventData.Data | Where-Object { $_.Name -eq 'TargetDomainName' } | Select-Object -ExpandProperty '#text'

                    if ($Username -and $targetUser -ne $Username) {
                        continue
                    }

                    $lockouts += [PSCustomObject]@{
                        TimeCreated = $event.TimeCreated
                        Username = $targetUser
                        SourceComputer = $callerComputer
                        DomainController = $dc.HostName
                        EventID = 4740
                        Type = "Lockout"
                    }
                }
                elseif ($event.Id -eq 4625) {
                    # Failed login
                    $targetUser = $eventXml.Event.EventData.Data | Where-Object { $_.Name -eq 'TargetUserName' } | Select-Object -ExpandProperty '#text'
                    $workstation = $eventXml.Event.EventData.Data | Where-Object { $_.Name -eq 'WorkstationName' } | Select-Object -ExpandProperty '#text'
                    $ipAddress = $eventXml.Event.EventData.Data | Where-Object { $_.Name -eq 'IpAddress' } | Select-Object -ExpandProperty '#text'

                    if ($Username -and $targetUser -ne $Username) {
                        continue
                    }

                    $failedLogins += [PSCustomObject]@{
                        TimeCreated = $event.TimeCreated
                        Username = $targetUser
                        SourceComputer = $workstation
                        IPAddress = $ipAddress
                        DomainController = $dc.HostName
                        EventID = 4625
                        Type = "Failed Login"
                    }
                }
            }
        }
        else {
            Write-Host "[-] No events found on $($dc.HostName)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "[-] Error querying $($dc.HostName): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""

# Display results
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Total Lockouts: $($lockouts.Count)" -ForegroundColor $(if ($lockouts.Count -gt 0) { "Red" } else { "Green" })
Write-Host "Total Failed Logins: $($failedLogins.Count)" -ForegroundColor Yellow
Write-Host ""

if ($lockouts.Count -gt 0) {
    Write-Host "=== Recent Lockouts ===" -ForegroundColor Cyan
    $lockouts | Sort-Object TimeCreated -Descending | Select-Object -First 20 TimeCreated, Username, SourceComputer, DomainController |
        Format-Table -AutoSize

    # Top locked out users
    Write-Host "`n=== Top Locked Out Users ===" -ForegroundColor Cyan
    $lockouts | Group-Object Username | Sort-Object Count -Descending | Select-Object -First 10 |
        ForEach-Object {
            Write-Host "$($_.Name): $($_.Count) lockout(s)" -ForegroundColor $(if ($_.Count -ge 5) { "Red" } else { "Yellow" })
        }
}

if ($IncludeSource -and $lockouts.Count -gt 0) {
    Write-Host "`n=== Lockout Sources ===" -ForegroundColor Cyan
    $lockouts | Group-Object SourceComputer | Sort-Object Count -Descending | Select-Object -First 10 |
        ForEach-Object {
            Write-Host "$($_.Name): $($_.Count) lockout(s)" -ForegroundColor Yellow
        }
}

# Brute force detection
if ($DetectBruteForce) {
    Write-Host "`n=== Brute Force Detection ===" -ForegroundColor Cyan

    # Look for patterns: multiple users from same source
    $sourceCounts = $failedLogins | Group-Object SourceComputer | Where-Object { $_.Count -ge 10 }

    if ($sourceCounts) {
        Write-Host "[!] Potential brute force detected!" -ForegroundColor Red
        foreach ($source in $sourceCounts) {
            $uniqueUsers = ($source.Group | Select-Object -ExpandProperty Username -Unique).Count
            Write-Host "  Source: $($source.Name)" -ForegroundColor Red
            Write-Host "  Failed Attempts: $($source.Count)" -ForegroundColor Red
            Write-Host "  Unique Users Targeted: $uniqueUsers" -ForegroundColor Red
            Write-Host ""
        }
    }
    else {
        Write-Host "[+] No obvious brute force patterns detected" -ForegroundColor Green
    }

    # Password spray detection: many different usernames in short time
    $timeWindow = 300 # 5 minutes
    $sprayThreshold = 10

    $groupedByTime = $failedLogins | Group-Object { [Math]::Floor(($_.TimeCreated - $startTime).TotalSeconds / $timeWindow) }

    foreach ($group in $groupedByTime) {
        $uniqueUsers = ($group.Group | Select-Object -ExpandProperty Username -Unique).Count
        if ($uniqueUsers -ge $sprayThreshold) {
            Write-Host "[!] Potential password spray detected:" -ForegroundColor Red
            Write-Host "  Time: $($group.Group[0].TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Red
            Write-Host "  Unique Users: $uniqueUsers" -ForegroundColor Red
            Write-Host "  Total Attempts: $($group.Count)" -ForegroundColor Red
            Write-Host ""
        }
    }
}

# Export results
if ($ExportHTML) {
    $htmlPath = Join-Path $ReportDir "UserLockoutReport_$timestamp.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>User Lockout Report - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #c0392b; }
        h2 { color: #e74c3c; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; }
        th { background-color: #c0392b; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; font-size: 12px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>User Account Lockout Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Time Range:</strong> $startTime to $(Get-Date)<br>
        <strong>Total Lockouts:</strong> $($lockouts.Count)<br>
        <strong>Total Failed Logins:</strong> $($failedLogins.Count)
    </div>

    <h2>Lockout Events</h2>
    <table>
        <tr><th>Time</th><th>Username</th><th>Source Computer</th><th>Domain Controller</th></tr>
"@

    foreach ($lockout in ($lockouts | Sort-Object TimeCreated -Descending)) {
        $html += "<tr><td>$($lockout.TimeCreated)</td><td>$([System.Net.WebUtility]::HtmlEncode("$($lockout.Username)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($lockout.SourceComputer)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($lockout.DomainController)"))</td></tr>`n"
    }

    $html += "</table></body></html>"

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($ExportCSV) {
    $csvPath = Join-Path $ReportDir "UserLockoutReport_$timestamp.csv"
    $lockouts | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

Write-Host "`n[+] Report completed!" -ForegroundColor Green

if ($lockouts.Count -gt 0) {
    exit 1
}

exit 0
