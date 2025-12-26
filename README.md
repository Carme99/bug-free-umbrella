# Bug-Free Umbrella

A comprehensive collection of PowerShell scripts for Windows system administration, Intune management, and automated device maintenance.

## 🆕 What's New

### Server Management Expansion (December 2024)

Major expansion of server management capabilities with **18 new enterprise-grade scripts** organized into specialized categories:

**🗂️ Group Policy Management** (3 scripts)
- **Get-GPOReport.ps1** - Comprehensive GPO reporting with HTML/XML exports
- **Backup-GroupPolicies.ps1** - Automated GPO backups with retention management
- **Find-GPOConflicts.ps1** - Detect GPO conflicts and configuration issues

**💾 Backup & Disaster Recovery** (2 scripts)
- **Get-BackupStatus.ps1** - Windows Server Backup verification and validation
- **Manage-RestorePoints.ps1** - System restore point creation and management

**👥 Active Directory Management** (2 scripts)
- **Get-ADUserAudit.ps1** - Comprehensive user account security auditing
- **Get-ServiceAccountAudit.ps1** - Service account security and compliance auditing

**📊 Advanced Monitoring** (2 scripts)
- **Get-BatteryHealth.ps1** - Laptop battery health tracking and reporting
- **Get-PerformanceTrends.ps1** - Performance monitoring with trend analysis

**🌐 Network Management** (2 scripts)
- **Test-NetworkDiagnostics.ps1** - Comprehensive network diagnostics toolkit
- **Reset-NetworkStack.ps1** - Network stack reset for troubleshooting

**🔐 User Access Management** (1 script)
- **Get-UserAccessReport.ps1** - User permissions and access rights auditing

**Reorganized Server Structure:**
```
scripts/server/
├── active-directory/      # AD management and auditing
├── backup-recovery/       # Backup and restore operations
├── group-policy/          # GPO management and reporting
├── monitoring/            # Server health and performance
├── network/               # Network configuration and testing
├── security/              # Security and certificates
├── storage/               # Disk and file management
├── system/                # System configuration and updates
└── user-management/       # User access and permissions
```

All new scripts include:
- ✅ Comprehensive error handling
- ✅ HTML and CSV reporting
- ✅ Detailed documentation with examples
- ✅ Enterprise-ready design patterns

---

## Quick Links

### 📖 Documentation
- **[Full Documentation](docs/README.md)** - Complete guide to all scripts and usage
- **[Script Examples & Expected Outputs](docs/SCRIPT-EXAMPLES.md)** - Detailed examples with sample outputs
- **[End-to-End Workflows](docs/WORKFLOWS.md)** - Step-by-step guides for common scenarios
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)** - Common issues and solutions

### 🎯 Specialized Guides
- **[Intune Sync Guide](docs/INTUNE-SYNC-README.md)** - User group to device group synchronization
- **[Intune Management Scripts](scripts/intune/README.md)** - Comprehensive Intune administration toolkit (reporting, maintenance, deployment)
- **[Server Management Scripts](scripts/server/README.md)** - Windows Server administration tools
- **[Security & Compliance Scripts](scripts/security-compliance/README.md)** - Security auditing and compliance verification (9 comprehensive scripts)
- **[Monitoring Scripts](scripts/monitoring/)** - System health checks and performance monitoring
- **[Network Management Scripts](scripts/network-management/)** - Network diagnostics and troubleshooting
- **[Proactive Remediations](scripts/device-management/proactive-remediations/README.md)** - Auto-fix common issues (9 remediation pairs)
- **[Winget Update Templates](scripts/device-management/winget-updates/Template/README.md)** - Application auto-update setup (40+ apps)

## Repository Structure

