# Prerequisites

Before using Bug-Free Umbrella scripts, ensure you have the following prerequisites installed and configured.

## System Requirements

### Operating System
- **Windows 10/11** or **Windows Server 2016+** (for most scripts)
- **Linux** (for scripts in `scripts/infrastructure/linux/`)
- **macOS** (limited support, mainly for cross-platform tools)

### PowerShell Version
- **PowerShell 5.1** (minimum for most scripts)
- **PowerShell 7+** (recommended for best compatibility)

Check your PowerShell version:
```powershell
$PSVersionTable.PSVersion
```

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
- ✅ PowerShell 5.1+ installed
- ✅ Execution policy set appropriately
- ✅ Required modules installed
- ✅ Proper permissions/credentials configured
- ✅ Network connectivity to cloud services (if applicable)
- ✅ Administrator privileges (if required)

## Next Steps

Once prerequisites are met:
1. **[Getting Started](Getting-Started)** - Learn basic script usage
2. **[Script Catalog](Script-Catalog)** - Browse available scripts
3. **[Script Examples](Script-Examples)** - See detailed examples

## Troubleshooting

Common issues:

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

For more help, see **[Troubleshooting](Troubleshooting)**.

---

**Last Updated:** 2025-12-31
**Version:** 1.0.0
