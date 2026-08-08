<#
.SYNOPSIS
    Audits local administrator accounts on the system.

.DESCRIPTION
    This script performs a comprehensive audit of all members of the local Administrators group,
    identifying non-standard accounts, checking last logon times, password expiration settings,
    and flagging potential security risks.

    The script helps identify:
    - Unexpected administrator accounts
    - Accounts that haven't been used recently
    - Accounts with passwords that never expire
    - Domain vs local account distinctions
    - Disabled/enabled status

.PARAMETER Detailed
    Include detailed account properties in the output

.PARAMETER ExportReport
    Generate HTML and CSV reports on the Desktop

.EXAMPLE
    .\Get-LocalAdminAudit.ps1
    Performs basic administrator audit

.EXAMPLE
    .\Get-LocalAdminAudit.ps1 -Detailed
    Shows detailed account properties

.EXAMPLE
    .\Get-LocalAdminAudit.ps1 -ExportReport
    Generates HTML and CSV reports

.NOTES
    Author: Security & Compliance Team
    Requires: Administrator privileges
    Compatible: Windows 10/11, Server 2016+
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Detailed,

    [Parameter()]
    [switch]$ExportReport
)

#Requires -RunAsAdministrator

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   Local Administrator Audit" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Get all members of the local Administrators group
try {
    Write-Host "[1/3] Retrieving local Administrators group members..." -ForegroundColor Yellow

    $AdminGroup = Get-LocalGroup -Name "Administrators" -ErrorAction Stop
    $AdminMembers = Get-LocalGroupMember -Name "Administrators" -ErrorAction Stop

    Write-Host "  Found $($AdminMembers.Count) member(s) in Administrators group`n" -ForegroundColor Green
}
catch {
    Write-Host "  ERROR: Failed to retrieve Administrators group: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Analyze each member
Write-Host "[2/3] Analyzing administrator accounts..." -ForegroundColor Yellow

$Results = @()
$IssuesFound = $false

# Known safe admin accounts (SIDs)
$SafeAdminSIDs = @(
    'S-1-5-32-544',  # BUILTIN\Administrators group
    'S-1-5-21-*-500' # Built-in Administrator account (typically disabled)
)

foreach ($Member in $AdminMembers) {
    $AccountInfo = [PSCustomObject]@{
        Name = $Member.Name
        SID = $Member.SID.Value
        ObjectClass = $Member.ObjectClass
        PrincipalSource = $Member.PrincipalSource
        LastLogon = "N/A"
        Enabled = "N/A"
        PasswordExpires = "N/A"
        PasswordLastSet = "N/A"
        AccountType = ""
        Risk = "Low"
        Notes = @()
    }

    # Determine account type
    if ($Member.PrincipalSource -eq "Local") {
        $AccountInfo.AccountType = "Local Account"

        # Get detailed info for local accounts
        try {
            $LocalUser = Get-LocalUser -SID $Member.SID -ErrorAction Stop

            $AccountInfo.Enabled = $LocalUser.Enabled
            $AccountInfo.PasswordLastSet = if ($LocalUser.PasswordLastSet) { $LocalUser.PasswordLastSet.ToString("yyyy-MM-dd HH:mm") } else { "Never" }
            $AccountInfo.LastLogon = if ($LocalUser.LastLogon) { $LocalUser.LastLogon.ToString("yyyy-MM-dd HH:mm") } else { "Never" }

            # Check if password expires
            if ($LocalUser.PasswordNeverExpires) {
                $AccountInfo.PasswordExpires = "Never"
                $AccountInfo.Notes += "Password never expires"
                $AccountInfo.Risk = "Medium"
            }
            else {
                $AccountInfo.PasswordExpires = "Yes"
            }

            # Check if enabled
            if ($LocalUser.Enabled) {
                # Check last logon
                if ($LocalUser.LastLogon) {
                    $DaysSinceLogon = (Get-Date) - $LocalUser.LastLogon
                    if ($DaysSinceLogon.Days -gt 90) {
                        $AccountInfo.Notes += "No logon in $($DaysSinceLogon.Days) days"
                        $AccountInfo.Risk = "Medium"
                    }
                }
                else {
                    $AccountInfo.Notes += "Account never used"
                    $AccountInfo.Risk = "High"
                }

                # Check if it's the built-in Administrator account
                if ($Member.SID.Value -like "*-500") {
                    $AccountInfo.Notes += "Built-in Administrator (should be disabled)"
                    $AccountInfo.Risk = "High"
                    $IssuesFound = $true
                }
            }
            else {
                $AccountInfo.Notes += "Account disabled"
            }

        }
        catch {
            $AccountInfo.Notes += "Could not retrieve account details"
        }

    }
    elseif ($Member.PrincipalSource -eq "ActiveDirectory") {
        $AccountInfo.AccountType = "Domain Account"
        $AccountInfo.Notes += "Domain-based administrator"

        # Check if it's a user or group
        if ($Member.ObjectClass -eq "Group") {
            $AccountInfo.Notes += "Domain Group"
        }
        else {
            $AccountInfo.Notes += "Domain User"
        }

    }
    elseif ($Member.PrincipalSource -eq "AzureAD") {
        $AccountInfo.AccountType = "Azure AD Account"
        $AccountInfo.Notes += "Azure AD-based administrator"

    }
    else {
        $AccountInfo.AccountType = "Unknown"
        $AccountInfo.Notes += "Unknown account source"
        $AccountInfo.Risk = "High"
        $IssuesFound = $true
    }

    # Display result
    $RiskColor = switch ($AccountInfo.Risk) {
        "High" { "Red"; $IssuesFound = $true }
        "Medium" { "Yellow" }
        "Low" { "Green" }
        default { "White" }
    }

    Write-Host "  [$($AccountInfo.Risk.PadRight(6))] " -ForegroundColor $RiskColor -NoNewline
    Write-Host "$($Member.Name)" -ForegroundColor White -NoNewline
    Write-Host " ($($AccountInfo.AccountType))" -ForegroundColor Gray

    if ($Detailed -and $AccountInfo.Notes.Count -gt 0) {
        foreach ($Note in $AccountInfo.Notes) {
            Write-Host "           - $Note" -ForegroundColor Gray
        }
    }

    $Results += $AccountInfo
}

# Summary
Write-Host "`n[3/3] Audit Summary..." -ForegroundColor Yellow

$LocalAdmins = ($Results | Where-Object { $_.PrincipalSource -eq "Local" }).Count
$DomainAdmins = ($Results | Where-Object { $_.PrincipalSource -eq "ActiveDirectory" }).Count
$AzureADAdmins = ($Results | Where-Object { $_.PrincipalSource -eq "AzureAD" }).Count
$HighRisk = ($Results | Where-Object { $_.Risk -eq "High" }).Count
$MediumRisk = ($Results | Where-Object { $_.Risk -eq "Medium" }).Count

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Administrators: $($Results.Count)" -ForegroundColor White
Write-Host "  Local Accounts: $LocalAdmins" -ForegroundColor White
Write-Host "  Domain Accounts: $DomainAdmins" -ForegroundColor White
Write-Host "  Azure AD Accounts: $AzureADAdmins" -ForegroundColor White
Write-Host "`nRisk Assessment:" -ForegroundColor White
Write-Host "  High Risk: $HighRisk" -ForegroundColor Red
Write-Host "  Medium Risk: $MediumRisk" -ForegroundColor Yellow
Write-Host "  Low Risk: $($Results.Count - $HighRisk - $MediumRisk)" -ForegroundColor Green

# Recommendations
if ($HighRisk -gt 0 -or $MediumRisk -gt 0) {
    Write-Host "`n========================================" -ForegroundColor Yellow
    Write-Host "   Recommendations" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow

    $HighRiskAccounts = $Results | Where-Object { $_.Risk -eq "High" }
    if ($HighRiskAccounts) {
        Write-Host "`nHigh Risk Accounts:" -ForegroundColor Red
        foreach ($Account in $HighRiskAccounts) {
            Write-Host "  - $($Account.Name)" -ForegroundColor Red
            foreach ($Note in $Account.Notes) {
                Write-Host "    → $Note" -ForegroundColor Yellow
            }
        }
    }

    $MediumRiskAccounts = $Results | Where-Object { $_.Risk -eq "Medium" }
    if ($MediumRiskAccounts) {
        Write-Host "`nMedium Risk Accounts:" -ForegroundColor Yellow
        foreach ($Account in $MediumRiskAccounts) {
            Write-Host "  - $($Account.Name)" -ForegroundColor Yellow
            foreach ($Note in $Account.Notes) {
                Write-Host "    → $Note" -ForegroundColor Gray
            }
        }
    }

    Write-Host "`nSuggested Actions:" -ForegroundColor Cyan
    Write-Host "  1. Review and remove unnecessary administrator accounts" -ForegroundColor White
    Write-Host "  2. Disable built-in Administrator account if enabled" -ForegroundColor White
    Write-Host "  3. Ensure passwords expire for local admin accounts" -ForegroundColor White
    Write-Host "  4. Remove administrator access for unused accounts" -ForegroundColor White
    Write-Host "  5. Consider implementing LAPS for local admin password management" -ForegroundColor White
}

# Export reports if requested
if ($ExportReport) {
    $ReportPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports')
    # Validate report directory: reject '..' traversal and UNC remote paths before resolution
    if ([string]::IsNullOrWhiteSpace($ReportPath) -or
        $ReportPath -match '(^|[\\/])\.\.([\\/]|$)' -or
        $ReportPath -match '^(\\\\|//)') {
        Write-Error "Unsafe report directory: $ReportPath. Report directory must be a local absolute path without '..' traversal."
        exit 1
    }
    $ReportPath = [System.IO.Path]::GetFullPath($ReportPath)
    if (-not (Test-Path -LiteralPath $ReportPath -PathType Container)) {
        New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
    }

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $TimestampRunId = "${Timestamp}_${RunId}"

    # Prepare export data
    $ExportData = $Results | Select-Object Name, SID, AccountType, PrincipalSource, Enabled, LastLogon, PasswordExpires, PasswordLastSet, Risk, @{
        Name = 'Notes'
        Expression = { $_.Notes -join '; ' }
    }

    # CSV Export
    $CSVPath = Join-Path $ReportPath "LocalAdminAudit_${TimestampRunId}.csv"
    $ExportData | Export-Csv -Path $CSVPath -NoTypeInformation
    Write-Host "`nCSV Report: $CSVPath" -ForegroundColor Green

    # HTML Export
    $HTMLPath = Join-Path $ReportPath "LocalAdminAudit_${TimestampRunId}.html"
    $HTML = @"
<!DOCTYPE html>
<html>
<head>
    <title>Local Administrator Audit - $Timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .summary-item { margin: 10px 0; font-size: 16px; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #3498db; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; font-size: 14px; }
        tr:hover { background-color: #f5f5f5; }
        .high { background-color: #ffebee; color: #c62828; font-weight: bold; }
        .medium { background-color: #fff3e0; color: #ef6c00; font-weight: bold; }
        .low { background-color: #e8f5e9; color: #2e7d32; font-weight: bold; }
        .recommendations { background-color: #fff8e1; padding: 15px; border-left: 4px solid #fbc02d; margin-top: 20px; }
    </style>
</head>
<body>
    <h1>Local Administrator Audit Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") | <strong>Run ID:</strong> $RunId</p>
    <p><strong>Computer:</strong> $([System.Net.WebUtility]::HtmlEncode("$env:COMPUTERNAME"))</p>

    <div class="summary">
        <div class="summary-item"><strong>Total Administrators:</strong> $($Results.Count)</div>
        <div class="summary-item"><strong>Local Accounts:</strong> $LocalAdmins</div>
        <div class="summary-item"><strong>Domain Accounts:</strong> $DomainAdmins</div>
        <div class="summary-item"><strong>Azure AD Accounts:</strong> $AzureADAdmins</div>
        <hr>
        <div class="summary-item"><strong>High Risk Accounts:</strong> <span style="color: #c62828;">$HighRisk</span></div>
        <div class="summary-item"><strong>Medium Risk Accounts:</strong> <span style="color: #ef6c00;">$MediumRisk</span></div>
        <div class="summary-item"><strong>Low Risk Accounts:</strong> <span style="color: #2e7d32;">$($Results.Count - $HighRisk - $MediumRisk)</span></div>
    </div>

    <h2>Administrator Accounts</h2>
    <table>
        <tr>
            <th>Name</th>
            <th>Account Type</th>
            <th>Enabled</th>
            <th>Last Logon</th>
            <th>Password Expires</th>
            <th>Risk Level</th>
            <th>Notes</th>
        </tr>
"@

    foreach ($Result in $Results) {
        $RiskClass = $Result.Risk.ToLower()
        $NotesText = ($Result.Notes -join '; ')
        $HTML += @"
        <tr>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($Result.Name)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($Result.AccountType)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($Result.Enabled)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($Result.LastLogon)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($Result.PasswordExpires)"))</td>
            <td class="$RiskClass">$([System.Net.WebUtility]::HtmlEncode("$($Result.Risk)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$NotesText"))</td>
        </tr>
"@
    }

    $HTML += "</table>"

    # Add recommendations
    if ($HighRisk -gt 0 -or $MediumRisk -gt 0) {
        $HTML += @"
    <div class="recommendations">
        <h2>Recommendations</h2>
        <ul>
            <li>Review and remove unnecessary administrator accounts</li>
            <li>Disable the built-in Administrator account if enabled</li>
            <li>Ensure passwords expire for local admin accounts</li>
            <li>Remove administrator access for unused or stale accounts</li>
            <li>Consider implementing Microsoft LAPS for local admin password management</li>
            <li>Regularly audit administrator group membership</li>
        </ul>
    </div>
"@
    }

    $HTML += @"
</body>
</html>
"@

    $HTML | Out-File -FilePath $HTMLPath -Encoding UTF8
    Write-Host "HTML Report: $HTMLPath" -ForegroundColor Green
}

# Exit with appropriate code
Write-Host ""
if ($IssuesFound) {
    Write-Host "⚠ Audit completed with issues found. Review high-risk accounts.`n" -ForegroundColor Yellow
    exit 1
}
else {
    Write-Host "✓ Audit completed. No critical issues found.`n" -ForegroundColor Green
    exit 0
}
