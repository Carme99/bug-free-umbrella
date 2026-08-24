<#
.SYNOPSIS
    Find and optionally remove or retire stale Intune devices that have not synced within a given number of days.

.DESCRIPTION
    This script identifies devices that have not synchronized with Intune for a specified number of days and can
    generate HTML/CSV reports under the user's Documents\Reports folder. With -Action Delete or -Action Retire it
    performs the corresponding device action for every stale device; those mutations are gated behind
    -WhatIf/-Confirm (SupportsShouldProcess) and, unless -AutoConfirm is supplied, an interactive confirmation.
    Re-running in Report mode on a converged tenant finds no stale devices and exits successfully without changes.

.PARAMETER DaysInactive
    Number of days of inactivity to consider a device stale. If not provided, script will prompt interactively.

.PARAMETER Action
    Action to perform: Report, Delete, or Retire.
    - Report: Only generate a report (default)
    - Delete: Remove devices from Intune
    - Retire: Retire devices (removes company data, keeps personal)

.PARAMETER ExportFormat
    Report format: HTML, CSV, or Both (default: Both).

.PARAMETER AutoConfirm
    Skip confirmation prompts (use with caution!).

.EXAMPLE
    PS C:\> .\Find-StaleDevices.ps1
    Prompts for days and generates a report.

.EXAMPLE
    PS C:\> .\Find-StaleDevices.ps1 -DaysInactive 90
    Finds devices inactive for 90+ days and generates report.

.EXAMPLE
    PS C:\> .\Find-StaleDevices.ps1 -DaysInactive 180 -Action Retire
    Finds devices inactive for 180+ days and retires them (with confirmation).

.NOTES
    File Name: Find-StaleDevices.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$DaysInactive,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Report', 'Delete', 'Retire')]
    [string]$Action = 'Report',

    [Parameter(Mandatory = $false)]
    [ValidateSet('HTML', 'CSV', 'Both')]
    [string]$ExportFormat = 'Both',

    [Parameter(Mandatory = $false)]
    [switch]$AutoConfirm
)

