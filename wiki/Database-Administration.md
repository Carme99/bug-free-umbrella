# 🗃️ Database Administration Guide

![SQL Server](https://img.shields.io/badge/SQL_Server-2016--2022-CC2927?logo=microsoftsqlserver)
![MySQL](https://img.shields.io/badge/MySQL-5.7+-4479A1?logo=mysql&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-10+-336791?logo=postgresql&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-4.0+-47A248?logo=mongodb&logoColor=white)

> **Database health monitoring and management scripts for PowerShell**

---

## 📋 Table of Contents
- [Overview](#overview)
- [Available Scripts](#available-scripts)
- [Prerequisites](#prerequisites)
- [SQL Server Management](#sql-server-management)
- [MySQL Management](#mysql-management)
- [PostgreSQL Management](#postgresql-management)
- [MongoDB Management](#mongodb-management)
- [Common Use Cases](#common-use-cases)
- [Best Practices](#best-practices)

---

## Overview

![Scripts](https://img.shields.io/badge/scripts-4-orange)
![Platforms](https://img.shields.io/badge/platforms-4-blue)

Bug-Free Umbrella provides comprehensive database health monitoring across **4 major platforms**:

| Platform | Script | Features | Cross-Platform |
|----------|--------|----------|----------------|
| **SQL Server** | Get-SQLServerHealth.ps1 | Backups, logs, jobs, performance | Windows primary |
| **MySQL** | Get-MySQLHealth.ps1 | Status, replication, connections | ✅ Full |
| **PostgreSQL** | Get-PostgreSQLHealth.ps1 | Queries, locks, vacuum | ✅ Full |
| **MongoDB** | Monitor-MongoDBHealth.ps1 | Collections, replication, indexes | ✅ Full |

---

## Available Scripts

### Get-SQLServerHealth.ps1

![Location](https://img.shields.io/badge/location-scripts/data/databases-blue)
![Platform](https://img.shields.io/badge/platform-SQL_Server-CC2927)

**Comprehensive SQL Server health monitoring and reporting**

**Capabilities:**
- ✅ Database status & integrity checks
- ✅ Backup verification (full, differential, log)
- ✅ Transaction log usage monitoring
- ✅ SQL Agent job failure detection
- ✅ Performance metrics (blocking, queries, indexes)
- ✅ Tempdb configuration analysis
- ✅ HTML/CSV report generation

[View Script →](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/data/databases/Get-SQLServerHealth.ps1)

---

### Get-MySQLHealth.ps1

![Location](https://img.shields.io/badge/location-scripts/data/databases-blue)
![Platform](https://img.shields.io/badge/platform-MySQL-4479A1)

**MySQL database server health and monitoring**

**Capabilities:**
- ✅ Server version and uptime
- ✅ Connection monitoring
- ✅ Database inventory
- ✅ Replication status (optional)
- ✅ HTML report generation

[View Script →](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/data/databases/Get-MySQLHealth.ps1)

---

### Get-PostgreSQLHealth.ps1

![Location](https://img.shields.io/badge/location-scripts/data/databases-blue)
![Platform](https://img.shields.io/badge/platform-PostgreSQL-336791)

**PostgreSQL database health and performance monitoring**

**Capabilities:**
- ✅ Version and database statistics
- ✅ Active connection monitoring
- ✅ Long-running query detection
- ✅ Replication health (optional)
- ✅ Lock monitoring
- ✅ Vacuum status

[View Script →](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/data/databases/Get-PostgreSQLHealth.ps1)

---

### Monitor-MongoDBHealth.ps1

![Location](https://img.shields.io/badge/location-scripts/data/databases-blue)
![Platform](https://img.shields.io/badge/platform-MongoDB-47A248)

**MongoDB health and performance monitoring framework**

**Capabilities:**
- ✅ Server uptime and connections
- ✅ Database & collection statistics
- ✅ Replica set health
- ✅ Query performance analysis
- ✅ Index usage monitoring
- ✅ Storage metrics

[View Script →](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/data/databases/Monitor-MongoDBHealth.ps1)

---

## Prerequisites

### SQL Server

![Module](https://img.shields.io/badge/module-SqlServer-blue)
![Permissions](https://img.shields.io/badge/permissions-VIEW_SERVER_STATE-yellow)

```powershell
# Install SQL Server module
Install-Module -Name SqlServer -Force

# Verify installation
Get-Module -ListAvailable SqlServer
```

**Required Permissions:**
- `VIEW SERVER STATE`
- `VIEW DATABASE STATE`
- `VIEW ANY DEFINITION`
- `CONNECT SQL`

---

### MySQL

![Tool](https://img.shields.io/badge/tool-mysql_cli-4479A1)
![Driver](https://img.shields.io/badge/driver-MySQL.Data.dll-orange)

```powershell
# Option 1: Install MySQL command-line client
# Download from: https://dev.mysql.com/downloads/mysql/

# Option 2: Use MySQL.Data.dll (included with MySQL Connector/NET)
# Download from: https://dev.mysql.com/downloads/connector/net/

# Verify mysql is in PATH
mysql --version
```

---

### PostgreSQL

![Tool](https://img.shields.io/badge/tool-psql_cli-336791)
![Driver](https://img.shields.io/badge/driver-Npgsql-orange)

```powershell
# Install psql client
# Download from: https://www.postgresql.org/download/

# Verify psql is in PATH
psql --version
```

---

### MongoDB

![Tool](https://img.shields.io/badge/tool-mongosh-47A248)
![Driver](https://img.shields.io/badge/driver-MongoDB_.NET-orange)

```powershell
# Install MongoDB Shell (mongosh)
# Download from: https://www.mongodb.com/try/download/shell

# Or install MongoDB .NET driver
Install-Package MongoDB.Driver
```

---

## SQL Server Management

### Example 1: Basic Health Check

```powershell
# Quick health check (all databases)
.\Get-SQLServerHealth.ps1 -ServerInstance "SQL-PROD-01"
```

**Expected Output:**
```
[+] Connected to SQL-PROD-01
[+] Found 8 databases
[+] ProductionDB: Online, Full Recovery, 45.2 GB
[+] Last backup: 2026-01-27 02:00:00 (0 days ago)
[+] Transaction log: 15% used
[✓] Health Score: 95%
```

### Example 2: Comprehensive Production Check

```powershell
# Full health check with all options
.\Get-SQLServerHealth.ps1 `
    -ServerInstance "SQL-PROD-01" `
    -CheckBackups `
    -IncludePerformance `
    -ExportHTML `
    -ExportCSV
```

**Output Files:**
- `SQL-PROD-01-Health-Report.html` - Visual dashboard
- `SQL-PROD-01-Health-Data.csv` - Raw data for analysis

### Example 3: Backup Verification

```powershell
# Critical: Alert if any database hasn't been backed up in 24 hours
.\Get-SQLServerHealth.ps1 `
    -ServerInstance "SQL-PROD-01" `
    -CheckBackups `
    -ExportHTML

# Check the report for backup warnings
```

### Example 4: Specific Database Focus

```powershell
# Monitor specific database
.\Get-SQLServerHealth.ps1 `
    -ServerInstance "SQL-PROD-01" `
    -Database "CriticalDB" `
    -IncludePerformance `
    -Verbose
```

### Example 5: Scheduled Daily Monitoring

```powershell
# Create scheduled task for daily checks
$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-File C:\Scripts\Get-SQLServerHealth.ps1 -ServerInstance SQL-PROD-01 -CheckBackups -ExportHTML"

$trigger = New-ScheduledTaskTrigger -Daily -At 7:00AM

Register-ScheduledTask `
    -TaskName "SQL Server Daily Health Check" `
    -Action $action `
    -Trigger $trigger `
    -User "SYSTEM" `
    -RunLevel Highest
```

---

## MySQL Management

### Example 1: Basic Health Check

```powershell
# Simple health check
.\Get-MySQLHealth.ps1 -Server "mysql-prod-01" -Username "monitor"
```

### Example 2: Replication Monitoring

```powershell
# Check replication status
.\Get-MySQLHealth.ps1 `
    -Server "mysql-replica-01" `
    -Username "monitor" `
    -CheckReplication `
    -ExportHTML
```

### Example 3: Custom Port

```powershell
# Non-standard port
.\Get-MySQLHealth.ps1 `
    -Server "mysql.company.com" `
    -Port 3307 `
    -Username "admin" `
    -ExportHTML
```

---

## PostgreSQL Management

### Example 1: Basic Health Check

```powershell
# Quick check
.\Get-PostgreSQLHealth.ps1 `
    -Server "postgres-prod-01" `
    -Database "postgres" `
    -Username "monitor"
```

### Example 2: Long-Running Query Detection

```powershell
# Find queries running over 5 minutes
.\Get-PostgreSQLHealth.ps1 `
    -Server "postgres-prod-01" `
    -Database "productiondb" `
    -Username "admin" `
    -Verbose
```

### Example 3: Replication Health

```powershell
# Check replica lag
.\Get-PostgreSQLHealth.ps1 `
    -Server "postgres-replica-01" `
    -Database "postgres" `
    -Username "monitor" `
    -CheckReplication `
    -ExportHTML
```

---

## MongoDB Management

### Example 1: Basic Monitoring

```powershell
# Monitor all databases
.\Monitor-MongoDBHealth.ps1 `
    -MongoDBServer "mongodb-prod-01" `
    -Database "*" `
    -OutputFormat HTML
```

### Example 2: Authenticated Connection

```powershell
# With authentication
.\Monitor-MongoDBHealth.ps1 `
    -MongoDBServer "mongodb.company.com" `
    -Username "admin" `
    -Password "SecurePassword123" `
    -Database "myapp" `
    -OutputFormat JSON
```

### Example 3: Slow Query Analysis

```powershell
# Analyze slow queries
.\Monitor-MongoDBHealth.ps1 `
    -MongoDBServer "mongodb-prod-01" `
    -Database "analytics" `
    -IncludeSlowQueries `
    -OutputFormat HTML
```

---

## Common Use Cases

### Use Case 1: Daily Database Health Monitoring

**Scenario**: Automated daily health checks for all databases

**Solution:**
```powershell
# Create wrapper script: daily-db-health.ps1

# SQL Server
.\Get-SQLServerHealth.ps1 -ServerInstance "SQL01" -CheckBackups -ExportHTML

# MySQL
.\Get-MySQLHealth.ps1 -Server "MYSQL01" -Username "monitor" -CheckReplication -ExportHTML

# PostgreSQL
.\Get-PostgreSQLHealth.ps1 -Server "PG01" -Database "postgres" -Username "monitor" -ExportHTML

# MongoDB
.\Monitor-MongoDBHealth.ps1 -MongoDBServer "MONGO01" -Database "*" -OutputFormat HTML

# Email consolidated report
Send-MailMessage -To "dba-team@company.com" -Subject "Daily DB Health Report" -Attachments *.html
```

### Use Case 2: Backup Compliance Auditing

**Scenario**: Weekly audit of all database backups

**Solution:**
```powershell
# SQL Server backup audit
$servers = @("SQL01", "SQL02", "SQL03")

foreach ($server in $servers) {
    Write-Host "Checking $server..." -ForegroundColor Cyan

    .\Get-SQLServerHealth.ps1 `
        -ServerInstance $server `
        -CheckBackups `
        -ExportHTML
}

# Review all reports for compliance
```

### Use Case 3: Performance Troubleshooting

**Scenario**: Identify database performance issues

**Solution:**
```powershell
# SQL Server performance analysis
.\Get-SQLServerHealth.ps1 `
    -ServerInstance "SQL-SLOW-01" `
    -IncludePerformance `
    -Verbose `
    -ExportHTML

# Review report for:
# - Blocking sessions
# - Long-running queries
# - Index fragmentation
# - Wait statistics
```

### Use Case 4: Disaster Recovery Validation

**Scenario**: Verify backup status before maintenance window

**Solution:**
```powershell
# Pre-change verification
.\Get-SQLServerHealth.ps1 `
    -ServerInstance "SQL-PROD-01" `
    -CheckBackups `
    -ExportHTML

# Verify:
# - All databases have recent backups
# - Backup age < 24 hours
# - Transaction log backups current
```

---

## Best Practices

### 🔒 Security

![Security](https://img.shields.io/badge/priority-high-critical)

- ✅ Use **least-privilege accounts** for monitoring
- ✅ Store credentials securely (Azure Key Vault, CyberArk)
- ✅ Never hardcode passwords in scripts
- ✅ Use Windows Authentication for SQL Server when possible
- ✅ Rotate monitoring account passwords regularly

### 📊 Monitoring Frequency

![Monitoring](https://img.shields.io/badge/frequency-varies-blue)

**Recommended Schedule:**
- **Production databases**: Daily minimum
- **Critical databases**: Multiple times per day
- **Development databases**: Weekly
- **Backup verification**: Daily
- **Performance metrics**: On-demand or when issues arise

### 💾 Backup Verification

![Backups](https://img.shields.io/badge/critical-backups-red)

**Critical Checks:**
- ✅ **Full backup age** < 24 hours (production)
- ✅ **Transaction log backup age** < 15 minutes (critical systems)
- ✅ **Differential backup** configured appropriately
- ✅ **Backup integrity** verified regularly
- ⚠️ Alert immediately if backup age exceeds threshold

### 📈 Trending and Analysis

![Analysis](https://img.shields.io/badge/trending-important-yellow)

- Export to CSV regularly for trending
- Track database growth over time
- Monitor performance metric trends
- Baseline normal behavior
- Alert on deviations from baseline

### 🔄 Automation

![Automation](https://img.shields.io/badge/automation-recommended-success)

- Schedule daily health checks
- Automated email reporting
- CSV exports for trending analysis
- Archive reports for compliance
- Integrate with ticketing systems

---

## Related Resources

- 📖 [Script Catalog](Script-Catalog)
- 📖 [Integration Patterns](Integration-Patterns)
- 📖 [Common Use Cases](Common-Use-Cases)
- 📂 [Database Scripts Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/data/databases)
- 📂 [Database README](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/data/databases/README.md)

---

**Last Updated:** 2026-01-27
**Wiki Version:** 1.2.0
**Platforms Covered:** 4 database platforms
