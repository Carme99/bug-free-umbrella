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

    The script is read-only: it never changes device state, so it can be re-run safely.
    Exit codes:
    - 0: audit completed and reports exported (also returned when no devices match the filter).
    - 1: connection failed, no Windows devices were found, or an unexpected error occurred.

.PARAMETER ExportFormat
    Report format: HTML, CSV, or Both (default: Both).

.PARAMETER ShowNonCompliantOnly
    Only show devices that are not Protected (or have not reported).

.PARAMETER IncludeAutoPatchInfo
    Include AutoPatch deployment ring information.

.PARAMETER DaysOutdated
    Highlight devices that haven't reported AV health in X days (default: 30).

.EXAMPLE
    PS C:\> .\Get-WindowsUpdateCompliance.ps1
    Generates the full Defender protection state report in HTML and CSV formats.

.EXAMPLE
    PS C:\> .\Get-WindowsUpdateCompliance.ps1 -ShowNonCompliantOnly
    Shows only devices that are not Protected.

.EXAMPLE
    PS C:\> .\Get-WindowsUpdateCompliance.ps1 -IncludeAutoPatchInfo -DaysOutdated 60
    Includes AutoPatch ring info and highlights devices not reporting in 60+ days.

.NOTES
    File Name: Get-WindowsUpdateCompliance.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
    Permissions: DeviceManagementManagedDevices.Read.All, WindowsUpdates.Read.All
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

$ErrorActionPreference = 'Stop'

