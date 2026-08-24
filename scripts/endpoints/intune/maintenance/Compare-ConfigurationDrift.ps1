<#
.SYNOPSIS
    Detects configuration drift in Intune policies and settings.

.DESCRIPTION
    Compares current Intune configuration against a baseline snapshot to identify
    changes, additions, and deletions. Useful for change tracking, compliance
    auditing, and troubleshooting unexpected behavior.
    With -CreateBaseline it captures a new baseline JSON; otherwise it compares a
    supplied baseline against the live tenant and writes a drift report JSON.

.PARAMETER TenantId
    Azure AD Tenant ID (optional, will prompt if not provided)

.PARAMETER BaselinePath
    Path to baseline configuration file (JSON). If not provided, creates new baseline.

.PARAMETER OutputPath
    Path to save the drift report (default: current directory)

.PARAMETER CreateBaseline
    Create a new baseline snapshot instead of comparing

.EXAMPLE
    PS C:\> .\Compare-ConfigurationDrift.ps1 -CreateBaseline
    Captures a new baseline snapshot of the current Intune configuration and saves
    it as a timestamped JSON file in the current directory.

.EXAMPLE
    PS C:\> .\Compare-ConfigurationDrift.ps1 -BaselinePath ".\baseline-20240101.json"
    Compares the live tenant configuration against the specified baseline file and
    writes a timestamped drift report JSON to the current directory.

.NOTES
    File Name: Compare-ConfigurationDrift.ps1
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
    [string]$BaselinePath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false)]
    [switch]$CreateBaseline
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Get-IntuneConfigurationSnapshot {
    [CmdletBinding()]
    param()

    Write-Host "[*] Capturing Intune configuration snapshot..." -ForegroundColor Cyan

    $snapshot = @{
        CapturedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        DeviceConfigurations = @()
        CompliancePolicies = @()
        ConfigurationPolicies = @()
        Applications = @()
    }

    # Get device configurations
    Write-Host "  [*] Device configurations..." -ForegroundColor Gray
    $configs = Invoke-MgGraphRequest `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations" `
        -Method GET -ErrorAction Stop
    $snapshot.DeviceConfigurations = @($configs.value | Select-Object id, displayName,
        description, createdDateTime, lastModifiedDateTime, '@odata.type')

    # Get compliance policies
    Write-Host "  [*] Compliance policies..." -ForegroundColor Gray
    $compliance = Invoke-MgGraphRequest `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" `
        -Method GET -ErrorAction Stop
    $snapshot.CompliancePolicies = @($compliance.value | Select-Object id, displayName,
        description, createdDateTime, lastModifiedDateTime, '@odata.type')

    # Get configuration policies (Settings Catalog)
    Write-Host "  [*] Configuration policies..." -ForegroundColor Gray
    $settingsCatalog = Invoke-MgGraphRequest `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" `
        -Method GET -ErrorAction Stop
    $snapshot.ConfigurationPolicies = @($settingsCatalog.value | Select-Object id, name,
        description, createdDateTime, lastModifiedDateTime)

    # Get applications
    Write-Host "  [*] Applications..." -ForegroundColor Gray
    $apps = Invoke-MgGraphRequest `
        -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps" `
        -Method GET -ErrorAction Stop
    $snapshot.Applications = @($apps.value | Select-Object id, displayName,
        description, createdDateTime, lastModifiedDateTime, '@odata.type')

    Write-Host "[+] Snapshot captured" -ForegroundColor Green
    return $snapshot
}

