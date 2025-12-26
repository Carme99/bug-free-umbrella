# Bug-Free Umbrella - Complete Documentation

A comprehensive collection of PowerShell scripts for Windows system administration, Intune management, and automated device maintenance.

## 📚 Documentation Index

This documentation hub provides detailed information about all scripts and tools in the bug-free-umbrella repository.

### Quick Navigation

- **[Main README](../README.md)** - Repository overview and quick start
- **[Script Examples & Outputs](SCRIPT-EXAMPLES.md)** - Detailed examples with sample outputs
- **[End-to-End Workflows](WORKFLOWS.md)** - Step-by-step guides for common scenarios
- **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Common issues and solutions
- **[Intune Sync Guide](INTUNE-SYNC-README.md)** - User group to device group synchronization

### Script Categories

- **[Intune Management](../scripts/intune/README.md)** - 19 comprehensive scripts for Intune administration
- **[Server Management](../scripts/server/README.md)** - 16 Windows Server administration tools
- **[Security & Compliance](../scripts/security-compliance/README.md)** - 9 security auditing scripts
- **[System Monitoring](../scripts/monitoring/README.md)** - Health checks and performance monitoring
- **[Network Management](../scripts/network-management/README.md)** - Network diagnostics and troubleshooting
- **[Proactive Remediations](../scripts/device-management/proactive-remediations/README.md)** - 6 auto-fix remediation pairs
- **[Winget Updates](../scripts/device-management/winget-updates/README.md)** - Application auto-update management

---

## Overview

The bug-free-umbrella repository contains production-ready PowerShell scripts designed for IT administrators managing Windows environments through Microsoft Intune and traditional server infrastructure. All scripts follow best practices for detection/remediation patterns and enterprise deployment.

### What's Included

#### Device Management (Intune)
- **Compliance Reporting** - Device compliance, BitLocker, Windows Update status
- **Application Management** - Installation status, winget updates, deployment
- **Device Maintenance** - Stale device cleanup, bulk actions, Autopilot tracking
- **Configuration Management** - Policy conflicts, group membership, backup/restore

#### Server Management
- **System Maintenance** - Windows Update reset, system integrity checks
- **Storage Management** - Disk analysis, cleanup, large file reports
- **Active Directory** - User/service account auditing, health checks, inactive computers
- **Group Policy** - GPO reporting, backups, conflict detection
- **Backup & Recovery** - Backup verification, restore point management
- **Monitoring & Performance** - Server health, event logs, performance trends
- **Network Configuration** - Connectivity testing, diagnostics, stack reset

#### Security & Compliance
- **Security Baselines** - CIS/Microsoft baseline verification
- **Access Auditing** - Local admin audit, failed logins, USB devices
- **Feature Verification** - TPM, Secure Boot, Credential Guard
- **Certificate Management** - Expiration checks, validation
- **Software Compliance** - License compliance, antivirus status

#### Automation & Proactive Remediations
- **Auto-Fix Scripts** - Disk space, temp files, stale profiles
- **Windows Update** - Stuck update resolution
- **Security Enforcement** - BitLocker key backup, security baseline
- **Application Updates** - Winget-based automatic updates for 40+ applications

---

## Repository Structure

```
bug-free-umbrella/
├── docs/                              # Documentation (you are here)
│   ├── README.md                      # This file - documentation index
│   ├── INTUNE-SYNC-README.md          # Intune user-to-device sync guide
│   ├── TROUBLESHOOTING.md             # Common issues and solutions
│   ├── WORKFLOWS.md                   # Step-by-step workflow guides
│   └── SCRIPT-EXAMPLES.md             # Detailed script examples with outputs
│
├── scripts/
│   ├── intune/                        # Intune management tools (19 scripts)
│   │   ├── reporting/                 # Compliance, status, and audit reports
│   │   ├── maintenance/               # Device cleanup and policy management
│   │   └── deployment/                # Packaging and deployment tools
│   │
│   ├── server/                        # Server management tools (16+ scripts)
│   │   ├── active-directory/          # AD user/service account auditing
│   │   ├── backup-recovery/           # Backup verification and restore points
│   │   ├── group-policy/              # GPO management and reporting
│   │   ├── monitoring/                # Server health and performance
│   │   ├── network/                   # Network configuration and connectivity
│   │   ├── security/                  # Security and certificates
│   │   ├── storage/                   # Disk and file management
│   │   ├── system/                    # System configuration and updates
│   │   └── user-management/           # User access and permissions
│   │
│   ├── security-compliance/           # Security auditing and compliance (9 scripts)
│   │
│   ├── monitoring/                    # System health checks and monitoring
│   │
│   ├── network-management/            # Network diagnostics and troubleshooting
│   │
│   └── device-management/             # Device management scripts
│       ├── proactive-remediations/    # Auto-fix scripts (6 pairs)
│       ├── winget-updates/            # Application update scripts (40+ apps)
│       │   ├── browsers/              # Firefox, Chrome
│       │   ├── communication/         # Slack, Discord
│       │   ├── development/           # VS Code, Git, Docker, Node.js
│       │   ├── security/              # 1Password, Bitwarden, KeePass
│       │   ├── cloud-storage/         # Dropbox, Google Drive, Box
│       │   ├── vpn/                   # NordVPN, ProtonVPN
│       │   ├── database/              # MySQL Workbench, Azure Data Studio
│       │   ├── media/                 # OBS, VLC, Zoom
│       │   ├── productivity/          # Teams, Notepad++, Adobe Reader
│       │   ├── remote-access/         # TeamViewer, WinSCP
│       │   ├── runtimes/              # C++ Redist, Edge WebView2
│       │   ├── utilities/             # 7-Zip
│       │   ├── vendor-specific/       # Lenovo tools
│       │   └── _templates/            # V3 enhanced templates
│       ├── autopatch/                 # Windows Update policies
│       ├── bitlocker-backup/          # BitLocker key backup
│       ├── device-uptime/             # Uptime monitoring
│       ├── l16-driver-block/          # Lenovo L16 driver management
│       ├── adobe-rum/                 # Adobe Remote Update Manager
│       └── remove-sccm/               # SCCM client removal
│
├── templates/                         # Reusable script templates
└── LICENSE
```

