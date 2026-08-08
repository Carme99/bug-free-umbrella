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
- [Latest Updates](#latest-updates-v430-zephyr)
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
| **Understand what this repo is** | [Main README](../README.md) |
| **See what's new** | [CHANGELOG](../CHANGELOG.md) - Check out our fun release names! 🌈 |
| **Get started quickly** | [Quick Start Guide](#quick-start-paths) (below) |
| **See example outputs** | [Script Examples](Script-Examples.md) |

### For Active Users
| What you want to do | Go here |
|---------------------|---------|
| **Follow a complete workflow** | [Workflows](Workflows.md) |
| **Troubleshoot a problem** | [Troubleshooting](Troubleshooting.md) |
| **Find a specific script** | [Script Index](#script-index-by-category) (below) |
| **Contribute** | [CONTRIBUTING](../CONTRIBUTING.md) |
| **Report security issue** | [SECURITY](../SECURITY.md) |

---

## 🎯 Quick Start Paths

### Path 1: "I manage Microsoft 365 / Intune"
```
START HERE → Main README → M365 Scripts Section
           ↓
    Choose your focus:
    • Intune device management     → scripts/endpoints/intune/
    • Exchange mailboxes           → scripts/collaboration/microsoft365/exchange-online/
    • Teams & SharePoint           → scripts/collaboration/microsoft365/teams/ or scripts/collaboration/microsoft365/sharepoint-onedrive/
    • Regional settings            → scripts/collaboration/microsoft365/
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
    • Health monitoring           → scripts/infrastructure/windows/monitoring/
    • Active Directory            → scripts/infrastructure/windows/active-directory/
    • Group Policy                → scripts/infrastructure/windows/group-policy/
    • Backup verification         → scripts/infrastructure/windows/backup-recovery/
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
    • Azure DevOps / GitHub       → scripts/automation/cicd/
    • Azure infrastructure        → scripts/cloud/azure/
    • AWS infrastructure          → scripts/cloud/aws/
    • Kubernetes / Docker         → scripts/cloud/containers/
    • Terraform / Bicep           → scripts/automation/iac/
           ↓
    See examples → Script-Examples
           ↓
    Follow workflow → Workflows
```

### Path 4: "I want to auto-fix common PC problems"
```
START HERE → Main README → Proactive Remediations
           ↓
    scripts/endpoints/devices/proactive-remediations/
           ↓
    Choose what to fix:
    • Low disk space              → Fix-DiskSpace/
    • Stuck Windows Updates       → Fix-WindowsUpdateStuck/
    • BitLocker not backed up     → Fix-BitLockerNotEscrowedKeys/
    • Stale user profiles         → Fix-StaleProfiles/
    • Teams cache issues          → Fix-TeamsCache/
    • ...and 46 more!
           ↓
    Deploy workflow → Workflows (Automated Winget Updates section)
```

### Path 5: "I want to automate app updates"
```
START HERE → Main README → Winget Updates Section
           ↓
    scripts/endpoints/devices/winget/
           ↓
    35 app templates organized by category:
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
| **[README](../README.md)** | Repository overview, quick start | First stop for new users |
| **[CHANGELOG](../CHANGELOG.md)** | Version history with fun codenames! 🌂 | See what's new, understand changes |
| **[Documentation Home](README.md)** | Complete documentation hub | Deep dive into all scripts |
| **[Script Examples](Script-Examples.md)** | Detailed examples with outputs | Learn how scripts work |
| **[Workflows](Workflows.md)** | End-to-end step-by-step guides | Follow complete processes |
| **[Troubleshooting](Troubleshooting.md)** | Common issues and solutions | When things don't work |
| **[Intune Sync Guide](Intune-Sync-Guide.md)** | User group → device group sync | Specific Intune sync scenarios |
| **[CONTRIBUTING](../CONTRIBUTING.md)** | How to contribute | Want to add scripts or fixes |
| **[SECURITY](../SECURITY.md)** | Security policy | Report vulnerabilities |

---

## 🗂️ Script Index by Category

### ☁️ Cloud & Infrastructure (20 scripts)

#### API Management (2 scripts)
**Location:** `scripts/data/api/`
- Monitor-AzureAPIManagement.ps1 - Azure APIM health monitoring
- Test-APIHealth.ps1 - Universal API endpoint testing

#### Cloud Infrastructure (13 scripts)
**Location:** `scripts/cloud/`

**Azure** (`azure/core/`, `azure/compute/Azure-VirtualMachines/`, `azure/keyvault/Azure-KeyVault/`)
- Get-AzureResourceHealth.ps1 - Multi-subscription monitoring
- Monitor-AzureResources.ps1 - Resource health & cost analysis
- Monitor-AzureKeyVaults.ps1 - Key Vault monitoring
- Get-VMSecurityConfig.ps1 - VM security audit
- Get-VMBackupCompliance.ps1 - VM backup compliance
- Optimize-AzureVMs.ps1 - VM optimization

**AWS** (`aws/core/`)
- Get-AWSResourceInventory.ps1 - Multi-region inventory

#### Container Management (3 scripts)
**Location:** `scripts/cloud/containers/`
- Get-DockerHealthCheck.ps1 - Docker environment health
- Get-KubernetesHealthCheck.ps1 - K8s cluster monitoring
- Optimize-DockerCleanup.ps1 - Docker resource cleanup

#### Infrastructure as Code (2 scripts)
**Location:** `scripts/automation/iac/`
- Test-TerraformConfiguration.ps1 - Terraform validation & security
- Test-BicepTemplates.ps1 - Azure Bicep validation

---

### 🔄 DevOps & Development (8 scripts)

#### DevOps CI/CD (4 scripts)
**Location:** `scripts/automation/cicd/`
- Monitor-AzureDevOpsPipelines.ps1 - Azure DevOps monitoring
- Monitor-GitHubActions.ps1 - GitHub Actions workflows
- Monitor-GitLabCI.ps1 - GitLab CI/CD pipelines
- Analyze-BuildPerformance.ps1 - Build performance analysis

#### Database Management (4 scripts)
**Location:** `scripts/data/databases/`
- Get-SQLServerHealth.ps1 - SQL Server comprehensive monitoring
- Get-MySQLHealth.ps1 - MySQL server health
- Get-PostgreSQLHealth.ps1 - PostgreSQL monitoring
- Monitor-MongoDBHealth.ps1 - MongoDB health

---

### 💼 Microsoft 365 & Enterprise (50 scripts)

#### Microsoft 365 Cloud Services (23 scripts)
**Location:** `scripts/collaboration/microsoft365/`

**Exchange Online** (`exchange-online/`)
- Get-MailboxHealth.ps1 - Mailbox health monitoring
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

**Power Platform** (`power-platform/`)
- Set-PowerPlatformRegionalSettings.ps1 - Environment settings

**Defender for Office 365** (`defender-office365/`)
- Get-DefenderO365ThreatReport.ps1 - Threat reporting and monitoring

#### Intune Management (18+ scripts)
**Location:** `scripts/endpoints/intune/`

**Reporting** (`reporting/`)
- Get-DeviceComplianceReport.ps1 - Compliance status
- Get-BitLockerStatus.ps1 - Encryption audit
- Get-WindowsUpdateCompliance.ps1 - Update status

**Maintenance** (`maintenance/`)
- Find-StaleDevices.ps1 - Stale device detection
- Device cleanup utilities

**Deployment** (`deployment/`)
- Packaging and deployment tools

#### Email Services (1 script)
**Location:** `scripts/collaboration/email/exchange-server/`
- Get-ExchangeServerHealth.ps1 - Exchange Server monitoring

---

### 🔒 Security & Compliance (11 scripts)

#### Advanced Security (1 script)
**Location:** `scripts/security/hardening/`
- Invoke-SecurityComplianceScan.ps1 - Multi-framework scanning (CIS, NIST, PCI-DSS, HIPAA, SOC2, ISO27001)

#### Security & Compliance (10 scripts)
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
**Location:** `scripts/infrastructure/windows/`

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
**Location:** `scripts/infrastructure/web/iis/`
- Get-IISHealthCheck.ps1 - IIS health monitoring
- Get-IISLogAnalyzer.ps1 - Log analysis + threat detection
- Optimize-IISConfiguration.ps1 - Performance tuning
- Backup-IISConfiguration.ps1 - Configuration backup

#### Linux Server
**Location:** `scripts/infrastructure/linux/`
- Linux server administration scripts

---

### 🖱️ Device Management (60+ scripts)

#### Proactive Remediations (51 pairs = 102 scripts)
**Location:** `scripts/endpoints/devices/proactive-remediations/`

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

#### Winget Application Updates (35 apps)
**Location:** `scripts/endpoints/devices/winget/`

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
**Location:** `scripts/endpoints/devices/`
- `autopatch/` - Windows Update policy management (V1-V5)
- `bitlocker/` - BitLocker key backup scripts
- `uptime/` - Uptime monitoring
- `sccm/` - SCCM client removal
- `adobe-rum/` - Adobe Remote Update Manager
- `drivers/` - AMD driver block management

---

### 🔧 Monitoring & Operations (11 scripts)

#### Monitoring (7 scripts)
**Location:** `scripts/security/monitoring/` and `scripts/infrastructure/windows/monitoring/`
- Monitor-ServerHealth.ps1 - **Massively expanded! 🌈**
- Get-PerformanceTrends.ps1 - Performance trending
- System health checks

#### Network Management (3 scripts)
**Location:** `scripts/infrastructure/network/`
- Test-NetworkConnectivity.ps1 - Network diagnostics
- Network troubleshooting tools

#### Print Management (1 script)
**Location:** `scripts/infrastructure/print/`
- Print server monitoring

---

### 🛠️ Utilities & Other (7 scripts)

#### Utilities (5 scripts)
**Location:** `scripts/utilities/`
- System utility scripts

#### Virtualization (2 scripts)
**Location:** `scripts/infrastructure/virtualization/`
- Hyper-V management
- VMware vSphere/ESXi management

#### Azure Virtual Desktop
**Location:** `scripts/cloud/azure/avd/`
- Remove-SysprepBlockers.ps1 - **Performance improved! 🌈**

---

## 🎓 Learning Paths

### Beginner Path: "New to PowerShell automation"
1. Start with [Main README](../README.md) - understand the repository
2. Review [Script Examples](Script-Examples.md) - see how scripts work
3. Try a simple script like `Get-DeviceComplianceReport.ps1`
4. Review [Troubleshooting](Troubleshooting.md) if issues arise
5. Explore [Proactive Remediations](../scripts/endpoints/devices/proactive-remediations/README.md) for auto-fix scripts

### Intermediate Path: "I know PowerShell, want to deploy"
1. Review [Main README](../README.md) prerequisites section
2. Pick your focus area from [Script Index](#script-index-by-category)
3. Follow a complete workflow from [Workflows](Workflows.md)
4. Review [CHANGELOG](../CHANGELOG.md) for latest improvements
5. Consider [contributing](../CONTRIBUTING.md) improvements

### Advanced Path: "I want to customize and contribute"
1. Read [CONTRIBUTING](../CONTRIBUTING.md) guidelines
2. Check [CHANGELOG](../CHANGELOG.md) - see what's been improved (e.g., 🌈 Rainbow release)
3. Fork, customize, and submit pull requests
4. Help expand documentation and examples

---

## 📊 Repository Statistics

| Metric | Count |
|--------|-------|
| **Total Scripts** | 358 |
| **Script Categories** | 20 |
| **Proactive Remediations** | 51 pairs (102 scripts) |
| **Winget App Templates** | 35 |
| **Documentation Files** | 36 |
| **Latest Release** | [v4.3.0 "Zephyr - Quality & Enforcement"](../CHANGELOG.md) 🌈 |

---

## 🌈 Latest Updates (v4.3.0 "Zephyr")

**What's New:**
- 📐 **PSSA Policy Enforcement**: Comment-based help, style rules and ShouldProcess (-WhatIf) are now enforced in CI on every PR; 4,404 style findings fixed across 345 scripts; 56 state-changing functions retrofitted with `SupportsShouldProcess` guards
- 🎯 **Microsoft Learn Alignment**: 14 dead/misleading MS Learn links fixed; deprecated APIs migrated (`Get-WmiObject`→`Get-CimInstance`, `WebAdministration`→`IISAdministration`, `Send-MailMessage`→`SmtpClient`, SQLPS→`SqlServer`); winget migrated to `Microsoft.WinGet.Client` (81 files)
- 🛡️ **Endpoint & Remediation Fixes**: Driver block scripts write `DenyDeviceIDs` as the documented REG value; Autopatch `UseWUServer` read at the documented `\AU` path; SYSTEM-context fixes for TeamsCache/TempFiles/BrokenShortcuts/CertificateExpiry/StaleProfiles
- 🔐 **Security**: `LockoutBadCount`/`PasswordComplexity` read from documented secedit keys; Schannel registry TLS check; Windows LAPS detection; retired AzureAD module guidance replaced with Microsoft Graph
- ⚙️ **CI & Tooling**: Syntax gate now actually fails on parse errors; 43 scripts with latent parse errors repaired
- 🐛 **Notable Bug Fixes**: Exit-code masking in Install-TeamsAVD, unhandled Az null-refs, `-OutputPath` traversal validation, division-by-zero guard, quote-aware argument splitting

Resolves 122 open issues (#106-#245) via 18 PRs (#228-#245).

**See full details:** [CHANGELOG](../CHANGELOG.md)

---

## 💡 Tips for Navigation

### Finding Scripts
1. **By Function**: Use the [Quick Start Paths](#quick-start-paths) above
2. **By Category**: Browse the [Script Index](#script-index-by-category)
3. **By Name**: Check the category folders in `scripts/`

### Understanding Scripts
1. **See Examples**: [Script Examples](Script-Examples.md) has detailed usage
2. **Get Help**: All major scripts support `Get-Help .\ScriptName.ps1 -Detailed`
3. **Check Comments**: Every script has inline comments explaining logic

### Following Processes
1. **Complete Workflows**: [Workflows](Workflows.md) has end-to-end guides
2. **Common Issues**: [Troubleshooting](Troubleshooting.md) has solutions
3. **Specific Scenarios**: Check individual script documentation

---

## 🔗 External Links

- **GitHub Repository**: [Carme99/bug-free-umbrella](https://github.com/Carme99/bug-free-umbrella)
- **Issues & Feature Requests**: [GitHub Issues](https://github.com/Carme99/bug-free-umbrella/issues)
- **Changelog with Fun Codenames**: [CHANGELOG](../CHANGELOG.md) 🌂
- **Claude Code**: [github.com/anthropics/claude-code](https://github.com/anthropics/claude-code)

---

## 🌟 Featured Scripts

### 🆕 Recently Enhanced (v3.7.0 Shower 🌧️)
- **Comprehensive Documentation Enhancements**
  - 9 new Tier 3 documentation pages for advanced topics
  - Critical fixes for version inconsistencies and duplicate content
  - Standardized documentation formatting across all pages

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
| "How do I use this script?" | [Script Examples](Script-Examples.md) |
| "Something's not working" | [Troubleshooting](Troubleshooting.md) |
| "How do I deploy this?" | [Workflows](Workflows.md) |
| "What's new?" | [CHANGELOG](../CHANGELOG.md) |
| "I want to contribute" | [CONTRIBUTING](../CONTRIBUTING.md) |
| "I found a security issue" | [SECURITY](../SECURITY.md) |
| "General questions" | Check script comments or [GitHub Issues](https://github.com/Carme99/bug-free-umbrella/issues) |

---

## See Also

- [Getting Started](Getting-Started.md) - Step-by-step onboarding
- [Prerequisites](Prerequisites.md) - System requirements and setup
- [README](README.md) - Documentation home and complete overview
- [Workflows](Workflows.md) - End-to-end process guides
- [Troubleshooting](Troubleshooting.md) - Solve common problems
- [SUPPORT](../SUPPORT.md) - Get help
