<#
.SYNOPSIS
    Report Intune settings catalog policies with their assignments, filters and status.

.DESCRIPTION
    Reads every settings catalog policy with Get-MgDeviceManagementConfigurationPolicy -All and
    reports, per policy: platforms, technologies, template family, setting count, assignment
    count and targets, scope tags and assignment filters, plus the per-setting status counts
    (devices successfully applied, in conflict, in error).

    Grounding:
    - Settings catalog overview:
      https://learn.microsoft.com/intune/device-configuration/settings-catalog/
    - Graph configurationPolicies list operation:
      https://learn.microsoft.com/graph/api/intune-deviceconfigv2-devicemanagementconfigurationpolicy-list
    - Microsoft.Graph.Beta.DeviceManagement cmdlet index:
      https://learn.microsoft.com/powershell/module/microsoft.graph.beta.devicemanagement/
    - Tenant Configuration Management resource model:
      https://learn.microsoft.com/graph/utcm-intune-resources
    - Per-setting state vocabulary (deviceConfigurationSettingState):
      https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-deviceconfigurationsettingstate

    The script flags policies whose settingCount is zero, policies assigned to nobody, and
    policies whose per-setting status reports devices in conflict or in error. Status counts are
    always printed; -NonCompliantOnly narrows only the rows that are reported and exported.

    The script is strictly read-only: it only reads Microsoft Graph and writes the optional
    report file named by -OutputPath. Requires the Microsoft.Graph.DeviceManagement module and
    the DeviceManagementConfiguration.Read.All permission.
    Exit codes: 0 = report produced and no findings; 2 = findings present; 1 = fatal error.

.PARAMETER PolicyName
    Name filter applied to the policy list. Wildcards are allowed; defaults to * (all policies).

.PARAMETER Platform
    Restrict the report to one platform: Windows, macOS, iOS or Android. When omitted every
    platform is reported. The values map to the Graph platforms enum (windows10, macOS, iOS,
    android).

.PARAMETER NonCompliantOnly
    Report and export only the policies that have at least one finding. The summary counts
    still describe every matching policy.

.PARAMETER OutputFormat
    Report format: Table (console only), Json or Csv. Defaults to Table.

.PARAMETER OutputPath
    File to write when -OutputFormat is Json or Csv. When omitted the rendered report is written
    to the console instead.

.EXAMPLE
    PS C:\> .\Get-SettingsCatalogPolicyReport.ps1
    Reports every settings catalog policy in the tenant to the console.

.EXAMPLE
    PS C:\> .\Get-SettingsCatalogPolicyReport.ps1 -Platform Windows -NonCompliantOnly
    Reports only the Windows policies that have findings.

