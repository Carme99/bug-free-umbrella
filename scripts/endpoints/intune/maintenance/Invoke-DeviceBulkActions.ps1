<#
.SYNOPSIS
    Performs bulk actions on Intune-managed devices.

.DESCRIPTION
    Executes bulk operations on devices:
    - Sync devices with Intune
    - Restart devices
    - Retire devices
    - Wipe devices
    - Collect diagnostics
    - Update primary user
    - Filter by device name, OS, group, or compliance status

.PARAMETER Action
    Action to perform: Sync, Restart, Retire, Wipe, CollectDiagnostics.

.PARAMETER DeviceNames
    Specific device names to target (comma-separated or array).

.PARAMETER DeviceFilter
    OData filter for devices (e.g., "operatingSystem eq 'Windows'").

.PARAMETER GroupName
    Target devices in specific Azure AD group.

.PARAMETER NonCompliantOnly
    Target only non-compliant devices.

.PARAMETER WhatIf
    Show what would be done without executing.

.PARAMETER Confirm
    Prompt for confirmation before each action.

.EXAMPLE
    .\Invoke-DeviceBulkActions.ps1 -Action Sync -DeviceNames "DESKTOP-01,LAPTOP-02"
    Syncs two specific devices.

.EXAMPLE
    .\Invoke-DeviceBulkActions.ps1 -Action Restart -NonCompliantOnly -WhatIf
    Shows which non-compliant devices would be restarted.

.EXAMPLE
    .\Invoke-DeviceBulkActions.ps1 -Action CollectDiagnostics -GroupName "IT-TestDevices"
    Collects diagnostics from all devices in group.

.NOTES
    Requires Microsoft.Graph PowerShell module
    Requires permissions: DeviceManagementManagedDevices.ReadWrite.All
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Sync', 'Restart', 'Retire', 'Wipe', 'CollectDiagnostics')]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [string[]]$DeviceNames,

    [Parameter(Mandatory = $false)]
    [string]$DeviceFilter,

    [Parameter(Mandatory = $false)]
    [string]$GroupName,

    [Parameter(Mandatory = $false)]
    [switch]$NonCompliantOnly
)

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement

$script:results = @{
    Action = $Action
    TargetedDevices = 0
    SuccessfulActions = 0
    FailedActions = 0
    Devices = @()
}

function Write-ColorOutput {
    param([string]$Message, [string]$Level = 'Info')
    $color = switch ($Level) { 'Success' { 'Green' } 'Warning' { 'Yellow' } 'Error' { 'Red' } default { 'Cyan' } }
    Write-Host $Message -ForegroundColor $color
}

function Connect-ToGraph {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    try {
        $context = Get-MgContext
        if (-not $context) {
            Connect-MgGraph -Scopes "DeviceManagementManagedDevices.ReadWrite.All", "Group.Read.All"
        }
        Write-ColorOutput "  Connected successfully" -Level Success
    }
    catch {
        Write-ColorOutput "  Failed to connect: $($_.Exception.Message)" -Level Error
        exit 1
    }
}

function Get-TargetDevices {
    Write-Host "`nQuerying target devices..." -ForegroundColor Cyan
    
    $devices = @()
    
    try {
        if ($DeviceNames) {
            foreach ($name in $DeviceNames) {
                $device = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$name'" -All
                if ($device) { $devices += $device }
            }
        }
        elseif ($GroupName) {
            $group = Get-MgGroup -Filter "displayName eq '$GroupName'"
            if ($group) {
                $members = Get-MgGroupMember -GroupId $group.Id -All
                foreach ($member in $members) {
                    $device = Get-MgDeviceManagementManagedDevice -ManagedDeviceId $member.Id -ErrorAction SilentlyContinue
                    if ($device) { $devices += $device }
                }
            }
        }
        elseif ($DeviceFilter) {
            $devices = Get-MgDeviceManagementManagedDevice -Filter $DeviceFilter -All
        }
        else {
            $devices = Get-MgDeviceManagementManagedDevice -All
        }

        if ($NonCompliantOnly) {
            $devices = $devices | Where-Object { $_.ComplianceState -ne 'compliant' }
        }

        $script:results.TargetedDevices = $devices.Count
        Write-ColorOutput "  Found $($devices.Count) devices" -Level Success
        return $devices
    }
    catch {
        Write-ColorOutput "  Error querying devices: $($_.Exception.Message)" -Level Error
        return @()
    }
}

function Invoke-DeviceAction {
    [CmdletBinding(SupportsShouldProcess)]
    param($Device)
    
    $deviceName = $Device.DeviceName
    $deviceId = $Device.Id

    if ($PSCmdlet.ShouldProcess($deviceName, $Action)) {
        try {
            switch ($Action) {
                'Sync' {
                    Invoke-MgSyncDeviceManagementManagedDevice -ManagedDeviceId $deviceId
                    Write-ColorOutput "  [OK] Synced: $deviceName" -Level Success
                }
                'Restart' {
                    Invoke-MgRestartDeviceManagementManagedDevice -ManagedDeviceId $deviceId
                    Write-ColorOutput "  [OK] Restarted: $deviceName" -Level Success
                }
                'Retire' {
                    Invoke-MgRetireDeviceManagementManagedDevice -ManagedDeviceId $deviceId
                    Write-ColorOutput "  [OK] Retired: $deviceName" -Level Success
                }
                'Wipe' {
                    Invoke-MgWipeDeviceManagementManagedDevice -ManagedDeviceId $deviceId
                    Write-ColorOutput "  [OK] Wiped: $deviceName" -Level Success
                }
                'CollectDiagnostics' {
                    Invoke-MgCollectDeviceManagementManagedDeviceDiagnostic -ManagedDeviceId $deviceId
                    Write-ColorOutput "  [OK] Collected diagnostics: $deviceName" -Level Success
                }
            }
            
            $script:results.SuccessfulActions++
            $script:results.Devices += [PSCustomObject]@{
                DeviceName = $deviceName
                Action = $Action
                Status = "Success"
                Timestamp = Get-Date
            }
        }
        catch {
            Write-ColorOutput "  [FAIL] $deviceName : $($_.Exception.Message)" -Level Error
            $script:results.FailedActions++
            $script:results.Devices += [PSCustomObject]@{
                DeviceName = $deviceName
                Action = $Action
                Status = "Failed"
                Error = $_.Exception.Message
                Timestamp = Get-Date
            }
        }
    }
}

# Main execution
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Intune Bulk Device Actions" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Connect-ToGraph
$devices = Get-TargetDevices

if ($devices.Count -eq 0) {
    Write-ColorOutput "No devices found matching criteria" -Level Warning
    exit 0
}

Write-Host "`nExecuting action: $Action" -ForegroundColor Cyan
Write-Host "Targeted devices: $($devices.Count)`n" -ForegroundColor Gray

foreach ($device in $devices) {
    Invoke-DeviceAction -Device $device
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Bulk Action Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Action: $Action"
Write-Host "Targeted: $($script:results.TargetedDevices)"
Write-ColorOutput "Successful: $($script:results.SuccessfulActions)" -Level Success
if ($script:results.FailedActions -gt 0) {
    Write-ColorOutput "Failed: $($script:results.FailedActions)" -Level Error
}
Write-Host "`n========================================`n" -ForegroundColor Cyan
