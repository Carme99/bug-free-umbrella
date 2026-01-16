# Add-LenovoFriendlyModelNames.ps1

## Overview

`Add-LenovoFriendlyModelNames.ps1` automates the enrichment of Lenovo device records with human-readable model names. It maps cryptic Machine Type Model (MTM) codes to friendly product family names using Lenovo's official dataset, then updates both Intune device notes and Azure AD extension attributes.

## Problem Statement

Lenovo devices in Intune typically display model numbers like "21AH001AUS" which are difficult for administrators and help desk staff to interpret. This script resolves these codes to friendly names like "ThinkPad T14 Gen 3", making device inventory management more intuitive.

## Features

### Core Functionality
- **Automatic MTM Mapping**: Downloads and processes Lenovo's official product dataset
- **Dual Update Targets**: Updates both Intune Notes and Entra device extension attributes
- **Smart Deduplication**: Avoids duplicate entries in Notes field
- **Audit Mode**: Validates mapping coverage without making changes
- **Progress Tracking**: Real-time progress indicators for large device collections
- **Comprehensive Logging**: Detailed operation logs with error tracking

### Reliability Features
- **Retry Logic**: Automatic retry for network operations with exponential backoff
- **Rate Limiting**: Built-in throttling protection to avoid Graph API limits
- **Dual Addressing**: Falls back to alternate device addressing if primary method fails
- **Error Recovery**: Individual device failures don't stop batch processing
- **Error Logging**: Failed operations exported to CSV for review

### Safety Features
- **WhatIf Support**: Preview changes before applying (built-in PowerShell feature)
- **Confirm Support**: Interactive confirmation for each change
- **AuditOnly Mode**: Validate mappings without making modifications
- **Selective Updates**: Choose which targets to update (Notes, Extension Attributes, or both)

### Authentication
- **Robust Sign-In**: Automatic fallback from interactive to device code authentication
- **Session Management**: Proper connection and disconnection handling
- **Scope Management**: Requests only required permissions

## Requirements

### Software
- PowerShell 5.1 or later (PowerShell 7+ recommended)
- Microsoft Graph PowerShell SDK
- Internet access to download Lenovo dataset

### Permissions
Required Microsoft Graph API permissions:
- `DeviceManagementManagedDevices.ReadWrite.All` - Update Intune managed device records
- `Device.ReadWrite.All` - Update Azure AD device extension attributes

### Environment
- Run from PowerShell console or Windows Terminal (best for interactive auth)
- Azure AD tenant with Lenovo devices enrolled in Intune
- Devices must have manufacturer = "LENOVO"

## Installation

1. Install Microsoft Graph PowerShell SDK:
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

2. Ensure execution policy allows script execution:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

3. Place script in maintenance directory:
```powershell
.\scripts\endpoints\intune\maintenance\Add-LenovoFriendlyModelNames.ps1
```

## Usage

### Initial Validation (Recommended First Step)

Before making any changes, run in audit mode to validate mapping coverage:

```powershell
.\Add-LenovoFriendlyModelNames.ps1 -AuditOnly
```

This will:
- Show how many Lenovo devices exist
- Display unique MTM codes found
- Report mapping success rate
- Identify unmapped MTM codes
- Exit without making changes

### Preview Changes with WhatIf

See what changes would be made without actually applying them:

```powershell
.\Add-LenovoFriendlyModelNames.ps1 -WhatIf
```

Output shows:
```
What if: Performing the operation "Update Intune Notes with 'ThinkPad T14 Gen 3'" on target "LTW1010013".
What if: Performing the operation "Set Entra extensionAttribute1 to 'ThinkPad T14 Gen 3'" on target "LTW1010013".
```

### Production Run

Apply changes to all Lenovo devices:

```powershell
.\Add-LenovoFriendlyModelNames.ps1
```

Default behavior:
- Updates Intune Notes (appends friendly name)
- Updates Entra extensionAttribute1 (sets/overwrites)
- Shows progress for each device
- Displays summary statistics

### Strict Validation Mode

Fail if any MTM codes cannot be mapped:

```powershell
.\Add-LenovoFriendlyModelNames.ps1 -AuditOnly -FailIfMissingMappings
```

Use this to ensure 100% mapping coverage before running updates.

### Selective Updates

Update only Intune Notes (skip extension attributes):

```powershell
.\Add-LenovoFriendlyModelNames.ps1 -UpdateExtensionAttributes:$false
```

Update only extension attributes (skip Notes):

```powershell
.\Add-LenovoFriendlyModelNames.ps1 -UpdateNotes:$false
```

### Custom Extension Attribute

Use a different extension attribute:

```powershell
.\Add-LenovoFriendlyModelNames.ps1 -ExtensionAttributeName "extensionAttribute5"
```

### Custom Notes Prefix

Add a prefix to Notes entries:

