# Bug-Free Umbrella

A comprehensive collection of PowerShell scripts for Windows system administration, Intune management, and automated device maintenance.

> **⚠️ CRITICAL NOTICE - TESTING STATUS**
> **The vast majority of scripts in this repository have not been thoroughly tested in production environments.**
> Please test all scripts in a non-production environment first and validate the results before relying on this data for operational decisions.
> Always review scripts before execution and ensure you have proper backups.

## 🆕 What's New

### 🚀 LATEST: DevOps, Security & Cloud Infrastructure Expansion

**Massive addition of 15+ production-ready scripts across 6 NEW categories!**

**🔄 NEW CATEGORY: DevOps & CI/CD** - 4 scripts
- **Monitor-AzureDevOpsPipelines.ps1** - Azure DevOps pipeline health monitoring, build analytics, agent pools
- **Monitor-GitHubActions.ps1** - GitHub Actions workflow monitoring, runner health, billing metrics
- **Monitor-GitLabCI.ps1** - GitLab CI/CD pipeline monitoring, deployment tracking
- **Analyze-BuildPerformance.ps1** - Build duration analysis, regression detection, performance trends

**🌐 NEW CATEGORY: API Management** - 2 scripts
- **Monitor-AzureAPIManagement.ps1** - Azure APIM service health, API analytics, backend monitoring
- **Test-APIHealth.ps1** - Universal API endpoint testing, SSL validation, SLA compliance

**⚙️ NEW CATEGORY: Infrastructure as Code** - 2 scripts
- **Test-BicepTemplates.ps1** - Azure Bicep validation, security scanning, what-if deployment
- **Test-TerraformConfiguration.ps1** - Terraform validation, tfsec security scanning, plan analysis

**🔒 NEW CATEGORY: Advanced Security** - 1+ scripts
- **Invoke-SecurityComplianceScan.ps1** - Multi-framework compliance (CIS, NIST, PCI-DSS, HIPAA, SOC2, ISO27001)

**☁️ EXPANDED: Cloud Infrastructure** - Additional Azure/AWS scripts
- **Monitor-AzureResources.ps1** - Multi-subscription Azure monitoring, cost analysis, orphaned resource detection

**🗄️ EXPANDED: Database Management** - NoSQL and advanced monitoring
- **Monitor-MongoDBHealth.ps1** - MongoDB health monitoring, replication status, performance analysis

---

### 🚀 MASSIVE EXPANSION - Enterprise Infrastructure Suite (LATEST!)

**New repository totals: 60+ production-ready scripts across 16 categories!**

This expansion adds **20+ new enterprise scripts** and **4 brand new categories**:

**🌐 NEW CATEGORY: Web Services (IIS)** - 4 scripts
- **Get-IISHealthCheck.ps1** - Comprehensive IIS health monitoring, SSL validation, performance analysis
- **Get-IISLogAnalyzer.ps1** - Advanced log analysis with security threat detection (SQL injection, XSS, path traversal)
- **Optimize-IISConfiguration.ps1** - Performance tuning and security hardening (HSTS, CSP, compression)
- **Backup-IISConfiguration.ps1** - Complete IIS configuration backup and restoration

**🐳 NEW CATEGORY: Container Management** - 3 scripts
- **Get-DockerHealthCheck.ps1** - Docker environment health, container/image/volume monitoring
- **Optimize-DockerCleanup.ps1** - Docker resource cleanup and storage optimization
- **Get-KubernetesHealthCheck.ps1** - Kubernetes cluster health, pod monitoring, event analysis

**☁️ NEW CATEGORY: Cloud Infrastructure** - 5 scripts
- **Get-AzureResourceHealth.ps1** - Azure resource monitoring and cost analysis
- **Get-AWSResourceInventory.ps1** - AWS resource inventory (EC2, S3, RDS, Lambda)
- Plus 3 more multi-cloud management scripts

**📧 NEW CATEGORY: Email Services (Exchange Server)** - 4 scripts
- **Get-ExchangeServerHealth.ps1** - Exchange Server health monitoring, database status, mail queues
- Plus 3 more Exchange management and reporting scripts

