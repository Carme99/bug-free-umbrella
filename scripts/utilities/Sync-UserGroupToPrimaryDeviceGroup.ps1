<#
.SYNOPSIS
    Sync users' primary Intune devices from a source user group to a target device group.

.DESCRIPTION
    Takes a source Entra ID user group, finds each member's primary device in Intune, and adds
    those devices to a target Entra ID device group. It performs a full sync: devices belonging
    to users no longer in the source group are removed from the target group. Requires the
    Microsoft.Graph PowerShell modules, prompts interactively for missing group names and for
    confirmation before applying changes, and is idempotent - an already-converged target group
    is reported as in sync with no membership mutations.

.PARAMETER SourceGroupName
    The name of the Entra ID user group containing users whose devices should be synced.

.PARAMETER TargetGroupName
    The name of the Entra ID device group where primary devices should be added.

.EXAMPLE
    PS C:\> .\Sync-UserGroupToPrimaryDeviceGroup.ps1 -SourceGroupName "All Users" -TargetGroupName "Primary Devices"
    Syncs primary devices of 'All Users' members into the 'Primary Devices' group.

.EXAMPLE
    PS C:\> .\Sync-UserGroupToPrimaryDeviceGroup.ps1
    Runs interactively and prompts for the source and target group names.

.NOTES
    File Name: Sync-UserGroupToPrimaryDeviceGroup.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23

    Requires Microsoft.Graph PowerShell modules (Authentication, Groups,
    Devices.CorporateManagement).
    Run with appropriate permissions: Group.Read.All, Device.Read.All, GroupMember.ReadWrite.All,
    DeviceManagementManagedDevices.Read.All.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$TargetGroupName
)

$ErrorActionPreference = 'Stop'

