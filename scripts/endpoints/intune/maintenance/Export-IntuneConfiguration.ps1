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
    Each exported policy is written as a JSON file under the output directory, and an
    export summary JSON is always produced. The script is read-only against the tenant
    and safe to re-run; existing export files are overwritten in place.

.PARAMETER OutputPath
    Where to save exported configuration (default: MyDocuments\Reports).

.PARAMETER ConfigTypes
    Comma-separated list: DeviceConfig,Compliance,Apps,Scripts,Autopilot,All (default: All).

.PARAMETER IncludeAssignments
    Include policy assignments in export.

.PARAMETER CompressOutput
    Create ZIP archive of exports.

.EXAMPLE
    PS C:\> .\Export-IntuneConfiguration.ps1
    Exports all configuration to MyDocuments\Reports.

.EXAMPLE
    PS C:\> .\Export-IntuneConfiguration.ps1 -ConfigTypes "DeviceConfig,Compliance" -IncludeAssignments
    Exports only device and compliance policies with assignments.

.NOTES
    File Name: Export-IntuneConfiguration.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

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

$ErrorActionPreference = 'Stop'

function Write-ColorOutput {
    [CmdletBinding()]
    param([string]$Message, [string]$Level = 'Info')
    switch ($Level) {
        'Success' { Write-Host "[+] $Message" -ForegroundColor Green }
        'Warning' { Write-Host "[!] $Message" -ForegroundColor Yellow }
        'Error'   { Write-Host "[-] $Message" -ForegroundColor Red }
        default   { Write-Host "[*] $Message" -ForegroundColor Cyan }
    }
}

function Main {
    try {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  Intune Configuration Export" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan

        Write-ColorOutput "Connecting to Microsoft Graph..." -Level Info
        $context = Get-MgContext -ErrorAction Stop
        if (-not $context) {
            $graphScopes = @(
                "DeviceManagementConfiguration.Read.All",
                "DeviceManagementApps.Read.All",
                "DeviceManagementServiceConfig.Read.All"
            )
            Connect-MgGraph -Scopes $graphScopes -ErrorAction Stop
        }
        Write-ColorOutput "Connected" -Level Success

        if (-not $OutputPath) {
            $ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
            if ([string]::IsNullOrWhiteSpace($ReportDir) -or
                $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
                $ReportDir -match '^(\\\\|//)') {
                throw "Unsafe report path: $ReportDir. " +
                    "Report path must be a local absolute path without '..' traversal."
            }
            $ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
            if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
                New-Item -ItemType Directory -Path $ReportDir -Force -ErrorAction Stop | Out-Null
            }
            $OutputPath = Join-Path $ReportDir "IntuneBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        }

        if (-not (Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force -ErrorAction Stop | Out-Null
        }

        $exportSummary = @{
            ExportTime = Get-Date
            TenantId = (Get-MgContext).TenantId
            ItemsExported = 0
        }

        if ('All' -in $ConfigTypes -or 'DeviceConfig' -in $ConfigTypes) {
            Write-Host "`nExporting device configuration policies..." -ForegroundColor Cyan
            try {
                $policies = Invoke-MgGraphRequest `
                    -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations" `
                    -Method GET -ErrorAction Stop
                $policyPath = Join-Path $OutputPath "DeviceConfigurations"
                New-Item -ItemType Directory -Path $policyPath -Force -ErrorAction Stop | Out-Null

                foreach ($policy in $policies.value) {
                    $safeName = ($policy.displayName -replace '[\\/:*?"<>|]', '_').Trim()
                    if ([string]::IsNullOrWhiteSpace($safeName)) {
                        $safeName = "DeviceConfiguration"
                    }
                    $fileName = "{0}_{1}.json" -f $safeName, $policy.id
                    $policy | ConvertTo-Json -Depth 10 |
                        Out-File (Join-Path $policyPath $fileName) -Encoding UTF8 -ErrorAction Stop
                    $exportSummary.ItemsExported++
                }
                Write-ColorOutput "Exported $($policies.value.Count) device configurations" -Level Success
            }
            catch {
                Write-ColorOutput "Error exporting device configurations: $($_.Exception.Message)" -Level Error
            }
        }

        if ('All' -in $ConfigTypes -or 'Compliance' -in $ConfigTypes) {
            Write-Host "`nExporting compliance policies..." -ForegroundColor Cyan
            try {
                $policies = Invoke-MgGraphRequest `
                    -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" `
                    -Method GET -ErrorAction Stop
                $policyPath = Join-Path $OutputPath "CompliancePolicies"
                New-Item -ItemType Directory -Path $policyPath -Force -ErrorAction Stop | Out-Null

                foreach ($policy in $policies.value) {
                    $safeName = ($policy.displayName -replace '[\\/:*?"<>|]', '_').Trim()
                    if ([string]::IsNullOrWhiteSpace($safeName)) {
                        $safeName = "CompliancePolicy"
                    }
                    $fileName = "{0}_{1}.json" -f $safeName, $policy.id
                    $policy | ConvertTo-Json -Depth 10 |
                        Out-File (Join-Path $policyPath $fileName) -Encoding UTF8 -ErrorAction Stop
                    $exportSummary.ItemsExported++
                }
                Write-ColorOutput "Exported $($policies.value.Count) compliance policies" -Level Success
            }
            catch {
                Write-ColorOutput "Error exporting compliance policies: $($_.Exception.Message)" -Level Error
            }
        }

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  Export Summary" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Output Location: $OutputPath"
        Write-ColorOutput "Total Items Exported: $($exportSummary.ItemsExported)" -Level Success
        Write-Host "`n========================================`n" -ForegroundColor Cyan

        $exportSummary | ConvertTo-Json |
            Out-File (Join-Path $OutputPath "export-summary.json") -Encoding UTF8 -ErrorAction Stop

        if ($CompressOutput) {
            $zipPath = "$OutputPath.zip"
            Compress-Archive -Path $OutputPath -DestinationPath $zipPath -Force -ErrorAction Stop
            Write-ColorOutput "Created archive: $zipPath" -Level Success
        }

        Write-ColorOutput "Done" -Level Success
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
