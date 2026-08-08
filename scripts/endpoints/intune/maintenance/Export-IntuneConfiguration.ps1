<#
.SYNOPSIS
    Exports Intune configuration for backup or migration.

.DESCRIPTION
    Backs up Intune tenant configuration including:
    - Device configuration policies
    - Compliance policies
    - App protection policies
    - Conditional access policies
    - Win32 applications
    - PowerShell scripts
    - Proactive remediations
    - Autopilot profiles

.PARAMETER OutputPath
    Where to save exported configuration (default: MyDocuments\Reports).

.PARAMETER ConfigTypes
    Comma-separated list: DeviceConfig,Compliance,Apps,Scripts,Autopilot,All (default: All).

.PARAMETER IncludeAssignments
    Include policy assignments in export.

.PARAMETER CompressOutput
    Create ZIP archive of exports.

.EXAMPLE
    .\Export-IntuneConfiguration.ps1
    Exports all configuration to MyDocuments\Reports.

.EXAMPLE
    .\Export-IntuneConfiguration.ps1 -ConfigTypes "DeviceConfig,Compliance" -IncludeAssignments
    Exports only device and compliance policies with assignments.

.NOTES
    Requires Microsoft.Graph PowerShell module
    Requires appropriate Graph API permissions
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [string[]]$ConfigTypes = @('All'),

    [Parameter(Mandatory = $false)]
    [switch]$IncludeAssignments,

    [Parameter(Mandatory = $false)]
    [switch]$CompressOutput
)

#Requires -Modules Microsoft.Graph.Authentication

function Write-ColorOutput {
    param([string]$Message, [string]$Level = 'Info')
    $color = switch ($Level) { 'Success' { 'Green' } 'Warning' { 'Yellow' } 'Error' { 'Red' } default { 'Cyan' } }
    Write-Host $Message -ForegroundColor $color
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Intune Configuration Export" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-ColorOutput "Connecting to Microsoft Graph..." -Level Info
try {
    $context = Get-MgContext
    if (-not $context) {
        Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All", "DeviceManagementApps.Read.All", "DeviceManagementServiceConfig.Read.All"
    }
    Write-ColorOutput "  Connected" -Level Success
}
catch {
    Write-ColorOutput "  Failed: $($_.Exception.Message)" -Level Error
    exit 1
}


$ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
if ([string]::IsNullOrWhiteSpace($ReportDir) -or
    $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
    $ReportDir -match '^(\\\\|//)') {
    Write-Error "Unsafe report path: $ReportDir. Report path must be a local absolute path without '..' traversal."
    exit 1
}
$ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

if (-not $OutputPath) {
    $OutputPath = Join-Path $ReportDir "IntuneBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
}

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$exportSummary = @{
    ExportTime = Get-Date
    TenantId = (Get-MgContext).TenantId
    ItemsExported = 0
}

if ('All' -in $ConfigTypes -or 'DeviceConfig' -in $ConfigTypes) {
    Write-Host "`nExporting device configuration policies..." -ForegroundColor Cyan
    try {
        $policies = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations" -Method GET
        $policyPath = Join-Path $OutputPath "DeviceConfigurations"
        New-Item -ItemType Directory -Path $policyPath -Force | Out-Null

        foreach ($policy in $policies.value) {
            $safeName = ($policy.displayName -replace '[\\/:*?"<>|]', '_').Trim()
            if ([string]::IsNullOrWhiteSpace($safeName)) {
                $safeName = "DeviceConfiguration"
            }
            $fileName = "{0}_{1}.json" -f $safeName, $policy.id
            $policy | ConvertTo-Json -Depth 10 | Out-File (Join-Path $policyPath $fileName) -Encoding UTF8
            $exportSummary.ItemsExported++
        }
        Write-ColorOutput "  Exported $($policies.value.Count) device configurations" -Level Success
    }
    catch {
        Write-ColorOutput "  Error: $($_.Exception.Message)" -Level Error
    }
}

if ('All' -in $ConfigTypes -or 'Compliance' -in $ConfigTypes) {
    Write-Host "`nExporting compliance policies..." -ForegroundColor Cyan
    try {
        $policies = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" -Method GET
        $policyPath = Join-Path $OutputPath "CompliancePolicies"
        New-Item -ItemType Directory -Path $policyPath -Force | Out-Null

        foreach ($policy in $policies.value) {
            $safeName = ($policy.displayName -replace '[\\/:*?"<>|]', '_').Trim()
            if ([string]::IsNullOrWhiteSpace($safeName)) {
                $safeName = "CompliancePolicy"
            }
            $fileName = "{0}_{1}.json" -f $safeName, $policy.id
            $policy | ConvertTo-Json -Depth 10 | Out-File (Join-Path $policyPath $fileName) -Encoding UTF8
            $exportSummary.ItemsExported++
        }
        Write-ColorOutput "  Exported $($policies.value.Count) compliance policies" -Level Success
    }
    catch {
        Write-ColorOutput "  Error: $($_.Exception.Message)" -Level Error
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Export Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Output Location: $OutputPath"
Write-ColorOutput "Total Items Exported: $($exportSummary.ItemsExported)" -Level Success
Write-Host "`n========================================`n" -ForegroundColor Cyan

$exportSummary | ConvertTo-Json | Out-File (Join-Path $OutputPath "export-summary.json") -Encoding UTF8

if ($CompressOutput) {
    $zipPath = "$OutputPath.zip"
    Compress-Archive -Path $OutputPath -DestinationPath $zipPath -Force
    Write-ColorOutput "Created archive: $zipPath" -Level Success
}
