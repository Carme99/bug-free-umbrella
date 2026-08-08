<#
.SYNOPSIS
    Exports all non-compliant devices from Intune with detailed compliance reasons.

.DESCRIPTION
    This script connects to Microsoft Intune via Graph API and generates a comprehensive
    report of all non-compliant devices, including:
    - Device name and user
    - Operating system and version
    - Last sync time
    - Compliance state
    - Specific compliance policy failures
    - Remediation suggestions

.PARAMETER ExportFormat
    Output format: HTML, CSV, or Both (default: HTML).

.PARAMETER IncludeCompliant
    Include compliant devices in the report (default: false).

.PARAMETER OutputPath
    Custom output path for reports (default: Desktop).

.EXAMPLE
    .\Get-DeviceComplianceReport.ps1
    Generates HTML report of non-compliant devices on desktop.

.EXAMPLE
    .\Get-DeviceComplianceReport.ps1 -ExportFormat Both -IncludeCompliant
    Generates both HTML and CSV reports including all devices.

.NOTES
    Requires Microsoft.Graph PowerShell module
    Requires permissions: DeviceManagementManagedDevices.Read.All, DeviceManagementConfiguration.Read.All
    Compatible with Windows, macOS, and Linux devices in Intune
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('HTML', 'CSV', 'Both')]
    [string]$ExportFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [switch]$IncludeCompliant,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

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

# Import helper module
$modulePath = Join-Path $PSScriptRoot "IntuneGraphHelper.psm1"
Import-Module $modulePath -Force

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Device Compliance Report Generator" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Connect to Microsoft Graph
$connected = Connect-IntuneGraph -Scopes @(
    "DeviceManagementManagedDevices.Read.All",
    "DeviceManagementConfiguration.Read.All"
)

if (-not $connected) {
    Write-Host "Failed to connect to Microsoft Graph. Exiting." -ForegroundColor Red
    exit 1
}

