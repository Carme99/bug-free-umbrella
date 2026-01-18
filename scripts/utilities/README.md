# System Utilities

PowerShell utility scripts for system management, maintenance, and automation tasks.

## 📋 Available Scripts

### Update-DotNetRuntimes.ps1

**Comprehensive .NET runtime maintenance script with interactive menu system, EOL detection, automatic updates, and disk space cleanup.**

This enterprise-grade script manages ASP.NET Core and Windows Desktop runtimes across your system with an interactive menu for easy management or full CLI automation. Features include automatic updates, EOL detection with LTS replacement, dependency analysis, system restore points, and security-hardened installation with Authenticode signature verification.

**Version:** 2.5 | **Last Updated:** 2025-01-17

#### Features

##### Core Capabilities
- ✅ **Interactive Menu System** - 8 maintenance options with user-friendly interface
- ✅ **Full CLI Automation** - Complete parameter support for scripting and CI/CD
- ✅ **Architecture Aware** - Handles both x64 and x86 runtimes independently
- ✅ **Automatic Updates** - Downloads and installs latest patches per channel
- ✅ **EOL Detection & Removal** - Identifies and removes end-of-life runtime versions
- ✅ **Smart EOL Replacement** - Automatically suggests and installs LTS replacements

##### Security & Safety
- 🔒 **Authenticode Verification** - Mandatory digital signature validation (no bypass)
- 🔒 **SHA512 Hash Validation** - Integrity checks for all downloads
- 🔒 **Dependency Detection** - Scans for IIS, ANCM, Windows Services, Scheduled Tasks
- 🔒 **System Restore Points** - Optional rollback support before major changes
- 🔒 **Protected Channels** - Prevent accidental removal of critical runtimes

##### Performance & Reporting
- ⚡ **Performance Optimized** - .NET DirectoryInfo API for fast disk operations
- ⚡ **Smart Caching** - 5-minute cache with Force override for fresh data
- 📊 **Disk Usage Reporting** - Before/after reports with reclaimed space
- 📊 **Multiple Export Formats** - CSV and JSON reports available
- 📊 **Structured Logging** - PowerShell streams for automation compatibility

##### Flexibility
- ✅ **LTS Filtering** - Option to only update Long Term Support channels
- ✅ **Uninstall Tool Integration** - Auto-installs .NET Uninstall Tool if needed
- ✅ **Dry Run Mode** - Preview changes without applying them
- ✅ **One-Shot Cleanup** - Single parameter for complete maintenance
- ✅ **Non-Interactive Mode** - Batch processing support

#### Requirements

- **PowerShell**: 5.1 or later
- **Privileges**: Administrator (for install/uninstall operations)
- **Internet**: Required to download metadata and runtimes
- **dotnet.exe**: Should be present at `C:\Program Files\dotnet\dotnet.exe`

#### Usage

**Interactive Menu Mode (NEW in v2.5):**
```powershell
# Launch interactive menu with 8 maintenance options
.\Update-DotNetRuntimes.ps1
```

**One-Shot Complete Maintenance (NEW in v2.5):**
```powershell
# Fully automated: update all, remove EOL, cleanup patches, install uninstall tool
.\Update-DotNetRuntimes.ps1 -OneShotCleanup
```

**CLI Automation (Non-Interactive):**
```powershell
# Automated execution with all parameters specified
.\Update-DotNetRuntimes.ps1 -NonInteractive -Approve -RemoveEol -CleanupLowerPatches
```

**Dry Run (Preview Only):**
```powershell
# See what would be updated without making changes
.\Update-DotNetRuntimes.ps1 -DryRun
```

**With Dependency Protection (NEW in v2.5):**
```powershell
# Block EOL removal if dependencies detected (IIS, Services, Tasks)
.\Update-DotNetRuntimes.ps1 -DependencyCheck Block
```

