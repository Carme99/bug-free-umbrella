# Get-IntuneDevicePrimaryUsers.ps1

## Overview

`Get-IntuneDevicePrimaryUsers.ps1` is a comprehensive PowerShell script that resolves Intune primary users and hardware specifications for managed devices. It provides accurate user assignment information through multiple detection methods and enriches device records with detailed hardware data.

## Features

### Primary User Resolution
- **True Primary User Detection**: Uses the Graph API `managedDevice/users` relationship (beta endpoint) for most accurate results
- **Multiple Fallback Methods**:
  1. Intune `managedDevice/users` relation (beta) - Primary method
  2. `managedDevice.userPrincipalName` - First fallback
  3. Azure AD registered owner - Final fallback
- **Source Tracking**: Reports which method was used to resolve each user

### Hardware Information
- **Memory**: Physical RAM in GB
- **Storage**: Total and free capacity in GB, plus percentage free
- **Processor**: Architecture and friendly CPU name (normalized)
- **Device Details**: Manufacturer, model, serial number
- **Operating System**: OS type and version
- **Last Seen**: Device last sync date/time from Intune
- **Friendly Model**: Retrieves friendly model names from Entra device extension attributes

### Input Flexibility
- **Direct Parameters**: Comma or newline-separated device names
- **CSV Files**: Automatically detects device name column
- **Text Files**: Line-by-line device names
- **Interactive Mode**: Prompts if no input provided
- **GUID Support**: Accepts device IDs or Azure AD Device IDs

### Output Options
- **Console Display**: Formatted table view
- **CSV Export**: UTF-8 encoded export (default: Desktop\PrimaryUsers.csv)
- **Configurable Path**: Specify custom output location
- **NoExport Option**: Console-only mode

## Requirements

### Software
- PowerShell 5.1 or later
- Microsoft Graph PowerShell SDK

### Permissions
Required Microsoft Graph API permissions:
- `DeviceManagementManagedDevices.Read.All` - Read Intune managed devices
- `Directory.Read.All` - Read directory objects
- `User.Read.All` - Read user information
- `Device.Read.All` - Read device information

## Installation

1. Install Microsoft Graph PowerShell SDK:
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

2. Place the script in your desired location:
```powershell
# Recommended location in repository
.\scripts\endpoints\intune\reporting\Get-IntuneDevicePrimaryUsers.ps1
```

## Usage

### Basic Usage

Retrieve information for a single device:
```powershell
.\Get-IntuneDevicePrimaryUsers.ps1 -DeviceName "LTW1010013"
```

Retrieve information for multiple devices:
```powershell
.\Get-IntuneDevicePrimaryUsers.ps1 -DeviceName "LTW1010013,LTW1010334,LTW1010344"
```

### Using Input Files

Process devices from a text file:
```powershell
.\Get-IntuneDevicePrimaryUsers.ps1 -InputFile "C:\Temp\devices.txt"
```

Process devices from a CSV file:
```powershell
.\Get-IntuneDevicePrimaryUsers.ps1 -InputFile "C:\Temp\devices.csv"
```

### Customizing Output

Specify custom output path:
```powershell
.\Get-IntuneDevicePrimaryUsers.ps1 -DeviceName "LTW1010013" -OutputPath "C:\Reports\PrimaryUsers.csv"
```

Display results without exporting:
```powershell
.\Get-IntuneDevicePrimaryUsers.ps1 -DeviceName "LTW1010013" -NoExport
```

### Extension Attributes

Use a different extension attribute for friendly model names:
```powershell
.\Get-IntuneDevicePrimaryUsers.ps1 -DeviceName "LTW1010013" -FriendlyModelAttribute "extensionAttribute2"
```

### Interactive Mode

Run without parameters for interactive input:
```powershell
.\Get-IntuneDevicePrimaryUsers.ps1
# Script will prompt: "Enter one or more device names separated by commas"
```

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `DeviceName` | String[] | No | - | One or more device names (comma/newline separated) |
| `InputFile` | String | No | - | Path to .txt or .csv file containing device names |
| `OutputPath` | String | No | Desktop\PrimaryUsers.csv | Path where CSV report will be saved |
| `FriendlyModelAttribute` | String | No | extensionAttribute1 | Which Entra extension attribute contains friendly model name |
| `NoExport` | Switch | No | False | Skip CSV export, console display only |
| `Quiet` | Switch | No | False | Suppress INFO and DEBUG log messages |

