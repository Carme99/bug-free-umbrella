<#
.SYNOPSIS
    Generate a Microsoft Teams usage and compliance report.

.DESCRIPTION
    This script analyzes Microsoft Teams and reports team count and membership statistics, guest user access, channel
    counts and types, archived teams, public/private visibility, external access configuration, and teams without
    active owners. It connects to Microsoft Teams interactively when no active session exists, and can optionally
    export the results as HTML and/or CSV under the user's Documents\Reports folder (exports honor -WhatIf).
    Exit codes: 0 when the report completed with no critical findings; 1 when the module or connection is unavailable
    or when -CheckOwnership found teams without owners.

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
    PS C:\> .\Get-TeamsReport.ps1
    Generates a basic Teams usage report.

.EXAMPLE
    PS C:\> .\Get-TeamsReport.ps1 -IncludeGuests -CheckOwnership -ExportHTML
    Generates a comprehensive Teams audit with guest and ownership analysis plus an HTML export.

.NOTES
    File Name  : Get-TeamsReport.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Requires the MicrosoftTeams module and the Teams Administrator or Global Reader role.
    Compatible with Microsoft Teams (Microsoft 365).
#>

# PSAvoidUsingWriteHost: Write-Host with [+]/[!]/[-]/[*] prefixes is mandated by AGENTS.md.
# PSReviewUnusedParameter: script parameters are consumed inside Main via scope chaining.
[CmdletBinding(SupportsShouldProcess)]
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

$ErrorActionPreference = 'Stop'

function Export-TeamsReportOutput {
    # Writes the optional HTML/CSV report artifacts; each write is gated by ShouldProcess.
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [string]$HtmlPath,

        [Parameter(Mandatory = $false)]
        [string]$CsvPath,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Html,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$Results
    )

    if ($HtmlPath -and $PSCmdlet.ShouldProcess($HtmlPath, 'Write HTML report')) {
        $Html | Out-File -FilePath $HtmlPath -Encoding utf8 -ErrorAction Stop
        Write-Host "[+] HTML report saved to: $HtmlPath" -ForegroundColor Green
    }

    if ($CsvPath -and $PSCmdlet.ShouldProcess($CsvPath, 'Write CSV export')) {
        $Results | Export-Csv -Path $CsvPath -NoTypeInformation -ErrorAction Stop
        Write-Host "[+] CSV export saved to: $CsvPath" -ForegroundColor Green
    }
}

function Main {
    try {
        # Prepare report directory (local absolute path only, no traversal).
        $documentsRoot = [Environment]::GetFolderPath('MyDocuments')
        if ([string]::IsNullOrWhiteSpace($documentsRoot)) {
            $documentsRoot = [System.IO.Path]::Combine($HOME, 'Documents')
        }
        $reportDir = Join-Path $documentsRoot 'Reports'
        if ([string]::IsNullOrWhiteSpace($reportDir) -or
            $reportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
            $reportDir -match '^(\\\\|//)') {
            throw "Unsafe report path: $reportDir. Report path must be a local absolute path without '..' traversal."
        }
        $reportDir = [System.IO.Path]::GetFullPath($reportDir)
        if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
            New-Item -ItemType Directory -Path $reportDir -Force -ErrorAction Stop | Out-Null
        }

        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

        Write-Host "`n=== Microsoft Teams Usage Report ===" -ForegroundColor Cyan
        Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
        Write-Host ""

        # Check for Teams module
        if (-not (Get-Module -Name MicrosoftTeams -ListAvailable)) {
            Write-Host "[-] Microsoft Teams module not found!" -ForegroundColor Red
            Write-Host "[!] Install with: Install-Module -Name MicrosoftTeams" -ForegroundColor Yellow
            return 1
        }

        # Check connection
        try {
            $null = Get-CsTeamsCallingPolicy -ErrorAction Stop
        }
        catch {
            Write-Host "[!] Not connected to Teams. Connecting..." -ForegroundColor Yellow
            Connect-MicrosoftTeams -ErrorAction Stop
        }

        Write-Host "[+] Connected to Microsoft Teams" -ForegroundColor Green

        Write-Host ""

        # Get all teams
        Write-Host "[*] Retrieving teams..." -ForegroundColor Cyan

        $teams = @(Get-Team -ErrorAction Stop)

        Write-Host "[+] Found $($teams.Count) team(s)" -ForegroundColor Green

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
            $progressStatus = "$i of $($teams.Count): $($team.DisplayName)"
            $percentComplete = if ($teams.Count -gt 0) { ($i / $teams.Count) * 100 } else { 100 }
            Write-Progress -Activity "Analyzing Teams" -Status $progressStatus -PercentComplete $percentComplete

            # Get team details
            $teamDetails = Get-Team -GroupId $team.GroupId -ErrorAction Stop

            # Get members
            $members = @(Get-TeamUser -GroupId $team.GroupId -ErrorAction Stop)

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
            $channels = @(Get-TeamChannel -GroupId $team.GroupId -ErrorAction Stop)
            $channelCount = $channels.Count
            $totalChannels += $channelCount

            $privateChannelCount = ($channels | Where-Object { $_.MembershipType -eq 'Private' }).Count

            # Track guests
            if ($IncludeGuests) {
                $totalGuests += $guestCount
            }

            $result = [PSCustomObject]@{
                TeamName            = $team.DisplayName
                Description         = $team.Description
                Visibility          = $teamDetails.Visibility
                Archived            = $teamDetails.Archived
                OwnerCount          = $ownerCount
                MemberCount         = $memberCount
                GuestCount          = $guestCount
                TotalUsers          = $members.Count
                ChannelCount        = $channelCount
                PrivateChannelCount = $privateChannelCount
                GroupId             = $team.GroupId
                MailNickName        = $teamDetails.MailNickName
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
            $ownershipColor = if ($teamsWithoutOwners -gt 0) { "Red" } else { "Green" }
            Write-Host "Teams Without Owners: $teamsWithoutOwners" -ForegroundColor $ownershipColor
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
        $htmlPath = $null
        $csvPath = $null
        $html = ''

        if ($ExportHTML) {
            $htmlPath = Join-Path $reportDir "TeamsReport_$timestamp.html"

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
        }

        $exportParams = @{
            HtmlPath = $htmlPath
            CsvPath  = $csvPath
            Html     = $html
            Results  = @($results)
        }
        if ($ExportCSV) {
            $exportParams.CsvPath = Join-Path $reportDir "TeamsReport_$timestamp.csv"
        }

        $null = Export-TeamsReportOutput @exportParams

        Write-Host "`n[+] Report completed!" -ForegroundColor Green

        if ($teamsWithoutOwners -gt 0) {
            return 1
        }

        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