**🗄️ EXPANDED: Database Management** (+3 scripts)
- **Get-MySQLHealth.ps1** - MySQL server health monitoring and performance
- **Get-PostgreSQLHealth.ps1** - PostgreSQL health checks and query analysis
- **Get-SQLServerHealth.ps1** - SQL Server comprehensive monitoring (existing)

**🖥️ EXPANDED: Virtualization** (+2 scripts)
- **Get-VMwareHealth.ps1** - VMware vSphere/ESXi health monitoring
- **Get-HyperVHealth.ps1** - Hyper-V management (existing)

**☁️ EXPANDED: Microsoft 365** (+5 scripts)
- **Get-ComplianceCenterReport.ps1** - M365 Compliance Center DLP and retention reporting
- Plus 4 more Power Platform and Defender for Office 365 scripts

**📊 EXPANDED: Monitoring** (+3 scripts)
- **Get-SystemResourceTrends.ps1** - Historical performance trend analysis and capacity planning
- Plus 2 more advanced monitoring scripts

**🔒 EXPANDED: Security & Compliance** (+3 scripts)
- **Test-CISBenchmark.ps1** - CIS Benchmark compliance testing for Windows Server
- Plus 2 more NIST framework and security audit scripts

---

### Microsoft 365 Cloud Services Expansion

Complete M365 cloud management suite with **6 new scripts** across **4 service categories**:

**📧 Exchange Online Management** (2 scripts)
- **Get-MailboxHealth.ps1** - Mailbox quota monitoring, archive status, litigation hold, permissions
- **Get-SharedMailboxReport.ps1** - Shared mailbox auditing, permission analysis, sign-in status

**👥 Microsoft Teams** (1 script)
- **Get-TeamsReport.ps1** - Team usage, guest access, channel analysis, ownership verification

**📁 SharePoint / OneDrive** (1 script)
- **Get-OneDriveUsageReport.ps1** - OneDrive storage monitoring, quota warnings, inactive sites

**🔐 Azure AD / Entra ID** (2 scripts)
- **Get-AzureADGuestAudit.ps1** - Guest user security audit, privilege detection, domain analysis
- **Get-AzureADLicenseReport.ps1** - M365 license tracking, unused licenses, cost optimization

---

### Major Script Expansion - Extended Limits Release

Previous expansion with **13 enterprise-grade scripts** and **3 new categories**:

**🔒 Enhanced Security Scripts** (Server/Security - 4 total)

- **Manage-FirewallRules.ps1** (NEW) - Windows Firewall audit, compliance, and bulk management
- **Get-SecurityEventAudit.ps1** (NEW) - Analyze security logs for suspicious activities
- **Test-ServerHardening.ps1** (NEW) - Server hardening compliance (CIS/STIG/Microsoft baselines)
- **Test-CertificateExpiration.ps1** - SSL/TLS certificate monitoring

**👥 Enhanced User Management** (Server/User-Management - 3 total)
- **Get-UserAccessReport.ps1** - User permissions and access rights auditing
- **Get-InactiveUserReport.ps1** (NEW) - Find inactive AD accounts with privilege detection
- **Get-UserLockoutReport.ps1** (NEW) - Account lockout analysis and brute force detection

**💾 Backup & Recovery** (Server/Backup-Recovery - 3 total)
- **Get-BackupStatus.ps1** - Windows Server Backup verification
- **Manage-RestorePoints.ps1** - System restore point management
- **Test-BackupIntegrity.ps1** (NEW) - Backup integrity verification and VSS health

**🔧 System Utilities** (Utilities - 3 total)
- **Sync-UserGroupToPrimaryDeviceGroup.ps1** - Intune user-to-device sync
- **Get-SoftwareInventory.ps1** (NEW) - Comprehensive software inventory with winget support
- **Optimize-WindowsServices.ps1** (NEW) - Service optimization with Minimal/Balanced/Performance profiles

**🗄️ NEW CATEGORY: Database Management**
- **Get-SQLServerHealth.ps1** - SQL Server health monitoring (backups, logs, jobs, performance)

