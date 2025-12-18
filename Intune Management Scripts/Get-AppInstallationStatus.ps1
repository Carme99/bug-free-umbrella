<#
.SYNOPSIS
    Checks installation status of a specific application across all Intune-managed devices.

.DESCRIPTION
    This script retrieves installation status for a specific application from Intune.
    It shows which devices have successfully installed the app, which failed, and which
    are pending installation.

    Features:
    - Interactive app selection from Intune catalog
    - Search for apps by name
    - Installation status per device
    - Success/failure/pending breakdown
    - Error details for failed installations
    - Export to HTML/CSV

.PARAMETER AppName
    Name of the application to check (supports partial matching).
    If not provided, displays list of all apps for selection.

.PARAMETER AppId
    Specific Application ID to check (bypasses search).

.PARAMETER ExportFormat
    Report format: HTML, CSV, or Both (default: Both).

.PARAMETER ShowSuccessOnly
    Only show devices where app installed successfully.

.PARAMETER ShowFailuresOnly
    Only show devices where app installation failed.

.EXAMPLE
    .\Get-AppInstallationStatus.ps1
    Displays list of all apps and prompts for selection.

.EXAMPLE
    .\Get-AppInstallationStatus.ps1 -AppName "Microsoft Edge"
    Searches for apps matching "Microsoft Edge" and shows status.

.EXAMPLE
    .\Get-AppInstallationStatus.ps1 -AppName "Chrome" -ShowFailuresOnly
    Shows only devices where Chrome installation failed.

.NOTES
    Requires Microsoft.Graph PowerShell module
    Requires permissions: DeviceManagementApps.Read.All, DeviceManagementManagedDevices.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$AppName,

    [Parameter(Mandatory=$false)]
    [string]$AppId,

    [Parameter(Mandatory=$false)]
    [ValidateSet('HTML', 'CSV', 'Both')]
    [string]$ExportFormat = 'Both',

    [Parameter(Mandatory=$false)]
    [switch]$ShowSuccessOnly,

    [Parameter(Mandatory=$false)]
    [switch]$ShowFailuresOnly
)

# Import helper module
$modulePath = Join-Path $PSScriptRoot "IntuneGraphHelper.psm1"
Import-Module $modulePath -Force

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Application Installation Status Checker" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Connect to Microsoft Graph
$connected = Connect-IntuneGraph -Scopes @(
    "DeviceManagementApps.Read.All",
    "DeviceManagementManagedDevices.Read.All"
)

if (-not $connected) {
    Write-Host "Failed to connect to Microsoft Graph. Exiting." -ForegroundColor Red
    exit 1
}

