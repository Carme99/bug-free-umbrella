<#
.SYNOPSIS
    Detect conflicting configuration policies across Intune profiles, Settings Catalog, and compliance policies.

.DESCRIPTION
    This script analyzes configuration policies retrieved from Microsoft Graph to identify potential conflicts,
    including multiple same-type policies targeted at the same group, duplicate policy names, and overlapping
    assignments. Results are summarized in the console and exported as an HTML and/or CSV report under the
    user's Documents\Reports folder. The script is read-only: it never modifies tenant configuration, so it is
    safe to re-run at any time.

.PARAMETER ExportFormat
    Report format: HTML, CSV, or Both (default: HTML).

.PARAMETER CheckSettingsCatalog
    Include Settings Catalog policies in the analysis.

.PARAMETER CheckConfigurationProfiles
    Include Configuration Profiles in the analysis (default: true).

.PARAMETER CheckCompliancePolicies
    Include Compliance Policies in the analysis.

.EXAMPLE
    PS C:\> .\Find-PolicyConflicts.ps1
    Analyzes all configuration profiles for conflicts and writes an HTML report.

.EXAMPLE
    PS C:\> .\Find-PolicyConflicts.ps1 -CheckSettingsCatalog -CheckCompliancePolicies -ExportFormat Both
    Includes Settings Catalog and Compliance policies in the analysis and writes both HTML and CSV reports.

