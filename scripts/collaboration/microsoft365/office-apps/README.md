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
- Install configuration XML at `C:\AVD\M365Apps\install.xml` (see example XMLs below)
- Internet connectivity
- Minimum 10GB free disk space

**Quick Start:**

1. **Download Office Deployment Tool:**
   - Visit: https://www.microsoft.com/en-us/download/details.aspx?id=49117
   - Extract `setup.exe` to `C:\AVD\M365Apps\`

2. **Choose a configuration template:**
   - Copy one of the example XML files (see below)
   - Rename it to `install.xml`
   - Place it at `C:\AVD\M365Apps\install.xml`

3. **Run the script:**
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

## Example Configuration Files

This directory includes ready-to-use ODT configuration XML files for common deployment scenarios:

### 📋 Available Templates

| File | Channel | Use Case | Apps Included |
|------|---------|----------|---------------|
| **example-install-monthly-enterprise.xml** | Monthly Enterprise | **Recommended for most organizations** | All apps (Word, Excel, PowerPoint, Outlook, OneNote, Publisher, Access) |
| **example-install-semi-annual.xml** | Semi-Annual | Maximum stability, regulated industries | Core apps only (Word, Excel, PowerPoint, Outlook) |
| **example-install-current-channel.xml** | Current | Fastest updates, early adopters | All apps |
| **example-install-avd-shared.xml** | Monthly Enterprise | **Azure Virtual Desktop (AVD/WVD)** | Core apps + SharedComputerLicensing enabled |
| **example-install-minimal.xml** | Monthly Enterprise | Limited disk space, task workers | Word, Excel, PowerPoint only |

### 📝 How to Use Example XMLs

1. **Choose the appropriate template** for your environment
2. **Copy the example file:**
   ```powershell
   Copy-Item "example-install-monthly-enterprise.xml" "C:\AVD\M365Apps\install.xml"
   ```
3. **Customize if needed** (edit apps, languages, settings)
4. **Run Update-M365Apps.ps1**

### 🎯 Which Configuration Should I Use?

- **General business users** → `example-install-monthly-enterprise.xml`
- **Risk-averse organizations** → `example-install-semi-annual.xml`
- **AVD/WVD/RDS environments** → `example-install-avd-shared.xml` ⚠️ **MUST use SharedComputerLicensing**
- **Power users/IT staff** → `example-install-current-channel.xml`
- **Limited storage devices** → `example-install-minimal.xml`

### ⚙️ Customizing XML Configurations

All example XMLs can be customized:

**Exclude specific apps:**
```xml
<ExcludeApp ID="Access" />     <!-- Microsoft Access -->
<ExcludeApp ID="Publisher" />  <!-- Microsoft Publisher -->
<ExcludeApp ID="OneNote" />    <!-- OneNote (desktop) -->
<ExcludeApp ID="Groove" />     <!-- OneDrive for Business -->
<ExcludeApp ID="Lync" />       <!-- Skype/Teams -->
```

**Add additional languages:**
```xml
<Language ID="en-us" />
<Language ID="en-gb" />
<Language ID="fr-fr" />
<Language ID="de-de" />
```

**Adjust installation behavior:**
```xml
<Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />  <!-- Force close apps -->
<Property Name="PinIconsToTaskbar" Value="FALSE" /> <!-- Don't pin icons -->
<Property Name="AUTOACTIVATE" Value="1" />          <!-- Auto-activate -->
```

---

## Troubleshooting

Encountering issues? Check the **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** guide for:

- ❌ **Prerequisites Issues** - ODT not found, missing XML, permissions
- 🌐 **Network & Connectivity** - Proxy settings, firewall rules, CDN access
- 🔢 **ODT Exit Codes** - Complete exit code reference (0, 17, 30066, etc.)
- 🚫 **Installation Failures** - Office won't close, disk space, hanging installs
- 🔄 **Channel Switching** - Channel not changing, version mismatches
- 📝 **Registry & Detection** - Office not detected, version unknown
- 🔑 **Activation & Licensing** - Product key prompts, SharedComputerLicensing
- ⚡ **Performance** - Slow downloads, long installations
- 📊 **Log File Analysis** - Reading ODT logs, finding errors
- 💬 **Common Error Messages** - Detailed solutions for specific errors

**Quick Troubleshooting:**
```powershell
# Check if ODT exists
Test-Path "C:\AVD\M365Apps\setup.exe"

# Verify XML is valid
[xml]$config = Get-Content "C:\AVD\M365Apps\install.xml"

# Test internet connectivity
Test-NetConnection clients.config.office.net -Port 443

# View installed Office info
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
```

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

## Files in This Directory

| File | Description |
|------|-------------|
| **Update-M365Apps.ps1** | Main update manager script |
| **README.md** | This documentation file |
| **TROUBLESHOOTING.md** | Comprehensive troubleshooting guide |
| **example-install-monthly-enterprise.xml** | Monthly Enterprise Channel config (recommended) |
| **example-install-semi-annual.xml** | Semi-Annual Channel config (most stable) |
| **example-install-current-channel.xml** | Current Channel config (fastest updates) |
| **example-install-avd-shared.xml** | AVD/WVD config with SharedComputerLicensing |
| **example-install-minimal.xml** | Minimal installation (Word, Excel, PowerPoint only) |

---

## Related Documentation
- [Office Deployment Tool Documentation](https://docs.microsoft.com/en-us/deployoffice/overview-office-deployment-tool)
- [Update channels for Microsoft 365 Apps](https://docs.microsoft.com/en-us/deployoffice/updates/overview-update-channels)
- [Configuration options for ODT](https://docs.microsoft.com/en-us/deployoffice/office-deployment-tool-configuration-options)
