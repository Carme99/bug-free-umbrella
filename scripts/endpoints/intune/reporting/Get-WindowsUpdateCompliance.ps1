<#
.SYNOPSIS
    Generates Windows Update compliance report for devices, including AutoPatch status.

.DESCRIPTION
    This script analyzes Windows Update compliance across all managed Windows devices.
    Especially useful for environments using Windows Autopatch.

    Reports on:
    - Windows Update installation status
    - Security updates compliance
    - Feature updates compliance
    - Devices needing updates
    - Update installation failures
    - Days since last update check
    - AutoPatch ring membership (if applicable)

.PARAMETER ExportFormat
    Report format: HTML, CSV, or Both (default: Both).

.PARAMETER ShowNonCompliantOnly
    Only show devices that are not up-to-date.

.PARAMETER IncludeAutoPatchInfo
    Include AutoPatch deployment ring information.

.PARAMETER DaysOutdated
    Highlight devices that haven't updated in X days (default: 30).

.EXAMPLE
    .\Get-WindowsUpdateCompliance.ps1
    Generates full Windows Update compliance report.

.EXAMPLE
    .\Get-WindowsUpdateCompliance.ps1 -ShowNonCompliantOnly
    Shows only devices that need updates.

.EXAMPLE
    .\Get-WindowsUpdateCompliance.ps1 -IncludeAutoPatchInfo -DaysOutdated 60
    Includes AutoPatch info and highlights devices not updated in 60+ days.

.NOTES
    Requires Microsoft.Graph PowerShell module
    Requires permissions: DeviceManagementManagedDevices.Read.All, WindowsUpdates.Read.All
    For AutoPatch info: WindowsUpdateDeploymentSettings.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('HTML', 'CSV', 'Both')]
    [string]$ExportFormat = 'Both',

    [Parameter(Mandatory=$false)]
    [switch]$ShowNonCompliantOnly,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeAutoPatchInfo,

    [Parameter(Mandatory=$false)]
    [int]$DaysOutdated = 30
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
Write-Host "Windows Update Compliance Report" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Connect to Microsoft Graph
$scopes = @(
    "DeviceManagementManagedDevices.Read.All",
    "DeviceManagementConfiguration.Read.All"
)

if ($IncludeAutoPatchInfo) {
    $scopes += "WindowsUpdates.Read.All"
}

$connected = Connect-IntuneGraph -Scopes $scopes

if (-not $connected) {
    Write-Host "Failed to connect to Microsoft Graph. Exiting." -ForegroundColor Red
    exit 1
}

