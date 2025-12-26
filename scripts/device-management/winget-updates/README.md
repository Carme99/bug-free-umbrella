# Winget Update Scripts for Intune

Automated application update management using Winget and Microsoft Intune Proactive Remediations.

## Overview

This repository contains PowerShell detection and remediation scripts for keeping Windows applications up-to-date via Winget in enterprise environments managed by Intune.

**Key Features:**
- Automated update detection and installation
- Retry logic with exponential backoff
- Network connectivity validation
- Optional logging and notifications
- Maintenance window support
- Force-close capabilities with user notifications

## Folder Structure

```
winget-updates/
├── _templates/          # Template files and documentation
├── browsers/            # Web browsers (Chrome, Firefox)
├── development/         # Dev tools (Git, VS Code, PowerShell)
├── media/              # Media players (VLC, OBS, Zoom)
├── productivity/       # Office/productivity apps (Teams, Adobe Reader)
├── remote-access/      # Remote desktop/access tools (TeamViewer, WinSCP)
├── runtimes/           # Runtime libraries (C++ Redist, WebView2)
├── utilities/          # System utilities (7-Zip, Azure CLI)
└── vendor-specific/    # Vendor-specific tools (Lenovo utilities)
```

## Quick Start

### 1. Choose an Application

Browse the category folders to find the application you want to manage, or check `_templates/app-catalog.md` for a list of available and suggested apps.

### 2. Review Scripts

Each application folder contains:
- `detect.ps1` - Checks if an update is available
- `remediate.ps1` - Installs the update
- `remediate_force_close.ps1` - (Optional) Force-closes app before updating
- `remediate_maintenance.ps1` - (Optional) Updates only during maintenance windows

### 3. Deploy to Intune

1. Navigate to **Endpoint Manager** → **Reports** → **Endpoint Analytics** → **Proactive Remediations**
2. Click **Create script package**
3. Upload `detect.ps1` as the detection script
4. Upload `remediate.ps1` (or variant) as the remediation script
5. Configure:
   - **Run this script using logged-on credentials**: No
   - **Run script in 64-bit PowerShell**: Yes
6. Assign to device groups
7. Set schedule (hourly, daily, weekly)

## Template Versions

All scripts use **V3 templates** - the latest and recommended version with enhanced features.

### V3 Features

**Detection:**
- Retry logic with exponential backoff
- Network connectivity validation
- Optional file or event log logging
- Auto-detection of app name
- Detailed error messages

**Remediation Variants:**
1. **Standard** - Updates when app is not running
2. **Force Close** - Closes app with optional user notification
3. **Maintenance Window** - Updates only during specified times

**See `_templates/README_V3.md` for detailed documentation.**

## Adding a New Application

### Method 1: Use Existing App as Template

1. Copy an existing app folder from the appropriate category
2. Rename to PascalCase (see `NAMING_CONVENTIONS.md`)
3. Edit `detect.ps1` and update the `$ID` variable
4. Edit `remediate.ps1` and update the `$ID` variable
5. Test locally, then deploy to Intune

### Method 2: Use Templates

1. Create a new folder in the appropriate category
2. Copy `_templates/detect_v3.ps1` to your app folder as `detect.ps1`
3. Copy appropriate remediation template to your app folder as `remediate.ps1`
4. Edit both files and set the `$ID` variable to your winget package ID
5. Customize optional settings as needed
6. Test locally, then deploy to Intune

### Finding Winget Package IDs

```powershell
# Search for an app
winget search "Google Chrome"

# Get exact ID
winget show "Google.Chrome"
```

## Configuration Examples

### Simple Configuration (Recommended for Most Apps)

```powershell
# detect.ps1
$ID = 'Google.Chrome'

# remediate.ps1
$ID = 'Google.Chrome'
```

That's it! The script auto-detects the app name and process.

### Advanced Configuration

```powershell
# detect.ps1
$ID = 'Microsoft.Teams'
$EnableLogging = $true
$MaxRetries = 5

# remediate.ps1 (force close variant)
$ID = 'Microsoft.Teams'
$NotifyUserBeforeClose = $true
$UserNotificationSeconds = 120
$EnableLogging = $true
```

### Maintenance Window Example

```powershell
# remediate.ps1 (maintenance window variant)
$ID = 'Microsoft.SQLServerManagementStudio'
$MaintenanceWindowDays = @('Saturday', 'Sunday')
$MaintenanceWindowStartHour = 2
$MaintenanceWindowEndHour = 6
$ForceCloseInMaintenanceWindow = $true
```

## Best Practices

### 1. Choose the Right Template

| App Type | Recommended Template | Examples |
|----------|---------------------|----------|
| User apps (business hours) | Standard | Chrome, VS Code, VLC |
| Background services | Force Close | TeamViewer, utilities |
| Critical production tools | Maintenance Window | SSMS, PowerShell 7 |
| Collaboration tools | Force Close + Notifications | Teams, Zoom |

### 2. Test Locally First

```powershell
# Test detection
.\detect.ps1

# Test remediation
.\remediate.ps1
```

### 3. Enable Logging During Testing

```powershell
$EnableLogging = $true
```

Disable in production once stable to reduce disk I/O.

### 4. Monitor Intune Reports

- Check success/failure rates regularly
- Review logs if enabled
- Adjust retry counts or timings based on results

### 5. Use Conservative Settings First

Start with standard remediation, only add force-close if updates aren't completing.

## Naming Conventions

See `NAMING_CONVENTIONS.md` for detailed guidelines.

**Quick rules:**
- Folder names: PascalCase (`GoogleChrome`, `MicrosoftTeams`)
- No spaces or special characters in folder names
- Spell out leading numbers (`SevenZip` not `7Zip`)
- Architecture suffix for variants (`AdobeReader32bit`, `Cpp2013Redist-x86`)

## Troubleshooting

### Updates Not Detecting

**Solutions:**
1. Enable logging: `$EnableLogging = $true`
2. Increase retries: `$MaxRetries = 5`
3. Verify winget ID is correct
4. Check network connectivity

### Force Close Not Working

**Solutions:**
1. Verify process name
2. Increase close attempts: `$MaxProcessCloseAttempts = 5`
3. Check for child processes

### Maintenance Window Not Triggering

**Solutions:**
1. Enable logging to see time checks
2. Verify day names (case-sensitive)
3. Check hour format (24-hour, 0-23)
4. Ensure Intune schedule aligns with window

### User Notifications Not Showing

**Solutions:**
1. Verify users are logged in when script runs
2. Check Windows Messenger service is running
3. Test with longer notification time

## Documentation

- `README.md` - This file (overview and quick start)
- `NAMING_CONVENTIONS.md` - Folder and file naming standards
- `_templates/README_V3.md` - Comprehensive V3 template guide
- `_templates/app-catalog.md` - List of popular apps and their winget IDs

## Support

For issues or questions:
1. Check existing app folders for working examples
2. Review `_templates/README_V3.md` for detailed template documentation
3. Enable logging (`$EnableLogging = $true`) for diagnostics
4. Review Intune deployment logs

## Version History

- **V3 (2024)** - Enhanced templates with retry logic, logging, notifications, maintenance windows
- **V2 (2024)** - Auto-detection, simplified configuration
- **V1 (2023)** - Basic templates, manual configuration

Current repository uses **V3 templates** exclusively.

## Contributing

When adding new applications:
1. Follow naming conventions in `NAMING_CONVENTIONS.md`
2. Use V3 templates from `_templates/`
3. Place in appropriate category folder
4. Test locally before committing
5. Add app to `_templates/app-catalog.md` if widely used

---

**Last Updated:** December 26, 2024
