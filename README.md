# 🌂 Bug-Free Umbrella

**Enterprise PowerShell automation for the modern IT professional.**

A curated collection of 260+ production-ready PowerShell scripts for Windows system administration, cloud infrastructure, DevOps automation, and Microsoft 365 management.

---

## ⚠️ Important Notice

**Most scripts in this repository have not been thoroughly tested in production environments.**

Always test in a non-production environment first. Review all scripts before execution and ensure you have proper backups.

---

## 📚 Documentation

### **[→ Visit the Wiki](../../wiki)**

All documentation has moved to our comprehensive, searchable wiki:

- 🚀 **[Getting Started](../../wiki/Getting-Started)** - Quick start guides for every role
- 📋 **[Script Catalog](../../wiki/Script-Catalog)** - Browse all 260+ scripts by category
- 💡 **[Script Examples](../../wiki/Script-Examples)** - Real-world usage examples
- 🔄 **[Workflows](../../wiki/Workflows)** - Complete step-by-step process guides
- 🔧 **[Troubleshooting](../../wiki/Troubleshooting)** - Common issues and solutions

---

## 🎯 What's Inside

This repository contains scripts organized into **20 categories**:

### Cloud & Infrastructure
- ☁️ Azure & AWS resource management
- 🐳 Docker & Kubernetes monitoring
- 🌐 API management & health checks
- ⚙️ Infrastructure as Code (Terraform, Bicep)
- 💻 Virtualization (Hyper-V, VMware)

### DevOps & Development
- 🔄 CI/CD pipeline monitoring (Azure DevOps, GitHub Actions, GitLab)
- 🗄️ Database management (SQL Server, MySQL, PostgreSQL, MongoDB)

### Microsoft 365 & Enterprise
- 📧 Exchange Online & Teams administration
- 📁 SharePoint & OneDrive management
- 🔐 Azure AD / Entra ID tools
- 🛡️ Microsoft Defender & Compliance Center

### Device & Endpoint Management
- 📱 **Intune Management** - 18+ comprehensive scripts
- 🔧 **Proactive Remediations** - 14 auto-fix script pairs
- 📦 **Winget Updates** - 40+ application auto-update templates

### Server & Infrastructure
- 🖥️ Windows Server administration (30+ scripts)
- 🌐 IIS web server management
- 🔗 Network diagnostics & troubleshooting
- 🖨️ Print server management

### Security & Compliance
- 🔒 Multi-framework compliance scanning (CIS, NIST, PCI-DSS, HIPAA, SOC2, ISO27001)
- 🛡️ Security auditing & baseline verification
- 📊 Compliance reporting

**[View Full Script Catalog →](../../wiki/Script-Catalog)**

---

## 🚀 Quick Start

### 1. Choose Your Path

