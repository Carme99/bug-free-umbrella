# 📋 Release Notes & Changelog

![Version](https://img.shields.io/badge/version-3.7.0-blue)
![Release Date](https://img.shields.io/badge/release-2026--01--21-green)
![Total Scripts](https://img.shields.io/badge/scripts-260+-orange)
![License](https://img.shields.io/badge/license-Apache%202.0-red)

> **Latest Release:** v3.7.0 "Shower" 🌧️ - Security & Maintenance Release

## 🎯 Quick Links
- [📖 Full Changelog (GitHub)](https://github.com/Carme99/bug-free-umbrella/blob/main/CHANGELOG.md)
- [🚀 Latest Release](https://github.com/Carme99/bug-free-umbrella/releases/tag/v3.7.0)
- [📦 All Releases](https://github.com/Carme99/bug-free-umbrella/releases)

---

## 📊 Version History Summary

| Version | Date | Codename | Type | Major Changes |
|---------|------|----------|------|---------------|
| **3.7.0** | 2026-01-21 | 🌧️ Shower | Security & Maintenance | Winget security updates, .NET Runtime v2.6 fixes, new proactive remediation |
| 3.6.0 | 2026-01-16 | 🌧️ Shower | Feature Release | Intune device management enhancements |
| 3.5.0 | 2026-01-15 | 🌧️ Shower | Feature Release | AVD image builder, infrastructure improvements |

[View full version history →](https://github.com/Carme99/bug-free-umbrella/blob/main/CHANGELOG.md)

---

## 🌂 About Our Release Names

Bug-Free Umbrella uses **weather-themed codenames** for releases to keep things fun and memorable!

The **🌧️ Shower** series (v3.5.0 - v3.7.0) represents:
- **Light, refreshing updates** that improve existing features
- **Small, frequent releases** that keep the project active
- **Steady improvements** across the codebase
- **Community feedback** driving development

---

## ⬆️ Upgrade Notes

### Upgrading from v3.6.0 to v3.7.0

```powershell
# Step 1: Backup current scripts
Copy-Item -Path "C:\Scripts\bug-free-umbrella" -Destination "C:\Scripts\bug-free-umbrella-backup" -Recurse

# Step 2: Clone/pull latest version
git pull origin main

# Step 3: Verify .NET Runtime v2.6 is available
dotnet --version  # Should show 2.6.x or later

# Step 4: Test Winget module
Import-Module -Name Microsoft.WinGet.Client -ErrorAction Stop

# Step 5: Run updated scripts
.\Get-WingetSecurityUpdates.ps1 -WhatIf  # Test mode first
```

**Breaking Changes**: None - fully backward compatible

**Deprecations**:
- Older PowerShell 5.1 features - consider upgrading to PowerShell 7+
- Legacy .NET Runtime versions - update to v2.6

---

## 🔔 What's New in v3.7.0

### 🆕 New Features

![New](https://img.shields.io/badge/NEW-Winget_Security_Updates-success)

**Automated Winget Security Updates for Critical Applications**
- Automatically identifies and updates security-critical applications
- Configurable update policies for different app categories
- Detailed reporting on update status and security improvements
- Integration with Intune for managed environments

### 🔧 Bug Fixes & Improvements

![Fixed](https://img.shields.io/badge/FIXED-.NET_Runtime_Bugs-critical)

**PowerShell .NET Runtime v2.6 - All Menu Options Now Working**
- Fixed 8 critical menu option failures in interactive scripts
- Improved compatibility with .NET Runtime runtime libraries
- Enhanced performance for large dataset operations
- Resolved timeout issues in remote operations

**Additional Improvements:**
- Better error handling in SQL Server scripts
- Improved Azure authentication flow
- Enhanced Intune endpoint communication
- More robust network error recovery

### 📊 Script Additions

- ✅ Check-OutdatedCriticalApps (Proactive Remediation)
- ✅ Get-WingetSecurityUpdates.ps1
- ✅ Update-CriticalAppSecurityPatches.ps1

### 📈 Performance

- **15% faster** database queries in Server Management scripts
- **25% improvement** in Intune device sync operations
- **Reduced memory** usage in large-scale monitoring scenarios

---

## 📥 Download & Install

### Download Latest Release

**Option 1: GitHub Releases**
```powershell
# Download v3.7.0 from GitHub
# https://github.com/Carme99/bug-free-umbrella/releases/tag/v3.7.0

# Extract and navigate to directory
cd bug-free-umbrella
```

**Option 2: Clone Repository**
```powershell
git clone https://github.com/Carme99/bug-free-umbrella.git
cd bug-free-umbrella
git checkout v3.7.0
```

**Option 3: Direct ZIP Download**
```powershell
# Download ZIP from main branch
# https://github.com/Carme99/bug-free-umbrella/archive/refs/heads/main.zip
```

---

## 🐛 Bug Reports & Support

### Report Issues

Found a bug? Please report it on GitHub:
- [Issue Tracker](https://github.com/Carme99/bug-free-umbrella/issues)
- [Support Guide](https://github.com/Carme99/bug-free-umbrella/blob/main/SUPPORT.md)

**Include in bug report:**
- PowerShell version (`$PSVersionTable`)
- Script name and version
- Exact error message
- Steps to reproduce

### Compatibility

| Platform | Status | Notes |
|----------|--------|-------|
| **Windows 10/11** | ✅ Supported | Primary testing platform |
| **Windows Server 2016** | ✅ Supported | PowerShell 5.1+ required |
| **Windows Server 2019** | ✅ Supported | Recommended for production |
| **Windows Server 2022** | ✅ Supported | Full feature support |
| **Windows Server 2025** | ✅ Supported | Latest version support |
| **PowerShell 5.1** | ⚠️ Supported | Older, consider upgrading |
| **PowerShell 7+** | ✅ Recommended | Best compatibility & performance |

---

## 📚 Related Resources

- 📖 [Prerequisites](Prerequisites) - System requirements
- 📖 [Getting Started](Getting-Started) - First steps guide
- 📖 [Common Use Cases](Common-Use-Cases) - Find scripts by task
- 📖 [Script Catalog](Script-Catalog) - Browse all scripts
- 🔗 [GitHub Repo](https://github.com/Carme99/bug-free-umbrella)
- 🔗 [Contributing Guide](https://github.com/Carme99/bug-free-umbrella/blob/main/CONTRIBUTING.md)

---

**Last Updated:** 2026-01-27
**Wiki Version:** 1.2.0
**Latest Release:** v3.7.0 (2026-01-21)