$ErrorActionPreference = 'Stop'

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Starting stale device detection..." -ForegroundColor Cyan

        $ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
        if ([string]::IsNullOrWhiteSpace($ReportDir) -or
            $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
            $ReportDir -match '^(\\\\|//)') {
            throw "Unsafe report path: $ReportDir. Report path must be a local absolute path without '..' traversal."
        }
        $ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
        if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
            New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
        }

        # Import helper module (mock seam for offline testing)
        $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) "IntuneGraphHelper.psm1"
        Import-Module $modulePath -Force -ErrorAction Stop

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
                $promptInput = Read-Host "Enter number of days"
                $DaysInactive = $promptInput -as [int]

                if ($DaysInactive -le 0) {
                    Write-Host "[-] Please enter a valid positive number." -ForegroundColor Red
                }
            } while ($DaysInactive -le 0)
        }

        Write-Host "[*] Searching for devices inactive for $DaysInactive+ days..." -ForegroundColor Cyan
        $actionColor = if ($Action -eq 'Report') { 'Green' } else { 'Yellow' }
        Write-Host "[*] Action mode: $Action" -ForegroundColor $actionColor

        # Connect to Microsoft Graph
        $mgV1Base = "https://graph.microsoft.com/v1.0/deviceManagement"
        $scopes = @("DeviceManagementManagedDevices.Read.All")
        if ($Action -ne 'Report') {
            $scopes += "DeviceManagementManagedDevices.ReadWrite.All"
        }

        $connected = Connect-IntuneGraph -Scopes $scopes

        if (-not $connected) {
            Write-Host "[-] Failed to connect to Microsoft Graph." -ForegroundColor Red
            return 1
        }

        try {
            # Import required modules
            Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop

            # Get all managed devices
            Write-Host "[*] Retrieving all managed devices..." -ForegroundColor Cyan
            $devices = Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop

            Write-Host "[+] Retrieved $($devices.Count) total devices" -ForegroundColor Green

            # Calculate cutoff date
            $cutoffDate = (Get-Date).AddDays(-$DaysInactive)
            Write-Host "[*] Cutoff date: $($cutoffDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan

            # Find stale devices
            Write-Host "[*] Analyzing device sync status..." -ForegroundColor Cyan
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
                    $lastSyncText = "Never"
                    if ($device.LastSyncDateTime) {
                        $lastSyncText = $device.LastSyncDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                    }
                    $daysInactiveText = "Never"
                    if ($daysSinceSync -ne "Never") {
                        $daysInactiveText = [math]::Round($daysSinceSync, 1)
                    }
                    $enrollmentText = "Unknown"
                    if ($device.EnrolledDateTime) {
                        $enrollmentText = $device.EnrolledDateTime.ToString("yyyy-MM-dd")
                    }

                    $staleDevices += [PSCustomObject]@{
                        DeviceName         = $device.DeviceName
                        UserPrincipalName  = $device.UserPrincipalName
                        OperatingSystem    = $device.OperatingSystem
                        OSVersion          = $device.OsVersion
                        Manufacturer       = $device.Manufacturer
                        Model              = $device.Model
                        LastSyncDateTime   = $lastSyncText
                        DaysInactive       = $daysInactiveText
                        EnrollmentDate     = $enrollmentText
                        SerialNumber       = $device.SerialNumber
                        DeviceId           = $device.Id
                        ComplianceState    = $device.ComplianceState
                        ManagementAgent    = $device.ManagementAgent
                    }
                }
            }

            # Display summary
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "STALE DEVICE SUMMARY" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "Total Devices:           $($devices.Count)" -ForegroundColor White
            Write-Host "Inactive Threshold:      $DaysInactive days" -ForegroundColor Yellow
            $staleColor = if ($staleDevices.Count -gt 0) { 'Red' } else { 'Green' }
            Write-Host "Stale Devices Found:     $($staleDevices.Count)" -ForegroundColor $staleColor

            if ($staleDevices.Count -eq 0) {
                Write-Host "[+] No stale devices found! Your tenant is clean." -ForegroundColor Green
                return 0
            }

            # Group by OS
            $groupedByOS = $staleDevices | Group-Object -Property OperatingSystem
            Write-Host ""
            Write-Host "Breakdown by OS:" -ForegroundColor Cyan
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
                Export-IntuneReportToHTML -Data $staleDevices `
                    -Title "Stale Devices Report ($DaysInactive+ days)" `
                    -FilePath $htmlPath -ErrorAction Stop
            }

            if ($ExportFormat -eq 'CSV' -or $ExportFormat -eq 'Both') {
                $csvPath = Join-Path $outputPath "StaleDevices_${DaysInactive}Days_$timestamp.csv"
                Export-IntuneReportToCSV -Data $staleDevices -Title "StaleDevices" -FilePath $csvPath -ErrorAction Stop
            }

            # Perform action if requested
            if ($Action -ne 'Report') {
                Write-Host ""
                Write-Host "[!] WARNING: $Action ACTION REQUESTED" -ForegroundColor Yellow

                Write-Host ""
                Write-Host "[!] You are about to $($Action.ToUpper()) $($staleDevices.Count) devices!" `
                    -ForegroundColor Red

                # Show summary
                foreach ($group in $groupedByOS | Sort-Object Count -Descending) {
                    Write-Host "  - $($group.Count) $($group.Name) devices" -ForegroundColor Yellow
                }

                if ($Action -eq 'Delete') {
                    Write-Host ""
                    Write-Host "[!] DELETE will permanently remove devices from Intune and cannot be undone." `
                        -ForegroundColor Red
                }
                elseif ($Action -eq 'Retire') {
                    Write-Host ""
                    Write-Host "[!] RETIRE will remove company data and unenroll devices; personal data stays intact." `
                        -ForegroundColor Yellow
                }

                if (-not $PSCmdlet.ShouldProcess("$($staleDevices.Count) stale devices", "$Action")) {
                    Write-Host "[!] Action skipped (WhatIf/Confirm)." -ForegroundColor Yellow
                    return 0
                }

                if (-not $AutoConfirm) {
                    Write-Host "[!] Type 'YES' in capital letters to confirm: " -ForegroundColor Red -NoNewline
                    $confirmation = Read-Host

                    if ($confirmation -ne 'YES') {
                        Write-Host "[!] Action cancelled by user." -ForegroundColor Yellow
                        return 0
                    }
                }

                Write-Host "[*] Processing $Action for $($staleDevices.Count) devices..." -ForegroundColor Yellow

                $successCount = 0
                $failCount = 0
                $counter = 0

                foreach ($device in $staleDevices) {
                    $counter++
                    Write-Progress -Activity "Processing devices" `
                        -Status "$counter of $($staleDevices.Count)" `
                        -PercentComplete (($counter / $staleDevices.Count) * 100)

                    if (-not $PSCmdlet.ShouldProcess($device.DeviceName, "$Action stale device")) {
                        continue
                    }

                    try {
                        if ($Action -eq 'Delete') {
                            Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $device.DeviceId -ErrorAction Stop
                            Write-Host "[+] Deleted: $($device.DeviceName)" -ForegroundColor Green
                            $successCount++
                        }
                        elseif ($Action -eq 'Retire') {
                            $retireUri = "$mgV1Base/managedDevices/$($device.DeviceId)/retire"
                            Invoke-MgGraphRequest -Method POST -Uri $retireUri -ErrorAction Stop | Out-Null
                            Write-Host "[+] Retired: $($device.DeviceName)" -ForegroundColor Green
                            $successCount++
                        }
                    }
                    catch {
                        Write-Host "[-] Failed: $($device.DeviceName) - $($_.Exception.Message)" -ForegroundColor Red
                        $failCount++
                    }

                    Start-Sleep -Milliseconds 200  # Throttle requests
                }

                Write-Progress -Activity "Processing devices" -Completed

                Write-Host ""
                Write-Host "ACTION SUMMARY" -ForegroundColor Cyan
                Write-Host "Total Processed:  $($staleDevices.Count)" -ForegroundColor White
                Write-Host "Successful:       $successCount" -ForegroundColor Green
                $failColor = if ($failCount -gt 0) { 'Red' } else { 'Green' }
                Write-Host "Failed:           $failCount" -ForegroundColor $failColor
            }

            Write-Host "[+] Stale device processing completed!" -ForegroundColor Green
        }
        finally {
            # Disconnect from Graph
            Disconnect-IntuneGraph
        }

        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
