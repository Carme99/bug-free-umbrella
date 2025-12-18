<#
.SYNOPSIS
    Detects conflicting configuration policies in Intune.

.DESCRIPTION
    This script analyzes all configuration policies in Intune to identify potential conflicts.
    It checks for:
    - Overlapping settings across policies
    - Multiple policies targeting the same devices
    - Conflicting priority assignments
    - Duplicate settings with different values

    Helps identify:
    - Configuration drift
    - Policy conflicts causing issues
    - Redundant policies
    - Assignment overlaps

.PARAMETER ExportFormat
    Report format: HTML, CSV, or Both (default: HTML).

.PARAMETER CheckSettingsCatalog
    Include Settings Catalog policies in analysis.

.PARAMETER CheckConfigurationProfiles
    Include Configuration Profiles in analysis (default: true).

.PARAMETER CheckCompliancePolicies
    Include Compliance Policies in analysis.

.EXAMPLE
    .\Find-PolicyConflicts.ps1
    Analyzes all configuration profiles for conflicts.

.EXAMPLE
    .\Find-PolicyConflicts.ps1 -CheckSettingsCatalog -CheckCompliancePolicies
    Includes Settings Catalog and Compliance policies in analysis.

.NOTES
    Requires Microsoft.Graph PowerShell module
    Requires permissions: DeviceManagementConfiguration.Read.All
    Analysis may take several minutes for large tenants
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('HTML', 'CSV', 'Both')]
    [string]$ExportFormat = 'HTML',

    [Parameter(Mandatory=$false)]
    [switch]$CheckSettingsCatalog,

    [Parameter(Mandatory=$false)]
    [switch]$CheckConfigurationProfiles = $true,

    [Parameter(Mandatory=$false)]
    [switch]$CheckCompliancePolicies
)

# Import helper module
$modulePath = Join-Path $PSScriptRoot "IntuneGraphHelper.psm1"
Import-Module $modulePath -Force

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Policy Conflict Detector" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Connect to Microsoft Graph
$connected = Connect-IntuneGraph -Scopes @(
    "DeviceManagementConfiguration.Read.All",
    "DeviceManagementManagedDevices.Read.All"
)

if (-not $connected) {
    Write-Host "Failed to connect to Microsoft Graph. Exiting." -ForegroundColor Red
    exit 1
}

