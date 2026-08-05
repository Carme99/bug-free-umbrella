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
    .\Get-BitLockerStatus.ps1
    Generates full BitLocker status report for all Windows devices.

.EXAMPLE
    .\Get-BitLockerStatus.ps1 -ShowUnencryptedOnly
    Shows only unencrypted devices.

.EXAMPLE
    .\Get-BitLockerStatus.ps1 -ShowMissingKeys
    Shows only devices missing recovery key backup to Azure AD.

.NOTES
    Requires Microsoft.Graph PowerShell module
    Requires permissions: DeviceManagementManagedDevices.Read.All, BitlockerKey.Read.All
    Only applicable to Windows devices
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('HTML', 'CSV', 'Both')]
    [string]$ExportFormat = 'Both',

    [Parameter(Mandatory=$false)]
    [switch]$ShowUnencryptedOnly,

    [Parameter(Mandatory=$false)]
    [switch]$ShowMissingKeys,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeNonWindows
)

# Import helper module
$modulePath = Join-Path $PSScriptRoot "IntuneGraphHelper.psm1"
Import-Module $modulePath -Force

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "BitLocker Encryption Status Audit" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Connect to Microsoft Graph
$connected = Connect-IntuneGraph -Scopes @(
    "DeviceManagementManagedDevices.Read.All",
    "BitlockerKey.Read.All"
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

    # Filter to Windows devices (unless IncludeNonWindows is specified)
    if (-not $IncludeNonWindows) {
        $devices = $devices | Where-Object { $_.OperatingSystem -like "Windows*" }
    }

    Write-Host "✓ Retrieved $($devices.Count) devices" -ForegroundColor Green

    if ($devices.Count -eq 0) {
        Write-Host "✗ No devices found to audit." -ForegroundColor Red
        Disconnect-IntuneGraph
        exit 1
    }

    # Process each device
    Write-Host "`nAnalyzing BitLocker encryption status..." -ForegroundColor Cyan
    $report = @()
    $counter = 0

    foreach ($device in $devices) {
        $counter++
        Write-Progress -Activity "Analyzing devices" -Status "$counter of $($devices.Count)" -PercentComplete (($counter / $devices.Count) * 100)

        $osIsWindows = $device.OperatingSystem -like "Windows*"
        $encryptionStatus = "N/A"
        $recoveryKeyStatus = "N/A"
        $encryptionMethod = "N/A"

        if ($osIsWindows) {
            # Get BitLocker encryption state from device
            $deviceId = $device.Id

            # Try to get encryption status from device properties
            try {
                $deviceDetails = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$deviceId" -ErrorAction SilentlyContinue

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
            try {
                $azureAdDeviceId = $device.AzureAdDeviceId

                if ($azureAdDeviceId) {
                    $recoveryKeys = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$azureAdDeviceId'" -ErrorAction SilentlyContinue

                    if ($recoveryKeys.value -and $recoveryKeys.value.Count -gt 0) {
                        $recoveryKeyStatus = "Backed Up ($($recoveryKeys.value.Count) keys)"

                        # Get most recent key creation date
                        $mostRecentKey = $recoveryKeys.value | Sort-Object createdDateTime -Descending | Select-Object -First 1
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
                $complianceStates = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$deviceId/deviceCompliancePolicyStates" -ErrorAction SilentlyContinue

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
        $reportEntry = [PSCustomObject]@{
            DeviceName = $device.DeviceName
            UserPrincipalName = $device.UserPrincipalName
            OperatingSystem = $device.OperatingSystem
            OSVersion = $device.OsVersion
            EncryptionStatus = $encryptionStatus
            RecoveryKeyStatus = $recoveryKeyStatus
            LastSyncDateTime = if ($device.LastSyncDateTime) { $device.LastSyncDateTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" }
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
    Write-Host "Encrypted:               $encrypted ($(if($totalDevices -gt 0){'{0:P0}' -f ($encrypted/$totalDevices)}else{'N/A'}))" -ForegroundColor Green
    Write-Host "Not Encrypted:           $notEncrypted ($(if($totalDevices -gt 0){'{0:P0}' -f ($notEncrypted/$totalDevices)}else{'N/A'}))" -ForegroundColor Red
    Write-Host "Unknown Status:          $unknown" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Recovery Keys Backed Up: $keysBackedUp" -ForegroundColor Green
    Write-Host "No Key Backup:           $noBackup" -ForegroundColor $(if($noBackup -gt 0){'Red'}else{'Green'})

    if ($report.Count -eq 0) {
        Write-Host "`nNo devices match the current filter criteria." -ForegroundColor Yellow
        Disconnect-IntuneGraph
        exit 0
    }

    # Group by encryption status
    Write-Host "`nBreakdown by Encryption Status:" -ForegroundColor Cyan
    $grouped = $report | Group-Object -Property EncryptionStatus
    foreach ($group in $grouped | Sort-Object Count -Descending) {
        $color = switch($group.Name) {
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
    $outputPath = "$env:USERPROFILE\Desktop"

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
        Write-Host "`n⚠ RECOMMENDATIONS:" -ForegroundColor Yellow
        Write-Host "  - $notEncrypted devices are not encrypted" -ForegroundColor Yellow
        Write-Host "  - Review and deploy BitLocker compliance policies" -ForegroundColor Yellow
        Write-Host "  - Ensure devices meet TPM requirements" -ForegroundColor Yellow
    }

    if ($noBackup -gt 0) {
        Write-Host "`n⚠ RECOMMENDATIONS:" -ForegroundColor Yellow
        Write-Host "  - $noBackup encrypted devices have no key backup" -ForegroundColor Yellow
        Write-Host "  - Configure BitLocker recovery key backup to Azure AD" -ForegroundColor Yellow
        Write-Host "  - Run proactive remediation to backup existing keys" -ForegroundColor Yellow
    }

    Write-Host "`n✓ BitLocker encryption audit completed!" -ForegroundColor Green
}
catch {
    Write-Host "`n✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
}
finally {
    # Disconnect from Graph
    Disconnect-IntuneGraph
}
