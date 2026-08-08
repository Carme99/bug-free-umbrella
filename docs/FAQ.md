# Frequently Asked Questions (FAQ)

![Tier](https://img.shields.io/badge/Tier-1-green) ![Category](https://img.shields.io/badge/Category-Foundation-blue) ![Status](https://img.shields.io/badge/Status-Stable-brightgreen)

Common questions about Bug-Free Umbrella scripts and how to use them.

## Table of Contents

- [General Questions](#general-questions)
- [Getting Started](#getting-started)
- [Script Usage](#script-usage)
- [Permissions & Security](#permissions--security)
- [Authentication & Modules](#authentication--modules)
- [Intune & Endpoint Management](#intune--endpoint-management)
- [Troubleshooting](#troubleshooting)
- [Contributing & Support](#contributing--support)
- [Updates & Versions](#updates--versions)
- [Advanced Topics](#advanced-topics)
- [See Also](#see-also)

## General Questions

### What is Bug-Free Umbrella?

Bug-Free Umbrella is a comprehensive collection of 260+ PowerShell scripts for enterprise IT management, covering:

- Microsoft 365 & Intune administration
- Azure & AWS cloud management
- Windows Server administration
- Security & compliance auditing
- Device management & automation

### Who maintains this project?

Bug-Free Umbrella is maintained by a solo developer using [Claude Code](https://github.com/anthropics/claude-code).

### Is this project free to use?

Yes! Bug-Free Umbrella is open source under the **Apache License 2.0**. You can use, modify, and distribute the scripts freely.

### Can I use these scripts in production?

Yes, but always:

1. **Test in a non-production environment first**
2. **Review the script code** before running
3. **Understand what the script does**
4. **Ensure you have proper backups**
5. **Have appropriate permissions**

---

## Getting Started

### How do I install/download the scripts?

**Option 1: Git Clone (Recommended)**

```powershell
git clone https://github.com/Carme99/bug-free-umbrella.git
cd bug-free-umbrella
```

**Option 2: Download ZIP**

1. Visit https://github.com/Carme99/bug-free-umbrella
2. Click "Code" → "Download ZIP"
3. Extract to your preferred location

### Do I need to install anything?

Yes, check the **[Prerequisites](Prerequisites.md)** page for:

- PowerShell 5.1+ (PowerShell 7+ recommended)
- Required PowerShell modules (Az, Microsoft.Graph, etc.)
- Proper execution policy
- Administrator privileges (for many scripts)

### How do I run a script?

```powershell
# Navigate to script directory
cd scripts/security/compliance/frameworks

# Run the script
.\Test-CISBenchmark.ps1

# Or with parameters
.\Test-CISBenchmark.ps1 -Level 2 -ExportHTML
```

See **[Getting Started](Getting-Started.md)** for detailed instructions.

---

## Script Usage

### How do I find the right script for my task?

1. Browse the **[Script Catalog](Script-Catalog.md)** organized by category
2. Check **[Script Examples](Script-Examples.md)** for common use cases
3. Search the repository at https://github.com/Carme99/bug-free-umbrella

### What do the script directories mean?

| Directory | Purpose |
|-----------|---------|
| `scripts/endpoints/` | Device management (Intune, proactive remediations) |
| `scripts/cloud/` | Azure & AWS management |
| `scripts/collaboration/` | M365, Exchange, Teams, SharePoint |
| `scripts/security/` | Security auditing & compliance |
| `scripts/infrastructure/` | Server management (Windows, Linux) |
| `scripts/automation/` | CI/CD & DevOps automation |
| `scripts/data/` | Database & API management |

See **[scripts/](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts)** in the repository.

### Can I modify the scripts?

Absolutely! The scripts are open source. You can:

- Modify them for your environment
- Add features
- Fix bugs
- Share improvements back (see **[Contributing](../CONTRIBUTING.md)**)

---

## Permissions & Security

### Why do some scripts need administrator privileges?

Scripts that modify system settings, read security policies, or access protected resources require admin rights. Examples:

- **Test-CISBenchmark.ps1** - Reads security policies via `secedit.exe`
- **Monitor-ServerHealth.ps1** - Accesses performance counters
- **Proactive remediations** - Make system changes

### How do I run PowerShell as Administrator?

**Windows 10/11:**

- Right-click PowerShell → "Run as Administrator"
- Or search "PowerShell" → Right-click → "Run as Administrator"

**Windows Terminal:**

- Open Windows Terminal as Administrator
- Or use Ctrl+Shift+Enter when launching

### Are these scripts safe to run?

The scripts are designed to be safe, but you should always:

1. **Review the code** before running
2. **Test in non-production** first
3. **Understand what it does**
4. **Have backups**

Report security concerns to our **[Security Policy](../SECURITY.md)**.

---

## Authentication & Modules

### How do I authenticate to Microsoft 365/Azure?

Most scripts use Microsoft Graph or Az modules:

```powershell
# Microsoft Graph (for M365/Intune)
Connect-MgGraph -Scopes "User.Read.All", "DeviceManagementManagedDevices.Read.All"

# Azure
Connect-AzAccount

# Exchange Online
Connect-ExchangeOnline
```

### What if I get "Module not found" errors?

Install the required module:

```powershell
# Find what module you need
Get-Command <cmdlet-name> -ListAvailable

# Install missing module
Install-Module <ModuleName> -Scope CurrentUser -Force

# Common modules
Install-Module Microsoft.Graph -Scope CurrentUser
Install-Module Az -Scope CurrentUser
Install-Module ExchangeOnlineManagement -Scope CurrentUser
```

### Do scripts store my credentials?

No. Scripts use:

- **Interactive authentication** (you sign in manually)
- **Managed identities** (for Azure automation)
- **Service principals** (for automated scenarios)

Scripts never store passwords in plain text.

---

## Intune & Endpoint Management

### How do I deploy scripts to Intune?

See **[Intune Management](Intune-Management.md)** and **[Workflows](Workflows.md)** for detailed guides.

Quick steps:

1. Package script as Intune application
2. Upload to Endpoint Manager
3. Assign to device groups
4. Monitor deployment

### What are Proactive Remediations?

Proactive Remediations are detect/remediate script pairs that:

- **Detection script** - Checks if issue exists
- **Remediation script** - Fixes the issue automatically

Located in: `scripts/endpoints/devices/proactive-remediations/`

### Can I use these scripts with SCCM/ConfigMgr?

Yes! Most scripts work with ConfigMgr:

- Deploy as packages
- Run as applications
- Use in task sequences
- Schedule as maintenance tasks

---

## Troubleshooting

### Script fails with "Execution policy" error

**Error:**

```
File cannot be loaded because running scripts is disabled on this system
```

**Solution:**

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Script fails with "Unauthorized" or "Forbidden"

**Cause:** Insufficient permissions

**Solutions:**

- Check your role assignments (Global Admin, etc.)
- Connect with appropriate scopes: `Connect-MgGraph -Scopes "<required-permissions>"`
- Verify license requirements (Intune, E3/E5, etc.)

### Script runs but produces no output

**Common causes:**

1. No data matches your criteria
2. Missing parameters
3. Permissions issue (returns empty results)

**Debug:**

```powershell
# Run with verbose output
.\Script.ps1 -Verbose

# Check execution
$Error[0] | Format-List * -Force
```

See **[Troubleshooting](Troubleshooting.md)** for more help.

---

## Contributing & Support

### How can I contribute?

See **[Contributing Guide](../CONTRIBUTING.md)** for:

- Bug reports
- Feature requests
- Pull requests
- Code style guidelines

### I found a bug, what should I do?

1. Check **[Troubleshooting](Troubleshooting.md)** first
2. Search existing **[Issues](https://github.com/Carme99/bug-free-umbrella/issues)**
3. Create a new issue with:
   - Script name & location
   - Error message
   - PowerShell version
   - Steps to reproduce

### Can I request new scripts?

Yes! **[Create an issue](https://github.com/Carme99/bug-free-umbrella/issues/new)** with:

- Detailed description of what you need
- Use case/scenario
- Any specific requirements

### How do I get support?

- **[Support Guide](../SUPPORT.md)** - Response times and support channels (START HERE!)
- **[Troubleshooting Guide](Troubleshooting.md)** - Common issues
- **[GitHub Issues](https://github.com/Carme99/bug-free-umbrella/issues)** - Bug reports & questions (auto-labeled)

**Note:** GitHub Discussions are not enabled for this repository. Please use Issues for all questions.

### How quickly will I get a response?

This is a hobby project maintained in spare time. See the **[Support Guide](../SUPPORT.md)** for detailed response time expectations:

| Issue Type | Typical Response Time |
|------------|----------------------|
| 🔴 Security vulnerabilities | 1-3 days |
| 🐛 Critical bugs | 3-7 days |
| ✨ Feature requests | 1-2 weeks |
| ❓ Questions | 1-2 weeks |
| 📝 Documentation | 2-4 weeks |

**Important:** These are estimates, not guarantees. Responses may take longer depending on availability.

### What is expected when contributing?

Please review our **[Code of Conduct](../CODE_OF_CONDUCT.md)** to understand community standards and expectations. All contributors must:

- Be respectful and professional
- Follow contribution guidelines in **[CONTRIBUTING.md](../CONTRIBUTING.md)**
- Understand this is a hobby project with no SLAs

### Will my issue be closed automatically?

Yes. Inactive issues are automatically closed after 60 days of inactivity (PRs after 30 days) with a 7-day warning. This helps keep the repository organized. Issues can be reopened if needed.

---

## Updates & Versions

### How do I update to the latest version?

**If using Git:**

```powershell
cd bug-free-umbrella
git pull origin main
```

**If using ZIP:**

- Download latest release from **[Releases](https://github.com/Carme99/bug-free-umbrella/releases)**
- Extract and replace old files

### How often are scripts updated?

Check the **[Changelog](../CHANGELOG.md)** for release history. Recent updates:

- **v3.0.2 "Drizzle"** (2026-01-03) - Documentation cleanup
- **v3.0.1 "Drizzle"** (2025-12-31) - Bug fixes
- **v3.0.0 "Hurricane"** (2025-12-30) - Repository restructure
- **v2.2.0 "Shower"** (2025-12-28) - Navigation improvements

### Will old scripts break after updates?

We follow **[Semantic Versioning](https://semver.org/)**:

- **Patch (x.x.1)** - Bug fixes, safe to update
- **Minor (x.1.x)** - New features, backward compatible
- **Major (1.x.x)** - Breaking changes, review before updating

---

## Advanced Topics

### Can I automate these scripts in pipelines?

Yes! Many scripts work in:

- **Azure DevOps Pipelines**
- **GitHub Actions**
- **GitLab CI/CD**
- **Jenkins**

Use service principals or managed identities for authentication.

### Do scripts support parameters?

Most scripts support parameters. Check help:

```powershell
Get-Help .\Script.ps1 -Full
Get-Help .\Script.ps1 -Examples
```

### Can I schedule scripts?

Yes, use:

- **Windows Task Scheduler**
- **Azure Automation** (recommended for cloud scripts)
- **Intune scheduled tasks**
- **SCCM scheduled packages**

---

## Still Have Questions?

- 📖 **[Getting Started](Getting-Started.md)** - Basic usage guide
- 📍 **[Script Catalog](Script-Catalog.md)** - Browse all scripts
- 💡 **[Script Examples](Script-Examples.md)** - Detailed examples
- 🆘 **[Troubleshooting](Troubleshooting.md)** - Common issues
- 🐛 **[GitHub Issues](https://github.com/Carme99/bug-free-umbrella/issues)** - Report bugs

## See Also

- [Getting Started](Getting-Started.md) - Step-by-step onboarding
- [Prerequisites](Prerequisites.md) - System requirements and setup
- [Script Catalog](Script-Catalog.md) - Browse all 260+ scripts
- [Troubleshooting](Troubleshooting.md) - Solve common problems
- [Support Guide](../SUPPORT.md) - Get help
- [Contributing](../CONTRIBUTING.md) - Contribute to the project
