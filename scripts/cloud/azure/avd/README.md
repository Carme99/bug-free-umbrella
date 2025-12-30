# Azure Virtual Desktop Scripts

This folder contains PowerShell scripts for managing and preparing Azure Virtual Desktop (AVD) environments.

## Overview

These scripts streamline the AVD image lifecycle, from preparing Windows images to publishing them as Azure Compute Gallery resources. They feature interactive modes, comprehensive logging, and production-ready error handling.

## Scripts

### New-AzureComputeGalleryImage.ps1

🚀 **NEW!** A comprehensive, interactive tool for creating Azure Compute Gallery images from gold VMs.

#### Overview

This script automates the complete end-to-end workflow for creating versioned Azure Compute Gallery images from a source "gold" VM. It handles everything from snapshotting the source disk to publishing the final image version, with a beautiful interactive UI featuring ASCII art, colorful progress indicators, and detailed status updates.

**Perfect for:** AVD administrators, DevOps engineers, and anyone managing Windows golden images at scale.

#### Key Features

- 🎨 **Beautiful Interactive UI**: ASCII art banner, colorful outputs, and real-time progress bars
- ⚙️ **Flexible Configuration**: Interactive wizard, JSON config files, or command-line parameters
- 🔄 **Smart Versioning**: Automatic semantic versioning (major, minor, or patch increments)
- 🛡️ **Safe by Design**: Works with powered-off or powered-on source VMs
- 📊 **Comprehensive Logging**: Detailed progress tracking and error reporting
- 🧹 **Auto Cleanup**: Automatically removes all temporary resources
- 🔧 **Production Ready**: Robust error handling and validation at every step

#### What It Does

The script performs a complete image publishing workflow:

1. ✓ Authenticates to Azure with your tenant and subscription
2. ✓ Validates source VM, gallery, and network configuration
3. ✓ Calculates the next semantic version automatically
4. ✓ Creates a snapshot of the source VM's OS disk (non-destructive)
5. ✓ Creates a managed disk from the snapshot in a temporary resource group
6. ✓ Provisions a temporary clone VM from the disk
7. ✓ Waits for the Azure VM Guest Agent to be ready
8. ✓ Runs Sysprep to generalize the VM
9. ✓ Creates a managed image from the generalized VM
10. ✓ Publishes the image to your Azure Compute Gallery
11. ✓ Cleans up all temporary resources
12. ✓ Displays a beautiful success summary

#### Usage Modes

##### 1. Interactive Mode (Recommended for First-Time Users)

The easiest way to get started! Just run the script and follow the prompts:

```powershell
.\New-AzureComputeGalleryImage.ps1 -Interactive
```

You'll be guided through a step-by-step wizard that collects:
- Azure tenant and subscription details
- Source VM information
- Gallery and image definition names
- Network configuration
- Versioning preferences

**Bonus:** Save your configuration for future use!

##### 2. Configuration File Mode (Recommended for Production)

Generate a template configuration file:

```powershell
.\New-AzureComputeGalleryImage.ps1 -GenerateConfig -ConfigFile ".\my-environment.json"
```

Edit the JSON file with your environment details:

```json
{
  "TenantId": "your-tenant-id",
  "SubscriptionId": "your-subscription-id",
  "Location": "East US",
  "SourceVM": {
    "Name": "WIN11-GOLD",
    "ResourceGroup": "rg-images"
  },
  "Gallery": {
    "ResourceGroup": "rg-images",
    "Name": "MyComputeGallery",
    "ImageDefinitionName": "Windows11-Enterprise"
  },
  "Network": {
    "VNetName": "vnet-prod",
    "VNetResourceGroup": "rg-network",
    "SubnetName": "snet-images"
  },
  "TempVM": {
    "Size": "Standard_D2s_v3"
  },
  "Options": {
    "VersioningStrategy": "Major",
    "SkipAgentCheck": false,
    "SkipCleanup": false
  }
}
```

Then run using the config file:

```powershell
.\New-AzureComputeGalleryImage.ps1 -ConfigFile ".\my-environment.json"
```

##### 3. Command-Line Parameters (For Automation)

For CI/CD pipelines and automation:

```powershell
.\New-AzureComputeGalleryImage.ps1 `
    -TenantId "your-tenant-id" `
    -SubscriptionId "your-subscription-id" `
    -Location "East US" `
    -SourceVMName "WIN11-GOLD" `
    -SourceVMResourceGroup "rg-images" `
    -GalleryName "MyGallery" `
    -GalleryResourceGroup "rg-images" `
    -ImageDefinitionName "Windows11-Enterprise" `
    -VNetName "vnet-prod" `
    -VNetResourceGroup "rg-network" `
    -SubnetName "snet-images" `
    -VMSize "Standard_D2s_v3" `
    -VersioningStrategy "Major" `
    -Force
```

#### Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `-ConfigFile` | String | Path to JSON configuration file | - |
| `-GenerateConfig` | Switch | Generate template configuration file | - |
| `-Interactive` | Switch | Run interactive configuration wizard | Default if no config |
| `-TenantId` | String | Azure AD Tenant ID | - |
| `-SubscriptionId` | String | Azure Subscription ID | - |
| `-Location` | String | Azure region (e.g., "East US", "UK South") | - |
| `-SourceVMName` | String | Name of the source/gold VM | - |
| `-SourceVMResourceGroup` | String | Resource group containing source VM | - |
| `-GalleryResourceGroup` | String | Resource group for the gallery | - |
| `-GalleryName` | String | Azure Compute Gallery name | - |
| `-ImageDefinitionName` | String | Image definition name in gallery | - |
| `-VMSize` | String | VM size for temporary clone | Standard_D2s_v3 |
| `-VNetName` | String | Virtual network name | - |
| `-VNetResourceGroup` | String | VNet resource group | - |
| `-SubnetName` | String | Subnet name within VNet | - |
| `-VersioningStrategy` | String | Major, Minor, or Patch | Major |
| `-SkipAgentCheck` | Switch | Skip guest agent validation | False |
| `-SkipCleanup` | Switch | Keep temp resources for debugging | False |
| `-Force` | Switch | Run without confirmation prompts | False |

#### Versioning Strategies

The script supports semantic versioning with three strategies:

| Strategy | Behavior | Use Case | Example |
|----------|----------|----------|---------|
| **Major** | Increments first digit, resets others to 0 | Significant changes, new OS versions | 1.0.0 → 2.0.0 |
| **Minor** | Increments second digit, resets patch to 0 | Feature additions, app updates | 1.2.0 → 1.3.0 |
| **Patch** | Increments third digit | Bug fixes, minor updates | 1.2.3 → 1.2.4 |

#### Requirements

**Azure Resources:**
- Azure Compute Gallery (must exist)
- Gallery Image Definition (must exist, matching OS type and Hyper-V generation)
- Virtual Network and Subnet with outbound internet access
- Sufficient RBAC permissions:
  - Read access to source VM and its resource group
  - Contributor on a resource group where temp resources can be created
  - Contributor on the gallery resource group

**PowerShell Modules:**
- Az.Accounts
- Az.Compute
- Az.Network
- Az.Resources

Install with:
```powershell
Install-Module -Name Az -Repository PSGallery -Force
```

**Network Requirements:**
- Outbound HTTPS (443) to Azure public endpoints
- Outbound access to Azure platform IP: 168.63.129.16
- No overly restrictive NSG rules that block VM Guest Agent

**Source VM Requirements:**
- Must have Azure Windows Guest Agent installed (standard on Azure VMs)
- Can be powered on or off (script works either way!)
- OS disk should be in a healthy state

#### Example Workflows

##### Workflow 1: First-Time Setup

```powershell
# Step 1: Run interactive mode
.\New-AzureComputeGalleryImage.ps1 -Interactive

# Step 2: Follow the prompts and save your configuration
# Step 3: Confirm and watch the magic happen!
```

##### Workflow 2: Monthly Patching Cycle

```powershell
# Update your gold VM with patches
# ...

# Generate a new minor version image
.\New-AzureComputeGalleryImage.ps1 `
    -ConfigFile ".\prod-config.json" `
    -VersioningStrategy "Minor"
```

##### Workflow 3: CI/CD Pipeline

```yaml
# Azure DevOps Pipeline example
- task: AzurePowerShell@5
  inputs:
    azureSubscription: 'YourServiceConnection'
    scriptType: 'FilePath'
    scriptPath: '$(System.DefaultWorkingDirectory)/New-AzureComputeGalleryImage.ps1'
    scriptArguments: '-ConfigFile "$(System.DefaultWorkingDirectory)/config.json" -Force'
    azurePowerShellVersion: 'LatestVersion'
```

#### Output and Logs

The script provides rich, colorful console output with:
- ✓ Success indicators in green
- ℹ Informational messages in blue
- ⚠ Warnings in yellow
- ✗ Errors in red
- Real-time progress bars for long-running operations
- Step-by-step progress tracking (Step X of 12)

**Exit Codes:**
- `0`: Success - image created and published
- `1`: Failure - check console output for details

