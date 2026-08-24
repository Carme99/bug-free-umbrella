<#
.SYNOPSIS
    Generates a user-device affinity report for Intune-managed users and their assigned devices.

.DESCRIPTION
    Reports on the relationships between users and their assigned devices by joining every
    Intune managed device with the Azure AD user inventory (with pagination over large tenants).
    Useful for license management, understanding device distribution, and identifying users
    with multiple devices or no devices at all. The script is read-only and safe to re-run.
    Exit codes:
    - 0: the affinity report was generated successfully.
    - 1: the report failed (Graph connection, data retrieval, or export error).

.PARAMETER TenantId
    Azure AD Tenant ID (optional, will prompt if not provided).

.PARAMETER OutputPath
    Path to save the report (default: current directory).

.PARAMETER Format
    Output format: HTML or CSV (default: HTML).

.PARAMETER ShowMultiDeviceUsers
    Show only users with multiple devices.

.PARAMETER ShowNoDeviceUsers
    Show users with no assigned devices.

.EXAMPLE
    PS C:\> .\Get-UserDeviceAffinity.ps1
    Generates an HTML user-device affinity report for all users in the current directory.

.EXAMPLE
    PS C:\> .\Get-UserDeviceAffinity.ps1 -ShowNoDeviceUsers -Format CSV -OutputPath C:\Reports
    Exports a CSV listing only users who have no assigned devices to C:\Reports.

.EXAMPLE
    PS C:\> .\Get-UserDeviceAffinity.ps1 -ShowMultiDeviceUsers
    Reports only on users who are assigned more than one device.

.NOTES
    File Name: Get-UserDeviceAffinity.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
    Permissions: DeviceManagementManagedDevices.Read.All, User.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".",

    [Parameter(Mandatory = $false)]
    [ValidateSet("HTML", "CSV")]
    [string]$Format = "HTML",

    [Parameter(Mandatory = $false)]
    [switch]$ShowMultiDeviceUsers,

    [Parameter(Mandatory = $false)]
    [switch]$ShowNoDeviceUsers
)

$ErrorActionPreference = 'Stop'

