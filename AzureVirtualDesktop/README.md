# Azure Virtual Desktop Scripts

This folder contains PowerShell scripts for managing and preparing Azure Virtual Desktop (AVD) environments.

## Scripts

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