**With System Restore Point (NEW in v2.5):**
```powershell
# Create restore point before making changes
.\Update-DotNetRuntimes.ps1 -CreateRestorePoint -RestorePointName "Before .NET Update"
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

**Protected Channels (NEW in v2.5):**
```powershell
# Prevent accidental removal of critical runtime versions
.\Update-DotNetRuntimes.ps1 -ProtectChannels 8.0,9.0
```

**Force Fresh Scan (NEW in v2.5):**
```powershell
# Bypass cache and perform fresh system scan
.\Update-DotNetRuntimes.ps1 -Force
```

**With Reports:**
```powershell
# Generate CSV and JSON reports
.\Update-DotNetRuntimes.ps1 -ReportPath "C:\Reports\dotnet-disk.csv" -JsonSummaryPath "C:\Reports\summary.json"
```

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| **Interactive & Automation** |||
| `NonInteractive` | Switch | `$false` | Disable menu system, use CLI mode only |
| `Approve` | Switch | `$false` | Auto-approve all installs and removals without prompts |
| `DryRun` | Switch | `$false` | Preview actions without making changes |
| `OneShotCleanup` | Switch | `$false` | 🆕 Preset: enables all automation flags for complete maintenance |
| **Runtime Management** |||
| `RemoveEol` | Switch | `$false` | Automatically remove EOL (end-of-life) runtimes |
| `CleanupLowerPatches` | Switch | `$false` | Remove lower patch versions within each channel |
| `LtsOnly` | Switch | `$false` | Only update Long Term Support channels |
| `IncludeChannels` | String[] | *(all)* | Specific channels to process (e.g., `8.0`, `9.0`) |
| `ProtectChannels` | String[] | *(none)* | 🆕 Channels to protect from removal |
| `MinVersion` | Version | *(none)* | Minimum version floor (skip if latest is below) |
| `Arch` | String | *(both)* | Limit to `x64` or `x86` only |
| **Safety & Dependencies** |||
| `DependencyCheck` | String | `Warn` | 🆕 Dependency handling: `Warn`, `Block`, or `Off` |
| `CreateRestorePoint` | Switch | `$false` | 🆕 Create system restore point before changes |
| `RestorePointName` | String | *(auto)* | 🆕 Custom restore point description |
| `Force` | Switch | `$false` | 🆕 Bypass cache and force fresh system scan |
| **Tools & Reporting** |||
| `AutoInstallUninstallTool` | Switch | `$false` | Install .NET Uninstall Tool if missing |
| `UninstallToolMsiUrl` | String | *(GitHub)* | Override URL for uninstall tool MSI |
| `ForceFileCleanup` | Switch | `$false` | Use filesystem cleanup if uninstall tool unavailable |
| `LogPath` | String | *(none)* | Path to transcript log file |
| `ReportPath` | String | *(none)* | CSV export path for disk usage report |
| `JsonSummaryPath` | String | *(none)* | JSON export path for action summary |
| **Advanced** |||
| `SkipDiskScan` | Switch | `$false` | Skip disk usage calculations for faster execution |

#### What It Does

**Interactive Menu Mode** (default when no parameters specified):
   - Presents 8 maintenance options in a user-friendly menu
   - Shows real-time system status (installed runtimes, disk usage, dependencies)
   - Options include: Update all, Remove EOL, Install specific versions, Cleanup, Reports

**Automated CLI Mode** (when parameters or `-NonInteractive` specified):

1. **Discovery & Analysis Phase**
   - Scans for installed ASP.NET Core and Windows Desktop runtimes (x64 and x86)
   - Fetches official .NET release metadata from Microsoft
   - Identifies which channels have updates available
   - 🆕 **Detects dependencies**: IIS, ANCM module, Windows Services, Scheduled Tasks, running processes
   - 🆕 **Caches system status** for 5 minutes (override with `-Force`)

2. **EOL Handling**
   - Detects channels that have reached End of Life
   - Suggests active LTS replacement versions
   - 🆕 **Dependency safety**: Warns or blocks removal if dependencies detected (configurable)
   - 🆕 **Protected channels**: Prevents removal of specified critical versions
   - Optionally removes EOL runtimes (with approval)
   - Can automatically install recommended LTS replacement
   - Cleans up associated base runtimes

3. **Safety Measures** 🆕
   - Creates system restore point before changes (optional)
   - Validates runtime dependencies before removal
   - Checks for protected channels
   - Dry run mode for preview without changes

4. **Update Phase**
   - Downloads latest patch versions per channel
   - 🆕 **Mandatory Authenticode signature validation** (no bypass - security hardened)
   - Verifies file integrity with SHA512 hashes
   - Installs base runtime and ASP.NET Core/WindowsDesktop runtime
   - Supports both x64 and x86 architectures

5. **Cleanup Phase**
   - Removes lower patch versions within each channel
   - Uses .NET Uninstall Tool if available (auto-installs if missing)
   - Falls back to filesystem cleanup if needed
   - 🆕 **Performance optimized** with .NET DirectoryInfo API
   - Verifies cleanup completed successfully

6. **Reporting Phase**
   - Compares disk usage before and after
   - Shows reclaimed space per runtime
   - 🆕 **Enhanced logging** with PowerShell streams (Write-Warning, Write-Error, Write-Information)
   - Exports detailed reports to CSV/JSON

#### Output Examples

**Interactive Menu Mode** (NEW in v2.5):
```
╔═════════════════════════════════════════════════════════════════╗
║            .NET Runtime Maintenance Tool v2.5                   ║
║                                                                 ║
║  System Status (cached, use option 8 to refresh)               ║
║  ─────────────────────────────────────────────────────────     ║
║  • IIS Installed: No                                            ║
║  • ANCM Detected: No                                            ║
║  • .NET Services: 0                                             ║
║  • .NET Tasks: 0                                                ║
║  • Total Disk: 2.4 GB                                           ║
║                                                                 ║
║  Installed Runtimes:                                            ║
║  • ASP.NET Core 8.0.22 x64 (LTS, current)                       ║
║  • ASP.NET Core 9.0.11 x64 (STS, current)                       ║
║  • Desktop 8.0.22 x64 (LTS, current)                            ║
║                                                                 ║
╠═════════════════════════════════════════════════════════════════╣
║  Maintenance Options:                                           ║
║  ─────────────────────────────────────────────────────────     ║
║  [1] Update All Runtimes (patches only)                         ║
║  [2] Remove EOL Runtimes                                        ║
║  [3] Install Specific Runtime Version                           ║
║  [4] Cleanup Lower Patches                                      ║
║  [5] Generate Disk Usage Report                                 ║
║  [6] Show System Dependencies                                   ║
║  [7] Create System Restore Point                                ║
║  [8] Refresh System Status (force scan)                         ║
║  [9] Exit                                                       ║
╚═════════════════════════════════════════════════════════════════╝