#### Troubleshooting

##### "Gallery not found"

Ensure your Azure Compute Gallery exists. Create one with:

```powershell
New-AzGallery -ResourceGroupName "rg-images" -Name "MyGallery" -Location "East US"
```

##### "Image definition not found"

Create an image definition matching your source VM:

```powershell
$galleryImageDefinitionParams = @{
    GalleryName = 'MyGallery'
    ResourceGroupName = 'rg-images'
    Location = 'East US'
    Name = 'Windows11-Enterprise'
    OsState = 'Generalized'
    OsType = 'Windows'
    Publisher = 'MyCompany'
    Offer = 'Windows11'
    Sku = 'Enterprise'
    HyperVGeneration = 'V2'
}
New-AzGalleryImageDefinition @galleryImageDefinitionParams
```

##### "VM Agent not ready"

Check network connectivity:
- Ensure subnet allows outbound HTTPS (443)
- Verify NSG rules allow traffic to 168.63.129.16
- Check if Azure Firewall or NVA is blocking traffic

##### "Sysprep failed"

Consider running `Remove-SysprepBlockers.ps1` on your gold VM first to remove problematic AppX packages.

##### Authentication Issues

```powershell
# Ensure you're signed in
Connect-AzAccount

# Verify correct subscription context
Get-AzContext
Set-AzContext -SubscriptionId "your-subscription-id"
```

#### Best Practices

1. **Use Configuration Files**: Store configs in source control for reproducibility
2. **Test First**: Run against a test gallery before production
3. **Source VM Preparation**:
   - Install all applications
   - Run Windows Updates
   - Run `Remove-SysprepBlockers.ps1`
   - Clean up temp files
   - Then capture image
4. **Versioning**: Stick to one strategy consistently
5. **Network Isolation**: Use a dedicated subnet for image building
6. **Cleanup**: Don't use `-SkipCleanup` in production (costs money!)
7. **Documentation**: Comment your config files with environment details

#### Integration with AVD

Use the created gallery image in AVD host pools:

```powershell
# Create AVD session hosts from the gallery image
$imageReference = @{
    Id = "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Compute/galleries/{gallery}/images/{def}/versions/{version}"
}

# Use in New-AzWvdSessionHost or ARM/Bicep templates
```

#### What's Different from the Classic Approach?

**Before (Manual Process):**
1. Manually stop source VM
2. Navigate portal to create snapshot
3. Create disk from snapshot
4. Create VM from disk
5. Wait... is it ready yet?
6. RDP in and run Sysprep manually
7. Deallocate and generalize via portal
8. Create managed image
9. Navigate to gallery and create version
10. Remember to delete all the temp stuff!

**Now (This Script):**
1. Run script
2. ☕ Get coffee
3. ✨ Done!

#### Version History

- **v3.0** (Current): Interactive wizard, JSON configs, beautiful UI, flexible versioning
- **v2.0**: Added parameter support and basic automation
- **v1.0**: Original hardcoded script

---

### Remove-SysprepBlockers.ps1

A comprehensive tool for detecting and removing applications that block Windows Sysprep operations.

#### Overview

When preparing Windows images for Azure Virtual Desktop, Sysprep may fail due to AppX packages that are installed for specific users but not provisioned for all users. This script automatically detects these problematic packages and removes them after user confirmation.

#### Features

- **Automatic Detection**: Scans for AppX packages that will block Sysprep
- **Interactive Confirmation**: Shows detailed information and asks for confirmation before removal
- **Comprehensive Logging**: Creates detailed log files for audit and troubleshooting
- **Export Capability**: Can export list of detected blockers to CSV
- **Safe Whitelist**: Protects critical Windows system components from removal
- **Service Management**: Automatically stops/restarts AppX services to prevent file locks
- **Summary Report**: Provides detailed results after completion
- **Final Audit**: Verifies system is ready for Sysprep after cleanup

#### Usage

##### Interactive Mode (Recommended)
```powershell
.\Remove-SysprepBlockers.ps1
```

This will:
1. Scan for Sysprep blockers
2. Display detected packages
3. Ask for confirmation
4. Remove confirmed packages
5. Show summary report

##### Automatic Mode (No Confirmation)
```powershell
.\Remove-SysprepBlockers.ps1 -Force
```

Use this for automated deployments where you want to remove all detected blockers without prompting.

##### Export Blockers List
```powershell
.\Remove-SysprepBlockers.ps1 -ExportBlockersList
```

This will export the detected blockers to a CSV file on the Desktop before proceeding with removal.

