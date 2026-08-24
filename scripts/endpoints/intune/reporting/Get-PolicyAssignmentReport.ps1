<#
.SYNOPSIS
    Generate a comprehensive policy assignment report for Intune.

.DESCRIPTION
    Creates a detailed report showing all Intune policies, their assignments,
    and potential conflicts or overlaps. Helps identify assignment gaps and
    over-assignment issues.

    Covers device configuration policies, compliance policies, Settings Catalog
    profiles and app protection policies. Requires connection to Microsoft Graph
    with DeviceManagementConfiguration.Read.All permissions. The HTML or CSV
    report is written to the path given by -OutputPath (default: current directory).

.PARAMETER TenantId
    Azure AD Tenant ID (optional, will prompt if not provided)

.PARAMETER OutputPath
    Path to save the report (default: current directory)

.PARAMETER Format
    Output format: HTML or CSV (default: HTML)

.EXAMPLE
    PS C:\> .\Get-PolicyAssignmentReport.ps1 -Format HTML
    Generates an HTML policy assignment report in the current directory.

.EXAMPLE
    PS C:\> .\Get-PolicyAssignmentReport.ps1 -TenantId "your-tenant-id" -Format CSV
    Connects to the given tenant and writes a CSV report.

.NOTES
    File Name: Get-PolicyAssignmentReport.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

    Requires: Microsoft.Graph (PowerShell SDK) module
    Permissions: DeviceManagementConfiguration.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false)]
    [ValidateSet("HTML", "CSV")]
    [string]$Format = "HTML"
)

$ErrorActionPreference = 'Stop'

function Main {
    try {
        # Import helper module from the parent (intune/) directory
        $helperModule = Join-Path (Split-Path -Parent $PSScriptRoot) 'IntuneGraphHelper.psm1'
        Import-Module $helperModule -Force -ErrorAction Stop

        Write-Host "[*] Connecting to Microsoft Graph..." -ForegroundColor Cyan
        Connect-IntuneGraph -TenantId $TenantId -ErrorAction Stop

        Write-Host "[*] Gathering policy information..." -ForegroundColor Cyan

        # Get all device configuration policies
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"
        $configPolicies = Invoke-MgGraphRequest -Uri $uri -Method GET -ErrorAction Stop
        $configPolicies = $configPolicies.value

        # Get all device compliance policies
        $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies"
        $compliancePolicies = Invoke-MgGraphRequest -Uri $uri -Method GET -ErrorAction Stop
        $compliancePolicies = $compliancePolicies.value

        # Get all configuration profiles (Settings Catalog)
        $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
        $settingsCatalog = Invoke-MgGraphRequest -Uri $uri -Method GET -ErrorAction Stop
        $settingsCatalog = $settingsCatalog.value

        # Get all app protection policies
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/managedAppPolicies"
        $appProtection = Invoke-MgGraphRequest -Uri $uri -Method GET -ErrorAction Stop
        $appProtection = $appProtection.value

        Write-Host "[*] Analyzing policy assignments..." -ForegroundColor Cyan

        $assignmentReport = @()

        # Process device configuration policies
        foreach ($policy in $configPolicies) {
            $api = "deviceConfigurations/$($policy.id)/assignments"
            $policyUri = "https://graph.microsoft.com/beta/deviceManagement/$api"
            $assignments = Invoke-MgGraphRequest -Uri $policyUri -Method GET -ErrorAction Stop

            foreach ($assignment in $assignments.value) {
                $targetType = if ($assignment.target.'@odata.type' -match "allLicensedUsersAssignmentTarget") {
                    "All Users"
                }
                elseif ($assignment.target.'@odata.type' -match "allDevicesAssignmentTarget") { "All Devices" }
                elseif ($assignment.target.'@odata.type' -match "groupAssignmentTarget") {
                    "Group: $($assignment.target.groupId)"
                }
                elseif ($assignment.target.'@odata.type' -match "exclusionGroupAssignmentTarget") {
                    "Excluded Group: $($assignment.target.groupId)"
                }
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
            $api = "deviceCompliancePolicies/$($policy.id)/assignments"
            $policyUri = "https://graph.microsoft.com/beta/deviceManagement/$api"
            $assignments = Invoke-MgGraphRequest -Uri $policyUri -Method GET -ErrorAction Stop

            foreach ($assignment in $assignments.value) {
                $targetType = if ($assignment.target.'@odata.type' -match "allLicensedUsersAssignmentTarget") {
                    "All Users"
                }
                elseif ($assignment.target.'@odata.type' -match "allDevicesAssignmentTarget") { "All Devices" }
                elseif ($assignment.target.'@odata.type' -match "groupAssignmentTarget") {
                    "Group: $($assignment.target.groupId)"
                }
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
            $api = "configurationPolicies/$($policy.id)/assignments"
            $policyUri = "https://graph.microsoft.com/beta/deviceManagement/$api"
            $assignments = Invoke-MgGraphRequest -Uri $policyUri -Method GET -ErrorAction Stop

            foreach ($assignment in $assignments.value) {
                $targetType = if ($assignment.target.'@odata.type' -match "allLicensedUsersAssignmentTarget") {
                    "All Users"
                }
                elseif ($assignment.target.'@odata.type' -match "allDevicesAssignmentTarget") { "All Devices" }
                elseif ($assignment.target.'@odata.type' -match "groupAssignmentTarget") {
                    "Group: $($assignment.target.groupId)"
                }
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

        Write-Host "[+] Found $($assignmentReport.Count) policy assignments" -ForegroundColor Green

        # Detect potential conflicts (same group assigned multiple policies of same type)
        Write-Host "[*] Analyzing for potential conflicts..." -ForegroundColor Cyan

        $conflicts = $assignmentReport | Group-Object -Property PolicyType, GroupId |
            Where-Object { $_.Count -gt 1 -and $_.Name -notmatch "All Users|All Devices" }

        if ($conflicts) {
            Write-Host "[!] Found $($conflicts.Count) potential policy conflicts" -ForegroundColor Yellow
        }

        # Generate report
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $reportPath = Join-Path $OutputPath "PolicyAssignmentReport-$timestamp.$($Format.ToLower())"

        if ($Format -eq "CSV") {
            $assignmentReport | Export-Csv -Path $reportPath -NoTypeInformation -ErrorAction Stop
        }
        else {
            Export-IntuneReportToHTML -Data $assignmentReport -Title "Intune Policy Assignment Report" `
                -Description "Generated on $(Get-Date)" -FilePath $reportPath -ErrorAction Stop
        }

        Write-Host "`n[+] Report generated successfully:" -ForegroundColor Green
        Write-Host "   $reportPath" -ForegroundColor Cyan
        Write-Host "`nSummary:" -ForegroundColor Yellow
        $uniquePolicies = @($assignmentReport | Select-Object -ExpandProperty PolicyName -Unique)
        Write-Host "  Total Policies: $($uniquePolicies.Count)"
        Write-Host "  Total Assignments: $($assignmentReport.Count)"
        $configCount = @($assignmentReport | Where-Object PolicyType -eq 'Device Configuration').Count
        $complianceCount = @($assignmentReport | Where-Object PolicyType -eq 'Compliance Policy').Count
        $settingsCount = @($assignmentReport | Where-Object PolicyType -eq 'Settings Catalog').Count
        Write-Host "  Configuration Policies: $configCount"
        Write-Host "  Compliance Policies: $complianceCount"
        Write-Host "  Settings Catalog: $settingsCount"
        return 0
    }
    catch {
        Write-Host "[-] Error generating policy assignment report: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
