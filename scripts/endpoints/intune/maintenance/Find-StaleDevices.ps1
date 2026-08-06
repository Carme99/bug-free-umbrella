<#
.SYNOPSIS
    Finds and optionally removes stale devices from Intune that haven't synced in X days.

.DESCRIPTION
    This script identifies devices that haven't synchronized with Intune for a specified
    number of days. It can generate reports and optionally delete/retire stale devices.

    Features:
    - Interactive prompt for days threshold
    - Identifies devices that haven't synced
    - Shows last logged-in user
    - Option to delete or retire devices
    - Safety confirmation before bulk actions
    - Detailed HTML/CSV reports

.PARAMETER DaysInactive
    Number of days of inactivity to consider a device stale.
    If not provided, script will prompt interactively.

.PARAMETER Action
    Action to perform: Report, Delete, or Retire
    - Report: Only generate a report (default)
    - Delete: Remove devices from Intune
    - Retire: Retire devices (removes company data, keeps personal)

.PARAMETER ExportFormat
    Report format: HTML, CSV, or Both (default: Both).

.PARAMETER AutoConfirm
    Skip confirmation prompts (use with caution!).

.EXAMPLE
    .\Find-StaleDevices.ps1
    Prompts for days and generates a report.

.EXAMPLE
    .\Find-StaleDevices.ps1 -DaysInactive 90
    Finds devices inactive for 90+ days and generates report.

.EXAMPLE
    .\Find-StaleDevices.ps1 -DaysInactive 180 -Action Retire
    Finds devices inactive for 180+ days and retires them (with confirmation).

.NOTES
    Requires Microsoft.Graph PowerShell module
    Requires permissions: DeviceManagementManagedDevices.ReadWrite.All
    BE CAREFUL with Delete/Retire actions - they cannot be easily undone!
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [int]$DaysInactive,

    [Parameter(Mandatory=$false)]
    [ValidateSet('Report', 'Delete', 'Retire')]
    [string]$Action = 'Report',

    [Parameter(Mandatory=$false)]
    [ValidateSet('HTML', 'CSV', 'Both')]
    [string]$ExportFormat = 'Both',

    [Parameter(Mandatory=$false)]
    [switch]$AutoConfirm
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
Write-Host "Stale Device Finder" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Prompt for days if not provided
if (-not $DaysInactive) {
    Write-Host "How many days of inactivity should be considered 'stale'?" -ForegroundColor Yellow
    Write-Host "Common values:" -ForegroundColor Gray
    Write-Host "  30  - 1 month" -ForegroundColor Gray
    Write-Host "  60  - 2 months" -ForegroundColor Gray
    Write-Host "  90  - 3 months (recommended minimum)" -ForegroundColor Gray
    Write-Host "  180 - 6 months" -ForegroundColor Gray
    Write-Host "  365 - 1 year" -ForegroundColor Gray

    do {
        $input = Read-Host "`nEnter number of days"
        $DaysInactive = $input -as [int]

        if ($DaysInactive -le 0) {
            Write-Host "Please enter a valid positive number." -ForegroundColor Red
        }
    } while ($DaysInactive -le 0)
}

Write-Host "`nSearching for devices inactive for $DaysInactive+ days..." -ForegroundColor Cyan
Write-Host "Action mode: $Action" -ForegroundColor $(if($Action -eq 'Report'){'Green'}else{'Yellow'})

# Connect to Microsoft Graph
$scopes = @("DeviceManagementManagedDevices.Read.All")
if ($Action -ne 'Report') {
    $scopes += "DeviceManagementManagedDevices.ReadWrite.All"
}

$connected = Connect-IntuneGraph -Scopes $scopes

if (-not $connected) {
    Write-Host "Failed to connect to Microsoft Graph. Exiting." -ForegroundColor Red
    exit 1
}

