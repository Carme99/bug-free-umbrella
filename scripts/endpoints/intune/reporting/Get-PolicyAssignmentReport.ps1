<#
.SYNOPSIS
    Generates a comprehensive policy assignment report for Intune.

.DESCRIPTION
    Creates a detailed report showing all Intune policies, their assignments,
    and potential conflicts or overlaps. Helps identify assignment gaps and
    over-assignment issues.

.PARAMETER TenantId
    Azure AD Tenant ID (optional, will prompt if not provided)

.PARAMETER OutputPath
    Path to save the report (default: current directory)

.PARAMETER Format
    Output format: HTML or CSV (default: HTML)

.EXAMPLE
    .\Get-PolicyAssignmentReport.ps1 -Format HTML

.EXAMPLE
    .\Get-PolicyAssignmentReport.ps1 -TenantId "your-tenant-id" -Format CSV

.NOTES
    Author: Intune Admin
    Version: 1.0
    Requires: Microsoft.Graph.Intune module
    Permissions: DeviceManagementConfiguration.Read.All
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false)]
    [ValidateSet("HTML", "CSV")]
    [string]$Format = "HTML"
)

# Import helper module
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$scriptPath\..\IntuneGraphHelper.psm1" -Force

try {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-IntuneGraph -TenantId $TenantId

    Write-Host "Gathering policy information..." -ForegroundColor Cyan

    # Get all device configuration policies
    $configPolicies = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations" -Method GET
    $configPolicies = $configPolicies.value

    # Get all device compliance policies
    $compliancePolicies = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" -Method GET
    $compliancePolicies = $compliancePolicies.value

    # Get all configuration profiles (Settings Catalog)
    $settingsCatalog = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" -Method GET
    $settingsCatalog = $settingsCatalog.value

    # Get all app protection policies
    $appProtection = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceAppManagement/managedAppPolicies" -Method GET
    $appProtection = $appProtection.value

    Write-Host "Analyzing policy assignments..." -ForegroundColor Cyan

    $assignmentReport = @()

    # Process device configuration policies
    foreach ($policy in $configPolicies) {
        $assignments = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($policy.id)/assignments" -Method GET

        foreach ($assignment in $assignments.value) {
            $targetType = if ($assignment.target.'@odata.type' -match "allLicensedUsersAssignmentTarget") { "All Users" }
                         elseif ($assignment.target.'@odata.type' -match "allDevicesAssignmentTarget") { "All Devices" }
                         elseif ($assignment.target.'@odata.type' -match "groupAssignmentTarget") { "Group: $($assignment.target.groupId)" }
                         elseif ($assignment.target.'@odata.type' -match "exclusionGroupAssignmentTarget") { "Excluded Group: $($assignment.target.groupId)" }
                         else { "Unknown" }

            $assignmentReport += [PSCustomObject]@{
                PolicyName = $policy.displayName
                PolicyType = "Device Configuration"
                AssignmentTarget = $targetType
                Intent = $assignment.intent
                GroupId = $assignment.target.groupId
                CreatedDate = $policy.createdDateTime
                ModifiedDate = $policy.lastModifiedDateTime
            }
        }
    }

    # Process compliance policies
    foreach ($policy in $compliancePolicies) {
        $assignments = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)/assignments" -Method GET

        foreach ($assignment in $assignments.value) {
            $targetType = if ($assignment.target.'@odata.type' -match "allLicensedUsersAssignmentTarget") { "All Users" }
                         elseif ($assignment.target.'@odata.type' -match "allDevicesAssignmentTarget") { "All Devices" }
                         elseif ($assignment.target.'@odata.type' -match "groupAssignmentTarget") { "Group: $($assignment.target.groupId)" }
                         else { "Unknown" }

            $assignmentReport += [PSCustomObject]@{
                PolicyName = $policy.displayName
                PolicyType = "Compliance Policy"
                AssignmentTarget = $targetType
                Intent = "N/A"
                GroupId = $assignment.target.groupId
                CreatedDate = $policy.createdDateTime
                ModifiedDate = $policy.lastModifiedDateTime
            }
        }
    }

    # Process Settings Catalog policies
    foreach ($policy in $settingsCatalog) {
        $assignments = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policy.id)/assignments" -Method GET

        foreach ($assignment in $assignments.value) {
            $targetType = if ($assignment.target.'@odata.type' -match "allLicensedUsersAssignmentTarget") { "All Users" }
                         elseif ($assignment.target.'@odata.type' -match "allDevicesAssignmentTarget") { "All Devices" }
                         elseif ($assignment.target.'@odata.type' -match "groupAssignmentTarget") { "Group: $($assignment.target.groupId)" }
                         else { "Unknown" }

            $assignmentReport += [PSCustomObject]@{
                PolicyName = $policy.name
                PolicyType = "Settings Catalog"
                AssignmentTarget = $targetType
                Intent = "N/A"
                GroupId = $assignment.target.groupId
                CreatedDate = $policy.createdDateTime
                ModifiedDate = $policy.lastModifiedDateTime
            }
        }
    }

    Write-Host "Found $($assignmentReport.Count) policy assignments" -ForegroundColor Green

    # Detect potential conflicts (same group assigned multiple policies of same type)
    Write-Host "Analyzing for potential conflicts..." -ForegroundColor Cyan

    $conflicts = $assignmentReport | Group-Object -Property PolicyType, GroupId |
        Where-Object { $_.Count -gt 1 -and $_.Name -notmatch "All Users|All Devices" }

    if ($conflicts) {
        Write-Host "⚠️  Found $($conflicts.Count) potential policy conflicts" -ForegroundColor Yellow
    }

    # Generate report
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $reportPath = Join-Path $OutputPath "PolicyAssignmentReport-$timestamp.$($Format.ToLower())"

    if ($Format -eq "CSV") {
        $assignmentReport | Export-Csv -Path $reportPath -NoTypeInformation
    } else {
        # Generate HTML report
        $htmlReport = ConvertTo-IntuneHtmlReport -Data $assignmentReport -Title "Intune Policy Assignment Report" -Description "Generated on $(Get-Date)"
        $htmlReport | Out-File -FilePath $reportPath -Encoding UTF8
    }

    Write-Host "`n✅ Report generated successfully:" -ForegroundColor Green
    Write-Host "   $reportPath" -ForegroundColor Cyan
    Write-Host "`nSummary:" -ForegroundColor Yellow
    Write-Host "  Total Policies: $($assignmentReport | Select-Object -ExpandProperty PolicyName -Unique | Measure-Object | Select-Object -ExpandProperty Count)"
    Write-Host "  Total Assignments: $($assignmentReport.Count)"
    Write-Host "  Configuration Policies: $(($assignmentReport | Where-Object { $_.PolicyType -eq 'Device Configuration' }).Count)"
    Write-Host "  Compliance Policies: $(($assignmentReport | Where-Object { $_.PolicyType -eq 'Compliance Policy' }).Count)"
    Write-Host "  Settings Catalog: $(($assignmentReport | Where-Object { $_.PolicyType -eq 'Settings Catalog' }).Count)"

} catch {
    Write-Error "Error generating policy assignment report: $_"
    exit 1
}
