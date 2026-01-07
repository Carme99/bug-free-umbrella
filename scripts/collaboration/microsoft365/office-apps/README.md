# M365 Office Apps Management Scripts

PowerShell scripts for managing Microsoft 365 Apps installations, updates, and configurations.

## Scripts

### Update-M365Apps.ps1

Comprehensive M365 Apps update manager for environments without Microsoft AutoUpdate.

**Features:**
- 🔍 Detects installed M365 Apps and current version
- 🔄 Checks for available updates from Microsoft CDN
- 📥 Downloads updates locally using Office Deployment Tool (ODT)
- ⚙️ Installs updates with progress tracking
- 🎯 Interactive update channel selection (Monthly, Semi-Annual, Beta, etc.)
- 🧹 Automatic cleanup of downloaded files to save disk space
- 📊 Rotating log files with automatic cleanup
- ✅ Fresh installation support for new systems
- 🎨 Color-coded, user-friendly console output

**Requirements:**
- Administrator privileges
- Office Deployment Tool (setup.exe) at `C:\AVD\M365Apps\setup.exe`
- Install configuration XML at `C:\AVD\M365Apps\install.xml`
- Internet connectivity

**Usage:**
```powershell
.\Update-M365Apps.ps1
```

**Interactive Prompts:**
- Change update channel (Monthly, Enterprise, Semi-Annual, Beta)
- Download updates
- Install updates immediately or defer
- Clean up downloaded files after installation

**Configuration:**
Edit the script's `$Config` hashtable to customize:
- ODT and XML file paths
- Updates download location
- Log retention period (default: 30 days)
- Update channel

**Logs:**
Detailed logs are saved to `C:\AVD\M365Apps\Logs\` with automatic rotation.

**Update Channels Supported:**
- **Monthly (Current Channel)** - Latest features monthly (recommended)
- **Monthly Enterprise** - Validated monthly updates for enterprise
- **Monthly Preview** - Preview of upcoming monthly features
- **Semi-Annual (Preview)** - Preview of semi-annual updates
- **Semi-Annual** - Updates twice yearly (most stable)
- **Beta (Insider)** - Cutting edge features

---

## Common Use Cases

### Scenario 1: Regular Update Maintenance
Run the script monthly to check for and install updates on managed workstations.

### Scenario 2: AVD Image Management
Use before capturing AVD images to ensure latest M365 Apps version and clean up installation files.

### Scenario 3: Channel Migration
Switch between update channels (e.g., from Monthly to Semi-Annual for stability).

### Scenario 4: Fresh Installation
Deploy M365 Apps on new systems without existing Office installations.

---

## Related Documentation
- [Office Deployment Tool Documentation](https://docs.microsoft.com/en-us/deployoffice/overview-office-deployment-tool)
- [Update channels for Microsoft 365 Apps](https://docs.microsoft.com/en-us/deployoffice/updates/overview-update-channels)
