# Azure Virtual Desktop (AVD)

## Overview

This collection of PowerShell scripts streamlines the management and preparation of Azure Virtual Desktop environments, from preparing Windows golden images to publishing them as Azure Compute Gallery resources.

## Available Scripts

### 🚀 [New-AzureComputeGalleryImage.ps1](Azure-Compute-Gallery-Image-Builder)

**NEW!** A comprehensive, interactive tool for creating versioned Azure Compute Gallery images from gold VMs.

**Key Features:**
- 🎨 Beautiful interactive UI with ASCII art and progress bars
- ⚙️ Multiple configuration modes (interactive, config file, CLI)
- 🔄 Smart semantic versioning (major, minor, patch)
- 🛡️ Works with powered-on or powered-off source VMs
- 🧹 Automatic cleanup of temporary resources

**Quick Start:**
```powershell
.\New-AzureComputeGalleryImage.ps1 -Interactive
```

**[Full Documentation →](Azure-Compute-Gallery-Image-Builder)**

---

### 🔧 Remove-SysprepBlockers.ps1

A tool for detecting and removing AppX packages that block Windows Sysprep operations.

**Key Features:**
- Automatic detection of Sysprep blockers
- Interactive confirmation before removal
- Comprehensive logging and audit trails
- Safe whitelist for critical Windows components

**Quick Start:**
```powershell
.\Remove-SysprepBlockers.ps1
```

**Use Case:** Run this on your gold VM **before** capturing an image to ensure Sysprep will succeed.

## Typical AVD Image Pipeline

Here's how these scripts fit into a complete AVD image preparation workflow:

```
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: Prepare Gold VM                                         │
├─────────────────────────────────────────────────────────────────┤
│ • Install Windows updates                                       │
│ • Install applications (Office, Edge, LOB apps)                 │
│ • Configure Windows settings                                    │
│ • Optimize and clean up                                         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: Clean Sysprep Blockers                                  │
├─────────────────────────────────────────────────────────────────┤
│ Run: .\Remove-SysprepBlockers.ps1                               │
│                                                                  │
│ • Scans for problematic AppX packages                           │
│ • Removes blockers that prevent Sysprep                         │
│ • Validates system is ready                                     │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: Create ACG Image                                        │
├─────────────────────────────────────────────────────────────────┤
│ Run: .\New-AzureComputeGalleryImage.ps1 -Interactive            │
│                                                                  │
│ • Snapshots the gold VM OS disk                                 │
│ • Creates temporary clone VM                                    │
│ • Runs Sysprep to generalize                                    │
│ • Publishes versioned image to gallery                          │
│ • Cleans up all temporary resources                             │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 4: Deploy AVD Session Hosts                                │
├─────────────────────────────────────────────────────────────────┤
│ • Use the gallery image to create AVD session hosts             │
│ • Deploy via portal, ARM templates, or Bicep                    │
│ • Configure host pool settings                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Links

| Resource | Description |
|----------|-------------|
| [ACG Image Builder Guide](Azure-Compute-Gallery-Image-Builder) | Complete documentation for New-AzureComputeGalleryImage.ps1 |
| [AVD Scripts Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/cloud/azure/avd) | Source code and scripts |
| [Troubleshooting](Troubleshooting) | Common issues and solutions |

## Common Workflows

### Monthly Patching Workflow

```powershell
# 1. Update gold VM with patches
# ... apply Windows updates, app updates ...

# 2. Clean up blockers
.\Remove-SysprepBlockers.ps1

# 3. Create new minor version image
.\New-AzureComputeGalleryImage.ps1 `
    -ConfigFile ".\config\production.json" `
    -VersioningStrategy "Minor"

# 4. Test the new image
# ... deploy test session hosts ...

# 5. Update production host pools to use new image
# ... update host pool configuration ...
```

### New OS Version Workflow

```powershell
# 1. Build new gold VM with new OS (e.g., Windows 11 24H2)
# ... install apps, configure settings ...

# 2. Clean up blockers
.\Remove-SysprepBlockers.ps1

# 3. Create new major version image
.\New-AzureComputeGalleryImage.ps1 `
    -ConfigFile ".\config\win11-24h2.json" `
    -VersioningStrategy "Major"

# 4. Pilot with test users
# ... deploy to pilot host pool ...

# 5. Gradual rollout to production
# ... update production host pools ...
```

## Best Practices

### Gold VM Preparation

1. ✅ Use a clean Windows installation
2. ✅ Install all required applications
3. ✅ Apply all Windows updates
4. ✅ Configure Windows settings (timezone, language, policies)
5. ✅ Optimize for VDI (disable services, remove bloat)
6. ✅ Clean temp files and user profiles
7. ✅ Run `Remove-SysprepBlockers.ps1`
8. ✅ Take a snapshot backup (optional, for rollback)

### Image Versioning Strategy

Choose a consistent versioning approach:

| Strategy | When to Use | Example |
|----------|-------------|---------|
| **Major** | New OS versions, significant changes | 1.0.0 → 2.0.0 |
| **Minor** | Monthly patches, app updates | 1.0.0 → 1.1.0 |
| **Patch** | Hotfixes, small updates | 1.1.0 → 1.1.1 |

### Configuration Management

Store configuration files in source control:

```
config/
├── windows10-ltsc-2021.json
├── windows11-22h2.json
├── windows11-23h2.json
└── windows11-24h2.json
```

This provides:
- Version history
- Easy replication
- Disaster recovery
- Audit trail

### Testing Before Production

1. Create image in dev/test gallery first
2. Deploy test session hosts
3. Validate applications work
4. Test user experience
5. Only then promote to production gallery

## Prerequisites

### Azure Resources

- Azure Compute Gallery (create if needed)
- Gallery Image Definition (matching OS type)
- Virtual Network with internet access
- RBAC permissions (Contributor on relevant RGs)

### PowerShell Modules

```powershell
# Install Az modules
Install-Module -Name Az -Repository PSGallery -Force

# Import modules
Import-Module Az.Accounts
Import-Module Az.Compute
Import-Module Az.Network
```

### Network Requirements

- Outbound HTTPS (443) to Azure endpoints
- Outbound access to 168.63.129.16 (Azure platform IP)
- No restrictive NSG rules blocking VM Guest Agent

## Troubleshooting

### Sysprep Fails

**Solution:** Run `Remove-SysprepBlockers.ps1` first to clean up problematic AppX packages.

### VM Agent Not Ready

**Cause:** Network connectivity issues.

**Solutions:**
- Check NSG rules (must allow outbound 443 and 168.63.129.16)
- Verify subnet has internet access
- Check Azure Firewall/NVA rules

### Gallery Image Version Already Exists

**Cause:** Version N.0.0 already exists.

**Solutions:**
- Use different versioning strategy (Minor or Patch)
- Delete old version if not in use
- Wait for script to calculate next version automatically

## Additional Resources

- [Azure Compute Gallery Documentation](https://docs.microsoft.com/azure/virtual-machines/shared-image-galleries)
- [AVD Image Management Best Practices](https://docs.microsoft.com/azure/virtual-desktop/set-up-customize-master-image)
- [Sysprep Overview](https://docs.microsoft.com/windows-hardware/manufacture/desktop/sysprep--generalize--a-windows-installation)

## Support

For issues or questions:
1. Check the [Troubleshooting](Troubleshooting) guide
2. Review script-specific documentation
3. Check error messages and logs
4. Open an issue in the repository

---

**Last Updated:** 2025-01-15
