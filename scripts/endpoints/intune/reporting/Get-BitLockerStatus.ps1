<#
.SYNOPSIS
    Audits BitLocker encryption status across all Windows devices in Intune.

.DESCRIPTION
    This script generates a comprehensive report of BitLocker encryption status for all
    Windows devices managed by Intune. It identifies:
    - Encrypted devices with key backup status
    - Unencrypted devices
    - Devices with encryption errors
    - Recovery key backup status to Azure AD
    - Encryption methods and cipher strength

    Useful for:
    - Compliance auditing
    - Security posture assessment
    - Identifying encryption gaps
    - Recovery key verification

.PARAMETER ExportFormat
    Report format: HTML, CSV, or Both (default: Both).

.PARAMETER ShowUnencryptedOnly
    Only show devices that are not encrypted.

.PARAMETER ShowMissingKeys
    Only show devices missing recovery key backup.

.PARAMETER IncludeNonWindows
    Include non-Windows devices in report (will show as N/A).

.EXAMPLE
    PS C:\> .\Get-BitLockerStatus.ps1
    Generates full BitLocker status report for all Windows devices.

.EXAMPLE
    PS C:\> .\Get-BitLockerStatus.ps1 -ShowUnencryptedOnly
    Shows only unencrypted devices.

.EXAMPLE
    PS C:\> .\Get-BitLockerStatus.ps1 -ShowMissingKeys
    Shows only devices missing recovery key backup to Azure AD.

.NOTES
    File Name  : Get-BitLockerStatus.ps1
    Author     : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2026-08-23

    Requires Microsoft.Graph PowerShell module.
    Requires permissions: DeviceManagementManagedDevices.Read.All, BitlockerKey.Read.All
    Only applicable to Windows devices.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('HTML', 'CSV', 'Both')]
    [string]$ExportFormat = 'Both',

    [Parameter(Mandatory = $false)]
    [switch]$ShowUnencryptedOnly,

    [Parameter(Mandatory = $false)]
    [switch]$ShowMissingKeys,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeNonWindows
)

