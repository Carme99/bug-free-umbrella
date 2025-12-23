# Bug-Free Umbrella

A comprehensive collection of PowerShell scripts for Windows system administration, Intune management, and automated device maintenance.

## Overview

This repository contains production-ready PowerShell scripts designed for IT administrators managing Windows environments through Microsoft Intune and traditional server infrastructure. The scripts follow best practices for detection/remediation patterns and enterprise deployment.

## Repository Structure

```
bug-free-umbrella/
├── docs/                              # Documentation
│   ├── README.md                      # This file
│   ├── INTUNE-SYNC-README.md          # Intune sync guide
│   └── TROUBLESHOOTING.md             # Troubleshooting guide
│
├── scripts/
│   ├── intune/                        # Intune management tools
│   ├── server/                        # Server management tools
│   ├── device-management/             # Device management scripts
│   │   ├── autopatch/                 # Windows Update policies
│   │   ├── winget-updates/            # Application update scripts
│   │   ├── bitlocker-backup/          # BitLocker key backup
│   │   ├── device-uptime/             # Uptime monitoring
│   │   ├── l16-driver-block/          # Lenovo L16 driver management
│   │   ├── adobe-rum/                 # Adobe Remote Update Manager
│   │   └── remove-sccm/               # SCCM client removal
│   └── utilities/                     # Standalone utilities
│
├── templates/                         # Reusable script templates
├── LICENSE
└── .gitignore
```

### Intune Management Scripts (`scripts/intune/`)
Enterprise-grade tools for Microsoft Intune administration:
- **Find-PolicyConflicts.ps1** - Identifies conflicting policies across your Intune environment
- **Find-StaleDevices.ps1** - Locates inactive or stale devices in Intune
- **Get-AppInstallationStatus.ps1** - Monitors application installation status across devices
- **Get-BitLockerStatus.ps1** - Retrieves BitLocker encryption status for managed devices
- **Get-DeviceComplianceReport.ps1** - Generates compliance reports for enrolled devices
- **Get-DeviceGroupMembership.ps1** - Queries device group assignments
- **Get-WindowsUpdateCompliance.ps1** - Tracks Windows Update compliance status
- **New-IntuneWinPackage.ps1** - Creates .intunewin packages for app deployment
- **New-Win32AppTemplate.ps1** - Generates templates for Win32 app deployments
- **New-WingetRemediationScript.ps1** - Creates remediation scripts for Winget-based applications

### Server Management Scripts (`scripts/server/`)
PowerShell utilities for Windows Server administration:
- **Check-SystemIntegrity.ps1** - Performs system health checks and integrity verification
- **Get-DiskReport.ps1** - Generates comprehensive disk usage and health reports
- **Remove-USLanguagePack.ps1** - Removes US language packs from systems
- **Reset-WindowsUpdate.ps1** - Resets Windows Update components to resolve update issues
- **Set-EnglishUKRegion.ps1** - Configures regional settings to English (UK)

### AutoPatch (`scripts/device-management/autopatch/`)
Multiple versions of Windows Update management scripts for controlling automatic patching behavior. Each version provides detect and remediate scripts for managing Windows Update policies.

**Versions:**
- **V1** - Granular control over individual update policies (UseWUServer, DisableWindowsUpdateAccess, etc.)
- **V2-V5** - Progressive iterations of consolidated AutoPatch management

### Winget Updates (`scripts/device-management/winget-updates/`)
Detection and remediation script pairs for automated application updates via Windows Package Manager (winget):
- Adobe Reader (32-bit & 64-bit)
- Azure CLI
- Firefox
- Google Chrome
- Lenovo Dock Manager (multiple versions)
- Lenovo System Update
- Microsoft Remote Desktop
- Microsoft Visual Studio Code
- Microsoft Visual Studio Professional (2019 & 2022)
- Microsoft Edge WebView2
- NotePad++
- OBS Studio
- Oh My Posh
- SQL Server Management Studio (SSMS)
- TeamViewer (Full & Host)
- Visual C++ Redistributables (2008, 2010, 2012, 2013, 2015-2019)
- WinSCP
- Zoom

Each application folder contains:
- `detect.ps1` - Checks if an update is needed
- `remediate.ps1` - Performs the application update

### Device Management (`scripts/device-management/`)

**bitlocker-backup/** - Ensures BitLocker recovery keys are properly backed up to Azure AD/Intune

**device-uptime/** - Monitors and manages device uptime with remediation actions

**l16-driver-block/** - Manages AMD driver blocking/unblocking for Lenovo L16 devices

**adobe-rum/** - Scripts for Adobe Remote Update Manager

**remove-sccm/** - Cleanly removes SCCM client components from devices

### Templates (`templates/`)

**App Detection Template.ps1** - Reusable template for creating custom application detection scripts

### Utilities (`scripts/utilities/`)

**Sync-UserGroupToPrimaryDeviceGroup.ps1** - Synchronizes user group memberships to device groups

## Usage

### For Intune Administrators

1. **Deploy Proactive Remediations:**
   - Upload detect/remediate script pairs to Intune
   - Configure appropriate detection and remediation schedules
   - Assign to target device groups

2. **Run Management Scripts:**
   ```powershell
   # Example: Check BitLocker status across devices
   .\scripts\intune\Get-BitLockerStatus.ps1
   ```

3. **Create Win32 App Packages:**
   ```powershell
   # Package an application for Intune deployment
   .\scripts\intune\New-IntuneWinPackage.ps1
   ```

### For Server Administrators

```powershell
# Generate disk health report
.\scripts\server\Get-DiskReport.ps1

# Reset Windows Update components
.\scripts\server\Reset-WindowsUpdate.ps1

# Verify system integrity
.\scripts\server\Check-SystemIntegrity.ps1
```

### Script Execution Requirements

- **PowerShell Version:** 5.1 or later recommended
- **Execution Policy:** Scripts may require execution policy adjustment
- **Permissions:** Many scripts require administrator privileges
- **Intune Scripts:** Graph API permissions may be required for Intune management scripts

## Best Practices

1. **Test Before Deployment:** Always test scripts in a non-production environment first
2. **Review Permissions:** Ensure scripts have appropriate permissions for your environment
3. **Monitor Execution:** Use Intune reporting to monitor detection/remediation outcomes
4. **Customize as Needed:** Scripts may require customization for your specific environment
5. **Version Control:** Track any modifications you make to these scripts

## Contributing

When adding new scripts:
- Follow the existing detection/remediation pattern
- Include clear comments and documentation
- Test thoroughly before committing
- Update this README with new script descriptions

## License

This project is licensed under the terms specified in the LICENSE file.

## Support

For issues or questions:
- Review script comments for usage details
- Check the README files in subdirectories for specific guidance
- Test in a controlled environment before production deployment
