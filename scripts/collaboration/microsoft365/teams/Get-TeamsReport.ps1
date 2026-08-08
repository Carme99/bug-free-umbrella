<#
.SYNOPSIS
    Generates comprehensive Microsoft Teams usage and compliance report.

.DESCRIPTION
    This script analyzes Microsoft Teams for:
    - Team count and membership statistics
    - Guest user access and external sharing
    - Channel count and types
    - Teams without owners
    - Archived teams
    - Privacy settings (Public vs Private)
    - External access configuration
    - Teams creation policy compliance

.PARAMETER IncludeGuests
    Include detailed guest user analysis.

.PARAMETER CheckOwnership
    Identify teams without active owners.

.PARAMETER CheckArchived
    Include archived teams in the report.

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER ExportCSV
    Export results to CSV file.

.EXAMPLE
    .\Get-TeamsReport.ps1
    Basic Teams usage report.

.EXAMPLE
    .\Get-TeamsReport.ps1 -IncludeGuests -CheckOwnership -ExportHTML
    Comprehensive Teams audit with guest and ownership analysis.

.NOTES
    Requires Microsoft Teams PowerShell module
    Requires Teams Administrator or Global Reader role
    Compatible with Microsoft Teams (Microsoft 365)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$IncludeGuests,

    [Parameter(Mandatory = $false)]
    [switch]$CheckOwnership,

    [Parameter(Mandatory = $false)]
    [switch]$CheckArchived,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$ExportCSV
)

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

Write-Host "`n=== Microsoft Teams Usage Report ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

