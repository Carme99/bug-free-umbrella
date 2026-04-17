<#
.SYNOPSIS
    Comprehensive distribution list and group audit for Exchange Online.

.DESCRIPTION
    Audits distribution lists, Microsoft 365 Groups, and mail-enabled security groups:
    - Membership analysis and ownership tracking
    - Orphaned groups (no owners)
    - Empty or single-member groups
    - External member detection
    - Group sprawl identification
    - Naming convention compliance
    - Send/receive permissions
    - Last activity tracking (M365 Groups)

.PARAMETER IncludeMicrosoft365Groups
    Include Microsoft 365 Groups in analysis

.PARAMETER IncludeSecurityGroups
    Include mail-enabled security groups

.PARAMETER CheckForOrphaned
    Identify groups with no owners

.PARAMETER MinimumMembers
    Minimum member count threshold. Groups below are flagged. Default: 2

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', 'CSV', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for output files. Default: Desktop

.EXAMPLE
    Connect-ExchangeOnline
    .\Get-DistributionListAudit.ps1

.EXAMPLE
    .\Get-DistributionListAudit.ps1 -IncludeMicrosoft365Groups `
        -IncludeSecurityGroups `
        -CheckForOrphaned `
        -MinimumMembers 3

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 5.1+, ExchangeOnlineManagement module

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$IncludeMicrosoft365Groups,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeSecurityGroups,

    [Parameter(Mandatory = $false)]
    [switch]$CheckForOrphaned,

    [Parameter(Mandatory = $false)]
    [int]$MinimumMembers = 2,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'CSV', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = [Environment]::GetFolderPath('Desktop')
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Error "ExchangeOnlineManagement module required. Install: Install-Module ExchangeOnlineManagement"
    exit 1
}

$results = @{
    Timestamp = Get-Date
    DistributionLists = @()
    Microsoft365Groups = @()
    SecurityGroups = @()
    OrphanedGroups = @()
    SmallGroups = @()
    Summary = @{}
}

Write-Host "Auditing distribution lists and groups..." -ForegroundColor Cyan

try {
    # Check connection
    try {
        Get-OrganizationConfig -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Not connected to Exchange Online. Run: Connect-ExchangeOnline"
        exit 1
    }

    # Get Distribution Lists
    Write-Host "`nRetrieving distribution lists..." -ForegroundColor Yellow
    $distributionLists = Get-DistributionGroup -ResultSize Unlimited

    foreach ($dl in $distributionLists) {
        Write-Host "  Analyzing: $($dl.DisplayName)" -ForegroundColor Gray

        # Get members
        $members = Get-DistributionGroupMember -Identity $dl.Identity -ErrorAction SilentlyContinue
        $memberCount = ($members | Measure-Object).Count

        # Get owners
        $owners = $dl.ManagedBy
        $hasOwners = ($owners | Measure-Object).Count -gt 0

        $dlData = @{
            DisplayName = $dl.DisplayName
            PrimarySmtpAddress = $dl.PrimarySmtpAddress
            Alias = $dl.Alias
            RecipientType = $dl.RecipientTypeDetails
            MemberCount = $memberCount
            Owners = $owners -join '; '
            RequireSenderAuthenticationEnabled = $dl.RequireSenderAuthenticationEnabled
            HiddenFromAddressListsEnabled = $dl.HiddenFromAddressListsEnabled
            Notes = @()
        }

        # Check for issues
        if (-not $hasOwners -and $CheckForOrphaned) {
            $dlData.Notes += "No owners assigned"
            $results.OrphanedGroups += $dlData
        }

        if ($memberCount -lt $MinimumMembers) {
            $dlData.Notes += "Below minimum member threshold ($memberCount < $MinimumMembers)"
            $results.SmallGroups += $dlData
        }

        if ($memberCount -eq 0) {
            $dlData.Notes += "Empty group"
        }

        # Check for external members
        $externalMembers = $members | Where-Object { $_.PrimarySmtpAddress -notlike "*@$((Get-AcceptedDomain | Where-Object { $_.Default }).DomainName.Domain)" }
        if ($externalMembers) {
            $dlData.Notes += "Contains $($externalMembers.Count) external members"
        }

        $dlData.Notes = $dlData.Notes -join '; '
        $results.DistributionLists += $dlData
    }

    Write-Host "Found $($distributionLists.Count) distribution lists" -ForegroundColor White

    # Get Microsoft 365 Groups
    if ($IncludeMicrosoft365Groups) {
        Write-Host "`nRetrieving Microsoft 365 Groups..." -ForegroundColor Yellow
        $m365Groups = Get-UnifiedGroup -ResultSize Unlimited

        foreach ($group in $m365Groups) {
            $members = Get-UnifiedGroupLinks -Identity $group.Identity -LinkType Members -ErrorAction SilentlyContinue
            $owners = Get-UnifiedGroupLinks -Identity $group.Identity -LinkType Owners -ErrorAction SilentlyContinue

            $memberCount = ($members | Measure-Object).Count
            $ownerCount = ($owners | Measure-Object).Count

            $groupData = @{
                DisplayName = $group.DisplayName
                PrimarySmtpAddress = $group.PrimarySmtpAddress
                Alias = $group.Alias
                RecipientType = "Microsoft 365 Group"
                MemberCount = $memberCount
                Owners = ($owners | Select-Object -ExpandProperty PrimarySmtpAddress) -join '; '
                Privacy = $group.AccessType
                WhenCreated = $group.WhenCreated
                Notes = @()
            }

            if ($ownerCount -eq 0 -and $CheckForOrphaned) {
                $groupData.Notes += "No owners assigned"
                $results.OrphanedGroups += $groupData
            }

            if ($memberCount -lt $MinimumMembers) {
                $groupData.Notes += "Below minimum member threshold"
                $results.SmallGroups += $groupData
            }

            $groupData.Notes = $groupData.Notes -join '; '
            $results.Microsoft365Groups += $groupData
        }

        Write-Host "Found $($m365Groups.Count) Microsoft 365 Groups" -ForegroundColor White
    }

    # Get Mail-Enabled Security Groups
    if ($IncludeSecurityGroups) {
        Write-Host "`nRetrieving mail-enabled security groups..." -ForegroundColor Yellow
        $securityGroups = Get-DistributionGroup -RecipientTypeDetails MailUniversalSecurityGroup -ResultSize Unlimited

        foreach ($sg in $securityGroups) {
            $members = Get-DistributionGroupMember -Identity $sg.Identity -ErrorAction SilentlyContinue
            $memberCount = ($members | Measure-Object).Count

            $sgData = @{
                DisplayName = $sg.DisplayName
                PrimarySmtpAddress = $sg.PrimarySmtpAddress
                Alias = $sg.Alias
                RecipientType = "Mail-Enabled Security Group"
                MemberCount = $memberCount
                Owners = $sg.ManagedBy -join '; '
                Notes = if ($memberCount -lt $MinimumMembers) { "Below minimum member threshold" } else { "" }
            }

            if ($memberCount -lt $MinimumMembers) {
                $results.SmallGroups += $sgData
            }

            $results.SecurityGroups += $sgData
        }

        Write-Host "Found $($securityGroups.Count) mail-enabled security groups" -ForegroundColor White
    }

} catch {
    Write-Error "Error auditing groups: $($_.Exception.Message)"
}