```
bug-free-umbrella/
├── docs/                              # Documentation
├── scripts/
│   ├── intune/                        # Intune management tools (18 scripts)
│   │   ├── reporting/                 # Compliance, status, and audit reports
│   │   ├── maintenance/               # Device cleanup and policy management
│   │   └── deployment/                # Packaging and deployment tools
│   ├── server/                        # Server management tools (34 scripts)
│   │   ├── active-directory/          # AD user/service account auditing
│   │   ├── backup-recovery/           # Backup verification and restore points
│   │   ├── group-policy/              # GPO management and reporting
│   │   ├── monitoring/                # Server health and performance
│   │   ├── network/                   # Network configuration and connectivity
│   │   ├── security/                  # Security and certificates
│   │   ├── storage/                   # Disk and file management
│   │   ├── system/                    # System configuration and updates
│   │   └── user-management/           # User access and permissions
│   ├── security-compliance/           # Security auditing and compliance (9 scripts)
│   ├── monitoring/                    # System health checks and monitoring (NEW)
│   ├── network-management/            # Network diagnostics and troubleshooting (NEW)
│   ├── device-management/             # Device management scripts
│   │   ├── proactive-remediations/    # Auto-fix scripts (9 pairs)
│   │   ├── winget-updates/            # Application update scripts (40+ apps)
│   │   │   ├── browsers/              # Firefox, Chrome
│   │   │   ├── communication/         # Slack, Discord (NEW)
│   │   │   ├── development/           # VS Code, Git, Docker, Node.js, etc.
│   │   │   ├── security/              # 1Password, Bitwarden, KeePass (NEW)
│   │   │   ├── cloud-storage/         # Dropbox, Google Drive, Box (NEW)
│   │   │   ├── vpn/                   # NordVPN, ProtonVPN (NEW)
│   │   │   ├── database/              # MySQL Workbench, Azure Data Studio (NEW)
│   │   │   ├── media/                 # OBS, VLC, Zoom
│   │   │   ├── productivity/          # Teams, Notepad++, Adobe Reader
│   │   │   ├── remote-access/         # TeamViewer, WinSCP
│   │   │   ├── runtimes/              # C++ Redist, Edge WebView2
│   │   │   ├── utilities/             # 7-Zip
│   │   │   ├── vendor-specific/       # Lenovo tools
│   │   │   └── _templates/            # V3 enhanced templates
│   │   ├── autopatch/                 # Windows Update policies
│   │   ├── bitlocker-backup/          # BitLocker key backup
│   │   ├── device-uptime/             # Uptime monitoring
│   │   ├── l16-driver-block/          # Lenovo L16 driver management
│   │   ├── adobe-rum/                 # Adobe Remote Update Manager
│   │   └── remove-sccm/               # SCCM client removal
│   └── utilities/                     # Standalone utilities
├── templates/                         # Reusable script templates
└── LICENSE
```

## Getting Started

### Prerequisites

Before using these scripts, ensure you have the following:

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

### Verify Your Environment

**Check PowerShell Version**:
```powershell
$PSVersionTable.PSVersion
# Should show 5.1 or higher
```

**Check if running as Administrator**:
```powershell
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# Should return: True
```

**Check Execution Policy**:
```powershell
Get-ExecutionPolicy
# If Restricted, run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Check Microsoft Graph Module** (for Intune scripts):
```powershell
Get-Module Microsoft.Graph -ListAvailable
# If not installed, run: Install-Module Microsoft.Graph -Scope CurrentUser
```

### Quick Start Examples

#### Intune Management

**Generate Monthly Compliance Report**:
```powershell
cd scripts\intune

# Device compliance status
.\Get-DeviceComplianceReport.ps1

# BitLocker encryption audit
.\Get-BitLockerStatus.ps1

# Windows Update compliance
.\Get-WindowsUpdateCompliance.ps1

# All reports saved to Desktop as HTML and CSV
```

**Find and Clean Up Stale Devices**:
```powershell
# Interactive mode - prompts for days threshold
.\Find-StaleDevices.ps1

