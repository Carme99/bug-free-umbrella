# Prerequisites

![Tier](https://img.shields.io/badge/Tier-1-green) ![Category](https://img.shields.io/badge/Category-Foundation-blue) ![Status](https://img.shields.io/badge/Status-Stable-brightgreen) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1+_|_7.0+-5391FE?logo=powershell&logoColor=white) ![Windows](https://img.shields.io/badge/Windows-10/11_|_Server_2016--2025-0078D6?logo=windows&logoColor=white) ![License](https://img.shields.io/badge/license-Apache%202.0-red)

> **Quick Tip:** PowerShell 7+ recommended for best compatibility and performance! 🚀

Before using Bug-Free Umbrella scripts, ensure you have the following prerequisites installed and configured.

## Table of Contents

- [System Requirements](#system-requirements)
- [PowerShell Version Guide](#powershell-version-guide)
- [Required Modules](#required-modules)
- [Permissions & Access](#permissions--access)
- [Optional Tools](#optional-tools)
- [Quick Setup Script](#quick-setup-script)
- [Script-Specific Requirements](#script-specific-requirements)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Next Steps](#next-steps)
- [See Also](#see-also)

## System Requirements

### Operating System

![Desktop](https://img.shields.io/badge/Windows_10/11-supported-success) ![Server](https://img.shields.io/badge/Server_2016--2025-supported-success) ![Linux](https://img.shields.io/badge/Linux-partial-yellow)

- **Windows 10/11** - Full support (primary target)
- **Windows Server 2016** - Supported, PowerShell 5.1+
- **Windows Server 2019** - Supported, PowerShell 5.1+ or 7+
- **Windows Server 2022** - Supported, PowerShell 5.1+ or 7+
- **Windows Server 2025** - Fully supported, PowerShell 7+ recommended
- **Linux** - Partial support (scripts in `scripts/infrastructure/linux/`)
- **macOS** - Limited support (cross-platform tools only)

### PowerShell Version Guide

#### PowerShell 5.1 (Windows PowerShell)

![Status](https://img.shields.io/badge/status-supported-success) ![Platform](https://img.shields.io/badge/platform-Windows_only-blue)

- Built into Windows 10/11 and Windows Server 2016+
- **Limitation**: Windows-only, cannot run on Linux/macOS
- **Use when**: Managing Windows-only environments
- **Note**: Some modern scripts may require PowerShell 7+ features

Check version:

```powershell
# PowerShell 5.1
$PSVersionTable.PSVersion
$PSVersionTable.PSEdition  # Output: Desktop
```

#### PowerShell 7+ (PowerShell Core)

![Status](https://img.shields.io/badge/status-recommended-brightgreen) ![Platform](https://img.shields.io/badge/platform-cross--platform-success)

- **Cross-platform**: Windows, Linux, macOS
- **Better performance** and modern features
- **Recommended** for all new deployments
- Latest version: PowerShell 7.4+

Check version:

```powershell
# PowerShell 7+
$PSVersionTable.PSVersion
$PSVersionTable.PSEdition  # Output: Core

# Install from: https://github.com/PowerShell/PowerShell/releases
```

**⚠️ Important**: Some scripts require PowerShell 7+ features. Check individual script requirements.

### Windows Server Support

![Server 2016](https://img.shields.io/badge/2016-supported-success) ![Server 2019](https://img.shields.io/badge/2019-supported-success) ![Server 2022](https://img.shields.io/badge/2022-supported-success) ![Server 2025](https://img.shields.io/badge/2025-supported-brightgreen)

**Supported Versions:**

- ✅ Windows Server 2025 (Latest)
- ✅ Windows Server 2022
- ✅ Windows Server 2019
- ✅ Windows Server 2016
- ⚠️ Windows Server 2012 R2 (Limited support, PowerShell 5.1 required)

## Required Modules

Different scripts require different PowerShell modules. Here are the most common:

### Microsoft 365 & Azure

```powershell
# Install Microsoft Graph (for M365 scripts)
Install-Module Microsoft.Graph -Scope CurrentUser -Force

# Install Azure PowerShell (for Azure scripts)
Install-Module Az -Scope CurrentUser -Force

# Install Exchange Online (for Exchange scripts)
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force

# Install Teams (for Teams scripts)
Install-Module MicrosoftTeams -Scope CurrentUser -Force
```

### Intune Management

```powershell
# Microsoft Graph is the primary module for Intune
Install-Module Microsoft.Graph.Intune -Scope CurrentUser -Force
```

### AWS Management

```powershell
# Install AWS Tools
Install-Module AWS.Tools.Common -Scope CurrentUser -Force
Install-Module AWS.Tools.EC2 -Scope CurrentUser -Force
```

## Permissions & Access

### Execution Policy

Set PowerShell execution policy to allow script execution:

```powershell
# For current user (recommended)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Or for all users (requires admin)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
```

### Administrator Privileges

Many scripts require administrator privileges:

- **Security & Compliance scripts** - Require admin to read security policies
- **Server Management scripts** - Require admin for system changes
- **Proactive Remediations** - Typically run as SYSTEM in Intune

Run PowerShell as Administrator when needed:

```powershell
# Check if running as admin
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

### Cloud Service Authentication

#### Microsoft 365 / Azure

Most scripts use modern authentication. Ensure you have:

- **Global Admin** or appropriate role-based permissions
- **Multi-factor authentication** configured
- **Application registrations** (for automated scripts)

Connect to services:

```powershell
# Connect to Microsoft Graph
Connect-MgGraph -Scopes "User.Read.All", "Group.Read.All"

# Connect to Azure
Connect-AzAccount

# Connect to Exchange Online
Connect-ExchangeOnline
```

#### AWS

Configure AWS credentials:

```powershell
# Set AWS credentials
Set-AWSCredential -AccessKey YOUR_ACCESS_KEY -SecretKey YOUR_SECRET_KEY -StoreAs default
```

## Optional Tools

### Git (Recommended)

For cloning the repository and staying updated:

```powershell
# Install Git via winget
winget install Git.Git

# Clone the repository
git clone https://github.com/Carme99/bug-free-umbrella.git
```

### VS Code (Recommended)

Best editor for PowerShell development:

```powershell
# Install VS Code via winget
winget install Microsoft.VisualStudioCode

# Install PowerShell extension
code --install-extension ms-vscode.PowerShell
```

### Windows Terminal (Recommended)

Modern terminal experience:

```powershell
# Install Windows Terminal via winget
winget install Microsoft.WindowsTerminal
```

## Quick Setup Script

Run this script to install common prerequisites:

```powershell
# Install common modules
$modules = @(
    'Microsoft.Graph',
    'Az',
    'ExchangeOnlineManagement',
    'MicrosoftTeams'
)

foreach ($module in $modules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing $module..." -ForegroundColor Cyan
        Install-Module $module -Scope CurrentUser -Force -AllowClobber
    } else {
        Write-Host "$module already installed" -ForegroundColor Green
    }
}

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

Write-Host "`nPrerequisites installation complete!" -ForegroundColor Green
```

## Script-Specific Requirements

Different categories have specific requirements:

| Category | Additional Requirements |
|----------|------------------------|
| **Azure Virtual Desktop** | Azure subscription, AVD host pool |
| **Intune Management** | Microsoft Intune license, Endpoint Manager access |
| **Security & Compliance** | Administrator rights, audit permissions |
| **Container Management** | Docker Desktop or Kubernetes cluster |
| **Database Scripts** | Database client tools (SQL Server, MySQL, etc.) |

## Verification Checklist

Before running scripts, verify:

- ✅ PowerShell 5.1+ installed (5.1 or 7.0+, prefer 7.0+)
- ✅ Execution policy set appropriately
- ✅ Required modules installed
- ✅ Proper permissions/credentials configured
- ✅ Network connectivity to cloud services (if applicable)
- ✅ Administrator privileges (if required)
- ✅ Windows Server 2016+ (or Windows 10/11)

## Troubleshooting

### Common Issues

**"Script cannot be loaded" error:**
- Check execution policy: `Get-ExecutionPolicy`
- Set to RemoteSigned: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`

**Module not found:**
- Install the module: `Install-Module <ModuleName> -Scope CurrentUser`
- Check installed modules: `Get-Module -ListAvailable`

**Authentication fails:**
- Verify credentials are current
- Check for MFA requirements
- Ensure proper permissions assigned

For more help, see the [Troubleshooting Guide](Troubleshooting) or contact support.

## Next Steps

Once prerequisites are met:

1. **[Getting Started](Getting-Started)** - Learn basic script usage
2. **[Script Catalog](Script-Catalog)** - Browse available scripts
3. **[Script Examples](Script-Examples)** - See detailed examples

## See Also

- [Getting Started](Getting-Started) - Onboarding guide
- [Script Catalog](Script-Catalog) - Browse all available scripts
- [FAQ](FAQ) - Common questions answered
- [Troubleshooting](Troubleshooting) - Solve common issues
- [Support Guide](https://github.com/Carme99/bug-free-umbrella/blob/main/SUPPORT.md) - Get help
- [Code of Conduct](https://github.com/Carme99/bug-free-umbrella/blob/main/CODE_OF_CONDUCT.md) - Community guidelines

---

**Last Updated:** 2026-03-03  
**Wiki Version:** 1.3.0  
**Status:** Current with v4.0.0 Release  
**Maintained by:** Carme99 with [Claude Code](https://claude.com/claude-code)