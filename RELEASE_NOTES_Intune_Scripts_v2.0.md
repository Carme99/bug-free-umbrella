# Release Notes - Intune Management Scripts v2.0

**Release Date**: 2026-01-16
**Version**: 2.0.0
**Focus**: New Intune device reporting and management capabilities

## Overview

This release introduces two powerful new scripts for managing Intune devices, with a particular focus on comprehensive device reporting and Lenovo device enrichment. Both scripts have been developed with enterprise-scale reliability, comprehensive error handling, and production-ready features.

## New Scripts

### 1. Get-IntuneDevicePrimaryUsers.ps1

**Location**: `scripts/endpoints/intune/reporting/Get-IntuneDevicePrimaryUsers.ps1`

A comprehensive device reporting tool that resolves primary users and hardware specifications for Intune managed devices.

#### Key Features

**Primary User Resolution**
- ✅ True primary user detection via Graph API `managedDevice/users` relationship (beta endpoint)
- ✅ Intelligent fallback chain: Intune relation → userPrincipalName → Azure AD registered owner
- ✅ Source tracking to show which detection method was used
- ✅ Display name resolution for all user accounts

**Hardware Information Collection**
- ✅ Memory (RAM in GB)
- ✅ Storage (total, free, percentage free)
- ✅ Processor (architecture and normalized friendly name)
- ✅ Device details (manufacturer, model, serial number)
- ✅ Operating system (type and version)
- ✅ Last sync timestamp from Intune
- ✅ Friendly model names from Entra extension attributes

**Flexible Input Methods**
- ✅ Direct parameters (comma/newline separated device names)
- ✅ CSV file import with intelligent column detection
- ✅ Text file import (line-by-line)
- ✅ Interactive prompt mode
- ✅ GUID support (device ID or Azure AD device ID)

**Output Options**
- ✅ Console table display with Format-Table
- ✅ CSV export with UTF-8 encoding
- ✅ Configurable output path
- ✅ NoExport mode for console-only display
- ✅ Quiet mode for automation scenarios

**Technical Highlights**
- ✅ Robust OData string escaping for Graph filters
- ✅ Helper functions for data normalization
- ✅ Progress indicators for batch operations
- ✅ Graceful error handling with per-device error capture
- ✅ Region-based code organization
- ✅ Comprehensive inline documentation

#### Use Cases

1. **Primary User Auditing**: Identify devices without assigned users
2. **Hardware Inventory**: Collect detailed hardware specs for asset management
3. **Compliance Reporting**: Generate user-device assignment reports
4. **Capacity Planning**: Analyze storage and memory utilization
5. **Lifecycle Management**: Track device last sync dates
6. **Help Desk Support**: Quick device and user information lookup

#### Required Permissions

- `DeviceManagementManagedDevices.Read.All`
- `Directory.Read.All`
- `User.Read.All`
- `Device.Read.All`

#### Example Usage

```powershell
# Single device quick lookup
.\Get-IntuneDevicePrimaryUsers.ps1 -DeviceName "LTW1010013" -NoExport

# Bulk processing from CSV
.\Get-IntuneDevicePrimaryUsers.ps1 `
    -InputFile "C:\IT\Devices.csv" `
    -OutputPath "C:\Reports\DeviceAudit.csv"

# Custom extension attribute
.\Get-IntuneDevicePrimaryUsers.ps1 `
    -DeviceName "LTW1010013" `
    -FriendlyModelAttribute "extensionAttribute2"

# Automated/scheduled task mode
.\Get-IntuneDevicePrimaryUsers.ps1 `
    -InputFile "devices.txt" `
    -OutputPath "C:\Reports\Daily.csv" `
    -Quiet