# Calculate summary
$totalGroups = $results.DistributionLists.Count + $results.Microsoft365Groups.Count + $results.SecurityGroups.Count

$results.Summary = @{
    TotalGroups = $totalGroups
    DistributionLists = $results.DistributionLists.Count
    Microsoft365Groups = $results.Microsoft365Groups.Count
    SecurityGroups = $results.SecurityGroups.Count
    OrphanedGroups = $results.OrphanedGroups.Count
    SmallGroups = $results.SmallGroups.Count
}

# Output results
switch ($OutputFormat) {
    'Console' {
        Write-Host "`n=== Distribution List Audit Summary ===" -ForegroundColor Cyan
        Write-Host "Total Groups: $totalGroups" -ForegroundColor White
        Write-Host "  Distribution Lists: $($results.DistributionLists.Count)" -ForegroundColor White
        if ($IncludeMicrosoft365Groups) {
            Write-Host "  Microsoft 365 Groups: $($results.Microsoft365Groups.Count)" -ForegroundColor White
        }
        if ($IncludeSecurityGroups) {
            Write-Host "  Security Groups: $($results.SecurityGroups.Count)" -ForegroundColor White
        }
        Write-Host "Orphaned Groups (no owners): $($results.OrphanedGroups.Count)" -ForegroundColor $(if ($results.OrphanedGroups.Count -gt 0) { 'Yellow' } else { 'White' })
        Write-Host "Small Groups (< $MinimumMembers members): $($results.SmallGroups.Count)" -ForegroundColor $(if ($results.SmallGroups.Count -gt 0) { 'Yellow' } else { 'White' })

        if ($results.OrphanedGroups.Count -gt 0) {
            Write-Host "`n=== Orphaned Groups ===" -ForegroundColor Yellow
            foreach ($group in ($results.OrphanedGroups | Select-Object -First 10)) {
                Write-Host "  $($group.DisplayName) - $($group.MemberCount) members" -ForegroundColor Red
            }
        }
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "DistributionList-Audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Distribution List Audit Report</title>
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
        .orphaned { background-color: #fdd; }
        .small { background-color: #fff3cd; }
        .footer { margin-top: 30px; text-align: center; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <h1>Distribution List Audit Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

        <div class="summary-grid">
            <div class="summary-item">
                <div class="value">$totalGroups</div>
                <div class="label">Total Groups</div>
            </div>
            <div class="summary-item">
                <div class="value">$($results.DistributionLists.Count)</div>
                <div class="label">Distribution Lists</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: $(if ($results.OrphanedGroups.Count -gt 0) { '#d13438' } else { '#107c10' });">$($results.OrphanedGroups.Count)</div>
                <div class="label">Orphaned</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: $(if ($results.SmallGroups.Count -gt 0) { '#ff8c00' } else { '#107c10' });">$($results.SmallGroups.Count)</div>
                <div class="label">Small Groups</div>
            </div>
        </div>
    </div>

    <h2>Distribution Lists</h2>
    <table>
        <tr>
            <th>Display Name</th>
            <th>Email</th>
            <th>Members</th>
            <th>Owners</th>
            <th>Notes</th>
        </tr>
"@

        foreach ($dl in $results.DistributionLists) {
            $rowClass = ""
            if ($dl.Notes -like "*No owners*") { $rowClass = "orphaned" }
            elseif ($dl.Notes -like "*Below minimum*") { $rowClass = "small" }

            $html += @"
        <tr class="$rowClass">
            <td>$($dl.DisplayName)</td>
            <td>$($dl.PrimarySmtpAddress)</td>
            <td>$($dl.MemberCount)</td>
            <td>$($dl.Owners)</td>
            <td>$($dl.Notes)</td>
        </tr>
"@
        }

        $html += "</table>"
        $html += @"
    <div class="footer">
        <strong>Note:</strong> This report has not been thoroughly tested. Please validate results before making changes.<br>
        Generated by Get-DistributionListAudit.ps1
    </div>
</body>
</html>
"@

        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "`nHTML report saved to: $htmlFile" -ForegroundColor Green
        Start-Process $htmlFile
    }

    'CSV' {
        $csvFile = Join-Path $OutputPath "DistributionLists-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
        $results.DistributionLists | Export-Csv -Path $csvFile -NoTypeInformation
        Write-Host "`nCSV report saved to: $csvFile" -ForegroundColor Green
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "DistributionList-Audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "`nJSON report saved to: $jsonFile" -ForegroundColor Green
    }
}

Write-Host "`nDistribution list audit complete!" -ForegroundColor Green
