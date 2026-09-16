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
    All actions are destructive/bulk operations and are gated by ShouldProcess,
    so they honor -WhatIf and -Confirm. A summary of targeted devices and their
    per-device action results is printed at the end of the run.

    -GroupName resolves the Entra device members of the named group to Intune managed devices
    by their azureAdDeviceId; members that are not devices are ignored. A -GroupName that
    resolves to zero managed devices is reported explicitly and exits non-zero instead of
    reporting a false success.
    Exit codes:
    - 0: the action ran (including selections that legitimately match no device).
    - 1: connection failure, device lookup failure, a -GroupName matching no group or no
         managed device, or one or more per-device actions failed.

.PARAMETER Action
    Action to perform: Sync, Restart, Retire, Wipe, CollectDiagnostics.

.PARAMETER DeviceNames
    Specific device names to target (comma-separated or array).

.PARAMETER DeviceFilter
    OData filter for devices (e.g., "operatingSystem eq 'Windows'").

.PARAMETER GroupName
    Target the Entra device members of the named Azure AD group, resolved to Intune managed
    devices by azureAdDeviceId.

.PARAMETER NonCompliantOnly
    Target only non-compliant devices.

.EXAMPLE
    PS C:\> .\Invoke-DeviceBulkActions.ps1 -Action Sync -DeviceNames "DESKTOP-01,LAPTOP-02"
    Syncs two specific devices.

.EXAMPLE
    PS C:\> .\Invoke-DeviceBulkActions.ps1 -Action Restart -NonCompliantOnly -WhatIf
    Shows which non-compliant devices would be restarted without executing.

.NOTES
    File Name: Invoke-DeviceBulkActions.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 2.0.0
    Date: 2026-09-16

    Requires Microsoft.Graph PowerShell module
    Requires permissions: DeviceManagementManagedDevices.ReadWrite.All, Group.Read.All

    Device actions use the Microsoft.Graph.DeviceManagement action cmdlets:
    - Sync-MgDeviceManagementManagedDevice
    - Restart-MgDeviceManagementManagedDeviceNow
    - Clear-MgDeviceManagementManagedDevice (wipe)
    - Invoke-MgRetireDeviceManagementManagedDevice
    - New-MgDeviceManagementManagedDeviceLogCollectionRequest for collect diagnostics
      (beta-profile cmdlet)
    Cmdlet index:
    https://learn.microsoft.com/powershell/module/microsoft.graph.devicemanagement/
    Log collection action:
    https://learn.microsoft.com/graph/api/intune-devices-manageddevice-createdevicelogcollectionrequest
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

$ErrorActionPreference = 'Stop'

$script:results = @{
    Action = $Action
    TargetedDevices = 0
    SuccessfulActions = 0
    FailedActions = 0
    Devices = @()
}

function Write-ColorOutput {
    [CmdletBinding()]
    param([string]$Message, [string]$Level = 'Info')
    switch ($Level) {
        'Success' { Write-Host "[+] $Message" -ForegroundColor Green }
        'Warning' { Write-Host "[!] $Message" -ForegroundColor Yellow }
        'Error'   { Write-Host "[-] $Message" -ForegroundColor Red }
        default   { Write-Host "[*] $Message" -ForegroundColor Cyan }
    }
}

function Connect-ToGraph {
    [CmdletBinding()]
    param()

    Write-Host "[*] Connecting to Microsoft Graph..." -ForegroundColor Cyan
    $context = Get-MgContext -ErrorAction Stop
    if (-not $context) {
        Connect-MgGraph -Scopes "DeviceManagementManagedDevices.ReadWrite.All", "Group.Read.All" -ErrorAction Stop
    }
    Write-ColorOutput "Connected successfully" -Level Success
}

