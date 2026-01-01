# 🌂 Bug-Free Umbrella Wiki

Welcome to the comprehensive documentation for Bug-Free Umbrella - a collection of 260+ PowerShell scripts for enterprise IT management!

> **Latest Release:** [v3.0.1 "Drizzle" ☔](../CHANGELOG.md#301---2025-12-31--drizzle---bug-fix-release) - Critical bug fixes for Test-CISBenchmark.ps1!
>
> 📋 **[View Full Changelog →](../CHANGELOG.md)** | 📦 **[GitHub Releases](https://github.com/Carme99/bug-free-umbrella/releases)**

---

## 🚀 Quick Start

**New here?** Start with these pages:
- 📖 **[Getting Started](Getting-Started)** ✅ - Prerequisites, installation, first steps
- 📍 **[Script Catalog](Script-Catalog)** ✅ - Browse all 260+ scripts by category
- 💡 **[Script Examples](Script-Examples)** ✅ - See detailed usage examples

**Looking for something specific?**
- 🔍 Use the **search bar** above to find scripts and topics
- 📑 Check the **sidebar** for quick navigation to available pages
- 🗺️ Browse the **[Script Catalog](Script-Catalog)** or **[repository folders](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts)**

---

## 🌟 Available Documentation

| Page | Description | Status |
|------|-------------|--------|
| **[Getting Started](Getting-Started)** | Prerequisites, installation, first steps | ✅ |
| **[Script Catalog](Script-Catalog)** | Browse all 260+ scripts by directory | ✅ |
| **[Script Examples](Script-Examples)** | Detailed usage examples | ✅ |
| **[Workflows](Workflows)** | Step-by-step guides for complete processes | ✅ |
| **[Troubleshooting](Troubleshooting)** | Common issues and solutions | ✅ |
| **[Azure Virtual Desktop](Azure-Virtual-Desktop)** | AVD deployment and image building | ✅ |
| **[Azure Compute Gallery Image Builder](Azure-Compute-Gallery-Image-Builder)** | Interactive ACG workflow | ✅ |
| **[Intune Sync Guide](Intune-Sync-Guide)** | Sync status troubleshooting | ✅ |

---

## 📊 Repository Stats

| Metric | Count |
|--------|-------|
| **Total Scripts** | 260+ |
| **Categories** | 20 |
| **Proactive Remediations** | 14 pairs (28 scripts) |
| **Winget App Templates** | 40+ applications |
| **Latest Release** | v3.0.1 "Drizzle" ☔ |
| **Documentation Pages** | Comprehensive wiki! |

---

## 🗂️ Browse by Category

> 📍 **Currently Available:** [Script Catalog](Script-Catalog) - Browse all 260+ scripts organized by directory structure
>
> 🚧 **Detailed category pages coming soon!** For now, explore scripts via the catalog or repository folders.

### ☁️ Cloud & Infrastructure 🚧
- **Cloud Infrastructure (Azure/AWS)** - 15+ scripts for Azure and AWS management
- **[Azure Virtual Desktop](Azure-Virtual-Desktop)** ✅ - AVD deployment and image building
  - **[Azure Compute Gallery Image Builder](Azure-Compute-Gallery-Image-Builder)** ✅ - Interactive ACG workflow
- **Container Management** - Docker & Kubernetes health checks
- **API Management** - Azure APIM and API health monitoring
- **Infrastructure as Code** - Terraform & Bicep validation
- **Virtualization** - Hyper-V & VMware management

### 🔄 DevOps & Development 🚧
- **DevOps & CI/CD** - Pipeline monitoring (Azure DevOps, GitHub, GitLab)
- **Database Management** - SQL Server, MySQL, PostgreSQL, MongoDB

### 💼 Microsoft 365 & Enterprise 🚧
- **Microsoft 365 Cloud Services** - 19 scripts for M365 management
- **Intune Management** - Comprehensive Intune toolkit (18+ scripts)
  - **[Intune Sync Guide](Intune-Sync-Guide)** ✅ - Sync status troubleshooting
- **Email Services** - Exchange Server health and management

### 🔒 Security & Compliance 🚧
- **Advanced Security** - Multi-framework compliance scanning
- **Security & Compliance** - 12 scripts for security auditing (includes Test-CISBenchmark.ps1)

### 🖥️ Server & Infrastructure 🚧
- **Server Management** - 30+ Windows Server administration scripts
- **Web Services** - IIS health monitoring and optimization
- **Linux Server** - Linux server management

### 🔧 Monitoring & Operations 🚧
- **Monitoring** - System health checks and performance
- **Network Management** - Network diagnostics and troubleshooting
- **Print Management** - Print server monitoring

### 🖱️ Device Management 🚧
- **Proactive Remediations** - 14 pairs of auto-fix scripts
- **Winget Updates** - 40+ application auto-update templates
- **Device Management Tools** - Autopatch, BitLocker, SCCM removal

---

## 📚 Documentation Sections

### ✅ Available Now
- **[Getting Started](Getting-Started)** - Quick start guide for your first scripts
- **[Script Catalog](Script-Catalog)** - Complete index of all 260+ scripts
- **[Script Examples](Script-Examples)** - Detailed usage examples
- **[Workflows](Workflows)** - End-to-end process guides
- **[Troubleshooting](Troubleshooting)** - Common issues and solutions
- **[Azure Virtual Desktop](Azure-Virtual-Desktop)** - AVD deployment documentation
- **[Azure Compute Gallery Image Builder](Azure-Compute-Gallery-Image-Builder)** - Interactive ACG workflow
- **[Intune Sync Guide](Intune-Sync-Guide)** - Sync status troubleshooting

### 🚧 Coming Soon
Additional documentation pages are planned for future releases:
- Installation guides and prerequisites
- Category-specific pages (M365, Security, DevOps, etc.)
- Advanced workflow guides
- FAQ and performance tips
- Best practices and architecture guides

### 📋 Project Information
- **[📋 Full Changelog (CHANGELOG.md)](../CHANGELOG.md)** - Complete version history
  - [v3.0.1 "Drizzle" ☔](../CHANGELOG.md#301---2025-12-31--drizzle---bug-fix-release) - Latest release
  - [v3.0.0 "Hurricane" 🌪️](../CHANGELOG.md#300---2025-12-30--hurricane---repository-restructure)
  - [v2.2.0 "Shower" 🌧️](../CHANGELOG.md#220---2025-12-28--shower---navigation--usability-improvements)
- **[Contributing](../CONTRIBUTING.md)** - How to contribute to the project
- **[Security Policy](../SECURITY.md)** - Reporting security vulnerabilities
- **[GitHub Repository](https://github.com/Carme99/bug-free-umbrella)** - Source code and issues

---

## ☔ What's New in v3.0.1 "Drizzle"

The latest release focuses on **critical bug fixes** following the v3.0.0 restructure:

✨ **Highlights:**
- 🔧 **CRITICAL FIX:** Test-CISBenchmark.ps1 v2.0.0 - Completely rewritten
  - Replaced broken `Get-LocalGroupPolicy` cmdlet with working `secedit.exe`
  - Expanded from 3 to 15+ CIS controls tested
  - Added password policies, account lockout, and audit policies
  - Enhanced HTML reporting with detailed control results
- 📚 **Enhanced Testing:** Now supports Level 1/Level 2 CIS benchmarks
- 🛡️ **Better Compliance:** Production-ready security compliance testing
- 📖 **Documentation Updates:** CHANGELOG.md and Script-Catalog.md updated

**[Read Full Changelog →](../CHANGELOG.md#301---2025-12-31--drizzle---bug-fix-release)**

### Recent Major Releases
- ☔ **[v3.0.1 "Drizzle"](../CHANGELOG.md#301---2025-12-31--drizzle---bug-fix-release)** (2025-12-31) - Bug fixes
- 🌪️ **[v3.0.0 "Hurricane"](../CHANGELOG.md#300---2025-12-30--hurricane---repository-restructure)** (2025-12-30) - Repository restructure
- 🌧️ **[v2.2.0 "Shower"](../CHANGELOG.md#220---2025-12-28--shower---navigation--usability-improvements)** (2025-12-28) - Navigation improvements

---

## 🎯 I Want To...

Quick links to accomplish specific tasks:

| Task | Where to Find It |
|------|------------------|
| **Find a specific script** | Browse the **[Script Catalog](Script-Catalog)** or search the **[repository](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts)** |
| **See script examples** | Check **[Script Examples](Script-Examples)** page |
| **Learn basic usage** | Start with **[Getting Started](Getting-Started)** |
| **Follow a complete workflow** | Visit **[Workflows](Workflows)** page |
| **Fix an issue** | Check **[Troubleshooting](Troubleshooting)** |
| **Deploy Azure Virtual Desktop** | See **[Azure Virtual Desktop](Azure-Virtual-Desktop)** guide |
| **Build ACG images** | Follow **[ACG Image Builder](Azure-Compute-Gallery-Image-Builder)** workflow |
| **Check what's new** | Read the **[Changelog](../CHANGELOG.md)** |

---

## 💡 Tips for Using This Wiki

### Navigation
- 📑 **Use the sidebar** for quick access to available documentation pages
- 🔍 **Use search** (top) to find specific scripts, topics, or keywords
- 📍 **Browse the catalog** - The [Script Catalog](Script-Catalog) is your main navigation tool
- 🏠 **Return here** anytime by clicking "Home" in the sidebar

### Finding Scripts
1. **[Script Catalog](Script-Catalog)** - Browse all 260+ scripts organized by directory structure
2. **[Repository Folders](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts)** - Navigate the actual script directories
3. **Search** - Use GitHub's search or the wiki search to find by name or keyword

### Learning Path
**Beginner?** Follow this path:
1. **[Getting Started](Getting-Started)** - Set up your environment and learn basics
2. **[Script Examples](Script-Examples)** - See how scripts work in practice
3. **[Workflows](Workflows)** - Follow complete end-to-end processes

**Intermediate?** Try this:
1. **[Script Catalog](Script-Catalog)** - Browse all available scripts
2. **[Workflows](Workflows)** - Deploy complex scenarios
3. **[Azure Virtual Desktop](Azure-Virtual-Desktop)** - Advanced deployment guides

**Advanced?** Check out:
1. **[Changelog](../CHANGELOG.md)** - Stay current with latest changes
2. **[Contributing](../CONTRIBUTING.md)** - Help improve the repository
3. **Repository code** - Explore the scripts directly

---

## 🆘 Need Help?

| Question Type | Where to Go |
|---------------|-------------|
| "How do I use this script?" | [Script Examples](Script-Examples) ✅ |
| "Something's not working" | [Troubleshooting](Troubleshooting) ✅ |
| "How do I set this up?" | [Getting Started](Getting-Started) ✅ |
| "What's new?" | [📋 Changelog](../CHANGELOG.md) ✅ |
| "I found a bug" | [GitHub Issues](https://github.com/Carme99/bug-free-umbrella/issues) |
| "I want to contribute" | [Contributing Guide](../CONTRIBUTING.md) |
| "Security issue" | [Security Policy](../SECURITY.md) |

---

## 🔗 External Links

- **[GitHub Repository](https://github.com/Carme99/bug-free-umbrella)** - Main code repository
- **[Issues & Requests](https://github.com/Carme99/bug-free-umbrella/issues)** - Report bugs, request features
- **[Pull Requests](https://github.com/Carme99/bug-free-umbrella/pulls)** - Active development
- **[Releases](https://github.com/Carme99/bug-free-umbrella/releases)** - Download releases
- **[Claude Code](https://github.com/anthropics/claude-code)** - Tool used to create these scripts

---

## 🤖 About This Project

Bug-Free Umbrella is a comprehensive collection of PowerShell scripts for enterprise IT management, created and maintained by a solo developer using [Claude Code](https://github.com/anthropics/claude-code).

**Licensed under:** Apache License 2.0

**Maintained by:** Solo developer with Claude Code

**Created with:** [Claude Code](https://github.com/anthropics/claude-code) - Anthropic's official CLI for Claude AI

---

**Last Updated:** 2025-12-31

**Wiki Version:** 1.1.0

**Corresponds to Release:** v3.0.1 "Drizzle" ☔

**[📋 View Full Changelog →](../CHANGELOG.md)**
