# Azure Compute Gallery Image Builder

![Tier](https://img.shields.io/badge/Tier-3-red) ![Category](https://img.shields.io/badge/Category-Advanced-ff69b4) ![Status](https://img.shields.io/badge/Status-New-orange)

## Overview

The **New-AzureComputeGalleryImage.ps1** script is a comprehensive, interactive tool for creating versioned Azure Compute Gallery (ACG) images from gold VMs. It automates the entire end-to-end workflow of cloning, sysprep'ing, and publishing Windows images to an Azure Compute Gallery.

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage Modes](#usage-modes)
- [Configuration](#configuration)
- [Advanced Topics](#advanced-topics)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [FAQ](#faq)
- [See Also](#see-also)

## Features

### 🎨 Beautiful User Experience
- ASCII art banner and colorful console output
- Real-time progress bars for long-running operations
- Clear step-by-step progress tracking (Step X of 12)
- Success/warning/error indicators with emoji

### ⚙️ Flexible Configuration
- **Interactive Mode**: Guided wizard for first-time users
- **Config File Mode**: JSON configuration files for reproducible deployments
- **CLI Mode**: Full command-line parameter support for automation

### 🔄 Smart Versioning
Automatic semantic versioning with three strategies:
- **Major** (N.0.0): For significant changes, OS upgrades
- **Minor** (N.M.0): For feature additions, application updates
- **Patch** (N.M.P): For bug fixes, minor updates

### 🛡️ Production Ready
- Works with powered-on or powered-off source VMs
- Comprehensive validation at every step
- Automatic cleanup of temporary resources
- Robust error handling and recovery
- Non-destructive (snapshots source VM, never modifies it)

## Quick Start

### First-Time Users (Interactive Mode)

```powershell
# Navigate to the script location
cd /path/to/bug-free-umbrella/AzureVirtualDesktop

# Run in interactive mode
.\New-AzureComputeGalleryImage.ps1 -Interactive
```

Follow the prompts to provide:
- Azure tenant and subscription IDs
- Source VM details
- Gallery configuration
- Network settings

### Experienced Users (Config File)

```powershell
# Generate a config template
.\New-AzureComputeGalleryImage.ps1 -GenerateConfig -ConfigFile ".\my-environment.json"

# Edit the config file with your details
notepad .\my-environment.json

# Run with config file
.\New-AzureComputeGalleryImage.ps1 -ConfigFile ".\my-environment.json"
```

## Prerequisites

### Azure Resources

| Resource | Requirement | Notes |
|----------|-------------|-------|
| **Azure Compute Gallery** | Must exist | Create if needed: `New-AzGallery` |
| **Gallery Image Definition** | Must exist | Must match OS type and Hyper-V generation |
| **Virtual Network** | Must exist | For temporary VM placement |
| **Subnet** | Must exist | Must allow outbound internet access |
| **Source VM** | Must exist | Your "gold" image VM |

### RBAC Permissions

Your Azure account needs:
- **Read** access to source VM and its resource group
- **Contributor** on a resource group where temporary resources can be created
- **Contributor** on the gallery resource group

### PowerShell Modules

Install the Azure PowerShell modules:

```powershell
# Install Az module (if not already installed)
Install-Module -Name Az -Repository PSGallery -Force -AllowClobber

# Import required modules
Import-Module Az.Accounts
Import-Module Az.Compute
Import-Module Az.Network
Import-Module Az.Resources
```

Verify installation:

```powershell
Get-Module -ListAvailable Az.*
```

### Network Requirements

The subnet used for the temporary VM must allow:
- ✅ Outbound HTTPS (TCP 443) to Azure public endpoints
- ✅ Outbound access to Azure platform IP: **168.63.129.16**
- ❌ No overly restrictive NSG rules blocking VM Guest Agent

### Source VM Requirements

- ✅ Must have Azure Windows Guest Agent installed (standard on Azure VMs)
- ✅ Can be powered on or off (script works either way)
- ✅ OS disk should be in a healthy, bootable state
- ✅ Recommended: Run `Remove-SysprepBlockers.ps1` first to clean up AppX packages

## Installation

### Clone the Repository

```bash
git clone https://github.com/YourOrg/bug-free-umbrella.git
cd bug-free-umbrella/AzureVirtualDesktop
```

### Verify Script Availability

```powershell
# Check the script is present
Test-Path .\New-AzureComputeGalleryImage.ps1

# View help
Get-Help .\New-AzureComputeGalleryImage.ps1 -Detailed
```

## Usage Modes

### Mode 1: Interactive Wizard

**Best for:** First-time users, ad-hoc image creation

```powershell
.\New-AzureComputeGalleryImage.ps1 -Interactive
```

**What happens:**
1. Displays ASCII art banner
2. Prompts for all required configuration
3. Offers to save configuration for future use
4. Displays configuration summary
5. Asks for confirmation
6. Executes the image creation workflow

**Advantages:**
- No need to remember parameter names
- Guided experience with helpful prompts
- Option to save configuration for reuse

### Mode 2: Configuration File

**Best for:** Production environments, repeatable deployments, CI/CD

#### Step 1: Generate Template

```powershell
.\New-AzureComputeGalleryImage.ps1 -GenerateConfig -ConfigFile ".\production.json"
```

#### Step 2: Edit Configuration

Edit `production.json`:

```json
{
  "TenantId": "12345678-1234-1234-1234-123456789012",
  "SubscriptionId": "87654321-4321-4321-4321-210987654321",
  "Location": "East US",
  "SourceVM": {
    "Name": "WIN11-GOLD-2024",
    "ResourceGroup": "rg-golden-images"
  },
  "Gallery": {
    "ResourceGroup": "rg-shared-images",
    "Name": "ACG_Production",
    "ImageDefinitionName": "Windows11-23H2-Enterprise"
  },
  "Network": {
    "VNetName": "vnet-production",
    "VNetResourceGroup": "rg-networking",
    "SubnetName": "snet-image-builders"
  },
  "TempVM": {
    "Size": "Standard_D4s_v3"
  },
  "Options": {
    "VersioningStrategy": "Major",
    "SkipAgentCheck": false,
    "SkipCleanup": false
  }
}
```

#### Step 3: Run with Config

```powershell
.\New-AzureComputeGalleryImage.ps1 -ConfigFile ".\production.json"
```

**Advantages:**
- Reproducible deployments
- Version control friendly
- Easy to maintain multiple environments
- No interactive prompts needed

### Mode 3: Command-Line Parameters

**Best for:** Automation, scripts, dynamic parameter generation

```powershell
.\New-AzureComputeGalleryImage.ps1 `
    -TenantId "12345678-1234-1234-1234-123456789012" `
    -SubscriptionId "87654321-4321-4321-4321-210987654321" `
    -Location "East US" `
    -SourceVMName "WIN11-GOLD" `
    -SourceVMResourceGroup "rg-images" `
    -GalleryName "MyGallery" `
    -GalleryResourceGroup "rg-images" `
    -ImageDefinitionName "Windows11-Enterprise" `
    -VNetName "vnet-prod" `
    -VNetResourceGroup "rg-network" `
    -SubnetName "snet-default" `
    -VMSize "Standard_D2s_v3" `
    -VersioningStrategy "Minor" `
    -Force
```

**Advantages:**
- Full control via parameters
- Can be called from other scripts
- Suitable for dynamic environments

## Configuration

### Complete Parameter Reference

| Parameter | Type | Required | Description | Default |
|-----------|------|----------|-------------|---------|
| `-ConfigFile` | String | No | Path to JSON configuration file | - |
| `-GenerateConfig` | Switch | No | Generate template configuration file | - |
| `-Interactive` | Switch | No | Run interactive configuration wizard | Auto if no config |
| `-TenantId` | String | Yes* | Azure AD Tenant ID | - |
| `-SubscriptionId` | String | Yes* | Azure Subscription ID | - |
| `-Location` | String | Yes* | Azure region | - |
| `-SourceVMName` | String | Yes* | Name of source VM | - |
| `-SourceVMResourceGroup` | String | Yes* | Resource group containing source VM | - |
| `-GalleryResourceGroup` | String | Yes* | Resource group for gallery | - |
| `-GalleryName` | String | Yes* | Azure Compute Gallery name | - |
| `-ImageDefinitionName` | String | Yes* | Image definition name | - |
| `-VMSize` | String | No | VM size for temporary clone | Standard_D2s_v3 |
| `-VNetName` | String | Yes* | Virtual network name | - |
| `-VNetResourceGroup` | String | Yes* | VNet resource group | - |
| `-SubnetName` | String | Yes* | Subnet name | - |
| `-VersioningStrategy` | String | No | Major, Minor, or Patch | Major |
| `-SkipAgentCheck` | Switch | No | Skip guest agent validation | False |
| `-SkipCleanup` | Switch | No | Keep temp resources | False |
| `-Force` | Switch | No | Run without confirmation | False |

*Required when using explicit parameter mode (not required for Interactive or ConfigFile modes)

### Versioning Strategies Explained

#### Major Versioning (Default)

```powershell
-VersioningStrategy "Major"
```

- Increments the first digit
- Resets minor and patch to 0
- **Use for:** OS upgrades, significant changes, new baseline images
- **Example:** 1.0.0 → 2.0.0 → 3.0.0

#### Minor Versioning

```powershell
-VersioningStrategy "Minor"
```

- Increments the second digit
- Resets patch to 0
- **Use for:** Application updates, feature additions, monthly patches
- **Example:** 1.0.0 → 1.1.0 → 1.2.0

#### Patch Versioning

```powershell
-VersioningStrategy "Patch"
```

- Increments the third digit
- **Use for:** Bug fixes, small updates, hotfixes
- **Example:** 1.2.0 → 1.2.1 → 1.2.2

### VM Size Selection

Choose an appropriate VM size for the temporary clone VM based on your needs:

| VM Size | vCPUs | RAM | Use Case | Approx. Cost/Hour |
|---------|-------|-----|----------|-------------------|
| Standard_D2s_v3 | 2 | 8 GB | Most scenarios | ~$0.10 |
| Standard_D4s_v3 | 4 | 16 GB | Faster Sysprep | ~$0.20 |
| Standard_D2as_v5 | 2 | 8 GB | AMD-based, cost-effective | ~$0.08 |
| Standard_D2as_v6 | 2 | 8 GB | Latest generation | ~$0.08 |

**Recommendation:** Start with Standard_D2s_v3 unless you experience slow Sysprep operations.

## Advanced Topics

### Integration with CI/CD Pipelines

#### Azure DevOps Pipeline

```yaml
# azure-pipelines.yml
trigger:
  - main

pool:
  vmImage: 'windows-latest'

steps:
- task: AzurePowerShell@5
  displayName: 'Create ACG Image'
  inputs:
    azureSubscription: 'YourServiceConnection'
    scriptType: 'FilePath'
    scriptPath: '$(System.DefaultWorkingDirectory)/AzureVirtualDesktop/New-AzureComputeGalleryImage.ps1'
    scriptArguments: >
      -ConfigFile "$(System.DefaultWorkingDirectory)/config/production.json"
      -Force
      -VersioningStrategy "Minor"
    azurePowerShellVersion: 'LatestVersion'
    pwsh: true

- task: PublishBuildArtifacts@1
  inputs:
    PathtoPublish: '$(System.DefaultWorkingDirectory)/config'
    ArtifactName: 'config'
```

#### GitHub Actions

```yaml
# .github/workflows/create-acg-image.yml
name: Create ACG Image

on:
  workflow_dispatch:
    inputs:
      versioningStrategy:
        description: 'Versioning strategy (Major, Minor, Patch)'
        required: true
        default: 'Major'
        type: choice
        options:
          - Major
          - Minor
          - Patch

jobs:
  create-image:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3

      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Create ACG Image
        shell: pwsh
        run: |
          ./AzureVirtualDesktop/New-AzureComputeGalleryImage.ps1 `
            -ConfigFile "./config/production.json" `
            -VersioningStrategy "${{ github.event.inputs.versioningStrategy }}" `
            -Force
```

### Scheduled Monthly Image Builds

Create a scheduled task or Azure Automation runbook to build images monthly:

```powershell
# Register a scheduled task (Windows)
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
    -Argument '-File "C:\Scripts\New-AzureComputeGalleryImage.ps1" -ConfigFile "C:\Config\monthly.json" -Force'

$trigger = New-ScheduledTaskTrigger -Monthly -At 2am -DaysOfWeek Sunday

Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "MonthlyACGImageBuild"
```

### Multi-Environment Configuration

Maintain separate configs for different environments:

```
config/
├── dev.json
├── test.json
├── staging.json
└── production.json
```

```powershell
# Build for different environments
.\New-AzureComputeGalleryImage.ps1 -ConfigFile ".\config\dev.json"
.\New-AzureComputeGalleryImage.ps1 -ConfigFile ".\config\production.json"
```

### Custom Temporary Resource Group Naming

The script automatically generates unique temporary RG names:

```
Format: acg-temp-YYYYMMDD-HHmmss-XXXX
Example: acg-temp-20250130-143022-7845
```

This ensures:
- No naming conflicts
- Easy identification of temporary resources
- Timestamped for audit purposes

## Troubleshooting

### Common Issues and Solutions

#### Issue: "Gallery not found"

**Cause:** Azure Compute Gallery doesn't exist.

**Solution:**

```powershell
New-AzGallery `
    -ResourceGroupName "rg-images" `
    -Name "MyGallery" `
    -Location "East US" `
    -Description "Production image gallery"
```

#### Issue: "Image definition not found"

**Cause:** Image definition doesn't exist in the gallery.

**Solution:**

```powershell
$params = @{
    GalleryName = 'MyGallery'
    ResourceGroupName = 'rg-images'
    Location = 'East US'
    Name = 'Windows11-Enterprise'
    OsState = 'Generalized'
    OsType = 'Windows'
    Publisher = 'MyCompany'
    Offer = 'Windows11'
    Sku = 'Enterprise'
    HyperVGeneration = 'V2'  # Use V1 for Gen1 VMs
}
New-AzGalleryImageDefinition @params
```

#### Issue: "VM Agent not ready"

**Cause:** Network connectivity issues or VM agent not running.

**Solutions:**

1. **Check Network Security Group (NSG) rules:**
   ```powershell
   # Verify outbound rules allow 443 and 168.63.129.16
   Get-AzNetworkSecurityGroup -Name "MyNSG" -ResourceGroupName "rg-network" |
       Select-Object -ExpandProperty SecurityRules
   ```

2. **Check if using Azure Firewall or NVA:**
   - Ensure traffic to Azure platform IP (168.63.129.16) is allowed
   - Ensure outbound HTTPS (443) to *.azure.com is allowed

3. **Use a different subnet:**
   - Try a subnet with less restrictive rules for the temporary VM

#### Issue: "Sysprep failed"

**Cause:** AppX packages blocking Sysprep, or VM not in generalized state.

**Solutions:**

1. **Run Sysprep blocker removal on gold VM:**
   ```powershell
   .\Remove-SysprepBlockers.ps1
   ```

2. **Check Sysprep logs (manual investigation):**
   - RDP to gold VM
   - Check: `C:\Windows\System32\Sysprep\Panther\setuperr.log`

3. **Ensure VM is not domain-joined** (can cause Sysprep issues)

#### Issue: "Authentication failed"

**Cause:** Not logged in or wrong subscription context.

**Solutions:**

```powershell
# Login to Azure
Connect-AzAccount

# List subscriptions
Get-AzSubscription

# Set correct subscription
Set-AzContext -SubscriptionId "your-subscription-id"

# Verify context
Get-AzContext
```

#### Issue: "Insufficient permissions"

**Cause:** RBAC permissions missing.

**Solutions:**

Check your permissions:

```powershell
# Check role assignments
Get-AzRoleAssignment -SignInName "your-email@domain.com"
```

Required roles:
- Contributor on source VM resource group (or Reader)
- Contributor on gallery resource group
- Contributor on a resource group for temp resources (or ability to create RGs)

#### Issue: Script hangs during "Creating gallery image version"

**Cause:** Gallery image version creation is a long-running operation.

**Solutions:**
- Be patient! This step can take 10-20 minutes depending on image size
- The script is not frozen; Azure is replicating the image
- Check Azure Portal → Galleries → Image Definition → Versions for progress

### Debug Mode

For deep troubleshooting, run with verbose output:

```powershell
$VerbosePreference = 'Continue'
.\New-AzureComputeGalleryImage.ps1 -ConfigFile ".\config.json" -SkipCleanup
```

The `-SkipCleanup` flag keeps temporary resources for investigation.

## Best Practices

### 1. Gold VM Preparation Checklist

Before capturing an image, ensure your gold VM:

- ✅ Has all required applications installed
- ✅ Has all Windows updates applied
- ✅ Has AppX packages cleaned (`Remove-SysprepBlockers.ps1`)
- ✅ Has temp files cleaned (`Disk Cleanup`, CCleaner, etc.)
- ✅ Has user profiles removed (if applicable)
- ✅ Has page file reset to default
- ✅ Is not domain-joined (or will be removed during Sysprep)
- ✅ Has desired Windows settings configured

### 2. Configuration Management

```powershell
# Store configs in version control
git add config/*.json
git commit -m "Update production image config"

# Use descriptive names
config/
├── windows11-23h2-production.json
├── windows11-22h2-test.json
└── windows10-ltsc-legacy.json
```

### 3. Versioning Strategy

Choose one strategy and stick with it:

- **Monthly patches:** Use Minor versioning (1.0.0 → 1.1.0 → 1.2.0)
- **Quarterly updates:** Use Major versioning (1.0.0 → 2.0.0 → 3.0.0)
- **Hotfixes:** Use Patch versioning (1.2.0 → 1.2.1)

### 4. Testing Workflow

```powershell
# 1. Test in dev
.\New-AzureComputeGalleryImage.ps1 -ConfigFile ".\config\dev.json"

# 2. Deploy test VMs from the new version
# ... test VMs ...

# 3. If successful, promote to production
.\New-AzureComputeGalleryImage.ps1 -ConfigFile ".\config\production.json"
```

### 5. Network Isolation

Use a dedicated subnet for image building:
- Isolated from production workloads
- Minimal NSG rules (allow outbound internet)
- No forced tunneling via NVA (can break VM agent)

### 6. Cost Optimization

- Use the smallest VM size that works (Standard_D2s_v3)
- Ensure `-SkipCleanup` is NOT used in production
- Schedule image builds during off-hours
- Use spot instances for temp VM (not yet supported, but could be added)

### 7. Audit and Compliance

Maintain logs:
- Config files in source control
- Image versions documented (what changed)
- Audit trail of who created images and when

Example documentation:

```markdown
# Image Version History

## Version 12.0.0
- Date: 2025-01-30
- Created by: john.doe@company.com
- Changes: Windows 11 23H2 + January 2025 patches
- Config: config/windows11-23h2-jan2025.json
```

## FAQ

### Q: Can this work with Linux VMs?

**A:** Not currently. The script is designed for Windows VMs (uses Sysprep). For Linux, you would use `waagent -deprovision` instead.

### Q: Does the source VM need to be powered on?

**A:** No! The script works with both powered-on and powered-off source VMs. It only snapshots the disk.

### Q: Will this modify my gold VM?

**A:** No. The script creates a snapshot of the OS disk, leaving your gold VM completely untouched.

### Q: How long does the process take?

**A:** Typically 30-60 minutes:
- Snapshot: 5-10 min
- VM creation: 5-10 min
- VM Agent ready: 2-5 min
- Sysprep: 5-10 min
- Gallery publish: 10-30 min

### Q: Can I run multiple instances concurrently?

**A:** Yes, as long as you're creating different image versions. The unique temporary RG names prevent conflicts.

### Q: What if I need to cancel mid-execution?

**A:** Press Ctrl+C. Then manually clean up the temporary resource group:

```powershell
Remove-AzResourceGroup -Name "acg-temp-YYYYMMDD-HHmmss-XXXX" -Force
```

### Q: Can I customize the Sysprep command?

**A:** The Sysprep command is hardcoded as `/generalize /oobe /mode:vm /quit`. To customize, edit the `$sysprepScript` variable in the script.

### Q: Does this support Hyper-V Generation 1 and 2?

**A:** Yes, both. The script automatically detects the Hyper-V generation from the source VM and creates the image accordingly.

### Q: Can I replicate images to multiple regions?

**A:** Not directly in this script, but you can configure replication in the gallery image version after creation or modify the script to add `-TargetRegion` parameters to `New-AzGalleryImageVersion`.

### Q: What happens if the script fails partway through?

**A:** The script uses `$ErrorActionPreference = 'Stop'` to fail fast. Temporary resources will remain. You can:
1. Investigate the issue using the temp resources
2. Delete the temp RG manually
3. Fix the issue and rerun

### Q: Can I use this with Azure Government or other sovereign clouds?

**A:** Yes, but you need to connect to the correct Azure environment first:

```powershell
Connect-AzAccount -Environment AzureUSGovernment
```

## Additional Resources

- [Azure Compute Gallery Documentation](https://docs.microsoft.com/azure/virtual-machines/shared-image-galleries)
- [Sysprep Overview](https://docs.microsoft.com/windows-hardware/manufacture/desktop/sysprep--generalize--a-windows-installation)
- [Azure VM Guest Agent](https://docs.microsoft.com/azure/virtual-machines/extensions/agent-windows)
- [Remove-SysprepBlockers.ps1 Script](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/cloud/azure/avd/Remove-SysprepBlockers.ps1)

## Support

For issues or questions:
1. Check this wiki page
2. Review [Troubleshooting](#troubleshooting) section
3. Check script logs and error messages
4. Open an issue in the repository

---

## See Also

- [Azure Virtual Desktop](Azure-Virtual-Desktop) - AVD management and optimization
- [Cloud Infrastructure](Cloud-Infrastructure) - Azure and cloud resources
- [Advanced-Scripting-Patterns](Advanced-Scripting-Patterns) - Expert scripting techniques
- [Performance-Tuning](Performance-Tuning) - Optimization strategies
- [Prerequisites](Prerequisites) - Required modules and setup
- [Support Guide](https://github.com/Carme99/bug-free-umbrella/blob/main/SUPPORT.md) - Get help

---

**Last Updated:** 2026-03-03  
**Wiki Version:** 1.3.0  
**Status:** Current with v4.0.0 Release  
**Maintained by:** Carme99 with [Claude Code](https://claude.com/claude-code)
