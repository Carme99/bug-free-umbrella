# 🚀 Getting Started with Bug-Free Umbrella

Welcome! This guide will help you get up and running with Bug-Free Umbrella scripts quickly and safely.

---

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Environment Check](#quick-environment-check)
3. [Choose Your Path](#choose-your-path)
4. [Your First Script](#your-first-script)
5. [Next Steps](#next-steps)

---

## Prerequisites

Before using these scripts, ensure you have the following:

### For All Scripts
- ✅ **PowerShell 5.1 or later** (PowerShell 7+ recommended)
- ✅ **Administrator privileges** (most scripts require elevation)
- ✅ **Execution Policy** set appropriately

### For Intune Scripts
- ✅ **Microsoft Graph PowerShell SDK**
  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser
  ```
- ✅ **Required Permissions**: DeviceManagementManagedDevices.Read.All (minimum)
- ✅ **Intune Administrator** or **Global Reader** role

### For Cloud Scripts (Azure/AWS)
- ✅ **Azure PowerShell** (for Azure scripts)
  ```powershell
  Install-Module Az -Scope CurrentUser
  ```
- ✅ **AWS Tools for PowerShell** (for AWS scripts)
  ```powershell
  Install-Module AWS.Tools.Common -Scope CurrentUser
  ```

### For Server Scripts
- ✅ **Windows Server 2016, 2019, or 2022**
- ✅ **Local Administrator** privileges
- ✅ No additional modules required (uses built-in cmdlets)

---

## Quick Environment Check

Run these commands to verify your setup:

### Check PowerShell Version
```powershell
$PSVersionTable.PSVersion
# Should show 5.1 or higher
```

### Check if Running as Administrator
```powershell
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# Should return: True
```

### Check Execution Policy
```powershell
Get-ExecutionPolicy
# If Restricted, run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Choose Your Path

Select the path that matches your role:

### Path 1: Microsoft 365 / Intune Administrator
```
YOU ARE HERE
    ↓
Install Microsoft.Graph module
    ↓
Try: Get-DeviceComplianceReport.ps1
    ↓
See: [Intune Management](Intune-Management) guide
    ↓
Follow: [Monthly Compliance Audit Workflow](Workflows#monthly-compliance-audit-workflow)
```

**[Start with Intune Management →](Intune-Management)**

### Path 2: Windows Server Administrator
```
YOU ARE HERE
    ↓
Verify administrator access
    ↓
Try: Monitor-ServerHealth.ps1
    ↓
See: [Server Management](Server-Management) guide
    ↓
Follow: [New Server Setup Workflow](Workflows#new-windows-server-setup)
```

**[Start with Server Management →](Server-Management)**

### Path 3: DevOps / Cloud Engineer
```
YOU ARE HERE
    ↓
Install Az or AWS.Tools modules
    ↓
Try: Monitor-AzureDevOpsPipelines.ps1
    ↓
See: DevOps & CI/CD scripts (Coming soon)
    ↓
Explore: Cloud Infrastructure scripts (Coming soon)
```

**Start with DevOps & CI/CD** (Category pages coming soon - see [Script Catalog](Script-Catalog) for now)

### Path 4: IT Support / Help Desk
```
YOU ARE HERE
    ↓
Review [Proactive Remediations](Proactive-Remediations)
    ↓
Try: Fix-DiskSpace (detect.ps1 first!)
    ↓
Follow: [Automated Winget Updates Workflow](Workflows#setting-up-automated-winget-updates)
    ↓
Explore: All 14 remediation pairs
```

**[Start with Proactive Remediations →](Proactive-Remediations)**

---

## Your First Script

Let's run a simple, safe script to get started!

### Example 1: Check Intune Device Compliance (Read-Only)

```powershell
# Navigate to the scripts folder
cd scripts/intune

# View help for the script
Get-Help .\Get-DeviceComplianceReport.ps1 -Detailed

# Run the script (generates HTML report on Desktop)
.\Get-DeviceComplianceReport.ps1
```

**What it does:**
- ✅ Reads Intune device compliance data
- ✅ Generates HTML and CSV reports
- ✅ Saves to your Desktop
- ✅ **No changes** to your environment

### Example 2: Check Server Health (Read-Only)

```powershell
# Navigate to server monitoring
cd scripts/server/monitoring

# Run basic health check
.\Monitor-ServerHealth.ps1

# Try the new interactive mode!
.\Monitor-ServerHealth.ps1 -Interactive
```

**What it does:**
- ✅ Checks CPU, memory, disk usage
- ✅ Shows service status
- ✅ Displays event log errors
- ✅ **No changes** to your environment

### Example 3: Test API Health (Read-Only)

```powershell
# Navigate to API management
cd scripts/api-management

# Test a simple API endpoint
.\Test-APIHealth.ps1 -Endpoint "https://api.github.com/status"
```

**What it does:**
- ✅ Tests API connectivity
- ✅ Measures response time
- ✅ Validates SSL certificates
- ✅ **No changes** to your environment

---

## Understanding Script Types

### Detection Scripts (detect.ps1)
- **Purpose:** Identify issues without making changes
- **Exit 0:** No issues found (compliant)
- **Exit 1:** Issues detected (non-compliant)
- **Safe to run:** Yes! Read-only

### Remediation Scripts (remediate.ps1)
- **Purpose:** Fix detected issues
- **Exit 0:** Remediation successful
- **Exit 1:** Remediation failed
- **Safe to run:** Test in non-production first!

### Reporting Scripts
- **Purpose:** Generate reports and dashboards
- **Output:** HTML and CSV files
- **Exit 0:** Report generated successfully
- **Safe to run:** Yes! Read-only

---

## Safety Tips

### ⚠️ IMPORTANT: Test First!
> **The vast majority of scripts have not been thoroughly tested in production.**
> Always test in a non-production environment first!

### Best Practices
1. ✅ **Read the script** - Review the code before running
2. ✅ **Check prerequisites** - Ensure required modules are installed
3. ✅ **Use Get-Help** - Read the documentation
   ```powershell
   Get-Help .\ScriptName.ps1 -Detailed
   ```
4. ✅ **Test with -WhatIf** - If available, use this parameter to preview changes
5. ✅ **Check exit codes** - Understand what they mean
6. ✅ **Review output** - Check logs and reports
7. ✅ **Have backups** - Always have a recovery plan

### Running Detection Scripts First
For Proactive Remediations, **always run detect.ps1 before remediate.ps1**:

```powershell
# 1. First, detect issues
.\detect.ps1
# Check the output and exit code

# 2. Only if exit code is 1 (issues found), run remediation
.\remediate.ps1
```

---

## What to Expect

### Script Execution Times
| Script Type | Typical Duration |
|-------------|------------------|
| Detection Scripts | 10-30 seconds |
| Winget Updates | 2-5 minutes |
| Intune Reports | 3-10 minutes |
| Server Health Checks | 15-30 minutes |
| Cloud Infrastructure Scans | 5-15 minutes |
| CI/CD Pipeline Monitoring | 1-5 minutes |

### Output Formats
Most scripts generate:
- 📊 **HTML reports** - Pretty, formatted reports
- 📑 **CSV files** - For data analysis
- 🖥️ **Console output** - Color-coded status

**Default location:** `C:\Users\[YourName]\Desktop\`

### Exit Codes
- **0** = Success / No issues found / Compliant
- **1** = Issues detected / Remediation needed / Non-compliant

See individual script documentation for detailed exit code information.

---

## Next Steps

### Beginner Path
1. ✅ You've completed Getting Started!
2. 📖 Browse [Script Catalog](Script-Catalog) to see all scripts
3. 💡 Review [Script Examples](Script-Examples) for detailed usage
4. 🛠️ Try a [Workflow](Workflows) for a complete process

### Intermediate Path
1. ✅ You're ready for production!
2. 📋 Follow [Complete Workflows](Workflows)
3. 🔧 Set up [Automated Winget Updates](Workflows#setting-up-automated-winget-updates)
4. 📊 Implement [Monthly Compliance Audit](Workflows#monthly-compliance-audit-workflow)

### Advanced Path
1. ✅ You're a power user!
2. 🏗️ Review the codebase to understand design patterns
3. 🔨 Customize scripts for your environment
4. 🤝 Read [Contributing](https://github.com/Carme99/bug-free-umbrella/blob/main/CONTRIBUTING.md) to help improve the repo

---

## Getting Help

### Built-in Help
Every major script has built-in help:
```powershell
# Detailed help
Get-Help .\ScriptName.ps1 -Detailed

# Just examples
Get-Help .\ScriptName.ps1 -Examples

# Full documentation
Get-Help .\ScriptName.ps1 -Full
```

### Documentation
- 📖 **Script Examples** - [See detailed examples](Script-Examples)
- 🔍 **Troubleshooting** - [Common issues](Troubleshooting)
- ❓ **FAQ** - [Frequently asked questions](FAQ)
- 📋 **Workflows** - [Complete processes](Workflows)

### Support
| Issue | Where to Go |
|-------|-------------|
| Script not working | [Troubleshooting Guide](Troubleshooting) |
| Don't understand usage | [Script Examples](Script-Examples) |
| Found a bug | [GitHub Issues](https://github.com/Carme99/bug-free-umbrella/issues) |
| Want to contribute | [Contributing Guide](https://github.com/Carme99/bug-free-umbrella/blob/main/CONTRIBUTING.md) |
| Security concern | [Security Policy](https://github.com/Carme99/bug-free-umbrella/blob/main/SECURITY.md) |

---

## Quick Reference Card

Save this for quick access:

```powershell
# Check PowerShell version
$PSVersionTable.PSVersion

# Check if admin
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Get script help
Get-Help .\ScriptName.ps1 -Detailed

# Install Microsoft Graph
Install-Module Microsoft.Graph -Scope CurrentUser

# Install Azure PowerShell
Install-Module Az -Scope CurrentUser

# Navigate to scripts
cd C:\Path\To\bug-free-umbrella\scripts
```

---

## Congratulations! 🎉

You're ready to start using Bug-Free Umbrella scripts!

**Next:** Choose your path above or browse the [Script Catalog](Script-Catalog)

**Questions?** Check the [FAQ](FAQ) or [Troubleshooting](Troubleshooting) guide

---

**Last Updated:** 2026-01-04
**Corresponds to:** v3.0.2 "Drizzle" ☔