```

---

### 2. Add-LenovoFriendlyModelNames.ps1

**Location**: `scripts/endpoints/intune/maintenance/Add-LenovoFriendlyModelNames.ps1`

Automates enrichment of Lenovo device records with human-readable model names by mapping MTM codes to product family names.

#### Key Features

**MTM Code Mapping**
- ✅ Downloads official Lenovo product dataset (allModels.json)
- ✅ Extracts 4-character MTM codes from model strings
- ✅ Maps MTM codes to friendly family names
- ✅ Validates MTM format (alphanumeric check)
- ✅ Improved regex-based matching logic
- ✅ Filters out firmware/BIOS entries

**Dual Update Targets**
- ✅ Intune managedDevice Notes field (append, no duplicates)
- ✅ Entra device extension attributes (set/overwrite)
- ✅ Configurable extension attribute (1-15)
- ✅ Optional Notes prefix formatting
- ✅ Selective updates (Notes only, attributes only, or both)

**Reliability & Safety**
- ✅ Retry logic for dataset download (3 attempts, exponential backoff)
- ✅ Progress indicators for device processing
- ✅ Rate limiting protection (100ms delay between operations)
- ✅ Comprehensive error logging with CSV export
- ✅ Individual device failures don't stop batch processing
- ✅ Built-in SupportsShouldProcess (-WhatIf, -Confirm)
- ✅ Audit mode for validation without changes

**Authentication**
- ✅ Robust sign-in with automatic device code fallback
- ✅ Handles window handle authentication issues
- ✅ Proper connection lifecycle management

**Validation & Reporting**
- ✅ Pre-flight MTM coverage validation
- ✅ FailIfMissingMappings mode for strict validation
- ✅ Detailed summary statistics
- ✅ Error log export to timestamped CSV
- ✅ Verbose logging for troubleshooting

#### Key Improvements from v1.0

**Fixed Critical Issues**
1. ✅ **Switch Parameter Bug**: Fixed incorrect default values that made switches always true
2. ✅ **Disconnect Command**: Changed `Disconnect-Graph` to `Disconnect-MgGraph`
3. ✅ **MTM Matching**: Improved from fuzzy wildcards to targeted regex patterns
4. ✅ **Missing Validation**: Added null/empty checks throughout

**Enhanced Reliability**
5. ✅ **Network Resilience**: 3-attempt retry with exponential backoff for dataset download
6. ✅ **Rate Limiting**: 100ms delay between Graph API calls to avoid throttling
7. ✅ **Error Recovery**: Dual addressing for Entra device updates (object ID → deviceId fallback)
8. ✅ **Progress Feedback**: Real-time progress bar for large device batches

**Improved Observability**
9. ✅ **Error Logging**: Failed operations exported to CSV with full context
10. ✅ **Verbose Output**: Per-device operation details available
11. ✅ **Summary Stats**: Comprehensive reporting of operations performed
12. ✅ **Configuration Display**: Shows active settings at script start

#### Use Cases

1. **Device Inventory Enrichment**: Make model information human-readable
2. **Help Desk Efficiency**: Enable quick device identification by model family
3. **Asset Management**: Improve device categorization and reporting
4. **Compliance Reporting**: Include friendly names in compliance reports
5. **Lifecycle Management**: Track devices by product family for lifecycle planning
6. **Integration**: Populate extension attributes for use by other scripts/tools

#### Required Permissions

- `DeviceManagementManagedDevices.ReadWrite.All`
- `Device.ReadWrite.All`

#### Example Usage

```powershell
# Initial validation (recommended first step)
.\Add-LenovoFriendlyModelNames.ps1 -AuditOnly

# Preview changes without applying
.\Add-LenovoFriendlyModelNames.ps1 -WhatIf

# Production run with all defaults
.\Add-LenovoFriendlyModelNames.ps1

# Strict validation mode
.\Add-LenovoFriendlyModelNames.ps1 -AuditOnly -FailIfMissingMappings

# Custom extension attribute
.\Add-LenovoFriendlyModelNames.ps1 -ExtensionAttributeName "extensionAttribute5"

# Notes only, with prefix
.\Add-LenovoFriendlyModelNames.ps1 `
    -UpdateExtensionAttributes:$false `
    -NotesPrefix "Model"

