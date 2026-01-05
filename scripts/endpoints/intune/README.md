# Intune Management Scripts

> **⚠️ IMPORTANT NOTICE**: The vast majority of scripts in this repository have not been thoroughly tested in production environments. Please test all scripts in a non-production environment first and validate the results before relying on this data for operational decisions.

A comprehensive PowerShell toolkit for managing and reporting on Microsoft Intune environments. These scripts help automate common Intune administration tasks, generate reports, and streamline device management.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Scripts](#scripts)
- [Quick Start](#quick-start)
- [Common Scenarios](#common-scenarios)
- [Troubleshooting](#troubleshooting)

---

## Overview

This toolkit provides **24 PowerShell scripts** for comprehensive Intune management:

### 📊 Reporting Scripts (11 scripts)
- **Device Compliance Report** - Export non-compliant devices with reasons
- **BitLocker Encryption Status** - Audit encryption across your estate
- **Windows Update Compliance** - Track update status (AutoPatch compatible)
- **Application Installation Status** - Check app deployment success/failures
- **App Install Error Report** - Detailed app failure analysis with error codes
- **Autopilot Deployment Report** - Track Autopilot success/failures
- **Winget Update Compliance** - Report on winget-managed app versions
- **Policy Assignment Report** 🆕 - Comprehensive policy assignments with conflict detection
- **Device Health Score** 🆕 - Aggregated health score based on multiple metrics
- **User Device Affinity** 🆕 - User-device relationships for license management
- **Device Group Membership** - Show device-to-group mappings

### 🧹 Maintenance Scripts (6 scripts)
- **Stale Device Finder** - Identify and remove inactive devices
- **Policy Conflict Detector** - Find conflicting configuration policies
- **Device Bulk Actions** - Bulk sync, restart, retire, wipe, collect diagnostics
- **Export Intune Configuration** - Backup all policies, apps, and configs
- **Test Intune Connectivity** 🆕 - Validate connectivity to all Intune endpoints
- **Compare Configuration Drift** 🆕 - Track configuration changes over time

### 🚀 Deployment & Packaging (6 scripts)
- **Winget Remediation Generator** - Auto-create proactive remediation scripts
- **Bulk Winget Updater** - Universal winget package updater for ANY app
- **Winget Source Config** - Configure custom enterprise winget sources
- **Export Winget Package List** - Inventory winget-installed apps
- **Bulk App Packager** - Convert installers to .intunewin format
- **Win32 App Template** - Generate complete deployment packages

### 🔧 Helper Module
- **IntuneGraphHelper** - Common functions for Graph API authentication and reporting

---

## Prerequisites

### Required Software
- **PowerShell 5.1** or later (PowerShell 7+ recommended)
- **Microsoft.Graph PowerShell SDK**
  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser
  ```

### Required Permissions

Most scripts require these Graph API permissions:
- `DeviceManagementManagedDevices.Read.All`
- `DeviceManagementConfiguration.Read.All`
- `DeviceManagementApps.Read.All`

Additional permissions for specific scripts:
- **BitLocker Status**: `BitlockerKey.Read.All`
- **Stale Devices (delete/retire)**: `DeviceManagementManagedDevices.ReadWrite.All`
- **Group Membership**: `Group.Read.All`, `Device.Read.All`

### Azure AD Role Requirements
- **Intune Administrator** or **Global Reader** (minimum for read-only reports)
- **Intune Administrator** or **Global Administrator** (for modification scripts)

---

## Installation

### 1. Clone or Download
```powershell
# Clone the repository
git clone https://github.com/Carme99/bug-free-umbrella.git
cd "bug-free-umbrella/Intune Management Scripts"
```

### 2. Install Microsoft.Graph Module
```powershell
# Install Graph SDK
Install-Module Microsoft.Graph -Scope CurrentUser -Force

# Import the module
Import-Module Microsoft.Graph
```

### 3. Test Authentication
```powershell
# Test connection
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All"
Get-MgContext
Disconnect-MgGraph
```

---

## Scripts

### Winget Management (NEW!)

#### New-BulkWingetUpdater.ps1

Universal winget package updater that generates remediation scripts for ANY application.

**Features**:
- Works with any winget package ID
- Generates both detect.ps1 and remediate.ps1
- Prevents forced app closure
- Batch creation from CSV
- Intune-ready deployment scripts

**Usage**:
```powershell
# Single app
.\New-BulkWingetUpdater.ps1 -AppName "Google Chrome" -WingetID "Google.Chrome" -ProcessName "chrome"

# Batch from CSV (AppName,WingetID,ProcessName)
.\New-BulkWingetUpdater.ps1 -GenerateBatch -CSVPath ".\apps.csv"
```

---

#### Get-WingetUpdateCompliance.ps1

Reports winget-managed application update compliance across devices.

**Features**:
- Track app versions across estate
- Identify outdated applications
- Compliance reporting
- HTML/CSV export

**Usage**:
```powershell
.\Get-WingetUpdateCompliance.ps1 -ExportHTML
.\Get-WingetUpdateCompliance.ps1 -ApplicationFilter "*Chrome*"
```

---

#### Export-WingetPackageList.ps1

Exports installed winget packages from devices for inventory.

**Features**:
- JSON/CSV/Console output
- Source filtering
- Version tracking
- Update availability detection

**Usage**:
```powershell
.\Export-WingetPackageList.ps1
.\Export-WingetPackageList.ps1 -ExportFormat JSON -OutputPath "C:\Temp\packages.json"
```

---

#### New-WingetSourceConfig.ps1

Configures custom winget sources for enterprise environments.

**Features**:
- Add enterprise repositories
- Remove default sources
- Reset configuration
- Generate Intune deployment scripts

**Usage**:
```powershell
.\New-WingetSourceConfig.ps1 -SourceName "CompanyRepo" -SourceURL "https://packages.company.com" -GenerateIntuneScript
.\New-WingetSourceConfig.ps1 -ResetSources
```

---

### Device Management (NEW!)

#### Invoke-DeviceBulkActions.ps1

Performs bulk actions on Intune-managed devices.

**Features**:
- Sync, Restart, Retire, Wipe, Collect Diagnostics
- Filter by name, group, compliance
- WhatIf support
- Detailed results reporting

**Usage**:
```powershell
.\Invoke-DeviceBulkActions.ps1 -Action Sync -DeviceNames "PC-01,PC-02"
.\Invoke-DeviceBulkActions.ps1 -Action CollectDiagnostics -GroupName "IT-Test"
.\Invoke-DeviceBulkActions.ps1 -Action Restart -NonCompliantOnly -WhatIf
```

---

#### Get-AutopilotDeploymentReport.ps1

Tracks Windows Autopilot deployment status and failures.

**Features**:
- Success/failure rates
- ESP error tracking
- Deployment duration
- Failed deployment details

**Usage**:
```powershell
.\Get-AutopilotDeploymentReport.ps1 -Days 7 -ExportHTML
.\Get-AutopilotDeploymentReport.ps1 -Status Failed
```

---

#### Export-IntuneConfiguration.ps1

Exports Intune configuration for backup or migration.

**Features**:
- Device/compliance policies
- Apps and scripts
- Autopilot profiles
- Assignment export
- ZIP compression

**Usage**:
```powershell
.\Export-IntuneConfiguration.ps1
.\Export-IntuneConfiguration.ps1 -ConfigTypes "DeviceConfig,Compliance" -CompressOutput
```

---

#### Get-AppInstallErrorReport.ps1

Detailed analysis of application installation failures.

**Features**:
- Error code analysis
- Device/user-specific failures
- Installation history
- Remediation suggestions

**Usage**:
```powershell
.\Get-AppInstallErrorReport.ps1 -Days 7 -ExportHTML
.\Get-AppInstallErrorReport.ps1 -AppName "Microsoft Teams"
```

---

### Existing Scripts

#### 1. Get-DeviceComplianceReport.ps1

Exports all non-compliant devices with detailed compliance policy failures.

**Usage:**
```powershell
# Basic report
.\Get-DeviceComplianceReport.ps1

# Include compliant devices
.\Get-DeviceComplianceReport.ps1 -IncludeCompliant

# Export as CSV
.\Get-DeviceComplianceReport.ps1 -ExportFormat CSV
```

**Output:**
- HTML and/or CSV report on desktop
- Device name, user, compliance state, failure reasons
- Summary statistics

**When to use:**
- Monthly compliance audits
- Troubleshooting policy issues
- Security assessments

---

### 2. Find-StaleDevices.ps1

Identifies devices that haven't synced in X days, with optional cleanup.

**Usage:**
```powershell
# Interactive mode (prompts for days)
.\Find-StaleDevices.ps1

# Specify days directly
.\Find-StaleDevices.ps1 -DaysInactive 90

# Delete stale devices (CAUTION!)
.\Find-StaleDevices.ps1 -DaysInactive 180 -Action Delete

# Retire stale devices
.\Find-StaleDevices.ps1 -DaysInactive 180 -Action Retire
```

**Parameters:**
- `-DaysInactive` - Inactivity threshold (prompts if not provided)
- `-Action` - Report, Delete, or Retire (default: Report)
- `-AutoConfirm` - Skip confirmation prompts (dangerous!)

**Safety Features:**
- Confirmation required before deletions
- "YES" typed confirmation for bulk actions
- Export report before taking action

**Recommended Thresholds:**
- **30 days** - Flag for review
- **90 days** - Standard stale threshold
- **180 days** - Safe deletion threshold

---

### 3. Get-AppInstallationStatus.ps1

Checks installation status of specific apps across all devices.

**Usage:**
```powershell
# Interactive app selection
.\Get-AppInstallationStatus.ps1

# Search by name
.\Get-AppInstallationStatus.ps1 -AppName "Google Chrome"

# Show only failures
.\Get-AppInstallationStatus.ps1 -AppName "Chrome" -ShowFailuresOnly
```

**Output:**
- Installation status per device
- Success/failure/pending counts
- Error codes for failures
- HTML and CSV reports

**Perfect for:**
- Troubleshooting app deployments
- Verifying rollout progress
- Finding installation failures

---

### 4. Get-BitLockerStatus.ps1

Audits BitLocker encryption status and recovery key backups.

**Usage:**
```powershell
# Full encryption audit
.\Get-BitLockerStatus.ps1

# Show only unencrypted devices
.\Get-BitLockerStatus.ps1 -ShowUnencryptedOnly

# Show devices missing key backups
.\Get-BitLockerStatus.ps1 -ShowMissingKeys
```

**Reports on:**
- Encryption status per device
- Recovery key backup status
- Compliance recommendations
- Devices at risk

**Compliance Use:**
- Monthly encryption audits
- Recovery key verification
- Security posture assessments

---

### 5. Get-WindowsUpdateCompliance.ps1

Generates Windows Update compliance reports, including AutoPatch integration.

**Usage:**
```powershell
# Basic update compliance
.\Get-WindowsUpdateCompliance.ps1

# Show only non-compliant
.\Get-WindowsUpdateCompliance.ps1 -ShowNonCompliantOnly

# Include AutoPatch ring info
.\Get-WindowsUpdateCompliance.ps1 -IncludeAutoPatchInfo

# Custom outdated threshold
.\Get-WindowsUpdateCompliance.ps1 -DaysOutdated 60
```

**Features:**
- Update compliance status
- Days since last update check
- AutoPatch deployment rings
- Outdated device identification

**AutoPatch Users:**
- Use `-IncludeAutoPatchInfo` for ring visibility
- Track update rollout progress
- Identify devices falling behind

---

### 6. New-WingetRemediationScript.ps1

Generates proactive remediation script pairs for Winget package updates.

**Usage:**
```powershell
# Interactive mode
.\New-WingetRemediationScript.ps1

# Specify package
.\New-WingetRemediationScript.ps1 -PackageId "Google.Chrome"

# With README
.\New-WingetRemediationScript.ps1 -PackageId "Mozilla.Firefox" -IncludeReadme
```

**Creates:**
- `detect.ps1` - Checks if update is available
- `remediate.ps1` - Updates the package silently
- `README.md` - Deployment instructions (optional)

**Supported Apps:**
- Any app in Winget repository
- Search packages at https://winget.run
- Examples: Chrome, Firefox, 7-Zip, VSCode, etc.

**Deployment:**
1. Generate scripts for your app
2. Upload to **Intune > Devices > Scripts and remediations**
3. Configure as SYSTEM, 64-bit PowerShell
4. Assign to device groups
5. Set schedule (daily/weekly)

---

### 7. Find-PolicyConflicts.ps1

Analyzes configuration policies to identify conflicts and overlaps.

**Usage:**
```powershell
# Analyze configuration profiles
.\Find-PolicyConflicts.ps1

# Include Settings Catalog
.\Find-PolicyConflicts.ps1 -CheckSettingsCatalog

# Include compliance policies
.\Find-PolicyConflicts.ps1 -CheckCompliancePolicies
```

**Detects:**
- Overlapping assignments
- Duplicate policy names
- Same policy types on same targets
- Potential conflicts

**Severity Levels:**
- **High** - Same policy type, same target (likely conflict)
- **Medium** - Overlapping assignments
- **Low** - Duplicate names (clarity issue)

**Use When:**
- Troubleshooting unexpected device configs
- Policy cleanup projects
- Audit exercises

---

### 8. Get-DeviceGroupMembership.ps1

Shows which devices belong to which Azure AD groups.

**Usage:**
```powershell
# Show groups for specific device
.\Get-DeviceGroupMembership.ps1 -DeviceName "DESKTOP-ABC123"

# Show devices in specific group
.\Get-DeviceGroupMembership.ps1 -GroupName "Windows 10 Devices"

# Full device-to-group matrix
.\Get-DeviceGroupMembership.ps1 -ShowAllMappings

# Only dynamic groups
.\Get-DeviceGroupMembership.ps1 -DeviceName "PC01" -ShowDynamicGroupsOnly
```

**Perfect for:**
- Troubleshooting policy targeting
- Verifying dynamic group rules
- Understanding device categorization
- Assignment validation

---

### 9. New-IntuneWinPackage.ps1

Bulk converts installers to .intunewin format.

**Usage:**
```powershell
# Convert all installers in folder
.\New-IntuneWinPackage.ps1 -SourceFolder "C:\Installers"

# Convert single file
.\New-IntuneWinPackage.ps1 -SetupFile "C:\Installers\app.exe"
```

**Features:**
- Auto-downloads IntuneWinAppUtil.exe if missing
- Batch processing
- Progress tracking
- Package validation

**Prerequisites:**
- IntuneWinAppUtil.exe (auto-downloaded)
- Installer files organized in folders

---

### 10. New-Win32AppTemplate.ps1

Generates complete Win32 app deployment packages with detection and requirements scripts.

**Usage:**
```powershell
# Interactive mode
.\New-Win32AppTemplate.ps1

# Specify details
.\New-Win32AppTemplate.ps1 -AppName "7-Zip" `
    -InstallCommand "7z-x64.exe /S" `
    -DetectionType "Registry"
```

**Detection Types:**
- **Registry** - Check registry key/value
- **File** - Verify file or folder exists
- **MSI** - Check MSI product code
- **Script** - Custom PowerShell logic

**Creates:**
- `detection.ps1` - Detects if app is installed
- `requirements.ps1` - Checks device prerequisites
- `README.md` - Complete deployment guide

---

### 11. IntuneGraphHelper.psm1

Common helper module used by all scripts.

**Functions:**
- `Connect-IntuneGraph` - Authenticate to Graph API
- `Get-AllIntuneDevices` - Retrieve all managed devices
- `Export-IntuneReportToHTML` - Generate HTML reports
- `Export-IntuneReportToCSV` - Generate CSV reports

**Usage:**
```powershell
# Import module
Import-Module .\IntuneGraphHelper.psm1

# Connect to Graph
Connect-IntuneGraph

# Get devices
$devices = Get-AllIntuneDevices

# Export report
Export-IntuneReportToHTML -Data $devices -Title "My Report"
```

---

## Quick Start

### First Time Setup

```powershell
# 1. Install Graph SDK
Install-Module Microsoft.Graph -Scope CurrentUser

# 2. Navigate to scripts folder
cd "C:\Path\To\Intune Management Scripts"

# 3. Run your first report
.\Get-DeviceComplianceReport.ps1
```

### Authentication

All scripts use the helper module for authentication:
1. Script prompts for Microsoft sign-in
2. Consent to requested permissions (first time only)
3. Script executes with your credentials
4. Automatically disconnects when finished

**Pro Tip:** Use a service account or app registration for automation.

---

## Common Scenarios

### Scenario 1: Monthly Compliance Audit

```powershell
# 1. Device compliance
.\Get-DeviceComplianceReport.ps1 -ExportFormat Both

# 2. BitLocker encryption
.\Get-BitLockerStatus.ps1

# 3. Windows Updates
.\Get-WindowsUpdateCompliance.ps1

# 4. Stale devices
.\Find-StaleDevices.ps1 -DaysInactive 90
```

### Scenario 2: Troubleshooting App Deployment

```powershell
# 1. Check installation status
.\Get-AppInstallationStatus.ps1 -AppName "Your App"

# 2. Review policy assignments
.\Get-DeviceGroupMembership.ps1 -GroupName "App Deployment Group"

# 3. Check for conflicts
.\Find-PolicyConflicts.ps1
```

### Scenario 3: Setting Up Winget Auto-Updates

```powershell
# Generate remediation for Chrome
.\New-WingetRemediationScript.ps1 -PackageId "Google.Chrome" -IncludeReadme

# Generate remediation for Firefox
.\New-WingetRemediationScript.ps1 -PackageId "Mozilla.Firefox" -IncludeReadme

# Deploy both to Intune Proactive Remediations
```

### Scenario 4: New Win32 App Deployment

```powershell
# 1. Create deployment template
.\New-Win32AppTemplate.ps1 -AppName "MyApp"

# 2. Package the installer
.\New-IntuneWinPackage.ps1 -SetupFile "C:\Installers\MyApp\setup.exe"

# 3. Upload to Intune and configure using template files
```

### Scenario 5: Device Health Assessment 🆕

```powershell
# 1. Generate comprehensive health scores
.\Get-DeviceHealthScore.ps1 -MinHealthScore 70 -Format HTML

# 2. Identify devices with connectivity issues
.\Test-IntuneConnectivity.ps1 -Detailed -ExportResults

# 3. Check policy assignments and conflicts
.\Get-PolicyAssignmentReport.ps1 -Format HTML

# 4. Review user-device relationships
.\Get-UserDeviceAffinity.ps1 -ShowMultiDeviceUsers
```

### Scenario 6: Configuration Management & Drift Detection 🆕

```powershell
# 1. Create baseline snapshot
.\Compare-ConfigurationDrift.ps1 -CreateBaseline

# 2. Later, compare against baseline
.\Compare-ConfigurationDrift.ps1 -BaselinePath ".\intune-baseline-20260101.json"

# 3. Analyze policy assignments
.\Get-PolicyAssignmentReport.ps1 -Format CSV
```

### Scenario 5: Tenant Cleanup

```powershell
# 1. Find policy conflicts
.\Find-PolicyConflicts.ps1 -CheckSettingsCatalog

# 2. Find stale devices
.\Find-StaleDevices.ps1 -DaysInactive 180

# 3. Review and retire stale devices
.\Find-StaleDevices.ps1 -DaysInactive 180 -Action Retire
```

---

## Troubleshooting

### Authentication Issues

**Problem:** "Access Denied" or permission errors

**Solution:**
```powershell
# Check your permissions
Connect-MgGraph
Get-MgContext | Select-Object Scopes

# Disconnect and reconnect with correct scopes
Disconnect-MgGraph
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All", "DeviceManagementConfiguration.Read.All"
```

**Problem:** "Insufficient privileges"

**Solution:**
- Ensure you have **Intune Administrator** role
- Or **Global Reader** for read-only reports
- Check Azure AD role assignments

### Module Not Found

**Problem:** "IntuneGraphHelper.psm1 not found"

**Solution:**
```powershell
# Ensure you're in the correct directory
cd "C:\Path\To\Intune Management Scripts"

# Verify files exist
Get-ChildItem *.ps1, *.psm1
```

### No Data Returned

**Problem:** Reports show 0 devices

**Solution:**
1. Verify devices exist in Intune portal
2. Check Graph API permissions granted
3. Try a simple test:
   ```powershell
   Connect-MgGraph
   Get-MgDeviceManagementManagedDevice | Select-Object -First 5
   ```

### Graph API Throttling

**Problem:** "Too many requests" errors

**Solution:**
- Scripts include automatic throttling
- For large tenants, run during off-peak hours
- Use filters to reduce data returned

### Reports Not Opening

**Problem:** HTML reports don't open automatically

**Solution:**
```powershell
# Reports are saved to Desktop by default
# Open manually from:
Start-Process "$env:USERPROFILE\Desktop"
```

---

## Best Practices

### Security
- Use dedicated service account for automation
- Apply least-privilege permissions
- Audit script usage regularly
- Never hardcode credentials

### Performance
- Run large reports during off-peak hours
- Use filters to reduce data retrieval
- Close unnecessary Graph connections
- Archive old reports

### Maintenance
- Update Microsoft.Graph module monthly
- Test scripts after Intune updates
- Keep local copies of customized scripts
- Document your modifications

### Reporting
- Schedule regular compliance reports
- Archive reports for compliance records
- Share with stakeholders in read-only format
- Create dashboards from CSV exports

---

## Additional Resources

### Microsoft Documentation
- [Microsoft Graph API](https://learn.microsoft.com/en-us/graph/)
- [Intune Documentation](https://learn.microsoft.com/en-us/mem/intune/)
- [PowerShell SDK for Graph](https://learn.microsoft.com/en-us/powershell/microsoftgraph/)

### Useful Links
- [Winget Package Repository](https://winget.run)
- [Intune Content Prep Tool](https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool)
- [Intune Community](https://techcommunity.microsoft.com/t5/microsoft-intune/ct-p/Microsoft-Intune)

### Support
- Report issues on GitHub
- Check existing issues before reporting
- Include error messages and logs
- Specify your environment (OS, PowerShell version, etc.)

---

## Version History

**Version 3.0** - Enhanced Reporting & Daily Operations (January 2026)
- Added 5 new Intune management scripts:
  - Get-PolicyAssignmentReport.ps1 - Policy assignment analysis with conflict detection
  - Get-DeviceHealthScore.ps1 - Comprehensive device health scoring
  - Get-UserDeviceAffinity.ps1 - User-device relationship reporting
  - Test-IntuneConnectivity.ps1 - Endpoint connectivity validation
  - Compare-ConfigurationDrift.ps1 - Configuration change tracking
- Expanded proactive remediation library from 14 to 42 scripts (+28 total)
- Added 18 initial daily operations remediations:
  - Security: DefenderHealth, TPMStatus, LocalAdmin, PowerShell policy, CertificateExpiry
  - System: TimeSync, NetworkPowerMgmt, EventLogs, DiskHealth, StartMenu, WindowsStore
  - Apps: OneDrive KFM, EdgeCache, CredentialManager, WindowsActivation
  - Network: SMBv1, SharedFolders
- Added 10 advanced system maintenance remediations:
  - Performance: WPR/ETW sessions, Task Scheduler, Store Apps health
  - Reliability: System file corruption (SFC/DISM), Page file configuration
  - Monitoring: Battery health, Memory diagnostics, Activation grace period
  - Updates: Reboot pending state fixes
- Total toolkit: 24 Intune scripts + 42 proactive remediations

**Version 2.0** - Winget & Advanced Management
- Added 4 winget enhancement scripts (bulk updater, compliance, inventory, source config)
- Added 4 device management scripts (bulk actions, Autopilot reporting, config export, app errors)
- Created proactive remediation library (14 detect/remediate pairs)
- Expanded from 11 to 19 scripts
- Enhanced enterprise winget capabilities

**Version 1.0** - Initial Release
- 11 comprehensive scripts
- Helper module for common functions
- HTML and CSV export support
- AutoPatch integration
- Winget remediation generator

---

## License

These scripts are provided as-is for system administration purposes.

---

## Quick Reference Card

| Task | Script | Command |
|------|--------|---------|
| **Reporting** |
| Compliance Report | Get-DeviceComplianceReport.ps1 | `.\Get-DeviceComplianceReport.ps1` |
| Device Health Score 🆕 | Get-DeviceHealthScore.ps1 | `.\Get-DeviceHealthScore.ps1 -MinHealthScore 75` |
| Policy Assignments 🆕 | Get-PolicyAssignmentReport.ps1 | `.\Get-PolicyAssignmentReport.ps1 -Format HTML` |
| User-Device Affinity 🆕 | Get-UserDeviceAffinity.ps1 | `.\Get-UserDeviceAffinity.ps1` |
| App Install Status | Get-AppInstallationStatus.ps1 | `.\Get-AppInstallationStatus.ps1 -AppName "Chrome"` |
| App Install Errors | Get-AppInstallErrorReport.ps1 | `.\Get-AppInstallErrorReport.ps1 -Days 7` |
| BitLocker Audit | Get-BitLockerStatus.ps1 | `.\Get-BitLockerStatus.ps1` |
| **Maintenance** |
| Find Stale Devices | Find-StaleDevices.ps1 | `.\Find-StaleDevices.ps1 -DaysInactive 90` |
| Test Connectivity 🆕 | Test-IntuneConnectivity.ps1 | `.\Test-IntuneConnectivity.ps1 -Detailed` |
| Configuration Drift 🆕 | Compare-ConfigurationDrift.ps1 | `.\Compare-ConfigurationDrift.ps1 -CreateBaseline` |
| Update Compliance | Get-WindowsUpdateCompliance.ps1 | `.\Get-WindowsUpdateCompliance.ps1` |
| Winget Remediation | New-WingetRemediationScript.ps1 | `.\New-WingetRemediationScript.ps1 -PackageId "Google.Chrome"` |
| Bulk Winget Update | New-BulkWingetUpdater.ps1 | `.\New-BulkWingetUpdater.ps1 -AppName "Chrome" -WingetID "Google.Chrome"` |
| Winget Compliance | Get-WingetUpdateCompliance.ps1 | `.\Get-WingetUpdateCompliance.ps1 -ExportHTML` |
| Winget Inventory | Export-WingetPackageList.ps1 | `.\Export-WingetPackageList.ps1` |
| Winget Sources | New-WingetSourceConfig.ps1 | `.\New-WingetSourceConfig.ps1 -SourceName "Corp"` |
| Device Bulk Actions | Invoke-DeviceBulkActions.ps1 | `.\Invoke-DeviceBulkActions.ps1 -Action Sync` |
| Autopilot Report | Get-AutopilotDeploymentReport.ps1 | `.\Get-AutopilotDeploymentReport.ps1 -Days 7` |
| Export Config | Export-IntuneConfiguration.ps1 | `.\Export-IntuneConfiguration.ps1` |
| Policy Conflicts | Find-PolicyConflicts.ps1 | `.\Find-PolicyConflicts.ps1` |
| Group Membership | Get-DeviceGroupMembership.ps1 | `.\Get-DeviceGroupMembership.ps1 -DeviceName "PC01"` |
| Package Apps | New-IntuneWinPackage.ps1 | `.\New-IntuneWinPackage.ps1 -SourceFolder "C:\Installers"` |
| App Template | New-Win32AppTemplate.ps1 | `.\New-Win32AppTemplate.ps1 -AppName "MyApp"` |

---

**Compatibility:** Windows 10/11, Windows Server 2016+, PowerShell 5.1+
**Graph API Version:** v1.0 and beta endpoints