function Main {
    try {
        # Import helper module (kept inside Main so dot-sourcing executes nothing harmful).
        $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'IntuneGraphHelper.psm1'
        Import-Module $modulePath -Force -ErrorAction Stop

        Write-Host "[*] Connecting to Microsoft Graph..." -ForegroundColor Cyan
        Connect-IntuneGraph -TenantId $TenantId

        Write-Host "[*] Retrieving all managed devices..." -ForegroundColor Cyan
        $devices = Get-AllIntuneDevices

        Write-Host "[*] Retrieving all users..." -ForegroundColor Cyan
        $userFields = "id,displayName,userPrincipalName,accountEnabled,department,jobTitle"
        $usersUri = "https://graph.microsoft.com/v1.0/users?`$select=$userFields"
        $users = Invoke-MgGraphRequest -Uri $usersUri -Method GET -ErrorAction Stop
        $allUsers = @($users.value)

        # Handle pagination
        while ($users.'@odata.nextLink') {
            $users = Invoke-MgGraphRequest -Uri $users.'@odata.nextLink' -Method GET -ErrorAction Stop
            $allUsers += $users.value
        }

        Write-Host "[*] Analyzing user-device relationships..." -ForegroundColor Cyan

        # Group devices by user
        $userDeviceMap = @{}

        foreach ($device in $devices) {
            if ($device.userPrincipalName) {
                $upn = $device.userPrincipalName.ToLower()

                if (-not $userDeviceMap.ContainsKey($upn)) {
                    $userDeviceMap[$upn] = @{
                        Devices = @()
                        DeviceCount = 0
                    }
                }

                $userDeviceMap[$upn].Devices += [PSCustomObject]@{
                    DeviceName = $device.deviceName
                    OperatingSystem = $device.operatingSystem
                    OSVersion = $device.osVersion
                    Model = $device.model
                    SerialNumber = $device.serialNumber
                    ComplianceState = $device.complianceState
                    LastSyncDate = $device.lastSyncDateTime
                    EnrollmentDate = $device.enrolledDateTime
                }

                $userDeviceMap[$upn].DeviceCount++
            }
        }

        # Build affinity report
        $affinityReport = @()

        foreach ($user in $allUsers) {
            $upn = $user.userPrincipalName.ToLower()
            $deviceCount = 0
            $deviceList = ""
            $deviceDetails = @()

            if ($userDeviceMap.ContainsKey($upn)) {
                $deviceCount = $userDeviceMap[$upn].DeviceCount
                $deviceList = ($userDeviceMap[$upn].Devices | ForEach-Object { $_.DeviceName }) -join ", "
                $deviceDetails = $userDeviceMap[$upn].Devices
            }

            # Apply filters
            $includeInReport = $true

            if ($ShowMultiDeviceUsers -and $deviceCount -le 1) {
                $includeInReport = $false
            }

            if ($ShowNoDeviceUsers -and $deviceCount -gt 0) {
                $includeInReport = $false
            }

            if ($includeInReport) {
                $affinityReport += [PSCustomObject]@{
                    DisplayName = $user.displayName
                    UserPrincipalName = $user.userPrincipalName
                    AccountEnabled = $user.accountEnabled
                    Department = $user.department
                    JobTitle = $user.jobTitle
                    DeviceCount = $deviceCount
                    DeviceList = $deviceList
                    Devices = $deviceDetails
                }
            }
        }

        # Statistics
        $totalUsers = $affinityReport.Count
        $usersWithDevices = ($affinityReport | Where-Object { $_.DeviceCount -gt 0 }).Count
        $usersWithoutDevices = ($affinityReport | Where-Object { $_.DeviceCount -eq 0 }).Count
        $usersWithMultipleDevices = ($affinityReport | Where-Object { $_.DeviceCount -gt 1 }).Count
        $avgDevicesPerUser = if ($usersWithDevices -gt 0) {
            [math]::Round(($affinityReport |
                Where-Object { $_.DeviceCount -gt 0 } |
                Measure-Object -Property DeviceCount -Average).Average, 2)
        }
        else { 0 }

        Write-Host "`n[*] User-Device Affinity Summary:" -ForegroundColor Cyan
        Write-Host "  Total Users: $totalUsers"
        Write-Host "  Users with Devices: $usersWithDevices"
        Write-Host "  Users without Devices: $usersWithoutDevices"
        Write-Host "  Users with Multiple Devices: $usersWithMultipleDevices"
        Write-Host "  Average Devices per User: $avgDevicesPerUser"

        # Sort by device count (descending)
        $affinityReport = $affinityReport | Sort-Object DeviceCount -Descending

        # Generate report
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $reportPath = Join-Path $OutputPath "UserDeviceAffinity-$timestamp.$($Format.ToLower())"

        if ($Format -eq "CSV") {
            # Flatten device details for CSV
            $csvReport = $affinityReport | Select-Object DisplayName, UserPrincipalName,
                AccountEnabled, Department, JobTitle, DeviceCount, DeviceList
            $csvReport | Export-Csv -Path $reportPath -NoTypeInformation -ErrorAction Stop
        }
        else {
            # Create enhanced HTML report with device details
            $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>User-Device Affinity Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; }
        .summary { background-color: white; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .stat { display: inline-block; margin-right: 30px; }
        .stat-label { font-weight: bold; color: #666; }
        .stat-value { font-size: 24px; color: #0078d4; }
        table { border-collapse: collapse; width: 100%; background-color: white; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .device-details { margin-left: 20px; font-size: 0.9em; color: #666; }
    </style>
</head>
<body>
    <h1>User-Device Affinity Report</h1>
    <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>

    <div class="summary">
        <div class="stat">
            <div class="stat-label">Total Users</div>
            <div class="stat-value">$totalUsers</div>
        </div>
        <div class="stat">
            <div class="stat-label">With Devices</div>
            <div class="stat-value">$usersWithDevices</div>
        </div>
        <div class="stat">
            <div class="stat-label">Without Devices</div>
            <div class="stat-value">$usersWithoutDevices</div>
        </div>
        <div class="stat">
            <div class="stat-label">Multiple Devices</div>
            <div class="stat-value">$usersWithMultipleDevices</div>
        </div>
        <div class="stat">
            <div class="stat-label">Avg Devices/User</div>
            <div class="stat-value">$avgDevicesPerUser</div>
        </div>
    </div>

    <table>
        <tr>
            <th>User</th>
            <th>Email</th>
            <th>Department</th>
            <th>Device Count</th>
            <th>Devices</th>
        </tr>
"@

        foreach ($item in $affinityReport) {
            $htmlContent += @"
        <tr>
            <td>$($item.DisplayName)</td>
            <td>$($item.UserPrincipalName)</td>
            <td>$($item.Department)</td>
            <td>$($item.DeviceCount)</td>
            <td>$($item.DeviceList)</td>
        </tr>
"@
        }

        $htmlContent += @"
    </table>
</body>
</html>
"@

        $htmlContent | Out-File -FilePath $reportPath -Encoding ([System.Text.Encoding]::UTF8) -ErrorAction Stop
        }

        Write-Host "`n[+] Report generated successfully:" -ForegroundColor Green
        Write-Host "   $reportPath" -ForegroundColor Cyan
        return 0
    }
    catch {
        Write-Host "[-] Error generating user-device affinity report: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