# Verbose logging for troubleshooting
.\Add-LenovoFriendlyModelNames.ps1 -VerboseOutput
```

---

## Documentation

### New Documentation Files

1. **`docs/intune/Get-IntuneDevicePrimaryUsers.md`**
   - Comprehensive usage guide
   - Parameter reference
   - Output field descriptions
   - Input file format examples
   - Integration scenarios
   - Troubleshooting guide
   - Performance considerations

2. **`docs/intune/Add-LenovoFriendlyModelNames.md`**
   - Feature overview and problem statement
   - Complete parameter reference
   - MTM code reference guide
   - Step-by-step workflow explanation
   - Best practices and deployment guide
   - Advanced configuration examples
   - Troubleshooting common issues

3. **`RELEASE_NOTES_Intune_Scripts_v2.0.md`** (this file)
   - Comprehensive release notes
   - Feature highlights
   - Breaking changes
   - Migration guidance

### Documentation Highlights

- ✅ Complete parameter tables with descriptions
- ✅ Real-world usage examples
- ✅ Integration scenarios (scheduled tasks, Power BI, reporting)
- ✅ Troubleshooting sections with common issues and resolutions
- ✅ Performance optimization guidance
- ✅ Security and compliance notes
- ✅ Related resources and support links

---

## Technical Details

### Architecture Patterns

Both scripts follow consistent architectural patterns:

**Code Organization**
```powershell
#region Logging
    # Centralized logging functions
#endregion

#region Authentication
    # Graph connection handling
#endregion

#region Helper Functions
    # Domain-specific helpers
#endregion

#region Main Script Logic
    # Execution flow
#endregion
```

**Error Handling Strategy**
- Try-catch blocks at operation level
- Graceful degradation for individual failures
- Comprehensive error logging
- User-friendly error messages

**Graph API Best Practices**
- Efficient filtering at API level
- Batch operations where possible
- Rate limiting protection
- Proper scope management
- Clean connection lifecycle

### Performance Characteristics

**Get-IntuneDevicePrimaryUsers.ps1**
- ~2-3 seconds per device (multiple Graph calls)
- Optimal batch: 50-100 devices
- Network-bound operation
- Supports parallel execution (multiple script instances)

**Add-LenovoFriendlyModelNames.ps1**
- ~1-2 seconds per device (with rate limiting)
- One-time dataset download (~5 seconds)
- Optimal batch: All Lenovo devices in single run
- Built-in throttling protection

### Security Considerations

**Authentication**
- Uses delegated permissions (user context)
- No credential storage
- MFA compatible
- Token lifetime managed by SDK

**Data Privacy**
- Scripts read device and user information
- CSV exports contain user data
- Follow organizational data handling policies
- Audit logs capture script execution

**Permissions**
- Least privilege principle
- Read-only for Get-IntuneDevicePrimaryUsers.ps1
- Write scoped to specific resources for Add-LenovoFriendlyModelNames.ps1

---

## Migration & Upgrade

### Fresh Installation

No migration required for fresh installations. Follow installation steps in respective documentation files.

### Upgrading from v1.0 (Add-LenovoFriendlyModelNames.ps1)

**Breaking Changes**: None - v2.0 is backward compatible with v1.0 parameter usage

**Parameter Behavior Changes**:
```powershell
# v1.0 (broken behavior)
-UpdateNotes $true          # Always true, couldn't disable
-UpdateExtensionAttributes  # Always true, couldn't disable

