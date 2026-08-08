<#
.SYNOPSIS
    Syncs users' primary Intune devices from a user group to a device group.

.DESCRIPTION
    This script takes a source Entra ID user group and finds each user's primary device in Intune,
    then adds those devices to a target device group. It performs a full sync, meaning devices
    of users no longer in the source group will be removed from the target group.

.PARAMETER SourceGroupName
    The name of the Entra ID user group containing users whose devices should be synced.

.PARAMETER TargetGroupName
    The name of the Entra ID device group where primary devices should be added.

.EXAMPLE
    .\Sync-UserGroupToPrimaryDeviceGroup.ps1

.NOTES
    Requires Microsoft.Graph PowerShell modules.
    Run with appropriate permissions: Group.Read.All, Device.Read.All, GroupMember.ReadWrite.All, DeviceManagementManagedDevices.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$TargetGroupName
)

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.Devices.CorporateManagement

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Function to get primary device for a user
function Get-UserPrimaryDevice {
    param(
        [string]$UserId,
        [string]$UserPrincipalName
    )

    try {
        # Get all managed devices for the user
        $devices = Get-MgUserManagedDevice -UserId $UserId -All -ErrorAction Stop

        if ($devices.Count -eq 0) {
            Write-ColorOutput "  └─ No devices found in Intune" "Yellow"
            return $null
        }

        # First, try to find device marked as primary
        $primaryDevice = $devices | Where-Object { $_.IsManaged -eq $true } | Select-Object -First 1

        if ($devices.Count -eq 1) {
            Write-ColorOutput "  └─ Found 1 device: $($devices[0].DeviceName)" "Green"
            return $devices[0]
        }

        # Multiple devices - let admin choose
        Write-ColorOutput "  └─ Found $($devices.Count) devices. Please select one:" "Yellow"

        for ($i = 0; $i -lt $devices.Count; $i++) {
            $device = $devices[$i]
            $lastSync = if ($device.LastSyncDateTime) { $device.LastSyncDateTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" }
            Write-Host "     [$($i + 1)] $($device.DeviceName) - OS: $($device.OperatingSystem) - Last Check-in: $lastSync"
        }

        do {
            $selection = Read-Host "     Enter selection (1-$($devices.Count))"
            $selectionNum = 0
            $validSelection = [int]::TryParse($selection, [ref]$selectionNum) -and $selectionNum -ge 1 -and $selectionNum -le $devices.Count
        } while (-not $validSelection)

        $selectedDevice = $devices[$selectionNum - 1]
        Write-ColorOutput "     Selected: $($selectedDevice.DeviceName)" "Green"

        return $selectedDevice

    }
    catch {
        Write-ColorOutput "  └─ Error getting devices: $($_.Exception.Message)" "Red"
        return $null
    }
}

# Main script
try {
    Write-ColorOutput "`n=== Intune Device Group Sync Script ===" "Cyan"
    Write-ColorOutput "This script syncs users' primary devices to a device group.`n" "Cyan"

    # Connect to Microsoft Graph
    Write-ColorOutput "Connecting to Microsoft Graph..." "Yellow"
    $requiredScopes = @(
        "Group.Read.All",
        "Device.Read.All",
        "GroupMember.ReadWrite.All",
        "DeviceManagementManagedDevices.Read.All"
    )

    Connect-MgGraph -Scopes $requiredScopes -NoWelcome
    Write-ColorOutput "Connected successfully!`n" "Green"

    # Get source group name if not provided
    if (-not $SourceGroupName) {
        $SourceGroupName = Read-Host "Enter the name of the SOURCE user group"
    }

    # Get target group name if not provided
    if (-not $TargetGroupName) {
        $TargetGroupName = Read-Host "Enter the name of the TARGET device group"
    }

    Write-ColorOutput "`nLooking up groups..." "Yellow"

    # Get source user group
    $sourceGroup = Get-MgGroup -Filter "displayName eq '$SourceGroupName'" -ErrorAction Stop
    if (-not $sourceGroup) {
        throw "Source group '$SourceGroupName' not found"
    }
    Write-ColorOutput "✓ Source group found: $($sourceGroup.DisplayName) (ID: $($sourceGroup.Id))" "Green"

    # Get target device group
    $targetGroup = Get-MgGroup -Filter "displayName eq '$TargetGroupName'" -ErrorAction Stop
    if (-not $targetGroup) {
        throw "Target group '$TargetGroupName' not found"
    }
    Write-ColorOutput "✓ Target group found: $($targetGroup.DisplayName) (ID: $($targetGroup.Id))`n" "Green"

    # Get all members from source user group
    Write-ColorOutput "Getting members from source group..." "Yellow"
    $sourceMembers = Get-MgGroupMember -GroupId $sourceGroup.Id -All
    Write-ColorOutput "Found $($sourceMembers.Count) users in source group`n" "Green"

    # Get all current members from target device group
    Write-ColorOutput "Getting current members from target device group..." "Yellow"
    $currentTargetMembers = Get-MgGroupMember -GroupId $targetGroup.Id -All
    Write-ColorOutput "Found $($currentTargetMembers.Count) devices currently in target group`n" "Green"

    # Process each user and get their primary device
    Write-ColorOutput "Processing users and finding primary devices..." "Yellow"
    $devicesToAdd = @()
    $processedCount = 0

    foreach ($member in $sourceMembers) {
        $processedCount++
        Write-ColorOutput "[$processedCount/$($sourceMembers.Count)] Processing: $($member.AdditionalProperties.displayName) ($($member.AdditionalProperties.userPrincipalName))" "White"

        $primaryDevice = Get-UserPrimaryDevice -UserId $member.Id -UserPrincipalName $member.AdditionalProperties.userPrincipalName

        if ($primaryDevice) {
            $devicesToAdd += @{
                DeviceId = $primaryDevice.Id
                DeviceName = $primaryDevice.DeviceName
                UserName = $member.AdditionalProperties.displayName
                AzureAdDeviceId = $primaryDevice.AzureAdDeviceId
            }
        }
    }

    Write-ColorOutput "`nFound $($devicesToAdd.Count) devices to sync to target group" "Cyan"

    # Get Azure AD device IDs for comparison
    Write-ColorOutput "`nRetrieving Azure AD device information..." "Yellow"
    $deviceIdMap = @{}
    foreach ($device in $devicesToAdd) {
        if ($device.AzureAdDeviceId) {
            try {
                $azureAdDevice = Get-MgDevice -Filter "deviceId eq '$($device.AzureAdDeviceId)'" -ErrorAction Stop
                if ($azureAdDevice) {
                    $deviceIdMap[$azureAdDevice.Id] = $device
                }
            }
            catch {
                Write-ColorOutput "Warning: Could not find Azure AD device for $($device.DeviceName)" "Yellow"
            }
        }
    }

    $targetDeviceIds = $deviceIdMap.Keys
    $currentDeviceIds = $currentTargetMembers | ForEach-Object { $_.Id }

    # Determine devices to add and remove
    $devicesToAddToGroup = $targetDeviceIds | Where-Object { $_ -notin $currentDeviceIds }
    $devicesToRemoveFromGroup = $currentDeviceIds | Where-Object { $_ -notin $targetDeviceIds }

    Write-ColorOutput "`n=== Sync Summary ===" "Cyan"
    Write-ColorOutput "Devices to add: $($devicesToAddToGroup.Count)" "Green"
    Write-ColorOutput "Devices to remove: $($devicesToRemoveFromGroup.Count)" "Red"

    if ($devicesToAddToGroup.Count -eq 0 -and $devicesToRemoveFromGroup.Count -eq 0) {
        Write-ColorOutput "`nNo changes needed. Target group is already in sync!" "Green"
    }
    else {
        $confirm = Read-Host "`nProceed with sync? (Y/N)"

        if ($confirm -eq 'Y' -or $confirm -eq 'y') {
            # Add devices
            if ($devicesToAddToGroup.Count -gt 0) {
                Write-ColorOutput "`nAdding devices to target group..." "Yellow"
                foreach ($deviceId in $devicesToAddToGroup) {
                    $deviceInfo = $deviceIdMap[$deviceId]
                    try {
                        New-MgGroupMember -GroupId $targetGroup.Id -DirectoryObjectId $deviceId -ErrorAction Stop
                        Write-ColorOutput "  ✓ Added: $($deviceInfo.DeviceName) (User: $($deviceInfo.UserName))" "Green"
                    }
                    catch {
                        Write-ColorOutput "  ✗ Failed to add $($deviceInfo.DeviceName): $($_.Exception.Message)" "Red"
                    }
                }
            }

            # Remove devices
            if ($devicesToRemoveFromGroup.Count -gt 0) {
                Write-ColorOutput "`nRemoving devices from target group..." "Yellow"
                foreach ($deviceId in $devicesToRemoveFromGroup) {
                    try {
                        Remove-MgGroupMemberByRef -GroupId $targetGroup.Id -DirectoryObjectId $deviceId -ErrorAction Stop
                        Write-ColorOutput "  ✓ Removed device ID: $deviceId" "Green"
                    }
                    catch {
                        Write-ColorOutput "  ✗ Failed to remove device ${deviceId}: $($_.Exception.Message)" "Red"
                    }
                }
            }

            Write-ColorOutput "`nSync completed successfully!" "Green"
        }
        else {
            Write-ColorOutput "`nSync cancelled by user." "Yellow"
        }
    }

}
catch {
    Write-ColorOutput "`nError: $($_.Exception.Message)" "Red"
    Write-ColorOutput $_.ScriptStackTrace "Red"
}
finally {
    Write-ColorOutput "`nDisconnecting from Microsoft Graph..." "Yellow"
    Disconnect-MgGraph | Out-Null
    Write-ColorOutput "Done!`n" "Green"
}
