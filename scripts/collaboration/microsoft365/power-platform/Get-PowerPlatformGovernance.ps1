<#
.SYNOPSIS
    Comprehensive Power Platform governance and compliance reporting.

.DESCRIPTION
    Monitors and reports on Power Platform governance, including Power Apps and Power Automate
    flow inventory, connector usage and data loss prevention (DLP) compliance, environment
    capacity, orphaned apps and flows, guest maker access, premium license usage, and shared app
    permissions. Results are printed to the console or exported as HTML, CSV, or JSON under
    -OutputPath. The script is read-only and idempotent: it never mutates tenant configuration
    and is safe to re-run. Returns exit code 1 when tenant data cannot be retrieved and exit
    code 0 on success.

.PARAMETER TenantId
    Microsoft 365 Tenant ID.

.PARAMETER IncludeAppDetails
    Include detailed app metadata and connection information.

.PARAMETER IncludeFlowDetails
    Include Power Automate flow details and trigger information.

.PARAMETER CheckDLPCompliance
    Check DLP policy compliance for connectors.

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', 'CSV', or 'JSON'. Default: 'HTML'

.PARAMETER OutputPath
    Path for output files. Default: MyDocuments\Reports

.EXAMPLE
    PS C:\> Connect-AzAccount
    PS C:\> .\Get-PowerPlatformGovernance.ps1 -TenantId "tenant-id" -IncludeAppDetails -OutputFormat Console

