# 🌂 Bug-Free Umbrella

> **Because IT shouldn't rain on your parade.**

Your personal collection of 260+ battle-tested PowerShell scripts for when you need to automate *everything* in your enterprise environment.

<div align="center">

[![PowerShell](https://img.shields.io/badge/PowerShell-7.0+-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Windows](https://img.shields.io/badge/Windows-Server_2016+-0078D6?style=for-the-badge&logo=windows&logoColor=white)](https://www.microsoft.com/windows-server)
[![Linux](https://img.shields.io/badge/Linux-Compatible-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://github.com/PowerShell/PowerShell)
[![macOS](https://img.shields.io/badge/macOS-Compatible-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/PowerShell/PowerShell)

[![License](https://img.shields.io/github/license/Carme99/bug-free-umbrella?style=for-the-badge)](LICENSE)
[![Stars](https://img.shields.io/github/stars/Carme99/bug-free-umbrella?style=for-the-badge)](https://github.com/Carme99/bug-free-umbrella/stargazers)
[![Issues](https://img.shields.io/github/issues/Carme99/bug-free-umbrella?style=for-the-badge)](https://github.com/Carme99/bug-free-umbrella/issues)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen?style=for-the-badge)](CONTRIBUTING.md)

[![Scripts](https://img.shields.io/badge/Scripts-260+-FF6B6B?style=for-the-badge&logo=files&logoColor=white)](https://github.com/Carme99/bug-free-umbrella/wiki/Script-Catalog)
[![Wiki](https://img.shields.io/badge/📚_Full_Documentation-Wiki-4A9EFF?style=for-the-badge)](https://github.com/Carme99/bug-free-umbrella/wiki)
[![Claude Code](https://img.shields.io/badge/Built_with-Claude_Code-8B5CF6?style=for-the-badge&logo=anthropic&logoColor=white)](https://github.com/anthropics/claude-code)
[![Last Commit](https://img.shields.io/github/last-commit/Carme99/bug-free-umbrella?style=for-the-badge)](https://github.com/Carme99/bug-free-umbrella/commits/main)

---

### 📚 **[→ Visit the Wiki for Complete Documentation](https://github.com/Carme99/bug-free-umbrella/wiki)** ⭐

**[🚀 Quick Start](https://github.com/Carme99/bug-free-umbrella/wiki/Getting-Started)** • **[📋 Script Catalog](https://github.com/Carme99/bug-free-umbrella/wiki/Script-Catalog)** • **[💡 Examples](https://github.com/Carme99/bug-free-umbrella/wiki/Script-Examples)** • **[🔧 Troubleshooting](https://github.com/Carme99/bug-free-umbrella/wiki/Troubleshooting)**

</div>

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
| **📱 Intune Management** | 18+ scripts to wrangle your endpoints into submission |
| **🔧 Proactive Remediations** | 14 pairs of detect/fix scripts that run before users notice issues |
| **📦 Winget Updates** | 40+ app auto-update templates (set it and forget it) |
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

**[→ Full getting started guide](https://github.com/Carme99/bug-free-umbrella/wiki/Getting-Started)**

---

## 📁 What's Inside the Toolbox

This isn't just a random pile of scripts. Everything's organized into **7 technology domains** so you can actually find what you need:

```
🌂 bug-free-umbrella/
├── ☁️  cloud/          # Azure, AWS, Kubernetes - make the clouds do your bidding
├── 📱 endpoints/       # Intune, devices, remediation - keep users happy
├── 🖥️  infrastructure/ # Servers, networking, VMs - the backbone
├── 🔒 security/        # Compliance, hardening - sleep better at night
├── ⚙️  automation/     # CI/CD, IaC - because clicking is for chumps
├── 👥 collaboration/   # M365, Teams, Exchange - office productivity++
└── 🗄️  data/           # Databases, APIs - where the magic happens
```

**[→ Browse the full catalog](https://github.com/Carme99/bug-free-umbrella/wiki/Script-Catalog)**

---

## 💡 Popular Scripts (AKA The Fan Favorites)

These are the scripts people actually use every week:

- **🔍 Get-DeviceComplianceReport.ps1** - Find out which devices are misbehaving
- **🔄 Sync-IntuneDevice.ps1** - Force that stubborn device to check in
- **🖥️ Monitor-ServerHealth.ps1** - "Is the server okay?" answered in 30 seconds
- **🔐 Invoke-SecurityComplianceScan.ps1** - Multi-framework compliance check that actually works
- **☁️ Monitor-AzureResources.ps1** - Keep tabs on your Azure environment
- **📦 Winget Update Templates** - Auto-update everything from Chrome to Zoom

**[→ See real-world examples](https://github.com/Carme99/bug-free-umbrella/wiki/Script-Examples)**

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
| 📜 **Scripts** | 260+ | Solutions to 260+ real problems |
| 🏗️ **Domains** | 7 | Organized so you can actually find things |
| 🔧 **Remediation Pairs** | 14 | Auto-fix scripts running in prod |
| 📦 **Winget Templates** | 40+ | Apps that update themselves |
| 📚 **Wiki Pages** | 20+ | Comprehensive docs (actually maintained!) |
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

Everything you need is in the wiki, organized by what you're trying to do:

| If You Want To... | Go Here |
|-------------------|---------|
| 🆕 **Get started from scratch** | [Getting Started Guide](https://github.com/Carme99/bug-free-umbrella/wiki/Getting-Started) |
| 🔍 **Find a specific script** | [Script Catalog](https://github.com/Carme99/bug-free-umbrella/wiki/Script-Catalog) |
| 📖 **See how to use something** | [Script Examples](https://github.com/Carme99/bug-free-umbrella/wiki/Script-Examples) |
| 🎯 **Solve a specific problem** | [Common Use Cases](https://github.com/Carme99/bug-free-umbrella/wiki/Common-Use-Cases) |
| 🔥 **Fix something broken** | [Troubleshooting](https://github.com/Carme99/bug-free-umbrella/wiki/Troubleshooting) |
| ❓ **Answer a quick question** | [FAQ](https://github.com/Carme99/bug-free-umbrella/wiki/FAQ) |

**Plus:** [CHANGELOG](CHANGELOG.md) • [SECURITY](SECURITY.md) • [CONTRIBUTING](CONTRIBUTING.md) • [CODE OF CONDUCT](CODE_OF_CONDUCT.md) • [GOVERNANCE](GOVERNANCE.md)

---

## 🤖 The Secret Sauce

This entire repository is maintained by one human developer and [Claude Code](https://github.com/anthropics/claude-code), Anthropic's official AI coding assistant.

**What this means:**
- ⚡ **Fast iteration** - Scripts get better quickly
- 🧠 **AI-assisted** - Best practices baked in
- 🔍 **Thorough** - AI catches things humans miss
- 🎯 **Focused** - Solves real problems, not theoretical ones

**License:** Apache 2.0 (use it, share it, improve it)

---

<div align="center">

### Ready to Automate Your World? 🚀

**[Get Started →](https://github.com/Carme99/bug-free-umbrella/wiki/Getting-Started)** | **[Browse Scripts →](https://github.com/Carme99/bug-free-umbrella/wiki/Script-Catalog)** | **[See Examples →](https://github.com/Carme99/bug-free-umbrella/wiki/Script-Examples)**

---

*Built with 🤖 AI assistance, ☕ caffeine, and 🌂 a commitment to sharing knowledge*

**Star ⭐ this repo if it saves you time!**

</div>
