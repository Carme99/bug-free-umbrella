# Optimize-WsusServer.ps1

Comprehensive Windows Server Update Services (WSUS) optimization and maintenance script with interactive configuration wizard and automated scheduling.

## Overview

This PowerShell script provides a complete solution for WSUS server maintenance, including deep cleaning of obsolete updates, database optimization, IIS configuration management, and automated scheduling. It modernizes and enhances WSUS management with an interactive wizard for easy setup.

## Credits

**Original Author:** Austin Warren (awarre)
**Original Repository:** [awarre/Optimize-WsusServer](https://github.com/awarre/Optimize-WsusServer) (v1.2.1)
**Modified By:** Carme99
**Version:** 2.0.0
**Last Updated:** 2025-01-09

This script is based on Austin Warren's excellent WSUS optimization script and has been modernized with enhanced features, improved syntax, and additional functionality for 2025.

## Features

- **Interactive Configuration Wizard** - First-time setup with guided prompts for all settings
- **Deep Cleaning** - Remove obsolete updates by product and title (Windows XP, Vista, 7, 8, legacy Office, etc.)
- **IIS Configuration** - Validate and optimize IIS settings for WSUS
- **Driver Management** - Disable driver synchronization to reduce database bloat
- **Database Optimization** - Microsoft best practice SQL reindexing and statistics updates
- **Scheduled Tasks** - Automatic creation of daily, weekly, and monthly maintenance tasks
- **Comprehensive Logging** - Detailed logging with configurable verbosity and retention
- **Safety Features** - Backups, confirmations, and rollback capabilities
- **Progress Tracking** - Real-time progress indicators for long-running operations

## Requirements

- Windows Server 2016 or later
- WSUS role installed and configured
- SQL Server (Windows Internal Database or Full SQL Server)
- PowerShell 5.1 or later
- Required PowerShell Modules:
  - `SqlServer`
  - `UpdateServices`
  - `WebAdministration`
- Administrator privileges (Run as Administrator)

## Installation

1. Download the script to your WSUS server:
   ```powershell
   # Download to default location
   New-Item -Path "C:\Scripts\WSUS" -ItemType Directory -Force
   # Copy Optimize-WsusServer.ps1 to C:\Scripts\WSUS\
   ```

2. Ensure required modules are installed:
   ```powershell
   Install-Module -Name SqlServer -Force
   Import-Module UpdateServices
   Import-Module WebAdministration
   ```

3. Run the interactive wizard for first-time setup:
   ```powershell
   .\Optimize-WsusServer.ps1 -Interactive
   ```

## Usage

### Interactive Mode (Recommended for First Run)

Launch the configuration wizard that guides you through all settings:

```powershell
.\Optimize-WsusServer.ps1 -Interactive
```

The wizard will:
- Configure deep cleaning settings
- Set up driver synchronization preferences
- Create scheduled maintenance tasks (daily, weekly, monthly)
- Offer to run initial optimization

### Command-Line Operations

After configuration, run specific operations:

```powershell
# Run all built-in WSUS cleanup processes
.\Optimize-WsusServer.ps1 -OptimizeServer

# Optimize database (reindex, update statistics)
.\Optimize-WsusServer.ps1 -OptimizeDatabase

# Decline superseded updates
.\Optimize-WsusServer.ps1 -DeclineSupersededUpdates

# Deep clean obsolete updates
.\Optimize-WsusServer.ps1 -DeepClean

# Disable driver synchronization
.\Optimize-WsusServer.ps1 -DisableDrivers

# Check IIS configuration
.\Optimize-WsusServer.ps1 -CheckConfig

# Create scheduled tasks from config
.\Optimize-WsusServer.ps1 -CreateTasks
```

### Combined Operations

Run multiple operations in sequence:

```powershell
# Full optimization
.\Optimize-WsusServer.ps1 -OptimizeServer -OptimizeDatabase -CheckConfig

# Deep clean with optimization
.\Optimize-WsusServer.ps1 -DeepClean -OptimizeServer -OptimizeDatabase
```

### Custom Configuration File

Use a custom configuration file location:

```powershell
.\Optimize-WsusServer.ps1 -ConfigFile "C:\Custom\wsus-config.json" -OptimizeServer
```

### Custom Log Path

Specify a custom log file location:

```powershell
.\Optimize-WsusServer.ps1 -LogPath "D:\Logs\wsus-optimization.log" -OptimizeServer
```

## Configuration

The script uses a JSON configuration file (default: `C:\Scripts\WSUS\wsus-config.json`) that stores:

- **Deep Clean Settings** - Lists of obsolete products and update titles to remove
- **IIS Settings** - Recommended IIS configuration values
- **Scheduled Tasks** - Task schedules and enabled operations
- **Features** - Enable/disable driver sync, custom indexes, etc.
- **Logging** - Log path, retention, and verbosity settings

### Configuration File Structure

```json
{
  "Version": "2.0.0",
  "DeepClean": {
    "Enabled": true,
    "UnneededProductTitles": [
      "Windows 7", "Windows 8", "Office 2010", ...
    ],
    "UnneededUpdateTitles": [
      "Internet Explorer 8", "Itanium", ...
    ],
    "RemoveDrivers": true,
    "DeclineSuperseded": true
  },
  "ScheduledTasks": {
    "Daily": {
      "Enabled": true,
      "Time": "02:00",
      "Actions": ["OptimizeServer", "DeclineSupersededUpdates"]
    },
    "Weekly": {
      "Enabled": true,
      "DayOfWeek": "Sunday",
      "Time": "03:00",
      "Actions": ["OptimizeDatabase", "CheckConfig"]
    },
    "Monthly": {
      "Enabled": false,
      "Day": 1,
      "Time": "04:00",
      "Actions": ["DeepClean"]
    }
  },
  "Features": {
    "DisableDriverSync": true,
    "CreateCustomIndexes": true
  }
}
```

## Scheduled Tasks

The script can create three types of scheduled tasks:

### Daily Task (WSUS-DailyOptimization)
- Default Time: 02:00
- Operations:
  - Run WSUS server cleanup
  - Decline superseded updates

### Weekly Task (WSUS-WeeklyOptimization)
- Default: Sunday at 03:00
- Operations:
  - Database optimization (reindex, statistics)
  - IIS configuration validation

### Monthly Task (WSUS-MonthlyDeepClean)
- Default: Day 1 at 04:00
- Operations:
  - Deep clean obsolete products and updates
  - Remove drivers (if configured)

All tasks run as SYSTEM with highest privileges.

## Deep Cleaning

The deep clean feature removes updates for obsolete products and filters by update titles. Default lists include:

### Obsolete Products (EOL)
- Windows 2000, XP, Vista, 7, 8, 8.1
- Windows Server 2003, 2003 R2, 2008, 2008 R2
- Office 2002, 2003, 2007, 2010
- SQL Server 2000, 2005, 2008
- Legacy products (Lync 2010/2013, Virtual PC, etc.)

### Update Title Filters
- Internet Explorer 6-10
- Itanium and ARM64 architectures
- Consumer editions (if enterprise-only)
- Language packs (if English-only)

**Customize these lists** in the interactive wizard or by editing the configuration file to match your environment.

## Database Optimization

The script performs Microsoft-recommended database maintenance:

1. **Custom Index Creation** - Creates optimized indexes on key tables:
   - `tbLocalizedPropertyForRevision`
   - `tbRevisionSupersedesUpdate`

2. **Statistics Update** - Runs `sp_updatestats` for query plan optimization

3. **Index Rebuild** - Rebuilds fragmented indexes (>10% fragmentation)

4. **Progress Reporting** - Tracks and reports each optimization step

## IIS Configuration

Validates and applies recommended IIS settings for WSUS:

| Setting | Recommended Value |
|---------|-------------------|
| Queue Length | 25000 |
| CPU Reset Interval | 15 minutes |
| Recycling Memory | 0 (disabled) |
| Private Memory Limit | 0 (disabled) |
| Max Request Length | 204800 KB |
| Execution Timeout | 7200 seconds |

The script backs up `web.config` before making changes.

## Logging

Logs are written to `C:\Scripts\WSUS\Logs\wsus-optimization.log` by default.

### Log Levels
- **Info** - Normal operations and status messages
- **Warning** - Non-critical issues that should be reviewed
- **Error** - Critical failures that prevent operation
- **Success** - Successful completion of operations

### Log Management
- Configurable retention period (default: 30 days)
- Optional verbose logging
- Automatic log directory creation

## Safety Features

1. **Backups** - Web.config files are backed up before modification
2. **Confirmations** - ShouldProcess support for `-WhatIf` and `-Confirm`
3. **Error Handling** - Try/catch blocks with detailed error logging
4. **Validation** - Configuration validation before applying changes
5. **Progress Tracking** - Real-time feedback during long operations

## Troubleshooting

### Script Won't Run
- Ensure you're running PowerShell as Administrator
- Check execution policy: `Set-ExecutionPolicy RemoteSigned -Scope LocalMachine`
- Verify required modules are installed

### Database Optimization Fails
- Verify SQL Server/WID service is running
- Check if SUSDB database is accessible
- Ensure sufficient disk space for index rebuilds
- Review SQL query timeout settings

### IIS Configuration Fails
- Verify WebAdministration module is loaded
- Check WsusPool app pool exists
- Ensure WSUS Administration site is running
- Review IIS permissions

### Scheduled Tasks Don't Run
- Verify tasks were created: `Get-ScheduledTask -TaskName "WSUS-*"`
- Check task history in Task Scheduler
- Ensure SYSTEM account has necessary permissions
- Review script path in task action

### Updates Not Being Declined
- Verify WSUS server connection
- Check filter criteria in configuration
- Review update approval states
- Ensure sufficient permissions

## Best Practices

1. **Run Interactive Wizard First** - Configure all settings before scheduling
2. **Test in Non-Production** - Validate settings in a test environment
3. **Review Deep Clean Lists** - Customize product/title lists for your environment
4. **Monitor Initial Runs** - Watch logs during first few scheduled executions
5. **Regular Database Maintenance** - Run weekly database optimization minimum
6. **Backup WSUS** - Maintain regular backups before major cleanups
7. **Review Declined Updates** - Periodically audit declined updates
8. **Disable Driver Sync** - Unless specifically needed, disable to reduce bloat
9. **Schedule Off-Hours** - Run intensive operations during low-usage periods
10. **Monitor Disk Space** - Ensure adequate space for database operations

## Performance Considerations

- **Deep Clean** - First run can take several hours depending on update count
- **Database Optimization** - Duration scales with database size (typically 30-90 minutes)
- **Superseded Updates** - Can decline thousands of updates on first run
- **Driver Removal** - Drivers can represent significant database space

## Version History

### Version 2.0.0 (2025-01-09) - Carme99
- Fixed all syntax errors in regex patterns and validation
- Added comprehensive header documentation
- Enhanced error handling and logging
- Modernized for PowerShell 5.1+ and Windows Server 2016+
- Improved interactive wizard user experience
- Added progress indicators for long-running operations
- Enhanced configuration management
- Improved scheduled task creation

### Version 1.2.1 (Original) - Austin Warren
- Original WSUS optimization implementation
- Deep cleaning capabilities
- Database optimization
- IIS configuration management
- Scheduled task support

## License

This script maintains the original license from Austin Warren's repository. Please refer to the [original repository](https://github.com/awarre/Optimize-WsusServer) for licensing details.

## Contributing

Contributions and improvements are welcome! When contributing:
1. Maintain backward compatibility with existing configurations
2. Document all changes in the version history
3. Test thoroughly on multiple WSUS environments
4. Follow existing code style and conventions
5. Update this documentation as needed

## Support

For issues specific to this modernized version, please file issues in the Carme99/bug-free-umbrella repository.

For questions about the original implementation, refer to the [original repository](https://github.com/awarre/Optimize-WsusServer) by Austin Warren.

## Related Resources

- [Microsoft WSUS Documentation](https://docs.microsoft.com/en-us/windows-server/administration/windows-server-update-services/get-started/windows-server-update-services-wsus)
- [WSUS Best Practices](https://docs.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-best-practices)
- [Original Optimize-WsusServer by Austin Warren](https://github.com/awarre/Optimize-WsusServer)

## Acknowledgments

Special thanks to **Austin Warren** ([@awarre](https://github.com/awarre)) for creating the original Optimize-WsusServer script that formed the foundation of this modernized version. The original script has been invaluable to the WSUS administrator community.