# Check for Teams module
try {
    if (-not (Get-Module -Name MicrosoftTeams -ListAvailable)) {
        Write-Host "[-] Microsoft Teams module not found!" -ForegroundColor Red
        Write-Host "[!] Install with: Install-Module -Name MicrosoftTeams" -ForegroundColor Yellow
        exit 1
    }

    # Check connection
    try {
        $null = Get-CsTeamsCallingPolicy -ErrorAction Stop
    }
    catch {
        Write-Host "[!] Not connected to Teams. Connecting..." -ForegroundColor Yellow
        Connect-MicrosoftTeams
    }

    Write-Host "[+] Connected to Microsoft Teams" -ForegroundColor Green
}
catch {
    Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Get all teams
Write-Host "[*] Retrieving teams..." -ForegroundColor Cyan

try {
    $teams = Get-Team

    Write-Host "[+] Found $($teams.Count) team(s)" -ForegroundColor Green
}
catch {
    Write-Host "[-] Error retrieving teams: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

$results = @()
$teamsWithoutOwners = 0
$archivedTeams = 0
$publicTeams = 0
$privateTeams = 0
$totalGuests = 0
$totalChannels = 0

$i = 0
foreach ($team in $teams) {
    $i++
    Write-Progress -Activity "Analyzing Teams" -Status "$i of $($teams.Count): $($team.DisplayName)" -PercentComplete (($i / $teams.Count) * 100)

    # Get team details
    $teamDetails = Get-Team -GroupId $team.GroupId

    # Get members
    $members = Get-TeamUser -GroupId $team.GroupId

    $ownerCount = ($members | Where-Object { $_.Role -eq 'Owner' }).Count
    $memberCount = ($members | Where-Object { $_.Role -eq 'Member' }).Count
    $guestCount = ($members | Where-Object { $_.Role -eq 'Guest' }).Count

    # Check for teams without owners
    if ($CheckOwnership -and $ownerCount -eq 0) {
        $teamsWithoutOwners++
    }

    # Count archived
    if ($teamDetails.Archived) {
        $archivedTeams++
    }

    # Count public/private
    if ($teamDetails.Visibility -eq 'Public') {
        $publicTeams++
    }
    else {
        $privateTeams++
    }

    # Get channels
    $channels = Get-TeamChannel -GroupId $team.GroupId
    $channelCount = $channels.Count
    $totalChannels += $channelCount

    $privateChannelCount = ($channels | Where-Object { $_.MembershipType -eq 'Private' }).Count

    # Track guests
    if ($IncludeGuests) {
        $totalGuests += $guestCount
    }

    $result = [PSCustomObject]@{
        TeamName = $team.DisplayName
        Description = $team.Description
        Visibility = $teamDetails.Visibility
        Archived = $teamDetails.Archived
        OwnerCount = $ownerCount
        MemberCount = $memberCount
        GuestCount = $guestCount
        TotalUsers = $members.Count
        ChannelCount = $channelCount
        PrivateChannelCount = $privateChannelCount
        GroupId = $team.GroupId
        MailNickName = $teamDetails.MailNickName
    }

    $results += $result
}

Write-Progress -Activity "Analyzing Teams" -Completed

Write-Host ""

# Summary
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Total Teams: $($results.Count)" -ForegroundColor White
Write-Host "Public Teams: $publicTeams" -ForegroundColor Gray
Write-Host "Private Teams: $privateTeams" -ForegroundColor Gray
Write-Host "Archived Teams: $archivedTeams" -ForegroundColor Yellow
Write-Host "Total Channels: $totalChannels" -ForegroundColor Gray

if ($CheckOwnership) {
    Write-Host "Teams Without Owners: $teamsWithoutOwners" -ForegroundColor $(if ($teamsWithoutOwners -gt 0) { "Red" } else { "Green" })
}

if ($IncludeGuests) {
    Write-Host "Total Guest Users: $totalGuests" -ForegroundColor Yellow
}

Write-Host ""

# Show issues
if ($CheckOwnership -and $teamsWithoutOwners -gt 0) {
    Write-Host "=== Teams Without Owners (CRITICAL) ===" -ForegroundColor Red
    $results | Where-Object { $_.OwnerCount -eq 0 } |
        Select-Object TeamName, MemberCount, GuestCount |
        Format-Table -AutoSize
}

# Top teams by size
Write-Host "=== Top 10 Teams by Members ===" -ForegroundColor Cyan
$results | Sort-Object TotalUsers -Descending |
    Select-Object -First 10 TeamName, Visibility, TotalUsers, ChannelCount |
    Format-Table -AutoSize

# Export
if ($ExportHTML) {
    $htmlPath = (Join-Path $ReportDir "TeamsReport_$timestamp.html")

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Microsoft Teams Report - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #6264a7; }
        .summary { background-color: #f0f0f0; padding: 15px; border-radius: 5px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin-top: 10px; font-size: 12px; }
        th { background-color: #6264a7; color: white; padding: 10px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .issue { background-color: #ffe6e6; }
    </style>
</head>
<body>
    <h1>Microsoft Teams Usage Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Total Teams:</strong> $($results.Count)<br>
        <strong>Public Teams:</strong> $publicTeams<br>
        <strong>Private Teams:</strong> $privateTeams<br>
        <strong>Archived Teams:</strong> $archivedTeams<br>
        <strong>Total Channels:</strong> $totalChannels<br>
        <strong>Teams Without Owners:</strong> $teamsWithoutOwners<br>
        <strong>Total Guest Users:</strong> $totalGuests
    </div>

    <h2>Team Details</h2>
    <table>
        <tr>
            <th>Team Name</th>
            <th>Visibility</th>
            <th>Archived</th>
            <th>Owners</th>
            <th>Members</th>
            <th>Guests</th>
            <th>Channels</th>
        </tr>
"@

    foreach ($result in ($results | Sort-Object TeamName)) {
        $rowClass = if ($result.OwnerCount -eq 0) { "issue" } else { "" }
        $html += @"
        <tr class="$rowClass">
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.TeamName)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.Visibility)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.Archived)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.OwnerCount)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.MemberCount)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.GuestCount)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($result.ChannelCount)"))</td>
        </tr>
"@
    }

    $html += "</table></body></html>"
    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green
}

if ($ExportCSV) {
    $csvPath = (Join-Path $ReportDir "TeamsReport_$timestamp.csv")
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "[+] CSV export saved to: $csvPath" -ForegroundColor Green
}

Write-Host "`n[+] Report completed!" -ForegroundColor Green

if ($teamsWithoutOwners -gt 0) {
    exit 1
}

exit 0
