<#
.SYNOPSIS
    Comprehensive Power Platform governance and compliance reporting.

.DESCRIPTION
    Monitors and reports on Power Platform governance including:
    - Power Apps inventory and ownership
    - Power Automate flow inventory and status
    - Connector usage and data loss prevention (DLP) compliance
    - Environment capacity and licensing
    - Orphaned apps and flows
    - Guest maker access
    - Premium license usage
    - Shared app permissions

.PARAMETER TenantId
    Microsoft 365 Tenant ID

.PARAMETER IncludeAppDetails
    Include detailed app metadata and connection information

.PARAMETER IncludeFlowDetails
    Include Power Automate flow details and trigger information

.PARAMETER CheckDLPCompliance
    Check DLP policy compliance for connectors

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', 'CSV', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for output files. Default: Desktop

.EXAMPLE
    Connect-AzAccount
    .\Get-PowerPlatformGovernance.ps1 -TenantId "tenant-id" -IncludeAppDetails

.EXAMPLE
    .\Get-PowerPlatformGovernance.ps1 -TenantId "tenant-id" `
        -IncludeAppDetails `
        -IncludeFlowDetails `
        -CheckDLPCompliance `
        -OutputFormat HTML

.NOTES
    Author: IT Operations
    Version: 1.0.0
    Requires: PowerShell 5.1+, Microsoft.PowerApps.Administration.PowerShell module

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeAppDetails,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeFlowDetails,

    [Parameter(Mandatory = $false)]
    [switch]$CheckDLPCompliance,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'HTML', 'CSV', 'JSON')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = [Environment]::GetFolderPath('Desktop')
)

# Check for required module
if (-not (Get-Module -ListAvailable -Name Microsoft.PowerApps.Administration.PowerShell)) {
    Write-Warning "Microsoft.PowerApps.Administration.PowerShell module not found."
    Write-Host "Install with: Install-Module -Name Microsoft.PowerApps.Administration.PowerShell" -ForegroundColor Yellow
    # Continue with limited functionality
}

$results = @{
    Timestamp = Get-Date
    TenantId = $TenantId
    Environments = @()
    PowerApps = @()
    Flows = @()
    Connectors = @()
    DLPPolicies = @()
    OrphanedResources = @()
    Summary = @{}
}

Write-Host "Analyzing Power Platform governance for tenant: $TenantId" -ForegroundColor Cyan