```powershell
.\Add-LenovoFriendlyModelNames.ps1 -NotesPrefix "Model"
```

Result in Notes field: `Model: ThinkPad T14 Gen 3`

### Verbose Logging

Enable detailed per-device logging:

```powershell
.\Add-LenovoFriendlyModelNames.ps1 -VerboseOutput
```

Shows:
- Each device being processed
- MTM resolution results
- Update operation details
- Skip reasons

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `AuditOnly` | Switch | No | False | Validate mappings without making changes |
| `FailIfMissingMappings` | Switch | No | False | Fail if any MTM codes cannot be resolved |
| `UpdateNotes` | Switch | No | True | Enable Intune Notes updates |
| `UpdateExtensionAttributes` | Switch | No | True | Enable Entra extension attribute updates |
| `ExtensionAttributeName` | String | No | extensionAttribute1 | Which extension attribute to update (1-15) |
| `NotesPrefix` | String | No | "" | Optional prefix for Notes entries |
| `NotesSeparator` | String | No | \n | Separator when appending to Notes |
| `VerboseOutput` | Switch | No | False | Enable detailed per-device logging |

## How It Works

### Step 1: Device Retrieval
```powershell
# Retrieves all Lenovo devices from Intune
$lenovoDevices = Get-MgDeviceManagementManagedDevice `
    -Filter "manufacturer eq 'LENOVO'" `
    -All `
    -Property "id,deviceName,manufacturer,model,notes,azureADDeviceId"
```

### Step 2: MTM Extraction
```powershell
# Extracts MTM code from model string
# Example: "21AH001AUS" -> "21AH"
$mtm = $Model.Substring(0, 4).Trim().ToUpperInvariant()
```

### Step 3: Mapping Resolution
```powershell
# Downloads Lenovo dataset
$allModels = Invoke-RestMethod -Uri "https://download.lenovo.com/bsco/public/allModels.json"

# Matches MTM to friendly name
# Example: "21AH" -> "ThinkPad T14 Gen 3 (Type 21AH, 21AJ)"
# Extracts: "ThinkPad T14 Gen 3"
```

### Step 4: Notes Update
```powershell
# Appends friendly name to Notes if not already present
# Existing: "Asset Tag: 12345"
# Result:   "Asset Tag: 12345\nThinkPad T14 Gen 3"
```

### Step 5: Extension Attribute Update
```powershell
# Sets extension attribute value (overwrites existing)
PATCH /v1.0/devices/{id}
{
  "extensionAttributes": {
    "extensionAttribute1": "ThinkPad T14 Gen 3"
  }
}
```

## Output Examples

### Audit Mode Output
```
=== Lenovo Friendly Model Names Update Script ===
Version 2.0 - Enhanced with retry logic, progress tracking, and error logging

Configuration:
  Audit Only: True
  Update Notes: True
  Update Extension Attributes: True
  Extension Attribute: extensionAttribute1

Connecting to Microsoft Graph using interactive authentication
Retrieving Lenovo managed devices from Intune...
Found 247 Lenovo devices
Extracting unique MTM codes from device models...
Identified 23 unique MTM codes in tenant

Building MTM to friendly name mapping from Lenovo dataset...
Mapping Results:
  Successfully mapped: 21 MTM codes
  Unable to map: 2 MTM codes
  Lenovo dataset entries processed: 3847

WARNING: The following MTM codes could not be mapped:
  - 20XY
  - 21F9
Example devices with unmapped MTMs:
  - LTW1010789: 20XY001GUS
  - LTW1010856: 21F9000HUS

=== Audit Only Mode - No Changes Made ===
To apply changes, run without -AuditOnly flag
```

### Production Run Output
```
=== Lenovo Friendly Model Names Update Script ===
Version 2.0 - Enhanced with retry logic, progress tracking, and error logging

Configuration:
  Audit Only: False
  Update Notes: True
  Update Extension Attributes: True
  Extension Attribute: extensionAttribute1

Connecting to Microsoft Graph using interactive authentication
Retrieving Lenovo managed devices from Intune...
Found 247 Lenovo devices
Extracting unique MTM codes from device models...
Identified 23 unique MTM codes in tenant

Building MTM to friendly name mapping from Lenovo dataset...
Successfully downloaded Lenovo model dataset (attempt 1/3)
Processing 3847 model entries from Lenovo dataset

Mapping Results:
  Successfully mapped: 21 MTM codes
  Unable to map: 2 MTM codes
  Lenovo dataset entries processed: 3847

Processing devices...
[Progress bar: 247/247 complete]

=== Update Summary ===
Intune Notes:
  Updated: 203
  Skipped (already present): 42

Entra Extension Attributes:
  Updated: 245
  Skipped: 0

Other:
  Unknown/Unmapped: 2
  Errors: 0

