# Windows Server Management Scripts

A comprehensive collection of PowerShell scripts for managing Windows Server 2016, 2019, and 2022 environments.

## 📋 Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Scripts](#scripts)
  - [Reset Windows Update](#1-reset-windows-update)
  - [Check System Integrity](#2-check-system-integrity)
  - [Get Disk Report](#3-get-disk-report)
  - [Set English UK Regional Settings](#4-set-english-uk-regional-settings)
  - [Remove US Language Pack](#5-remove-us-language-pack)
- [Usage Guidelines](#usage-guidelines)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

This collection provides essential system administration tools for Windows Server environments, focusing on:

- **System Maintenance**: Windows Update management and system integrity verification
- **Disk Management**: Comprehensive disk usage analysis and cleanup recommendations
- **Regional Configuration**: Automated locale and language pack management for UK environments

All scripts are designed with safety in mind, include detailed logging, and support common parameters for automation.

---

## Requirements

### System Requirements
- Windows Server 2016, 2019, or 2022
- PowerShell 5.1 or later
- Administrator privileges

### PowerShell Modules
Most scripts use built-in modules. Additional requirements are automatically checked and reported.

---

## Scripts

### 1. Reset Windows Update

**File**: `Reset-WindowsUpdate.ps1`

Resolves Windows Update issues by resetting all update components.

#### Features
- Stops and restarts Windows Update services
- Clears update cache and temporary files
- Re-registers Windows Update DLLs
- Resets Windows Update policies
- Optional BITS queue cleanup

#### Usage

**Basic Reset**:
```powershell
.\Reset-WindowsUpdate.ps1
```

**Full Reset** (includes BITS and Cryptographic services):
```powershell
.\Reset-WindowsUpdate.ps1 -FullReset
```

#### When to Use
- Windows Update is stuck or failing
- Updates won't download or install
- Error codes: 0x80070002, 0x8024402F, 0x80244007
- After resolving update conflicts

#### Output
- Real-time logging with color-coded status
- Service stop/start confirmation
- DLL registration count
- Final status report

---

### 2. Check System Integrity

**File**: `Check-SystemIntegrity.ps1`

Comprehensive system health verification using SFC, DISM, and event log analysis.

#### Features
- System File Checker (SFC) scan
- DISM component store verification
- Disk health analysis
- Critical event log review (24-hour window)
- Optional HTML report generation
- Automatic repair capability

#### Usage

**Standard Check**:
```powershell
.\Check-SystemIntegrity.ps1
```

**Quick Scan** (SFC only - faster):
```powershell
.\Check-SystemIntegrity.ps1 -QuickScan
```

**Auto-Repair with Report**:
```powershell
.\Check-SystemIntegrity.ps1 -AutoRepair -GenerateReport
```

#### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-QuickScan` | Runs SFC and basic DISM only | False |
| `-AutoRepair` | Automatically repairs detected issues | False |
| `-GenerateReport` | Creates HTML report on desktop | False |

#### Scan Time
- Quick Scan: 5-10 minutes
- Full Scan: 15-30 minutes
- With Repair: 20-45 minutes

#### When to Use
- Before major system changes
- After failed updates
- Troubleshooting system instability
- Regular health checks (monthly recommended)
- Server acting abnormally

---

### 3. Get Disk Report

**File**: `Get-DiskReport.ps1`

Analyzes disk usage and provides intelligent cleanup suggestions with potential space savings.

#### Features
- Detailed disk space analysis per volume
- Top 20 largest folders identification
- Temporary file analysis
- Log file analysis (System, IIS, WER)
- Windows Update cache size
- Recycle Bin analysis
- Safe cleanup command generation
- HTML report export

#### Usage

**Analyze All Drives**:
```powershell
.\Get-DiskReport.ps1
```

**Analyze Specific Drive with Report**:
```powershell
.\Get-DiskReport.ps1 -DriveLetter C -ExportReport
```

**Show Cleanup Suggestions Only**:
```powershell
.\Get-DiskReport.ps1 -ShowCleanupOnly
```

**Custom Minimum Folder Size**:
```powershell
.\Get-DiskReport.ps1 -MinimumFolderSizeMB 500
```

#### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-DriveLetter` | Specific drive to analyze (e.g., 'C') | All drives |
| `-ExportReport` | Generate HTML report | False |
| `-ShowCleanupOnly` | Skip full analysis, show cleanup only | False |
| `-MinimumFolderSizeMB` | Minimum folder size to include | 100 MB |

#### Cleanup Categories

The script identifies and suggests cleanup for:

1. **Windows Temp Files** (Low Risk)
   - Location: `C:\Windows\Temp`
   - Suggestion: Delete files older than 7 days

2. **User Temp Files** (Low Risk)
   - Location: `C:\Users\*\AppData\Local\Temp`
   - Suggestion: Delete files older than 7 days

3. **Windows Update Cache** (Low Risk)
   - Location: `C:\Windows\SoftwareDistribution\Download`
   - Suggestion: Clear after stopping wuauserv

4. **IIS Log Files** (Medium Risk)
   - Location: `C:\inetpub\logs\LogFiles`
   - Suggestion: Archive/delete logs older than 90 days

5. **Windows Error Reports** (Low Risk)
   - Location: `C:\ProgramData\Microsoft\Windows\WER`
   - Suggestion: Delete old error reports

6. **Recycle Bin** (Low Risk)
   - Suggestion: Empty permanently

7. **Old System Logs** (Low Risk)
   - Locations: Various log directories
   - Suggestion: Delete logs older than 90 days

8. **Previous Windows Installation** (Medium Risk)
   - Location: `C:\Windows.old`
   - Warning: Cannot rollback after deletion

#### Output Example
```
[2024-01-15 10:30:15] Starting disk analysis on SERVER01...

--- Drive C: ---
Total Size:    500.00 GB
Used Space:    380.50 GB
Free Space:    119.50 GB
Free Percent:  23.90%

========================================
CLEANUP SUGGESTIONS
========================================
Total Potential Savings: 45.32 GB

Category              Path                                    Size       Action
--------              ----                                    ----       ------
Windows Update Cache  C:\Windows\SoftwareDistribution\...    15.50 GB   Clear cache
IIS Log Files         C:\inetpub\logs\LogFiles               12.80 GB   Archive old logs
Windows Temp Files    C:\Windows\Temp                         8.20 GB   Delete old files
```

---

### 4. Set English UK Regional Settings

**File**: `Set-EnglishUKRegion.ps1`

Configures Windows Server to use English (UK) regional settings system-wide.

#### Features
- Sets system locale to en-GB
- Configures UK timezone (GMT/BST)
- Sets UK date format (DD/MM/YYYY)
- Configures 24-hour time format
- Sets currency to GBP (£)
- Configures metric measurements
- Sets first day of week to Monday
- Applies UK keyboard layout
- System-wide application (default user + welcome screen)
- Optional existing user profile updates

#### Usage

**Standard Configuration**:
```powershell
.\Set-EnglishUKRegion.ps1
```

**Apply to All Users**:
```powershell
.\Set-EnglishUKRegion.ps1 -ApplyToExistingUsers
```

**Custom Timezone**:
```powershell
.\Set-EnglishUKRegion.ps1 -TimeZone "GMT Standard Time"
```

**Skip Components**:
```powershell
.\Set-EnglishUKRegion.ps1 -SkipTimeZone -SkipKeyboard
```

#### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-TimeZone` | Timezone to set | GMT Standard Time |
| `-ApplyToExistingUsers` | Update all existing user profiles | False |
| `-SkipTimeZone` | Skip timezone configuration | False |
| `-SkipKeyboard` | Skip keyboard layout configuration | False |

#### Settings Applied

| Setting | Value |
|---------|-------|
| System Locale | en-GB |
| UI Language | English (United Kingdom) |
| Timezone | GMT Standard Time |
| Date Format | DD/MM/YYYY |
| Time Format | HH:mm:ss (24-hour) |
| Currency | £ (GBP) |
| Decimal Separator | . |
| Thousands Separator | , |
| First Day of Week | Monday |
| Measurement System | Metric |
| Keyboard Layout | UK English (0809:00000809) |

#### Important Notes
- A system restart is recommended after running
- Settings apply to system, new users, and welcome screen
- Existing users are only updated if `-ApplyToExistingUsers` is specified
- The script will prompt for restart unless automated

---

### 5. Remove US Language Pack

**File**: `Remove-USLanguagePack.ps1`

Removes US English (en-US) language packs and ensures UK English is properly configured.

#### Features
- Verifies en-GB is installed before removal
- Removes en-US language pack via DISM
- Removes US keyboard layout
- Cleans up language features on demand (FOD)
- Registry cleanup
- Optional system restore point creation
- Safety checks to prevent language removal issues

#### Usage

**Standard Removal**:
```powershell
.\Remove-USLanguagePack.ps1
```

**Force Removal with Backup**:
```powershell
.\Remove-USLanguagePack.ps1 -Force -BackupFirst
```

**Keep US Keyboard**:
```powershell
.\Remove-USLanguagePack.ps1 -KeepKeyboard
```

#### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-Force` | Skip confirmation prompts | False |
| `-KeepKeyboard` | Keep US keyboard layout | False |
| `-BackupFirst` | Create system restore point | False |

#### Safety Features

1. **Pre-flight Checks**:
   - Verifies en-GB is installed
   - Offers to install en-GB if missing
   - Confirms en-US is present

2. **Protection**:
   - Sets en-GB as default before removal
   - Optional restore point creation
   - Confirmation prompts (unless -Force)

3. **Thorough Removal**:
   - Language pack removal via DISM
   - Keyboard layout cleanup
   - Features on Demand removal
   - Registry cleanup
   - Verification step

#### What Gets Removed
- Microsoft-Windows-Client-Language-Pack (en-US)
- US keyboard layouts (unless `-KeepKeyboard`)
- Language.Basic~en-US
- Language.Handwriting~en-US
- Language.OCR~en-US
- Language.Speech~en-US
- Language.TextToSpeech~en-US
- Registry entries for en-US

#### Important Notes
- **Requires restart** to complete removal
- En-GB must be installed first
- Some residual entries may remain until restart
- Cannot be easily reversed - use `-BackupFirst` if uncertain

---

## Usage Guidelines

### Running Scripts

1. **Open PowerShell as Administrator**
   ```powershell
   # Right-click PowerShell and select "Run as Administrator"
   ```

2. **Navigate to Script Directory**
   ```powershell
   cd "C:\Path\To\Server Management Scripts"
   ```

3. **Check Execution Policy**
   ```powershell
   Get-ExecutionPolicy
   ```
   If restricted, temporarily allow:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   ```

4. **Run Script**
   ```powershell
   .\ScriptName.ps1 -Parameters
   ```

### Getting Help

All scripts include detailed help:
```powershell
Get-Help .\ScriptName.ps1 -Detailed
Get-Help .\ScriptName.ps1 -Examples
Get-Help .\ScriptName.ps1 -Full
```

---

## Best Practices

### Before Running Scripts

1. **Take Backups**
   - Create system restore point
   - Backup critical data
   - Document current configuration

2. **Test in Non-Production**
   - Run on test server first
   - Verify expected behavior
   - Check for conflicts

3. **Review Parameters**
   - Read script help
   - Understand what changes will be made
   - Use appropriate switches

### During Execution

1. **Monitor Output**
   - Watch for errors or warnings
   - Note any failed operations
   - Check log messages

2. **Don't Interrupt**
   - Allow scripts to complete
   - Avoid Ctrl+C during critical operations
   - Wait for confirmation messages

### After Execution

1. **Verify Changes**
   - Check that expected changes were applied
   - Test affected functionality
   - Review generated reports

2. **Restart if Recommended**
   - Many changes require restart
   - Schedule during maintenance window
   - Notify users if applicable

3. **Keep Logs**
   - Save HTML reports
   - Note any errors for troubleshooting
   - Document successful runs

---

## Troubleshooting

### Common Issues

#### "Access Denied" Errors
**Cause**: Not running as Administrator
**Solution**:
```powershell
# Right-click PowerShell > Run as Administrator
```

#### "Execution Policy" Errors
**Cause**: Script execution is disabled
**Solution**:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
# Then run your script
```

#### Script Doesn't Start
**Cause**: Path issues or incorrect file name
**Solution**:
```powershell
# Ensure you're in the correct directory
cd "C:\Path\To\Server Management Scripts"

# List files to verify name
Get-ChildItem *.ps1

# Run with full path if needed
& "C:\Path\To\Server Management Scripts\ScriptName.ps1"
```

#### Changes Don't Apply
**Cause**: Restart required
**Solution**: Restart the server after running scripts that modify system settings

#### "Module Not Found" Errors
**Cause**: Required PowerShell module not available
**Solution**: Scripts will report missing modules - install if needed

### Script-Specific Issues

#### Reset-WindowsUpdate.ps1
- **Issue**: Services won't stop
  - Try running multiple times
  - Check for group policy restrictions
  - Reboot and retry

#### Check-SystemIntegrity.ps1
- **Issue**: Scan takes too long
  - Use `-QuickScan` for faster results
  - Run during low-usage periods
  - Check disk performance

#### Get-DiskReport.ps1
- **Issue**: Folder analysis is slow
  - Increase `-MinimumFolderSizeMB` to reduce scan scope
  - Use `-ShowCleanupOnly` to skip full analysis
  - Run on specific drives only

#### Set-EnglishUKRegion.ps1
- **Issue**: Settings revert after restart
  - Use `-ApplyToExistingUsers`
  - Check for group policy overrides
  - Verify changes applied to default user profile

#### Remove-USLanguagePack.ps1
- **Issue**: en-US still appears after removal
  - Restart the server
  - Run DISM cleanup: `DISM /Online /Cleanup-Image /StartComponentCleanup`
  - Re-run script with `-Force`

---

## Support and Contributions

### Getting Help

If you encounter issues:
1. Review script help: `Get-Help .\ScriptName.ps1 -Full`
2. Check the troubleshooting section above
3. Review script output and error messages
4. Check Windows Event Logs for related errors

### Script Customization

All scripts can be modified to suit your environment:
- Edit parameters and default values
- Customize log output formats
- Add organization-specific checks
- Integrate with monitoring systems

### Safety Notes

- Always test in non-production first
- Read script contents before running
- Understand what changes will be made
- Keep backups of important data
- Use `-WhatIf` parameter where available (future enhancement)

---

## Version History

**Version 1.0** - Initial Release
- Reset Windows Update script
- System Integrity Check script
- Disk Report and Cleanup script
- English UK Regional Settings script
- US Language Pack Removal script

---

## License

These scripts are provided as-is for system administration purposes. Use at your own risk and always test in non-production environments first.

---

## Quick Reference

| Task | Script | Basic Command |
|------|--------|---------------|
| Fix Windows Update | Reset-WindowsUpdate.ps1 | `.\Reset-WindowsUpdate.ps1` |
| Check System Health | Check-SystemIntegrity.ps1 | `.\Check-SystemIntegrity.ps1 -GenerateReport` |
| Analyze Disk Space | Get-DiskReport.ps1 | `.\Get-DiskReport.ps1 -ExportReport` |
| Configure UK Settings | Set-EnglishUKRegion.ps1 | `.\Set-EnglishUKRegion.ps1 -ApplyToExistingUsers` |
| Remove US Language | Remove-USLanguagePack.ps1 | `.\Remove-USLanguagePack.ps1 -BackupFirst` |

---

**Last Updated**: 2024-01-15
**Compatible**: Windows Server 2016, 2019, 2022
**PowerShell**: 5.1+