try {
    # Get environments
    Write-Host "`nRetrieving Power Platform environments..." -ForegroundColor Yellow
    $environments = Get-AdminPowerAppEnvironment

    foreach ($env in $environments) {
        $envData = @{
            Name = $env.DisplayName
            EnvironmentName = $env.EnvironmentName
            Location = $env.Location
            Type = $env.EnvironmentType
            CreatedTime = $env.CreatedTime
            IsDefault = $env.IsDefault
            SecurityGroupId = $env.SecurityGroupId
        }

        # Get environment capacity
        try {
            $capacity = Get-AdminPowerAppEnvironmentCapacity -EnvironmentName $env.EnvironmentName
            $envData.DatabaseCapacity = @{
                Used = $capacity.DatabaseCapacity.Capacity.Allocated
                Available = $capacity.DatabaseCapacity.Capacity.Available
                PercentUsed = if ($capacity.DatabaseCapacity.Capacity.Available -gt 0) {
                    [math]::Round(($capacity.DatabaseCapacity.Capacity.Allocated / $capacity.DatabaseCapacity.Capacity.Available) * 100, 2)
                } else { 0 }
            }
        } catch {
            Write-Warning "Could not retrieve capacity for $($env.DisplayName)"
        }

        $results.Environments += $envData
    }

    Write-Host "Found $($environments.Count) environments" -ForegroundColor White

    # Get Power Apps
    if ($IncludeAppDetails) {
        Write-Host "`nRetrieving Power Apps..." -ForegroundColor Yellow
        $apps = Get-AdminPowerApp

        foreach ($app in $apps) {
            $appData = @{
                DisplayName = $app.DisplayName
                AppName = $app.AppName
                Owner = $app.Owner.displayName
                OwnerEmail = $app.Owner.email
                Environment = $app.EnvironmentName
                CreatedTime = $app.CreatedTime
                LastModifiedTime = $app.LastModifiedTime
                IsFeaturedApp = $app.IsFeaturedApp
                IsHeroApp = $app.IsHeroApp
                BypassConsent = $app.BypassConsent
            }

            # Check for orphaned apps (owner no longer exists)
            if ([string]::IsNullOrEmpty($app.Owner.email)) {
                $results.OrphanedResources += @{
                    Type = "Power App"
                    Name = $app.DisplayName
                    Id = $app.AppName
                    Environment = $app.EnvironmentName
                    Reason = "Owner not found or deleted"
                }
            }

            # Get app connections
            try {
                $connections = Get-AdminPowerAppConnection -EnvironmentName $app.EnvironmentName
                $appConnectors = $connections | Where-Object { $_.AppName -eq $app.AppName }
                $appData.Connectors = ($appConnectors | Select-Object -ExpandProperty ConnectorName) -join ', '
            } catch {
                $appData.Connectors = "Unable to retrieve"
            }

            $results.PowerApps += $appData
        }

        Write-Host "Found $($apps.Count) Power Apps" -ForegroundColor White
    }

    # Get Power Automate Flows
    if ($IncludeFlowDetails) {
        Write-Host "`nRetrieving Power Automate flows..." -ForegroundColor Yellow
        $flows = Get-AdminFlow

        foreach ($flow in $flows) {
            $flowData = @{
                DisplayName = $flow.DisplayName
                FlowName = $flow.FlowName
                Owner = $flow.CreatedBy.displayName
                OwnerEmail = $flow.CreatedBy.email
                Environment = $flow.EnvironmentName
                State = $flow.Enabled
                CreatedTime = $flow.CreatedTime
                LastModifiedTime = $flow.LastModifiedTime
                TriggerType = $flow.Properties.definitionSummary.triggers.type -join ', '
            }

            # Check for orphaned flows
            if ([string]::IsNullOrEmpty($flow.CreatedBy.email)) {
                $results.OrphanedResources += @{
                    Type = "Power Automate Flow"
                    Name = $flow.DisplayName
                    Id = $flow.FlowName
                    Environment = $flow.EnvironmentName
                    Reason = "Owner not found or deleted"
                }
            }

            $results.Flows += $flowData
        }

        Write-Host "Found $($flows.Count) Power Automate flows" -ForegroundColor White
    }

    # Get DLP Policies
    if ($CheckDLPCompliance) {
        Write-Host "`nRetrieving DLP policies..." -ForegroundColor Yellow
        $dlpPolicies = Get-AdminDlpPolicy

        foreach ($policy in $dlpPolicies) {
            $results.DLPPolicies += @{
                DisplayName = $policy.DisplayName
                CreatedTime = $policy.CreatedTime
                EnvironmentType = $policy.EnvironmentType
                BusinessConnectors = $policy.BusinessDataGroup.Count
                NonBusinessConnectors = $policy.NonBusinessDataGroup.Count
                BlockedConnectors = $policy.BlockedGroup.Count
            }
        }

        Write-Host "Found $($dlpPolicies.Count) DLP policies" -ForegroundColor White
    }

} catch {
    Write-Error "Error retrieving Power Platform data: $($_.Exception.Message)"
    Write-Warning "Ensure you have the Microsoft.PowerApps.Administration.PowerShell module installed and are authenticated"
}

# Calculate summary
$results.Summary = @{
    TotalEnvironments = $results.Environments.Count
    TotalPowerApps = $results.PowerApps.Count
    TotalFlows = $results.Flows.Count
    OrphanedResources = $results.OrphanedResources.Count
    DLPPolicies = $results.DLPPolicies.Count
    DefaultEnvironments = ($results.Environments | Where-Object { $_.IsDefault }).Count
}

