# 🌂 Bug-Free Umbrella

> **Because IT shouldn't rain on your parade.**

Your personal collection of **358 battle-tested PowerShell scripts** for when you need to automate *everything* in your enterprise environment.

<div align="center">

[![PowerShell](https://img.shields.io/badge/PowerShell-7.0+-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Windows](https://img.shields.io/badge/Windows-Server_2016+-0078D6?style=for-the-badge&logo=windows&logoColor=white)](https://www.microsoft.com/windows-server)
[![Linux](https://img.shields.io/badge/Linux-Compatible-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://github.com/PowerShell/PowerShell)
[![macOS](https://img.shields.io/badge/macOS-Compatible-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/PowerShell/PowerShell)

[![License](https://img.shields.io/github/license/Carme99/bug-free-umbrella?style=for-the-badge)](LICENSE)
[![Stars](https://img.shields.io/github/stars/Carme99/bug-free-umbrella?style=for-the-badge)](https://github.com/Carme99/bug-free-umbrella/stargazers)
[![Issues](https://img.shields.io/github/issues/Carme99/bug-free-umbrella?style=for-the-badge)](https://github.com/Carme99/bug-free-umbrella/issues)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen?style=for-the-badge)](CONTRIBUTING.md)

[![Scripts](https://img.shields.io/badge/Scripts-358-FF6B6B?style=for-the-badge&logo=files&logoColor=white)](docs/Script-Catalog.md)
[![Docs](https://img.shields.io/badge/📚_Full_Documentation-docs%2F-4A9EFF?style=for-the-badge)](docs/README.md)
[![Claude Code](https://img.shields.io/badge/Built_with-Claude_Code-8B5CF6?style=for-the-badge&logo=anthropic&logoColor=white)](https://github.com/anthropics/claude-code)
[![Last Commit](https://img.shields.io/github/last-commit/Carme99/bug-free-umbrella?style=for-the-badge)](https://github.com/Carme99/bug-free-umbrella/commits/main)

---

### 📚 **[→ Read the Full Documentation](docs/README.md)** ⭐

**[🚀 Quick Start](docs/Getting-Started.md)** • **[📋 Script Catalog](docs/Script-Catalog.md)** • **[💡 Examples](docs/Script-Examples.md)** • **[🔧 Troubleshooting](docs/Troubleshooting.md)**

</div>

---

## 📑 Quick Navigation

**Jump to:** [What's This?](#-whats-this-all-about) • [Features](#-quick-highlights) • [Get Started](#-get-started-in-60-seconds) • [Scripts](#-whats-inside-the-toolbox) • [Popular Scripts](#-popular-scripts-aka-the-fan-favorites) • [Documentation](#-documentation) • [Contributing](#-join-the-party)

---

## 🎯 What's This All About?

Ever find yourself thinking *"there's got to be a script for this"*? Well, now there is. This repo is what happens when you combine:

- 🔧 **Real IT problems** that need solving
- 🤖 **AI-assisted development** (built with Claude Code)
- ☕ **Way too much coffee** and spare time
- 🌂 **A commitment to sharing** instead of hoarding scripts

**The result?** A treasure trove of PowerShell automation covering everything from Intune device management to multi-cloud infrastructure, security compliance, and that one script that fixes the thing Windows Update always breaks.

---

## ⚡ Quick Highlights

| 🎨 Feature | 📊 What You Get |
|-----------|----------------|
| **📱 Intune Management** | 20+ scripts to wrangle your endpoints into submission |
| **🔧 Proactive Remediations** | 51 detect/fix pairs that run before users notice issues |
| **📦 Winget Updates** | 16 app auto-update pairs (set it and forget it) |
| **🔒 Security & Compliance** | Multi-framework scanning (CIS, NIST, PCI-DSS, HIPAA, SOC2, ISO27001) |
| **☁️ Cloud Automation** | Azure, AWS, and container management scripts |
| **🖥️ Server Management** | 30+ scripts for Windows/Linux servers |
| **👥 M365 Everything** | Exchange, Teams, SharePoint, and more |

---

## 🚀 Get Started in 60 Seconds

```powershell
# Clone the repo
git clone https://github.com/Carme99/bug-free-umbrella.git
cd bug-free-umbrella

# Pick a script that solves your problem
cd scripts/endpoints/intune/reporting

# Check the help (always read before you run!)
Get-Help .\Get-DeviceComplianceReport.ps1 -Detailed

# Run it
.\Get-DeviceComplianceReport.ps1
```

**Don't know where to start?** Check out our [**Command Recipes**](docs/RECIPES.md) - 80+ copy-paste commands organized by task. It's like Stack Overflow, but it actually works in your environment.

**[→ Full getting started guide](docs/Getting-Started.md)**

---

## 📁 What's Inside the Toolbox

This isn't just a random pile of scripts. Everything's organized into **8 technology domains** so you can actually find what you need:

```
🌂 bug-free-umbrella/
├── 📱 endpoints/       # Intune, Winget, remediations - keep users happy
├── 🖥️ infrastructure/  # Servers, networking, VMs - the backbone
├── 🔒 security/        # Compliance, hardening - sleep better at night
├── ☁️ cloud/           # Azure, AWS, Kubernetes - make the clouds do your bidding
├── 👥 collaboration/   # M365, Teams, Exchange - office productivity++
├── 🗄️ data/            # Databases, APIs - where the magic happens
├── ⚙️ automation/      # CI/CD, IaC - because clicking is for chumps
└── 🧰 utilities/       # General toolbox - the grab bag of useful stuff
```

**[→ Browse the full catalog](docs/Script-Catalog.md)** · **[→ See how it all fits together](docs/ARCHITECTURE.md)**

---

## 💡 Popular Scripts (AKA The Fan Favorites)

New here? **Try these first** - they're the most commonly used scripts in the wild:

<table>
<tr>
<td width="50%">

### 📱 For Intune Admins
- **[Get-DeviceComplianceReport.ps1](scripts/endpoints/intune/reporting/)** - Find misbehaving devices fast
- **[Find-StaleDevices.ps1](scripts/endpoints/intune/maintenance/)** - Devices that haven't checked in lately
- **[Check-OutdatedCriticalApps](scripts/endpoints/devices/proactive-remediations/Check-OutdatedCriticalApps/)** - Auto-detect outdated critical apps

</td>
<td width="50%">

### 🖥️ For Server Admins
- **[Monitor-ServerHealth.ps1](scripts/infrastructure/windows/monitoring/)** - 30-second health check
- **[Invoke-SecurityComplianceScan.ps1](scripts/security/hardening/)** - Multi-framework compliance
- **[Get-EventLogReport.ps1](scripts/infrastructure/windows/monitoring/)** - Find issues before users report them

</td>
</tr>
<tr>
<td width="50%">

### ☁️ For Cloud Engineers
- **[Monitor-AzureResources.ps1](scripts/cloud/azure/core/)** - Keep tabs on your Azure environment
- **[Get-AzureResourceHealth.ps1](scripts/cloud/azure/core/)** - Track resource health and outages
- **[Get-KubernetesHealthCheck.ps1](scripts/cloud/containers/)** - K8s cluster monitoring

</td>
<td width="50%">

### 📦 For Everyone
- **[Winget Update Pairs](scripts/endpoints/devices/winget/)** - Auto-update 16 apps (Chrome, Zoom, Teams, etc.)
- **[Command Recipes](docs/RECIPES.md)** - 80+ copy-paste commands
- **[Proactive Remediations](scripts/endpoints/devices/proactive-remediations/)** - 51 auto-fix script pairs

</td>
</tr>
</table>

**[→ Browse all 358 scripts in the catalog](docs/Script-Catalog.md)**

---

## 🎯 Real Problems, Real Solutions

Here's what these scripts actually help you do:

- **"My Intune devices won't sync!"** → `Test-IntuneConnectivity.ps1` diagnoses the Graph connection, then `Find-StaleDevices.ps1` lists the laggards
- **"Which servers need patching?"** → `Monitor-ServerHealth.ps1` + compliance reports
- **"Is my Azure environment healthy?"** → `Get-AzureResourceHealth.ps1` breaks it down
- **"Users keep installing outdated software!"** → Winget auto-update pairs
- **"I need to audit 100 servers for CIS compliance!"** → Multi-framework scanner does it all
- **"Exchange mailbox permissions are a mess!"** → `Get-UserMailboxPermissions.ps1` maps it out

**Real IT problems. Real working solutions.** No fluff.

---

## ⚠️ The Honest Truth

**Most of these scripts haven't been battle-tested in massive production environments.** They're built by one person (with AI help), tested in lab environments, and improved based on real-world feedback.

**Translation:**
- ✅ DO test in non-prod first
- ✅ DO read the script before running it
- ✅ DO have backups
- ❌ DON'T YOLO it in production on Friday afternoon

That said, many are running in real environments and getting better every day. When you find issues, [open an issue](https://github.com/Carme99/bug-free-umbrella/issues) and let's fix it together!

---

## 🎨 Built Different

This repo exists because:

1. **Sharing > Hoarding** - Why should everyone rewrite the same scripts?
2. **AI + Human = Better** - Built with Claude Code, refined by experience
3. **Real Problems** - Every script solves an actual IT challenge
4. **Community First** - Your feedback makes this better for everyone

---

## 📊 By the Numbers

<div align="center">

| Metric | Count | What It Means |
|--------|-------|---------------|
| 📜 **Scripts** | 358 | Solutions to 358 real problems |
| 🏗️ **Domains** | 8 | Organized so you can actually find things |
| 🔧 **Remediation Pairs** | 51 | Auto-fix scripts running in prod |
| 📦 **Winget Pairs** | 16 | Apps that update themselves |
| 📚 **Docs Pages** | 30+ | In-repo documentation (updated with every PR) |
| ⭐ **Code Quality** | Variable | Honest software is better than perfect marketing |

</div>

---

## 🤝 Join the Party

Found a bug? Have a script to share? Want to make something better?

- 🐛 **[Report Issues](https://github.com/Carme99/bug-free-umbrella/issues)** - Bug reports make everyone's life better
- ✨ **[Request Features](https://github.com/Carme99/bug-free-umbrella/issues/new?template=feature_request.yml)** - Tell us what you need
- 🎉 **[Contribute](CONTRIBUTING.md)** - PRs welcome! (Code review by AI and human)
- 💬 **[Get Support](SUPPORT.md)** - Stuck? We'll help when we can

This is a hobby project (response time: 1-2 weeks typically), but your contributions help everyone in the community!

---

## 📖 Documentation

All documentation lives **in this repository** under [`docs/`](docs/README.md) — versioned with the code, reviewable in every PR, never stale:

| If You Want To... | Go Here |
|-------------------|---------|
| 🆕 **Get started from scratch** | [Getting Started](docs/Getting-Started.md) |
| 🔍 **Find a specific script** | [Script Catalog](docs/Script-Catalog.md) |
| 📖 **See how to use something** | [Script Examples](docs/Script-Examples.md) |
| 🎯 **Solve a specific problem** | [Common Use Cases](docs/Common-Use-Cases.md) |
| 🔥 **Fix something broken** | [Troubleshooting](docs/Troubleshooting.md) |
| ❓ **Answer a quick question** | [FAQ](docs/FAQ.md) |
| 🏗️ **Understand the architecture** | [ARCHITECTURE](docs/ARCHITECTURE.md) |

**Plus:** [CHANGELOG](CHANGELOG.md) • [SECURITY](SECURITY.md) • [CONTRIBUTING](CONTRIBUTING.md) • [CODE OF CONDUCT](CODE_OF_CONDUCT.md) • [GOVERNANCE](GOVERNANCE.md)

---

## 🤖 The Secret Sauce

This entire repository is maintained by one human developer and [Claude Code](https://github.com/anthropics/claude-code), Anthropic's official AI coding assistant.

**What this means:**
- ⚡ **Fast iteration** - Scripts get better quickly
- 🧠 **AI-assisted** - Best practices baked in
- 🔍 **Thorough** - AI catches things humans miss
- 🎯 **Focused** - Solves real problems, not theoretical ones

### 🤖 AI-Native: MCP Server

[![MCP](https://img.shields.io/badge/MCP-Server-8B5CF6?style=for-the-badge)](https://modelcontextprotocol.io)

This repo ships an MCP server (`mcp-server/`) that exposes all 358 scripts as AI tools — search, preview, and validate scripts from Claude Desktop. [→ MCP Docs](docs/MCP-Server.md)

**License:** Apache 2.0 (use it, share it, improve it)

---

## 📬 Stay Updated

- 🌟 **[Star this repo](https://github.com/Carme99/bug-free-umbrella)** to get notified of new scripts
- 👀 **[Watch releases](https://github.com/Carme99/bug-free-umbrella/releases)** for version updates
- 📋 **[Read the CHANGELOG](CHANGELOG.md)** to see what's new
- 🐛 **[Follow issues](https://github.com/Carme99/bug-free-umbrella/issues)** to track development

---

<div align="center">

### Ready to Automate Your World? 🚀

**[Get Started →](docs/Getting-Started.md)** | **[Browse Scripts →](docs/Script-Catalog.md)** | **[See Examples →](docs/Script-Examples.md)**

---

*Built with 🤖 AI assistance, ☕ caffeine, and 🌂 a commitment to sharing knowledge*

**Star ⭐ this repo if it saves you time!**

Made with ❤️ by the IT community, for the IT community

</div>
