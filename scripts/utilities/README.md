# System Utilities

PowerShell utility scripts for system management, maintenance, and automation tasks.

## 📋 Available Scripts

### Update-DotNetRuntimes.ps1

**Comprehensive .NET runtime maintenance script with EOL detection, automatic updates, and disk space cleanup.**

This advanced script manages ASP.NET Core and Windows Desktop runtimes across your system, automatically updating to the latest patches, removing EOL (End of Life) versions, and cleaning up old patch installations to reclaim disk space.

#### Features

- ✅ **Architecture Aware** - Handles both x64 and x86 runtimes independently
- ✅ **Automatic Updates** - Downloads and installs latest patches per channel
- ✅ **EOL Detection** - Identifies and removes end-of-life runtime versions
- ✅ **Smart EOL Replacement** - Automatically suggests and installs LTS replacements for EOL versions
- ✅ **Patch Cleanup** - Removes lower patch versions automatically
- ✅ **Disk Usage Reporting** - Before/after reports with reclaimed space
- ✅ **LTS Filtering** - Option to only update Long Term Support channels
- ✅ **Uninstall Tool Integration** - Auto-installs .NET Uninstall Tool if needed
- ✅ **Multiple Export Formats** - CSV and JSON reports available
- ✅ **Interactive Mode** - Prompts for all options when needed
- ✅ **Dry Run Mode** - Preview changes without applying them

#### Requirements

- **PowerShell**: 5.1 or later
- **Privileges**: Administrator (for install/uninstall operations)
- **Internet**: Required to download metadata and runtimes
- **dotnet.exe**: Should be present at `C:\Program Files\dotnet\dotnet.exe`

#### Usage

**Basic Usage (Auto-approve all):**
```powershell
# Default: auto-approve, remove EOL, cleanup patches
.\Update-DotNetRuntimes.ps1
```

**Interactive Mode:**
```powershell
# Prompt for all configuration options
.\Update-DotNetRuntimes.ps1 -Interactive
```

**Dry Run (Preview Only):**
```powershell
# See what would be updated without making changes
.\Update-DotNetRuntimes.ps1 -DryRun
```

**LTS Only:**
```powershell
# Only update LTS channels
.\Update-DotNetRuntimes.ps1 -LtsOnly -IncludeChannels 8.0,9.0
```

**Single Architecture:**
```powershell
# Update only x64 runtimes
.\Update-DotNetRuntimes.ps1 -Arch x64 -LogPath "C:\Logs\dotnet-update.log"
```

**Conservative Mode:**
```powershell
# No auto-removal of EOL, require confirmation
.\Update-DotNetRuntimes.ps1 -RemoveEol:$false -Approve:$false
```

**With Reports:**
```powershell
# Generate CSV and JSON reports
.\Update-DotNetRuntimes.ps1 -ReportPath "C:\Reports\dotnet-disk.csv" -JsonSummaryPath "C:\Reports\summary.json"
```

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Approve` | Switch | `$true` | Auto-approve all installs and removals (non-interactive) |
| `RemoveEol` | Switch | `$true` | Automatically remove EOL runtimes |
| `CleanupLowerPatches` | Switch | `$true` | Remove lower patch versions (mandatory) |
| `AutoInstallUninstallTool` | Switch | `$true` | Install .NET Uninstall Tool if missing |
| `ForceFileCleanup` | Switch | `$true` | Use filesystem cleanup if uninstall tool unavailable |
| `Interactive` | Switch | `$false` | Prompt for all configuration options |
| `DryRun` | Switch | `$false` | Preview actions without making changes |
| `UninstallToolMsiUrl` | String | *(GitHub release)* | Override URL for uninstall tool MSI |
| `Arch` | String | *(both)* | Limit to x64 or x86 only |
| `LtsOnly` | Switch | `$false` | Only update LTS channels |
| `IncludeChannels` | String[] | *(all)* | Specific channels to process (e.g., '8.0', '9.0') |
| `MinVersion` | Version | *(none)* | Minimum version floor (skip if latest is below) |
| `LogPath` | String | *(none)* | Path to transcript log file |
| `ReportPath` | String | *(none)* | CSV export path for disk usage report |
| `JsonSummaryPath` | String | *(none)* | JSON export path for action summary |

#### What It Does

1. **Discovery Phase**
   - Scans for installed ASP.NET Core and Windows Desktop runtimes (x64 and x86)
   - Fetches official .NET release metadata from Microsoft
   - Identifies which channels have updates available

2. **EOL Handling**
   - Detects channels that have reached End of Life
   - Suggests active LTS replacement versions
   - Optionally removes EOL runtimes (with approval)
   - Can automatically install recommended LTS replacement
   - Cleans up associated base runtimes

3. **Update Phase**
   - Downloads latest patch versions per channel
   - Verifies file integrity with SHA512 hashes
   - Installs base runtime and ASP.NET Core/WindowsDesktop runtime
   - Supports both x64 and x86 architectures

4. **Cleanup Phase**
   - Removes lower patch versions within each channel
   - Uses .NET Uninstall Tool if available
   - Falls back to filesystem cleanup if needed
   - Verifies cleanup completed successfully

5. **Reporting Phase**
   - Compares disk usage before and after
   - Shows reclaimed space per runtime
   - Exports detailed reports to CSV/JSON

#### Output Example

```
=== ASP.NET Core Channel 6.0 x64 ===
EOL channel detected: 6.0 | End of support: 2024-11-12 | Installed: 6.0.14
  → Recommended replacement: .NET 8.0 LTS (supported until 2026-11-10)
  → Will install .NET 8.0 LTS after removal