**🖥️ NEW CATEGORY: Virtualization**
- **Get-HyperVHealth.ps1** - Hyper-V host and VM health monitoring

**🖨️ NEW CATEGORY: Print Management**
- **Get-PrintServerHealth.ps1** - Print server monitoring and stuck job cleanup

**🔄 Enhanced Proactive Remediations** (11 pairs total - 2 NEW)
- **Fix-BrokenShortcuts** (NEW) - Remove broken Desktop/Start Menu shortcuts
- **Fix-DNSCache** (NEW) - DNS cache flush and client reset
- Plus 9 existing remediation pairs

**Complete Repository Structure:**
```
scripts/
├── web-services/           # NEW: IIS web server management (4 scripts)
│   └── iis/               # Health checks, log analysis, optimization, backup
├── container-management/   # NEW: Docker & Kubernetes (3 scripts)
│   ├── Docker health monitoring and cleanup
│   └── Kubernetes cluster management
├── cloud-infrastructure/   # NEW: Azure & AWS management (5 scripts)
│   ├── azure/             # Azure resource health and cost analysis
│   ├── aws/               # AWS inventory and security
│   └── multi-cloud/       # Multi-cloud management
├── email-services/         # NEW: Exchange Server (4 scripts)
│   └── exchange-server/   # Health monitoring, mailbox management
├── database/              # Database management (4 scripts - 3 NEW)
│   ├── SQL Server         # Get-SQLServerHealth.ps1
│   ├── MySQL             # Get-MySQLHealth.ps1 (NEW)
│   ├── PostgreSQL        # Get-PostgreSQLHealth.ps1 (NEW)
│   └── Oracle            # Get-OracleHealth.ps1 (NEW)
├── virtualization/        # Virtualization platforms (3 scripts - 2 NEW)
│   ├── Hyper-V           # Get-HyperVHealth.ps1
│   ├── VMware            # Get-VMwareHealth.ps1 (NEW)
│   └── Virtual Box       # Get-VirtualBoxHealth.ps1 (NEW)
├── m365/                  # Microsoft 365 cloud services (11 scripts - 5 NEW)
│   ├── exchange-online/   # Exchange Online mailbox management (2 scripts)
│   ├── teams/             # Microsoft Teams administration (1 script)
│   ├── sharepoint-onedrive/ # SharePoint and OneDrive (1 script)
│   ├── azure-ad/          # Azure AD / Entra ID (2 scripts)
│   ├── compliance/        # Compliance Center (NEW - 2 scripts)
│   ├── power-platform/    # Power Platform management (NEW - 2 scripts)
│   └── defender/          # Defender for Office 365 (NEW - 1 script)
├── server/                # Windows Server management (30+ scripts)
│   ├── active-directory/  # AD management (4 scripts)
│   ├── backup-recovery/   # Backup verification (3 scripts)
│   ├── group-policy/      # GPO management (3 scripts)
│   ├── monitoring/        # Server health (3 scripts)
│   ├── network/           # Network configuration (3 scripts)
│   ├── security/          # Security and certificates (4 scripts)
│   ├── storage/           # Disk and file management (3 scripts)
│   ├── system/            # System configuration (4 scripts)
│   └── user-management/   # User access and permissions (3 scripts)
├── monitoring/            # System monitoring (6 scripts - 3 NEW)
│   ├── Health checks and performance monitoring
│   ├── Resource trend analysis (NEW)
│   └── Capacity planning (NEW)
├── security-compliance/   # Security auditing (12 scripts - 3 NEW)
│   ├── Security baselines and audits
│   ├── CIS Benchmark testing (NEW)
│   ├── NIST framework compliance (NEW)
│   └── Compliance reporting (NEW)
├── print-management/      # Print server management (1 script)
├── network-management/    # Network diagnostics (3 scripts)
├── intune/                # Intune management (18+ scripts - 4 NEW)
│   ├── reporting/         # Compliance and status reports
│   ├── maintenance/       # Device cleanup and policy management
│   ├── deployment/        # Packaging and deployment tools
│   └── automation/        # Automated configuration (NEW - 4 scripts)
├── device-management/     # Device management
│   ├── proactive-remediations/ # Auto-fix scripts (11 pairs)
│   ├── winget-updates/    # Application updates (40+ apps)
│   ├── autopatch/         # Windows Update policies
│   ├── bitlocker-backup/  # BitLocker key backup
│   └── device-uptime/     # Uptime monitoring
└── utilities/             # System utilities (3 scripts)
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

**NEW INFRASTRUCTURE CATEGORIES:**
- **[Web Services (IIS)](scripts/web-services/README.md)** - IIS health monitoring, log analysis, optimization, backup (4 scripts - NEW!)
- **[Container Management](scripts/container-management/README.md)** - Docker & Kubernetes monitoring and management (3 scripts - NEW!)
- **[Cloud Infrastructure](scripts/cloud-infrastructure/README.md)** - Azure & AWS resource management (5 scripts - NEW!)
- **[Email Services](scripts/email-services/README.md)** - Exchange Server health and management (4 scripts - NEW!)

**EXPANDED CATEGORIES:**
- **[Database Management](scripts/database/)** - SQL Server, MySQL, PostgreSQL, Oracle (4 scripts - 3 NEW!)
- **[Virtualization](scripts/virtualization/)** - Hyper-V, VMware vSphere/ESXi (3 scripts - 2 NEW!)
- **[Microsoft 365 Scripts](scripts/m365/README.md)** - Exchange Online, Teams, SharePoint, Azure AD, Compliance, Power Platform (11 scripts - 5 NEW!)
- **[Security & Compliance](scripts/security-compliance/README.md)** - CIS Benchmark, NIST framework, security auditing (12 scripts - 3 NEW!)
- **[Monitoring Scripts](scripts/monitoring/)** - System health, performance trends, capacity planning (6 scripts - 3 NEW!)

**EXISTING CATEGORIES:**
- **[Intune Management Scripts](scripts/intune/README.md)** - Comprehensive Intune administration toolkit (18+ scripts)
- **[Intune Sync Guide](docs/INTUNE-SYNC-README.md)** - User group to device group synchronization
- **[Server Management Scripts](scripts/server/README.md)** - Windows Server administration tools (30+ scripts)
- **[Print Management Scripts](scripts/print-management/)** - Print server monitoring (1 script)
- **[Network Management Scripts](scripts/network-management/)** - Network diagnostics and troubleshooting (3 scripts)
- **[Proactive Remediations](scripts/device-management/proactive-remediations/README.md)** - Auto-fix common issues (11 remediation pairs)
- **[Winget Update Templates](scripts/device-management/winget-updates/Template/README.md)** - Application auto-update setup (40+ apps)

## Repository Structure

```
bug-free-umbrella/
├── docs/                              # Documentation
├── scripts/
│   ├── m365/                          # Microsoft 365 cloud services (6 scripts - NEW)
│   │   ├── exchange-online/           # Exchange Online mailbox management
│   │   ├── teams/                     # Microsoft Teams administration
│   │   ├── sharepoint-onedrive/       # SharePoint and OneDrive management
│   │   └── azure-ad/                  # Azure AD / Entra ID management
│   ├── intune/                        # Intune management tools (18 scripts)
│   │   ├── reporting/                 # Compliance, status, and audit reports
│   │   ├── maintenance/               # Device cleanup and policy management
│   │   └── deployment/                # Packaging and deployment tools
│   ├── server/                        # Server management tools (30 scripts)
│   │   ├── active-directory/          # AD user/service account auditing (4 scripts)
│   │   ├── backup-recovery/           # Backup verification and restore points (3 scripts)
│   │   ├── group-policy/              # GPO management and reporting (3 scripts)
│   │   ├── monitoring/                # Server health and performance (3 scripts)
│   │   ├── network/                   # Network configuration and connectivity (3 scripts)
│   │   ├── security/                  # Security and certificates (4 scripts)
│   │   ├── storage/                   # Disk and file management (3 scripts)
│   │   ├── system/                    # System configuration and updates (4 scripts)
│   │   └── user-management/           # User access and permissions (3 scripts)
│   ├── database/                      # Database management (SQL Server) (NEW)
│   ├── virtualization/                # Hyper-V management (NEW)
│   ├── print-management/              # Print server management (NEW)
│   ├── security-compliance/           # Security auditing and compliance (9 scripts)
│   ├── monitoring/                    # System health checks and monitoring (3 scripts)
│   ├── network-management/            # Network diagnostics and troubleshooting (3 scripts)
│   ├── utilities/                     # System utilities (3 scripts)
│   ├── device-management/             # Device management scripts
│   │   ├── proactive-remediations/    # Auto-fix scripts (11 pairs)
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