**Microsoft 365 / Intune Administrator?**
- Start here: [Intune Quick Start](../../wiki/Getting-Started#microsoft-365--intune-administrator)

**Windows Server Administrator?**
- Start here: [Server Quick Start](../../wiki/Getting-Started#windows-server-administrator)

**DevOps / Cloud Engineer?**
- Start here: [DevOps Quick Start](../../wiki/Getting-Started#devops--cloud-engineer)

**IT Support / Help Desk?**
- Start here: [Support Quick Start](../../wiki/Getting-Started#it-support--help-desk)

### 2. Prerequisites

Before using these scripts:

- **PowerShell 5.1+** (PowerShell 7+ recommended)
- **Administrator privileges** (most scripts require elevation)
- **Appropriate modules** installed (Az, Microsoft.Graph, AWS.Tools - depending on script category)

See the [Getting Started Guide](../../wiki/Getting-Started) for detailed setup instructions.

### 3. Run Your First Script

```powershell
# Example: Check Intune device compliance
cd scripts/intune
.\Get-DeviceComplianceReport.ps1

# Example: Monitor server health
cd scripts/monitoring
.\Monitor-ServerHealth.ps1

# Example: Check Azure resources
cd scripts/cloud-infrastructure/azure
.\Monitor-AzureResources.ps1
```

**[See More Examples →](../../wiki/Script-Examples)**

---

## 💡 Common Tasks

| I Want To... | Go Here |
|--------------|---------|
| **Monitor my Azure DevOps pipelines** | [DevOps Scripts](../../wiki/Script-Catalog#devops--cicd) |
| **Check Intune device compliance** | [Intune Scripts](../../wiki/Script-Catalog#intune-management) |
| **Auto-update applications** | [Winget Templates](../../wiki/Script-Catalog#winget-updates) |
| **Fix stuck Windows Updates** | [Server Scripts](../../wiki/Script-Catalog#server-management) |
| **Run security compliance scans** | [Security Scripts](../../wiki/Script-Catalog#advanced-security) |
| **Monitor IIS web servers** | [Web Services Scripts](../../wiki/Script-Catalog#web-services) |
| **Manage M365 mailboxes** | [M365 Scripts](../../wiki/Script-Catalog#microsoft-365-cloud-services) |

**[View All Use Cases →](../../wiki/Script-Catalog)**

---

## 📂 Repository Structure

> **🌪️ v3.0.0 "Hurricane"**: Technology-based hierarchy for better navigation

```
bug-free-umbrella/
├── 📂 scripts/                        # All PowerShell scripts in tech-based hierarchy
│   │
│   ├── 📂 cloud/                      # ☁️ Cloud Platforms & Services
│   │   ├── 📂 azure/                 # Azure resource management
│   │   │   ├── 📂 avd/              # Azure Virtual Desktop
│   │   │   ├── 📂 compute/          # Virtual machines
│   │   │   ├── 📂 keyvault/         # Key Vault management
│   │   │   └── 📂 core/             # General Azure resources
│   │   ├── 📂 aws/                   # AWS resource management
│   │   │   └── 📂 core/             # AWS core services
│   │   └── 📂 containers/            # Docker & Kubernetes
│   │
│   ├── 📂 endpoints/                  # 📱 Endpoint & Device Management
│   │   ├── 📂 intune/                # Microsoft Intune (18+ scripts)
│   │   │   ├── 📂 deployment/       # App deployment
│   │   │   ├── 📂 maintenance/      # Device maintenance
│   │   │   └── 📂 reporting/        # Compliance reporting
│   │   └── 📂 devices/               # Device management
│   │       ├── 📂 proactive-remediations/  # Auto-fix scripts (14 pairs)
│   │       ├── 📂 winget/           # Windows Package Manager (40+ apps)
│   │       ├── 📂 autopatch/        # Windows Update automation
│   │       ├── 📂 bitlocker/        # BitLocker management
│   │       └── 📂 drivers/          # Driver management
│   │
│   ├── 📂 infrastructure/             # 🖥️ On-Premises & Hybrid
│   │   ├── 📂 windows/               # Windows Server (30+ scripts)
│   │   │   ├── 📂 active-directory/ # AD management
│   │   │   ├── 📂 group-policy/     # GPO configuration
│   │   │   ├── 📂 monitoring/       # Server monitoring
│   │   │   └── 📂 ...               # 6 more categories
│   │   ├── 📂 linux/                 # Linux administration
│   │   ├── 📂 network/               # Network management
│   │   ├── 📂 virtualization/        # Hyper-V & VMware
│   │   ├── 📂 web/                   # IIS web servers
│   │   └── 📂 print/                 # Print servers
│   │
│   ├── 📂 security/                   # 🔒 Security & Compliance
│   │   ├── 📂 compliance/            # Multi-framework compliance
│   │   │   └── 📂 frameworks/       # CIS, NIST, PCI-DSS, HIPAA, SOC2, ISO27001
│   │   ├── 📂 hardening/             # Security hardening
│   │   └── 📂 monitoring/            # Security monitoring
│   │
│   ├── 📂 automation/                 # ⚙️ DevOps & Automation
│   │   ├── 📂 cicd/                  # CI/CD pipelines
│   │   └── 📂 iac/                   # Infrastructure as Code
│   │
│   ├── 📂 collaboration/              # 👥 Microsoft 365 & Communication
│   │   ├── 📂 microsoft365/          # M365 services
│   │   │   ├── 📂 azure-ad/         # Azure AD/Entra ID
│   │   │   ├── 📂 exchange-online/  # Exchange Online
│   │   │   ├── 📂 teams/            # Microsoft Teams
│   │   │   └── 📂 ...               # SharePoint, Power Platform
│   │   └── 📂 email/                 # Exchange Server
│   │
│   ├── 📂 data/                       # 🗄️ Data Management
│   │   ├── 📂 databases/             # SQL, MySQL, PostgreSQL, MongoDB
│   │   └── 📂 api/                   # API management
│   │
│   ├── 📂 utilities/                  # 🔧 General Utilities
│   └── 📂 .catalog/                   # 📋 Metadata & Compatibility
│
├── 📂 examples/                       # 💡 Practical Workflow Examples
│   ├── 📂 onboarding/                # New employee/device setup
│   ├── 📂 maintenance/               # Maintenance routines
│   ├── 📂 compliance/                # Compliance audits
│   └── 📂 ...                        # More examples
│
├── 📂 Tests/                          # Test files and validation
├── 📂 templates/                      # Script templates
├── 📂 wiki/                           # Wiki documentation
├── 📂 docs/                           # ⚠️ Legacy docs (see wiki)
│
├── 📂 .github/                        # GitHub configuration
│   ├── 📂 workflows/                 # CI/CD automation
│   └── 📂 ISSUE_TEMPLATE/            # Issue templates
│
├── 📄 README.md                       # This file
├── 📄 QUICK_START.md                  # Role-based quick start
├── 📄 CHANGELOG.md                    # Version history (v3.0.0!)
├── 📄 CONTRIBUTING.md                 # Contribution guidelines
├── 📄 SECURITY.md                     # Security policy
└── 📄 LICENSE                         # Apache License 2.0
```

### Quick Navigation by Domain

| Domain | Description | Top Categories |
|--------|-------------|----------------|
| **[☁️ Cloud](scripts/cloud/)** | Cloud platforms & services | Azure, AWS, Containers |
| **[📱 Endpoints](scripts/endpoints/)** | Device & endpoint management | Intune, Devices, Winget |
| **[🖥️ Infrastructure](scripts/infrastructure/)** | On-premises systems | Windows, Linux, Network |
| **[🔒 Security](scripts/security/)** | Security & compliance | Compliance, Hardening |
| **[⚙️ Automation](scripts/automation/)** | DevOps & automation | CI/CD, IaC |
| **[👥 Collaboration](scripts/collaboration/)** | M365 & communication | Microsoft 365, Email |
| **[🗄️ Data](scripts/data/)** | Data management | Databases, APIs |
| **[🔧 Utilities](scripts/utilities/)** | General utilities | Helper scripts |

### Migration Notes

> **Breaking Change (v3.0.0)**: Scripts reorganized from 20 flat categories into 7 technology domains.
> See [CHANGELOG.md](CHANGELOG.md#300) for complete migration guide.

**Quick Links:**
- **[🚀 QUICK_START.md](QUICK_START.md)** - Find scripts by role or task
- **[📚 Wiki](../../wiki)** - Comprehensive documentation
- **[💡 Examples](examples/)** - Real-world workflow examples
- **[📋 Compatibility Matrix](scripts/.catalog/COMPATIBILITY.md)** - Platform compatibility

---

## 📖 Documentation

| Resource | Description |
|----------|-------------|
| **[Wiki Home](../../wiki)** | Main documentation hub |
| **[Getting Started](../../wiki/Getting-Started)** | Setup and first steps |
| **[Script Catalog](../../wiki/Script-Catalog)** | All 260+ scripts indexed |
| **[Script Examples](../../wiki/Script-Examples)** | Real-world usage examples |
| **[Workflows](../../wiki/Workflows)** | Complete process guides |
| **[Troubleshooting](../../wiki/Troubleshooting)** | Common issues & solutions |
| **[Changelog](CHANGELOG.md)** | Version history |

---

## 🤝 Contributing

Contributions are welcome! This is a solo project maintained with Claude Code. See the [Contributing Guide](CONTRIBUTING.md) if you'd like to suggest improvements or report issues.

---

## 📊 Stats

- **260+** PowerShell scripts
- **7** technology domains (formerly 20 flat categories)
- **14** proactive remediation pairs
- **40+** winget application templates
- **Comprehensive** wiki documentation
- **v3.0.0** - Complete restructure with technology-based hierarchy

---

## 🔒 Security

Found a security vulnerability? Please review our [Security Policy](SECURITY.md) for reporting instructions.

---

## 🤖 About

Bug-Free Umbrella is a solo project created and maintained by one developer using [Claude Code](https://github.com/anthropics/claude-code), Anthropic's official CLI for Claude AI. These scripts are personal automation tools shared publicly to help other IT professionals.

**License:** Apache License 2.0

---

**[Get Started →](../../wiki/Getting-Started)** | **[Browse Scripts →](../../wiki/Script-Catalog)** | **[View Examples →](../../wiki/Script-Examples)**