.EXAMPLE
    PS C:\> .\Get-SettingsCatalogPolicyReport.ps1 -PolicyName 'Baseline*' -OutputFormat Csv `
        -OutputPath C:\Reports\settings-catalog.csv
    Writes the matching policies to a CSV file; exit code is 2 when any policy has a finding.

.NOTES
   File Name   : Get-SettingsCatalogPolicyReport.ps1
   Author      : Bug-Free Umbrella
   Prerequisite: PowerShell 7.0
   Version     : 2.0.0
   Date        : 2026-09-16
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$PolicyName = '*',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Windows', 'macOS', 'iOS', 'Android')]
    [string]$Platform,

    [Parameter(Mandatory = $false)]
    [switch]$NonCompliantOnly,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'Json', 'Csv')]
    [string]$OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# Friendly platform names mapped onto the Graph deviceManagementConfigurationPolicy platforms enum.
$script:PlatformMap = @{
    Windows = 'windows10'
    macOS   = 'macOS'
    iOS     = 'iOS'
    Android = 'android'
}

function Get-SettingStateTotal {
    # Collapses the per-setting status collection into applied / conflict / error device totals.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$SettingStatus,
        [Parameter(Mandatory = $true)][string]$State
    )

    $total = 0
    foreach ($status in @($SettingStatus)) {
        if ($null -eq $status) { continue }
        $current = ''
        if ($null -ne $status.state) { $current = ([string]$status.state).ToLowerInvariant() }
        if ($current -ne $State.ToLowerInvariant()) { continue }
        if ($null -ne $status.deviceCount) { $total += [int]$status.deviceCount }
    }

    return $total
}

function Main {
    try {
        if (-not (Get-Command -Name 'Get-MgDeviceManagementConfigurationPolicy' `
                -ErrorAction SilentlyContinue)) {
            throw ('Get-MgDeviceManagementConfigurationPolicy is not available. ' +
                'Install-Module Microsoft.Graph.DeviceManagement')
        }

        Write-Host '[+] Microsoft Graph DeviceManagement cmdlets are available' `
            -ForegroundColor Green
        Write-Host '[*] Reading settings catalog policies from Intune' -ForegroundColor Cyan

        $policies = @(Get-MgDeviceManagementConfigurationPolicy -All -ErrorAction Stop)
        Write-Host "[+] Retrieved $($policies.Count) settings catalog policies" `
            -ForegroundColor Green

        $nameFilter = $PolicyName
        if (-not $nameFilter) { $nameFilter = '*' }

        $wantedPlatform = ''
        if ($Platform) { $wantedPlatform = $script:PlatformMap[$Platform] }

        $rows = @()
        foreach ($policy in $policies) {
            $policyName = ''
            if ($null -ne $policy.name) { $policyName = [string]$policy.name }
            if ($policyName -notlike $nameFilter) { continue }

            $platforms = @()
            if ($null -ne $policy.platforms) {
                $platforms = @($policy.platforms -split ',' | Where-Object { $_ -ne '' })
            }
            if ($wantedPlatform -and ($platforms -notcontains $wantedPlatform)) { continue }

            $technologies = ''
            if ($null -ne $policy.technologies) { $technologies = [string]$policy.technologies }

            $templateFamily = ''
            if ($null -ne $policy.templateReference) {
                $templateFamily = [string]$policy.templateReference.templateFamily
            }

            $settingCount = 0
            if ($null -ne $policy.settingCount) { $settingCount = [int]$policy.settingCount }

            $assignments = @()
            if ($null -ne $policy.assignments) { $assignments = @($policy.assignments) }

            $targets = @()
            $filters = @()
            foreach ($assignment in $assignments) {
                if ($null -eq $assignment) { continue }
                $target = $assignment.target
                if ($null -eq $target) { continue }

                $targetType = [string]$target.'@odata.type'
                if ($targetType) { $targets += $targetType }

                $filterId = [string]$target.deviceAndAppManagementAssignmentFilterId
                if ($filterId) {
                    $filterType = [string]$target.deviceAndAppManagementAssignmentFilterType
                    $filters += ($filterId + ' (' + $filterType + ')')
                }
            }

            $scopeTags = @()
            if ($null -ne $policy.roleScopeTagIds) {
                $scopeTags = @($policy.roleScopeTagIds | Where-Object { $_ })
            }

            $applied = 0
            $conflicts = 0
            $errors = 0
            if ($null -ne $policy.settingStatuses) {
                $applied = Get-SettingStateTotal -SettingStatus $policy.settingStatuses `
                    -State 'compliant'
                $conflicts = Get-SettingStateTotal -SettingStatus $policy.settingStatuses `
                    -State 'conflict'
                $errors = Get-SettingStateTotal -SettingStatus $policy.settingStatuses `
                    -State 'error'
            }

            $rowFindings = @()
            if ($settingCount -le 0) { $rowFindings += 'zero settings' }
            if ($assignments.Count -eq 0) { $rowFindings += 'assigned to nobody' }
            if ($conflicts -gt 0) { $rowFindings += "$conflicts device(s) in conflict" }
            if ($errors -gt 0) { $rowFindings += "$errors device(s) in error" }

            $rows += [pscustomobject]@{
                PolicyName        = $policyName
                Platforms         = ($platforms -join '; ')
                Technologies      = $technologies
                TemplateFamily    = $templateFamily
                SettingCount      = $settingCount
                Assignments       = $assignments.Count
                Targets           = ($targets -join '; ')
                ScopeTags         = ($scopeTags -join '; ')
                AssignmentFilters = ($filters -join '; ')
                AppliedDevices    = $applied
                ConflictDevices   = $conflicts
                ErrorDevices      = $errors
                Findings          = ($rowFindings -join '; ')
            }
        }

        # Summary counts always describe every matching policy, even with -NonCompliantOnly.
        $emptyCount = @($rows | Where-Object { $_.SettingCount -le 0 }).Count
        $unassignedCount = @($rows | Where-Object { $_.Assignments -eq 0 }).Count
        $totalSettings = 0
        $totalConflicts = 0
        $totalErrors = 0
        foreach ($row in $rows) {
            $totalSettings += $row.SettingCount
            $totalConflicts += $row.ConflictDevices
            $totalErrors += $row.ErrorDevices
        }

        Write-Host ''
        Write-Host '=== Settings catalog policy status ===' -ForegroundColor Cyan
        Write-Host "  Policies matched           : $($rows.Count)" -ForegroundColor White
        Write-Host "  Policies with zero settings: $emptyCount" -ForegroundColor Yellow
        Write-Host "  Policies assigned to nobody: $unassignedCount" -ForegroundColor Yellow
        Write-Host "  Settings configured        : $totalSettings" -ForegroundColor White
        Write-Host "  Devices in conflict        : $totalConflicts" -ForegroundColor Yellow
        Write-Host "  Devices in error           : $totalErrors" -ForegroundColor Yellow

        $reportRows = $rows
        if ($NonCompliantOnly) {
            $reportRows = @($rows | Where-Object { $_.Findings })
            Write-Host "[*] -NonCompliantOnly selects $($reportRows.Count) of $($rows.Count) policies" `
                -ForegroundColor Cyan
        }

        foreach ($row in $reportRows) {
            $colour = 'Green'
            if ($row.Findings) { $colour = 'Yellow' }
            $line = '  ' + $row.PolicyName + ' [' + $row.Platforms + '] settings=' +
                $row.SettingCount + ' assignments=' + $row.Assignments
            Write-Host $line -ForegroundColor $colour
        }

        if ($OutputFormat -ne 'Table') {
            $payload = [pscustomobject]@{
                Generated = (Get-Date).ToString('s')
                Summary   = [pscustomobject]@{
                    Matched         = $rows.Count
                    ZeroSettings    = $emptyCount
                    Unassigned      = $unassignedCount
                    Settings        = $totalSettings
                    ConflictDevices = $totalConflicts
                    ErrorDevices    = $totalErrors
                }
                Policies  = $reportRows
            }

            if ($OutputFormat -eq 'Json') {
                $rendered = $payload | ConvertTo-Json -Depth 5
            }
            else {
                $rendered = $reportRows | ConvertTo-Csv -NoTypeInformation
            }

            if ($OutputPath) {
                if ($OutputFormat -eq 'Json') {
                    Set-Content -LiteralPath $OutputPath -Value $rendered -ErrorAction Stop
                }
                else {
                    $reportRows | Export-Csv -Path $OutputPath -NoTypeInformation -ErrorAction Stop
                }
                Write-Host "[+] Report written to $OutputPath" -ForegroundColor Green
            }
            else {
                Write-Host ($rendered | Out-String) -ForegroundColor Gray
            }
        }

        $findings = @($rows | Where-Object { $_.Findings })
        if ($findings.Count -gt 0) {
            Write-Host "[!] $($findings.Count) policy(ies) need attention" -ForegroundColor Yellow
            foreach ($row in $findings) {
                Write-Host "    $($row.PolicyName): $($row.Findings)" -ForegroundColor Yellow
            }
            return 2
        }

        Write-Host '[+] All settings catalog policies are clean' -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