##### Custom Log Location
```powershell
.\Remove-SysprepBlockers.ps1 -LogPath "C:\Logs\SysprepCleanup.log"
```

Specify a custom location for the log file.

#### Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `-Force` | Switch | Skip confirmation prompts and remove all blockers automatically | False |
| `-LogPath` | String | Custom path for the log file | Desktop\SysprepBlockerRemoval_[timestamp].log |
| `-ExportBlockersList` | Switch | Export detected blockers to CSV before removal | False |

#### Output

The script creates several outputs:

1. **Console Output**: Real-time colored output showing progress
2. **Log File**: Detailed log saved to Desktop (or custom location)
3. **CSV Export** (optional): List of detected blockers with details
4. **Exit Codes**:
   - `0`: Success - all blockers removed or none found
   - `1`: Partial failure - some blockers could not be removed
   - `2`: Fatal error occurred

#### Example Workflow

```powershell
# Step 1: Run detection and export list
.\Remove-SysprepBlockers.ps1 -ExportBlockersList

# Review the exported CSV and console output

# Step 2: Confirm removal when prompted
# Press 'Y' to proceed, 'N' to cancel, or 'L' to list packages again

# Step 3: Review the summary report

# Step 4: If any packages failed to remove, reboot and run again
Restart-Computer

# After reboot, run again
.\Remove-SysprepBlockers.ps1
```

#### What Gets Removed?

The script removes AppX packages that meet ALL these criteria:

- ✅ Installed for users but NOT provisioned in the image
- ✅ Not signed as a Windows system component
- ✅ Removable (not marked as NonRemovable)
- ✅ Not a framework package
- ✅ Not located in Windows\SystemApps
- ✅ Not in the system component whitelist

The script explicitly targets known problematic packages such as:
- Microsoft.Winget.Source (known Sysprep blocker)

#### What Is Protected?

The script will NEVER remove:

- Core Windows components (Microsoft.AAD, Microsoft.LockApp, etc.)
- .NET Native Framework and Runtime packages
- VCLibs and Windows App Runtime
- Windows Shell and system experience components
- Immersive Control Panel and Print Dialog
- Any package marked as NonRemovable or System-signed
- Framework packages

#### Troubleshooting

##### Some packages couldn't be removed

If the script reports that some packages failed to remove:

1. **Reboot the system** - this releases file locks
2. **Run the script again** after reboot
3. **Check the log file** for specific error messages
4. **Manually remove** stubborn packages using:
   ```powershell
   Get-AppxPackage -AllUsers -Name "PackageName" | Remove-AppxPackage -AllUsers
   ```

##### Script requires elevation

The script must run as Administrator. Right-click and select "Run as Administrator" or use:

```powershell
Start-Process powershell -Verb RunAs -ArgumentList "-File .\Remove-SysprepBlockers.ps1"
```

##### Sysprep still fails after running script

1. Check the Sysprep log: `C:\Windows\System32\Sysprep\Panther\setuperr.log`
2. Run the script again to verify no blockers remain
3. Look for other issues (pending Windows updates, domain-joined systems, etc.)

#### Requirements

- **Administrator privileges**: Required for AppX package removal
- **PowerShell 5.1 or later**: Script uses AppX cmdlets
- **Windows 10/11 or Windows Server 2016+**: For AppX management

#### Integration with AVD Image Preparation

This script should be run as part of your AVD image preparation workflow:

1. Install applications and configure the image
2. Run Windows Updates
3. **Run Remove-SysprepBlockers.ps1** ← This script
4. Run Sysprep with desired options
5. Capture the image

#### Logs and Audit Trail

Each run creates a timestamped log file containing:

- Timestamp of each operation
- List of detected blockers
- Services stopped/started
- Each package removal attempt (success/failure)
- Final audit results
- Any errors or warnings

Example log location: `C:\Users\Admin\Desktop\SysprepBlockerRemoval_20250115_143022.log`

#### Best Practices

1. **Test first**: Run in a test VM before production
2. **Export list**: Use `-ExportBlockersList` to review what will be removed
3. **Review logs**: Check log files for any issues
4. **Reboot if needed**: Some packages may require a reboot to fully remove
5. **Run before Sysprep**: Always run this as the last step before Sysprep

#### Version History

- **v2.0** (Current): Interactive version with confirmation prompts, logging, and export
- **v1.0**: Original automatic removal script

---

## Support

For issues or questions:
1. Check the log file for detailed error messages
2. Review the troubleshooting section above
3. Ensure you're running as Administrator
4. Verify PowerShell version compatibility
