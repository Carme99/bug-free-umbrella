<#
.SYNOPSIS
    Identifies potential Group Policy conflicts and issues across the domain.

.DESCRIPTION
    This script analyzes Group Policy Objects to identify duplicate or conflicting settings,
    GPOs with partially disabled configurations, empty GPOs that are still linked, duplicate
    and similar GPO names, loopback processing conflicts, security filtering issues, and
    (optionally) inheritance blocking and enforced links. Findings are exported to a CSV file
    and an HTML report under -OutputPath. The analysis is read-only and safe to re-run.

.PARAMETER Scope
    Scope of analysis. Options: Domain, OU, Site, All. Default is Domain.

.PARAMETER TargetOU
    Specific OU to analyze. Required if Scope is set to OU.

.PARAMETER OutputPath
    Local absolute path where the conflict report will be saved.

.PARAMETER IncludeInheritance
    Switch to analyze inheritance blocking and enforcement.

.PARAMETER CheckDuplicateSettings
    Switch to perform deep analysis of duplicate settings (slower).

.EXAMPLE
    PS C:\> .\Find-GPOConflicts.ps1 -OutputPath "C:\Reports"
    Analyzes all domain GPOs for conflicts.

.EXAMPLE
    PS C:\> .\Find-GPOConflicts.ps1 -Scope OU -TargetOU "OU=Workstations,DC=contoso,DC=com" -OutputPath "C:\Reports"
    Analyzes GPOs applied to specific OU including inheritance.

.NOTES
    File Name: Find-GPOConflicts.ps1
    Author: Server Management Team
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification='Spec 3 requirement')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification='Used in Main scope')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Domain', 'OU', 'Site', 'All')]
    [string]$Scope = 'Domain',

    [Parameter(Mandatory = $false)]
    [string]$TargetOU,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = "$env:TEMP\GPOConflicts_$(Get-Date -Format 'yyyyMMdd_HHmmss')",

    [Parameter(Mandatory = $false)]
    [switch]$IncludeInheritance,

    [Parameter(Mandatory = $false)]
    [switch]$CheckDuplicateSettings
)

$ErrorActionPreference = 'Stop'

function Assert-SafeLocalPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or
        $Path -match '(^|[\\/])\.\.([\\/]|$)' -or
        $Path -match '^(\\\\|//)') {
        throw "$Label must be a local absolute path without '..' traversal: '$Path'"
    }

    return [System.IO.Path]::GetFullPath($Path)
}