function Compare-Snapshots {
    [CmdletBinding()]
    param(
        [object]$Baseline,
        [object]$Current
    )

    $driftReport = @{
        Added = @{
            DeviceConfigurations = @()
            CompliancePolicies = @()
            ConfigurationPolicies = @()
            Applications = @()
        }
        Removed = @{
            DeviceConfigurations = @()
            CompliancePolicies = @()
            ConfigurationPolicies = @()
            Applications = @()
        }
        Modified = @{
            DeviceConfigurations = @()
            CompliancePolicies = @()
            ConfigurationPolicies = @()
            Applications = @()
        }
        TotalChanges = 0
    }

    # Compare each configuration type
    $configTypes = @("DeviceConfigurations", "CompliancePolicies", "ConfigurationPolicies", "Applications")

    foreach ($type in $configTypes) {
        # Find added items
        $currentIds = @($Current.$type | ForEach-Object { $_.id })
        $baselineIds = @($Baseline.$type | ForEach-Object { $_.id })

        $addedIds = $currentIds | Where-Object { $_ -notin $baselineIds }
        foreach ($id in $addedIds) {
            $item = $Current.$type | Where-Object { $_.id -eq $id }
            $driftReport.Added.$type += $item
            $driftReport.TotalChanges++
        }

        # Find removed items
        $removedIds = $baselineIds | Where-Object { $_ -notin $currentIds }
        foreach ($id in $removedIds) {
            $item = $Baseline.$type | Where-Object { $_.id -eq $id }
            $driftReport.Removed.$type += $item
            $driftReport.TotalChanges++
        }

        # Find modified items
        $commonIds = $currentIds | Where-Object { $_ -in $baselineIds }
        foreach ($id in $commonIds) {
            $currentItem = $Current.$type | Where-Object { $_.id -eq $id }
            $baselineItem = $Baseline.$type | Where-Object { $_.id -eq $id }

            # Check if lastModifiedDateTime has changed.
            # Normalize timestamps: a JSON round-trip may deserialize ISO strings as DateTime objects.
            $currentModified = if ($currentItem.lastModifiedDateTime -is [datetime]) {
                $currentItem.lastModifiedDateTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss\Z')
            }
            else { [string]$currentItem.lastModifiedDateTime }
            $baselineModified = if ($baselineItem.lastModifiedDateTime -is [datetime]) {
                $baselineItem.lastModifiedDateTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss\Z')
            }
            else { [string]$baselineItem.lastModifiedDateTime }
            if ($currentModified -ne $baselineModified) {
                $driftReport.Modified.$type += [PSCustomObject]@{
                    id = $id
                    displayName = if ($currentItem.displayName) { $currentItem.displayName } else { $currentItem.name }
                    baselineModified = $baselineModified
                    currentModified = $currentModified
                }
                $driftReport.TotalChanges++
            }
        }
    }

    return $driftReport
}