try {
    # Import required modules
    Import-Module Microsoft.Graph.DeviceManagement

    # Get all managed devices
    Write-Host "Retrieving all managed devices..." -ForegroundColor Cyan
    $devices = Get-MgDeviceManagementManagedDevice -All

    Write-Host "✓ Retrieved $($devices.Count) total devices" -ForegroundColor Green

    # Get compliance policies
    Write-Host "Retrieving compliance policies..." -ForegroundColor Cyan
    $compliancePolicies = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies"

    Write-Host "✓ Retrieved $($compliancePolicies.value.Count) compliance policies" -ForegroundColor Green

    # Process devices
    Write-Host "`nAnalyzing device compliance status..." -ForegroundColor Cyan
    $report = @()

    foreach ($device in $devices) {
        # Filter based on compliance state
        if (-not $IncludeCompliant -and $device.ComplianceState -eq 'compliant') {
            continue
        }

        # Get device compliance policy states
        $deviceId = $device.Id
        $complianceDetails = $null
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$deviceId/deviceCompliancePolicyStates"

        try {
            $complianceDetails = Invoke-MgGraphRequest -Uri $uri
        }
        catch {
            # Warn and continue - a per-device failure shouldn't abort the report
            Write-Warning "Graph API request failed for ${uri}: $_"
        }

        # Determine compliance reasons
        $failedPolicies = @()
        $complianceReason = "Unknown"

        if ($complianceDetails -and $complianceDetails.value) {
            foreach ($policy in $complianceDetails.value) {
                if ($policy.state -eq "nonCompliant" -or $policy.state -eq "error") {
                    $failedPolicies += $policy.displayName
                }
            }

            if ($failedPolicies.Count -gt 0) {
                $complianceReason = $failedPolicies -join "; "
            }
            elseif ($device.ComplianceState -eq 'noncompliant') {
                $complianceReason = "Device does not meet compliance policy requirements"
            }
            elseif ($device.ComplianceState -eq 'unknown') {
                $complianceReason = "Compliance not yet evaluated"
            }
            elseif ($device.ComplianceState -eq 'inGracePeriod') {
                $complianceReason = "In grace period"
            }
        }

        # Calculate days since last sync
        $daysSinceSync = "Unknown"
        if ($device.LastSyncDateTime) {
            $daysSinceSync = [math]::Round((New-TimeSpan -Start $device.LastSyncDateTime -End (Get-Date)).TotalDays, 1)
        }

        # Build report entry
        $reportEntry = [PSCustomObject]@{
            DeviceName = $device.DeviceName
            UserPrincipalName = $device.UserPrincipalName
            Manufacturer = $device.Manufacturer
            Model = $device.Model
            OperatingSystem = $device.OperatingSystem
            OSVersion = $device.OsVersion
            ComplianceState = $device.ComplianceState
            ComplianceReason = $complianceReason
            LastSyncDateTime = if ($device.LastSyncDateTime) { $device.LastSyncDateTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" }
            DaysSinceLastSync = $daysSinceSync
            SerialNumber = $device.SerialNumber
            EnrollmentDate = if ($device.EnrolledDateTime) { $device.EnrolledDateTime.ToString("yyyy-MM-dd") } else { "Unknown" }
            ManagementAgent = $device.ManagementAgent
        }

        $report += $reportEntry
    }

    # Display summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "COMPLIANCE SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $compliantCount = ($devices | Where-Object { $_.ComplianceState -eq 'compliant' }).Count
    $nonCompliantCount = ($devices | Where-Object { $_.ComplianceState -eq 'noncompliant' }).Count
    $unknownCount = ($devices | Where-Object { $_.ComplianceState -eq 'unknown' }).Count
    $gracePeriodCount = ($devices | Where-Object { $_.ComplianceState -eq 'inGracePeriod' }).Count

    Write-Host "Total Devices:       $($devices.Count)" -ForegroundColor White
    Write-Host "Compliant:           $compliantCount" -ForegroundColor Green
    Write-Host "Non-Compliant:       $nonCompliantCount" -ForegroundColor Red
    Write-Host "Unknown:             $unknownCount" -ForegroundColor Yellow
    Write-Host "In Grace Period:     $gracePeriodCount" -ForegroundColor Yellow
    Write-Host "`nReport Entries:      $($report.Count)" -ForegroundColor Cyan

    if ($report.Count -eq 0) {
        Write-Host "`n✓ All devices are compliant! No report generated." -ForegroundColor Green
        Disconnect-IntuneGraph
        exit 0
    }

    # Sort report by compliance state then by device name
    $report = $report | Sort-Object ComplianceState, DeviceName

    # Export reports
    if (-not $OutputPath) {
        $OutputPath = $ReportDir
    }
    elseif ([string]::IsNullOrWhiteSpace($OutputPath) -or
        $OutputPath -match '(^|[\\/])\.\.([\\/]|$)' -or
        $OutputPath -match '^(\\\\|//)') {
        Write-Error "Unsafe report path: $OutputPath. Report path must be a local absolute path without '..' traversal."
        exit 1
    }
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

    if ($ExportFormat -eq 'HTML' -or $ExportFormat -eq 'Both') {
        $htmlPath = Join-Path $OutputPath "DeviceComplianceReport_$timestamp.html"
        Export-IntuneReportToHTML -Data $report -Title "Device Compliance Report" -FilePath $htmlPath
    }

    if ($ExportFormat -eq 'CSV' -or $ExportFormat -eq 'Both') {
        $csvPath = Join-Path $OutputPath "DeviceComplianceReport_$timestamp.csv"
        Export-IntuneReportToCSV -Data $report -Title "DeviceComplianceReport" -FilePath $csvPath
    }

    Write-Host "`n✓ Compliance report generation completed!" -ForegroundColor Green
}
catch {
    Write-Host "`n✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
}
finally {
    # Disconnect from Graph
    Disconnect-IntuneGraph
}