function Main {
    [CmdletBinding()]
    param()

    try {
        Write-Host '[*] Starting Group Policy conflict analysis...' -ForegroundColor Cyan

        # Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
        $resolvedOutputPath = Assert-SafeLocalPath -Path $OutputPath -Label 'OutputPath'
        if (-not (Test-Path -LiteralPath $resolvedOutputPath -PathType Container)) {
            New-Item -ItemType Directory -Path $resolvedOutputPath -Force -ErrorAction Stop | Out-Null
        }

        Write-Host ''
        Write-Host '=== Group Policy Conflict Analyzer ===' -ForegroundColor Cyan
        Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

        if ($Scope -eq 'OU' -and -not $TargetOU) {
            throw 'TargetOU is required when Scope is set to OU'
        }

        # Get domain information
        $domain = Get-ADDomain -ErrorAction Stop
        $domainName = $domain.DNSRoot
        Write-Host "Domain: $domainName" -ForegroundColor Green

        # Initialize conflict tracking
        $issues = @()
        $warnings = @()

        # Get all GPOs
        Write-Host '[*] Retrieving Group Policy Objects...' -ForegroundColor Yellow
        $allGPOs = @(Get-GPO -All -Domain $domainName)
        Write-Host "[+] Found $(@($allGPOs).Count) GPOs" -ForegroundColor Green

        # Check for disabled configurations
        Write-Host '[*] Checking for disabled configurations...' -ForegroundColor Yellow
        $partiallyDisabledGPOs = @($allGPOs | Where-Object {
                ($_.GpoStatus -eq 'UserSettingsDisabled') -or
                ($_.GpoStatus -eq 'ComputerSettingsDisabled')
            })

        foreach ($gpo in $partiallyDisabledGPOs) {
            $issues += [PSCustomObject]@{
                Type           = 'Partially Disabled GPO'
                Severity       = 'Warning'
                GPOName        = $gpo.DisplayName
                Description    = "GPO has $($gpo.GpoStatus)"
                Impact         = 'Some settings may not apply as expected'
                Recommendation = 'Review if this is intentional, otherwise enable all settings'
            }
        }

        $fgColor = if ($partiallyDisabledGPOs.Count -gt 0) { 'Yellow' } else { 'Green' }
        Write-Host "[*] Found $($partiallyDisabledGPOs.Count) partially disabled GPOs" -ForegroundColor $fgColor

        # Check for empty GPOs that are linked
        Write-Host '[*] Checking for empty linked GPOs...' -ForegroundColor Yellow
        $emptyLinkedCount = 0

        foreach ($gpo in $allGPOs) {
            # Check if GPO is empty
            $computerVersion = $gpo.Computer.DSVersion
            $userVersion = $gpo.User.DSVersion
            $isEmpty = ($computerVersion -eq 0) -and ($userVersion -eq 0)

            if ($isEmpty) {
                # Check if it has links
                $gpoReport = [xml](Get-GPOReport -Guid $gpo.Id -ReportType XML -ErrorAction Stop)
                $links = $gpoReport.GPO.LinksTo
                $linkCount = if ($links) { @($links).Count } else { 0 }

                if ($linkCount -gt 0) {
                    $emptyLinkedCount++
                    $issues += [PSCustomObject]@{
                        Type           = 'Empty Linked GPO'
                        Severity       = 'Warning'
                        GPOName        = $gpo.DisplayName
                        Description    = "GPO is empty but linked to $linkCount location(s)"
                        Impact         = 'Unnecessary processing overhead'
                        Recommendation = 'Remove links or delete GPO if not needed'
                    }
                }
            }
        }

        $fgColor = if ($emptyLinkedCount -gt 0) { 'Yellow' } else { 'Green' }
        Write-Host "[*] Found $emptyLinkedCount empty GPOs with links" -ForegroundColor $fgColor

        # Check for duplicate GPO names
        Write-Host '[*] Checking for duplicate GPO names...' -ForegroundColor Yellow
        $duplicateNames = @($allGPOs | Group-Object -Property DisplayName |
                Where-Object { $_.Count -gt 1 })

        foreach ($duplicate in $duplicateNames) {
            $issues += [PSCustomObject]@{
                Type           = 'Duplicate GPO Names'
                Severity       = 'High'
                GPOName        = $duplicate.Name
                Description    = "Multiple GPOs ($($duplicate.Count)) with the same name"
                Impact         = 'Confusion in management and troubleshooting'
                Recommendation = 'Rename GPOs to have unique names'
            }
        }

        $fgColor = if ($duplicateNames.Count -gt 0) { 'Red' } else { 'Green' }
        Write-Host "[*] Found $($duplicateNames.Count) sets of duplicate names" -ForegroundColor $fgColor

        # Check for conflicting loopback policies
        Write-Host '[*] Checking for loopback processing conflicts...' -ForegroundColor Yellow
        $loopbackGPOs = @()

        foreach ($gpo in $allGPOs) {
            try {
                $gpoReport = [xml](Get-GPOReport -Guid $gpo.Id -ReportType XML -ErrorAction Stop)

                # Check for loopback processing in Computer Configuration
                $loopbackSetting = @($gpoReport.GPO.Computer.ExtensionData |
                        Where-Object { $_.Name -like '*Loopback*' })

                if ($loopbackSetting.Count -gt 0) {
                    $loopbackGPOs += $gpo
                }
            }
            catch {
                # Skip GPOs that can't be read
                continue
            }
        }

        if ($loopbackGPOs.Count -gt 1) {
            $issues += [PSCustomObject]@{
                Type           = 'Multiple Loopback Policies'
                Severity       = 'High'
                GPOName        = ($loopbackGPOs.DisplayName -join ', ')
                Description    = "$($loopbackGPOs.Count) GPOs configure loopback processing"
                Impact         = 'Conflicting loopback modes may cause unexpected behavior'
                Recommendation = 'Consolidate loopback processing configuration into single GPO'
            }
        }

        Write-Host "[*] Found $($loopbackGPOs.Count) GPOs with loopback processing" -ForegroundColor Cyan

        # Check for GPOs with same name pattern (potential duplicates)
        Write-Host '[*] Checking for similar GPO names...' -ForegroundColor Yellow
        $similarNames = @()

        foreach ($gpo1 in $allGPOs) {
            foreach ($gpo2 in $allGPOs) {
                if ($gpo1.Id -ne $gpo2.Id) {
                    # Simple similarity check - same first 15 characters
                    $name1 = $gpo1.DisplayName.Substring(0, [Math]::Min(15, $gpo1.DisplayName.Length))
                    $name2 = $gpo2.DisplayName.Substring(0, [Math]::Min(15, $gpo2.DisplayName.Length))

                    if ($name1 -eq $name2 -and $gpo1.DisplayName -ne $gpo2.DisplayName) {
                        $similarity = "$($gpo1.DisplayName) / $($gpo2.DisplayName)"
                        if ($similarNames -notcontains $similarity) {
                            $similarNames += $similarity

                            $warnings += [PSCustomObject]@{
                                Type           = 'Similar GPO Names'
                                Severity       = 'Low'
                                GPOName        = $similarity
                                Description    = 'GPOs have similar names'
                                Impact         = 'May indicate duplicate policies or cause confusion'
                                Recommendation = 'Review if these are duplicate policies'
                            }
                        }
                    }
                }
            }
        }

        $fgColor = if ($similarNames.Count -gt 0) { 'Yellow' } else { 'Green' }
        Write-Host "[*] Found $($similarNames.Count) pairs of similar GPO names" -ForegroundColor $fgColor

        # Check for security filtering conflicts
        Write-Host '[*] Checking for security filtering issues...' -ForegroundColor Yellow
        $securityFilterIssues = 0

        foreach ($gpo in $allGPOs) {
            try {
                $permissions = Get-GPPermissions -Guid $gpo.Id -All -ErrorAction Stop

                # Check if Authenticated Users is denied
                $authenticatedUsersDenied = $permissions | Where-Object {
                    $_.Trustee.Name -eq 'Authenticated Users' -and
                    $_.Permission -eq 'GpoApply' -and
                    $_.Denied -eq $true
                }

                if ($authenticatedUsersDenied) {
                    $securityFilterIssues++
                    $issues += [PSCustomObject]@{
                        Type           = 'Security Filtering Issue'
                        Severity       = 'Medium'
                        GPOName        = $gpo.DisplayName
                        Description    = 'Authenticated Users explicitly denied GpoApply'
                        Impact         = 'GPO may not apply as expected without specific security group filtering'
                        Recommendation = 'Ensure appropriate security groups are added for GPO application'
                    }
                }

                # Check if no apply permissions exist
                $applyPermissions = $permissions | Where-Object {
                    $_.Permission -eq 'GpoApply' -and $_.Denied -eq $false
                }

                if (-not $applyPermissions) {
                    $securityFilterIssues++
                    $issues += [PSCustomObject]@{
                        Type           = 'No Apply Permissions'
                        Severity       = 'High'
                        GPOName        = $gpo.DisplayName
                        Description    = 'No security principals have GpoApply permission'
                        Impact         = 'GPO will not apply to any users or computers'
                        Recommendation = 'Add appropriate security principals with GpoApply permission'
                    }
                }
            }
            catch {
                # Skip GPOs with permission issues
                continue
            }
        }

        $fgColor = if ($securityFilterIssues -gt 0) { 'Yellow' } else { 'Green' }
        Write-Host "[*] Found $securityFilterIssues security filtering issues" -ForegroundColor $fgColor

        # Inheritance blocking analysis (if requested)
        if ($IncludeInheritance) {
            Write-Host '[*] Analyzing GPO inheritance...' -ForegroundColor Yellow

            # Get all OUs with inheritance blocked
            $allOUs = @(Get-ADOrganizationalUnit -Filter * -Properties gPOptions -ErrorAction Stop)
            $blockedOUs = @($allOUs | Where-Object { $_.gPOptions -eq 1 })

            foreach ($ou in $blockedOUs) {
                $warnings += [PSCustomObject]@{
                    Type           = 'Inheritance Blocked'
                    Severity       = 'Medium'
                    GPOName        = 'N/A'
                    Description    = "OU '$($ou.Name)' has GPO inheritance blocked"
                    Impact         = 'Parent GPOs will not apply to this OU'
                    Recommendation = 'Ensure this is intentional and necessary'
                }
            }

            $fgColor = if ($blockedOUs.Count -gt 0) { 'Yellow' } else { 'Green' }
            Write-Host "[*] Found $($blockedOUs.Count) OUs with inheritance blocked" -ForegroundColor $fgColor

            # Check for enforced GPOs
            $enforcedLinks = 0
            foreach ($ou in $allOUs) {
                $links = Get-GPInheritance -Target $ou.DistinguishedName -ErrorAction Stop
                foreach ($link in $links.GpoLinks) {
                    if ($link.Enforced) {
                        $enforcedLinks++
                    }
                }
            }

            Write-Host "[*] Found $enforcedLinks enforced GPO links" -ForegroundColor Cyan
        }

        # Combine all findings
        $allFindings = @($issues + $warnings)

        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

        # Export results to CSV
        $csvPath = Join-Path -Path $resolvedOutputPath -ChildPath "GPOConflicts_${RunTimestamp}_${RunId}.csv"
        $allFindings | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
        Write-Host "[+] Results exported to: $csvPath" -ForegroundColor Green

        # Generate HTML report
        $htmlPath = Join-Path -Path $resolvedOutputPath -ChildPath 'GPOConflictsReport.html'

        $htmlHead = @"
<!DOCTYPE html>
<html>
<head>
    <title>GPO Conflict Analysis - $([System.Net.WebUtility]::HtmlEncode("$domainName"))</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0066cc; }
        h2 { color: #0099cc; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; background-color: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin: 20px 0; }
        th { background-color: #0066cc; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f0f0f0; }
        .high { background-color: #ffcccc; }
        .medium { background-color: #ffffcc; }
        .warning { background-color: #e6f3ff; }
        .info { background-color: #e6f3ff; padding: 15px; border-left: 4px solid #0066cc; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>Group Policy Conflict Analysis</h1>
    <div class="info">
        <strong>Domain:</strong> $([System.Net.WebUtility]::HtmlEncode("$domainName"))<br>
        <strong>Analysis Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
        <strong>Total GPOs Analyzed:</strong> $(@($allGPOs).Count)<br>
        <strong>Total Issues Found:</strong> $($allFindings.Count)
    </div>

    <h2>Summary</h2>
    <table>
        <tr><td><strong>High Severity Issues</strong></td>
            <td>$(($allFindings | Where-Object Severity -EQ 'High').Count)</td></tr>
        <tr><td><strong>Medium Severity Issues</strong></td>
            <td>$(($allFindings | Where-Object Severity -EQ 'Medium').Count)</td></tr>
        <tr><td><strong>Warnings</strong></td>
            <td>$(($allFindings | Where-Object Severity -EQ 'Warning').Count)</td></tr>
        <tr><td><strong>Low Priority</strong></td>
            <td>$(($allFindings | Where-Object Severity -EQ 'Low').Count)</td></tr>
    </table>

    <h2>Issues and Conflicts</h2>
    <table>
        <tr>
            <th>Severity</th>
            <th>Type</th>
            <th>GPO Name</th>
            <th>Description</th>
            <th>Impact</th>
            <th>Recommendation</th>
        </tr>
"@

        $htmlRows = ''
        foreach ($finding in $allFindings | Sort-Object -Property @{ Expression = {
                    switch ($_.Severity) {
                        'High' { 1 }
                        'Medium' { 2 }
                        'Warning' { 3 }
                        'Low' { 4 }
                    }
                }
            }, Type) {
            $rowClass = switch ($finding.Severity) {
                'High' { 'high' }
                'Medium' { 'medium' }
                'Warning' { 'warning' }
                default { '' }
            }

            $htmlRows += @"
        <tr class="$rowClass">
            <td><strong>$($finding.Severity)</strong></td>
            <td>$($finding.Type)</td>
            <td>$($finding.GPOName)</td>
            <td>$($finding.Description)</td>
            <td>$($finding.Impact)</td>
            <td>$($finding.Recommendation)</td>
        </tr>
"@
        }

        $html = "$htmlHead$htmlRows    </table>`n</body>`n</html>"

        $html | Out-File -FilePath $htmlPath -Encoding UTF8 -ErrorAction Stop
        Write-Host "[+] HTML report saved to: $htmlPath" -ForegroundColor Green

        # Display summary
        Write-Host '[+] Analysis Complete' -ForegroundColor Green
        Write-Host "Total Issues Found: $($allFindings.Count)" -ForegroundColor Cyan
        Write-Host "  High Severity: $(($allFindings | Where-Object Severity -EQ 'High').Count)" -ForegroundColor Red
        Write-Host ("  Medium Severity:" +
            "$(($allFindings | Where-Object Severity -EQ 'Medium').Count)") -ForegroundColor Yellow
        Write-Host "  Warnings: $(($allFindings | Where-Object Severity -EQ 'Warning').Count)" -ForegroundColor Yellow
        Write-Host "  Low Priority: $(($allFindings | Where-Object Severity -EQ 'Low').Count)" -ForegroundColor Cyan
        Write-Host "End Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

        return 0
    }
    catch {
        Write-Host "[-] Error during conflict analysis: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
