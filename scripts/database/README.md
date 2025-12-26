# Database Management Scripts

Enterprise-grade PowerShell scripts for SQL Server management, monitoring, and maintenance.

## 📋 Overview

This category provides comprehensive database management tools for SQL Server environments, including health monitoring, backup verification, performance analysis, and troubleshooting.

## 🔧 Scripts

### Get-SQLServerHealth.ps1
Performs comprehensive health check of SQL Server instances.

**Features:**
- Database status and integrity checks
- Last backup date verification
- Database file sizes and growth monitoring
- Transaction log usage analysis
- Failed SQL Agent job detection
- Long-running query identification
- Blocking session detection
- Performance metrics analysis

**Usage:**
```powershell
# Basic health check
.\Get-SQLServerHealth.ps1

# Comprehensive check with backups
.\Get-SQLServerHealth.ps1 -ServerInstance "SQLSERVER01" -CheckBackups -ExportHTML

# Specific database with performance metrics
.\Get-SQLServerHealth.ps1 -Database "ProductionDB" -IncludePerformance
```

**Parameters:**
- `-ServerInstance`: SQL Server instance name (default: localhost)
- `-Database`: Specific database to check (default: all)
- `-IncludePerformance`: Include performance metrics
- `-CheckBackups`: Verify backup status
- `-ExportHTML`: Export to HTML report
- `-ExportCSV`: Export to CSV file

**Requirements:**
- SQL Server PowerShell module or SMO
- Appropriate SQL Server permissions
- Compatible with SQL Server 2016, 2017, 2019, 2022

## 📊 Common Use Cases

### Daily Health Monitoring
```powershell
# Quick health check
.\Get-SQLServerHealth.ps1 -ExportHTML

# Check critical production server
.\Get-SQLServerHealth.ps1 -ServerInstance "PROD-SQL-01" -CheckBackups -IncludePerformance
```

### Backup Validation
```powershell
# Verify all database backups
.\Get-SQLServerHealth.ps1 -CheckBackups -ExportCSV

# Check specific database backup status
.\Get-SQLServerHealth.ps1 -Database "CustomerDB" -CheckBackups
```

### Performance Troubleshooting
```powershell
# Performance analysis with full metrics
.\Get-SQLServerHealth.ps1 -IncludePerformance -ExportHTML
```

## 🎯 Health Check Metrics

The health check evaluates:

1. **Database Status**
   - Online/offline state
   - Recovery model
   - Compatibility level
   - Database size

2. **Backup Status**
   - Last full backup date
   - Last differential backup
   - Last log backup
   - Days since last backup

3. **Transaction Logs**
   - Log usage percentage
   - Log size
   - Growth settings

4. **SQL Agent Jobs**
   - Failed job executions
   - Job schedules
   - Job history

5. **Performance (Optional)**
   - Blocking sessions
   - Long-running queries
   - Index fragmentation
   - Wait statistics

## 📈 Output Examples

### Healthy Server
```
=== SQL Server Health Check ===
Server Instance: SQLSERVER01

[+] SQL Server: SQLSERVER01
    Version: 15.0.4138.2 RTM
    Edition: Enterprise Edition (64-bit)

[Pass] ProductionDB: ONLINE (2048.50 MB)
[Pass] ReportingDB: ONLINE (512.25 MB)

[Pass] ProductionDB: Last backup 0 days ago
[Pass] ReportingDB: Last backup 0 days ago

[Pass] ProductionDB: Log 15% used
[Pass] ReportingDB: Log 23% used

Health Score: 100%
```

### Issues Detected
```
[Fail] ArchiveDB: OFFLINE (512.00 MB)
[Warning] OldDB: Last backup 8 days ago
[Fail] LargeDB: Log 95% used (WARNING!)

Health Score: 67%
Issues Found: 3
```

## 🔍 Troubleshooting

### Module Not Found
If SQL Server module is missing:
```powershell
# Install SqlServer module
Install-Module -Name SqlServer -Scope CurrentUser

# Or use SQLPS (older)
Import-Module SQLPS -DisableNameChecking
```

### Permission Denied
Ensure your account has appropriate permissions:
- VIEW SERVER STATE
- VIEW DATABASE STATE
- VIEW ANY DEFINITION
- CONNECT SQL

### Connection Failures
```powershell
# Test SQL connectivity first
Test-NetConnection -ComputerName SQLSERVER01 -Port 1433

# Verify instance name
Get-Service -Name "MSSQL*"
```

## 📝 Best Practices

1. **Daily Monitoring**
   - Run health checks daily on production servers
   - Export reports for compliance tracking
   - Set up automated scheduling via Task Scheduler

2. **Backup Verification**
   - Always include `-CheckBackups` for production
   - Alert on backups older than 24 hours
   - Verify backup restore capability regularly

3. **Performance Analysis**
   - Use `-IncludePerformance` during troubleshooting
   - Baseline normal performance metrics
   - Compare trends over time

4. **Reporting**
   - Export HTML reports for management
   - Keep CSV exports for trending analysis
   - Archive reports for compliance

## 🚀 Future Enhancements

Planned additions:
- Index maintenance recommendations
- Database growth forecasting
- Automated backup scheduling
- Query performance tuning suggestions
- Tempdb configuration analysis

## 📚 Additional Resources

- [SQL Server PowerShell Documentation](https://docs.microsoft.com/sql/powershell/)
- [SQL Server Best Practices](https://docs.microsoft.com/sql/database-engine/sql-server-best-practices/)
- [Monitoring SQL Server](https://docs.microsoft.com/sql/relational-databases/performance/monitor-and-tune-for-performance)

---

**Version**: 1.0
**Last Updated**: 2025