# Or specify days directly (90 days = 3 months)
.\Find-StaleDevices.ps1 -DaysInactive 90

# Review report, then optionally retire devices >180 days
.\Find-StaleDevices.ps1 -DaysInactive 180 -Action Retire
```

**Expected Time**: 5-10 minutes per report
**Output Location**: `%USERPROFILE%\Desktop\`

#### Server Administration

**Fix Stuck Windows Updates**:
```powershell
cd scripts\server

# Standard reset (fixes most issues)
.\Reset-WindowsUpdate.ps1

# Full reset including BITS and Cryptographic services
.\Reset-WindowsUpdate.ps1 -FullReset

# Then check for updates in Windows Update
```

**Expected Time**: 2-5 minutes
**Expected Result**: Windows Update services reset, can now check for updates

**Check Server Health**:
```powershell
# Verify system file integrity
.\Check-SystemIntegrity.ps1

# Quick scan (faster, SFC only)
.\Check-SystemIntegrity.ps1 -QuickScan

# Auto-repair with HTML report
.\Check-SystemIntegrity.ps1 -AutoRepair -GenerateReport
```

**Expected Time**:
- Quick scan: 5-10 minutes
- Full scan: 15-30 minutes
- With repair: 20-45 minutes

**Analyze Disk Usage**:
```powershell
# Scan all drives
.\Get-DiskReport.ps1

# Scan specific drive with report
.\Get-DiskReport.ps1 -DriveLetter C -ExportReport

# Shows cleanup suggestions with potential space savings
```

**Expected Output**: Detailed disk analysis with cleanup recommendations

#### Security & Compliance

**Run Security Baseline Check**:
```powershell
cd scripts\security-compliance

# Check system against security baseline
.\Get-SecurityBaseline.ps1

# Generate detailed report
.\Get-SecurityBaseline.ps1 -ExportReport
```

**Expected Time**: 30-60 seconds
**Expected Output**: Security compliance report with pass/fail status

**Audit Local Administrators**:
```powershell
# Audit administrator accounts
.\Get-LocalAdminAudit.ps1

# Generate detailed report
.\Get-LocalAdminAudit.ps1 -Detailed -ExportReport
```

**Expected Time**: 10-20 seconds
**Expected Output**: List of admin accounts with risk assessment

**Monthly Security Audit**:
```powershell
# Run comprehensive security checks
.\Get-SecurityBaseline.ps1 -ExportReport
.\Get-LocalAdminAudit.ps1 -ExportReport
.\Test-SecurityFeatures.ps1 -ExportReport
.\Get-ExpiredCertificates.ps1 -DaysToExpire 60 -ExportReport
.\Get-FailedLoginReport.ps1 -Hours 720 -ExportReport

# All reports saved to Desktop
```

**Expected Time**: 2-5 minutes
**Expected Output**: Comprehensive security and compliance reports

#### System Monitoring & Health Checks

**Run Comprehensive System Health Check**:
```powershell
cd scripts\monitoring

# Full system health check
.\Get-SystemHealthCheck.ps1

# Generate HTML report
.\Get-SystemHealthCheck.ps1 -OutputFormat HTML -OutputPath "C:\Reports"

# Custom thresholds
.\Get-SystemHealthCheck.ps1 -DiskThresholdPercent 85 -MemoryThresholdPercent 85
```

**Expected Time**: 30-60 seconds
**Expected Output**: Overall health score, CPU/memory/disk status, service status, uptime analysis

#### Network Management & Diagnostics

**Troubleshoot Network Connectivity**:
```powershell
cd scripts\network-management

# Comprehensive network diagnostic
.\Test-NetworkConnectivity.ps1

# Test specific endpoints
.\Test-NetworkConnectivity.ps1 -TestEndpoints @("office.com", "microsoft.com", "google.com")

