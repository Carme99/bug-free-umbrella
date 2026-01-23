# 🌂 Bug-Free Umbrella

**Enterprise PowerShell automation for the modern IT professional.**

A curated collection of 260+ production-ready PowerShell scripts for Windows system administration, cloud infrastructure, DevOps automation, and Microsoft 365 management.

---

## ⚠️ Important Notice

**Most scripts in this repository have not been thoroughly tested in production environments.**

Always test in a non-production environment first. Review all scripts before execution and ensure you have proper backups.

---

## 📚 Documentation

### **[→ Visit the Wiki](../../wiki)** for comprehensive documentation

All detailed documentation is in the wiki:

- 📚 **[Command Recipes](docs/RECIPES.md)** - Quick cookbook with 80+ copy-paste commands
- 🚀 **[Getting Started](../../wiki/Getting-Started)** - Quick start guides for every role
- 📋 **[Script Catalog](../../wiki/Script-Catalog)** - Browse all 260+ scripts by category
- 💡 **[Script Examples](../../wiki/Script-Examples)** - Real-world usage examples
- 🔄 **[Workflows](../../wiki/Workflows)** - Complete step-by-step process guides
- 🔧 **[Troubleshooting](../../wiki/Troubleshooting)** - Common issues and solutions

---

## 🎯 What's Inside

This repository contains 260+ PowerShell scripts organized into 7 technology domains:

### 📁 Script Categories

- **☁️ [Cloud](scripts/cloud/)** - Azure, AWS, and container management
- **📱 [Endpoints](scripts/endpoints/)** - Intune and device management (18+ scripts, 14 remediation pairs, 40+ winget templates)
- **🖥️ [Infrastructure](scripts/infrastructure/)** - Windows/Linux servers, networking, virtualization (30+ scripts)
- **🔒 [Security](scripts/security/)** - Compliance scanning (CIS, NIST, PCI-DSS, HIPAA, SOC2, ISO27001)
- **⚙️ [Automation](scripts/automation/)** - CI/CD pipelines and Infrastructure as Code
- **👥 [Collaboration](scripts/collaboration/)** - Microsoft 365, Exchange, Teams, SharePoint
- **🗄️ [Data](scripts/data/)** - Database management and APIs

**[View Full Script Catalog →](../../wiki/Script-Catalog)**

---

## 🚀 Quick Start

1. **Choose your role** and follow the guide:
   - [Microsoft 365 / Intune Administrator](../../wiki/Getting-Started#microsoft-365--intune-administrator)
   - [Windows Server Administrator](../../wiki/Getting-Started#windows-server-administrator)
   - [DevOps / Cloud Engineer](../../wiki/Getting-Started#devops--cloud-engineer)
   - [IT Support / Help Desk](../../wiki/Getting-Started#it-support--help-desk)

2. **Install prerequisites:**
   - PowerShell 7+ (recommended)
   - Administrator privileges
   - Required modules: Az, Microsoft.Graph, AWS.Tools (as needed)

3. **Run your first script:**
   ```powershell
   # Check Intune device compliance
   cd scripts/endpoints/intune/reporting
   .\Get-DeviceComplianceReport.ps1
   ```

**[See detailed setup instructions →](../../wiki/Getting-Started)**

---

## 📊 Repository Stats

- **260+** PowerShell scripts
- **7** technology domains
- **14** proactive remediation pairs
- **40+** winget application templates
- **Comprehensive** wiki documentation

---

## 🤝 Contributing

Contributions are welcome! This is a solo project maintained with Claude Code. See the [Contributing Guide](CONTRIBUTING.md) for details.

---

## 📖 Additional Documentation

| Resource | Description |
|----------|-------------|
| **[CHANGELOG.md](CHANGELOG.md)** | Complete version history |
| **[CONTRIBUTING.md](CONTRIBUTING.md)** | How to contribute |
| **[SECURITY.md](SECURITY.md)** | Security policy and vulnerability reporting |
| **[SUPPORT.md](SUPPORT.md)** | How to get help |
| **[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)** | Community standards |
| **[GOVERNANCE.md](GOVERNANCE.md)** | Project governance model |

---

## 🔒 Security

Found a security vulnerability? Please review our [Security Policy](SECURITY.md) for reporting instructions.

---

## 🤖 About

Bug-Free Umbrella is a solo project created and maintained by one developer using [Claude Code](https://github.com/anthropics/claude-code), Anthropic's official CLI for Claude AI. These scripts are personal automation tools shared publicly to help other IT professionals.

**License:** Apache License 2.0

---

**[Get Started →](../../wiki/Getting-Started)** | **[Browse Scripts →](../../wiki/Script-Catalog)** | **[View Examples →](../../wiki/Script-Examples)**