try {
    # Import required modules
    Import-Module Microsoft.Graph.DeviceManagement

    # Get all managed devices
    Write-Host "`nRetrieving all managed devices..." -ForegroundColor Cyan
    $devices = Get-MgDeviceManagementManagedDevice -All

    Write-Host "✓ Retrieved $($devices.Count) total devices" -ForegroundColor Green

    # Calculate cutoff date
    $cutoffDate = (Get-Date).AddDays(-$DaysInactive)
    Write-Host "✓ Cutoff date: $($cutoffDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Green

    # Find stale devices
    Write-Host "`nAnalyzing device sync status..." -ForegroundColor Cyan
    $staleDevices = @()

    foreach ($device in $devices) {
        $isStale = $false
        $daysSinceSync = $null

        if ($device.LastSyncDateTime) {
            $daysSinceSync = (New-TimeSpan -Start $device.LastSyncDateTime -End (Get-Date)).TotalDays

            if ($device.LastSyncDateTime -lt $cutoffDate) {
                $isStale = $true
            }
        }
        else {
            # Never synced
            $isStale = $true
            $daysSinceSync = "Never"
        }

        if ($isStale) {
            $staleDevices += [PSCustomObject]@{
                DeviceName = $device.DeviceName
                UserPrincipalName = $device.UserPrincipalName
                OperatingSystem = $device.OperatingSystem
                OSVersion = $device.OsVersion
                Manufacturer = $device.Manufacturer
                Model = $device.Model
                LastSyncDateTime = if ($device.LastSyncDateTime) { $device.LastSyncDateTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" }
                DaysInactive = if ($daysSinceSync -eq "Never") { "Never" } else { [math]::Round($daysSinceSync, 1) }
                EnrollmentDate = if ($device.EnrolledDateTime) { $device.EnrolledDateTime.ToString("yyyy-MM-dd") } else { "Unknown" }
                SerialNumber = $device.SerialNumber
                DeviceId = $device.Id
                ComplianceState = $device.ComplianceState
                ManagementAgent = $device.ManagementAgent
            }
        }
    }

    # Display summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "STALE DEVICE SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total Devices:           $($devices.Count)" -ForegroundColor White
    Write-Host "Inactive Threshold:      $DaysInactive days" -ForegroundColor Yellow
    Write-Host "Stale Devices Found:     $($staleDevices.Count)" -ForegroundColor $(if($staleDevices.Count -gt 0){'Red'}else{'Green'})

    if ($staleDevices.Count -eq 0) {
        Write-Host "`n✓ No stale devices found! Your tenant is clean." -ForegroundColor Green
        Disconnect-IntuneGraph
        exit 0
    }

    # Group by OS
    $groupedByOS = $staleDevices | Group-Object -Property OperatingSystem
    Write-Host "`nBreakdown by OS:" -ForegroundColor Cyan
    foreach ($group in $groupedByOS | Sort-Object Count -Descending) {
        Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor Gray
    }

    # Sort by days inactive
    $staleDevices = $staleDevices | Sort-Object {
        if ($_.DaysInactive -eq "Never") { 999999 } else { [int]$_.DaysInactive }
    } -Descending

    # Export report
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outputPath = $ReportDir

    if ($ExportFormat -eq 'HTML' -or $ExportFormat -eq 'Both') {
        $htmlPath = Join-Path $outputPath "StaleDevices_${DaysInactive}Days_$timestamp.html"
        Export-IntuneReportToHTML -Data $staleDevices -Title "Stale Devices Report ($DaysInactive+ days)" -FilePath $htmlPath
    }

    if ($ExportFormat -eq 'CSV' -or $ExportFormat -eq 'Both') {
        $csvPath = Join-Path $outputPath "StaleDevices_${DaysInactive}Days_$timestamp.csv"
        Export-IntuneReportToCSV -Data $staleDevices -Title "StaleDevices" -FilePath $csvPath
    }

    # Perform action if requested
    if ($Action -ne 'Report') {
        Write-Host "`n========================================" -ForegroundColor Yellow
        Write-Host "WARNING: $Action ACTION REQUESTED" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow

        Write-Host "`nYou are about to $($Action.ToUpper()) $($staleDevices.Count) devices!" -ForegroundColor Red
        Write-Host "This action affects:" -ForegroundColor Yellow

        # Show summary
        foreach ($group in $groupedByOS | Sort-Object Count -Descending) {
            Write-Host "  - $($group.Count) $($group.Name) devices" -ForegroundColor Yellow
        }

        if ($Action -eq 'Delete') {
            Write-Host "`nDELETE will:" -ForegroundColor Red
            Write-Host "  • Permanently remove devices from Intune" -ForegroundColor Red
            Write-Host "  • Cannot be undone" -ForegroundColor Red
            Write-Host "  • Devices must re-enroll to be managed again" -ForegroundColor Red
        }
        elseif ($Action -eq 'Retire') {
            Write-Host "`nRETIRE will:" -ForegroundColor Yellow
            Write-Host "  • Remove company data from devices" -ForegroundColor Yellow
            Write-Host "  • Keep personal data intact" -ForegroundColor Yellow
            Write-Host "  • Unenroll devices from management" -ForegroundColor Yellow
        }

        if (-not $AutoConfirm) {
            Write-Host "`nType 'YES' in capital letters to confirm: " -ForegroundColor Red -NoNewline
            $confirmation = Read-Host

            if ($confirmation -ne 'YES') {
                Write-Host "`n✗ Action cancelled by user." -ForegroundColor Yellow
                Disconnect-IntuneGraph
                exit 0
            }
        }

        Write-Host "`nProcessing $Action for $($staleDevices.Count) devices..." -ForegroundColor Yellow

        $successCount = 0
        $failCount = 0
        $counter = 0

        foreach ($device in $staleDevices) {
            $counter++
            Write-Progress -Activity "Processing devices" -Status "$counter of $($staleDevices.Count)" -PercentComplete (($counter / $staleDevices.Count) * 100)

            try {
                if ($Action -eq 'Delete') {
                    Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $device.DeviceId -ErrorAction Stop
                    Write-Host "  ✓ Deleted: $($device.DeviceName)" -ForegroundColor Green
                    $successCount++
                }
                elseif ($Action -eq 'Retire') {
                    Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$($device.DeviceId)/retire" -ErrorAction Stop
                    Write-Host "  ✓ Retired: $($device.DeviceName)" -ForegroundColor Green
                    $successCount++
                }
            }
            catch {
                Write-Host "  ✗ Failed: $($device.DeviceName) - $($_.Exception.Message)" -ForegroundColor Red
                $failCount++
            }

            Start-Sleep -Milliseconds 200  # Throttle requests
        }

        Write-Progress -Activity "Processing devices" -Completed

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "ACTION SUMMARY" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Total Processed:  $($staleDevices.Count)" -ForegroundColor White
        Write-Host "Successful:       $successCount" -ForegroundColor Green
        Write-Host "Failed:           $failCount" -ForegroundColor $(if($failCount -gt 0){'Red'}else{'Green'})
    }

    Write-Host "`n✓ Stale device processing completed!" -ForegroundColor Green
}
catch {
    Write-Host "`n✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
}
finally {
    # Disconnect from Graph
    Disconnect-IntuneGraph
}