# Generate diagnostic report
.\Test-NetworkConnectivity.ps1 -OutputFormat HTML -OutputPath "C:\Reports"
```

**Expected Time**: 30-90 seconds
**Expected Output**: Adapter status, gateway connectivity, DNS resolution, internet connectivity tests

#### Winget Application Updates

**Set Up Auto-Updates for Google Chrome**:

```powershell
cd scripts\device-management\winget-updates\Template

# 1. Copy template files
New-Item -Path "..\Google Chrome" -ItemType Directory
Copy-Item "detect_v2.ps1" -Destination "..\Google Chrome\detect.ps1"
Copy-Item "remediate_v2_standard.ps1" -Destination "..\Google Chrome\remediate.ps1"

# 2. Edit detect.ps1 - Change line 1 to:
#    $ID = 'Google.Chrome'

# 3. Edit remediate.ps1 - Change line 1 to:
#    $ID = 'Google.Chrome'

# 4. Upload both files to Intune > Devices > Proactive Remediations
#    Schedule: Daily, Run as SYSTEM
```

**Deployment Time**: 20-30 minutes (including Intune configuration)
**For More Apps**: See [Winget Templates README](scripts/device-management/winget-updates/Template/README.md)

### Common Workflows

For detailed step-by-step guides, see our workflow documentation:

- **[Monthly Compliance Audit](docs/WORKFLOWS.md#monthly-compliance-audit-workflow)** - Complete compliance review process
- **[Automated Winget Updates](docs/WORKFLOWS.md#setting-up-automated-winget-updates)** - Deploy application auto-updates
- **[New Server Setup](docs/WORKFLOWS.md#new-windows-server-setup)** - Initial server configuration
- **[Device Cleanup](docs/WORKFLOWS.md#intune-device-cleanup-workflow)** - Remove stale devices
- **[BitLocker Deployment](docs/WORKFLOWS.md#bitlocker-deployment-and-monitoring)** - Enable encryption across devices

### What to Expect

**Script Execution Times**:
| Script Type | Typical Duration |
|-------------|------------------|
| Detection Scripts | 10-30 seconds |
| Winget Updates | 2-5 minutes |
| Intune Reports | 3-10 minutes |
| Server Health Checks | 15-30 minutes |
| Disk Analysis | 5-15 minutes |

**Output Formats**:
- Most scripts generate **HTML** and **CSV** reports
- Reports saved to: `C:\Users\[YourName]\Desktop\`
- Color-coded console output for quick status checks

**Exit Codes**:
- **0** = Success / No issues found
- **1** = Issues detected / Remediation needed
- See [Script Examples](docs/SCRIPT-EXAMPLES.md) for detailed behavior

### Getting Help

**Built-in Help**:
```powershell
# View detailed help for any script
Get-Help .\ScriptName.ps1 -Detailed

# See examples
Get-Help .\ScriptName.ps1 -Examples

# Full help including parameters
Get-Help .\ScriptName.ps1 -Full
```

**Documentation**:
- **Questions about usage?** → [Script Examples](docs/SCRIPT-EXAMPLES.md)
- **Following a process?** → [Workflow Guides](docs/WORKFLOWS.md)
- **Something not working?** → [Troubleshooting](docs/TROUBLESHOOTING.md)
- **Script reference?** → [Full Documentation](docs/README.md)

**Support**:
- Check existing documentation first
- Review script comments (all scripts are well-documented)
- Test in non-production environment
- Report issues with detailed error messages

## Requirements Summary

| Component | Requirement |
|-----------|-------------|
| **PowerShell** | 5.1 minimum (7.x recommended) |
| **OS (Intune)** | Windows 10/11, any supported OS |
| **OS (Server)** | Windows Server 2016/2019/2022 |
| **Privileges** | Administrator / Elevated |
| **Intune Role** | Intune Admin or Global Reader |
| **Graph Module** | Microsoft.Graph (for Intune scripts) |
| **Network** | Internet access for Intune/Graph API |

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.
