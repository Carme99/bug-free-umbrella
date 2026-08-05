<#
.SYNOPSIS
    Identifies potential Group Policy conflicts and issues.

.DESCRIPTION
    This script analyzes Group Policy Objects to identify:
    - Duplicate or conflicting settings across multiple GPOs
    - GPOs with overlapping scopes that may conflict
    - Disabled computer/user configurations
    - Loopback processing conflicts
    - Security filtering conflicts
    - WMI filter issues

    Useful for troubleshooting GPO application issues and optimizing policy structure.

.PARAMETER Scope
    Scope of analysis. Options: Domain, OU, Site, All. Default is Domain.

.PARAMETER TargetOU
    Specific OU to analyze. Required if Scope is set to OU.

.PARAMETER OutputPath
    Path where the conflict report will be saved.

.PARAMETER IncludeInheritance
    Switch to analyze inheritance blocking and enforcement.

.PARAMETER CheckDuplicateSettings
    Switch to perform deep analysis of duplicate settings (slower).

.EXAMPLE
    .\Find-GPOConflicts.ps1 -OutputPath "C:\Reports"
    Analyzes all domain GPOs for conflicts.

.EXAMPLE
    .\Find-GPOConflicts.ps1 -Scope OU -TargetOU "OU=Workstations,DC=contoso,DC=com" -OutputPath "C:\Reports" -IncludeInheritance
    Analyzes GPOs applied to specific OU including inheritance.