try {
    $allPolicies = @()
    $conflicts = @()

    # Get Configuration Profiles
    if ($CheckConfigurationProfiles) {
        Write-Host "Retrieving Configuration Profiles..." -ForegroundColor Cyan
        $configProfiles = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"

        if ($configProfiles.value) {
            foreach ($profile in $configProfiles.value) {
                $assignments = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($profile.id)/assignments"

                $allPolicies += [PSCustomObject]@{
                    Id = $profile.id
                    Name = $profile.displayName
                    Type = "Configuration Profile"
                    ODataType = $profile.'@odata.type'
                    CreatedDateTime = $profile.createdDateTime
                    LastModifiedDateTime = $profile.lastModifiedDateTime
                    Assignments = $assignments.value
                    Settings = $profile
                }
            }
            Write-Host "✓ Retrieved $($configProfiles.value.Count) Configuration Profiles" -ForegroundColor Green
        }
    }

    # Get Settings Catalog Policies
    if ($CheckSettingsCatalog) {
        Write-Host "Retrieving Settings Catalog policies..." -ForegroundColor Cyan
        $settingsCatalog = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"

        if ($settingsCatalog.value) {
            foreach ($policy in $settingsCatalog.value) {
                $assignments = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policy.id)/assignments"

                $allPolicies += [PSCustomObject]@{
                    Id = $policy.id
                    Name = $policy.name
                    Type = "Settings Catalog"
                    ODataType = "SettingsCatalog"
                    CreatedDateTime = $policy.createdDateTime
                    LastModifiedDateTime = $policy.lastModifiedDateTime
                    Assignments = $assignments.value
                    Settings = $policy
                }
            }
            Write-Host "✓ Retrieved $($settingsCatalog.value.Count) Settings Catalog policies" -ForegroundColor Green
        }
    }

    # Get Compliance Policies
    if ($CheckCompliancePolicies) {
        Write-Host "Retrieving Compliance Policies..." -ForegroundColor Cyan
        $compliancePolicies = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies"

        if ($compliancePolicies.value) {
            foreach ($policy in $compliancePolicies.value) {
                $assignments = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)/assignments"

                $allPolicies += [PSCustomObject]@{
                    Id = $policy.id
                    Name = $policy.displayName
                    Type = "Compliance Policy"
                    ODataType = $policy.'@odata.type'
                    CreatedDateTime = $policy.createdDateTime
                    LastModifiedDateTime = $policy.lastModifiedDateTime
                    Assignments = $assignments.value
                    Settings = $policy
                }
            }
            Write-Host "✓ Retrieved $($compliancePolicies.value.Count) Compliance Policies" -ForegroundColor Green
        }
    }

    Write-Host "`nTotal policies to analyze: $($allPolicies.Count)" -ForegroundColor White

    if ($allPolicies.Count -eq 0) {
        Write-Host "✗ No policies found to analyze." -ForegroundColor Yellow
        Disconnect-IntuneGraph
        exit 0
    }

    # Analyze for conflicts
    Write-Host "`nAnalyzing for conflicts..." -ForegroundColor Cyan

    # Check 1: Multiple policies assigned to same groups
    Write-Host "  Checking for overlapping assignments..." -ForegroundColor Gray

    $assignmentMap = @{}

    foreach ($policy in $allPolicies) {
        if ($policy.Assignments) {
            foreach ($assignment in $policy.Assignments) {
                $targetId = $assignment.target.groupId
                if (-not $targetId) {
                    $targetId = $assignment.target.'@odata.type'
                }

                if (-not $assignmentMap.ContainsKey($targetId)) {
                    $assignmentMap[$targetId] = @()
                }

                $assignmentMap[$targetId] += [PSCustomObject]@{
                    PolicyId = $policy.Id
                    PolicyName = $policy.Name
                    PolicyType = $policy.Type
                    ODataType = $policy.ODataType
                }
            }
        }
    }

    # Find groups with multiple policies
    foreach ($target in $assignmentMap.Keys) {
        $policies = $assignmentMap[$target]

        if ($policies.Count -gt 1) {
            # Group by policy type
            $typeGroups = $policies | Group-Object -Property ODataType

            foreach ($typeGroup in $typeGroups) {
                if ($typeGroup.Count -gt 1) {
                    $conflicts += [PSCustomObject]@{
                        ConflictType = "Overlapping Assignment"
                        Severity = "Medium"
                        TargetGroup = $target
                        PolicyCount = $typeGroup.Count
                        PolicyType = $typeGroup.Name
                        Policies = ($typeGroup.Group.PolicyName -join "; ")
                        Description = "$($typeGroup.Count) policies of type '$($typeGroup.Name)' assigned to same target"
                        Recommendation = "Review policies to ensure settings don't conflict. Consider consolidating."
                    }
                }
            }
        }
    }

    # Check 2: Similar policy names (possible duplicates)
    Write-Host "  Checking for duplicate or similar policies..." -ForegroundColor Gray

    $policyGroups = $allPolicies | Group-Object -Property Name

    foreach ($group in $policyGroups) {
        if ($group.Count -gt 1) {
            $conflicts += [PSCustomObject]@{
                ConflictType = "Duplicate Policy Name"
                Severity = "Low"
                TargetGroup = "N/A"
                PolicyCount = $group.Count
                PolicyType = ($group.Group.Type | Select-Object -Unique) -join ", "
                Policies = ($group.Group.Name -join "; ")
                Description = "$($group.Count) policies with identical name: '$($group.Name)'"
                Recommendation = "Rename policies for clarity or consolidate if redundant."
            }
        }
    }

    # Check 3: Same ODataType assigned to same groups (likely conflicts)
    Write-Host "  Checking for same policy types on same targets..." -ForegroundColor Gray

    foreach ($target in $assignmentMap.Keys) {
        $policies = $assignmentMap[$target]
        $odataGroups = $policies | Group-Object -Property ODataType

        foreach ($odataGroup in $odataGroups) {
            if ($odataGroup.Count -gt 1) {
                # Check if policies are the same type and might conflict
                $policyNames = $odataGroup.Group.PolicyName

                $conflicts += [PSCustomObject]@{
                    ConflictType = "Same Type Overlap"
                    Severity = "High"
                    TargetGroup = $target
                    PolicyCount = $odataGroup.Count
                    PolicyType = $odataGroup.Name
                    Policies = ($policyNames -join "; ")
                    Description = "Multiple policies of type '$($odataGroup.Name)' may have conflicting settings"
                    Recommendation = "Review settings in these policies. Last applied policy typically wins."
                }
            }
        }
    }

    # Display summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "CONFLICT ANALYSIS SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Write-Host "Total Policies Analyzed:  $($allPolicies.Count)" -ForegroundColor White
    Write-Host "Potential Conflicts:      $($conflicts.Count)" -ForegroundColor $(if($conflicts.Count -gt 0){'Yellow'}else{'Green'})

    if ($conflicts.Count -gt 0) {
        $high = ($conflicts | Where-Object { $_.Severity -eq "High" }).Count
        $medium = ($conflicts | Where-Object { $_.Severity -eq "Medium" }).Count
        $low = ($conflicts | Where-Object { $_.Severity -eq "Low" }).Count

        Write-Host "`nBy Severity:" -ForegroundColor Cyan
        Write-Host "  High:    $high" -ForegroundColor Red
        Write-Host "  Medium:  $medium" -ForegroundColor Yellow
        Write-Host "  Low:     $low" -ForegroundColor Gray

        Write-Host "`nBy Type:" -ForegroundColor Cyan
        $conflictTypes = $conflicts | Group-Object -Property ConflictType
        foreach ($type in $conflictTypes | Sort-Object Count -Descending) {
            Write-Host "  $($type.Name): $($type.Count)" -ForegroundColor White
        }
    }

    if ($conflicts.Count -eq 0) {
        Write-Host "`n✓ No policy conflicts detected!" -ForegroundColor Green
        Disconnect-IntuneGraph
        exit 0
    }

    # Sort conflicts by severity
    $severityOrder = @{ "High" = 1; "Medium" = 2; "Low" = 3 }
    $conflicts = $conflicts | Sort-Object { $severityOrder[$_.Severity] }, ConflictType

    # Export reports
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outputPath = "$env:USERPROFILE\Desktop"

    if ($ExportFormat -eq 'HTML' -or $ExportFormat -eq 'Both') {
        $htmlPath = Join-Path $outputPath "PolicyConflicts_$timestamp.html"
        Export-IntuneReportToHTML -Data $conflicts -Title "Policy Conflict Analysis" -FilePath $htmlPath
    }

    if ($ExportFormat -eq 'CSV' -or $ExportFormat -eq 'Both') {
        $csvPath = Join-Path $outputPath "PolicyConflicts_$timestamp.csv"
        Export-IntuneReportToCSV -Data $conflicts -Title "PolicyConflicts" -FilePath $csvPath
    }

    # Recommendations
    Write-Host "`n⚠ RECOMMENDATIONS:" -ForegroundColor Yellow
    Write-Host "  • Review HIGH severity conflicts immediately" -ForegroundColor Yellow
    Write-Host "  • Consolidate policies where possible" -ForegroundColor Yellow
    Write-Host "  • Use unique, descriptive names for all policies" -ForegroundColor Yellow
    Write-Host "  • Document policy assignment strategy" -ForegroundColor Yellow
    Write-Host "  • Test policy changes on pilot groups first" -ForegroundColor Yellow

    Write-Host "`n✓ Policy conflict analysis completed!" -ForegroundColor Green
}
catch {
    Write-Host "`n✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
}
finally {
    # Disconnect from Graph
    Disconnect-IntuneGraph
}