## 💡 Common Use Cases

Find the right tool for your needs:

| I need to... | Use this script | Location |
|--------------|----------------|----------|
| **Microsoft 365 Cloud Services** (NEW) |
| Check Exchange mailbox health | Get-MailboxHealth.ps1 (NEW) | [scripts/m365/exchange-online/](scripts/m365/exchange-online/) |
| Audit shared mailboxes | Get-SharedMailboxReport.ps1 (NEW) | [scripts/m365/exchange-online/](scripts/m365/exchange-online/) |
| Monitor Microsoft Teams usage | Get-TeamsReport.ps1 (NEW) | [scripts/m365/teams/](scripts/m365/teams/) |
| Check OneDrive storage usage | Get-OneDriveUsageReport.ps1 (NEW) | [scripts/m365/sharepoint-onedrive/](scripts/m365/sharepoint-onedrive/) |
| Audit Azure AD guest users | Get-AzureADGuestAudit.ps1 (NEW) | [scripts/m365/azure-ad/](scripts/m365/azure-ad/) |
| Review M365 license usage | Get-AzureADLicenseReport.ps1 (NEW) | [scripts/m365/azure-ad/](scripts/m365/azure-ad/) |
| **Intune Management** |
| Find devices that haven't synced in months | Find-StaleDevices.ps1 | [scripts/intune/](scripts/intune/) |
| Check BitLocker encryption status | Get-BitLockerStatus.ps1 | [scripts/intune/](scripts/intune/) |
| See which devices are non-compliant | Get-DeviceComplianceReport.ps1 | [scripts/intune/](scripts/intune/) |
| Auto-update applications via winget | Winget Update Templates | [scripts/device-management/winget-updates/](scripts/device-management/winget-updates/) |
| **Server Management** |
| Fix stuck Windows Updates | Reset-WindowsUpdate.ps1 | [scripts/server/](scripts/server/) |
| Clean up server disk space | Get-DiskReport.ps1 / Optimize-ServerStorage.ps1 | [scripts/server/](scripts/server/) |
| Audit Active Directory users | Get-ADUserAudit.ps1 | [scripts/server/active-directory/](scripts/server/active-directory/) |
| Backup all Group Policies | Backup-GroupPolicies.ps1 | [scripts/server/group-policy/](scripts/server/group-policy/) |
| Find inactive user accounts | Get-InactiveUserReport.ps1 (NEW) | [scripts/server/user-management/](scripts/server/user-management/) |
| Test backup integrity | Test-BackupIntegrity.ps1 (NEW) | [scripts/server/backup-recovery/](scripts/server/backup-recovery/) |
| **Security & Compliance** |
| Audit local administrator accounts | Get-LocalAdminAudit.ps1 | [scripts/security-compliance/](scripts/security-compliance/) |
| Check security baseline compliance | Get-SecurityBaseline.ps1 | [scripts/security-compliance/](scripts/security-compliance/) |
| Find expired certificates | Get-ExpiredCertificates.ps1 | [scripts/security-compliance/](scripts/security-compliance/) |
| Review failed login attempts | Get-FailedLoginReport.ps1 | [scripts/security-compliance/](scripts/security-compliance/) |
| Audit Windows Firewall rules | Manage-FirewallRules.ps1 (NEW) | [scripts/server/security/](scripts/server/security/) |
| Check server hardening compliance | Test-ServerHardening.ps1 (NEW) | [scripts/server/security/](scripts/server/security/) |
| **Monitoring & Troubleshooting** |
| Check server health status | Monitor-ServerHealth.ps1 | [scripts/monitoring/](scripts/monitoring/) |
| Diagnose network issues | Test-NetworkConnectivity.ps1 | [scripts/network-management/](scripts/network-management/) |
| Monitor performance trends | Get-PerformanceTrends.ps1 | [scripts/monitoring/](scripts/monitoring/) |
| **Web Services (IIS)** (NEW!) |
| Monitor IIS health and SSL certificates | Get-IISHealthCheck.ps1 (NEW) | [scripts/web-services/iis/](scripts/web-services/iis/) |
| Analyze IIS logs for security threats | Get-IISLogAnalyzer.ps1 (NEW) | [scripts/web-services/iis/](scripts/web-services/iis/) |
| Optimize IIS performance and security | Optimize-IISConfiguration.ps1 (NEW) | [scripts/web-services/iis/](scripts/web-services/iis/) |
| Backup IIS configuration | Backup-IISConfiguration.ps1 (NEW) | [scripts/web-services/iis/](scripts/web-services/iis/) |
| **Container Management** (NEW!) |
| Monitor Docker container health | Get-DockerHealthCheck.ps1 (NEW) | [scripts/container-management/](scripts/container-management/) |
| Clean up Docker resources | Optimize-DockerCleanup.ps1 (NEW) | [scripts/container-management/](scripts/container-management/) |
| Check Kubernetes cluster health | Get-KubernetesHealthCheck.ps1 (NEW) | [scripts/container-management/](scripts/container-management/) |
| **Cloud Infrastructure** (NEW!) |
| Monitor Azure resources and costs | Get-AzureResourceHealth.ps1 (NEW) | [scripts/cloud-infrastructure/azure/](scripts/cloud-infrastructure/azure/) |
| Inventory AWS resources | Get-AWSResourceInventory.ps1 (NEW) | [scripts/cloud-infrastructure/aws/](scripts/cloud-infrastructure/aws/) |
| **Email Services** (NEW!) |
| Check Exchange Server health | Get-ExchangeServerHealth.ps1 (NEW) | [scripts/email-services/exchange-server/](scripts/email-services/exchange-server/) |
| **Database Management** (EXPANDED) |
| Check SQL Server health | Get-SQLServerHealth.ps1 | [scripts/database/](scripts/database/) |
| Monitor MySQL server | Get-MySQLHealth.ps1 (NEW) | [scripts/database/](scripts/database/) |
| Monitor PostgreSQL server | Get-PostgreSQLHealth.ps1 (NEW) | [scripts/database/](scripts/database/) |
| **Virtualization** (EXPANDED) |
| Monitor Hyper-V health | Get-HyperVHealth.ps1 | [scripts/virtualization/](scripts/virtualization/) |
| Monitor VMware vSphere/ESXi | Get-VMwareHealth.ps1 (NEW) | [scripts/virtualization/](scripts/virtualization/) |
| **Monitoring & Performance** (EXPANDED) |
| Analyze resource usage trends | Get-SystemResourceTrends.ps1 (NEW) | [scripts/monitoring/](scripts/monitoring/) |
| Check server health status | Monitor-ServerHealth.ps1 | [scripts/monitoring/](scripts/monitoring/) |
| Monitor performance trends | Get-PerformanceTrends.ps1 | [scripts/monitoring/](scripts/monitoring/) |
| **Security & Compliance** (EXPANDED) |
| Test CIS Benchmark compliance | Test-CISBenchmark.ps1 (NEW) | [scripts/security-compliance/](scripts/security-compliance/) |
| Audit local administrator accounts | Get-LocalAdminAudit.ps1 | [scripts/security-compliance/](scripts/security-compliance/) |
| Check security baseline compliance | Get-SecurityBaseline.ps1 | [scripts/security-compliance/](scripts/security-compliance/) |
| **Print & Infrastructure** |
| Check print server status | Get-PrintServerHealth.ps1 | [scripts/print-management/](scripts/print-management/) |
| **System Utilities** |
| Generate software inventory | Get-SoftwareInventory.ps1 | [scripts/utilities/](scripts/utilities/) |
| Optimize Windows services | Optimize-WindowsServices.ps1 | [scripts/utilities/](scripts/utilities/) |

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

