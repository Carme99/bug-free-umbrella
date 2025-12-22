# Intune User Group to Device Group Sync Script

## Overview

This PowerShell script automates the synchronization of users' primary Intune-managed devices from an Entra ID user group to a device group. This is particularly useful for scenarios where you have a user group for Windows update policies, but auto-patching works at the device level.

## Use Case

At many organizations, users can opt-in to receive Windows updates early by joining a specific user group. However, since auto-patch policies target devices rather than users, this script bridges that gap by:

1. Reading all users from a specified user group
2. Finding each user's primary device in Intune
3. Adding those devices to a specified device group
4. Removing devices from users no longer in the source group (full sync)

## Prerequisites

### PowerShell Modules

Install the required Microsoft Graph PowerShell modules:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Groups -Scope CurrentUser
Install-Module Microsoft.Graph.DeviceManagement -Scope CurrentUser
```

### Permissions

The account running the script needs the following Microsoft Graph permissions:

- `Group.Read.All` - Read group information
- `Device.Read.All` - Read device information
- `GroupMember.ReadWrite.All` - Modify group membership
- `DeviceManagementManagedDevices.Read.All` - Read Intune managed devices

These permissions will be requested during the interactive login process.

### Azure AD Requirements

- Source group must exist (user group)
- Target group must exist (device group)
- Users in source group must have devices enrolled in Intune

## Usage

### Basic Usage

Run the script interactively:

```powershell
.\Sync-UserGroupToPrimaryDeviceGroup.ps1
```

The script will prompt you for:
1. Source user group name
2. Target device group name
3. Device selection (if a user has multiple devices)
4. Confirmation before making changes

### With Parameters

You can also provide group names as parameters:

```powershell
.\Sync-UserGroupToPrimaryDeviceGroup.ps1 -SourceGroupName "Early Updates Users" -TargetGroupName "Early Updates Devices"
```

## Features

### Interactive Device Selection

When a user has multiple devices enrolled in Intune, the script:
- Lists all devices with their names
- Shows the operating system
- Displays the last check-in time
- Prompts the administrator to select which device to use

Example output:
```
[1/5] Processing: John Doe (john.doe@company.com)
  └─ Found 3 devices. Please select one:
     [1] LAPTOP-001 - OS: Windows 11 - Last Check-in: 2025-12-20 14:32:15
     [2] DESKTOP-002 - OS: Windows 10 - Last Check-in: 2025-12-19 09:15:42
     [3] TABLET-003 - OS: Windows 11 - Last Check-in: 2025-12-15 16:20:33
     Enter selection (1-3):
```

### Full Sync

The script performs a complete synchronization:
- **Adds** devices of users in the source group who aren't in the target group
- **Removes** devices from the target group if their users are no longer in the source group

### Detailed Logging

The script provides color-coded output showing:
- Connection status
- Group lookup results
- User processing progress
- Device selection
- Summary of changes
- Success/failure of each operation

## Workflow

1. **Authentication**: Connects to Microsoft Graph with interactive login
2. **Group Validation**: Verifies both source and target groups exist
3. **User Enumeration**: Gets all members from the source user group
4. **Current State**: Retrieves current members of the target device group
5. **Device Discovery**: For each user, finds their primary device:
   - If 1 device: automatically selects it
   - If multiple devices: prompts administrator to choose
   - If no devices: logs a warning and skips
6. **Change Calculation**: Determines which devices to add and remove
7. **Confirmation**: Shows summary and asks for confirmation
8. **Sync Execution**: Adds and removes devices as needed
9. **Cleanup**: Disconnects from Microsoft Graph

## Example Output

```
=== Intune Device Group Sync Script ===
This script syncs users' primary devices to a device group.

Connecting to Microsoft Graph...
Connected successfully!

Enter the name of the SOURCE user group: Early Adopters
Enter the name of the TARGET device group: Early Update Devices

Looking up groups...
✓ Source group found: Early Adopters (ID: abc-123-def)
✓ Target group found: Early Update Devices (ID: xyz-789-ghi)

Getting members from source group...
Found 5 users in source group

Getting current members from target device group...
Found 3 devices currently in target group

Processing users and finding primary devices...
[1/5] Processing: John Doe (john.doe@company.com)
  └─ Found 1 device: LAPTOP-JD001

[2/5] Processing: Jane Smith (jane.smith@company.com)
  └─ Found 2 devices. Please select one:
     [1] DESKTOP-JS001 - OS: Windows 11 - Last Check-in: 2025-12-20 08:30:00
     [2] LAPTOP-JS002 - OS: Windows 10 - Last Check-in: 2025-12-18 17:45:00
     Enter selection (1-2): 1
     Selected: DESKTOP-JS001

=== Sync Summary ===
Devices to add: 3
Devices to remove: 1

Proceed with sync? (Y/N): y

Adding devices to target group...
  ✓ Added: LAPTOP-JD001 (User: John Doe)
  ✓ Added: DESKTOP-JS001 (User: Jane Smith)
  ✓ Added: LAPTOP-AB003 (User: Alice Brown)

Removing devices from target group...
  ✓ Removed device ID: old-device-id-123

Sync completed successfully!

Disconnecting from Microsoft Graph...
Done!
```

## Troubleshooting

### "Group not found"
- Verify the group name is spelled correctly (case-sensitive)
- Ensure you have permissions to read the group

### "No devices found in Intune"
- User may not have enrolled any devices
- Check that the user's device is properly enrolled in Intune
- Verify device compliance status

### "Failed to add device"
- Ensure the target group is a device group (not a user group)
- Check that you have GroupMember.ReadWrite.All permissions
- Verify the device exists in Azure AD

### Permission Issues
- Re-run the script and consent to the requested permissions
- Contact your Azure AD administrator for necessary permissions

## Best Practices

1. **Test First**: Run the script in a test environment before production
2. **Schedule Regular Runs**: Set up a scheduled task to run periodically
3. **Review Changes**: Always review the sync summary before confirming
4. **Monitor Logs**: Keep track of script output for troubleshooting
5. **Backup Groups**: Document group memberships before first run

## Security Considerations

- Uses interactive login (OAuth) - no credentials stored in script
- Requires explicit user consent for permissions
- All operations are logged for audit purposes
- Disconnects from Graph API after completion

## License

This script is provided as-is for use within your organization.

## Support

For issues or questions, please refer to your organization's IT support team.