try {
    $selectedApp = $null

    # If AppId is provided, use it directly
    if ($AppId) {
        Write-Host "Retrieving app with ID: $AppId..." -ForegroundColor Cyan
        $selectedApp = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$AppId"

        if (-not $selectedApp) {
            Write-Host "✗ App with ID '$AppId' not found." -ForegroundColor Red
            Disconnect-IntuneGraph
            exit 1
        }
    }
    else {
        # Get all apps from Intune
        Write-Host "Retrieving all applications from Intune..." -ForegroundColor Cyan
        $allApps = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"

        # Filter out irrelevant app types
        $apps = $allApps.value | Where-Object {
            $_.'@odata.type' -match 'win32LobApp|windowsMobileMSI|officeSuiteApp|webApp|managedIOSLobApp|managedAndroidLobApp'
        } | Select-Object id, displayName, publisher, '@odata.type'

        Write-Host "✓ Retrieved $($apps.Count) applications" -ForegroundColor Green

        if ($apps.Count -eq 0) {
            Write-Host "✗ No applications found in Intune." -ForegroundColor Red
            Disconnect-IntuneGraph
            exit 1
        }

        # Search by name if provided
        if ($AppName) {
            $matchingApps = $apps | Where-Object { $_.displayName -like "*$AppName*" }

            if ($matchingApps.Count -eq 0) {
                Write-Host "✗ No applications found matching '$AppName'" -ForegroundColor Red
                Write-Host "`nShowing all available applications:" -ForegroundColor Yellow
            }
            elseif ($matchingApps.Count -eq 1) {
                $selectedApp = $matchingApps[0]
                Write-Host "✓ Found matching app: $($selectedApp.displayName)" -ForegroundColor Green
            }
            else {
                Write-Host "Found $($matchingApps.Count) applications matching '$AppName':" -ForegroundColor Yellow
                $apps = $matchingApps
            }
        }

        # If no app selected yet, show selection menu
        if (-not $selectedApp) {
            Write-Host "`nAvailable Applications:" -ForegroundColor Cyan
            Write-Host "------------------------" -ForegroundColor Cyan

            for ($i = 0; $i -lt [Math]::Min(50, $apps.Count); $i++) {
                $app = $apps[$i]
                Write-Host "[$($i + 1)] $($app.displayName) - $($app.publisher)" -ForegroundColor White
            }

            if ($apps.Count -gt 50) {
                Write-Host "`n... and $($apps.Count - 50) more. Use -AppName to search." -ForegroundColor Gray
            }

            Write-Host "`nEnter the number of the application to check: " -ForegroundColor Yellow -NoNewline
            $selection = Read-Host

            $selectionIndex = ($selection -as [int]) - 1

            if ($selectionIndex -lt 0 -or $selectionIndex -ge $apps.Count) {
                Write-Host "✗ Invalid selection." -ForegroundColor Red
                Disconnect-IntuneGraph
                exit 1
            }

            $selectedApp = $apps[$selectionIndex]
        }
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Selected Application" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Name:      $($selectedApp.displayName)" -ForegroundColor White
    Write-Host "Publisher: $($selectedApp.publisher)" -ForegroundColor White
    Write-Host "Type:      $($selectedApp.'@odata.type')" -ForegroundColor White
    Write-Host "ID:        $($selectedApp.id)" -ForegroundColor Gray

    # Get installation status for this app
    Write-Host "`nRetrieving installation status..." -ForegroundColor Cyan
    $installStatusUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($selectedApp.id)/deviceStatuses"
    $installStatus = Invoke-MgGraphRequest -Uri $installStatusUri

    if (-not $installStatus.value -or $installStatus.value.Count -eq 0) {
        Write-Host "✗ No installation data found for this application." -ForegroundColor Yellow
        Write-Host "This could mean:" -ForegroundColor Gray
        Write-Host "  - App is not assigned to any devices" -ForegroundColor Gray
        Write-Host "  - App has not been deployed yet" -ForegroundColor Gray
        Write-Host "  - Installation data has not synced" -ForegroundColor Gray
        Disconnect-IntuneGraph
        exit 0
    }

    Write-Host "✓ Retrieved installation data for $($installStatus.value.Count) devices" -ForegroundColor Green

    # Process installation status
    Write-Host "`nProcessing installation status..." -ForegroundColor Cyan
    $report = @()

    foreach ($status in $installStatus.value) {
        # Get device details
        $deviceName = $status.deviceName
        $userName = $status.userName

        # Determine status
        $installState = switch ($status.installState) {
            "installed" { "Installed" }
            "failed" { "Failed" }
            "notInstalled" { "Not Installed" }
            "uninstallFailed" { "Uninstall Failed" }
            "pendingInstall" { "Pending Install" }
            "unknown" { "Unknown" }
            "notApplicable" { "Not Applicable" }
            default { $status.installState }
        }

        # Apply filters
        if ($ShowSuccessOnly -and $installState -ne "Installed") {
            continue
        }
        if ($ShowFailuresOnly -and $installState -ne "Failed") {
            continue
        }

        $reportEntry = [PSCustomObject]@{
            DeviceName = $deviceName
            UserName = $userName
            InstallState = $installState
            LastSyncDateTime = if ($status.lastSyncDateTime) { $status.lastSyncDateTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "Unknown" }
            OSVersion = $status.osVersion
            OSDescription = $status.osDescription
            ErrorCode = if ($status.errorCode) { "0x$($status.errorCode.ToString('X8'))" } else { "" }
            InstallStateDetail = $status.installStateDetail
        }

        $report += $reportEntry
    }

    # Display summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "INSTALLATION SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $totalDevices = $installStatus.value.Count
    $installed = ($installStatus.value | Where-Object { $_.installState -eq "installed" }).Count
    $failed = ($installStatus.value | Where-Object { $_.installState -eq "failed" }).Count
    $pending = ($installStatus.value | Where-Object { $_.installState -eq "pendingInstall" }).Count
    $notInstalled = ($installStatus.value | Where-Object { $_.installState -eq "notInstalled" }).Count

    Write-Host "Total Devices:       $totalDevices" -ForegroundColor White
    Write-Host "Installed:           $installed ($('{0:P0}' -f ($installed/$totalDevices)))" -ForegroundColor Green
    Write-Host "Failed:              $failed ($('{0:P0}' -f ($failed/$totalDevices)))" -ForegroundColor Red
    Write-Host "Pending:             $pending ($('{0:P0}' -f ($pending/$totalDevices)))" -ForegroundColor Yellow
    Write-Host "Not Installed:       $notInstalled ($('{0:P0}' -f ($notInstalled/$totalDevices)))" -ForegroundColor Gray

    if ($report.Count -eq 0) {
        Write-Host "`nNo devices match the current filter." -ForegroundColor Yellow
        Disconnect-IntuneGraph
        exit 0
    }

    # Sort report
    $report = $report | Sort-Object InstallState, DeviceName

    # Export reports
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outputPath = "$env:USERPROFILE\Desktop"
    $appNameClean = $selectedApp.displayName -replace '[\\/:*?"<>|]', '_'

    if ($ExportFormat -eq 'HTML' -or $ExportFormat -eq 'Both') {
        $htmlPath = Join-Path $outputPath "AppInstallStatus_${appNameClean}_$timestamp.html"
        Export-IntuneReportToHTML -Data $report -Title "Installation Status: $($selectedApp.displayName)" -FilePath $htmlPath
    }

    if ($ExportFormat -eq 'CSV' -or $ExportFormat -eq 'Both') {
        $csvPath = Join-Path $outputPath "AppInstallStatus_${appNameClean}_$timestamp.csv"
        Export-IntuneReportToCSV -Data $report -Title "AppInstallStatus_${appNameClean}" -FilePath $csvPath
    }

    Write-Host "`n✓ Application installation status report completed!" -ForegroundColor Green
}
catch {
    Write-Host "`n✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
}
finally {
    # Disconnect from Graph
    Disconnect-IntuneGraph
}