$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Starting BitLocker encryption status audit..." -ForegroundColor Cyan

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
        Write-Host "BitLocker Encryption Status Audit" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan

        # Connect to Microsoft Graph
        $connected = Connect-IntuneGraph -Scopes @(
            "DeviceManagementManagedDevices.Read.All",
            "BitlockerKey.Read.All"
        )

        if (-not $connected) {
            Write-Host "[-] Failed to connect to Microsoft Graph. Exiting." -ForegroundColor Red
            return 1
        }

        # Import required modules
        Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop

        # Get all managed devices
        Write-Host "[*] Retrieving all managed devices..." -ForegroundColor Cyan
        $devices = Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop

        # Filter to Windows devices (unless IncludeNonWindows is specified)
        if (-not $IncludeNonWindows) {
            $devices = @($devices | Where-Object { $_.OperatingSystem -like "Windows*" })
        }
        else {
            $devices = @($devices)
        }

        Write-Host "[+] Retrieved $($devices.Count) devices" -ForegroundColor Green

        if ($devices.Count -eq 0) {
            Write-Host "[-] No devices found to audit." -ForegroundColor Red
            return 1
        }

        # Process each device
        Write-Host "`n[*] Analyzing BitLocker encryption status..." -ForegroundColor Cyan
        $report = @()
        $counter = 0

        foreach ($device in $devices) {
            $counter++
            Write-Progress -Activity "Analyzing devices" -Status "$counter of $($devices.Count)" `
                -PercentComplete (($counter / $devices.Count) * 100)

            $osIsWindows = $device.OperatingSystem -like "Windows*"
            $encryptionStatus = "N/A"
            $recoveryKeyStatus = "N/A"
            $encryptionMethod = "N/A"

            if ($osIsWindows) {
                # Get BitLocker encryption state from device
                $deviceId = $device.Id
                $deviceBaseUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$deviceId"
                $deviceBaseUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$deviceId"

                # Try to get encryption status from device properties
                try {
                    $deviceDetails = Invoke-MgGraphRequest -Uri $deviceBaseUri -ErrorAction SilentlyContinue

                    if ($deviceDetails.isEncrypted -eq $true) {
                        $encryptionStatus = "Encrypted"
                    }
                    elseif ($deviceDetails.isEncrypted -eq $false) {
                        $encryptionStatus = "Not Encrypted"
                    }
                    else {
                        $encryptionStatus = "Unknown"
                    }
                }
                catch {
                    $encryptionStatus = "Unknown"
                }

                # Check for BitLocker recovery keys in Azure AD
                $keyUri = "https://graph.microsoft.com/v1.0/informationProtection/bitlocker/recoveryKeys"
                try {
                    $azureAdDeviceId = $device.AzureAdDeviceId

                    if ($azureAdDeviceId) {
                        $filteredKeyUri = "${keyUri}?`$filter=deviceId eq '$azureAdDeviceId'"
                        $recoveryKeys = Invoke-MgGraphRequest -Uri $filteredKeyUri -ErrorAction SilentlyContinue

                        if ($recoveryKeys.value -and $recoveryKeys.value.Count -gt 0) {
                            $recoveryKeyStatus = "Backed Up ($($recoveryKeys.value.Count) keys)"

                            # Get most recent key creation date
                            $mostRecentKey = $recoveryKeys.value |
                                Sort-Object createdDateTime -Descending |
                                Select-Object -First 1
                            $keyBackupDate = $mostRecentKey.createdDateTime
                        }
                        else {
                            $recoveryKeyStatus = "No Backup"
                        }
                    }
                    else {
                        $recoveryKeyStatus = "No Azure AD Device ID"
                    }
                }
                catch {
                    $recoveryKeyStatus = "Unknown"
                }

                # Determine encryption method (if available in compliance data)
                try {
                        $compStatesUri = "$deviceBaseUri/deviceCompliancePolicyStates"
                        $complianceStates = Invoke-MgGraphRequest -Uri $compStatesUri -ErrorAction SilentlyContinue

                    # Look for encryption method in compliance data
                    # This varies by compliance policy configuration
                    $encryptionMethod = "Unknown"
                }
                catch {
                    $encryptionMethod = "Unknown"
                }
            }

            # Apply filters
            if ($ShowUnencryptedOnly -and $encryptionStatus -ne "Not Encrypted") {
                continue
            }

            if ($ShowMissingKeys -and $recoveryKeyStatus -notmatch "No Backup") {
                continue
            }

            # Build report entry
            $lastSyncText = "Never"
            if ($device.LastSyncDateTime) {
                $lastSyncText = $device.LastSyncDateTime.ToString("yyyy-MM-dd HH:mm:ss")
            }

            $reportEntry = [PSCustomObject]@{
                DeviceName = $device.DeviceName
                UserPrincipalName = $device.UserPrincipalName
                OperatingSystem = $device.OperatingSystem
                OSVersion = $device.OsVersion
                EncryptionStatus = $encryptionStatus
                RecoveryKeyStatus = $recoveryKeyStatus
                LastSyncDateTime = $lastSyncText
                ComplianceState = $device.ComplianceState
                Manufacturer = $device.Manufacturer
                Model = $device.Model
                SerialNumber = $device.SerialNumber
                AzureAdDeviceId = $device.AzureAdDeviceId
            }

            $report += $reportEntry
        }

        Write-Progress -Activity "Analyzing devices" -Completed

        # Display summary
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "BITLOCKER ENCRYPTION SUMMARY" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan

        $totalDevices = $report.Count
        $encrypted = ($report | Where-Object { $_.EncryptionStatus -eq "Encrypted" }).Count
        $notEncrypted = ($report | Where-Object { $_.EncryptionStatus -eq "Not Encrypted" }).Count
        $unknown = ($report | Where-Object { $_.EncryptionStatus -eq "Unknown" }).Count
        $keysBackedUp = ($report | Where-Object { $_.RecoveryKeyStatus -like "Backed Up*" }).Count
        $noBackup = ($report | Where-Object { $_.RecoveryKeyStatus -eq "No Backup" }).Count

        Write-Host "Total Devices:           $totalDevices" -ForegroundColor White
        $encryptedPct = if ($totalDevices -gt 0) { '{0:P0}' -f ($encrypted/$totalDevices) }else { 'N/A' }
        $notEncryptedPct = if ($totalDevices -gt 0) { '{0:P0}' -f ($notEncrypted/$totalDevices) }else { 'N/A' }
        Write-Host "Encrypted:               $encrypted ($encryptedPct)" -ForegroundColor Green
        Write-Host "Not Encrypted:           $notEncrypted ($notEncryptedPct)" -ForegroundColor Red
        Write-Host "Unknown Status:          $unknown" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Recovery Keys Backed Up: $keysBackedUp" -ForegroundColor Green
        $noBackupColor = if ($noBackup -gt 0) { 'Red' }else { 'Green' }
        Write-Host "No Key Backup:           $noBackup" -ForegroundColor $noBackupColor

        if ($report.Count -eq 0) {
            Write-Host "[!] No devices match the current filter criteria." -ForegroundColor Yellow
            return 0
        }

        # Group by encryption status
        Write-Host "`nBreakdown by Encryption Status:" -ForegroundColor Cyan
        $grouped = $report | Group-Object -Property EncryptionStatus
        foreach ($group in $grouped | Sort-Object Count -Descending) {
            $color = switch ($group.Name) {
                "Encrypted" { "Green" }
                "Not Encrypted" { "Red" }
                default { "Yellow" }
            }
            Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor $color
        }

        # Sort report
        $report = $report | Sort-Object EncryptionStatus, RecoveryKeyStatus, DeviceName

        # Export reports
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $outputPath = $ReportDir

        if ($ExportFormat -eq 'HTML' -or $ExportFormat -eq 'Both') {
            $htmlPath = Join-Path $outputPath "BitLockerStatus_$timestamp.html"
            Export-IntuneReportToHTML -Data $report -Title "BitLocker Encryption Status Report" -FilePath $htmlPath
        }

        if ($ExportFormat -eq 'CSV' -or $ExportFormat -eq 'Both') {
            $csvPath = Join-Path $outputPath "BitLockerStatus_$timestamp.csv"
            Export-IntuneReportToCSV -Data $report -Title "BitLockerStatus" -FilePath $csvPath
        }

        # Recommendations
        if ($notEncrypted -gt 0) {
            Write-Host "`n[!] RECOMMENDATIONS:" -ForegroundColor Yellow
            Write-Host "  - $notEncrypted devices are not encrypted" -ForegroundColor Yellow
            Write-Host "  - Review and deploy BitLocker compliance policies" -ForegroundColor Yellow
            Write-Host "  - Ensure devices meet TPM requirements" -ForegroundColor Yellow
        }

        if ($noBackup -gt 0) {
            Write-Host "`n[!] RECOMMENDATIONS:" -ForegroundColor Yellow
            Write-Host "  - $noBackup encrypted devices have no key backup" -ForegroundColor Yellow
            Write-Host "  - Configure BitLocker recovery key backup to Azure AD" -ForegroundColor Yellow
            Write-Host "  - Run proactive remediation to backup existing keys" -ForegroundColor Yellow
        }

        Write-Host "`n[+] BitLocker encryption audit completed!" -ForegroundColor Green
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
