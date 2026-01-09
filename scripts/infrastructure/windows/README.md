# Windows Server Management Scripts


> **⚠️ IMPORTANT NOTICE**: The vast majority of scripts in this repository have not been thoroughly tested in production environments. Please test all scripts in a non-production environment first and validate the results before relying on this data for operational decisions.

A comprehensive collection of PowerShell scripts for managing Windows Server 2016, 2019, and 2022 environments.

## 📋 Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Scripts](#scripts)
  - [Reset Windows Update](#1-reset-windows-update)
  - [Check System Integrity](#2-check-system-integrity)
  - [Get Disk Report](#3-get-disk-report)
  - [Set English UK Regional Settings](#4-set-english-uk-regional-settings)
  - [Remove US Language Pack](#5-remove-us-language-pack)
  - [New Weekly Reboot Schedule](#17-new-weekly-reboot-schedule)
  - [Optimize WSUS Server](#18-optimize-wsus-server)
- [Usage Guidelines](#usage-guidelines)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

This collection provides essential system administration tools for Windows Server environments, focusing on:

- **System Maintenance**: Windows Update management and system integrity verification
- **Disk Management**: Comprehensive disk usage analysis and cleanup recommendations
- **Regional Configuration**: Automated locale and language pack management for UK environments

All scripts are designed with safety in mind, include detailed logging, and support common parameters for automation.

---

## Requirements

### System Requirements
- Windows Server 2016, 2019, or 2022
- PowerShell 5.1 or later
- Administrator privileges

### PowerShell Modules
Most scripts use built-in modules. Additional requirements are automatically checked and reported.

---

## Scripts

### Monitoring & Health

#### 1. Monitor-ServerHealth

**File**: `Monitor-ServerHealth.ps1`

Comprehensive real-time health monitoring for Windows Server.

**Features**:
- CPU utilization and trending
- Memory usage and available RAM
- Disk space and I/O performance
- Critical service status monitoring
- Event log error analysis (last 24 hours)
- Network adapter status
- System uptime tracking
- Process resource consumption analysis

**Usage**:
```powershell
# Standard health check
.\Monitor-ServerHealth.ps1

# With high alert sensitivity and HTML report
.\Monitor-ServerHealth.ps1 -AlertThreshold High -ExportReport

# Monitor specific services
.\Monitor-ServerHealth.ps1 -CheckServices "W3SVC,MSSQLSERVER"
```

**Parameters**:
- `-ExportReport` - Exports detailed report to HTML
- `-AlertThreshold` - Set threshold: High, Medium, Low (default: Medium)
- `-CheckServices` - Additional services to monitor
- `-EmailReport` - Send report via email (requires SMTP configuration)

---

#### 2. Get-EventLogReport

**File**: `Get-EventLogReport.ps1`

Analyzes Windows event logs for critical errors and security events.

**Features**:
- System, Application, and Security log analysis
- Event frequency and pattern detection
- Top error sources identification
- Customizable time range and severity filtering
- Export to HTML or CSV

**Usage**:
```powershell
# Analyze all logs for errors (last 24 hours)
.\Get-EventLogReport.ps1

# System log warnings for last 7 days
.\Get-EventLogReport.ps1 -LogName System -Days 7 -Severity Warning -ExportHTML

# Security log analysis
.\Get-EventLogReport.ps1 -LogName Security -Hours 12 -ExportCSV
```

**Parameters**:
- `-LogName` - Log to analyze: System, Application, Security, All (default: All)
- `-Hours` - Hours to look back (default: 24)
- `-Days` - Days to look back (overrides Hours)
- `-Severity` - Filter: Critical, Error, Warning, All (default: Error)
- `-MaxEvents` - Maximum events per log (default: 1000)
- `-ExportHTML` / `-ExportCSV` - Export options
- `-GroupBySource` - Group events by source for pattern analysis

---

#### 3. Get-PerformanceReport

**File**: `Get-PerformanceReport.ps1`

Generates comprehensive performance metrics and bottleneck analysis.

**Features**:
- CPU usage trends and peak time identification
- Memory consumption patterns
- Disk I/O performance (IOPS, latency, queue length)
- Network bandwidth utilization
- Top resource-consuming processes
- Performance counter analysis
- Bottleneck identification
- HTML export with graphs

**Usage**:
```powershell
# Standard 5-minute performance capture
.\Get-PerformanceReport.ps1

# Extended 10-minute capture with HTML report
.\Get-PerformanceReport.ps1 -DurationMinutes 10 -SampleInterval 2 -ExportHTML

# Detailed disk and network analysis
.\Get-PerformanceReport.ps1 -IncludeDiskIO -IncludeNetworkStats -ExportHTML
```

**Parameters**:
- `-DurationMinutes` - Collection duration (default: 5)
- `-SampleInterval` - Interval between samples in seconds (default: 5)
- `-IncludeDiskIO` - Include detailed disk I/O analysis
- `-IncludeNetworkStats` - Include network statistics
- `-ExportHTML` / `-ExportCSV` - Export options

---

### Network & Connectivity

#### 4. Test-ServerConnectivity

**File**: `Test-ServerConnectivity.ps1`

Comprehensive network connectivity testing including ping, port checks, and DNS resolution.

**Features**:
- ICMP ping tests with latency measurement
- TCP port connectivity tests
- DNS resolution verification
- Trace route analysis
- Network path MTU discovery
- Supports multiple targets and ports
- Export to HTML or CSV

**Usage**:
```powershell
# Basic connectivity test
.\Test-ServerConnectivity.ps1 -ComputerName "server01.domain.com"

# Test specific ports
.\Test-ServerConnectivity.ps1 -ComputerName "webserver" -Port 80,443

# Comprehensive test with trace route
.\Test-ServerConnectivity.ps1 -ComputerName "dc01","dc02" -Port 389,636 -IncludeTraceRoute -ExportHTML
```

**Parameters**:
- `-ComputerName` - Target computer(s) (hostname, FQDN, or IP)
- `-Port` - TCP port(s) to test
- `-PingCount` - Number of ping attempts (default: 4)
- `-Timeout` - Timeout in milliseconds (default: 3000)
- `-IncludeTraceRoute` - Perform trace route
- `-ExportHTML` / `-ExportCSV` - Export options

**Common Ports**: 80 (HTTP), 443 (HTTPS), 3389 (RDP), 445 (SMB), 1433 (SQL)

---

#### 5. Get-NetworkConfiguration

**File**: `Get-NetworkConfiguration.ps1`

Documents complete network configuration for Windows Server.

**Features**:
- Network adapter details and status
- IP configuration (IPv4, IPv6, DNS, DHCP)
- Routing table
- DNS resolver configuration
- Network adapter advanced properties
- Network bindings and protocols
- Firewall profile status
- Network shares

**Usage**:
```powershell
# Basic network configuration
.\Get-NetworkConfiguration.ps1

# Comprehensive documentation
.\Get-NetworkConfiguration.ps1 -IncludeRouting -IncludeShares -IncludeFirewall -ExportHTML
```

**Parameters**:
- `-IncludeRouting` - Include routing table
- `-IncludeShares` - Include network shares
- `-IncludeFirewall` - Include firewall profile status
- `-ExportHTML` / `-ExportCSV` - Export options

**Use Cases**: Documentation, troubleshooting, compliance audits

---

#### 6. Get-FirewallRulesReport

**File**: `Get-FirewallRulesReport.ps1`

Generates detailed reports on Windows Firewall rules.

**Features**:
- Lists all firewall rules with details
- Filter by profile, direction, or action
- Identify enabled/disabled rules
- Port and application mapping
- Export to HTML or CSV

**Usage**:
```powershell
# All firewall rules
.\Get-FirewallRulesReport.ps1 -ExportHTML

# Only enabled inbound rules
.\Get-FirewallRulesReport.ps1 -Direction Inbound -Enabled $true -ExportHTML
```

---

### Security & Compliance

#### 7. Test-CertificateExpiration

**File**: `Test-CertificateExpiration.ps1`

Checks SSL/TLS certificates for expiration across local stores and remote servers.

**Features**:
- Local certificate store scanning
- Remote server certificate checking
- Expiration warnings with configurable thresholds
- Subject Alternative Name (SAN) analysis
- Export to HTML or CSV

**Usage**:
```powershell
# Check local certificates
.\Test-CertificateExpiration.ps1 -CheckLocal -ExportHTML

# Check remote server certificates
.\Test-CertificateExpiration.ps1 -ComputerName "webserver.domain.com" -Port 443

# Custom warning threshold (30 days)
.\Test-CertificateExpiration.ps1 -CheckLocal -WarningDays 30
```

**Parameters**:
- `-CheckLocal` - Scan local certificate stores
- `-ComputerName` - Remote server(s) to check
- `-Port` - Port for SSL/TLS connection (default: 443)
- `-WarningDays` - Days before expiration to warn (default: 60)
- `-ExportHTML` / `-ExportCSV` - Export options

---

### Storage Management

#### 8. Get-DiskReport (Original)

**File**: `Get-DiskReport.ps1`

Analyzes disk usage and provides cleanup suggestions with potential space savings.

---

#### 9. Optimize-ServerStorage

**File**: `Optimize-ServerStorage.ps1`

Automated disk cleanup and optimization for Windows Server.

**Features**:
- Windows Update cleanup (old updates, download cache)
- Temporary file removal (Windows Temp, User Temp, IIS logs)
- Log file rotation and cleanup
- Recycle Bin cleanup
- Windows Error Reporting archives
- Thumbnail cache cleanup
- Shadow copy management
- IIS log cleanup
- Optional DISM component store cleanup
- Reports space saved

**Usage**:
```powershell
# Preview cleanup (WhatIf mode)
.\Optimize-ServerStorage.ps1 -WhatIf

# Full cleanup on C: drive
.\Optimize-ServerStorage.ps1 -DriveLetter C -IncludeWindowsUpdate -Force

# Clean IIS logs older than 14 days
.\Optimize-ServerStorage.ps1 -IncludeIISLogs -IISLogRetentionDays 14
```

**Parameters**:
- `-DriveLetter` - Target drive (default: all drives)
- `-IncludeWindowsUpdate` - Clean Windows Update cache
- `-IncludeIISLogs` - Clean old IIS logs
- `-IISLogRetentionDays` - IIS log retention (default: 30)
- `-IncludeDISM` - Run DISM component cleanup
- `-WhatIf` - Preview without deleting
- `-Force` - Skip confirmation prompts

**Typical Space Savings**: 5-20 GB depending on system age and usage

---

#### 10. Get-LargeFilesReport

**File**: `Get-LargeFilesReport.ps1`

Identifies and reports large files consuming disk space.

**Features**:
- Top largest files by size
- Files grouped by type/extension
- Optional duplicate file detection
- Age analysis of large files
- Customizable size threshold
- Interactive cleanup suggestions
- Export to HTML or CSV

**Usage**:
```powershell
# Scan all drives for files > 100 MB
.\Get-LargeFilesReport.ps1

# Find files > 500 MB with duplicate detection
.\Get-LargeFilesReport.ps1 -MinimumSizeMB 500 -IncludeDuplicates -ExportHTML

# Scan specific path, exclude system folders
.\Get-LargeFilesReport.ps1 -Path "D:\Data" -ExcludePath "D:\Data\Backups"
```

**Parameters**:
- `-Path` - Path to scan (default: all fixed drives)
- `-MinimumSizeMB` - Minimum file size (default: 100 MB)
- `-TopCount` - Number of largest files to report (default: 50)
- `-IncludeDuplicates` - Scan for duplicates (by size and hash)
- `-ExcludePath` - Paths to exclude
- `-ExportHTML` / `-ExportCSV` - Export options

---

### Active Directory

#### 11. Get-ADHealthCheck

**File**: `Get-ADHealthCheck.ps1`

Comprehensive Active Directory health check for domain controllers.

**Features**:
- Domain controller availability and connectivity
- AD replication status and error detection
- FSMO role holder identification
- DNS service status
- SYSVOL and NETLOGON share accessibility
- AD database and log file size monitoring
- Event log analysis (AD-related errors)
- Service status (AD DS, DNS, KDC, Netlogon)
- Time synchronization status
- Export to HTML or CSV

**Usage**:
```powershell
# Basic health check on all DCs
.\Get-ADHealthCheck.ps1

# Comprehensive check with replication and event logs
.\Get-ADHealthCheck.ps1 -IncludeReplication -IncludeEventLogs -ExportHTML

# Check specific domain controller
.\Get-ADHealthCheck.ps1 -DomainController "DC01.domain.com"
```

**Parameters**:
- `-DomainController` - Specific DC to check (default: all DCs)
- `-IncludeReplication` - Include detailed replication status
- `-IncludeEventLogs` - Analyze AD-related event logs
- `-ExportHTML` / `-ExportCSV` - Export options

**Requirements**:
- Active Directory PowerShell module
- Domain Admin or equivalent permissions
- Must run from domain-joined computer

---

#### 12. Find-InactiveADComputers

**File**: `Find-InactiveADComputers.ps1`

Identifies inactive computer accounts in Active Directory.

**Features**:
- Finds computers that haven't logged in for specified days
- Filters by OU, operating system, or other criteria
- Option to disable or delete stale accounts
- Export list to CSV
- Supports WhatIf mode for safe testing

**Usage**:
```powershell
# Find computers inactive for 90+ days
.\Find-InactiveADComputers.ps1 -DaysInactive 90 -ExportHTML

# Disable inactive computers (with confirmation)
.\Find-InactiveADComputers.ps1 -DaysInactive 120 -Action Disable

# Preview deletion (WhatIf)
.\Find-InactiveADComputers.ps1 -DaysInactive 180 -Action Delete -WhatIf
```

**Parameters**:
- `-DaysInactive` - Inactivity threshold (default: 90)
- `-Action` - Report, Disable, or Delete (default: Report)
- `-SearchBase` - Specific OU to search
- `-ExcludeOU` - OUs to exclude from search
- `-WhatIf` - Preview changes without executing
- `-ExportHTML` / `-ExportCSV` - Export options

---

### System Maintenance

#### 13. Reset Windows Update

**File**: `Reset-WindowsUpdate.ps1`

Resolves Windows Update issues by resetting all update components.

#### Features
- Stops and restarts Windows Update services
- Clears update cache and temporary files
- Re-registers Windows Update DLLs
- Resets Windows Update policies
- Optional BITS queue cleanup

#### Usage

**Basic Reset**:
```powershell
.\Reset-WindowsUpdate.ps1
```

**Full Reset** (includes BITS and Cryptographic services):
```powershell
.\Reset-WindowsUpdate.ps1 -FullReset
```

#### When to Use
- Windows Update is stuck or failing
- Updates won't download or install
- Error codes: 0x80070002, 0x8024402F, 0x80244007
- After resolving update conflicts

#### Output
- Real-time logging with color-coded status
- Service stop/start confirmation
- DLL registration count
- Final status report

---

### 14. Check System Integrity

**File**: `Check-SystemIntegrity.ps1`

Comprehensive system health verification using SFC, DISM, and event log analysis.

#### Features
- System File Checker (SFC) scan
- DISM component store verification
- Disk health analysis
- Critical event log review (24-hour window)
- Optional HTML report generation
- Automatic repair capability

#### Usage

**Standard Check**:
```powershell
.\Check-SystemIntegrity.ps1
```

**Quick Scan** (SFC only - faster):
```powershell
.\Check-SystemIntegrity.ps1 -QuickScan
```

**Auto-Repair with Report**:
```powershell
.\Check-SystemIntegrity.ps1 -AutoRepair -GenerateReport
```

#### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-QuickScan` | Runs SFC and basic DISM only | False |
| `-AutoRepair` | Automatically repairs detected issues | False |
| `-GenerateReport` | Creates HTML report on desktop | False |

#### Scan Time
- Quick Scan: 5-10 minutes
- Full Scan: 15-30 minutes
- With Repair: 20-45 minutes

#### When to Use
- Before major system changes
- After failed updates
- Troubleshooting system instability
- Regular health checks (monthly recommended)
- Server acting abnormally

---

### 15. Set English UK Regional Settings

**File**: `Set-EnglishUKRegion.ps1`

Configures Windows Server to use English (UK) regional settings system-wide.

---

### 16. Remove US Language Pack

**File**: `Remove-USLanguagePack.ps1`

Removes US English (en-US) language packs and ensures UK English is properly configured.

---

## Legacy Scripts

The following scripts provide disk analysis functionality and are complemented by the newer Optimize-ServerStorage.ps1 and Get-LargeFilesReport.ps1 scripts.

### Get Disk Report (Original)

**File**: `Get-DiskReport.ps1`

Analyzes disk usage and provides cleanup suggestions with potential space savings.

#### Features
- Detailed disk space analysis per volume
- Top 20 largest folders identification
- Temporary file analysis
- Log file analysis (System, IIS, WER)
- Windows Update cache size
- Recycle Bin analysis
- Safe cleanup command generation
- HTML report export

#### Usage

**Analyze All Drives**:
```powershell
.\Get-DiskReport.ps1
```

**Analyze Specific Drive with Report**:
```powershell
.\Get-DiskReport.ps1 -DriveLetter C -ExportReport
```

**Show Cleanup Suggestions Only**:
```powershell
.\Get-DiskReport.ps1 -ShowCleanupOnly
```

**Custom Minimum Folder Size**:
```powershell
.\Get-DiskReport.ps1 -MinimumFolderSizeMB 500
```

#### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-DriveLetter` | Specific drive to analyze (e.g., 'C') | All drives |
| `-ExportReport` | Generate HTML report | False |
| `-ShowCleanupOnly` | Skip full analysis, show cleanup only | False |
| `-MinimumFolderSizeMB` | Minimum folder size to include | 100 MB |

#### Cleanup Categories

The script identifies and suggests cleanup for:

1. **Windows Temp Files** (Low Risk)
   - Location: `C:\Windows\Temp`
   - Suggestion: Delete files older than 7 days

2. **User Temp Files** (Low Risk)
   - Location: `C:\Users\*\AppData\Local\Temp`
   - Suggestion: Delete files older than 7 days

3. **Windows Update Cache** (Low Risk)
   - Location: `C:\Windows\SoftwareDistribution\Download`
   - Suggestion: Clear after stopping wuauserv

4. **IIS Log Files** (Medium Risk)
   - Location: `C:\inetpub\logs\LogFiles`
   - Suggestion: Archive/delete logs older than 90 days

5. **Windows Error Reports** (Low Risk)
   - Location: `C:\ProgramData\Microsoft\Windows\WER`
   - Suggestion: Delete old error reports

6. **Recycle Bin** (Low Risk)
   - Suggestion: Empty permanently

7. **Old System Logs** (Low Risk)
   - Locations: Various log directories
   - Suggestion: Delete logs older than 90 days

8. **Previous Windows Installation** (Medium Risk)
   - Location: `C:\Windows.old`
   - Warning: Cannot rollback after deletion

#### Output Example
```
[2024-01-15 10:30:15] Starting disk analysis on SERVER01...

--- Drive C: ---
Total Size:    500.00 GB
Used Space:    380.50 GB
Free Space:    119.50 GB
Free Percent:  23.90%

========================================
CLEANUP SUGGESTIONS
========================================
Total Potential Savings: 45.32 GB

Category              Path                                    Size       Action
--------              ----                                    ----       ------
Windows Update Cache  C:\Windows\SoftwareDistribution\...    15.50 GB   Clear cache
IIS Log Files         C:\inetpub\logs\LogFiles               12.80 GB   Archive old logs
Windows Temp Files    C:\Windows\Temp                         8.20 GB   Delete old files
```


#### Features
- Sets system locale to en-GB
- Configures UK timezone (GMT/BST)
- Sets UK date format (DD/MM/YYYY)
- Configures 24-hour time format
- Sets currency to GBP (£)
- Configures metric measurements
- Sets first day of week to Monday
- Applies UK keyboard layout
- System-wide application (default user + welcome screen)
- Optional existing user profile updates

#### Usage

**Standard Configuration**:
```powershell
.\Set-EnglishUKRegion.ps1
```

**Apply to All Users**:
```powershell
.\Set-EnglishUKRegion.ps1 -ApplyToExistingUsers
```

**Custom Timezone**:
```powershell
.\Set-EnglishUKRegion.ps1 -TimeZone "GMT Standard Time"
```

**Skip Components**:
```powershell
.\Set-EnglishUKRegion.ps1 -SkipTimeZone -SkipKeyboard
```

#### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-TimeZone` | Timezone to set | GMT Standard Time |
| `-ApplyToExistingUsers` | Update all existing user profiles | False |
| `-SkipTimeZone` | Skip timezone configuration | False |
| `-SkipKeyboard` | Skip keyboard layout configuration | False |

#### Settings Applied

| Setting | Value |
|---------|-------|
| System Locale | en-GB |
| UI Language | English (United Kingdom) |
| Timezone | GMT Standard Time |
| Date Format | DD/MM/YYYY |
| Time Format | HH:mm:ss (24-hour) |
| Currency | £ (GBP) |
| Decimal Separator | . |
| Thousands Separator | , |
| First Day of Week | Monday |
| Measurement System | Metric |
| Keyboard Layout | UK English (0809:00000809) |

#### Important Notes
- A system restart is recommended after running
- Settings apply to system, new users, and welcome screen
- Existing users are only updated if `-ApplyToExistingUsers` is specified
- The script will prompt for restart unless automated


#### Features
- Verifies en-GB is installed before removal
- Removes en-US language pack via DISM
- Removes US keyboard layout
- Cleans up language features on demand (FOD)
- Registry cleanup
- Optional system restore point creation
- Safety checks to prevent language removal issues

#### Usage

**Standard Removal**:
```powershell
.\Remove-USLanguagePack.ps1
```

**Force Removal with Backup**:
```powershell
.\Remove-USLanguagePack.ps1 -Force -BackupFirst
```

**Keep US Keyboard**:
```powershell
.\Remove-USLanguagePack.ps1 -KeepKeyboard
```

#### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-Force` | Skip confirmation prompts | False |
| `-KeepKeyboard` | Keep US keyboard layout | False |
| `-BackupFirst` | Create system restore point | False |

#### Safety Features

1. **Pre-flight Checks**:
   - Verifies en-GB is installed
   - Offers to install en-GB if missing
   - Confirms en-US is present

2. **Protection**:
   - Sets en-GB as default before removal
   - Optional restore point creation
   - Confirmation prompts (unless -Force)

3. **Thorough Removal**:
   - Language pack removal via DISM
   - Keyboard layout cleanup
   - Features on Demand removal
   - Registry cleanup
   - Verification step

#### What Gets Removed
- Microsoft-Windows-Client-Language-Pack (en-US)
- US keyboard layouts (unless `-KeepKeyboard`)
- Language.Basic~en-US
- Language.Handwriting~en-US
- Language.OCR~en-US
- Language.Speech~en-US
- Language.TextToSpeech~en-US
- Registry entries for en-US

#### Important Notes
- **Requires restart** to complete removal
- En-GB must be installed first
- Some residual entries may remain until restart
- Cannot be easily reversed - use `-BackupFirst` if uncertain

---

## Usage Guidelines

### Running Scripts

1. **Open PowerShell as Administrator**
   ```powershell
   # Right-click PowerShell and select "Run as Administrator"
   ```

2. **Navigate to Script Directory**
   ```powershell
   cd "C:\Path\To\Server Management Scripts"
   ```

3. **Check Execution Policy**
   ```powershell
   Get-ExecutionPolicy
   ```
   If restricted, temporarily allow:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   ```

4. **Run Script**
   ```powershell
   .\ScriptName.ps1 -Parameters
   ```

### Getting Help

All scripts include detailed help:
```powershell
Get-Help .\ScriptName.ps1 -Detailed
Get-Help .\ScriptName.ps1 -Examples
Get-Help .\ScriptName.ps1 -Full
```

---

## Best Practices

### Before Running Scripts

1. **Take Backups**
   - Create system restore point
   - Backup critical data
   - Document current configuration

2. **Test in Non-Production**
   - Run on test server first
   - Verify expected behavior
   - Check for conflicts

3. **Review Parameters**
   - Read script help
   - Understand what changes will be made
   - Use appropriate switches

### During Execution

1. **Monitor Output**
   - Watch for errors or warnings
   - Note any failed operations
   - Check log messages

2. **Don't Interrupt**
   - Allow scripts to complete
   - Avoid Ctrl+C during critical operations
   - Wait for confirmation messages

### After Execution

1. **Verify Changes**
   - Check that expected changes were applied
   - Test affected functionality
   - Review generated reports

2. **Restart if Recommended**
   - Many changes require restart
   - Schedule during maintenance window
   - Notify users if applicable

3. **Keep Logs**
   - Save HTML reports
   - Note any errors for troubleshooting
   - Document successful runs

---

## Troubleshooting

### Common Issues

#### "Access Denied" Errors
**Cause**: Not running as Administrator
**Solution**:
```powershell
# Right-click PowerShell > Run as Administrator
```

#### "Execution Policy" Errors
**Cause**: Script execution is disabled
**Solution**:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
# Then run your script
```

#### Script Doesn't Start
**Cause**: Path issues or incorrect file name
**Solution**:
```powershell
# Ensure you're in the correct directory
cd "C:\Path\To\Server Management Scripts"

# List files to verify name
Get-ChildItem *.ps1

# Run with full path if needed
& "C:\Path\To\Server Management Scripts\ScriptName.ps1"
```

#### Changes Don't Apply
**Cause**: Restart required
**Solution**: Restart the server after running scripts that modify system settings

#### "Module Not Found" Errors
**Cause**: Required PowerShell module not available
**Solution**: Scripts will report missing modules - install if needed

### Script-Specific Issues

#### Reset-WindowsUpdate.ps1
- **Issue**: Services won't stop
  - Try running multiple times
  - Check for group policy restrictions
  - Reboot and retry

#### Check-SystemIntegrity.ps1
- **Issue**: Scan takes too long
  - Use `-QuickScan` for faster results
  - Run during low-usage periods
  - Check disk performance

#### Get-DiskReport.ps1
- **Issue**: Folder analysis is slow
  - Increase `-MinimumFolderSizeMB` to reduce scan scope
  - Use `-ShowCleanupOnly` to skip full analysis
  - Run on specific drives only

#### Set-EnglishUKRegion.ps1
- **Issue**: Settings revert after restart
  - Use `-ApplyToExistingUsers`
  - Check for group policy overrides
  - Verify changes applied to default user profile

#### Remove-USLanguagePack.ps1
- **Issue**: en-US still appears after removal
  - Restart the server
  - Run DISM cleanup: `DISM /Online /Cleanup-Image /StartComponentCleanup`
  - Re-run script with `-Force`

---

### 17. New Weekly Reboot Schedule

**File**: `New-WeeklyRebootSchedule.ps1`

Creates a scheduled task to automatically reboot Windows Server on a weekly basis.

#### Features
- Interactive day of week selection (Monday-Sunday)
- 24-hour time format input with validation
- Runs under NT AUTHORITY\SYSTEM account
- Configurable reboot delay for graceful shutdown
- Automatic detection and handling of existing tasks
- Comprehensive input validation
- Detailed logging and status reporting
- Task verification after creation

#### Usage

**Interactive Mode** (Recommended):
```powershell
.\New-WeeklyRebootSchedule.ps1
```
The script will prompt you to:
1. Select the day of week (1-7 for Monday-Sunday)
2. Enter the time in 24-hour format (HH:mm)

**Non-Interactive Mode**:
```powershell
# Schedule reboot for Sunday at 3:00 AM
.\New-WeeklyRebootSchedule.ps1 -DayOfWeek Sunday -Time "03:00"

# Schedule with custom reboot delay (2 minutes)
.\New-WeeklyRebootSchedule.ps1 -DayOfWeek Saturday -Time "23:30" -RebootDelay 120

# Force overwrite existing task
.\New-WeeklyRebootSchedule.ps1 -DayOfWeek Monday -Time "02:00" -Force
```

**Custom Task Name**:
```powershell
.\New-WeeklyRebootSchedule.ps1 -DayOfWeek Wednesday -Time "04:00" -TaskName "Maintenance Reboot"
```

#### Parameters

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `-DayOfWeek` | Day for weekly reboot (Monday-Sunday) | Interactive prompt | `Sunday` |
| `-Time` | Time in 24-hour format (HH:mm) | Interactive prompt | `"03:00"` |
| `-TaskName` | Custom name for scheduled task | Weekly Server Reboot | `"Maintenance Reboot"` |
| `-RebootDelay` | Delay in seconds before reboot | 60 | `120` |
| `-Force` | Overwrite existing task without prompting | False | `-Force` |

#### Scheduled Task Configuration

The script creates a scheduled task with the following settings:

| Setting | Value | Purpose |
|---------|-------|---------|
| **User Account** | NT AUTHORITY\SYSTEM | Ensures task runs with highest privileges |
| **Run Level** | Highest | Required for shutdown command |
| **Trigger** | Weekly on selected day | Consistent reboot schedule |
| **Action** | `shutdown.exe /r /f /t [delay]` | Forced reboot with delay |
| **Settings** | Start if on batteries, Start when available | Ensures task runs reliably |
| **Network** | Not required | Task runs regardless of network status |

#### Reboot Delay Explanation

The `-RebootDelay` parameter (default: 60 seconds) provides time for:
- Users to save work (if logged in)
- Services to shut down gracefully
- Disk writes to complete
- Network connections to close properly

**Recommended Values**:
- **30 seconds**: Minimal delay for automated environments
- **60 seconds**: Standard delay (default)
- **120-300 seconds**: Extended delay for servers with many services

#### When to Use

**Recommended Scenarios**:
- Patch Tuesday maintenance (Tuesday or Wednesday early morning)
- Weekly maintenance windows
- Clearing memory leaks or resource buildup
- Forcing Windows Update installation
- Regular server hygiene

**Best Practice Schedule Examples**:
```powershell
# Patch deployment schedule
.\New-WeeklyRebootSchedule.ps1 -DayOfWeek Wednesday -Time "03:00"

# End-of-week maintenance
.\New-WeeklyRebootSchedule.ps1 -DayOfWeek Sunday -Time "02:00"

# Mid-week maintenance (avoid Monday/Friday)
.\New-WeeklyRebootSchedule.ps1 -DayOfWeek Wednesday -Time "23:30"
```

#### Output Example

```
========================================
  Weekly Reboot Scheduler for Windows
========================================
Server: SERVER01
OS: Microsoft Windows Server 2022 Datacenter
Version: 10.0.20348
========================================

[2025-12-29 10:15:30] [INFO] Starting Weekly Reboot Scheduler configuration...

Please select the day of week for the weekly reboot:
  1. Monday
  2. Tuesday
  3. Wednesday
  4. Thursday
  5. Friday
  6. Saturday
  7. Sunday

Enter selection (1-7): 7

[2025-12-29 10:15:35] [INFO] Selected day: Sunday

Please enter the time for the weekly reboot (24-hour format):
  Examples: 02:00, 23:30, 18:45

Enter time (HH:mm): 03:00

[2025-12-29 10:15:40] [INFO] Selected time: 03:00

========================================
  Configuration Summary
========================================
Task Name:     Weekly Server Reboot
Day:           Sunday
Time:          03:00 (24-hour format)
Reboot Delay:  60 seconds
Run As:        NT AUTHORITY\SYSTEM
========================================

[2025-12-29 10:15:45] [SUCCESS] Scheduled task created successfully!

========================================
  Scheduled Task Created Successfully
========================================
Task Name:       Weekly Server Reboot
Schedule:        Every Sunday at 03:00
Reboot Delay:    60 seconds
Run As:          NT AUTHORITY\SYSTEM
State:           Ready
Next Run:        Sunday, December 31, 2025 3:00:00 AM
========================================
```

#### Managing the Scheduled Task

**View Task Details**:
```powershell
Get-ScheduledTask -TaskName "Weekly Server Reboot"
Get-ScheduledTaskInfo -TaskName "Weekly Server Reboot"
```

**Disable Task Temporarily**:
```powershell
Disable-ScheduledTask -TaskName "Weekly Server Reboot"
```

**Enable Task**:
```powershell
Enable-ScheduledTask -TaskName "Weekly Server Reboot"
```

**Test Reboot Immediately** (⚠️ Warning: Will reboot the server!):
```powershell
Start-ScheduledTask -TaskName "Weekly Server Reboot"
```

**Remove Task**:
```powershell
Unregister-ScheduledTask -TaskName "Weekly Server Reboot" -Confirm:$false
```

**Modify Schedule**:
```powershell
# Just run the script again with different parameters
# Use -Force to overwrite without confirmation
.\New-WeeklyRebootSchedule.ps1 -DayOfWeek Monday -Time "04:00" -Force
```

#### Important Notes

1. **Administrator Rights Required**: Script must run with elevated privileges
2. **System Account**: Task runs as NT AUTHORITY\SYSTEM for reliability
3. **Forced Reboot**: The shutdown command uses `/f` flag to force applications to close
4. **No User Intervention**: Task will execute automatically - ensure maintenance window is appropriate
5. **Reboot Message**: Users will see: "Scheduled weekly server reboot - initiated by scheduled task"
6. **Task Persistence**: Task survives reboots and will continue running on schedule
7. **Overwrite Protection**: Script warns if task exists unless `-Force` is used

#### Troubleshooting

**Task Not Running**:
- Check task status: `Get-ScheduledTask -TaskName "Weekly Server Reboot"`
- Verify next run time: `Get-ScheduledTaskInfo -TaskName "Weekly Server Reboot"`
- Check Task Scheduler event log: `Get-WinEvent -LogName "Microsoft-Windows-TaskScheduler/Operational" -MaxEvents 20`

**Task Disabled After Reboot**:
- Some group policies may disable scheduled tasks
- Check GPO settings: `gpresult /h gpresult.html`
- Ensure "Task Scheduler" service is running and set to Automatic

**Permission Issues**:
- Verify running as Administrator
- Check if Task Scheduler service is running: `Get-Service -Name Schedule`
- Ensure user has rights to create scheduled tasks

**Reboot Not Occurring**:
- Verify server was powered on at scheduled time
- Check if task has "Start when available" enabled
- Review Task Scheduler history for execution logs
- Ensure system wasn't in use (some policies prevent reboot if users logged in)

---

### 18. Optimize WSUS Server

**File**: `Optimize-WsusServer.ps1`

Comprehensive Windows Server Update Services (WSUS) optimization and maintenance script with interactive configuration wizard and automated scheduling.

#### Features

**Interactive Configuration Wizard**:
- First-time setup with guided prompts for all settings
- Customizable obsolete product lists (Windows 7/8, legacy Office, SQL Server, etc.)
- Update title filtering (IE 6-10, Itanium, ARM64, consumer editions)
- Scheduled task configuration (daily, weekly, monthly)
- Advanced options (custom indexes, verbose logging, retention)

**Deep Cleaning**:
- Remove updates for 20+ obsolete products (EOL Windows/Office/SQL versions)
- Decline superseded updates automatically
- Optional driver update removal to reduce database bloat
- Customizable product and title filter lists
- Progress tracking with real-time counts

**Database Optimization**:
- Microsoft best practice SQL reindexing
- Custom index creation on key WSUS tables
- Statistics updates for query plan optimization
- Fragmented index rebuilding (>10% fragmentation)

**IIS Configuration Management**:
- Validates against recommended WSUS IIS settings
- Queue length optimization (25,000)
- CPU reset interval, memory recycling settings
- Automatic web.config backup before changes

**Automated Scheduling**:
- Daily task: Server optimization + superseded update cleanup
- Weekly task: Database optimization + IIS config validation
- Monthly task: Deep clean of obsolete updates

#### Usage

**Interactive Mode** (Recommended for first run):
```powershell
.\Optimize-WsusServer.ps1 -Interactive
```

The wizard will guide you through:
1. Deep clean configuration (obsolete products to remove)
2. Driver synchronization settings
3. Scheduled task creation (daily/weekly/monthly)
4. Advanced options (logging, retention, custom indexes)

**Command-Line Operations**:
```powershell
# Run all built-in WSUS cleanup processes
.\Optimize-WsusServer.ps1 -OptimizeServer

# Optimize database (reindex, update statistics)
.\Optimize-WsusServer.ps1 -OptimizeDatabase

# Decline superseded updates
.\Optimize-WsusServer.ps1 -DeclineSupersededUpdates

# Deep clean obsolete updates
.\Optimize-WsusServer.ps1 -DeepClean

# Full optimization
.\Optimize-WsusServer.ps1 -OptimizeServer -OptimizeDatabase -CheckConfig

# Create scheduled tasks from configuration
.\Optimize-WsusServer.ps1 -CreateTasks
```

**Custom Configuration File**:
```powershell
.\Optimize-WsusServer.ps1 -ConfigFile "C:\Custom\wsus-config.json" -OptimizeServer
```

#### Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-Interactive` | Launch configuration wizard | `-Interactive` |
| `-OptimizeServer` | Run all WSUS cleanup processes | `-OptimizeServer` |
| `-OptimizeDatabase` | Database reindex and statistics | `-OptimizeDatabase` |
| `-DeclineSupersededUpdates` | Decline superseded updates | `-DeclineSupersededUpdates` |
| `-DeepClean` | Remove obsolete updates | `-DeepClean` |
| `-DisableDrivers` | Disable driver synchronization | `-DisableDrivers` |
| `-CheckConfig` | Validate IIS configuration | `-CheckConfig` |
| `-CreateTasks` | Create scheduled tasks | `-CreateTasks` |
| `-ConfigFile` | Custom configuration path | `-ConfigFile "C:\config.json"` |
| `-LogPath` | Custom log file path | `-LogPath "D:\Logs\wsus.log"` |

#### Requirements

- Windows Server 2016 or later
- WSUS role installed and configured
- SQL Server (Windows Internal Database or Full)
- PowerShell 5.1 or later
- Required modules: `SqlServer`, `UpdateServices`, `WebAdministration`
- Administrator privileges (Run as Administrator)

#### Configuration File

The script uses a JSON configuration file (default: `C:\Scripts\WSUS\wsus-config.json`) that stores:

- **Deep Clean Settings**: Lists of obsolete products and update titles
- **IIS Settings**: Recommended IIS configuration values
- **Scheduled Tasks**: Task schedules and operations
- **Features**: Driver sync, custom indexes, etc.
- **Logging**: Log path, retention, verbosity

#### Default Obsolete Products Removed

The script includes pre-configured lists for:

**EOL Operating Systems**:
- Windows 2000, XP, Vista, 7, 8, 8.1
- Windows Server 2003, 2003 R2, 2008, 2008 R2

**Legacy Applications**:
- Office 2002, 2003, 2007, 2010
- SQL Server 2000, 2005, 2008
- Internet Explorer 6-10

**Architecture/Edition Filters**:
- Itanium and ARM64 architectures
- Consumer editions (if enterprise-only)
- Language packs (if not needed)

#### Scheduled Tasks Created

**Daily Task** (WSUS-DailyOptimization):
- Default: 02:00 AM
- Operations: Server cleanup, decline superseded updates

**Weekly Task** (WSUS-WeeklyOptimization):
- Default: Sunday at 03:00 AM
- Operations: Database optimization, IIS config check

**Monthly Task** (WSUS-MonthlyDeepClean):
- Default: 1st day at 04:00 AM
- Operations: Deep clean obsolete updates

#### IIS Settings Validated

| Setting | Recommended Value |
|---------|-------------------|
| Queue Length | 25,000 |
| CPU Reset Interval | 15 minutes |
| Recycling Memory | 0 (disabled) |
| Private Memory Limit | 0 (disabled) |
| Max Request Length | 204,800 KB |
| Execution Timeout | 7,200 seconds |

#### When to Use

**Initial Setup**:
- Run `-Interactive` to configure all settings
- Creates configuration file for future runs
- Sets up automated scheduled tasks

**Regular Maintenance**:
- Daily/weekly/monthly tasks run automatically
- Manual runs as needed during troubleshooting

**Performance Issues**:
- Database growing too large
- Slow WSUS console performance
- Update synchronization taking too long
- IIS application pool issues

**After Major Changes**:
- After removing obsolete products from environment
- Before/after major Windows version upgrades
- When cleaning up test/pilot deployments

#### Output Example

```
========================================
WSUS Optimization Script v2.0.0
========================================

[2025-01-09 02:00:00] [INFO] Connected to WSUS server: WSUS01
[2025-01-09 02:00:05] [INFO] Starting WSUS server cleanup...
[2025-01-09 02:00:10] [INFO] Cleaning up: Unused updates and update revisions...
[2025-01-09 02:05:30] [SUCCESS]   Completed: Unused updates and update revisions
[2025-01-09 02:05:35] [INFO] Cleaning up: Expired updates...
[2025-01-09 02:10:15] [SUCCESS]   Completed: Expired updates
[2025-01-09 02:10:20] [INFO] Declining superseded updates...
[2025-01-09 02:15:45] [INFO] Declined 1,247 superseded updates
[2025-01-09 02:15:50] [SUCCESS] WSUS server cleanup completed
[2025-01-09 02:15:55] [INFO] Starting WSUS database optimization...
[2025-01-09 02:16:00] [INFO] Rebuilding fragmented indexes...
[2025-01-09 02:45:30] [SUCCESS] Database optimization completed successfully

========================================
Script execution completed
========================================
```

#### Important Notes

1. **First Run Duration**: Initial deep clean can take several hours depending on WSUS database size
2. **Database Optimization**: Duration scales with database size (typically 30-90 minutes)
3. **Backup Before Use**: Ensure WSUS backups are current before first deep clean
4. **Test Environment**: Test in non-production first to understand impact
5. **Schedule Off-Hours**: Run intensive operations during maintenance windows
6. **Monitor Disk Space**: Ensure adequate space for database operations
7. **Driver Sync**: Recommended to disable unless specifically needed
8. **Configuration**: Customize obsolete product lists for your environment

#### Troubleshooting

**Database Optimization Fails**:
- Verify SQL Server/WID service is running
- Check SUSDB database is accessible
- Ensure sufficient disk space for index rebuilds
- Review SQL query timeout settings

**IIS Configuration Fails**:
- Verify WebAdministration module loaded
- Check WsusPool app pool exists
- Ensure WSUS Administration site is running
- Review IIS permissions

**Updates Not Being Declined**:
- Verify WSUS server connection
- Check filter criteria in configuration
- Review update approval states
- Ensure sufficient permissions

**Scheduled Tasks Don't Run**:
- Verify tasks created: `Get-ScheduledTask -TaskName "WSUS-*"`
- Check task history in Task Scheduler
- Ensure SYSTEM account has permissions
- Review script path in task action

#### Credits

**Original Author**: Austin Warren ([@awarre](https://github.com/awarre))
**Original Repository**: [awarre/Optimize-WsusServer](https://github.com/awarre/Optimize-WsusServer) v1.2.1
**Modernized By**: Carme99 for Bug-Free Umbrella
**Version**: 2.0.0

This script is based on Austin Warren's excellent WSUS optimization script and has been modernized with enhanced features, syntax fixes, and additional functionality for 2025.

#### Related Documentation

For complete documentation, see: [`Optimize-WsusServer.md`](system/Optimize-WsusServer.md)

---

## Support and Contributions

### Getting Help

If you encounter issues:
1. Review script help: `Get-Help .\ScriptName.ps1 -Full`
2. Check the troubleshooting section above
3. Review script output and error messages
4. Check Windows Event Logs for related errors

### Script Customization

All scripts can be modified to suit your environment:
- Edit parameters and default values
- Customize log output formats
- Add organization-specific checks
- Integrate with monitoring systems

### Safety Notes

- Always test in non-production first
- Read script contents before running
- Understand what changes will be made
- Keep backups of important data
- Use `-WhatIf` parameter where available (future enhancement)

---

## Version History

**Version 1.0** - Initial Release
- Reset Windows Update script
- System Integrity Check script
- Disk Report and Cleanup script
- English UK Regional Settings script
- US Language Pack Removal script

---

## License

These scripts are provided as-is for system administration purposes. Use at your own risk and always test in non-production environments first.

---

## Quick Reference

| Task | Script | Basic Command |
|------|--------|---------------|
| **Monitoring** |
| Server Health Check | Monitor-ServerHealth.ps1 | `.\Monitor-ServerHealth.ps1 -ExportReport` |
| Event Log Analysis | Get-EventLogReport.ps1 | `.\Get-EventLogReport.ps1 -ExportHTML` |
| Performance Analysis | Get-PerformanceReport.ps1 | `.\Get-PerformanceReport.ps1 -ExportHTML` |
| **Network** |
| Test Connectivity | Test-ServerConnectivity.ps1 | `.\Test-ServerConnectivity.ps1 -ComputerName "server01"` |
| Network Config | Get-NetworkConfiguration.ps1 | `.\Get-NetworkConfiguration.ps1 -ExportHTML` |
| Firewall Rules | Get-FirewallRulesReport.ps1 | `.\Get-FirewallRulesReport.ps1 -ExportHTML` |
| **Security** |
| Certificate Expiry | Test-CertificateExpiration.ps1 | `.\Test-CertificateExpiration.ps1 -CheckLocal -ExportHTML` |
| **Storage** |
| Disk Report | Get-DiskReport.ps1 | `.\Get-DiskReport.ps1 -ExportReport` |
| Storage Cleanup | Optimize-ServerStorage.ps1 | `.\Optimize-ServerStorage.ps1 -Force` |
| Large Files | Get-LargeFilesReport.ps1 | `.\Get-LargeFilesReport.ps1 -ExportHTML` |
| **Active Directory** |
| AD Health Check | Get-ADHealthCheck.ps1 | `.\Get-ADHealthCheck.ps1 -ExportHTML` |
| Inactive Computers | Find-InactiveADComputers.ps1 | `.\Find-InactiveADComputers.ps1 -ExportHTML` |
| **Maintenance** |
| Fix Windows Update | Reset-WindowsUpdate.ps1 | `.\Reset-WindowsUpdate.ps1` |
| System Integrity | Check-SystemIntegrity.ps1 | `.\Check-SystemIntegrity.ps1 -GenerateReport` |
| Configure UK Settings | Set-EnglishUKRegion.ps1 | `.\Set-EnglishUKRegion.ps1 -ApplyToExistingUsers` |
| Remove US Language | Remove-USLanguagePack.ps1 | `.\Remove-USLanguagePack.ps1 -BackupFirst` |
| Weekly Reboot Schedule | New-WeeklyRebootSchedule.ps1 | `.\New-WeeklyRebootSchedule.ps1` |

---

**Compatible**: Windows Server 2016, 2019, 2022
**PowerShell**: 5.1+
**Total Scripts**: 17
