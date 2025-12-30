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

```
bug-free-umbrella/
├── 📂 scripts/                        # All PowerShell scripts organized by category (20 total)
│   │
│   ├── 📂 advanced-security/          # Security hardening and configuration scripts
│   ├── 📂 api-management/             # API health checks and monitoring
│   ├── 📂 cloud-infrastructure/       # Azure & AWS resource management
│   ├── 📂 container-management/       # Docker & Kubernetes tools
│   ├── 📂 database/                   # SQL Server, MySQL, PostgreSQL, MongoDB
│   ├── 📂 device-management/          # General device configuration & inventory
│   ├── 📂 devops-cicd/                # Pipeline monitoring (Azure DevOps, GitHub Actions, GitLab)
│   ├── 📂 email-services/             # Exchange Online & email system management
│   ├── 📂 infrastructure-as-code/     # Terraform, Bicep, ARM templates
│   ├── 📂 intune/                     # Microsoft Intune endpoint management (18+ scripts)
│   │   ├── 📂 deployment/            # Application deployment scripts
│   │   ├── 📂 maintenance/           # Device maintenance and cleanup
│   │   ├── 📂 reporting/             # Compliance and status reporting
│   │   ├── 📂 ProactiveRemediations/ # Auto-detect and fix scripts (14 pairs)
│   │   └── 📂 WingetUpdates/         # Application auto-update templates (40+)
│   ├── 📂 linux-server/               # Linux system administration
│   ├── 📂 m365/                       # Microsoft 365 services (Teams, SharePoint, OneDrive)
│   ├── 📂 monitoring/                 # System monitoring and health checks
│   ├── 📂 network-management/         # Network diagnostics and configuration
│   ├── 📂 print-management/           # Print server administration
│   ├── 📂 security-compliance/        # Multi-framework compliance (CIS, NIST, PCI-DSS, HIPAA, SOC2, ISO27001)
│   ├── 📂 server/                     # Windows Server administration (30+ scripts)
│   ├── 📂 utilities/                  # Helper scripts and tools
│   ├── 📂 virtualization/             # Hyper-V & VMware management
│   └── 📂 web-services/               # IIS web server management
│
├── 📂 examples/                       # ✨ NEW: Practical workflow examples
│   ├── 📂 onboarding/                # New employee/device setup workflows
│   ├── 📂 maintenance/               # Daily, weekly, monthly maintenance routines
│   ├── 📂 incident-response/         # Troubleshooting and security scenarios
│   ├── 📂 compliance/                # Compliance audit workflows
│   └── 📂 automation/                # Scheduled task and CI/CD examples
│
├── 📂 AzureVirtualDesktop/            # Azure Virtual Desktop specific scripts
├── 📂 Tests/                          # Test files and validation scripts
├── 📂 templates/                      # Script templates for new development
├── 📂 wiki/                           # Wiki documentation (deployed separately)
├── 📂 docs/                           # ⚠️ Legacy documentation (see wiki for latest)
│
├── 📂 .github/                        # GitHub configuration
│   └── 📂 workflows/                 # CI/CD automation workflows
│
├── 📄 README.md                       # This file - repository overview
├── 📄 QUICK_START.md                  # ✨ NEW: Role-based quick start guide
├── 📄 CHANGELOG.md                    # Detailed version history with weather-themed releases
├── 📄 CONTRIBUTING.md                 # Contribution guidelines
├── 📄 SECURITY.md                     # Security policy and vulnerability reporting
├── 📄 SCRIPT_ANALYSIS_REPORT.md       # Script quality analysis
└── 📄 LICENSE                         # Apache License 2.0
```

### Quick Navigation

- **[🚀 QUICK_START.md](QUICK_START.md)** - Find scripts by role or task
- **[📚 Wiki](../../wiki)** - Comprehensive documentation
- **[💡 Examples](examples/)** - Real-world workflow examples
- **[📋 Script Catalog](../../wiki/Script-Catalog)** - All 260+ scripts indexed

**[See Full Repository Structure →](../../wiki/Script-Catalog)**

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
- **20** categories
- **14** proactive remediation pairs
- **40+** winget application templates
- **Comprehensive** wiki documentation

---

## 🔒 Security

Found a security vulnerability? Please review our [Security Policy](SECURITY.md) for reporting instructions.

---

## 🤖 About

Bug-Free Umbrella is a solo project created and maintained by one developer using [Claude Code](https://github.com/anthropics/claude-code), Anthropic's official CLI for Claude AI. These scripts are personal automation tools shared publicly to help other IT professionals.

**License:** Apache License 2.0

---

**[Get Started →](../../wiki/Getting-Started)** | **[Browse Scripts →](../../wiki/Script-Catalog)** | **[View Examples →](../../wiki/Script-Examples)**