Using uninstall tool to remove ASP.NET Core 6.0
Removal complete for EOL channel 6.0 x64
Installing replacement: .NET 8.0 LTS x64...
Downloading ASP.NET Core Runtime x64...
Installing ASP.NET Core Runtime 8.0.22 x64...
Successfully installed .NET 8.0 LTS (8.0.22) x64

=== ASP.NET Core Channel 9.0 x64 ===
Update available: 9.0.8 → 9.0.11 (x64)
Downloading ASP.NET Core Runtime x64...
Installing ASP.NET Core Runtime 9.0.11 x64...
Update complete for 9.0 x64 to 9.0.11

=== Post install patch cleanup ===
Removing lower patches (tool or filesystem fallback)
Cleaning lower patches for ASP.NET Core Runtime x64...
Cleanup complete for ASP.NET Core Runtime x64

╔═══════════════════════════════════════════════════╗
║ Runtime Maintenance Summary                      ║
║ Updated        : 1                                ║
║ EOL removed    : 1                                ║
║ EOL upgraded   : 1                                ║
║ Already current: 2                                ║
║ Skipped        : 0                                ║
║ Cleanup runs   : 2                                ║
║ Reclaimed      : 1.24 GB                          ║
╚═══════════════════════════════════════════════════╝
```

#### Troubleshooting

**Script reports "not running elevated":**
- Run PowerShell as Administrator for install/uninstall operations

**"dotnet.exe not found":**
- Ensure .NET SDK or Runtime is installed
- Check paths: `C:\Program Files\dotnet\dotnet.exe` (x64) or `C:\Program Files (x86)\dotnet\dotnet.exe` (x86)

**"Failed to fetch release data":**
- Check internet connectivity
- Verify firewall isn't blocking `dotnetcli.blob.core.windows.net`

**Cleanup not removing files:**
- Try with `-ForceFileCleanup` to use filesystem method
- Check if files are in use (close running .NET applications)

**Uninstall tool installation fails:**
- Download manually from GitHub: `dotnet/cli-lab` releases
- Install MSI and rerun script with `-AutoInstallUninstallTool:$false`

#### Scheduled Task Setup

```powershell
# Run monthly on patch Tuesday (2nd Tuesday, 3 AM)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\Scripts\Update-DotNetRuntimes.ps1`" -LogPath `"C:\Logs\dotnet-update.log`""

# 2nd Tuesday of month at 3 AM
$trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Tuesday -At 3am

$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" `
    -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName ".NET Runtime Maintenance" `
    -Action $action -Trigger $trigger -Principal $principal `
    -Settings $settings -Description "Updates .NET runtimes and removes EOL versions"
```

#### Best Practices

1. **Test in Dev First** - Run with `-DryRun` to preview changes
2. **Schedule During Maintenance** - Run during low-usage periods
3. **Keep LTS Only** - Use `-LtsOnly` for production stability
4. **Monitor Logs** - Enable `-LogPath` for troubleshooting
5. **Export Reports** - Track disk usage trends over time
6. **Backup Before Major Updates** - Snapshot VMs before channel upgrades

#### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success - all operations completed |
| `1` | Error - check log for details |

---

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