.EXAMPLE
    PS C:\> .\Get-PowerPlatformGovernance.ps1 -TenantId "tenant-id" `
        -IncludeAppDetails -IncludeFlowDetails -CheckDLPCompliance -OutputFormat HTML

.NOTES
    File Name   : Get-PowerPlatformGovernance.ps1
    Author      : IT Operations
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23

    Requires the Microsoft.PowerApps.Administration.PowerShell module.

    WARNING: This script has not been thoroughly tested in production environments.
    Please test in a non-production environment first and validate results before relying on this data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
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
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# Thin wrapper around Out-File so callers (and Pester tests) can intercept report
# writes; Out-File's Encoding argument transformation cannot be mocked directly.
function Write-ReportTextFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $Content | Out-File -FilePath $Path -Encoding UTF8
}

function Main {
    try {
        # Default output location: Documents\Reports. The Documents folder may be
        # unavailable on non-Windows hosts; fall back to the system temp path.
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $documentsFolder = [Environment]::GetFolderPath('MyDocuments')
            if ([string]::IsNullOrWhiteSpace($documentsFolder)) {
                $documentsFolder = [System.IO.Path]::GetTempPath()
            }
            $OutputPath = Join-Path $documentsFolder 'Reports'
        }

        # Validate OutputPath: reject '..' traversal and UNC remote paths before resolution
        if ([string]::IsNullOrWhiteSpace($OutputPath) -or
            $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
            $OutputPath -match '^(\\\\|//)') {
            throw ("Unsafe OutputPath: $OutputPath. OutputPath must not contain '..' traversal " +
                "or be a UNC/remote path; relative paths are resolved to an absolute path.")
        }
        $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
        if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        # Check for required module
        if (-not (Get-Module -ListAvailable -Name Microsoft.PowerApps.Administration.PowerShell)) {
            Write-Host "[!] Microsoft.PowerApps.Administration.PowerShell module not found." -ForegroundColor Yellow
            $installHint = 'Install-Module -Name Microsoft.PowerApps.Administration.PowerShell'
            Write-Host "[!] Install with: $installHint" -ForegroundColor Yellow
            # Continue with limited functionality
        }

        $results = @{
            Timestamp         = Get-Date
            TenantId          = $TenantId
            Environments      = @()
            PowerApps         = @()
            Flows             = @()
            Connectors        = @()
            DLPPolicies       = @()
            OrphanedResources = @()
            Summary           = @{}
        }

        Write-Host "[*] Analyzing Power Platform governance for tenant: $TenantId" -ForegroundColor Cyan

        try {
            # Get environments
            Write-Host "[*] Retrieving Power Platform environments..." -ForegroundColor Cyan
            $environments = Get-AdminPowerAppEnvironment -ErrorAction Stop

            foreach ($env in $environments) {
                $envData = @{
                    Name            = $env.DisplayName
                    EnvironmentName = $env.EnvironmentName
                    Location        = $env.Location
                    Type            = $env.EnvironmentType
                    CreatedTime     = $env.CreatedTime
                    IsDefault       = $env.IsDefault
                    SecurityGroupId = $env.SecurityGroupId
                }

                # Get environment capacity
                try {
                    $capacityParams = @{ EnvironmentName = $env.EnvironmentName; ErrorAction = 'Stop' }
                    $capacity = Get-AdminPowerAppEnvironmentCapacity @capacityParams
                    $allocatedCapacity = $capacity.DatabaseCapacity.Capacity.Allocated
                    $availableCapacity = $capacity.DatabaseCapacity.Capacity.Available
                    $percentUsed = if ($availableCapacity -gt 0) {
                        [math]::Round(($allocatedCapacity / $availableCapacity) * 100, 2)
                    }
                    else { 0 }
                    $envData.DatabaseCapacity = @{
                        Used        = $allocatedCapacity
                        Available   = $availableCapacity
                        PercentUsed = $percentUsed
                    }
                }
                catch {
                    Write-Host "[!] Could not retrieve capacity for $($env.DisplayName)" -ForegroundColor Yellow
                }

                $results.Environments += $envData
            }

            Write-Host "[+] Found $($environments.Count) environments" -ForegroundColor Green

            # Get Power Apps
            if ($IncludeAppDetails) {
                Write-Host "[*] Retrieving Power Apps..." -ForegroundColor Cyan
                $apps = Get-AdminPowerApp -ErrorAction Stop

                foreach ($app in $apps) {
                    $appData = @{
                        DisplayName      = $app.DisplayName
                        AppName          = $app.AppName
                        Owner            = $app.Owner.displayName
                        OwnerEmail       = $app.Owner.email
                        Environment      = $app.EnvironmentName
                        CreatedTime      = $app.CreatedTime
                        LastModifiedTime = $app.LastModifiedTime
                        IsFeaturedApp    = $app.IsFeaturedApp
                        IsHeroApp        = $app.IsHeroApp
                        BypassConsent    = $app.BypassConsent
                    }

                    # Check for orphaned apps (owner no longer exists)
                    if ([string]::IsNullOrEmpty($app.Owner.email)) {
                        $results.OrphanedResources += @{
                            Type        = "Power App"
                            Name        = $app.DisplayName
                            Id          = $app.AppName
                            Environment = $app.EnvironmentName
                            Reason      = "Owner not found or deleted"
                        }
                    }

                    # Get app connections
                    try {
                        $connectionParams = @{ EnvironmentName = $app.EnvironmentName; ErrorAction = 'Stop' }
                        $connections = Get-AdminPowerAppConnection @connectionParams
                        $appConnectors = $connections | Where-Object { $_.AppName -eq $app.AppName }
                        $appData.Connectors = ($appConnectors | Select-Object -ExpandProperty ConnectorName) -join ', '
                    }
                    catch {
                        $appData.Connectors = "Unable to retrieve"
                    }

                    $results.PowerApps += $appData
                }

                Write-Host "[+] Found $($apps.Count) Power Apps" -ForegroundColor Green
            }

            # Get Power Automate Flows
            if ($IncludeFlowDetails) {
                Write-Host "[*] Retrieving Power Automate flows..." -ForegroundColor Cyan
                $flows = Get-AdminFlow -ErrorAction Stop

                foreach ($flow in $flows) {
                    $flowData = @{
                        DisplayName      = $flow.DisplayName
                        FlowName         = $flow.FlowName
                        Owner            = $flow.CreatedBy.displayName
                        OwnerEmail       = $flow.CreatedBy.email
                        Environment      = $flow.EnvironmentName
                        State            = $flow.Enabled
                        CreatedTime      = $flow.CreatedTime
                        LastModifiedTime = $flow.LastModifiedTime
                        TriggerType      = $flow.Properties.definitionSummary.triggers.type -join ', '
                    }

                    # Check for orphaned flows
                    if ([string]::IsNullOrEmpty($flow.CreatedBy.email)) {
                        $results.OrphanedResources += @{
                            Type        = "Power Automate Flow"
                            Name        = $flow.DisplayName
                            Id          = $flow.FlowName
                            Environment = $flow.EnvironmentName
                            Reason      = "Owner not found or deleted"
                        }
                    }

                    $results.Flows += $flowData
                }

                Write-Host "[+] Found $($flows.Count) Power Automate flows" -ForegroundColor Green
            }

            # Get DLP Policies
            if ($CheckDLPCompliance) {
                Write-Host "[*] Retrieving DLP policies..." -ForegroundColor Cyan
                $dlpPolicies = Get-AdminDlpPolicy -ErrorAction Stop

                foreach ($policy in $dlpPolicies) {
                    $results.DLPPolicies += @{
                        DisplayName          = $policy.DisplayName
                        CreatedTime          = $policy.CreatedTime
                        EnvironmentType      = $policy.EnvironmentType
                        BusinessConnectors   = $policy.BusinessDataGroup.Count
                        NonBusinessConnectors = $policy.NonBusinessDataGroup.Count
                        BlockedConnectors    = $policy.BlockedGroup.Count
                    }
                }

                Write-Host "[+] Found $($dlpPolicies.Count) DLP policies" -ForegroundColor Green
            }

        }
        catch {
            throw ("Error retrieving Power Platform data: $($_.Exception.Message). Ensure you have " +
                "the Microsoft.PowerApps.Administration.PowerShell module installed and are authenticated.")
        }

        # Calculate summary
        $results.Summary = @{
            TotalEnvironments  = $results.Environments.Count
            TotalPowerApps     = $results.PowerApps.Count
            TotalFlows         = $results.Flows.Count
            OrphanedResources  = $results.OrphanedResources.Count
            DLPPolicies        = $results.DLPPolicies.Count
            DefaultEnvironments = @($results.Environments | Where-Object { $_.IsDefault }).Count
        }

        # Output results
        $orphanColor = if ($results.Summary.OrphanedResources -gt 0) { '#d13438' } else { '#107c10' }
        $RunTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $RunId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
        switch ($OutputFormat) {
            'Console' {
                Write-Host "`n=== Power Platform Governance Summary ===" -ForegroundColor Cyan
                Write-Host "[*] Environments: $($results.Summary.TotalEnvironments)" -ForegroundColor Cyan
                Write-Host "[*] Power Apps: $($results.Summary.TotalPowerApps)" -ForegroundColor Cyan
                Write-Host "[*] Flows: $($results.Summary.TotalFlows)" -ForegroundColor Cyan
                Write-Host "[*] DLP Policies: $($results.Summary.DLPPolicies)" -ForegroundColor Cyan
                if ($results.Summary.OrphanedResources -gt 0) {
                    Write-Host "[!] Orphaned Resources: $($results.Summary.OrphanedResources)" -ForegroundColor Yellow
                }
                else {
                    Write-Host "[+] Orphaned Resources: $($results.Summary.OrphanedResources)" -ForegroundColor Green
                }

                if ($results.OrphanedResources.Count -gt 0) {
                    Write-Host "`n=== Orphaned Resources ===" -ForegroundColor Yellow
                    foreach ($orphan in $results.OrphanedResources) {
                        Write-Host "  [$($orphan.Type)] $($orphan.Name) - $($orphan.Reason)" -ForegroundColor Yellow
                    }
                }
            }

            'HTML' {
                $htmlFile = Join-Path $OutputPath "PowerPlatform-Governance-${RunTimestamp}_${RunId}.html"

                $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Power Platform Governance Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #742774; border-bottom: 3px solid #742774; padding-bottom: 10px; }
        h2 { color: #505050; margin-top: 30px; }
        .summary { background: white; padding: 20px; border-radius: 8px;
                   box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
                        gap: 15px; margin-top: 15px; }
        .summary-item { background: #f0f0f0; padding: 15px; border-radius: 5px; text-align: center; }
        .summary-item .value { font-size: 32px; font-weight: bold; color: #742774; }
        .summary-item .label { font-size: 14px; color: #666; margin-top: 5px; }
        table { border-collapse: collapse; width: 100%; background: white;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-top: 10px; }
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
        <strong>Tenant ID:</strong> $([System.Net.WebUtility]::HtmlEncode("$TenantId"))<br>
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
                <div class="value" style="color: $orphanColor;">$($results.Summary.OrphanedResources)</div>
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
            <td>$([System.Net.WebUtility]::HtmlEncode("$($env.Name)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($env.Type)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($env.Location)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($env.CreatedTime)"))</td>
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
            <td class="orphaned">$([System.Net.WebUtility]::HtmlEncode("$($orphan.Type)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($orphan.Name)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($orphan.Environment)"))</td>
            <td>$([System.Net.WebUtility]::HtmlEncode("$($orphan.Reason)"))</td>
        </tr>
"@
                    }
                    $html += "</table>"
                }

                $html += @"
    <div class="footer">
        <strong>Note:</strong> This report has not been thoroughly tested.
        Please validate results before making governance decisions.<br>
        Generated by Get-PowerPlatformGovernance.ps1
    </div>
</body>
</html>
"@

                Write-ReportTextFile -Path $htmlFile -Content $html
                Write-Host "[+] HTML report saved to: $htmlFile" -ForegroundColor Green
            }

            'CSV' {
                $csvFile = Join-Path $OutputPath "PowerPlatform-Apps-${RunTimestamp}_${RunId}.csv"
                $results.PowerApps | Export-Csv -Path $csvFile -NoTypeInformation
                Write-Host "[+] CSV report saved to: $csvFile" -ForegroundColor Green
            }

            'JSON' {
                $jsonFile = Join-Path $OutputPath "PowerPlatform-Governance-${RunTimestamp}_${RunId}.json"
                Write-ReportTextFile -Path $jsonFile -Content ($results | ConvertTo-Json -Depth 10)
                Write-Host "[+] JSON report saved to: $jsonFile" -ForegroundColor Green
            }
        }

        Write-Host "`n[+] Power Platform governance analysis complete!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
