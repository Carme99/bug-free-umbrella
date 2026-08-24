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
    PS C:\> .\Get-AppInstallationStatus.ps1
    Displays list of all apps and prompts for selection.

.EXAMPLE
    PS C:\> .\Get-AppInstallationStatus.ps1 -AppName "Microsoft Edge"
    Searches for apps matching "Microsoft Edge" and shows status.

.EXAMPLE
    PS C:\> .\Get-AppInstallationStatus.ps1 -AppName "Chrome" -ShowFailuresOnly
    Shows only devices where Chrome installation failed.

.NOTES
    File Name  : Get-AppInstallationStatus.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Requires Microsoft.Graph PowerShell module.
    Requires permissions: DeviceManagementApps.Read.All, DeviceManagementManagedDevices.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AppName,

    [Parameter(Mandatory = $false)]
    [string]$AppId,

    [Parameter(Mandatory = $false)]
    [ValidateSet('HTML', 'CSV', 'Both')]
    [string]$ExportFormat = 'Both',

    [Parameter(Mandatory = $false)]
    [switch]$ShowSuccessOnly,

    [Parameter(Mandatory = $false)]
    [switch]$ShowFailuresOnly
)

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Starting application installation status check..." -ForegroundColor Cyan

        # Prepare report directory
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

        # Import helper module
        $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) "IntuneGraphHelper.psm1"
        Import-Module $modulePath -Force -ErrorAction Stop

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "Application Installation Status Checker" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan

        # Connect to Microsoft Graph
        $connected = Connect-IntuneGraph -Scopes @(
            "DeviceManagementApps.Read.All",
            "DeviceManagementManagedDevices.Read.All"
        )

        if (-not $connected) {
            Write-Host "[-] Failed to connect to Microsoft Graph. Exiting." -ForegroundColor Red
            return 1
        }

        $selectedApp = $null

        # If AppId is provided, use it directly
        if ($AppId) {
            Write-Host "[*] Retrieving app with ID: $AppId..." -ForegroundColor Cyan
            $appUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$AppId"
            $selectedApp = Invoke-MgGraphRequest -Uri $appUri -ErrorAction Stop

            if (-not $selectedApp) {
                Write-Host "[-] App with ID '$AppId' not found." -ForegroundColor Red
                return 1
            }
        }
        else {
            # Get all apps from Intune
            Write-Host "[*] Retrieving all applications from Intune..." -ForegroundColor Cyan
            $appsListUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"
            $allApps = Invoke-MgGraphRequest -Uri $appsListUri -ErrorAction Stop

            # Filter out irrelevant app types
            $typeFilter = 'win32LobApp|windowsMobileMSI|officeSuiteApp|webApp|managedIOSLobApp|managedAndroidLobApp'
            $apps = $allApps.value | Where-Object {
                $_.'@odata.type' -match $typeFilter
            } | Select-Object id, displayName, publisher, '@odata.type'
            Write-Host "[+] Retrieved $($apps.Count) applications" -ForegroundColor Green

            if ($apps.Count -eq 0) {
                Write-Host "[-] No applications found in Intune." -ForegroundColor Red
                return 1
            }

            # Search by name if provided
            if ($AppName) {
                $matchingApps = @($apps | Where-Object { $_.displayName -like "*$AppName*" })

                if ($matchingApps.Count -eq 0) {
                    Write-Host "[-] No applications found matching '$AppName'" -ForegroundColor Red
                    Write-Host "[!] Showing all available applications:" -ForegroundColor Yellow
                }
                elseif ($matchingApps.Count -eq 1) {
                    $selectedApp = $matchingApps[0]
                    Write-Host "[+] Found matching app: $($selectedApp.displayName)" -ForegroundColor Green
                }
                else {
                    Write-Host "[!] Found $($matchingApps.Count) matching '$AppName':" -ForegroundColor Yellow
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
                    Write-Host "[-] Invalid selection." -ForegroundColor Red
                    return 1
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
        Write-Host "[*] Retrieving installation status..." -ForegroundColor Cyan
        $installStatusUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($selectedApp.id)" +
            "/deviceStatuses"
        $installStatus = Invoke-MgGraphRequest -Uri $installStatusUri -ErrorAction Stop

        if (-not $installStatus.value -or $installStatus.value.Count -eq 0) {
            Write-Host "[!] No installation data found for this application." -ForegroundColor Yellow
            Write-Host "This could mean:" -ForegroundColor Gray
            Write-Host "  - App is not assigned to any devices" -ForegroundColor Gray
            Write-Host "  - App has not been deployed yet" -ForegroundColor Gray
            Write-Host "  - Installation data has not synced" -ForegroundColor Gray
            return 0
        }

        Write-Host "[+] Retrieved installation data for $($installStatus.value.Count) devices" -ForegroundColor Green

        # Process installation status
        Write-Host "[*] Processing installation status..." -ForegroundColor Cyan
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

            $lastSyncText = "Unknown"
            if ($status.lastSyncDateTime) {
                $lastSyncText = $status.lastSyncDateTime.ToString("yyyy-MM-dd HH:mm:ss")
            }

            $reportEntry = [PSCustomObject]@{
                DeviceName = $deviceName
                UserName = $userName
                InstallState = $installState
                LastSyncDateTime = $lastSyncText
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
        $notInstalledPct = '{0:P0}' -f ($notInstalled/$totalDevices)
        Write-Host "Not Installed:       $notInstalled ($notInstalledPct)" -ForegroundColor Gray

        if ($report.Count -eq 0) {
            Write-Host "[!] No devices match the current filter." -ForegroundColor Yellow
            return 0
        }

        # Sort report
        $report = $report | Sort-Object InstallState, DeviceName

        # Export reports
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $outputPath = $ReportDir
        $appNameClean = $selectedApp.displayName -replace '[\\/:*?"<>|]', '_'

        if ($ExportFormat -eq 'HTML' -or $ExportFormat -eq 'Both') {
            $htmlPath = Join-Path $outputPath "AppInstallStatus_${appNameClean}_$timestamp.html"
            $reportTitle = "Installation Status: $($selectedApp.displayName)"
            Export-IntuneReportToHTML -Data $report -Title $reportTitle -FilePath $htmlPath
        }

        if ($ExportFormat -eq 'CSV' -or $ExportFormat -eq 'Both') {
            $csvPath = Join-Path $outputPath "AppInstallStatus_${appNameClean}_$timestamp.csv"
            Export-IntuneReportToCSV -Data $report -Title "AppInstallStatus_${appNameClean}" -FilePath $csvPath
        }

        Write-Host "`n[+] Application installation status report completed!" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "`n[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
        return 1
    }
    finally {
        # Disconnect from Graph
        Disconnect-IntuneGraph
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
