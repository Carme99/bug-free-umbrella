# Print Management Scripts

Enterprise-grade PowerShell scripts for print server monitoring, troubleshooting, and maintenance.

## 📋 Overview

This category provides comprehensive print server management tools for monitoring printer health, managing print queues, and resolving common printing issues.

## 🔧 Scripts

### Get-PrintServerHealth.ps1
Monitors print server health and identifies printing issues.

**Features:**
- Print Spooler service status
- Printer status and error detection
- Print queue health monitoring
- Stuck/stale print job identification
- Automatic stuck job cleanup
- Printer driver verification
- Port configuration checks
- Spool directory disk space monitoring
- Event log error analysis

**Usage:**
```powershell
# Basic health check
.\Get-PrintServerHealth.ps1

# Clear stuck jobs automatically
.\Get-PrintServerHealth.ps1 -ClearStuckJobs -StuckJobThresholdHours 4

# Comprehensive check with driver validation
.\Get-PrintServerHealth.ps1 -CheckDrivers -ExportHTML
```

**Parameters:**
- `-ClearStuckJobs`: Automatically clear stuck print jobs
- `-StuckJobThresholdHours`: Hours threshold for stuck jobs (default: 2)
- `-CheckDrivers`: Verify printer driver status
- `-ExportHTML`: Export to HTML report
- `-ExportCSV`: Export to CSV file

**Requirements:**
- Administrator privileges
- Print Management features
- Compatible with Windows Server 2016, 2019, 2022

## 📊 Common Use Cases

### Daily Maintenance
```powershell
# Morning health check
.\Get-PrintServerHealth.ps1 -ExportHTML

# Clear overnight stuck jobs
.\Get-PrintServerHealth.ps1 -ClearStuckJobs
```

### Troubleshooting Printer Issues
```powershell
# Identify problematic printers
.\Get-PrintServerHealth.ps1 -CheckDrivers

# Find and clear stuck jobs
.\Get-PrintServerHealth.ps1 -ClearStuckJobs -StuckJobThresholdHours 1
```

### Capacity Planning
```powershell
# Monitor spool directory space
.\Get-PrintServerHealth.ps1 -ExportCSV
```

## 🎯 Health Check Metrics

The health check evaluates:

1. **Print Spooler Service**
   - Service status (Running/Stopped)
   - Startup type configuration
   - Recent service restarts

2. **Disk Space**
   - Spool directory location
   - Free disk space
   - Usage percentage warnings

3. **Printer Status**
   - Online/offline state
   - Error conditions
   - Paper jams, out of paper, etc.
   - Shared printer configuration

4. **Print Queues**
   - Total jobs across all printers
   - Stuck jobs (older than threshold)
   - Job age and user information
   - Document sizes

5. **Printer Drivers**
   - Installed driver count
   - Driver versions
   - Driver duplicates

6. **Event Logs**
   - Recent print service errors
   - Warning events
   - Critical failures

## 📈 Output Examples

### Healthy Print Server
```
=== Print Server Health Check ===
Server: PRINTSERVER01

[+] Print Spooler is running

Spool Directory: C:\Windows\System32\spool\PRINTERS
    Free space: 25.50 GB (15% used)

[+] Found 15 printer(s)

    [Pass] HP-Floor1-Color: Normal
    [Pass] HP-Floor2-BW: Normal
    [Pass] Canon-Reception: Normal

[+] Total print jobs: 3
[+] Stuck jobs: 0

Health Score: 100%
```

### Issues Detected
```
[Fail] HP-Floor3-Color: Error - Paper Jam
[Warning] Canon-Warehouse: Paused

[Warning] Stuck job on HP-Floor1-Color: Report.pdf (5.2 hours old)

Spool Directory:
    [Warning] Free space: 2.1 GB

Health Score: 68%
Issues: 1
Warnings: 3
```

## 🔍 Troubleshooting

### Print Spooler Not Starting
```powershell
# Check dependencies
Get-Service -Name Spooler | Select-Object -ExpandProperty DependentServices

# Clear spool folder
Stop-Service -Name Spooler
Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force
Start-Service -Name Spooler
```

### Stuck Jobs Won't Clear
```powershell
# Force clear with remediation
.\Get-PrintServerHealth.ps1 -ClearStuckJobs -StuckJobThresholdHours 0

# Manual intervention
Stop-Service -Name Spooler
Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force
Start-Service -Name Spooler
```

### Low Disk Space
```powershell
# Check spool directory size
Get-ChildItem "$env:SystemRoot\System32\spool\PRINTERS" -Recurse |
    Measure-Object -Property Length -Sum

# Clean old spool files (with spooler stopped)
Stop-Service -Name Spooler
Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force
Start-Service -Name Spooler
```

## 📝 Best Practices

1. **Regular Monitoring**
   - Run health checks multiple times daily
   - Monitor spool directory disk space
   - Track stuck job patterns

2. **Stuck Job Management**
   - Set reasonable threshold (2-4 hours)
   - Clear stuck jobs automatically during off-hours
   - Investigate recurring stuck jobs

3. **Disk Space**
   - Monitor spool directory continuously
   - Alert when free space < 5GB
   - Plan for disk expansion proactively

4. **Driver Management**
   - Remove unused printer drivers
   - Keep drivers up to date
   - Test driver updates in non-production first

5. **Event Log Review**
   - Check print service errors daily
   - Address recurring errors
   - Correlate errors with printer issues

## 🚨 Common Issues

### Print Spooler Crashes
**Symptom**: Spooler service stops unexpectedly
**Solution**:
- Check for corrupt print jobs
- Update printer drivers
- Scan event logs for error details

### Jobs Stuck in Queue
**Symptom**: Jobs won't print or clear
**Solution**:
```powershell
.\Get-PrintServerHealth.ps1 -ClearStuckJobs -StuckJobThresholdHours 0
```

### Low Disk Space
**Symptom**: Spool directory fills up
**Solution**:
- Clear old spool files
- Increase disk size
- Move spool directory to larger drive

### Printer Offline
**Symptom**: Printer shows offline status
**Solution**:
- Verify network connectivity
- Check printer power and cables
- Test printer port configuration

## 🚀 Future Enhancements

Planned additions:
- Printer usage statistics
- Print queue forecasting
- Automated driver updates
- Print job archiving
- Multi-server monitoring

## 📚 Additional Resources

- [Print Management Documentation](https://docs.microsoft.com/windows-server/administration/windows-commands/print)
- [Print Server Best Practices](https://docs.microsoft.com/windows-server/administration/print-and-document-services/)
- [Troubleshooting Print Services](https://docs.microsoft.com/troubleshoot/windows-server/printing/)

---

**Version**: 1.0
**Last Updated**: 2025