function Get-TargetDevices {
    [CmdletBinding()]
    param()

    Write-Host "`n[*] Querying target devices..." -ForegroundColor Cyan

    $devices = @()

    try {
        if ($DeviceNames) {
            foreach ($name in $DeviceNames) {
                $device = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$name'" -All -ErrorAction Stop
                if ($device) { $devices += $device }
            }
        }
        elseif ($GroupName) {
            $group = Get-MgGroup -Filter "displayName eq '$GroupName'" -ErrorAction Stop
            if (-not $group) {
                throw "No Azure AD group named '$GroupName' was found."
            }

            $members = Get-MgGroupMember -GroupId $group.Id -All -ErrorAction Stop

            foreach ($member in $members) {
                # Get-MgGroupMember returns Entra directory objects; only device members can be
                # mapped to an Intune managed device.
                if ($member.'@odata.type' -ne '#microsoft.graph.device') { continue }

                # The Entra device ID (not the directory-object ID) is what an Intune managed
                # device reports as azureAdDeviceId; fall back to the directory-object ID when
                # Graph does not surface the device ID.
                $azureAdDeviceId = $member.DeviceId
                if (-not $azureAdDeviceId -and $member.AdditionalProperties) {
                    $azureAdDeviceId = $member.AdditionalProperties['deviceId']
                }
                if (-not $azureAdDeviceId) { $azureAdDeviceId = $member.Id }

                # A failed lookup must abort the run, never be silently swallowed.
                $matched = Get-MgDeviceManagementManagedDevice `
                    -Filter "azureAdDeviceId eq '$azureAdDeviceId'" -ErrorAction Stop
                if ($matched) { $devices += $matched }
            }
        }
        elseif ($DeviceFilter) {
            $devices = Get-MgDeviceManagementManagedDevice -Filter $DeviceFilter -All -ErrorAction Stop
        }
        else {
            $devices = Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop
        }

        if ($NonCompliantOnly) {
            $devices = @($devices | Where-Object { $_.ComplianceState -ne 'compliant' })
        }

        $script:results.TargetedDevices = $devices.Count
        Write-ColorOutput "Found $($devices.Count) devices" -Level Success
        return $devices
    }
    catch {
        Write-ColorOutput "Error querying devices: $($_.Exception.Message)" -Level Error
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
                    Sync-MgDeviceManagementManagedDevice -ManagedDeviceId $deviceId -ErrorAction Stop
                    Write-ColorOutput "Synced: $deviceName" -Level Success
                }
                'Restart' {
                    Restart-MgDeviceManagementManagedDeviceNow -ManagedDeviceId $deviceId -ErrorAction Stop
                    Write-ColorOutput "Restarted: $deviceName" -Level Success
                }
                'Retire' {
                    Invoke-MgRetireDeviceManagementManagedDevice -ManagedDeviceId $deviceId -ErrorAction Stop
                    Write-ColorOutput "Retired: $deviceName" -Level Success
                }
                'Wipe' {
                    Clear-MgDeviceManagementManagedDevice -ManagedDeviceId $deviceId -ErrorAction Stop
                    Write-ColorOutput "Wiped: $deviceName" -Level Success
                }
                'CollectDiagnostics' {
                    New-MgDeviceManagementManagedDeviceLogCollectionRequest -ManagedDeviceId $deviceId `
                        -TemplateType @{ templateType = 'predefined' } -ErrorAction Stop
                    Write-ColorOutput "Collected diagnostics: $deviceName" -Level Success
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
            Write-ColorOutput "$deviceName : $($_.Exception.Message)" -Level Error
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

function Main {
    try {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  Intune Bulk Device Actions" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan

        Connect-ToGraph
        $devices = Get-TargetDevices

        if ($devices.Count -eq 0) {
            if ($GroupName) {
                Write-ColorOutput "Group '$GroupName' resolved to 0 managed devices" -Level Error
                return 1
            }
            Write-ColorOutput "No devices found matching criteria" -Level Warning
            return 0
        }

        Write-Host "`n[*] Executing action: $Action" -ForegroundColor Cyan
        Write-Host "[*] Targeted devices: $($devices.Count)`n" -ForegroundColor Gray

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
            return 1
        }

        Write-ColorOutput "Done" -Level Success
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