Script completed successfully
```

### Error Scenario Output
```
=== Update Summary ===
Intune Notes:
  Updated: 198
  Skipped (already present): 42

Entra Extension Attributes:
  Updated: 240
  Skipped: 0

Other:
  Unknown/Unmapped: 2
  Errors: 5

Error log exported to: .\LenovoUpdateErrors_20260116_143052.csv

Script completed successfully
```

## Error Handling

### Error Log Format
When errors occur, a CSV file is generated with these fields:

| Field | Description |
|-------|-------------|
| DeviceName | Device hostname |
| Model | Full model string |
| MTM | Extracted MTM code |
| IntuneId | Intune managed device ID |
| AzureADDeviceId | Azure AD device object ID |
| Error | Error message details |
| Timestamp | When error occurred |

### Common Errors

#### Error: "No Lenovo devices found in Intune"
**Cause**: No devices with manufacturer = "LENOVO"
**Resolution**:
- Verify device enrollment
- Check manufacturer field in Intune
- Ensure devices are synced

#### Error: "Failed to download Lenovo dataset after 3 attempts"
**Cause**: Network connectivity or Lenovo server unavailable
**Resolution**:
- Check internet connection
- Verify proxy settings
- Try again later if Lenovo server is down

#### Error: "Object reference not set to an instance of an object"
**Cause**: Device missing required fields (azureADDeviceId, model, etc.)
**Resolution**:
- Review error log CSV for affected devices
- Manually verify device records in Intune
- May indicate orphaned or stale device records

#### Error: "Insufficient privileges to complete the operation"
**Cause**: Missing required Graph API permissions
**Resolution**:
- Verify permissions are granted
- Ensure admin consent provided
- Re-authenticate with correct permissions

## MTM Code Reference

### What is an MTM Code?
MTM (Machine Type Model) is Lenovo's 4-character product identifier system:
- **Format**: 4 alphanumeric characters (e.g., "21AH", "20XY", "21F9")
- **Location**: First 4 characters of model string
- **Purpose**: Identifies product family/generation
- **Example**: "21AH001AUS" → MTM = "21AH"

### Common MTM Patterns
- **ThinkPad T Series**: 20XY, 21AH, 21CF, 21CG
- **ThinkPad X1 Carbon**: 20XW, 20XV, 21CB
- **ThinkPad L Series**: 20X1, 20X2, 21DD
- **ThinkBook**: 20VE, 20VD, 21D2

### Mapping Logic
The script searches Lenovo's dataset for entries matching the MTM code:

**Match Criteria** (in order of precedence):
1. MTM in parenthetical type codes: `(Type 21AH, 21AJ)`
2. MTM as standalone identifier: `ThinkPad T14 21AH`

**Exclusions** (filtered out):
- UEFI/BIOS entries
- dTPM/fTPM entries
- Asset tag entries

**Extraction**:
```
Input:  "ThinkPad T14 Gen 3 (Type 21AH, 21AJ) - UEFI Lenovo"
Match:  "ThinkPad T14 Gen 3 (Type 21AH, 21AJ)"
Output: "ThinkPad T14 Gen 3"
```

## Integration Scenarios

### Pre-Deployment Validation
```powershell
# Before updating production devices
.\Add-LenovoFriendlyModelNames.ps1 `
    -AuditOnly `
    -FailIfMissingMappings `
    -VerboseOutput
```

### Scheduled Maintenance
```powershell
# Monthly scheduled task to update new devices
$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-File C:\Scripts\Add-LenovoFriendlyModelNames.ps1"

$trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At 2am

Register-ScheduledTask `
    -TaskName "Update Lenovo Model Names" `
    -Action $action `
    -Trigger $trigger `
    -RunLevel Highest
```

### Pipeline Integration
```powershell
# As part of device provisioning pipeline
try {
    .\Add-LenovoFriendlyModelNames.ps1 -Confirm:$false
    Write-Output "Successfully updated Lenovo model names"
    exit 0
}
catch {
    Write-Error "Failed to update model names: $_"
    exit 1
}
```

### Reporting Integration
```powershell
# Generate report after updates
.\Add-LenovoFriendlyModelNames.ps1 | Out-File -FilePath "C:\Reports\LenovoUpdate.log"

# Check for errors
if (Test-Path ".\LenovoUpdateErrors_*.csv") {
    $errors = Import-Csv ".\LenovoUpdateErrors_*.csv"
    Send-MailMessage `
        -To "it-admin@company.com" `
        -Subject "Lenovo Update Errors: $($errors.Count) devices" `
        -Body "See attached error log" `
        -Attachments (Get-ChildItem ".\LenovoUpdateErrors_*.csv").FullName
}
```

## Best Practices