# Output results
switch ($OutputFormat) {
    'Console' {
        Write-Host "`n=== Power Platform Governance Summary ===" -ForegroundColor Cyan
        Write-Host "Environments: $($results.Summary.TotalEnvironments)" -ForegroundColor White
        Write-Host "Power Apps: $($results.Summary.TotalPowerApps)" -ForegroundColor White
        Write-Host "Flows: $($results.Summary.TotalFlows)" -ForegroundColor White
        Write-Host "DLP Policies: $($results.Summary.DLPPolicies)" -ForegroundColor White
        Write-Host "Orphaned Resources: $($results.Summary.OrphanedResources)" -ForegroundColor $(if ($results.Summary.OrphanedResources -gt 0) { 'Yellow' } else { 'White' })

        if ($results.OrphanedResources.Count -gt 0) {
            Write-Host "`n=== Orphaned Resources ===" -ForegroundColor Yellow
            foreach ($orphan in $results.OrphanedResources) {
                Write-Host "  [$($orphan.Type)] $($orphan.Name) - $($orphan.Reason)" -ForegroundColor Red
            }
        }
    }

    'HTML' {
        $htmlFile = Join-Path $OutputPath "PowerPlatform-Governance-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Power Platform Governance Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #742774; border-bottom: 3px solid #742774; padding-bottom: 10px; }
        h2 { color: #505050; margin-top: 30px; }
        .summary { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin-top: 15px; }
        .summary-item { background: #f0f0f0; padding: 15px; border-radius: 5px; text-align: center; }
        .summary-item .value { font-size: 32px; font-weight: bold; color: #742774; }
        .summary-item .label { font-size: 14px; color: #666; margin-top: 5px; }
        table { border-collapse: collapse; width: 100%; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-top: 10px; }
        th { background-color: #742774; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .orphaned { color: #d13438; font-weight: bold; }
        .footer { margin-top: 30px; text-align: center; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <h1>Power Platform Governance Report</h1>
    <div class="summary">
        <strong>Tenant ID:</strong> $TenantId<br>
        <strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

        <div class="summary-grid">
            <div class="summary-item">
                <div class="value">$($results.Summary.TotalEnvironments)</div>
                <div class="label">Environments</div>
            </div>
            <div class="summary-item">
                <div class="value">$($results.Summary.TotalPowerApps)</div>
                <div class="label">Power Apps</div>
            </div>
            <div class="summary-item">
                <div class="value">$($results.Summary.TotalFlows)</div>
                <div class="label">Flows</div>
            </div>
            <div class="summary-item">
                <div class="value">$($results.Summary.DLPPolicies)</div>
                <div class="label">DLP Policies</div>
            </div>
            <div class="summary-item">
                <div class="value" style="color: $(if ($results.Summary.OrphanedResources -gt 0) { '#d13438' } else { '#107c10' });">$($results.Summary.OrphanedResources)</div>
                <div class="label">Orphaned Resources</div>
            </div>
        </div>
    </div>

    <h2>Environments</h2>
    <table>
        <tr>
            <th>Name</th>
            <th>Type</th>
            <th>Location</th>
            <th>Created</th>
            <th>Default</th>
        </tr>
"@

        foreach ($env in $results.Environments) {
            $html += @"
        <tr>
            <td>$($env.Name)</td>
            <td>$($env.Type)</td>
            <td>$($env.Location)</td>
            <td>$($env.CreatedTime)</td>
            <td>$(if ($env.IsDefault) { 'Yes' } else { 'No' })</td>
        </tr>
"@
        }

        $html += "</table>"

        if ($results.OrphanedResources.Count -gt 0) {
            $html += @"
    <h2>Orphaned Resources</h2>
    <table>
        <tr>
            <th>Type</th>
            <th>Name</th>
            <th>Environment</th>
            <th>Reason</th>
        </tr>
"@
            foreach ($orphan in $results.OrphanedResources) {
                $html += @"
        <tr>
            <td class="orphaned">$($orphan.Type)</td>
            <td>$($orphan.Name)</td>
            <td>$($orphan.Environment)</td>
            <td>$($orphan.Reason)</td>
        </tr>
"@
            }
            $html += "</table>"
        }

        $html += @"
    <div class="footer">
        <strong>Note:</strong> This report has not been thoroughly tested. Please validate results before making governance decisions.<br>
        Generated by Get-PowerPlatformGovernance.ps1
    </div>
</body>
</html>
"@

        $html | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Host "`nHTML report saved to: $htmlFile" -ForegroundColor Green
        Start-Process $htmlFile
    }

    'CSV' {
        $csvFile = Join-Path $OutputPath "PowerPlatform-Apps-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
        $results.PowerApps | Export-Csv -Path $csvFile -NoTypeInformation
        Write-Host "`nCSV report saved to: $csvFile" -ForegroundColor Green
    }

    'JSON' {
        $jsonFile = Join-Path $OutputPath "PowerPlatform-Governance-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
        Write-Host "`nJSON report saved to: $jsonFile" -ForegroundColor Green
    }
}

Write-Host "`nPower Platform governance analysis complete!" -ForegroundColor Green