function Main {
    try {
        Write-Host "[*] Starting Intune configuration drift analysis..." -ForegroundColor Cyan

        # Import helper module
        Import-Module (Join-Path (Join-Path $scriptDir "..") "IntuneGraphHelper.psm1") -Force -ErrorAction Stop

        Connect-IntuneGraph -TenantId $TenantId

        # Get current snapshot
        $currentSnapshot = Get-IntuneConfigurationSnapshot

        if ($CreateBaseline) {
            # Save baseline
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $baselineFile = Join-Path $OutputPath "intune-baseline-$timestamp.json"

            $currentSnapshot | ConvertTo-Json -Depth 10 |
                Out-File -FilePath $baselineFile -Encoding UTF8 -ErrorAction Stop

            Write-Host "[+] Baseline created successfully:" -ForegroundColor Green
            Write-Host "   $baselineFile" -ForegroundColor Cyan
            Write-Host "[*] Baseline Statistics:" -ForegroundColor Yellow
            Write-Host "  Device Configurations: $($currentSnapshot.DeviceConfigurations.Count)"
            Write-Host "  Compliance Policies: $($currentSnapshot.CompliancePolicies.Count)"
            Write-Host "  Configuration Policies: $($currentSnapshot.ConfigurationPolicies.Count)"
            Write-Host "  Applications: $($currentSnapshot.Applications.Count)"
        }
        else {
            # Compare against baseline
            if (-not $BaselinePath) {
                throw "Please specify -BaselinePath or use -CreateBaseline to create a new baseline"
            }

            if (-not (Test-Path $BaselinePath)) {
                throw "Baseline file not found: $BaselinePath"
            }

            Write-Host "[*] Loading baseline from: $BaselinePath" -ForegroundColor Cyan
            $baseline = Get-Content -Path $BaselinePath -Raw -ErrorAction Stop | ConvertFrom-Json

            Write-Host "[*] Comparing configurations..." -ForegroundColor Cyan
            $drift = Compare-Snapshots -Baseline $baseline -Current $currentSnapshot

            # Display results
            Write-Host "[*] Drift Detection Results" -ForegroundColor Cyan

            Write-Host "Baseline Date: $($baseline.CapturedDate)" -ForegroundColor Gray
            Write-Host "Current Date:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
            Write-Host "[!] Total Changes Detected: $($drift.TotalChanges)" -ForegroundColor Yellow

            # Show added items
            if ($drift.Added.DeviceConfigurations.Count -gt 0 -or
                $drift.Added.CompliancePolicies.Count -gt 0 -or
                $drift.Added.ConfigurationPolicies.Count -gt 0 -or
                $drift.Added.Applications.Count -gt 0) {

                Write-Host "[+] Added Items:" -ForegroundColor Green
                if ($drift.Added.DeviceConfigurations.Count -gt 0) {
                    Write-Host "  Device Configurations: $($drift.Added.DeviceConfigurations.Count)"
                    $drift.Added.DeviceConfigurations |
                        ForEach-Object { Write-Host "    - $($_.displayName)" -ForegroundColor Gray }
                }
                if ($drift.Added.CompliancePolicies.Count -gt 0) {
                    Write-Host "  Compliance Policies: $($drift.Added.CompliancePolicies.Count)"
                    $drift.Added.CompliancePolicies |
                        ForEach-Object { Write-Host "    - $($_.displayName)" -ForegroundColor Gray }
                }
                if ($drift.Added.ConfigurationPolicies.Count -gt 0) {
                    Write-Host "  Configuration Policies: $($drift.Added.ConfigurationPolicies.Count)"
                    $drift.Added.ConfigurationPolicies |
                        ForEach-Object { Write-Host "    - $($_.name)" -ForegroundColor Gray }
                }
                if ($drift.Added.Applications.Count -gt 0) {
                    Write-Host "  Applications: $($drift.Added.Applications.Count)"
                    $drift.Added.Applications |
                        ForEach-Object { Write-Host "    - $($_.displayName)" -ForegroundColor Gray }
                }
                Write-Host ""
            }

            # Show removed items
            if ($drift.Removed.DeviceConfigurations.Count -gt 0 -or
                $drift.Removed.CompliancePolicies.Count -gt 0 -or
                $drift.Removed.ConfigurationPolicies.Count -gt 0 -or
                $drift.Removed.Applications.Count -gt 0) {

                Write-Host "[-] Removed Items:" -ForegroundColor Red
                if ($drift.Removed.DeviceConfigurations.Count -gt 0) {
                    Write-Host "  Device Configurations: $($drift.Removed.DeviceConfigurations.Count)"
                    $drift.Removed.DeviceConfigurations |
                        ForEach-Object { Write-Host "    - $($_.displayName)" -ForegroundColor Gray }
                }
                if ($drift.Removed.CompliancePolicies.Count -gt 0) {
                    Write-Host "  Compliance Policies: $($drift.Removed.CompliancePolicies.Count)"
                    $drift.Removed.CompliancePolicies |
                        ForEach-Object { Write-Host "    - $($_.displayName)" -ForegroundColor Gray }
                }
                if ($drift.Removed.ConfigurationPolicies.Count -gt 0) {
                    Write-Host "  Configuration Policies: $($drift.Removed.ConfigurationPolicies.Count)"
                    $drift.Removed.ConfigurationPolicies |
                        ForEach-Object { Write-Host "    - $($_.name)" -ForegroundColor Gray }
                }
                if ($drift.Removed.Applications.Count -gt 0) {
                    Write-Host "  Applications: $($drift.Removed.Applications.Count)"
                    $drift.Removed.Applications |
                        ForEach-Object { Write-Host "    - $($_.displayName)" -ForegroundColor Gray }
                }
                Write-Host ""
            }

            # Show modified items
            if ($drift.Modified.DeviceConfigurations.Count -gt 0 -or
                $drift.Modified.CompliancePolicies.Count -gt 0 -or
                $drift.Modified.ConfigurationPolicies.Count -gt 0 -or
                $drift.Modified.Applications.Count -gt 0) {

                Write-Host "[!] Modified Items:" -ForegroundColor Yellow
                if ($drift.Modified.DeviceConfigurations.Count -gt 0) {
                    Write-Host "  Device Configurations: $($drift.Modified.DeviceConfigurations.Count)"
                    $drift.Modified.DeviceConfigurations |
                        ForEach-Object { Write-Host "    - $($_.displayName)" -ForegroundColor Gray }
                }
                if ($drift.Modified.CompliancePolicies.Count -gt 0) {
                    Write-Host "  Compliance Policies: $($drift.Modified.CompliancePolicies.Count)"
                    $drift.Modified.CompliancePolicies |
                        ForEach-Object { Write-Host "    - $($_.displayName)" -ForegroundColor Gray }
                }
                if ($drift.Modified.ConfigurationPolicies.Count -gt 0) {
                    Write-Host "  Configuration Policies: $($drift.Modified.ConfigurationPolicies.Count)"
                    $drift.Modified.ConfigurationPolicies |
                        ForEach-Object { Write-Host "    - $($_.name)" -ForegroundColor Gray }
                }
                if ($drift.Modified.Applications.Count -gt 0) {
                    Write-Host "  Applications: $($drift.Modified.Applications.Count)"
                    $drift.Modified.Applications |
                        ForEach-Object { Write-Host "    - $($_.displayName)" -ForegroundColor Gray }
                }
            }

            # Save drift report
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $reportPath = Join-Path $OutputPath "drift-report-$timestamp.json"
            $drift | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8 -ErrorAction Stop

            Write-Host "[+] Drift report saved to:" -ForegroundColor Green
            Write-Host "   $reportPath" -ForegroundColor Cyan

            if ($drift.TotalChanges -eq 0) {
                Write-Host "[+] No configuration drift detected!" -ForegroundColor Green
            }
        }

        Write-Host "[+] Done" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error during configuration drift analysis: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