## Output Fields

The script generates a CSV report with the following fields:

### Identity & User Information
- **DeviceName**: Device hostname
- **LastSeen**: Last sync date/time from Intune
- **PrimaryUserDisplayName**: User's display name
- **PrimaryUserUPN**: User's UserPrincipalName
- **Source**: Method used to resolve primary user

### Device Information
- **FriendlyModel**: Human-readable model name from extension attributes
- **Manufacturer**: Device manufacturer
- **Model**: Device model number
- **SerialNumber**: Device serial number
- **OperatingSystem**: Operating system type
- **OSVersion**: Operating system version

### Hardware Specifications
- **CPU**: Friendly processor name (normalized)
- **CPUArchitecture**: Processor architecture (x64, ARM64, etc.)
- **RAM_GB**: Physical memory in gigabytes
- **StorageTotal_GB**: Total storage capacity in gigabytes
- **StorageFree_GB**: Free storage space in gigabytes
- **StorageFree_Percent**: Percentage of storage available

## Input File Formats

### Text File Format
```
LTW1010013
LTW1010334
LTW1010344
```

### CSV File Format
The script intelligently detects device name columns. It will look for columns named:
- DeviceName
- deviceName
- Name
- ComputerName
- Computer
- Hostname
- Host

If none are found, it uses the first column.

Example CSV:
```csv
DeviceName,Location,Department
LTW1010013,Building A,IT
LTW1010334,Building B,Finance
LTW1010344,Building A,HR
```

## Examples

### Example 1: Single Device Quick Check
```powershell
.\Get-IntuneDevicePrimaryUsers.ps1 -DeviceName "LTW1010013" -NoExport
```

Output displays in console only, no CSV file created.

### Example 2: Bulk Processing from CSV
```powershell
.\Get-IntuneDevicePrimaryUsers.ps1 `
    -InputFile "C:\IT\DeviceList.csv" `
    -OutputPath "C:\Reports\DeviceAudit_$(Get-Date -Format 'yyyyMMdd').csv"
```

Processes all devices from CSV, exports to dated report file.

### Example 3: Using Custom Extension Attribute
```powershell
.\Get-IntuneDevicePrimaryUsers.ps1 `
    -DeviceName "LTW1010013" `
    -FriendlyModelAttribute "extensionAttribute5"
```

Retrieves friendly model name from extensionAttribute5 instead of default extensionAttribute1.

### Example 4: Quiet Mode for Automation
```powershell
.\Get-IntuneDevicePrimaryUsers.ps1 `
    -InputFile "C:\Automation\devices.txt" `
    -OutputPath "C:\Reports\output.csv" `
    -Quiet
```

Runs with minimal console output, suitable for scheduled tasks.

### Example 5: Multiple Devices with Custom Location
```powershell
$devices = @"
LTW1010013
LTW1010334
LTW1010344
"@

$devices | Out-File -FilePath "C:\Temp\devices.txt"

.\Get-IntuneDevicePrimaryUsers.ps1 `
    -InputFile "C:\Temp\devices.txt" `
    -OutputPath "\\FileServer\Reports\PrimaryUsers.csv"