### Initial Deployment
1. **Run audit first**: `.\Add-LenovoFriendlyModelNames.ps1 -AuditOnly`
2. **Review unmapped MTMs**: Research unknown codes at [Lenovo Support](https://pcsupport.lenovo.com)
3. **Test with WhatIf**: `.\Add-LenovoFriendlyModelNames.ps1 -WhatIf`
4. **Pilot run**: Test on small device subset
5. **Full deployment**: Run against all devices

### Ongoing Maintenance
1. **Monthly refresh**: Update devices as new models arrive
2. **Monitor errors**: Review error logs, fix device records
3. **Validate new MTMs**: Audit mode when new models deployed
4. **Update documentation**: Track custom MTM mappings

### Performance Optimization
1. **Off-peak hours**: Run during low-usage periods
2. **Batch processing**: Let rate limiting handle throttling
3. **Network stability**: Ensure reliable connection for dataset download
4. **Progress monitoring**: Use verbose mode for troubleshooting

## Troubleshooting

### Slow Performance
**Symptom**: Script takes longer than expected
**Causes**:
- Large number of devices (>500)
- Network latency
- Graph API throttling

**Solutions**:
- Run during off-peak hours
- Check network connectivity
- Rate limiting is built-in (100ms delay)
- Consider breaking into batches by device group

### Inconsistent Updates
**Symptom**: Some devices update, others don't
**Causes**:
- Missing azureADDeviceId for extension attributes
- Permission issues
- Device sync status

**Solutions**:
- Review error log CSV for patterns
- Verify devices fully synced to Azure AD
- Check individual device records in Azure AD portal

### Authentication Issues
**Symptom**: "window handle must be configured" error
**Solution**: Script automatically falls back to device code auth

**Symptom**: "Insufficient privileges" error
**Solution**:
1. Disconnect: `Disconnect-MgGraph`
2. Reconnect with admin account
3. Verify permissions in Azure AD

### MTM Not Mapping
**Symptom**: Device MTM shows in "Missing" list
**Causes**:
- New/unreleased model
- Custom/OEM model
- Non-standard model string format

**Solutions**:
1. Verify model string in Intune
2. Search Lenovo's dataset manually
3. Contact Lenovo support for MTM details
4. Document custom mapping for reference

## Advanced Configuration

### Custom Notes Formatting
```powershell
# Add timestamp to notes entries
$timestamp = Get-Date -Format "yyyy-MM-dd"
.\Add-LenovoFriendlyModelNames.ps1 -NotesPrefix "Model ($timestamp)"

# Result: "Model (2026-01-16): ThinkPad T14 Gen 3"
```

### Multiple Extension Attributes
```powershell
# Update attribute 1 with friendly name
.\Add-LenovoFriendlyModelNames.ps1 -ExtensionAttributeName "extensionAttribute1"

# Update attribute 2 with MTM code (requires script modification)
# See customization section in script comments
```

### Filtered Updates
```powershell
# To update specific devices only, modify script to add filter:
# Example: Only update devices in specific Azure AD group
# (Requires script customization)
```

## Version History

### Version 2.0 (2026-01-16)
- ✅ Fixed switch parameter declarations
- ✅ Added retry logic for dataset download (3 attempts, exponential backoff)
- ✅ Added progress indicators for device processing
- ✅ Added rate limiting protection (100ms delay)
- ✅ Improved MTM matching logic (regex-based)
- ✅ Added comprehensive error logging with CSV export
- ✅ Fixed Disconnect-MgGraph consistency
- ✅ Added null/empty validation checks
- ✅ Added MTM format validation
- ✅ Enhanced logging and status reporting
- ✅ Improved documentation and help text
- ✅ Added dataset download status messages

### Version 1.0
- Initial release
- Basic MTM mapping functionality
- Intune Notes and Entra attribute updates
- Audit mode support

## Support Resources

### Lenovo Resources
- [Lenovo Commercial Support](https://support.lenovo.com/us/en/solutions/lcsm)
- [Lenovo Product Specifications](https://psref.lenovo.com/)
- [Lenovo Model Lookup](https://pcsupport.lenovo.com/us/en/)

### Microsoft Resources
- [Microsoft Graph API - Devices](https://docs.microsoft.com/en-us/graph/api/resources/device)
- [Intune Managed Devices](https://docs.microsoft.com/en-us/graph/api/resources/intune-devices-manageddevice)
- [Azure AD Extension Attributes](https://docs.microsoft.com/en-us/azure/active-directory/hybrid/how-to-connect-sync-feature-directory-extensions)

## Related Scripts

- **Get-IntuneDevicePrimaryUsers.ps1**: Reads friendly model names from extension attributes
- **Get-DeviceComplianceReport.ps1**: Include friendly names in compliance reporting
- **Export-IntuneInventory.ps1**: Full device inventory with friendly names

## Contributing

Improvements welcome:
- New MTM mapping patterns
- Additional error handling
- Performance optimizations
- Integration examples

## License

See repository LICENSE file for details.