---

## Getting Started

### Prerequisites

#### For All Scripts
- **PowerShell 5.1 or later** (PowerShell 7+ recommended)
- **Administrator privileges** (most scripts require elevation)
- **Execution Policy** set appropriately

#### For Intune Scripts
- **Microsoft Graph PowerShell SDK**
  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser
  ```
- **Required Permissions**: DeviceManagementManagedDevices.Read.All (minimum)
- **Intune Administrator** or **Global Reader** role

#### For Server Scripts
- **Windows Server 2016, 2019, or 2022**
- **Local Administrator** privileges
- No additional modules required (uses built-in cmdlets)

### Quick Start

1. **Clone or download the repository**
   ```powershell
   git clone https://github.com/Carme99/bug-free-umbrella.git
   cd bug-free-umbrella
   ```

2. **Choose your script category**
   - Browse to the appropriate folder (intune/, server/, security-compliance/, etc.)
   - Read the category README for script descriptions

3. **Run a script**
   ```powershell
   # View script help
   Get-Help .\ScriptName.ps1 -Detailed

   # Execute the script
   .\ScriptName.ps1 -Parameters
   ```

---

## Documentation Guides

### [Script Examples & Expected Outputs](SCRIPT-EXAMPLES.md)

Comprehensive guide showing:
- Exact command syntax for common scenarios
- Sample output with interpretation
- Exit codes and their meanings
- Execution time expectations
- Best practices for each script category

**When to use**: Learning how scripts behave, understanding expected results, troubleshooting unexpected output

### [End-to-End Workflows](WORKFLOWS.md)

Step-by-step guides for complete processes:
- Monthly compliance audits
- Automated winget updates deployment
- New server setup procedures
- Intune device cleanup
- BitLocker deployment and monitoring
- Proactive remediation deployment

**When to use**: Following a complete process from start to finish, onboarding new team members

### [Troubleshooting Guide](TROUBLESHOOTING.md)

Solutions for common issues:
- Microsoft Graph API authentication problems
- PowerShell execution policy errors
- Module installation issues
- Intune script deployment problems
- Winget update failures
- BitLocker backup issues
- Network and proxy problems
- Permission errors

**When to use**: Resolving errors, investigating failures, fixing deployment issues

### [Intune Sync Guide](INTUNE-SYNC-README.md)

Detailed guide for synchronizing user groups to device groups:
- Use case and benefits
- Prerequisites and permissions
- Step-by-step configuration
- Interactive device selection
- Full sync process
- Troubleshooting

**When to use**: Implementing user-to-device group synchronization for autopatch or similar scenarios

---

## Common Use Cases

### Monthly IT Operations

#### Compliance Reporting
```powershell
# Generate all compliance reports
cd scripts\intune
.\Get-DeviceComplianceReport.ps1
.\Get-BitLockerStatus.ps1
.\Get-WindowsUpdateCompliance.ps1
.\Find-StaleDevices.ps1 -DaysInactive 90

# Review generated reports on Desktop
```

#### Security Audit
```powershell
cd scripts\security-compliance
.\Get-SecurityBaseline.ps1 -ExportReport
.\Get-LocalAdminAudit.ps1 -ExportReport
.\Test-SecurityFeatures.ps1 -ExportReport
.\Get-FailedLoginReport.ps1 -Hours 720 -ExportReport
```

### Server Maintenance

#### Pre-Change Checklist
```powershell
cd scripts\server
# Create restore point
.\backup-recovery\Manage-RestorePoints.ps1 -Action Create -Description "Before updates"

# Verify system health
.\Check-SystemIntegrity.ps1 -GenerateReport

# Backup Group Policies (if applicable)
.\group-policy\Backup-GroupPolicies.ps1 -BackupPath "D:\Backups"
```

#### Post-Change Verification
```powershell
# Check system integrity
.\Check-SystemIntegrity.ps1 -AutoRepair

