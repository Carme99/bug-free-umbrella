# System Utilities

PowerShell utility scripts for system management, maintenance, and automation tasks.

## 📋 Available Scripts

### Update-AllAppsWinget.ps1

**Updates all installed applications using Windows Package Manager (winget) in SYSTEM context.**

This comprehensive script automates the update process for all winget-managed applications and can run as a scheduled task in SYSTEM context. It automatically handles winget configuration, dependency installation, and application updates.

#### Features

- ✅ **Automatic Dependency Detection** - Checks for and installs VCLibs and UI.Xaml if needed
- ✅ **Winget Installation** - Downloads and installs winget if not present in SYSTEM context
- ✅ **Bulk Updates** - Updates all installed applications in one operation
- ✅ **Retry Logic** - Exponential backoff retry mechanism for reliability
- ✅ **Comprehensive Logging** - Detailed log file with timestamped entries
- ✅ **SYSTEM Context Support** - Designed to run as scheduled task with SYSTEM privileges
- ✅ **Update Verification** - Verifies updates completed successfully

#### Requirements

- **PowerShell**: 5.1 or later
- **Privileges**: Must run as Administrator or SYSTEM
- **Internet**: Required to download dependencies and updates

#### Usage

**Basic Usage:**
```powershell
# Run with default settings (installs dependencies if needed)
.\Update-AllAppsWinget.ps1
```

**Custom Log Path:**
```powershell
# Specify custom log location
.\Update-AllAppsWinget.ps1 -LogPath "C:\Logs\winget-updates.log"
```

**Increased Retry Count:**
```powershell
# Use more retries for unreliable connections
.\Update-AllAppsWinget.ps1 -MaxRetries 5
```

**Skip Dependency Check:**
```powershell
# Skip dependency installation (if already configured)
.\Update-AllAppsWinget.ps1 -SkipDependencyCheck
```

**Update from Microsoft Store:**
```powershell
# Use Microsoft Store as update source instead of winget
.\Update-AllAppsWinget.ps1 -UpdateSource msstore
```

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `LogPath` | String | `C:\ProgramData\WingetUpdates\update-all-apps.log` | Path where log file will be created |
| `MaxRetries` | Int | `3` | Maximum number of retry attempts for winget operations |
| `SkipDependencyCheck` | Switch | `$false` | Skip automatic dependency installation |
| `UpdateSource` | String | `winget` | Update source (`winget` or `msstore`) |

#### Scheduled Task Setup

**Create a scheduled task to run updates automatically:**

```powershell
# Create scheduled task (run as Administrator)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\Scripts\Update-AllAppsWinget.ps1`""

$trigger = New-ScheduledTaskTrigger -Daily -At 2am

$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" `
    -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName "Winget Update All Apps" `
    -Action $action -Trigger $trigger -Principal $principal `
    -Settings $settings -Description "Updates all applications using winget"
```

#### What Gets Installed (If Missing)

The script automatically installs the following if not present:

1. **VCLibs** - Visual C++ Runtime Libraries (required for winget)
2. **Microsoft.UI.Xaml** - UI framework (required for winget)
3. **Windows Package Manager (winget)** - Desktop App Installer

#### Log File Format

```
[2025-12-30 02:00:15] [Info] Winget System Update Script Started
[2025-12-30 02:00:15] [Info] Running as SYSTEM
[2025-12-30 02:00:16] [Success] Winget is already configured and ready
[2025-12-30 02:00:17] [Info] Updating winget sources...
[2025-12-30 02:00:20] [Success] Winget sources updated
[2025-12-30 02:00:21] [Info] Found 5 application(s) with available updates
[2025-12-30 02:00:45] [Success] Application update process completed
```

#### Troubleshooting

**Script exits with "must be run as Administrator":**
- Run PowerShell as Administrator or configure as scheduled task with SYSTEM privileges

**Winget installation fails:**
- Check internet connectivity
- Verify Windows Update service is running
- Ensure Microsoft Store is not blocked by policy

**Updates fail to install:**
- Check the log file for specific error messages
- Increase retry count: `-MaxRetries 5`
- Try running manually to see detailed error output

**Applications still showing updates available:**
- Some apps may require manual intervention (e.g., reboot, manual acceptance)
- Check if apps are currently running (may block update)
- Review log file for specific failures

#### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success - all updates completed |
| `1` | Error - check log file for details |

#### Best Practices

1. **Schedule During Off-Hours** - Run during maintenance windows (2-4 AM)
2. **Monitor Logs** - Regularly review log files for issues
3. **Test First** - Test manually before scheduling
4. **Keep Dependencies Updated** - Periodically update VCLibs and UI.Xaml manually
5. **Combine with Reporting** - Export log data to monitoring systems

#### Security Considerations

- Script runs with elevated privileges (SYSTEM or Administrator)
- Downloads dependencies from official Microsoft sources only
- All dependencies are verified during installation
- Log files may contain system information - secure appropriately

---

### Get-SoftwareInventory.ps1

**Generates comprehensive software inventory reports.**

Creates detailed reports of installed software across systems.

### Optimize-WindowsServices.ps1

**Optimizes Windows services for performance.**

Analyzes and adjusts Windows service configurations for optimal performance.

### Sync-UserGroupToPrimaryDeviceGroup.ps1

**Synchronizes Intune user groups to primary device groups.**

Automates the process of keeping user and device group memberships in sync.

---

## 📖 Documentation

For more information about this repository:
- **[Main README](../../README.md)** - Repository overview
- **[Script Catalog](../../wiki/Script-Catalog)** - Browse all scripts
- **[Contributing](../../CONTRIBUTING.md)** - Contribution guidelines

---

**Last Updated:** 2025-12-30