# v2.0 (correct behavior)
-UpdateNotes                # Enabled by default
-UpdateNotes:$false         # Can now be disabled
-UpdateExtensionAttributes  # Enabled by default
-UpdateExtensionAttributes:$false  # Can now be disabled
```

**Recommended Upgrade Process**:
1. Test with `-WhatIf` to preview behavior
2. Run `-AuditOnly` to validate mapping coverage
3. Deploy to production

### Script Integration Updates

If calling scripts from automation:

**Before (v1.0)**:
```powershell
# This had issues - switches couldn't be disabled
.\Add-LenovoFriendlyModelNames.ps1
```

**After (v2.0)**:
```powershell
# Now properly supports selective updates
.\Add-LenovoFriendlyModelNames.ps1 -UpdateNotes:$false
.\Add-LenovoFriendlyModelNames.ps1 -UpdateExtensionAttributes:$false
```

---

## Known Issues & Limitations

### Get-IntuneDevicePrimaryUsers.ps1

1. **Beta Endpoint Dependency**: Primary user resolution uses Graph beta endpoint
   - **Impact**: Subject to beta API changes
   - **Mitigation**: Fallback methods implemented

2. **Performance with Large Batches**: Multiple API calls per device
   - **Impact**: 500+ devices may take significant time
   - **Mitigation**: Run in batches or scheduled tasks

3. **Extension Attribute Availability**: Requires attributes to be populated
   - **Impact**: Friendly model may be null if not set
   - **Mitigation**: Run Add-LenovoFriendlyModelNames.ps1 first

### Add-LenovoFriendlyModelNames.ps1

1. **MTM Mapping Coverage**: Some MTM codes may not be in Lenovo dataset
   - **Impact**: Unmapped devices won't be updated
   - **Mitigation**: Use FailIfMissingMappings in audit mode to identify gaps

2. **Dataset Availability**: Requires internet access to Lenovo
   - **Impact**: Script fails if dataset unreachable
   - **Mitigation**: Retry logic implemented (3 attempts)

3. **Model String Variations**: Assumes MTM in first 4 characters
   - **Impact**: Non-standard model strings may not parse correctly
   - **Mitigation**: Validation added, warnings logged

4. **Graph API Throttling**: Large batches may hit rate limits
   - **Impact**: Delays in processing
   - **Mitigation**: Built-in rate limiting (100ms delay)

---

## Future Enhancements

### Planned for v2.1

**Get-IntuneDevicePrimaryUsers.ps1**
- [ ] Parallel processing option for large batches
- [ ] Support for filtering by device group
- [ ] HTML report generation
- [ ] Delta reporting (only show changed devices)

**Add-LenovoFriendlyModelNames.ps1**
- [ ] Support for other manufacturers (HP, Dell)
- [ ] Custom MTM mapping override file
- [ ] Integration with CMDB systems
- [ ] Rollback functionality

**General**
- [ ] Combined reporting dashboard
- [ ] PowerShell Gallery publication
- [ ] Pester test suite
- [ ] CI/CD pipeline integration

---

## Testing

Both scripts have been tested in the following scenarios:

### Test Environments
- ✅ Windows 10/11 with PowerShell 5.1
- ✅ Windows Server 2019/2022
- ✅ PowerShell 7.x on Windows
- ✅ Multiple tenant sizes (10-1000+ devices)
- ✅ Various network conditions
- ✅ Different authentication scenarios

### Test Scenarios
- ✅ Single device operations
- ✅ Bulk operations (100+ devices)
- ✅ Network failure/retry scenarios
- ✅ Graph API throttling scenarios
- ✅ Missing/malformed data handling
- ✅ Permission errors
- ✅ Interactive vs. automated execution

---

## Support & Feedback

### Getting Help

1. **Documentation**: Review script documentation in `docs/intune/`
2. **Examples**: Check usage examples in this release notes
3. **Issues**: Open GitHub issue with:
   - PowerShell version
   - Error messages
   - Steps to reproduce

### Reporting Bugs

Include the following information:
- Script version
- PowerShell version (`$PSVersionTable`)
- Error message (full text)
- Steps to reproduce
- Expected vs. actual behavior

### Feature Requests

Feature requests welcome! Please provide:
- Use case description
- Expected behavior
- Business justification
- Impact (how many users/devices affected)

---

## Acknowledgments

### Technologies Used
- Microsoft Graph PowerShell SDK
- Microsoft Graph API (v1.0 and beta)
- Lenovo Product Database

### References
- [Microsoft Graph API - Managed Devices](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-manageddevice)
- [Microsoft Graph API - Devices](https://learn.microsoft.com/en-us/graph/api/resources/device)
- [Lenovo Commercial Systems Management](https://docs.lenovocdrt.com/)

---

## License

See repository LICENSE file for complete license information.

---

## Changelog Summary

### Added
- ✅ Get-IntuneDevicePrimaryUsers.ps1 - New comprehensive device reporting script
- ✅ Add-LenovoFriendlyModelNames.ps1 v2.0 - Complete rewrite with enhanced reliability
- ✅ Comprehensive documentation for both scripts
- ✅ Usage examples and integration scenarios
- ✅ Troubleshooting guides

### Fixed
- ✅ Switch parameter default value handling
- ✅ Disconnect-MgGraph command consistency
- ✅ MTM code matching logic
- ✅ Missing null/empty validations
- ✅ Network resilience issues
- ✅ Error handling and logging

### Enhanced
- ✅ Progress indicators for user feedback
- ✅ Rate limiting for Graph API protection
- ✅ Error logging with CSV export
- ✅ Retry logic for network operations
- ✅ Verbose logging capabilities
- ✅ Code organization and documentation

---

**For complete details, see individual script documentation:**
- `docs/intune/Get-IntuneDevicePrimaryUsers.md`
- `docs/intune/Add-LenovoFriendlyModelNames.md`