# Verify services
.\monitoring\Get-SystemHealthCheck.ps1 -OutputFormat HTML

# Test network
.\network\Test-NetworkConnectivity.ps1 -OutputFormat HTML
```

### Application Management

#### Deploy Winget Auto-Updates
```powershell
cd scripts\device-management\winget-updates

# Use pre-built scripts for popular apps
# or generate new ones from templates

# Example: Deploy Chrome updates
# Upload GoogleChrome/detect.ps1 and remediate.ps1 to Intune
# Configure as Proactive Remediation, schedule daily
```

#### Monitor Application Deployments
```powershell
cd scripts\intune
.\Get-AppInstallationStatus.ps1 -AppName "Google Chrome"
.\Get-AppInstallErrorReport.ps1 -Days 7 -ExportHTML
```

---

## Integration Scenarios

### Intune + Server Management
```powershell
# Sync user group to device group for Autopatch
.\scripts\utilities\Sync-UserGroupToPrimaryDeviceGroup.ps1

# Then monitor update compliance
.\scripts\intune\Get-WindowsUpdateCompliance.ps1 -IncludeAutoPatchInfo
```

### Active Directory + Group Policy
```powershell
# Before AD changes
.\scripts\server\backup-recovery\Manage-RestorePoints.ps1 -Action Create

# Audit users
.\scripts\server\active-directory\Get-ADUserAudit.ps1 -CheckPrivilegedAccounts

# Backup GPOs
.\scripts\server\group-policy\Backup-GroupPolicies.ps1 -BackupPath "D:\Backups"

# Make changes...

# Verify no conflicts
.\scripts\server\group-policy\Find-GPOConflicts.ps1
```

### Proactive Remediation + Security
```powershell
# Deploy security baseline enforcement
cd scripts\device-management\proactive-remediations\Check-SecurityBaseline
# Upload to Intune as Proactive Remediation

# Monitor compliance
cd ..\..\security-compliance
.\Get-SecurityBaseline.ps1 -ExportReport
```

---

## Best Practices

### Script Execution
1. **Always read script help first**
   ```powershell
   Get-Help .\ScriptName.ps1 -Detailed
   ```

2. **Test in non-production first**
   - Use test device groups
   - Verify expected behavior
   - Check for unintended side effects

3. **Monitor execution and outputs**
   - Review console output
   - Check generated reports
   - Verify expected results

### Automation
1. **Use appropriate scheduling**
   - Daily: System health, disk space
   - Weekly: Stale devices, profile cleanup
   - Monthly: Compliance audits, security reviews

2. **Centralize report storage**
   - Create consistent output paths
   - Implement retention policies
   - Archive for compliance

3. **Implement alerting**
   - Email reports for critical items
   - Integrate with monitoring systems
   - Set appropriate thresholds

### Security
1. **Secure script storage**
   - Use version control (Git)
   - Restrict access appropriately
   - Review changes before deployment

2. **Protect sensitive outputs**
   - Reports may contain PII
   - Secure report storage locations
   - Implement data retention policies

3. **Audit script usage**
   - Log script executions
   - Review who runs what
   - Track configuration changes

---

## Script Categories Quick Reference

| Category | Script Count | Primary Use Cases |
|----------|--------------|-------------------|
| **Intune Management** | 19 | Compliance reporting, app deployment, device maintenance |
| **Server Management** | 16+ | System maintenance, AD/GPO management, backup verification |
| **Security & Compliance** | 9 | Security auditing, baseline verification, access reviews |
| **Monitoring** | 3 | System health, battery health, performance trending |
| **Network Management** | 3 | Connectivity testing, diagnostics, network stack reset |
| **Proactive Remediations** | 6 pairs | Auto-fix disk space, temp files, Windows Update, security |
| **Winget Updates** | 40+ apps | Application auto-updates via Intune remediations |

---

## Support and Resources

### Getting Help
1. **Check built-in help**
   ```powershell
   Get-Help .\ScriptName.ps1 -Full
   ```

2. **Review documentation**
   - Script Examples for usage patterns
   - Troubleshooting Guide for common issues
   - Workflow Guides for complete processes

3. **Check script comments**
   - All scripts include detailed comments
   - Parameter descriptions
   - Example usage

### Contributing
When adding new scripts or documentation:
- Follow existing patterns and structures
- Include comprehensive help
- Test thoroughly
- Update relevant README files
- Add examples to documentation

### Feedback
- Report issues with detailed error messages
- Suggest improvements
- Share success stories
- Contribute enhancements

---

## Version History

**Version 2.0** - December 2024
- Expanded server management (18 new scripts)
- Enhanced Intune scripts (19 total)
- Added monitoring and network categories
- Improved documentation structure
- Added comprehensive workflow guides

**Version 1.0** - Initial Release
- Core Intune management scripts
- Basic server utilities
- Winget update templates
- Proactive remediation library

---

## License

Licensed under the Apache License 2.0. See [LICENSE](../LICENSE) for details.

---

**Last Updated**: December 26, 2024
**Documentation Version**: 2.0
