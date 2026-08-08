<#
.SYNOPSIS
    Generates a Defender protection state report for Windows devices, including AutoPatch status.

.DESCRIPTION
    This script analyzes Defender protection state (windowsProtectionState) across all
    managed Windows devices. It does NOT report Windows Update compliance - the Graph
    API does not expose per-device update compliance through this endpoint, so this
    report honestly reflects what the data shows: endpoint protection health and the
    last AV health report time per device.

    Reports on:
    - Defender protection state (Protected / Not Protected)
    - Antivirus engine status
    - Last AV health report time per device
    - Days since last AV health report
    - AutoPatch ring membership (if applicable)

.PARAMETER ExportFormat
    Report format: HTML, CSV, or Both (default: Both).

.PARAMETER ShowNonCompliantOnly
    Only show devices that are not Protected (or have not reported).

.PARAMETER IncludeAutoPatchInfo
    Include AutoPatch deployment ring information.

.PARAMETER DaysOutdated
    Highlight devices that haven't reported AV health in X days (default: 30).

.EXAMPLE
    .\Get-WindowsUpdateCompliance.ps1
    Generates full Defender protection state report.

.EXAMPLE
    .\Get-WindowsUpdateCompliance.ps1 -ShowNonCompliantOnly
    Shows only devices that are not Protected.

.EXAMPLE
    .\Get-WindowsUpdateCompliance.ps1 -IncludeAutoPatchInfo -DaysOutdated 60
    Includes AutoPatch info and highlights devices not reporting in 60+ days.

.NOTES
    Requires Microsoft.Graph PowerShell module
    Requires permissions: DeviceManagementManagedDevices.Read.All, WindowsUpdates.Read.All
    For AutoPatch info: WindowsUpdateDeploymentSettings.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('HTML', 'CSV', 'Both')]
    [string]$ExportFormat = 'Both',

    [Parameter(Mandatory = $false)]
    [switch]$ShowNonCompliantOnly,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeAutoPatchInfo,

    [Parameter(Mandatory = $false)]
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
Write-Host "Defender Protection State Report" -ForegroundColor Cyan
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
    Write-Host "`nAnalyzing Defender protection state..." -ForegroundColor Cyan
    $report = @()
    $counter = 0

    foreach ($device in $devices) {
        $counter++
        Write-Progress -Activity "Analyzing devices" -Status "$counter of $($devices.Count)" -PercentComplete (($counter / $devices.Count) * 100)

        $deviceId = $device.Id

        # Get Defender protection state (this endpoint reports AV health, NOT Windows Update compliance)
        $protectionState = "Unknown"
        $antivirusStatus = "Unknown"
        $lastHealthReport = "Unknown"
        $daysSinceLastReport = "N/A"

        try {
            $protectionStateData = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$deviceId/windowsProtectionState" -ErrorAction SilentlyContinue

            if ($protectionStateData) {
                $antivirusStatus = if ($protectionStateData.antivirusEnabled -eq $true) { "Enabled" } else { "Not Enabled" }
                $protectionState = if ($protectionStateData.malwareProtectionEnabled -eq $true) { "Protected" } else { "Not Protected" }

                # Last AV health report time
                if ($protectionStateData.lastReportedDateTime) {
                    $lastReported = $protectionStateData.lastReportedDateTime
                    if ($lastReported -is [string]) { $lastReported = [datetime]::Parse($lastReported) }
                    $lastHealthReport = $lastReported.ToString("yyyy-MM-dd HH:mm:ss")
                    $daysSinceLastReport = [math]::Round((New-TimeSpan -Start $lastReported -End (Get-Date)).TotalDays, 1)
                }
            }
        }
        catch {
            # Unable to get protection state
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
            if ($protectionState -eq "Protected") {
                continue
            }
        }

        # Build report entry
        $reportEntry = [PSCustomObject]@{
            DeviceName = $device.DeviceName
            UserPrincipalName = $device.UserPrincipalName
            OSVersion = $device.OsVersion
            ProtectionState = $protectionState
            AntivirusStatus = $antivirusStatus
            LastHealthReport = $lastHealthReport
            DaysSinceLastReport = $daysSinceLastReport
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
    Write-Host "DEFENDER PROTECTION STATE SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $totalDevices = $report.Count
    $protected = ($report | Where-Object { $_.ProtectionState -eq "Protected" }).Count
    $notProtected = ($report | Where-Object { $_.ProtectionState -eq "Not Protected" }).Count
    $unknown = ($report | Where-Object { $_.ProtectionState -eq "Unknown" }).Count
    $stale = ($report | Where-Object { $_.DaysSinceLastReport -ne "N/A" -and [double]$_.DaysSinceLastReport -gt $DaysOutdated }).Count

    Write-Host "Total Windows Devices:   $totalDevices" -ForegroundColor White
    Write-Host "Protected:               $protected ($(if($totalDevices -gt 0){'{0:P0}' -f ($protected/$totalDevices)}else{'N/A'}))" -ForegroundColor Green
    Write-Host "Not Protected:           $notProtected ($(if($totalDevices -gt 0){'{0:P0}' -f ($notProtected/$totalDevices)}else{'N/A'}))" -ForegroundColor Red
    Write-Host "Unknown Status:          $unknown" -ForegroundColor Yellow
    Write-Host "No AV Report (${DaysOutdated}+ days):  $stale" -ForegroundColor $(if ($stale -gt 0) { 'Yellow' }else { 'Green' })

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
    $report = $report | Sort-Object ProtectionState, DeviceName

    # Export reports
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outputPath = $ReportDir

    if ($ExportFormat -eq 'HTML' -or $ExportFormat -eq 'Both') {
        $htmlPath = Join-Path $outputPath "DefenderProtectionState_$timestamp.html"
        Export-IntuneReportToHTML -Data $report -Title "Defender Protection State Report" -FilePath $htmlPath
    }

    if ($ExportFormat -eq 'CSV' -or $ExportFormat -eq 'Both') {
        $csvPath = Join-Path $outputPath "DefenderProtectionState_$timestamp.csv"
        Export-IntuneReportToCSV -Data $report -Title "DefenderProtectionState" -FilePath $csvPath
    }

    # Recommendations
    if ($notProtected -gt 0 -or $stale -gt 0) {
        Write-Host "`n⚠ RECOMMENDATIONS:" -ForegroundColor Yellow

        if ($notProtected -gt 0) {
            Write-Host "  - $notProtected devices are not Protected by Defender" -ForegroundColor Yellow
            Write-Host "  - Review Defender AV configuration and device health" -ForegroundColor Yellow
        }

        if ($stale -gt 0) {
            Write-Host "  - $stale devices haven't reported AV health in ${DaysOutdated}+ days" -ForegroundColor Yellow
            Write-Host "  - Verify devices are online and connected to network" -ForegroundColor Yellow
            Write-Host "  - Check for Defender service connectivity issues" -ForegroundColor Yellow
        }
    }

    Write-Host "`n✓ Defender protection state audit completed!" -ForegroundColor Green
}
catch {
    Write-Host "`n✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
}
finally {
    # Disconnect from Graph
    Disconnect-IntuneGraph
}