```

Processes devices and exports to network share.

## Advanced Features

### Device Lookup Methods
The script supports multiple device identifier formats:
1. **Device Name**: Standard hostname lookup
2. **Managed Device ID**: Direct Intune device ID (GUID)
3. **Azure AD Device ID**: Azure AD object ID (GUID)

When a GUID is provided, the script attempts all three methods automatically.

### Data Normalization
- **CPU Names**: Removes verbose manufacturer strings (e.g., "GenuineIntel" → "Intel")
- **Whitespace**: Normalizes excessive whitespace in processor names
- **Null Handling**: Gracefully handles missing or null values
- **Date Conversion**: Converts UTC timestamps to local time

### Error Handling
- Individual device failures don't stop processing
- Error details captured in "Source" field
- Graceful degradation for missing data
- Progress indicators for large batches

## Troubleshooting

### Issue: No devices found
**Cause**: Device name doesn't match Intune records
**Solution**: Verify device name spelling, try using Azure AD Device ID instead

### Issue: Primary user shows as "Not found in Intune"
**Cause**: Device exists but has no associated user
**Solution**: Check device enrollment status, verify user assignment in Intune

### Issue: Extension attribute returns null
**Cause**: Attribute not populated or wrong attribute selected
**Solution**: Verify extension attribute is populated in Azure AD, check attribute number

### Issue: Permission errors
**Cause**: Insufficient Graph API permissions
**Solution**: Ensure all required permissions are granted and admin consent provided

### Issue: Slow performance with large device lists
**Cause**: Individual API calls for each device
**Solution**: Process in batches, run during off-peak hours

## Performance Considerations

- **API Calls**: Script makes multiple Graph API calls per device (device lookup, user lookup, extension attributes)
- **Batch Size**: Optimal batch size is 50-100 devices per run
- **Rate Limiting**: Microsoft Graph has rate limits; large batches may experience throttling
- **Network**: Requires stable internet connection for Graph API calls

## Security Notes

- Script uses delegated permissions (user context)
- No credentials stored or logged
- Graph token expires after session
- CSV export contains user information - handle according to data privacy policies
- Supports multi-factor authentication

## Integration Examples

### Scheduled Task
```powershell
# Create scheduled task to run daily
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Scripts\Get-IntuneDevicePrimaryUsers.ps1 -InputFile C:\Data\devices.txt -OutputPath C:\Reports\Daily_$(Get-Date -Format 'yyyyMMdd').csv -Quiet"

$trigger = New-ScheduledTaskTrigger -Daily -At 6am

Register-ScheduledTask -TaskName "Intune Device Report" -Action $action -Trigger $trigger
```

### Power BI Integration
```powershell
# Export to Power BI-friendly format
.\Get-IntuneDevicePrimaryUsers.ps1 -InputFile "devices.txt" -OutputPath "C:\PowerBI\IntuneDevices.csv"

# Power BI can then import this CSV for visualization
```

### Compliance Reporting
```powershell
# Generate report and filter devices with issues
.\Get-IntuneDevicePrimaryUsers.ps1 -InputFile "all_devices.txt" -OutputPath "temp.csv"

$report = Import-Csv "temp.csv"
$noUserDevices = $report | Where-Object { -not $_.PrimaryUserUPN }
$noUserDevices | Export-Csv "DevicesWithoutUsers.csv" -NoTypeInformation
```

## Version History

### Version 2.0 (2026-01-16)
- Complete rewrite with enhanced functionality
- Added true primary user resolution via Graph beta endpoint
- Added comprehensive hardware information collection
- Added friendly model name from extension attributes
- Added multiple input methods (CSV, TXT, interactive)
- Added GUID-based device lookup
- Improved error handling and logging
- Added progress indicators
- Enhanced data normalization

### Version 1.0
- Initial release
- Basic device and user lookup

## Contributing

To contribute improvements:
1. Test changes thoroughly with various device types
2. Maintain backward compatibility with parameter names
3. Update documentation for new features
4. Follow PowerShell best practices (Verb-Noun naming, proper help text)

## License

See repository LICENSE file for details.

## Support

For issues, questions, or feature requests:
- Open an issue in the GitHub repository
- Review existing issues for similar problems
- Include PowerShell version and error messages in bug reports

## Related Scripts

- **Add-LenovoFriendlyModelNames.ps1**: Populates extension attributes with friendly model names
- **Get-UserDeviceAffinity.ps1**: Reports on user-device relationships
- **Get-DeviceHealthScore.ps1**: Comprehensive device health reporting

## See Also

- [Microsoft Graph API - Managed Devices](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-manageddevice)
- [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/)
- [Intune Device Management](https://learn.microsoft.com/en-us/mem/intune/remote-actions/device-management)