.NOTES
    File Name: Find-PolicyConflicts.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('HTML', 'CSV', 'Both')]
    [string]$ExportFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [switch]$CheckSettingsCatalog,

    [Parameter(Mandatory = $false)]
    [switch]$CheckConfigurationProfiles = $true,

    [Parameter(Mandatory = $false)]
    [switch]$CheckCompliancePolicies
)

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Starting policy conflict detection..." -ForegroundColor Cyan

        $ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
        if ([string]::IsNullOrWhiteSpace($ReportDir) -or
            $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
            $ReportDir -match '^(\\\\|//)') {
            throw "Unsafe report path: $ReportDir. Report path must be a local absolute path without '..' traversal."
        }
        $ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
        if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
            New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
        }

        # Import helper module (mock seam for offline testing)
        $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) "IntuneGraphHelper.psm1"
        Import-Module $modulePath -Force -ErrorAction Stop

        # Connect to Microsoft Graph
        $connected = Connect-IntuneGraph -Scopes @(
            "DeviceManagementConfiguration.Read.All",
            "DeviceManagementManagedDevices.Read.All"
        )

        if (-not $connected) {
            Write-Host "[-] Failed to connect to Microsoft Graph." -ForegroundColor Red
            return 1
        }

        try {
            $allPolicies = @()
            $conflicts = @()

            # Get Configuration Profiles
            $mgBetaBase = "https://graph.microsoft.com/beta/deviceManagement"
            if ($CheckConfigurationProfiles) {
                Write-Host "[*] Retrieving Configuration Profiles..." -ForegroundColor Cyan
                $listUri = "$mgBetaBase/deviceConfigurations"
                $configProfiles = Invoke-MgGraphRequest -Uri $listUri -ErrorAction Stop

                if ($configProfiles.value) {
                    foreach ($configProfile in $configProfiles.value) {
                        $assignUri = "$mgBetaBase/deviceConfigurations/$($configProfile.id)/assignments"
                        $assignments = Invoke-MgGraphRequest -Uri $assignUri -ErrorAction Stop

                        $allPolicies += [PSCustomObject]@{
                            Id                   = $configProfile.id
                            Name                 = $configProfile.displayName
                            Type                 = "Configuration Profile"
                            ODataType            = $configProfile.'@odata.type'
                            CreatedDateTime      = $configProfile.createdDateTime
                            LastModifiedDateTime = $configProfile.lastModifiedDateTime
                            Assignments          = $assignments.value
                            Settings             = $configProfile
                        }
                    }
                    Write-Host "[+] Retrieved $($configProfiles.value.Count) Configuration Profiles" `
                        -ForegroundColor Green
                }
            }

            # Get Settings Catalog Policies
            if ($CheckSettingsCatalog) {
                Write-Host "[*] Retrieving Settings Catalog policies..." -ForegroundColor Cyan
                $listUri = "$mgBetaBase/configurationPolicies"
                $settingsCatalog = Invoke-MgGraphRequest -Uri $listUri -ErrorAction Stop

                if ($settingsCatalog.value) {
                    foreach ($policy in $settingsCatalog.value) {
                        $assignUri = "$mgBetaBase/configurationPolicies/$($policy.id)/assignments"
                        $assignments = Invoke-MgGraphRequest -Uri $assignUri -ErrorAction Stop

                        $allPolicies += [PSCustomObject]@{
                            Id                   = $policy.id
                            Name                 = $policy.name
                            Type                 = "Settings Catalog"
                            ODataType            = "SettingsCatalog"
                            CreatedDateTime      = $policy.createdDateTime
                            LastModifiedDateTime = $policy.lastModifiedDateTime
                            Assignments          = $assignments.value
                            Settings             = $policy
                        }
                    }
                    Write-Host "[+] Retrieved $($settingsCatalog.value.Count) Settings Catalog policies" `
                        -ForegroundColor Green
                }
            }

            # Get Compliance Policies
            if ($CheckCompliancePolicies) {
                Write-Host "[*] Retrieving Compliance Policies..." -ForegroundColor Cyan
                $listUri = "$mgBetaBase/deviceCompliancePolicies"
                $compliancePolicies = Invoke-MgGraphRequest -Uri $listUri -ErrorAction Stop

                if ($compliancePolicies.value) {
                    foreach ($policy in $compliancePolicies.value) {
                        $assignUri = "$mgBetaBase/deviceCompliancePolicies/$($policy.id)/assignments"
                        $assignments = Invoke-MgGraphRequest -Uri $assignUri -ErrorAction Stop

                        $allPolicies += [PSCustomObject]@{
                            Id                   = $policy.id
                            Name                 = $policy.displayName
                            Type                 = "Compliance Policy"
                            ODataType            = $policy.'@odata.type'
                            CreatedDateTime      = $policy.createdDateTime
                            LastModifiedDateTime = $policy.lastModifiedDateTime
                            Assignments          = $assignments.value
                            Settings             = $policy
                        }
                    }
                    Write-Host "[+] Retrieved $($compliancePolicies.value.Count) Compliance Policies" `
                        -ForegroundColor Green
                }
            }

            Write-Host "[*] Total policies to analyze: $($allPolicies.Count)" -ForegroundColor White

            if ($allPolicies.Count -eq 0) {
                Write-Host "[!] No policies found to analyze." -ForegroundColor Yellow
                return 0
            }

            # Analyze for conflicts
            Write-Host "[*] Analyzing for conflicts..." -ForegroundColor Cyan

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
                            PolicyId   = $policy.Id
                            PolicyName = $policy.Name
                            PolicyType = $policy.Type
                            ODataType  = $policy.ODataType
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
                                ConflictType   = "Overlapping Assignment"
                                Severity       = "Medium"
                                TargetGroup    = $target
                                PolicyCount    = $typeGroup.Count
                                PolicyType     = $typeGroup.Name
                                Policies       = ($typeGroup.Group.PolicyName -join "; ")
                                Description    = ("$($typeGroup.Count) policies of type '$($typeGroup.Name)' " +
                                    "assigned to same target")
                                Recommendation = ("Review policies to ensure settings don't conflict. " +
                                    "Consider consolidating.")
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
                        ConflictType   = "Duplicate Policy Name"
                        Severity       = "Low"
                        TargetGroup    = "N/A"
                        PolicyCount    = $group.Count
                        PolicyType     = ($group.Group.Type | Select-Object -Unique) -join ", "
                        Policies       = ($group.Group.Name -join "; ")
                        Description    = "$($group.Count) policies with identical name: '$($group.Name)'"
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
                            ConflictType   = "Same Type Overlap"
                            Severity       = "High"
                            TargetGroup    = $target
                            PolicyCount    = $odataGroup.Count
                            PolicyType     = $odataGroup.Name
                            Policies       = ($policyNames -join "; ")
                            Description    = ("Multiple policies of type '$($odataGroup.Name)' may have " +
                                "conflicting settings")
                            Recommendation = "Review settings in these policies. Last applied policy typically wins."
                        }
                    }
                }
            }

            # Display summary
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "CONFLICT ANALYSIS SUMMARY" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan

            Write-Host "Total Policies Analyzed:  $($allPolicies.Count)" -ForegroundColor White
            $conflictColor = if ($conflicts.Count -gt 0) { 'Yellow' } else { 'Green' }
            Write-Host "Potential Conflicts:      $($conflicts.Count)" -ForegroundColor $conflictColor

            if ($conflicts.Count -gt 0) {
                $high = ($conflicts | Where-Object { $_.Severity -eq "High" }).Count
                $medium = ($conflicts | Where-Object { $_.Severity -eq "Medium" }).Count
                $low = ($conflicts | Where-Object { $_.Severity -eq "Low" }).Count

                Write-Host ""
                Write-Host "By Severity:" -ForegroundColor Cyan
                Write-Host "  High:    $high" -ForegroundColor Red
                Write-Host "  Medium:  $medium" -ForegroundColor Yellow
                Write-Host "  Low:     $low" -ForegroundColor Gray

                Write-Host ""
                Write-Host "By Type:" -ForegroundColor Cyan
                $conflictTypes = $conflicts | Group-Object -Property ConflictType
                foreach ($type in $conflictTypes | Sort-Object Count -Descending) {
                    Write-Host "  $($type.Name): $($type.Count)" -ForegroundColor White
                }
            }

            if ($conflicts.Count -eq 0) {
                Write-Host "[+] No policy conflicts detected!" -ForegroundColor Green
                return 0
            }

            # Sort conflicts by severity
            $severityOrder = @{ "High" = 1; "Medium" = 2; "Low" = 3 }
            $conflicts = $conflicts | Sort-Object { $severityOrder[$_.Severity] }, ConflictType

            # Export reports
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $outputPath = $ReportDir

            if ($ExportFormat -eq 'HTML' -or $ExportFormat -eq 'Both') {
                $htmlPath = Join-Path $outputPath "PolicyConflicts_$timestamp.html"
                Export-IntuneReportToHTML -Data $conflicts `
                    -Title "Policy Conflict Analysis" `
                    -FilePath $htmlPath -ErrorAction Stop
            }

            if ($ExportFormat -eq 'CSV' -or $ExportFormat -eq 'Both') {
                $csvPath = Join-Path $outputPath "PolicyConflicts_$timestamp.csv"
                Export-IntuneReportToCSV -Data $conflicts -Title "PolicyConflicts" -FilePath $csvPath -ErrorAction Stop
            }

            # Recommendations
            Write-Host ""
            Write-Host "[!] RECOMMENDATIONS:" -ForegroundColor Yellow
            Write-Host "  - Review HIGH severity conflicts immediately" -ForegroundColor Yellow
            Write-Host "  - Consolidate policies where possible" -ForegroundColor Yellow
            Write-Host "  - Use unique, descriptive names for all policies" -ForegroundColor Yellow
            Write-Host "  - Document policy assignment strategy" -ForegroundColor Yellow
            Write-Host "  - Test policy changes on pilot groups first" -ForegroundColor Yellow
        }
        finally {
            # Disconnect from Graph
            Disconnect-IntuneGraph
        }

        Write-Host "[+] Policy conflict analysis completed!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
