# 📍 Bug-Free Umbrella - Documentation Navigation Guide

![Tier](https://img.shields.io/badge/Tier-1-green) ![Category](https://img.shields.io/badge/Category-Foundation-blue) ![Status](https://img.shields.io/badge/Status-Stable-brightgreen)

> **Your roadmap to finding exactly what you need, fast!**

---

## Table of Contents

- [Quick Start](#quick-start---i-want-to)
- [Quick Start Paths](#quick-start-paths)
- [Complete Documentation Index](#complete-documentation-index)
- [Script Index by Category](#script-index-by-category)
- [Learning Paths](#learning-paths)
- [Repository Statistics](#repository-statistics)
- [Latest Updates](#latest-updates-v307-shower)
- [Tips for Navigation](#tips-for-navigation)
- [External Links](#external-links)
- [Featured Scripts](#featured-scripts)
- [Need Help](#need-help)
- [See Also](#see-also)

---

## 🚀 Quick Start - "I want to..."

### For First-Time Users
| What you want to do | Go here |
|---------------------|---------|
| **Understand what this repo is** | [Main README](https://github.com/Carme99/bug-free-umbrella/blob/main/README.md) |
| **See what's new** | [CHANGELOG](https://github.com/Carme99/bug-free-umbrella/blob/main/CHANGELOG.md) - Check out our fun release names! 🌈 |
| **Get started quickly** | [Quick Start Guide](#quick-start-paths) (below) |
| **See example outputs** | [Script Examples](Script-Examples) |

### For Active Users
| What you want to do | Go here |
|---------------------|---------|
| **Follow a complete workflow** | [Workflows](Workflows) |
| **Troubleshoot a problem** | [Troubleshooting](Troubleshooting) |
| **Find a specific script** | [Script Index](#script-index-by-category) (below) |
| **Contribute** | [CONTRIBUTING.md](https://github.com/Carme99/bug-free-umbrella/blob/main/CONTRIBUTING.md) |
| **Report security issue** | [SECURITY.md](https://github.com/Carme99/bug-free-umbrella/blob/main/SECURITY.md) |

---

## 🎯 Quick Start Paths

### Path 1: "I manage Microsoft 365 / Intune"
```
START HERE → Main README → M365 Scripts Section
           ↓
    Choose your focus:
    • Intune device management     → scripts/intune/
    • Exchange mailboxes           → scripts/m365/exchange-online/
    • Teams & SharePoint           → scripts/m365/teams/ or sharepoint-onedrive/
    • Regional settings            → scripts/m365/ (7 new scripts!)
           ↓
    See examples → Script-Examples
           ↓
    Follow workflow → Workflows
```

### Path 2: "I manage Windows Servers"
```
START HERE → Main README → Server Management Section
           ↓
    Choose your need:
    • Health monitoring           → scripts/server/monitoring/
    • Active Directory            → scripts/server/active-directory/
    • Group Policy                → scripts/server/group-policy/
    • Backup verification         → scripts/server/backup-recovery/
           ↓
    See examples → Script-Examples
           ↓
    Fix issues → Troubleshooting
```

### Path 3: "I do DevOps / Cloud Infrastructure"
```
START HERE → Main README → Cloud & DevOps Section
           ↓
    Choose your platform:
    • Azure DevOps / GitHub       → scripts/devops-cicd/
    • Azure infrastructure        → scripts/cloud-infrastructure/azure/
    • AWS infrastructure          → scripts/cloud-infrastructure/aws/
    • Kubernetes / Docker         → scripts/container-management/
    • Terraform / Bicep           → scripts/infrastructure-as-code/
           ↓
    See examples → Script-Examples
           ↓
    Follow workflow → Workflows
```

### Path 4: "I want to auto-fix common PC problems"
```
START HERE → Main README → Proactive Remediations
           ↓
    scripts/device-management/proactive-remediations/
           ↓
    Choose what to fix:
    • Low disk space              → Fix-DiskSpace/
    • Stuck Windows Updates       → Fix-WindowsUpdateStuck/
    • BitLocker not backed up     → Fix-BitLockerNotEscrowedKeys/
    • Stale user profiles         → Fix-StaleProfiles/
    • Teams cache issues          → Fix-TeamsCache/
    • ...and 9 more!
           ↓
    Deploy workflow → Workflows (Automated Winget Updates section)
```

### Path 5: "I want to automate app updates"
```
START HERE → Main README → Winget Updates Section
           ↓
    scripts/device-management/winget-updates/
           ↓
    40+ app templates organized by category:
    • browsers/                   → Chrome, Firefox, Edge
    • communication/              → Teams, Zoom, Slack
    • development/                → VS Code, Git, Python
    • productivity/               → 7-Zip, Notepad++, Adobe Reader
    • runtimes/                   → .NET, C++, Java
           ↓
    Follow setup guide → Workflows (Setting up Automated Winget Updates)
```

---

## 📚 Complete Documentation Index

### Core Documentation Files

| Document | Purpose | When to Use |
|----------|---------|-------------|
| **[README.md](https://github.com/Carme99/bug-free-umbrella/blob/main/README.md)** | Repository overview, quick start | First stop for new users |
| **[CHANGELOG.md](https://github.com/Carme99/bug-free-umbrella/blob/main/CHANGELOG.md)** | Version history with fun codenames! 🌂 | See what's new, understand changes |
| **[Wiki Home](Home)** | Complete documentation hub | Deep dive into all scripts |
| **[Script Examples](Script-Examples)** | Detailed examples with outputs | Learn how scripts work |
| **[Workflows](Workflows)** | End-to-end step-by-step guides | Follow complete processes |
| **[Troubleshooting](Troubleshooting)** | Common issues and solutions | When things don't work |
| **[Intune Sync Guide](Intune-Sync-Guide)** | User group → device group sync | Specific Intune sync scenarios |
| **[CONTRIBUTING.md](https://github.com/Carme99/bug-free-umbrella/blob/main/CONTRIBUTING.md)** | How to contribute | Want to add scripts or fixes |
| **[SECURITY.md](https://github.com/Carme99/bug-free-umbrella/blob/main/SECURITY.md)** | Security policy | Report vulnerabilities |
| **[SCRIPT_ANALYSIS_REPORT.md](https://github.com/Carme99/bug-free-umbrella/blob/main/SCRIPT_ANALYSIS_REPORT.md)** | PowerShell code analysis | Understand code quality |

---

## 🗂️ Script Index by Category

### ☁️ Cloud & Infrastructure (40+ scripts)

#### API Management (2 scripts)
**Location:** `scripts/api-management/`
- Monitor-AzureAPIManagement.ps1 - Azure APIM health monitoring
- Test-APIHealth.ps1 - Universal API endpoint testing

#### Cloud Infrastructure (15+ scripts)
**Location:** `scripts/cloud-infrastructure/`

**Azure** (`azure/`)
- Get-AzureResourceHealth.ps1 - Multi-subscription monitoring
- Monitor-AzureResources.ps1 - Resource health & cost analysis
- Monitor-AzureKeyVaults.ps1 - Key Vault monitoring
- Get-VMSecurityConfig.ps1 - VM security audit
- Get-VMBackupCompliance.ps1 - VM backup compliance
- Optimize-AzureVMs.ps1 - VM optimization

**AWS** (`aws/`)
- Get-AWSResourceInventory.ps1 - Multi-region inventory

#### Container Management (3 scripts)
**Location:** `scripts/container-management/`
- Get-DockerHealthCheck.ps1 - Docker environment health
- Get-KubernetesHealthCheck.ps1 - K8s cluster monitoring
- Optimize-DockerCleanup.ps1 - Docker resource cleanup

#### Infrastructure as Code (2 scripts)
**Location:** `scripts/infrastructure-as-code/`
- Test-TerraformConfiguration.ps1 - Terraform validation & security
- Test-BicepTemplates.ps1 - Azure Bicep validation

---

### 🔄 DevOps & Development (8 scripts)

#### DevOps CI/CD (4 scripts)
**Location:** `scripts/devops-cicd/`
- Monitor-AzureDevOpsPipelines.ps1 - Azure DevOps monitoring
- Monitor-GitHubActions.ps1 - GitHub Actions workflows
- Monitor-GitLabCI.ps1 - GitLab CI/CD pipelines
- Analyze-BuildPerformance.ps1 - Build performance analysis

#### Database Management (4 scripts)
**Location:** `scripts/database/`
- Get-SQLServerHealth.ps1 - SQL Server comprehensive monitoring
- Get-MySQLHealth.ps1 - MySQL server health
- Get-PostgreSQLHealth.ps1 - PostgreSQL monitoring
- Monitor-MongoDBHealth.ps1 - MongoDB health

---

### 💼 Microsoft 365 & Enterprise (45+ scripts)

#### Microsoft 365 Cloud Services (19 scripts)
**Location:** `scripts/m365/`

**Exchange Online** (`exchange-online/`)
- Get-MailboxHealth.ps1 - Mailbox health monitoring
- Get-SharedMailboxAudit.ps1 - Shared mailbox audit
- Set-MailboxRegionalSettings.ps1 - Regional configuration

**Teams** (`teams/`)
- Get-TeamsReport.ps1 - Teams usage reporting
- Set-TeamsRegionalSettings.ps1 - Teams regional settings

**SharePoint & OneDrive** (`sharepoint-onedrive/`)
- Get-OneDriveUsageReport.ps1 - Storage analytics
- Set-SiteRegionalSettings.ps1 - Site regional configuration
- Set-OneDriveRegionalSettings.ps1 - OneDrive settings

**Azure AD / Entra ID** (`azure-ad/`)
- Get-AzureADGuestAudit.ps1 - Guest user audit
- Get-AzureADLicenseReport.ps1 - License reporting
- Set-UserLanguageSettings.ps1 - User language config
- Set-OrganizationDefaults.ps1 - Tenant defaults

**Compliance Center** (`compliance/`)
- Compliance reporting scripts

**Power Platform** (`power-platform/`)
- Set-PowerPlatformRegionalSettings.ps1 - Environment settings

**Defender for Office 365** (`defender/`)
- Threat reporting and monitoring

#### Intune Management (18+ scripts)
**Location:** `scripts/intune/`

**Reporting** (`reporting/`)
- Get-DeviceComplianceReport.ps1 - Compliance status
- Get-BitLockerStatus.ps1 - Encryption audit
- Get-WindowsUpdateCompliance.ps1 - Update status

**Maintenance** (`maintenance/`)
- Find-StaleDevices.ps1 - Stale device detection
- Device cleanup utilities

**Deployment** (`deployment/`)
- Packaging and deployment tools

#### Email Services (4 scripts)
**Location:** `scripts/email-services/`
- Get-ExchangeServerHealth.ps1 - Exchange Server monitoring
- Exchange management scripts

---

### 🔒 Security & Compliance (13 scripts)

#### Advanced Security (1 script)
**Location:** `scripts/security/hardening/`
- Invoke-SecurityComplianceScan.ps1 - Multi-framework scanning (CIS, NIST, PCI-DSS, HIPAA, SOC2, ISO27001)

#### Security & Compliance (12 scripts)
**Location:** `scripts/security/compliance/frameworks/`
- Test-CISBenchmark.ps1 - **NEW v2.0.0! 15+ CIS controls** 🔧 *(Fixed in v3.0.1)*
  - Password policies (6 controls: history, age, length, complexity)
  - Account lockout policies (3 controls: duration, threshold, reset)
  - Audit policies (6+ controls: credential validation, logon, process creation)
  - Level 1 & Level 2 benchmark support
  - HTML compliance reports with recommendations
  - Requires Administrator privileges
- Get-SecurityBaseline.ps1 - Baseline verification
- Get-LocalAdminAudit.ps1 - Local admin auditing
- Certificate and security monitoring

---

### 🖥️ Server & Infrastructure (40+ scripts)

#### Server Management (30+ scripts)
**Location:** `scripts/server/`

**Active Directory** (`active-directory/`)
- Get-ADUserAudit.ps1 - User account auditing
- Service account discovery

**Backup & Recovery** (`backup-recovery/`)
- Backup verification scripts

**Group Policy** (`group-policy/`)
- Backup-GroupPolicies.ps1 - GPO backup automation

**Monitoring** (`monitoring/`)
- Monitor-ServerHealth.ps1 - **NEW! 13 major features!** 🌈
  - Interactive mode with menu
  - Disk I/O, Windows Update status, Security monitoring
  - Network connectivity, Certificate monitoring
  - Scheduled tasks, Application monitoring
  - JSON export, Email reporting

**Storage** (`storage/`)
- Disk space management

**System** (`system/`)
- Reset-WindowsUpdate.ps1 - Fix stuck updates
- Check-SystemIntegrity.ps1 - SFC/DISM checks

#### Web Services (4 scripts)
**Location:** `scripts/web-services/`
- Get-IISHealthCheck.ps1 - IIS health monitoring
- Get-IISLogAnalyzer.ps1 - Log analysis + threat detection
- Optimize-IISConfiguration.ps1 - Performance tuning
- Backup-IISConfiguration.ps1 - Configuration backup

#### Linux Server
**Location:** `scripts/linux-server/`
- Linux server administration scripts

---

### 🖱️ Device Management (60+ scripts)

#### Proactive Remediations (14 pairs = 28 scripts)
**Location:** `scripts/device-management/proactive-remediations/`

Each has `detect.ps1` and `remediate.ps1`:
- **Fix-DiskSpace** - Low disk space cleanup
- **Fix-TempFiles** - Temporary file removal
- **Fix-StaleProfiles** - Old profile cleanup
- **Fix-WindowsUpdateStuck** - Windows Update reset
- **Fix-BitLockerNotEscrowedKeys** - BitLocker key backup (**Enhanced! 🌈**)
- **Fix-TeamsCache** - Teams cache cleanup
- **Fix-PrintSpooler** - Print spooler repair
- **Fix-DNSCache** - DNS cache flush
- **Fix-WindowsSearch** - Search index rebuild
- **Fix-BrokenShortcuts** - Shortcut cleanup
- **Check-SecurityBaseline** - Security enforcement
- **region-language-settings** - Windows regional settings
- **keyboard-layout** - Keyboard layout enforcement
- **language-pack-audit** - Language pack cleanup

#### Winget Application Updates (40+ apps)
**Location:** `scripts/device-management/winget-updates/`

Organized by category:
- `browsers/` - Chrome, Firefox, Edge
- `communication/` - Teams, Zoom, Slack, Discord
- `development/` - VS Code, Git, Python, Node.js, Azure CLI
- `media/` - VLC, Spotify, iTunes
- `productivity/` - 7-Zip, Notepad++, Adobe Reader
- `remote-access/` - TeamViewer, AnyDesk, WinSCP
- `runtimes/` - .NET, C++ Redistributables, Java
- `utilities/` - Various system utilities

#### Other Device Management
**Location:** `scripts/device-management/`
- `autopatch/` - Windows Update policy management (V1-V5)
- `bitlocker-backup/` - BitLocker key backup scripts
- `device-uptime/` - Uptime monitoring
- `remove-sccm/` - SCCM client removal
- `adobe-rum/` - Adobe Remote Update Manager
- `l16-driver-block/` - Lenovo L16 driver management

---

### 🔧 Monitoring & Operations (10 scripts)

#### Monitoring (6 scripts)
**Location:** `scripts/monitoring/`
- Monitor-ServerHealth.ps1 - **Massively expanded! 🌈**
- Get-PerformanceTrends.ps1 - Performance trending
- System health checks

#### Network Management (3 scripts)
**Location:** `scripts/network-management/`
- Test-NetworkConnectivity.ps1 - Network diagnostics
- Network troubleshooting tools

#### Print Management (1 script)
**Location:** `scripts/print-management/`
- Print server monitoring

---

### 🛠️ Utilities & Other (10+ scripts)

#### Utilities (3 scripts)
**Location:** `scripts/utilities/`
- System utility scripts

#### Virtualization (3 scripts)
**Location:** `scripts/virtualization/`
- Hyper-V management
- VMware vSphere/ESXi management

#### Azure Virtual Desktop
**Location:** `AzureVirtualDesktop/`
- Remove-SysprepBlockers.ps1 - **Performance improved! 🌈**

---

## 🎓 Learning Paths

### Beginner Path: "New to PowerShell automation"
1. Start with [Main README](https://github.com/Carme99/bug-free-umbrella/blob/main/README.md) - understand the repository
2. Review [Script Examples](Script-Examples) - see how scripts work
3. Try a simple script like `Get-DeviceComplianceReport.ps1`
4. Review [Troubleshooting](Troubleshooting) if issues arise
5. Explore [Proactive Remediations](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations) for auto-fix scripts

### Intermediate Path: "I know PowerShell, want to deploy"
1. Review [Main README](https://github.com/Carme99/bug-free-umbrella/blob/main/README.md) prerequisites section
2. Pick your focus area from [Script Index](#script-index-by-category)
3. Follow a complete workflow from [Workflows](Workflows)
4. Review [CHANGELOG.md](https://github.com/Carme99/bug-free-umbrella/blob/main/CHANGELOG.md) for latest improvements
5. Consider [contributing](https://github.com/Carme99/bug-free-umbrella/blob/main/CONTRIBUTING.md) improvements

### Advanced Path: "I want to customize and contribute"
1. Read [CONTRIBUTING.md](https://github.com/Carme99/bug-free-umbrella/blob/main/CONTRIBUTING.md) guidelines
2. Review [SCRIPT_ANALYSIS_REPORT.md](https://github.com/Carme99/bug-free-umbrella/blob/main/SCRIPT_ANALYSIS_REPORT.md) for code quality standards
3. Check [CHANGELOG.md](https://github.com/Carme99/bug-free-umbrella/blob/main/CHANGELOG.md) - see what's been improved (e.g., 🌈 Rainbow release)
4. Fork, customize, and submit pull requests
5. Help expand documentation and examples

---

## 📊 Repository Statistics

| Metric | Count |
|--------|-------|
| **Total Scripts** | 260+ |
| **Script Categories** | 20 |
| **Proactive Remediations** | 14 pairs (28 scripts) |
| **Winget App Templates** | 40+ |
| **Documentation Files** | 10 |
| **Latest Release** | 3.7.0 "Shower" 🌧️ |

---

## ☔ Latest Updates (v3.7.0 "Shower")

**What's New:**
- 📚 **Comprehensive Tier 3 Documentation**: Advanced operations and optimization guides for expert users
- 🎨 **Enhanced Wiki Standards**: Consistent formatting with badges, TOCs, and cross-references
- 🔗 **Improved Navigation**: Standardized "See Also" sections linking related pages
- ✨ **Better UX**: All internal wiki links now use proper wiki-style navigation

**See full details:** [CHANGELOG.md](https://github.com/Carme99/bug-free-umbrella/blob/main/CHANGELOG.md)

---

## 💡 Tips for Navigation

### Finding Scripts
1. **By Function**: Use the [Quick Start Paths](#quick-start-paths) above
2. **By Category**: Browse the [Script Index](#script-index-by-category)
3. **By Name**: Check the category folders in `scripts/`

### Understanding Scripts
1. **See Examples**: [Script Examples](Script-Examples) has detailed usage
2. **Get Help**: All major scripts support `Get-Help .\ScriptName.ps1 -Detailed`
3. **Check Comments**: Every script has inline comments explaining logic

### Following Processes
1. **Complete Workflows**: [Workflows](Workflows) has end-to-end guides
2. **Common Issues**: [Troubleshooting](Troubleshooting) has solutions
3. **Specific Scenarios**: Check individual script documentation

---

## 🔗 External Links

- **GitHub Repository**: [Carme99/bug-free-umbrella](https://github.com/Carme99/bug-free-umbrella)
- **Issues & Feature Requests**: [GitHub Issues](https://github.com/Carme99/bug-free-umbrella/issues)
- **Changelog with Fun Codenames**: [CHANGELOG.md](https://github.com/Carme99/bug-free-umbrella/blob/main/CHANGELOG.md) 🌂
- **Claude Code**: [github.com/anthropics/claude-code](https://github.com/anthropics/claude-code)

---

## 🌟 Featured Scripts

### 🆕 Recently Enhanced (v3.7.0 Shower 🌧️)
- **Comprehensive Documentation Enhancements**
  - 9 new Tier 3 documentation pages for advanced topics
  - Critical fixes for version inconsistencies and duplicate content
  - Standardized wiki formatting across all pages

### 🔥 Most Popular
- **Get-DeviceComplianceReport.ps1** - Intune compliance reporting
- **Fix-WindowsUpdateStuck** - Fix stuck Windows Updates
- **Set-UserLanguageSettings.ps1** - M365 user language management
- **Get-AzureResourceHealth.ps1** - Azure resource monitoring

### 🎯 Recommended for New Users
- **Fix-DiskSpace** - Easy to understand detect/remediate pattern
- **Get-BitLockerStatus** - Simple Intune reporting
- **Test-APIHealth** - Universal API testing

---

## 📞 Need Help?

| Question Type | Resource |
|---------------|----------|
| "How do I use this script?" | [Script Examples](Script-Examples) |
| "Something's not working" | [Troubleshooting](Troubleshooting) |
| "How do I deploy this?" | [Workflows](Workflows) |
| "What's new?" | [CHANGELOG.md](https://github.com/Carme99/bug-free-umbrella/blob/main/CHANGELOG.md) |
| "I want to contribute" | [CONTRIBUTING.md](https://github.com/Carme99/bug-free-umbrella/blob/main/CONTRIBUTING.md) |
| "I found a security issue" | [SECURITY.md](https://github.com/Carme99/bug-free-umbrella/blob/main/SECURITY.md) |
| "General questions" | Check script comments or [GitHub Issues](https://github.com/Carme99/bug-free-umbrella/issues) |

---

## See Also

- [Getting Started](Getting-Started) - Step-by-step onboarding
- [Prerequisites](Prerequisites) - System requirements and setup
- [Home](Home) - Wiki homepage and complete overview
- [Workflows](Workflows) - End-to-end process guides
- [Troubleshooting](Troubleshooting) - Solve common problems
- [Support Guide](https://github.com/Carme99/bug-free-umbrella/blob/main/SUPPORT.md) - Get help

---

**Last Updated:** 2026-01-28  
**Wiki Version:** 1.2.0  
**Status:** Current with v3.7.0 Release  
**Maintained by:** Carme99 with [Claude Code](https://claude.com/claude-code)