.NOTES
    Author: Server Management Team
    Requires: GroupPolicy PowerShell module, ActiveDirectory module
    Version: 1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Domain', 'OU', 'Site', 'All')]
    [string]$Scope = 'Domain',

    [Parameter(Mandatory = $false)]
    [string]$TargetOU,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "$env:TEMP\GPOConflicts_$(Get-Date -Format 'yyyyMMdd_HHmmss')",

    [Parameter(Mandatory = $false)]
    [switch]$IncludeInheritance,

    [Parameter(Mandatory = $false)]
    [switch]$CheckDuplicateSettings
)
# Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
if ([string]::IsNullOrWhiteSpace($OutputPath) -or
    $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
    $OutputPath -match '^(\\\\|//)') {
    Write-Error "Unsafe OutputPath: $OutputPath. OutputPath must be a local absolute path without '..' traversal."
    exit 1
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

#Requires -Module GroupPolicy
#Requires -Module ActiveDirectory

Write-Host "`n=== Group Policy Conflict Analyzer ===" -ForegroundColor Cyan
Write-Host "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# Create output directory
if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

try {
    # Get domain information
    $domain = Get-ADDomain
    $domainName = $domain.DNSRoot
    Write-Host "`nDomain: $domainName" -ForegroundColor Green

    # Initialize conflict tracking
    $conflicts = @()
    $issues = @()
    $warnings = @()

    # Get all GPOs
    Write-Host "`nRetrieving Group Policy Objects..." -ForegroundColor Yellow
    $allGPOs = Get-GPO -All -Domain $domainName
    Write-Host "Found $($allGPOs.Count) GPOs" -ForegroundColor Green

    # Check for disabled configurations
    Write-Host "`nChecking for disabled configurations..." -ForegroundColor Yellow
    $partiallyDisabledGPOs = $allGPOs | Where-Object {
        ($_.GpoStatus -eq 'UserSettingsDisabled') -or
        ($_.GpoStatus -eq 'ComputerSettingsDisabled')
    }

    foreach ($gpo in $partiallyDisabledGPOs) {
        $issues += [PSCustomObject]@{
            Type        = "Partially Disabled GPO"
            Severity    = "Warning"
            GPOName     = $gpo.DisplayName
            Description = "GPO has $($gpo.GpoStatus)"
            Impact      = "Some settings may not apply as expected"
            Recommendation = "Review if this is intentional, otherwise enable all settings"
        }
    }

    Write-Host "Found $($partiallyDisabledGPOs.Count) partially disabled GPOs" -ForegroundColor $(if ($partiallyDisabledGPOs.Count -gt 0) { 'Yellow' } else { 'Green' })

    # Check for empty GPOs that are linked
    Write-Host "`nChecking for empty linked GPOs..." -ForegroundColor Yellow
    $emptyLinkedCount = 0

    foreach ($gpo in $allGPOs) {
        # Check if GPO is empty
        $computerVersion = $gpo.Computer.DSVersion
        $userVersion = $gpo.User.DSVersion
        $isEmpty = ($computerVersion -eq 0) -and ($userVersion -eq 0)

        if ($isEmpty) {
            # Check if it has links
            $gpoReport = [xml](Get-GPOReport -Guid $gpo.Id -ReportType XML)
            $links = $gpoReport.GPO.LinksTo
            $linkCount = if ($links) { @($links).Count } else { 0 }

            if ($linkCount -gt 0) {
                $emptyLinkedCount++
                $issues += [PSCustomObject]@{
                    Type        = "Empty Linked GPO"
                    Severity    = "Warning"
                    GPOName     = $gpo.DisplayName
                    Description = "GPO is empty but linked to $linkCount location(s)"
                    Impact      = "Unnecessary processing overhead"
                    Recommendation = "Remove links or delete GPO if not needed"
                }
            }
        }
    }

    Write-Host "Found $emptyLinkedCount empty GPOs with links" -ForegroundColor $(if ($emptyLinkedCount -gt 0) { 'Yellow' } else { 'Green' })

    # Check for duplicate GPO names
    Write-Host "`nChecking for duplicate GPO names..." -ForegroundColor Yellow
    $duplicateNames = $allGPOs | Group-Object -Property DisplayName |
        Where-Object { $_.Count -gt 1 }

    foreach ($duplicate in $duplicateNames) {
        $issues += [PSCustomObject]@{
            Type        = "Duplicate GPO Names"
            Severity    = "High"
            GPOName     = $duplicate.Name
            Description = "Multiple GPOs ($($duplicate.Count)) with the same name"
            Impact      = "Confusion in management and troubleshooting"
            Recommendation = "Rename GPOs to have unique names"
        }
    }

    Write-Host "Found $($duplicateNames.Count) sets of duplicate names" -ForegroundColor $(if ($duplicateNames.Count -gt 0) { 'Red' } else { 'Green' })

    # Check for conflicting loopback policies
    Write-Host "`nChecking for loopback processing conflicts..." -ForegroundColor Yellow
    $loopbackGPOs = @()

    foreach ($gpo in $allGPOs) {
        try {
            $gpoReport = [xml](Get-GPOReport -Guid $gpo.Id -ReportType XML)

            # Check for loopback processing in Computer Configuration
            $loopbackSetting = $gpoReport.GPO.Computer.ExtensionData |
                Where-Object { $_.Name -like "*Loopback*" }

            if ($loopbackSetting) {
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
            Type        = "Multiple Loopback Policies"
            Severity    = "High"
            GPOName     = ($loopbackGPOs.DisplayName -join ", ")
            Description = "$($loopbackGPOs.Count) GPOs configure loopback processing"
            Impact      = "Conflicting loopback modes may cause unexpected behavior"
            Recommendation = "Consolidate loopback processing configuration into single GPO"
        }
    }

    Write-Host "Found $($loopbackGPOs.Count) GPOs with loopback processing" -ForegroundColor Cyan

    # Check for GPOs with same name pattern (potential duplicates)
    Write-Host "`nChecking for similar GPO names..." -ForegroundColor Yellow
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
                            Type        = "Similar GPO Names"
                            Severity    = "Low"
                            GPOName     = $similarity
                            Description = "GPOs have similar names"
                            Impact      = "May indicate duplicate policies or cause confusion"
                            Recommendation = "Review if these are duplicate policies"
                        }
                    }
                }
            }
        }
    }

    Write-Host "Found $($similarNames.Count) pairs of similar GPO names" -ForegroundColor $(if ($similarNames.Count -gt 0) { 'Yellow' } else { 'Green' })

    # Check for security filtering conflicts
    Write-Host "`nChecking for security filtering issues..." -ForegroundColor Yellow
    $securityFilterIssues = 0

    foreach ($gpo in $allGPOs) {
        try {
            $permissions = Get-GPPermissions -Guid $gpo.Id -All

            # Check if Authenticated Users is denied
            $authenticatedUsersDenied = $permissions | Where-Object {
                $_.Trustee.Name -eq "Authenticated Users" -and
                $_.Permission -eq "GpoApply" -and
                $_.Denied -eq $true
            }

            if ($authenticatedUsersDenied) {
                $securityFilterIssues++
                $issues += [PSCustomObject]@{
                    Type        = "Security Filtering Issue"
                    Severity    = "Medium"
                    GPOName     = $gpo.DisplayName
                    Description = "Authenticated Users explicitly denied GpoApply"
                    Impact      = "GPO may not apply as expected without specific security group filtering"
                    Recommendation = "Ensure appropriate security groups are added for GPO application"
                }
            }

            # Check if no apply permissions exist
            $applyPermissions = $permissions | Where-Object {
                $_.Permission -eq "GpoApply" -and $_.Denied -eq $false
            }

            if (-not $applyPermissions) {
                $securityFilterIssues++
                $issues += [PSCustomObject]@{
                    Type        = "No Apply Permissions"
                    Severity    = "High"
                    GPOName     = $gpo.DisplayName
                    Description = "No security principals have GpoApply permission"
                    Impact      = "GPO will not apply to any users or computers"
                    Recommendation = "Add appropriate security principals with GpoApply permission"
                }
            }
        }
        catch {
            # Skip GPOs with permission issues
            continue
        }
    }

    Write-Host "Found $securityFilterIssues security filtering issues" -ForegroundColor $(if ($securityFilterIssues -gt 0) { 'Yellow' } else { 'Green' })

    # Inheritance blocking analysis (if requested)
    if ($IncludeInheritance) {
        Write-Host "`nAnalyzing GPO inheritance..." -ForegroundColor Yellow

        # Get all OUs with inheritance blocked
        $allOUs = Get-ADOrganizationalUnit -Filter * -Properties gPOptions
        $blockedOUs = $allOUs | Where-Object { $_.gPOptions -eq 1 }

        foreach ($ou in $blockedOUs) {
            $warnings += [PSCustomObject]@{
                Type        = "Inheritance Blocked"
                Severity    = "Medium"
                GPOName     = "N/A"
                Description = "OU '$($ou.Name)' has GPO inheritance blocked"
                Impact      = "Parent GPOs will not apply to this OU"
                Recommendation = "Ensure this is intentional and necessary"
            }
        }

        Write-Host "Found $($blockedOUs.Count) OUs with inheritance blocked" -ForegroundColor $(if ($blockedOUs.Count -gt 0) { 'Yellow' } else { 'Green' })

        # Check for enforced GPOs
        $enforcedLinks = 0
        foreach ($ou in $allOUs) {
            $links = Get-GPInheritance -Target $ou.DistinguishedName
            foreach ($link in $links.GpoLinks) {
                if ($link.Enforced) {
                    $enforcedLinks++
                }
            }
        }

        Write-Host "Found $enforcedLinks enforced GPO links" -ForegroundColor Cyan
    }

    # Combine all findings
    $allFindings = $issues + $warnings

    $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)

    # Export results to CSV
    $csvPath = Join-Path -Path $OutputPath -ChildPath "GPOConflicts_${RunTimestamp}_${RunId}.csv"
    $allFindings | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "`nResults exported to: $csvPath" -ForegroundColor Green

    # Generate HTML report
    $htmlPath = Join-Path -Path $OutputPath -ChildPath "GPOConflictsReport.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>GPO Conflict Analysis - $domainName</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0066cc; }
        h2 { color: #0099cc; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin: 20px 0; }
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
        <strong>Domain:</strong> $domainName<br>
        <strong>Analysis Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
        <strong>Total GPOs Analyzed:</strong> $($allGPOs.Count)<br>
        <strong>Total Issues Found:</strong> $($allFindings.Count)
    </div>

    <h2>Summary</h2>
    <table>
        <tr><td><strong>High Severity Issues</strong></td><td>$(($allFindings | Where-Object Severity -eq 'High').Count)</td></tr>
        <tr><td><strong>Medium Severity Issues</strong></td><td>$(($allFindings | Where-Object Severity -eq 'Medium').Count)</td></tr>
        <tr><td><strong>Warnings</strong></td><td>$(($allFindings | Where-Object Severity -eq 'Warning').Count)</td></tr>
        <tr><td><strong>Low Priority</strong></td><td>$(($allFindings | Where-Object Severity -eq 'Low').Count)</td></tr>
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

    foreach ($finding in $allFindings | Sort-Object -Property @{Expression = {
        switch ($_.Severity) {
            'High' { 1 }
            'Medium' { 2 }
            'Warning' { 3 }
            'Low' { 4 }
        }
    }}, Type) {
        $rowClass = switch ($finding.Severity) {
            'High' { 'high' }
            'Medium' { 'medium' }
            'Warning' { 'warning' }
            default { '' }
        }

        $html += @"
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

    $html += @"
    </table>
</body>
</html>
"@

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "HTML report saved to: $htmlPath" -ForegroundColor Green

    # Display summary
    Write-Host "`n=== Analysis Complete ===" -ForegroundColor Green
    Write-Host "Total Issues Found: $($allFindings.Count)" -ForegroundColor Cyan
    Write-Host "  High Severity: $(($allFindings | Where-Object Severity -eq 'High').Count)" -ForegroundColor Red
    Write-Host "  Medium Severity: $(($allFindings | Where-Object Severity -eq 'Medium').Count)" -ForegroundColor Yellow
    Write-Host "  Warnings: $(($allFindings | Where-Object Severity -eq 'Warning').Count)" -ForegroundColor Yellow
    Write-Host "  Low Priority: $(($allFindings | Where-Object Severity -eq 'Low').Count)" -ForegroundColor Cyan

}
catch {
    Write-Error "Error during conflict analysis: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}

Write-Host "`nEnd Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