Enter selection (1-9):
```

**CLI Automation Mode Output:**
```
=== ASP.NET Core Channel 6.0 x64 ===
EOL channel detected: 6.0 | End of support: 2024-11-12 | Installed: 6.0.14
  → Recommended replacement: .NET 8.0 LTS (supported until 2026-11-10)
  → Will install .NET 8.0 LTS after removal
WARNING: Dependency check: 0 Windows Services, 0 Scheduled Tasks, 0 running processes
Using uninstall tool to remove ASP.NET Core 6.0
Verifying digital signature...
Signature valid (Signer: CN=Microsoft Corporation)
Removal complete for EOL channel 6.0 x64
Installing replacement: .NET 8.0 LTS x64...
Downloading ASP.NET Core Runtime x64...
Verifying SHA512 hash... ✓
Verifying Authenticode signature... ✓
Installing ASP.NET Core Runtime 8.0.22 x64...
Successfully installed .NET 8.0 LTS (8.0.22) x64

=== ASP.NET Core Channel 9.0 x64 ===
Update available: 9.0.8 → 9.0.11 (x64)
Downloading ASP.NET Core Runtime x64...
Verifying SHA512 hash... ✓
Verifying Authenticode signature... ✓
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
- Right-click PowerShell and select "Run as Administrator"
- Required for install/uninstall operations

**Menu doesn't appear:**
- Add `-NonInteractive` to force CLI mode
- Check if parameters were specified (auto-switches to CLI mode)