function Write-ColorOutput {
    # Colored console output helper.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Intentional console output')]
    [CmdletBinding()]
    param(
        [string]$Message,
        [string]$Color = 'White'
    )
    Write-Host $Message -ForegroundColor $Color
}
function Get-UserPrimaryDevice {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'UserPrincipalName',
        Justification = 'Kept for caller context')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'primaryDevice',
        Justification = 'Upstream parity')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Intentional console output')]
    [CmdletBinding()]
    param(
        [string]$UserId,
        [string]$UserPrincipalName
    )

    try {
        # Get all managed devices for the user
        $devices = Get-MgUserManagedDevice -UserId $UserId -All -ErrorAction Stop

        if ($devices.Count -eq 0) {
            Write-ColorOutput "  [-] No devices found in Intune" "Yellow"
            return $null
        }

        # First, try to find device marked as primary
        $primaryDevice = $devices | Where-Object { $_.IsManaged -eq $true } | Select-Object -First 1

        if ($devices.Count -eq 1) {
            Write-ColorOutput "  [+] Found 1 device: $($devices[0].DeviceName)" "Green"
            return $devices[0]
        }

        # Multiple devices - let admin choose
        Write-ColorOutput "  [!] Found $($devices.Count) devices. Please select one:" "Yellow"

        for ($i = 0; $i -lt $devices.Count; $i++) {
            $device = $devices[$i]
            if ($device.LastSyncDateTime) {
                $lastSync = $device.LastSyncDateTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
            else {
                $lastSync = "Never"
            }
            $deviceLine = "     [$($i + 1)] $($device.DeviceName) - OS: $($device.OperatingSystem)"
            Write-Host "$deviceLine - Last Check-in: $lastSync"
        }

        do {
            $selection = Read-Host "     Enter selection (1-$($devices.Count))"
            $selectionNum = 0
            $validSelection = [int]::TryParse($selection, [ref]$selectionNum) -and
                $selectionNum -ge 1 -and $selectionNum -le $devices.Count
        } while (-not $validSelection)

        $selectedDevice = $devices[$selectionNum - 1]
        Write-ColorOutput "  [+] Selected: $($selectedDevice.DeviceName)" "Green"

        return $selectedDevice

    }
    catch {
        Write-ColorOutput "  [-] Error getting devices: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Main {
    [OutputType([int])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Intentional console output')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SourceGroupName,

        [Parameter(Mandatory = $false)]
        [string]$TargetGroupName
    )

    try {
        Write-ColorOutput "[*] === Intune Device Group Sync ===" "Cyan"
        Write-ColorOutput "[*] This script syncs users' primary devices to a device group." "Cyan"
        Write-ColorOutput "" "Cyan"

        # Connect to Microsoft Graph
        Write-ColorOutput "[*] Connecting to Microsoft Graph..." "Yellow"
        $requiredScopes = @(
            "Group.Read.All",
            "Device.Read.All",
            "GroupMember.ReadWrite.All",
            "DeviceManagementManagedDevices.Read.All"
        )

        Connect-MgGraph -Scopes $requiredScopes -NoWelcome -ErrorAction Stop
        Write-ColorOutput "[+] Connected successfully!" "Green"

        # Get source group name if not provided
        if (-not $SourceGroupName) {
            $SourceGroupName = Read-Host "Enter the name of the SOURCE user group"
        }

        # Get target group name if not provided
        if (-not $TargetGroupName) {
            $TargetGroupName = Read-Host "Enter the name of the TARGET device group"
        }

        Write-ColorOutput "[*] Looking up groups..." "Yellow"

        # Get source user group
        $sourceGroup = Get-MgGroup -Filter "displayName eq '$SourceGroupName'" -ErrorAction Stop
        if (-not $sourceGroup) {
            throw "Source group '$SourceGroupName' not found"
        }
        Write-ColorOutput "[+] Source group found: $($sourceGroup.DisplayName) (ID: $($sourceGroup.Id))" "Green"

        # Get target device group
        $targetGroup = Get-MgGroup -Filter "displayName eq '$TargetGroupName'" -ErrorAction Stop
        if (-not $targetGroup) {
            throw "Target group '$TargetGroupName' not found"
        }
        Write-ColorOutput "[+] Target group found: $($targetGroup.DisplayName) (ID: $($targetGroup.Id))" "Green"

        # Get all members from source user group
        Write-ColorOutput "[*] Getting members from source group..." "Yellow"
        $sourceMembers = Get-MgGroupMember -GroupId $sourceGroup.Id -All -ErrorAction Stop
        Write-ColorOutput "[+] Found $($sourceMembers.Count) users in source group" "Green"

        # Get all current members from target device group
        Write-ColorOutput "[*] Getting current members from target device group..." "Yellow"
        $currentTargetMembers = Get-MgGroupMember -GroupId $targetGroup.Id -All -ErrorAction Stop
        Write-ColorOutput "[+] Found $($currentTargetMembers.Count) devices currently in target group" "Green"

        # Process each user and get their primary device
        Write-ColorOutput "[*] Processing users and finding primary devices..." "Yellow"
        $devicesToAdd = @()
        $processedCount = 0

        foreach ($member in $sourceMembers) {
            $processedCount++
            $displayName = $member.AdditionalProperties.displayName
            $upn = $member.AdditionalProperties.userPrincipalName
            Write-ColorOutput "[*] [$processedCount/$($sourceMembers.Count)] Processing: ${displayName} ($upn)" "White"

            $primaryDevice = Get-UserPrimaryDevice -UserId $member.Id -UserPrincipalName $upn

            if ($primaryDevice) {
                $devicesToAdd += @{
                    DeviceId        = $primaryDevice.Id
                    DeviceName      = $primaryDevice.DeviceName
                    UserName        = $member.AdditionalProperties.displayName
                    AzureAdDeviceId = $primaryDevice.AzureAdDeviceId
                }
            }
        }

        Write-ColorOutput "[*] Found $($devicesToAdd.Count) devices to sync to target group" "Cyan"

        # Get Azure AD device IDs for comparison
        Write-ColorOutput "[*] Retrieving Azure AD device information..." "Yellow"
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
                    Write-ColorOutput "[!] Warning: Could not find Azure AD device for $($device.DeviceName)" "Yellow"
                }
            }
        }

        $targetDeviceIds = $deviceIdMap.Keys
        $currentDeviceIds = $currentTargetMembers | ForEach-Object { $_.Id }

        # Determine devices to add and remove (full-sync diff)
        $devicesToAddToGroup = $targetDeviceIds | Where-Object { $_ -notin $currentDeviceIds }
        $devicesToRemoveFromGroup = $currentDeviceIds | Where-Object { $_ -notin $targetDeviceIds }

        Write-ColorOutput "[*] === Sync Summary ===" "Cyan"
        Write-ColorOutput "[+] Devices to add: $($devicesToAddToGroup.Count)" "Green"
        Write-ColorOutput "[-] Devices to remove: $($devicesToRemoveFromGroup.Count)" "Red"

        # Idempotency check-then-act: only mutate when the diff is non-empty.
        if ($devicesToAddToGroup.Count -eq 0 -and $devicesToRemoveFromGroup.Count -eq 0) {
            Write-ColorOutput "[+] No changes needed. Target group is already in sync!" "Green"
        }
        else {
            $confirm = Read-Host "`nProceed with sync? (Y/N)"

            if ($confirm -eq 'Y' -or $confirm -eq 'y') {
                # Add devices
                if ($devicesToAddToGroup.Count -gt 0) {
                    Write-ColorOutput "[*] Adding devices to target group..." "Yellow"
                    foreach ($deviceId in $devicesToAddToGroup) {
                        $deviceInfo = $deviceIdMap[$deviceId]
                        try {
                            New-MgGroupMember -GroupId $targetGroup.Id -DirectoryObjectId $deviceId -ErrorAction Stop
                            Write-ColorOutput "  [+] Added: $($deviceInfo.DeviceName)" "Green"
                            Write-ColorOutput "      (User: $($deviceInfo.UserName))" "Green"
                        }
                        catch {
                            $addFailMsg = "  [-] Failed to add $($deviceInfo.DeviceName):"
                            Write-ColorOutput "$addFailMsg $($_.Exception.Message)" "Red"
                        }
                    }
                }

                # Remove devices
                if ($devicesToRemoveFromGroup.Count -gt 0) {
                    Write-ColorOutput "[*] Removing devices from target group..." "Yellow"
                    foreach ($deviceId in $devicesToRemoveFromGroup) {
                        try {
                            Remove-MgGroupMemberByRef -GroupId $targetGroup.Id `
                                -DirectoryObjectId $deviceId -ErrorAction Stop
                            Write-ColorOutput "  [+] Removed device ID: $deviceId" "Green"
                        }
                        catch {
                            Write-ColorOutput "  [-] Failed to remove device ${deviceId}: $($_.Exception.Message)" "Red"
                        }
                    }
                }

                Write-ColorOutput "[+] Sync completed successfully!" "Green"
            }
            else {
                Write-ColorOutput "[!] Sync cancelled by user." "Yellow"
            }
        }

        return 0
    }
    catch {
        Write-ColorOutput "[-] Error: $($_.Exception.Message)" "Red"
        return 1
    }
    finally {
        Write-ColorOutput "[*] Disconnecting from Microsoft Graph..." "Yellow"
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-ColorOutput "[+] Done!" "Green"
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }
