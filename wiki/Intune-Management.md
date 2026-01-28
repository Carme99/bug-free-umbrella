# Intune Management

![Tier](https://img.shields.io/badge/Tier-2-blue) ![Category](https://img.shields.io/badge/Category-Integration-blueviolet) ![Status](https://img.shields.io/badge/Status-Stable-brightgreen)

Comprehensive scripts for Microsoft Intune device management, application deployment, compliance reporting, and maintenance. These scripts help you manage and monitor endpoints enrolled in Microsoft Endpoint Manager.

**⭐ NEW in v3.6.0:** Two powerful new scripts for device primary user reporting and Lenovo device enrichment!

## Overview

The Intune Management category provides tools for:
- **Application Deployment** - Win32 app packaging, Winget integration, and bulk updates
- **Device Reporting** - Compliance reports, app installation status, and BitLocker monitoring
- **Configuration Management** - Export/import configurations, policy conflict detection
- **Device Maintenance** - Bulk actions, stale device cleanup, and automation
- **Autopilot Management** - Deployment reporting and monitoring

All scripts are located in: `/scripts/endpoints/intune/`

---

## Script Categories

### Application Deployment
Package and deploy applications through Intune with Winget integration.

| Script | Description | Location |
|--------|-------------|----------|
| **New-IntuneWinPackage.ps1** | Create .intunewin packages for Win32 apps | `scripts/endpoints/intune/deployment/` |
| **New-Win32AppTemplate.ps1** | Generate Win32 app deployment templates | `scripts/endpoints/intune/deployment/` |
| **Export-WingetPackageList.ps1** | Export Winget package list for deployment | `scripts/endpoints/intune/deployment/` |
| **New-BulkWingetUpdater.ps1** | Bulk update applications via Winget | `scripts/endpoints/intune/deployment/` |
| **New-WingetRemediationScript.ps1** | Create remediation scripts for Winget apps | `scripts/endpoints/intune/deployment/` |
| **New-WingetSourceConfig.ps1** | Configure Winget sources for enterprise | `scripts/endpoints/intune/deployment/` |

### Device Reporting
Generate comprehensive reports on device compliance, apps, and security.

| Script | Description | Location |
|--------|-------------|----------|
| **Get-DeviceComplianceReport.ps1** | Export non-compliant devices with details | `scripts/endpoints/intune/reporting/` |
| **Get-AppInstallationStatus.ps1** | Check application deployment status | `scripts/endpoints/intune/reporting/` |
| **Get-AppInstallErrorReport.ps1** | Analyze app installation failures | `scripts/endpoints/intune/reporting/` |
| **Get-BitLockerStatus.ps1** | Monitor BitLocker encryption status | `scripts/endpoints/intune/reporting/` |
| **Get-WindowsUpdateCompliance.ps1** | Track Windows Update installation | `scripts/endpoints/intune/reporting/` |
| **Get-WingetUpdateCompliance.ps1** | Monitor Winget app updates | `scripts/endpoints/intune/reporting/` |
| **Get-AutopilotDeploymentReport.ps1** | Track Autopilot deployment success | `scripts/endpoints/intune/reporting/` |
| **Get-DeviceGroupMembership.ps1** | Audit device group assignments | `scripts/endpoints/intune/reporting/` |
| **Get-IntuneDevicePrimaryUsers.ps1** ⭐ NEW | Resolve primary users with hardware specs | `scripts/endpoints/intune/reporting/` |
| **Get-UserDeviceAffinity.ps1** | Generate user-device affinity reports | `scripts/endpoints/intune/reporting/` |

### Configuration Maintenance
Manage Intune configurations, policies, and devices.

| Script | Description | Location |
|--------|-------------|----------|
| **Export-IntuneConfiguration.ps1** | Backup Intune policies and configurations | `scripts/endpoints/intune/maintenance/` |
| **Find-PolicyConflicts.ps1** | Detect conflicting policy assignments | `scripts/endpoints/intune/maintenance/` |
| **Find-StaleDevices.ps1** | Identify inactive or orphaned devices | `scripts/endpoints/intune/maintenance/` |
| **Invoke-DeviceBulkActions.ps1** | Perform bulk device actions (sync, retire, wipe) | `scripts/endpoints/intune/maintenance/` |
| **Add-LenovoFriendlyModelNames.ps1** ⭐ NEW | Enrich Lenovo devices with friendly model names | `scripts/endpoints/intune/maintenance/` |

---

## Prerequisites

### Required Permissions
- **Intune Administrator** or **Endpoint Security Administrator** role
- **Microsoft Graph permissions:**
  - `DeviceManagementManagedDevices.Read.All`
  - `DeviceManagementConfiguration.Read.All`
  - `DeviceManagementApps.Read.All`
  - `DeviceManagementManagedDevices.ReadWrite.All` (for bulk actions)

### Required Modules
```powershell
# Install Microsoft Graph PowerShell SDK
Install-Module Microsoft.Graph -Scope CurrentUser -Force

# Install Intune PowerShell module (optional, Graph is preferred)
Install-Module Microsoft.Graph.Intune -Scope CurrentUser -Force

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All", `
                        "DeviceManagementConfiguration.Read.All", `
                        "DeviceManagementApps.Read.All"
```

### Additional Requirements
- **Microsoft Intune license** (part of Microsoft 365 E3/E5, EMS E3/E5)
- **Endpoint Manager access** via Azure portal
- **PowerShell 5.1+** (PowerShell 7+ recommended)
- **IntuneWinAppUtil.exe** for packaging Win32 apps

---

## Common Use Cases

### 1. Device Compliance Reporting

Generate comprehensive reports of non-compliant devices with remediation guidance.

**Basic Compliance Report:**
```powershell
# Generate HTML report of non-compliant devices
.\Get-DeviceComplianceReport.ps1

# Include compliant devices in report
.\Get-DeviceComplianceReport.ps1 -IncludeCompliant

# Export to CSV for Excel analysis
.\Get-DeviceComplianceReport.ps1 -ExportFormat CSV
```

**Advanced Reporting:**
```powershell
# Generate both HTML and CSV reports
.\Get-DeviceComplianceReport.ps1 -ExportFormat Both -IncludeCompliant

# Custom output location
.\Get-DeviceComplianceReport.ps1 -OutputPath "C:\Reports\Intune" -ExportFormat Both
```

**Sample Output:**
```
=== Intune Device Compliance Report ===
Generated: 2025-12-31 10:00:00
Total Devices: 1,245
Compliant: 1,156 (93%)
Non-Compliant: 89 (7%)

Top Compliance Issues:
1. BitLocker not enabled (34 devices)
2. Antivirus definitions outdated (28 devices)
3. Password not meeting requirements (18 devices)
4. Device encryption not configured (9 devices)

Non-Compliant Devices:
Device Name: LAPTOP-001
User: john.doe@company.com
OS: Windows 11 22H2
Last Sync: 2025-12-30 18:30:00
Issues:
  - BitLocker not enabled
  - Antivirus definitions 15 days old
Remediation: Enable BitLocker via policy, update antivirus
```

### 2. Application Deployment Monitoring

Track application installation status and troubleshoot deployment failures.

**Check App Installation Status:**
```powershell
# Check specific application installation
.\Get-AppInstallationStatus.ps1 -AppName "Microsoft Edge"

# Check all applications
.\Get-AppInstallationStatus.ps1 -AllApps

# Export detailed report
.\Get-AppInstallationStatus.ps1 -AppName "Adobe Acrobat" -ExportHTML
```

**Analyze Installation Errors:**
```powershell
# Get all app installation errors
.\Get-AppInstallErrorReport.ps1

# Filter by specific app
.\Get-AppInstallErrorReport.ps1 -AppName "7-Zip"

# Get errors from last 7 days
.\Get-AppInstallErrorReport.ps1 -DaysBack 7 -ExportCSV
```

**Sample Output:**
```
=== App Installation Error Report ===
Application: Microsoft 365 Apps
Total Deployments: 500
Successful: 482 (96.4%)
Failed: 18 (3.6%)

Common Error Codes:
1. 0x87D1041C (10 devices) - "Insufficient disk space"
2. 0x87D13B7A (5 devices) - "User cancelled installation"
3. 0x80070643 (3 devices) - "Installation failed"

Failed Devices:
Device: LAPTOP-042
User: jane.smith@company.com
Error: 0x87D1041C
Message: Insufficient disk space (2.1 GB available, 5 GB required)
Remediation: Run disk cleanup or increase storage
```

### 3. Win32 App Packaging

Create .intunewin packages for deploying custom applications.

**Basic Packaging:**
```powershell
# Package an application
.\New-IntuneWinPackage.ps1 -SourcePath "C:\Apps\MyApp" `
                           -SetupFile "setup.exe" `
                           -OutputPath "C:\IntunePackages"

# Package with custom parameters
.\New-IntuneWinPackage.ps1 -SourcePath "C:\Apps\AdobeReader" `
                           -SetupFile "AcroRead.msi" `
                           -OutputPath "C:\IntunePackages" `
                           -Verbose
```

**Automated Packaging Pipeline:**
```powershell
# Batch package multiple applications
$Apps = @(
    @{Name="7-Zip"; Source="C:\Apps\7-Zip"; Setup="7z-install.exe"},
    @{Name="Notepad++"; Source="C:\Apps\Notepad++"; Setup="npp-install.exe"},
    @{Name="VLC"; Source="C:\Apps\VLC"; Setup="vlc-install.exe"}
)

foreach ($App in $Apps) {
    Write-Host "Packaging $($App.Name)..." -ForegroundColor Cyan
    .\New-IntuneWinPackage.ps1 -SourcePath $App.Source `
                               -SetupFile $App.Setup `
                               -OutputPath "C:\IntunePackages\$($App.Name)"
}

Write-Host "All applications packaged successfully!" -ForegroundColor Green
```

### 4. Winget Integration

Deploy and manage applications using Windows Package Manager (Winget).

**Export Installed Apps:**
```powershell
# Export Winget package list from reference device
.\Export-WingetPackageList.ps1 -OutputPath "C:\Winget\company-apps.json"

# Export with version pinning
.\Export-WingetPackageList.ps1 -OutputPath "C:\Winget\pinned-apps.json" -PinVersions
```

**Bulk Application Updates:**
```powershell
# Update all Winget apps on device
.\New-BulkWingetUpdater.ps1

# Update specific apps only
.\New-BulkWingetUpdater.ps1 -AppList "Microsoft.Edge", "7zip.7zip", "VideoLAN.VLC"

# Export update report
.\New-BulkWingetUpdater.ps1 -ExportReport -OutputPath "C:\Reports"
```

**Create Winget Remediation Scripts:**
```powershell
# Generate detect/remediate pair for Winget app
.\New-WingetRemediationScript.ps1 -AppId "Microsoft.PowerToys" `
                                   -OutputPath "C:\Remediations\PowerToys"

# This creates:
# - detect.ps1 (checks if app installed and up-to-date)
# - remediate.ps1 (installs or updates the app)
```

### 5. BitLocker Compliance Monitoring

Monitor BitLocker encryption status across all managed devices.

```powershell
# Check BitLocker status on all devices
.\Get-BitLockerStatus.ps1

# Include recovery key escrow status
.\Get-BitLockerStatus.ps1 -IncludeRecoveryKeys

# Export non-encrypted devices to CSV
.\Get-BitLockerStatus.ps1 -OnlyNonEncrypted -ExportCSV

# Custom report path
.\Get-BitLockerStatus.ps1 -ExportHTML -OutputPath "C:\Reports\BitLocker"
```

**Sample Output:**
```
=== BitLocker Status Report ===
Total Devices: 1,245
Encrypted: 1,198 (96.2%)
Not Encrypted: 47 (3.8%)

Encryption Methods:
- XTS-AES 256: 1,150 (96%)
- XTS-AES 128: 48 (4%)

Recovery Keys Escrowed: 1,195 (99.7%)
Missing Recovery Keys: 3 (0.3%)

Devices Needing Attention:
1. LAPTOP-089 - Not encrypted, no policy applied
2. DESKTOP-045 - Encrypted but recovery key not escrowed
3. LAPTOP-123 - Encryption suspended

Recommendations:
- Deploy BitLocker policy to 47 unencrypted devices
- Escrow missing recovery keys for 3 devices
- Investigate suspended encryption on LAPTOP-123
```

### 6. Stale Device Cleanup

Identify and remove inactive or orphaned devices from Intune.

```powershell
# Find devices not synced in 90 days
.\Find-StaleDevices.ps1 -DaysInactive 90

# Include detailed device information
.\Find-StaleDevices.ps1 -DaysInactive 60 -Detailed -ExportCSV

# Find devices by specific criteria
.\Find-StaleDevices.ps1 -DaysInactive 30 `
                        -OnlyOrphaned `
                        -OnlyNonCompliant `
                        -ExportHTML
```

**Automated Cleanup:**
```powershell
# Find stale devices and take action
$StaleDevices = .\Find-StaleDevices.ps1 -DaysInactive 120 -ReturnObject

Write-Host "Found $($StaleDevices.Count) stale devices" -ForegroundColor Yellow

# Review devices
$StaleDevices | Format-Table DeviceName, LastSync, User -AutoSize

# Retire stale devices (with confirmation)
if ($StaleDevices.Count -gt 0) {
    $Confirm = Read-Host "Retire these devices? (yes/no)"
    if ($Confirm -eq "yes") {
        .\Invoke-DeviceBulkActions.ps1 -DeviceIds $StaleDevices.DeviceId `
                                       -Action Retire `
                                       -Confirm:$false
    }
}
```

### 7. Policy Conflict Detection

Identify conflicting Intune policy assignments that may cause issues.

```powershell
# Find all policy conflicts
.\Find-PolicyConflicts.ps1

# Check specific policy type
.\Find-PolicyConflicts.ps1 -PolicyType "DeviceConfiguration"

# Export detailed conflict report
.\Find-PolicyConflicts.ps1 -Detailed -ExportHTML
```

**Sample Output:**
```
=== Intune Policy Conflict Report ===
Conflicts Found: 12

Conflict #1:
Policy Type: Device Configuration
Setting: Password Minimum Length
Device Group: "Sales Department"
Conflicting Policies:
  1. "Corporate Password Policy" - Requires 14 characters
  2. "Sales Security Policy" - Requires 10 characters
Resolution: Remove duplicate policy or adjust group assignments

Conflict #2:
Policy Type: Compliance Policy
Setting: BitLocker Encryption
Device Group: "Marketing Laptops"
Conflicting Policies:
  1. "BitLocker Required (XTS-256)"
  2. "Standard Encryption (XTS-128)"
Resolution: Consolidate to single encryption policy
```

### 8. Autopilot Deployment Monitoring

Track Windows Autopilot deployment success and troubleshoot failures.

```powershell
# Get Autopilot deployment report
.\Get-AutopilotDeploymentReport.ps1

# Check deployments from last 30 days
.\Get-AutopilotDeploymentReport.ps1 -DaysBack 30

# Export detailed report with error codes
.\Get-AutopilotDeploymentReport.ps1 -IncludeErrors -ExportHTML
```

---

## Script Examples

### Example 1: Weekly Compliance Review

Automated weekly compliance review with reports and notifications.

```powershell
# Weekly compliance review script
$ReportDate = Get-Date -Format "yyyy-MM-dd"
$ReportPath = "C:\Reports\Intune\Weekly\$ReportDate"
New-Item -Path $ReportPath -ItemType Directory -Force

Write-Host "Starting weekly Intune compliance review..." -ForegroundColor Cyan

# 1. Device Compliance
Write-Host "Generating compliance report..." -ForegroundColor Yellow
.\Get-DeviceComplianceReport.ps1 -ExportFormat Both -OutputPath $ReportPath

# 2. BitLocker Status
Write-Host "Checking BitLocker encryption..." -ForegroundColor Yellow
.\Get-BitLockerStatus.ps1 -ExportHTML -OutputPath $ReportPath

# 3. Windows Update Compliance
Write-Host "Checking Windows Updates..." -ForegroundColor Yellow
.\Get-WindowsUpdateCompliance.ps1 -ExportCSV -OutputPath $ReportPath

# 4. App Installation Status
Write-Host "Checking application deployments..." -ForegroundColor Yellow
.\Get-AppInstallErrorReport.ps1 -DaysBack 7 -ExportHTML -OutputPath $ReportPath

# 5. Stale Devices
Write-Host "Finding stale devices..." -ForegroundColor Yellow
.\Find-StaleDevices.ps1 -DaysInactive 90 -ExportCSV -OutputPath $ReportPath

# Send summary email
$EmailBody = @"
Weekly Intune Compliance Review - $ReportDate

Reports generated:
- Device Compliance Report
- BitLocker Encryption Status
- Windows Update Compliance
- Application Deployment Errors
- Stale Device Report

Reports saved to: $ReportPath

Please review and take necessary actions.
"@

Send-MailMessage -To "it-management@company.com" `
                 -From "intune-reports@company.com" `
                 -Subject "Weekly Intune Compliance Review - $ReportDate" `
                 -Body $EmailBody `
                 -Attachments (Get-ChildItem $ReportPath).FullName `
                 -SmtpServer "smtp.company.com"

Write-Host "Weekly compliance review complete!" -ForegroundColor Green
```

### Example 2: New Application Deployment Workflow

Complete workflow for deploying a new application via Intune.

```powershell
# Application Deployment Workflow
$AppName = "Adobe Acrobat Reader DC"
$AppSource = "C:\Apps\AdobeReader"
$AppSetup = "AcroRdrDC.exe"

Write-Host "Starting deployment workflow for: $AppName" -ForegroundColor Cyan

# Step 1: Package the application
Write-Host "`n[1/4] Packaging application..." -ForegroundColor Yellow
$PackageOutput = "C:\IntunePackages\AdobeReader"
.\New-IntuneWinPackage.ps1 -SourcePath $AppSource `
                           -SetupFile $AppSetup `
                           -OutputPath $PackageOutput

# Step 2: Generate Win32 app template
Write-Host "`n[2/4] Generating deployment template..." -ForegroundColor Yellow
$Template = .\New-Win32AppTemplate.ps1 -AppName $AppName `
                                       -Publisher "Adobe" `
                                       -SetupFile $AppSetup `
                                       -InstallCommand "$AppSetup /sAll /rs" `
                                       -UninstallCommand "msiexec /x {GUID} /qn"

# Step 3: Upload to Intune (manual step - display instructions)
Write-Host "`n[3/4] Upload to Intune:" -ForegroundColor Yellow
Write-Host "  1. Open Endpoint Manager: https://endpoint.microsoft.com" -ForegroundColor White
Write-Host "  2. Go to Apps > Windows > Add" -ForegroundColor White
Write-Host "  3. Upload package from: $PackageOutput" -ForegroundColor White
Write-Host "  4. Use template settings from: $($Template.Path)" -ForegroundColor White
Write-Host "`n  Press Enter when upload is complete..." -ForegroundColor Cyan
Read-Host

# Step 4: Monitor deployment
Write-Host "`n[4/4] Monitoring deployment..." -ForegroundColor Yellow
Write-Host "Waiting 1 hour for initial deployment..."
Start-Sleep -Seconds 3600

.\Get-AppInstallationStatus.ps1 -AppName $AppName -ExportHTML

Write-Host "`nDeployment workflow complete!" -ForegroundColor Green
Write-Host "Continue monitoring with: .\Get-AppInstallationStatus.ps1 -AppName '$AppName'" -ForegroundColor Cyan
```

### Example 3: Monthly Maintenance Tasks

Perform monthly Intune environment maintenance.

```powershell
# Monthly Intune Maintenance
$MaintenanceDate = Get-Date -Format "yyyy-MM"
$OutputPath = "C:\Maintenance\Intune\$MaintenanceDate"
New-Item -Path $OutputPath -ItemType Directory -Force

Write-Host "=== Monthly Intune Maintenance ===" -ForegroundColor Cyan
Write-Host "Date: $(Get-Date)" -ForegroundColor White

# 1. Backup Intune Configuration
Write-Host "`n[1/5] Backing up Intune configuration..." -ForegroundColor Yellow
.\Export-IntuneConfiguration.ps1 -OutputPath "$OutputPath\Backup" -IncludeAll

# 2. Find and document policy conflicts
Write-Host "`n[2/5] Checking for policy conflicts..." -ForegroundColor Yellow
$Conflicts = .\Find-PolicyConflicts.ps1 -Detailed -ExportHTML -OutputPath $OutputPath

if ($Conflicts.Count -gt 0) {
    Write-Host "  WARNING: $($Conflicts.Count) policy conflicts found!" -ForegroundColor Red
    Write-Host "  Review report: $OutputPath\PolicyConflicts.html" -ForegroundColor Yellow
}

# 3. Identify stale devices (120+ days inactive)
Write-Host "`n[3/5] Finding stale devices..." -ForegroundColor Yellow
$StaleDevices = .\Find-StaleDevices.ps1 -DaysInactive 120 -Detailed -ExportCSV -OutputPath $OutputPath

if ($StaleDevices.Count -gt 0) {
    Write-Host "  Found $($StaleDevices.Count) stale devices" -ForegroundColor Yellow
    $Cleanup = Read-Host "  Retire stale devices? (yes/no)"

    if ($Cleanup -eq "yes") {
        .\Invoke-DeviceBulkActions.ps1 -DeviceIds $StaleDevices.DeviceId -Action Retire
        Write-Host "  Stale devices retired" -ForegroundColor Green
    }
}

# 4. Generate comprehensive reports
Write-Host "`n[4/5] Generating reports..." -ForegroundColor Yellow
.\Get-DeviceComplianceReport.ps1 -ExportFormat Both -OutputPath $OutputPath
.\Get-AppInstallErrorReport.ps1 -DaysBack 30 -ExportHTML -OutputPath $OutputPath
.\Get-BitLockerStatus.ps1 -ExportHTML -OutputPath $OutputPath

# 5. Check device group memberships
Write-Host "`n[5/5] Auditing device group memberships..." -ForegroundColor Yellow
.\Get-DeviceGroupMembership.ps1 -ExportCSV -OutputPath $OutputPath

Write-Host "`n=== Maintenance Complete ===" -ForegroundColor Green
Write-Host "Reports saved to: $OutputPath" -ForegroundColor Cyan
```

---

## Best Practices

### Application Deployment
1. **Test in pilot groups** - Always test deployments on small groups first
2. **Monitor installation errors** - Review app install errors daily during rollout
3. **Use detection rules** - Implement robust detection to prevent reinstalls
4. **Document requirements** - Clearly document prerequisites and dependencies
5. **Version control packages** - Maintain package versions with clear naming

### Compliance Management
1. **Regular monitoring** - Schedule weekly compliance reviews
2. **Automated reporting** - Use scripts to generate regular compliance reports
3. **Proactive remediation** - Address compliance issues before they escalate
4. **Document exceptions** - Maintain records of compliance exceptions
5. **User communication** - Notify users of compliance requirements

### Device Maintenance
1. **Cleanup stale devices** - Regularly retire inactive devices (90-120 days)
2. **Monitor sync status** - Track devices that haven't synced recently
3. **Backup configurations** - Export Intune configs monthly
4. **Review group memberships** - Audit dynamic group rules quarterly
5. **Track Autopilot** - Monitor Autopilot deployment success rates

---

## Troubleshooting

### Common Issues

**"Unauthorized" or "Forbidden" errors:**
```powershell
# Verify you're connected to Microsoft Graph
Get-MgContext

# If not connected, connect with required scopes
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All", `
                        "DeviceManagementConfiguration.Read.All"

# Check your permissions
Get-MgContext | Select-Object Scopes
```

**App installation fails with error 0x87D1041C:**
- Cause: Insufficient disk space
- Solution: Deploy disk cleanup remediation first

**BitLocker recovery keys not escrowing:**
- Verify policy setting: "Store recovery information in Azure AD"
- Check Azure AD device permissions
- Review Event Viewer logs on affected devices

**Compliance report shows no devices:**
- Verify you have Intune administrator permissions
- Check that devices are enrolled in Intune
- Ensure compliance policies are assigned

**Policy conflicts not detected:**
- Script only detects conflicts in overlapping group memberships
- Review group assignments manually for complex scenarios
- Use Endpoint Manager's built-in conflict viewer as secondary check

---

## New Scripts in v3.6.0

### Get-IntuneDevicePrimaryUsers.ps1 ⭐ NEW

Comprehensive device reporting tool that resolves primary users and collects detailed hardware specifications for Intune managed devices.

**Key Features:**
- **True Primary User Detection**: Uses Graph API `managedDevice/users` (beta) with intelligent fallback chain
- **Hardware Collection**: RAM, storage (total/free/%), CPU, model, serial, OS, last sync timestamp
- **Flexible Input**: Direct parameters, CSV/TXT files, interactive mode, GUID support
- **Output Options**: Console display, CSV export (UTF-8), configurable paths
- **Data Enrichment**: Retrieves friendly model names from Entra extension attributes

**Quick Start:**
```powershell
# Single device lookup
.\Get-IntuneDevicePrimaryUsers.ps1 -DeviceName "LTW1010013"

# Bulk processing from CSV
.\Get-IntuneDevicePrimaryUsers.ps1 -InputFile "C:\IT\Devices.csv"

# Custom output path
.\Get-IntuneDevicePrimaryUsers.ps1 `
    -DeviceName "LTW1010013" `
    -OutputPath "C:\Reports\PrimaryUsers.csv"

# Console only (no export)
.\Get-IntuneDevicePrimaryUsers.ps1 -DeviceName "LTW1010013" -NoExport

# Use different extension attribute for friendly model
.\Get-IntuneDevicePrimaryUsers.ps1 `
    -DeviceName "LTW1010013" `
    -FriendlyModelAttribute "extensionAttribute2"
```

**Use Cases:**
- Primary user auditing and compliance reporting
- Hardware inventory and capacity planning
- Device-user assignment verification
- Help desk quick lookups
- Asset management integration

**Required Permissions:**
- `DeviceManagementManagedDevices.Read.All`
- `Directory.Read.All`
- `User.Read.All`
- `Device.Read.All`

**Output Fields:**
- DeviceName, LastSeen, PrimaryUserDisplayName, PrimaryUserUPN, Source
- FriendlyModel, Manufacturer, Model, SerialNumber
- OperatingSystem, OSVersion, CPU, CPUArchitecture
- RAM_GB, StorageTotal_GB, StorageFree_GB, StorageFree_Percent

**Documentation:** See `docs/intune/Get-IntuneDevicePrimaryUsers.md` for complete guide

---

### Add-LenovoFriendlyModelNames.ps1 ⭐ NEW

Automates enrichment of Lenovo device records with human-readable model names by mapping MTM codes to product family names using Lenovo's official dataset.

**Key Features:**
- **Automatic MTM Mapping**: Maps 4-character codes (e.g., "21AH") to friendly names (e.g., "ThinkPad T14 Gen 3")
- **Dual Update Targets**: Intune Notes (append) + Entra extension attributes (set/overwrite)
- **Reliability**: Retry logic (3 attempts), rate limiting (100ms), error logging to CSV
- **Safety**: Audit mode, WhatIf/Confirm support, selective updates
- **Authentication**: Robust sign-in with automatic device code fallback

**Quick Start:**
```powershell
# Initial validation (recommended first step)
.\Add-LenovoFriendlyModelNames.ps1 -AuditOnly

# Preview changes without applying
.\Add-LenovoFriendlyModelNames.ps1 -WhatIf

# Production run
.\Add-LenovoFriendlyModelNames.ps1

# Strict validation - fail if any MTM codes unmapped
.\Add-LenovoFriendlyModelNames.ps1 -AuditOnly -FailIfMissingMappings

# Update only Notes field
.\Add-LenovoFriendlyModelNames.ps1 -UpdateExtensionAttributes:$false

# Use custom extension attribute
.\Add-LenovoFriendlyModelNames.ps1 -ExtensionAttributeName "extensionAttribute5"

# Add prefix to Notes entries
.\Add-LenovoFriendlyModelNames.ps1 -NotesPrefix "Model"

# Verbose logging for troubleshooting
.\Add-LenovoFriendlyModelNames.ps1 -VerboseOutput
```

**Use Cases:**
- Device inventory enrichment with readable model names
- Help desk efficiency (quick device identification)
- Asset management and device categorization
- Compliance reporting with friendly names
- Lifecycle management by product family

**Required Permissions:**
- `DeviceManagementManagedDevices.ReadWrite.All`
- `Device.ReadWrite.All`

**How It Works:**
1. Retrieves all Lenovo devices from Intune
2. Extracts MTM code from model string (first 4 characters)
3. Downloads Lenovo's official product dataset
4. Maps MTM codes to friendly family names
5. Updates Intune Notes and/or Entra extension attributes

**Example Mapping:**
```
Model String: "21AH001AUS"
MTM Code:     "21AH"
Friendly:     "ThinkPad T14 Gen 3"
```

**Output Summary:**
```
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
```

**Documentation:** See `docs/intune/Add-LenovoFriendlyModelNames.md` for complete guide

---

## Related Resources

### Internal Documentation
- **[Prerequisites](Prerequisites)** - Required modules and permissions
- **[Proactive Remediations](Proactive-Remediations)** - Detect and fix device issues
- **[Security & Compliance](Security-Compliance)** - Security auditing scripts
- **[FAQ](FAQ)** - Common questions and answers

### External Resources
- **[Microsoft Endpoint Manager](https://endpoint.microsoft.com)** - Intune admin portal
- **[Intune Documentation](https://docs.microsoft.com/en-us/mem/intune/)** - Official Microsoft docs
- **[Microsoft Graph API](https://docs.microsoft.com/en-us/graph/api/resources/intune-graph-overview)** - Intune Graph API reference
- **[IntuneWinAppUtil](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)** - Win32 app packaging tool

---

## See Also

- [Microsoft 365 Management](M365-Management) - M365 and Exchange management
- [Proactive Remediations](Proactive-Remediations) - Device remediation scripts
- [Security & Compliance](Security-Compliance) - Security auditing and compliance
- [Prerequisites](Prerequisites) - Required modules and permissions
- [FAQ](FAQ) - Common questions and answers
- [Support Guide](https://github.com/Carme99/bug-free-umbrella/blob/main/SUPPORT.md) - Get help

---

**Last Updated:** 2026-01-28  
**Wiki Version:** 1.2.0  
**Status:** Current with v3.7.0 Release  
**Maintained by:** Carme99 with [Claude Code](https://claude.com/claude-code)