function Main {
    try {
        $connected = $false

        # Report output directory with traversal safety checks.
        $ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
        if ([string]::IsNullOrWhiteSpace($ReportDir) -or
            $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
            $ReportDir -match '^(\\\\|//)') {
            throw "Unsafe report path: $ReportDir. Report path must be a local absolute path without '..' traversal."
        }
        $ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
        if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
            New-Item -ItemType Directory -Path $ReportDir -Force -ErrorAction Stop | Out-Null
        }

        # Import helper module (kept inside Main so dot-sourcing executes nothing harmful).
        $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'IntuneGraphHelper.psm1'
        Import-Module $modulePath -Force -ErrorAction Stop

        Write-Host "`n[*] Defender Protection State Report" -ForegroundColor Cyan
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
            throw "Failed to connect to Microsoft Graph."
        }

        Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop

        # Get all Windows devices
        Write-Host "[*] Retrieving all Windows devices..." -ForegroundColor Cyan
        $devices = @(Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop |
            Where-Object { $_.OperatingSystem -like "Windows*" })

        Write-Host "[+] Retrieved $($devices.Count) Windows devices" -ForegroundColor Green

        if ($devices.Count -eq 0) {
            Write-Host "[-] No Windows devices found to audit." -ForegroundColor Red
            return 1
        }

        # Get AutoPatch deployment info if requested
        $autoPatchDevices = @{}
        if ($IncludeAutoPatchInfo) {
            Write-Host "[*] Retrieving AutoPatch deployment information..." -ForegroundColor Cyan

            try {
                # Try to get Windows Update deployment audience (AutoPatch rings)
                $audienceUri = "https://graph.microsoft.com/beta/admin/windows/updates/deploymentAudiences"
                $deploymentAudiences = Invoke-MgGraphRequest -Uri $audienceUri -ErrorAction SilentlyContinue

                if ($deploymentAudiences.value) {
                    foreach ($audience in $deploymentAudiences.value) {
                        $memberUri = "https://graph.microsoft.com/beta/admin/windows/updates/deploymentAudiences/" +
                            "$($audience.id)/members"
                        $audienceMembers = Invoke-MgGraphRequest -Uri $memberUri -ErrorAction SilentlyContinue

                        if ($audienceMembers.value) {
                            foreach ($member in $audienceMembers.value) {
                                if ($member.azureAdDeviceId) {
                                    $autoPatchDevices[$member.azureAdDeviceId] = $audience.displayName
                                }
                            }
                        }
                    }
                    Write-Host "[+] Retrieved AutoPatch ring memberships" -ForegroundColor Green
                }
                else {
                    Write-Host "[!] No AutoPatch configuration found (or insufficient permissions)" `
                        -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "[!] Could not retrieve AutoPatch info: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        # Process each device
        Write-Host "`n[*] Analyzing Defender protection state..." -ForegroundColor Cyan
        $report = @()
        $counter = 0

        foreach ($device in $devices) {
            $counter++
            Write-Progress -Activity "Analyzing devices" -Status "$counter of $($devices.Count)" `
                -PercentComplete (($counter / $devices.Count) * 100)

            $deviceId = $device.Id

            # Get Defender protection state (this endpoint reports AV health, NOT update compliance)
            $protectionState = "Unknown"
            $antivirusStatus = "Unknown"
            $lastHealthReport = "Unknown"
            $daysSinceLastReport = "N/A"

            try {
                $protectionUri = "https://graph.microsoft.com/beta/deviceManagement/" +
                    "managedDevices/$deviceId/windowsProtectionState"
                $protectionStateData = Invoke-MgGraphRequest -Uri $protectionUri -ErrorAction SilentlyContinue

                if ($protectionStateData) {
                    $antivirusStatus = "Not Enabled"
                    if ($protectionStateData.antivirusEnabled -eq $true) { $antivirusStatus = "Enabled" }
                    $protectionState = "Not Protected"
                    if ($protectionStateData.malwareProtectionEnabled -eq $true) { $protectionState = "Protected" }

                    # Last AV health report time
                    if ($protectionStateData.lastReportedDateTime) {
                        $lastReported = $protectionStateData.lastReportedDateTime
                        if ($lastReported -is [string]) { $lastReported = [datetime]::Parse($lastReported) }
                        $lastHealthReport = $lastReported.ToString("yyyy-MM-dd HH:mm:ss")
                        $daysSinceLastReport = [math]::Round(
                            (New-TimeSpan -Start $lastReported -End (Get-Date)).TotalDays, 1)
                    }
                }
            }
            catch {
                # Device has no reachable protection state; defaults (Unknown) stay in place.
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
                LastSyncDateTime = if ($device.LastSyncDateTime) {
                    $device.LastSyncDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                } else { "Never" }
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
        Write-Host "`n[*] DEFENDER PROTECTION STATE SUMMARY" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan

        $totalDevices = $report.Count
        $protected = ($report | Where-Object { $_.ProtectionState -eq "Protected" }).Count
        $notProtected = ($report | Where-Object { $_.ProtectionState -eq "Not Protected" }).Count
        $unknown = ($report | Where-Object { $_.ProtectionState -eq "Unknown" }).Count
        $stale = ($report | Where-Object {
            $_.DaysSinceLastReport -ne "N/A" -and [double]$_.DaysSinceLastReport -gt $DaysOutdated
        }).Count

        Write-Host "Total Windows Devices:   $totalDevices" -ForegroundColor White
        $protectedPct = if ($totalDevices -gt 0) { '{0:P0}' -f ($protected / $totalDevices) } else { 'N/A' }
        $notProtectedPct = if ($totalDevices -gt 0) { '{0:P0}' -f ($notProtected / $totalDevices) } else { 'N/A' }
        Write-Host "Protected:               $protected ($protectedPct)" -ForegroundColor Green
        Write-Host "Not Protected:           $notProtected ($notProtectedPct)" -ForegroundColor Red
        Write-Host "Unknown Status:          $unknown" -ForegroundColor Yellow
        $staleColor = if ($stale -gt 0) { 'Yellow' } else { 'Green' }
        Write-Host "No AV Report (${DaysOutdated}+ days):  $stale" -ForegroundColor $staleColor

        if ($IncludeAutoPatchInfo) {
            Write-Host "`n[*] AutoPatch Ring Distribution:" -ForegroundColor Cyan
            $ringGroups = $report | Group-Object -Property AutoPatchRing
            foreach ($ring in $ringGroups | Sort-Object Count -Descending) {
                $color = if ($ring.Name -eq "Not Enrolled") { "Yellow" } else { "Green" }
                Write-Host "  $($ring.Name): $($ring.Count)" -ForegroundColor $color
            }
        }

        if ($report.Count -eq 0) {
            Write-Host "`n[!] No devices match the current filter criteria." -ForegroundColor Yellow
            return 0
        }

        # Sort report
        $report = $report | Sort-Object ProtectionState, DeviceName

        # Export reports
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $outputPath = $ReportDir

        if ($ExportFormat -eq 'HTML' -or $ExportFormat -eq 'Both') {
            $htmlPath = Join-Path $outputPath "DefenderProtectionState_$timestamp.html"
            $htmlParams = @{ Data = $report; Title = "Defender Protection State Report"; FilePath = $htmlPath }
            Export-IntuneReportToHTML @htmlParams -ErrorAction Stop
        }

        if ($ExportFormat -eq 'CSV' -or $ExportFormat -eq 'Both') {
            $csvPath = Join-Path $outputPath "DefenderProtectionState_$timestamp.csv"
            $csvParams = @{ Data = $report; Title = "DefenderProtectionState"; FilePath = $csvPath }
            Export-IntuneReportToCSV @csvParams -ErrorAction Stop
        }

        # Recommendations
        if ($notProtected -gt 0 -or $stale -gt 0) {
            Write-Host "`n[!] RECOMMENDATIONS:" -ForegroundColor Yellow

            if ($notProtected -gt 0) {
                Write-Host "  - $notProtected devices are not Protected by Defender" -ForegroundColor Yellow
                Write-Host "  - Review Defender AV configuration and device health" -ForegroundColor Yellow
            }

            if ($stale -gt 0) {
                Write-Host "  - $stale devices haven't reported AV health in ${DaysOutdated}+ days" `
                    -ForegroundColor Yellow
                Write-Host "  - Verify devices are online and connected to network" -ForegroundColor Yellow
                Write-Host "  - Check for Defender service connectivity issues" -ForegroundColor Yellow
            }
        }

        Write-Host "`n[+] Defender protection state audit completed!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "`n[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
        return 1
    }
    finally {
        if ($connected) {
            Disconnect-IntuneGraph
        }
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