**"dotnet.exe not found":**
- Ensure .NET SDK or Runtime is installed
- Check paths: `C:\Program Files\dotnet\dotnet.exe` (x64) or `C:\Program Files (x86)\dotnet\dotnet.exe` (x86)

**"Failed to fetch release data":**
- Check internet connectivity
- Verify firewall isn't blocking `dotnetcli.blob.core.windows.net`
- Try `-Force` to bypass cache

**"MSI signature invalid" error:** 🆕
- This is a security feature preventing tampered downloads
- Verify internet connection isn't being intercepted (proxy/firewall)
- Download may be corrupted - script will retry automatically

**Dependency check blocking removal:** 🆕
- Use `-DependencyCheck Warn` to continue with warning only
- Review dependencies with menu option 6
- Manually stop services/tasks before removal if safe

**Cleanup not removing files:**
- Try with `-ForceFileCleanup` to use filesystem method
- Check if files are in use (close running .NET applications)
- Use menu option 4 for interactive cleanup

**Uninstall tool installation fails:**
- Download manually from GitHub: `dotnet/cli-lab` releases
- Install MSI and rerun script with `-AutoInstallUninstallTool:$false`

**Restore point creation fails:** 🆕
- Ensure System Restore is enabled
- Check disk space (requires ~300MB minimum)
- May fail on Windows Server (not supported by default)

#### Scheduled Task Setup

**Full Automation (Recommended for v2.5):**
```powershell
# Run monthly with one-shot cleanup preset
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\Scripts\Update-DotNetRuntimes.ps1`" -OneShotCleanup -LogPath `"C:\Logs\dotnet-update.log`" -ReportPath `"C:\Reports\dotnet-$(Get-Date -Format 'yyyy-MM').csv`""

# 2nd Tuesday of month at 3 AM (Patch Tuesday)
$trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Tuesday -At 3am

$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" `
    -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)

Register-ScheduledTask -TaskName ".NET Runtime Maintenance" `
    -Action $action -Trigger $trigger -Principal $principal `
    -Settings $settings -Description "Updates .NET runtimes, removes EOL versions, and cleans up patches"
```

**Conservative Automation (with dependency protection):**
```powershell
# Run with dependency checks and protected channels
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\Scripts\Update-DotNetRuntimes.ps1`" -NonInteractive -Approve -CleanupLowerPatches -DependencyCheck Block -ProtectChannels 8.0,9.0 -CreateRestorePoint -LogPath `"C:\Logs\dotnet-update.log`""

# Weekly on Sunday at 2 AM
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am

$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" `
    -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName ".NET Runtime Updates (Conservative)" `
    -Action $action -Trigger $trigger -Principal $principal `
    -Settings $settings -Description "Updates .NET runtimes with safety checks"
```

#### Best Practices

**Testing & Validation:**
1. **Test in Dev First** - Run with `-DryRun` to preview changes
2. **Use Interactive Mode** - Try menu mode interactively before automating
3. **Review Dependencies** - Check menu option 6 before removing EOL runtimes

**Production Deployment:**
4. **Schedule During Maintenance** - Run during low-usage periods (Patch Tuesday +1 week)
5. **Create Restore Points** 🆕 - Use `-CreateRestorePoint` before major updates
6. **Enable Dependency Checks** 🆕 - Use `-DependencyCheck Block` on production servers
7. **Protect Critical Channels** 🆕 - Use `-ProtectChannels` to prevent accidental removal

**Operational Excellence:**
8. **Keep LTS Only** - Use `-LtsOnly` for production stability
9. **Monitor Logs** - Enable `-LogPath` for troubleshooting and compliance
10. **Export Reports** - Track disk usage trends with monthly CSV exports
11. **Use OneShotCleanup** 🆕 - Single parameter for complete automation
12. **Force Refresh Weekly** 🆕 - Use `-Force` weekly to ensure fresh data

**Security:**
13. **Never bypass signatures** - Script enforces mandatory Authenticode validation
14. **Run as SYSTEM** - Use scheduled tasks with NT AUTHORITY\SYSTEM
15. **Audit dependency changes** - Review dependency reports before production deployment

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

**Last Updated:** 2025-01-17