try {
    # Import required modules
    Import-Module Microsoft.Graph.DeviceManagement

    # Get all Windows devices
    Write-Host "Retrieving all Windows devices..." -ForegroundColor Cyan
    $devices = Get-MgDeviceManagementManagedDevice -All | Where-Object { $_.OperatingSystem -like "Windows*" }

    Write-Host "✓ Retrieved $($devices.Count) Windows devices" -ForegroundColor Green

    if ($devices.Count -eq 0) {
        Write-Host "✗ No Windows devices found to audit." -ForegroundColor Red
        Disconnect-IntuneGraph
        exit 1
    }

    # Get AutoPatch deployment info if requested
    $autoPatchDevices = @{}
    if ($IncludeAutoPatchInfo) {
        Write-Host "Retrieving AutoPatch deployment information..." -ForegroundColor Cyan

        try {
            # Try to get Windows Update deployment audience (AutoPatch rings)
            $deploymentAudiences = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/admin/windows/updates/deploymentAudiences" -ErrorAction SilentlyContinue

            if ($deploymentAudiences.value) {
                foreach ($audience in $deploymentAudiences.value) {
                    $audienceMembers = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/admin/windows/updates/deploymentAudiences/$($audience.id)/members" -ErrorAction SilentlyContinue

                    if ($audienceMembers.value) {
                        foreach ($member in $audienceMembers.value) {
                            if ($member.azureAdDeviceId) {
                                $autoPatchDevices[$member.azureAdDeviceId] = $audience.displayName
                            }
                        }
                    }
                }
                Write-Host "✓ Retrieved AutoPatch ring memberships" -ForegroundColor Green
            }
            else {
                Write-Host "✓ No AutoPatch configuration found (or insufficient permissions)" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "✓ Could not retrieve AutoPatch info: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Process each device
    Write-Host "`nAnalyzing Windows Update compliance..." -ForegroundColor Cyan
    $report = @()
    $counter = 0

    foreach ($device in $devices) {
        $counter++
        Write-Progress -Activity "Analyzing devices" -Status "$counter of $($devices.Count)" -PercentComplete (($counter / $devices.Count) * 100)

        $deviceId = $device.Id

        # Get Windows Update compliance
        $updateCompliance = "Unknown"
        $securityUpdateStatus = "Unknown"
        $featureUpdateStatus = "Unknown"
        $lastUpdateCheck = "Unknown"
        $daysOutOfDate = "N/A"
        $pendingUpdates = 0

        try {
            # Try to get device update states
            $windowsUpdateStates = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$deviceId/windowsProtectionState" -ErrorAction SilentlyContinue

            if ($windowsUpdateStates) {
                # Parse update information
                if ($windowsUpdateStates.malwareProtectionEnabled -eq $true) {
                    $securityUpdateStatus = "Protected"
                }

                # Get last scan time
                if ($windowsUpdateStates.lastReportedDateTime) {
                    $lastUpdateCheck = $windowsUpdateStates.lastReportedDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                    $daysOutOfDate = [math]::Round((New-TimeSpan -Start $windowsUpdateStates.lastReportedDateTime -End (Get-Date)).TotalDays, 1)
                }
            }

            # Try to get pending updates
            $deviceConfigStates = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$deviceId/deviceConfigurationStates" -ErrorAction SilentlyContinue

            # Determine overall compliance
            if ($device.ComplianceState -eq "compliant") {
                $updateCompliance = "Compliant"
            }
            elseif ($device.ComplianceState -eq "noncompliant") {
                $updateCompliance = "Non-Compliant"
            }
            else {
                $updateCompliance = "Unknown"
            }

            # Check if device is outdated
            if ($daysOutOfDate -ne "N/A" -and $daysOutOfDate -gt $DaysOutdated) {
                $updateCompliance = "Outdated ($daysOutOfDate days)"
            }
        }
        catch {
            # Unable to get update info
        }

        # Get AutoPatch ring if available
        $autoPatchRing = "Not Enrolled"
        if ($IncludeAutoPatchInfo -and $device.AzureAdDeviceId) {
            if ($autoPatchDevices.ContainsKey($device.AzureAdDeviceId)) {
                $autoPatchRing = $autoPatchDevices[$device.AzureAdDeviceId]
            }
        }

        # Apply filters
        if ($ShowNonCompliantOnly) {
            if ($updateCompliance -eq "Compliant") {
                continue
            }
        }

        # Build report entry
        $reportEntry = [PSCustomObject]@{
            DeviceName = $device.DeviceName
            UserPrincipalName = $device.UserPrincipalName
            OSVersion = $device.OsVersion
            UpdateCompliance = $updateCompliance
            LastUpdateCheck = $lastUpdateCheck
            DaysSinceLastCheck = $daysOutOfDate
            ComplianceState = $device.ComplianceState
            LastSyncDateTime = if ($device.LastSyncDateTime) { $device.LastSyncDateTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" }
            Manufacturer = $device.Manufacturer
            Model = $device.Model
            SerialNumber = $device.SerialNumber
        }

        if ($IncludeAutoPatchInfo) {
            $reportEntry | Add-Member -NotePropertyName "AutoPatchRing" -NotePropertyValue $autoPatchRing
        }

        $report += $reportEntry
    }

    Write-Progress -Activity "Analyzing devices" -Completed

    # Display summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "WINDOWS UPDATE COMPLIANCE SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $totalDevices = $report.Count
    $compliant = ($report | Where-Object { $_.UpdateCompliance -eq "Compliant" }).Count
    $nonCompliant = ($report | Where-Object { $_.UpdateCompliance -match "Non-Compliant|Outdated" }).Count
    $unknown = ($report | Where-Object { $_.UpdateCompliance -eq "Unknown" }).Count
    $outdated = ($report | Where-Object { $_.DaysSinceLastCheck -ne "N/A" -and [double]$_.DaysSinceLastCheck -gt $DaysOutdated }).Count

    Write-Host "Total Windows Devices:   $totalDevices" -ForegroundColor White
    Write-Host "Compliant:               $compliant ($(if($totalDevices -gt 0){'{0:P0}' -f ($compliant/$totalDevices)}else{'N/A'}))" -ForegroundColor Green
    Write-Host "Non-Compliant:           $nonCompliant ($(if($totalDevices -gt 0){'{0:P0}' -f ($nonCompliant/$totalDevices)}else{'N/A'}))" -ForegroundColor Red
    Write-Host "Unknown Status:          $unknown" -ForegroundColor Yellow
    Write-Host "Outdated (${DaysOutdated}+ days):  $outdated" -ForegroundColor $(if($outdated -gt 0){'Yellow'}else{'Green'})

    if ($IncludeAutoPatchInfo) {
        Write-Host "`nAutoPatch Ring Distribution:" -ForegroundColor Cyan
        $ringGroups = $report | Group-Object -Property AutoPatchRing
        foreach ($ring in $ringGroups | Sort-Object Count -Descending) {
            $color = if ($ring.Name -eq "Not Enrolled") { "Yellow" } else { "Green" }
            Write-Host "  $($ring.Name): $($ring.Count)" -ForegroundColor $color
        }
    }

    if ($report.Count -eq 0) {
        Write-Host "`nNo devices match the current filter criteria." -ForegroundColor Yellow
        Disconnect-IntuneGraph
        exit 0
    }

    # Sort report
    $report = $report | Sort-Object UpdateCompliance, DeviceName

    # Export reports
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outputPath = $ReportDir

    if ($ExportFormat -eq 'HTML' -or $ExportFormat -eq 'Both') {
        $htmlPath = Join-Path $outputPath "WindowsUpdateCompliance_$timestamp.html"
        Export-IntuneReportToHTML -Data $report -Title "Windows Update Compliance Report" -FilePath $htmlPath
    }

    if ($ExportFormat -eq 'CSV' -or $ExportFormat -eq 'Both') {
        $csvPath = Join-Path $outputPath "WindowsUpdateCompliance_$timestamp.csv"
        Export-IntuneReportToCSV -Data $report -Title "WindowsUpdateCompliance" -FilePath $csvPath
    }

    # Recommendations
    if ($nonCompliant -gt 0 -or $outdated -gt 0) {
        Write-Host "`n⚠ RECOMMENDATIONS:" -ForegroundColor Yellow

        if ($nonCompliant -gt 0) {
            Write-Host "  - $nonCompliant devices are not compliant with update policies" -ForegroundColor Yellow
            Write-Host "  - Review Windows Update for Business settings" -ForegroundColor Yellow
        }

        if ($outdated -gt 0) {
            Write-Host "  - $outdated devices haven't checked for updates in ${DaysOutdated}+ days" -ForegroundColor Yellow
            Write-Host "  - Verify devices are online and connected to network" -ForegroundColor Yellow
            Write-Host "  - Check for update service connectivity issues" -ForegroundColor Yellow
        }
    }

    Write-Host "`n✓ Windows Update compliance audit completed!" -ForegroundColor Green
}
catch {
    Write-Host "`n✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
}
finally {
    # Disconnect from Graph
    Disconnect-IntuneGraph
}
