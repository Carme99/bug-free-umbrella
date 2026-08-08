# Server Management

Comprehensive scripts for Windows Server administration including Active Directory, Group Policy, backup management, monitoring, networking, security, storage, and system maintenance. These scripts help automate server operations and ensure infrastructure reliability.

## Overview

The Server Management category provides tools for:
- **Active Directory** - User/computer audits, health checks, and service account management
- **Backup & Recovery** - Backup status monitoring, restore point management, and integrity testing
- **Group Policy** - GPO backup, conflict detection, and reporting
- **Server Monitoring** - Health checks, performance tracking, and event log analysis
- **Network Management** - Firewall configuration, connectivity testing, and network auditing
- **Security Hardening** - Certificate management, security events, and server hardening
- **Storage Management** - Disk monitoring, space optimization, and large file reporting
- **System Maintenance** - Windows Update, scheduled reboots, and system integrity checks
- **User Management** - Inactive user reports, access audits, and lockout tracking

All scripts are located in: [scripts/infrastructure/windows/](../scripts/infrastructure/windows/)

---

## Script Categories

### Active Directory Management
Domain controller and AD object management.

| Script | Description | Location |
|--------|-------------|----------|
| **Get-ADHealthCheck.ps1** | Comprehensive AD health and replication check | `scripts/infrastructure/windows/active-directory/` |
| **Get-ADUserAudit.ps1** | Audit AD user accounts and permissions | `scripts/infrastructure/windows/active-directory/` |
| **Find-InactiveADComputers.ps1** | Find computers inactive for specified days | `scripts/infrastructure/windows/active-directory/` |
| **Get-ServiceAccountAudit.ps1** | Audit service accounts and SPNs | `scripts/infrastructure/windows/active-directory/` |

### Backup & Recovery
Backup monitoring and disaster recovery.

| Script | Description | Location |
|--------|-------------|----------|
| **Get-BackupStatus.ps1** | Check Windows Server Backup status | `scripts/infrastructure/windows/backup-recovery/` |
| **Test-BackupIntegrity.ps1** | Verify backup integrity and recoverability | `scripts/infrastructure/windows/backup-recovery/` |
| **Manage-RestorePoints.ps1** | Create and manage system restore points | `scripts/infrastructure/windows/backup-recovery/` |

### Group Policy Management
GPO administration and conflict resolution.

| Script | Description | Location |
|--------|-------------|----------|
| **Get-GPOReport.ps1** | Generate comprehensive GPO report | `scripts/infrastructure/windows/group-policy/` |
| **Backup-GroupPolicies.ps1** | Backup all Group Policy Objects | `scripts/infrastructure/windows/group-policy/` |
| **Find-GPOConflicts.ps1** | Detect conflicting GPO settings | `scripts/infrastructure/windows/group-policy/` |

### Server Monitoring
Real-time health monitoring and performance tracking.

| Script | Description | Location |
|--------|-------------|----------|
| **Monitor-ServerHealth.ps1** | Comprehensive server health monitoring | `scripts/infrastructure/windows/monitoring/` |
| **Get-PerformanceReport.ps1** | Generate performance metrics report | `scripts/infrastructure/windows/monitoring/` |
| **Get-EventLogReport.ps1** | Analyze Windows Event Logs for issues | `scripts/infrastructure/windows/monitoring/` |

### Network Management
Network configuration and connectivity monitoring.

| Script | Description | Location |
|--------|-------------|----------|
| **Get-NetworkConfiguration.ps1** | Export network adapter configuration | `scripts/infrastructure/windows/network/` |
| **Get-FirewallRulesReport.ps1** | Document firewall rules and policies | `scripts/infrastructure/windows/network/` |
| **Test-ServerConnectivity.ps1** | Test network connectivity to services | `scripts/infrastructure/windows/network/` |

### Security Management
Security auditing and hardening.

| Script | Description | Location |
|--------|-------------|----------|
| **Test-ServerHardening.ps1** | Validate security hardening measures | `scripts/infrastructure/windows/security/` |
| **Test-CertificateExpiration.ps1** | Monitor SSL/TLS certificate expiration | `scripts/infrastructure/windows/security/` |
| **Get-SecurityEventAudit.ps1** | Audit security events and logons | `scripts/infrastructure/windows/security/` |
| **Manage-FirewallRules.ps1** | Create and manage Windows Firewall rules | `scripts/infrastructure/windows/security/` |

### Storage Management
Disk space monitoring and optimization.

| Script | Description | Location |
|--------|-------------|----------|
| **Get-DiskReport.ps1** | Comprehensive disk usage report | `scripts/infrastructure/windows/storage/` |
| **Get-LargeFilesReport.ps1** | Find largest files consuming disk space | `scripts/infrastructure/windows/storage/` |
| **Optimize-ServerStorage.ps1** | Optimize disk storage and clean up | `scripts/infrastructure/windows/storage/` |

### System Maintenance
System updates, reboots, and maintenance tasks.

| Script | Description | Location |
|--------|-------------|----------|
| **Reset-WindowsUpdate.ps1** | Reset Windows Update components | `scripts/infrastructure/windows/system/` |
| **Check-SystemIntegrity.ps1** | Run SFC and DISM integrity checks | `scripts/infrastructure/windows/system/` |
| **New-WeeklyRebootSchedule.ps1** | Schedule weekly server reboots | `scripts/infrastructure/windows/system/` |
| **Set-EnglishUKRegion.ps1** | Configure regional settings for UK | `scripts/infrastructure/windows/system/` |
| **Remove-USLanguagePack.ps1** | Remove US English language pack | `scripts/infrastructure/windows/system/` |

### User Management
User account auditing and access reporting.

| Script | Description | Location |
|--------|-------------|----------|
| **Get-InactiveUserReport.ps1** | Find inactive user accounts | `scripts/infrastructure/windows/user-management/` |
| **Get-UserAccessReport.ps1** | Audit user access and permissions | `scripts/infrastructure/windows/user-management/` |
| **Get-UserLockoutReport.ps1** | Track account lockout events | `scripts/infrastructure/windows/user-management/` |

---

## Prerequisites

### Required Permissions
- **Domain Administrator** (for Active Directory scripts)
- **Local Administrator** (for server configuration scripts)
- **Backup Operator** (for backup scripts)
- **Security audit permissions** (for security scripts)

### Required Modules
```powershell
# Active Directory module
Install-Module ActiveDirectory -Scope CurrentUser

# Group Policy module (included in RSAT)
# Install via: Add-WindowsFeature RSAT-AD-PowerShell

# Windows Server Backup module
Install-WindowsFeature Windows-Server-Backup -IncludeManagementTools

# No additional modules for most scripts - built-in cmdlets used
```

### System Requirements
- **Windows Server 2016+** (2019/2022 recommended)
- **PowerShell 5.1+** (PowerShell 7+ recommended)
- **RSAT Tools** installed for AD/GPO scripts
- **Execution policy** set to RemoteSigned or Bypass

---

## Common Use Cases

### 1. Server Health Monitoring

Comprehensive real-time health monitoring with advanced checks and reporting.

**Basic Health Check:**
```powershell
# Quick health check with default settings
.\Monitor-ServerHealth.ps1

# Export detailed HTML report
.\Monitor-ServerHealth.ps1 -ExportReport

# Set custom alert thresholds
.\Monitor-ServerHealth.ps1 -AlertThreshold High
```

**Advanced Monitoring:**
```powershell
# Comprehensive monitoring with all optional checks
.\Monitor-ServerHealth.ps1 -ExportReport `
                           -IncludeDiskIO `
                           -IncludeWindowsUpdate `
                           -IncludeSecurity `
                           -IncludeNetwork `
                           -IncludeCertificates `
                           -IncludeScheduledTasks `
                           -IncludeApplications

# Monitor specific services
.\Monitor-ServerHealth.ps1 -CheckServices "W3SVC,MSSQLSERVER,WinRM" -ExportReport

# Email report to admins
.\Monitor-ServerHealth.ps1 -EmailReport `
                           -SMTPServer "smtp.company.com" `
                           -EmailFrom "monitoring@company.com" `
                           -EmailTo "admins@company.com"
```

**Sample Output:**
```
=== Windows Server Health Check ===
Server: DC01
Date: 2025-12-31 10:00:00
Uptime: 45 days, 12 hours

System Information:
OS: Windows Server 2022 Datacenter
Version: 21H2 (Build 20348.1547)
Role: Domain Controller

CPU:
Current Usage: 15%
Average (5 min): 18%
Trend: Normal
Status: HEALTHY

Memory:
Total: 32 GB
Used: 12 GB (37.5%)
Available: 20 GB (62.5%)
Page File Usage: 2.1 GB
Status: HEALTHY

Disk Space:
C:\ - 120 GB total, 45 GB free (37.5%)
D:\ - 500 GB total, 380 GB free (76%)
E:\ - 1 TB total, 450 GB free (45%)
Status: HEALTHY

Critical Services:
Active Directory Domain Services: Running
DNS Server: Running
DFS Replication: Running
Netlogon: Running
Status: ALL CRITICAL SERVICES RUNNING

Event Logs (Last 24 hours):
Critical: 0
Errors: 3 (review recommended)
Warnings: 12

Network Adapters:
Ethernet0: UP - 1 Gbps - 192.168.1.10
Status: HEALTHY

Overall Health: HEALTHY
Recommendations:
- Review 3 error events in Event Log
- Consider upgrading to latest Windows Update
```

**Interactive Monitoring Mode:**
```powershell
# Launch interactive monitoring dashboard
.\Monitor-ServerHealth.ps1 -Interactive

# Interactive mode allows:
# - Real-time metric updates every 30 seconds
# - Enable/disable checks on the fly
# - Quick remediation actions
# - Export reports on demand
```

### 2. Active Directory Health Check

Verify AD replication, FSMO roles, and domain controller health.

```powershell
# Basic AD health check
.\Get-ADHealthCheck.ps1

# Comprehensive check with detailed reporting
.\Get-ADHealthCheck.ps1 -Detailed -ExportHTML

# Check specific domain controller
.\Get-ADHealthCheck.ps1 -DomainController "DC01.company.local"

# Include SYSVOL and DFSR replication
.\Get-ADHealthCheck.ps1 -IncludeReplication -IncludeDFSR -ExportHTML
```

**Sample Output:**
```
=== Active Directory Health Check ===
Forest: company.local
Domain: company.local
Date: 2025-12-31 10:00:00

Domain Controllers:
1. DC01.company.local - Online - Windows Server 2022
2. DC02.company.local - Online - Windows Server 2022
3. DC03.company.local - Online - Windows Server 2019

FSMO Roles:
Schema Master: DC01.company.local
Domain Naming Master: DC01.company.local
PDC Emulator: DC02.company.local
RID Master: DC02.company.local
Infrastructure Master: DC03.company.local
Status: All FSMO role holders online

AD Replication Status:
DC01 <-> DC02: Last Success: 2025-12-31 09:55:00 - Healthy
DC01 <-> DC03: Last Success: 2025-12-31 09:56:00 - Healthy
DC02 <-> DC03: Last Success: 2025-12-31 09:54:00 - Healthy
Replication Errors: 0
Status: REPLICATION HEALTHY

SYSVOL Replication (DFSR):
All servers in sync
Last replication: 2025-12-31 09:58:00
Status: HEALTHY

DNS Tests:
DC01: PASS - All DNS zones replicated
DC02: PASS - All DNS zones replicated
DC03: PASS - All DNS zones replicated

Domain Health:
Total Users: 1,500
Total Computers: 2,300
Total Groups: 450
Disabled Accounts: 234
Locked Accounts: 3

Overall Status: HEALTHY
Warnings: 3 locked accounts need investigation
```

### 3. Group Policy Management

Backup GPOs and detect policy conflicts.

**Backup Group Policies:**
```powershell
# Backup all GPOs
.\Backup-GroupPolicies.ps1

# Backup to specific location
.\Backup-GroupPolicies.ps1 -BackupPath "\\FileServer\GPO-Backups"

# Backup with timestamp
.\Backup-GroupPolicies.ps1 -BackupPath "C:\GPO-Backups\$(Get-Date -Format 'yyyy-MM-dd')"

# Include HTML report
.\Backup-GroupPolicies.ps1 -GenerateReport -ExportHTML
```

**Find GPO Conflicts:**
```powershell
# Detect conflicting GPO settings
.\Find-GPOConflicts.ps1

# Check specific OU
.\Find-GPOConflicts.ps1 -OrganizationalUnit "OU=Servers,DC=company,DC=local"

# Export detailed conflict report
.\Find-GPOConflicts.ps1 -Detailed -ExportHTML
```

**Sample Output:**
```
=== Group Policy Conflict Report ===
Total GPOs: 42
GPOs Analyzed: 42
Conflicts Detected: 5

Conflict #1:
OU: OU=Workstations,DC=company,DC=local
Setting: Password Policy - Minimum Length
Conflicting GPOs:
  1. "Corporate Password Policy" (Link Order: 1)
     Setting: 14 characters
  2. "Legacy Password Policy" (Link Order: 2)
     Setting: 8 characters
Winner: "Corporate Password Policy" (higher precedence)
Recommendation: Remove or disable "Legacy Password Policy"

Conflict #2:
OU: OU=Servers,DC=company,DC=local
Setting: Windows Firewall - Enable
Conflicting GPOs:
  1. "Server Security Policy" (Enforced)
     Setting: Enabled
  2. "Test Firewall Policy" (Not Enforced)
     Setting: Disabled
Winner: "Server Security Policy" (enforced)
Recommendation: Remove "Test Firewall Policy" from production

Resolution Recommendations:
1. Review and consolidate 5 conflicting policies
2. Remove 2 legacy policies no longer needed
3. Document GPO link order for complex OUs
4. Consider using GPO comments for policy purpose
```

### 4. Backup Status Monitoring

Monitor Windows Server Backup health and verify integrity.

```powershell
# Check backup status
.\Get-BackupStatus.ps1

# Check backups with age threshold
.\Get-BackupStatus.ps1 -MaxAgeHours 24

# Export backup report
.\Get-BackupStatus.ps1 -ExportHTML

# Verify backup integrity
.\Test-BackupIntegrity.ps1 -BackupLocation "E:\WindowsBackup"
```

**Sample Output:**
```
=== Windows Server Backup Status ===
Server: FS01
Date: 2025-12-31 10:00:00

Backup Configuration:
Backup Type: Full Server Backup
Schedule: Daily at 2:00 AM
Target: Local Disk (E:\WindowsBackup)
Retention: 14 days

Last Backup:
Status: Success
Start Time: 2025-12-31 02:00:15
End Time: 2025-12-31 03:45:32
Duration: 1 hour 45 minutes
Backup Size: 245 GB

Backup History (Last 7 days):
2025-12-31: Success - 245 GB
2025-12-30: Success - 243 GB
2025-12-29: Success - 242 GB
2025-12-28: Success - 240 GB
2025-12-27: Success - 238 GB
2025-12-26: Success - 241 GB
2025-12-25: Success - 239 GB
Success Rate: 100%

Disk Space:
Backup Volume: E:\ (1 TB total)
Used: 485 GB (48.5%)
Available: 515 GB (51.5%)
Estimated Days Until Full: 42 days

Backup Integrity:
Last Verification: 2025-12-30
Status: Verified - All files recoverable
Next Verification: 2026-01-06

Overall Status: HEALTHY
Recommendations: None
```

### 5. Security Event Auditing

Monitor failed logins, privilege escalation, and security events.

```powershell
# Audit security events from last 24 hours
.\Get-SecurityEventAudit.ps1

# Check last 7 days with details
.\Get-SecurityEventAudit.ps1 -Days 7 -Detailed

# Focus on failed logons
.\Get-SecurityEventAudit.ps1 -EventType FailedLogon -Days 30 -ExportHTML

# Monitor privilege escalation
.\Get-SecurityEventAudit.ps1 -EventType PrivilegeUse -Detailed -ExportHTML
```

**Sample Output:**
```
=== Security Event Audit ===
Server: DC01
Period: Last 24 hours
Date: 2025-12-31

Event Summary:
Total Security Events: 12,456
Logon Events: 8,234
Failed Logons: 45
Account Lockouts: 2
Privilege Use: 234
Policy Changes: 3
Object Access: 3,945

Failed Logon Analysis:
Total Failed Logons: 45

By Account:
1. admin (18 attempts) - Multiple IPs
2. administrator (12 attempts)
3. root (8 attempts) - Suspicious
4. backup_service (5 attempts) - Service account
5. guest (2 attempts)

By Source IP:
1. 192.168.1.150 (15 attempts) - Internal workstation
2. 10.0.0.25 (12 attempts) - Internal server
3. 203.0.113.45 (10 attempts) - EXTERNAL - ALERT
4. 192.168.1.89 (8 attempts) - Internal laptop

Account Lockouts:
1. john.doe - Locked at 2025-12-31 08:15:00
   Source: 192.168.1.150 (WORKSTATION-042)
   Reason: Multiple incorrect passwords
   Status: Unlocked at 08:45:00

2. service_backup - Locked at 2025-12-31 14:30:00
   Source: 192.168.1.200 (BACKUP-SRV)
   Reason: Password expired
   Status: Still locked - ACTION REQUIRED

Policy Changes:
1. 2025-12-31 09:00:00 - User Rights Assignment modified
   Modified By: domain\IT-Admin
   Change: Added "Backup-Service" to "Backup files and directories"

Security Recommendations:
1. Investigate external IP 203.0.113.45 attempting logins
2. Review "admin" account - 18 failed attempts in 24 hours
3. Reset password for service_backup account (locked)
4. Consider implementing account lockout threshold if not enabled
```

### 6. Disk Space Management

Monitor disk usage, find large files, and optimize storage.

```powershell
# Generate disk report
.\Get-DiskReport.ps1

# Include file system details
.\Get-DiskReport.ps1 -Detailed -ExportHTML

# Find large files (>1 GB)
.\Get-LargeFilesReport.ps1 -MinimumSizeGB 1

# Find large files in specific path
.\Get-LargeFilesReport.ps1 -Path "D:\Data" -MinimumSizeGB 0.5 -Top 100 -ExportCSV

# Optimize server storage
.\Optimize-ServerStorage.ps1 -ScanOnly

# Run optimization (with cleanup)
.\Optimize-ServerStorage.ps1 -CleanTemp -CleanLogs -DefragmentDisks
```

**Sample Output:**
```
=== Disk Usage Report ===
Server: FS01
Date: 2025-12-31

Disk Summary:
┌──────┬──────────┬──────────┬──────────┬──────────┬────────┐
│ Disk │ Total    │ Used     │ Free     │ % Free   │ Status │
├──────┼──────────┼──────────┼──────────┼──────────┼────────┤
│ C:\  │ 120 GB   │ 68 GB    │ 52 GB    │ 43%      │ OK     │
│ D:\  │ 500 GB   │ 425 GB   │ 75 GB    │ 15%      │ WARN   │
│ E:\  │ 1 TB     │ 485 GB   │ 515 GB   │ 52%      │ OK     │
│ F:\  │ 2 TB     │ 1.8 TB   │ 200 GB   │ 10%      │ WARN   │
└──────┴──────────┴──────────┴──────────┴──────────┴────────┘

Warnings:
- D:\ has only 15% free space (75 GB)
- F:\ has only 10% free space (200 GB)

=== Large Files Report ===
Top 20 Largest Files:

1. F:\Backups\SQL\FULL_20251230.bak - 145 GB
2. F:\Backups\SQL\FULL_20251229.bak - 143 GB
3. F:\Backups\SQL\FULL_20251228.bak - 142 GB
4. D:\Logs\IIS\Archive_2025.zip - 38 GB
5. D:\Data\Database.mdf - 28 GB
...

Space Usage by Directory (D:\):
1. D:\Logs - 180 GB (42%)
2. D:\Data - 150 GB (35%)
3. D:\Backups - 65 GB (15%)
4. D:\Temp - 30 GB (7%)

Optimization Recommendations:
1. D:\ - Remove old IIS log archives (38 GB potential savings)
2. F:\ - Implement backup retention (3+ old SQL backups = 400+ GB)
3. D:\Temp - Clean temporary files (30 GB)
4. Consider expanding D:\ and F:\ volumes
5. Estimated reclaimable space: 468 GB
```

### 7. Certificate Expiration Monitoring

Monitor SSL/TLS certificates and prevent unexpected expiration.

```powershell
# Check certificates expiring in next 30 days
.\Test-CertificateExpiration.ps1

# Custom expiration window (90 days)
.\Test-CertificateExpiration.ps1 -DaysToExpire 90

# Check specific certificate store
.\Test-CertificateExpiration.ps1 -CertStore "LocalMachine\My" -ExportHTML

# Include all certificate stores
.\Test-CertificateExpiration.ps1 -AllStores -DaysToExpire 60 -ExportHTML
```

**Sample Output:**
```
=== Certificate Expiration Report ===
Server: WEB01
Date: 2025-12-31
Alert Threshold: 30 days

Certificates Expiring Soon:
┌──────────────────────────────────┬─────────────┬──────────────┬────────────┐
│ Subject                          │ Expires     │ Days Left    │ Store      │
├──────────────────────────────────┼─────────────┼──────────────┼────────────┤
│ CN=*.company.com                 │ 2026-01-15  │ 15 days      │ My         │
│ CN=mail.company.com              │ 2026-01-22  │ 22 days      │ My         │
│ CN=vpn.company.com               │ 2026-02-05  │ 35 days      │ My         │
└──────────────────────────────────┴─────────────┴──────────────┴────────────┘

Critical (< 15 days): 1
Warning (15-30 days): 1
Info (30-90 days): 1

Expired Certificates:
None found

Certificate Details:

1. *.company.com (Wildcard)
   Subject: CN=*.company.com
   Issuer: DigiCert
   Expires: 2026-01-15 23:59:59 (15 days)
   Thumbprint: A1B2C3D4E5F6...
   Status: CRITICAL - Renew immediately
   Used By: IIS bindings (www, api, portal)

2. mail.company.com
   Subject: CN=mail.company.com
   Issuer: Let's Encrypt
   Expires: 2026-01-22 14:30:00 (22 days)
   Thumbprint: F6E5D4C3B2A1...
   Status: WARNING - Schedule renewal
   Used By: Exchange Server

Recommendations:
1. Renew *.company.com immediately (15 days remaining)
2. Schedule renewal for mail.company.com (22 days remaining)
3. Set up auto-renewal for Let's Encrypt certificates
4. Consider certificate lifecycle management tool
```

### 8. Windows Update Management

Reset Windows Update when updates fail or get stuck.

```powershell
# Reset Windows Update components
.\Reset-WindowsUpdate.ps1

# Reset with verbose logging
.\Reset-WindowsUpdate.ps1 -Verbose

# Check system integrity after reset
.\Check-SystemIntegrity.ps1
```

**Sample Output:**
```
=== Windows Update Reset ===
Server: APP01
Date: 2025-12-31 10:00:00

[1/8] Stopping Windows Update services...
  - Windows Update service (wuauserv): Stopped
  - BITS service (bits): Stopped
  - Cryptographic Services (cryptsvc): Stopped
  - MSI Installer (msiserver): Stopped

[2/8] Deleting temporary update files...
  - Renamed C:\Windows\SoftwareDistribution to .old
  - Removed C:\Windows\System32\catroot2

[3/8] Resetting Windows Update registry settings...
  - Reset HKLM:\Software\Microsoft\Windows\CurrentVersion\WindowsUpdate
  - Cleared BITS queue

[4/8] Re-registering Windows Update DLLs...
  - Registered wuaueng.dll
  - Registered wuapi.dll
  - Registered wups.dll
  - Registered wuwebv.dll
  - Registered qmgr.dll
  - Registered qmgrprxy.dll
  - Registered wucltux.dll
  - Registered muweb.dll

[5/8] Starting Windows Update services...
  - Windows Update service: Started
  - BITS service: Started
  - Cryptographic Services: Started

[6/8] Forcing Windows Update detection...
  - Update detection triggered

[7/8] Running system integrity check...
  - SFC scan: No integrity violations found
  - Component Store: Healthy

[8/8] Verifying Windows Update functionality...
  - Windows Update service: Running
  - Update catalog accessible: Yes
  - Last successful check: Never (pre-reset)
  - Triggering new update check...

Reset Complete!
Recommendations:
1. Check for updates manually in Settings
2. Review Windows Update Event Logs
3. Monitor for next 24 hours to ensure updates install
4. If issues persist, run DISM: .\Check-SystemIntegrity.ps1 -RunDISM
```

---

## Script Examples

### Example 1: Daily Server Health Check Script

Automated daily health check with email notifications.

```powershell
# Daily-ServerHealthCheck.ps1
# Schedule via Task Scheduler: Daily at 8:00 AM

$ReportDate = Get-Date -Format "yyyy-MM-dd"
$ReportPath = "C:\Reports\DailyHealth\$ReportDate"
New-Item -Path $ReportPath -ItemType Directory -Force

Write-Host "=== Daily Server Health Check ===" -ForegroundColor Cyan
Write-Host "Date: $(Get-Date)`n"

# Array to collect issues
$Issues = @()

# 1. Server Health
Write-Host "[1/6] Checking server health..." -ForegroundColor Yellow
$Health = .\Monitor-ServerHealth.ps1 -ExportReport -OutputPath $ReportPath

if ($Health.CriticalIssues -gt 0) {
    $Issues += "Server health: $($Health.CriticalIssues) critical issues"
}

# 2. Disk Space
Write-Host "[2/6] Checking disk space..." -ForegroundColor Yellow
$Disk = .\Get-DiskReport.ps1 -ExportHTML -OutputPath $ReportPath

if ($Disk.LowSpaceDisks -gt 0) {
    $Issues += "Disk space: $($Disk.LowSpaceDisks) volumes low on space"
}

# 3. Backup Status
Write-Host "[3/6] Verifying backup..." -ForegroundColor Yellow
$Backup = .\Get-BackupStatus.ps1 -MaxAgeHours 24

if ($Backup.Status -ne "Success") {
    $Issues += "Backup: Last backup $($Backup.Status)"
}

# 4. Security Events
Write-Host "[4/6] Reviewing security events..." -ForegroundColor Yellow
$Security = .\Get-SecurityEventAudit.ps1 -Days 1

if ($Security.FailedLogons -gt 50) {
    $Issues += "Security: $($Security.FailedLogons) failed logons in 24 hours"
}

# 5. Event Logs
Write-Host "[5/6] Analyzing event logs..." -ForegroundColor Yellow
$EventLog = .\Get-EventLogReport.ps1 -Hours 24 -ExportHTML -OutputPath $ReportPath

if ($EventLog.CriticalEvents -gt 0) {
    $Issues += "Event Logs: $($EventLog.CriticalEvents) critical events"
}

# 6. Certificate Expiration
Write-Host "[6/6] Checking certificates..." -ForegroundColor Yellow
$Certs = .\Test-CertificateExpiration.ps1 -DaysToExpire 30

if ($Certs.ExpiringCerts -gt 0) {
    $Issues += "Certificates: $($Certs.ExpiringCerts) expiring within 30 days"
}

# Generate summary
$Summary = @"
Daily Server Health Check - $env:COMPUTERNAME
Date: $(Get-Date)

Status: $(if ($Issues.Count -eq 0) { "HEALTHY" } else { "ISSUES DETECTED" })

$(if ($Issues.Count -gt 0) {
    "Issues Found:`n" + ($Issues | ForEach-Object { "  - $_" } | Out-String)
} else {
    "No issues detected. All systems nominal."
})

Detailed reports saved to: $ReportPath
"@

Write-Host "`n$Summary" -ForegroundColor $(if ($Issues.Count -eq 0) { "Green" } else { "Yellow" })

# Email report
Send-MailMessage -To "serveradmins@company.com" `
                 -From "monitoring@company.com" `
                 -Subject "Daily Health Check - $env:COMPUTERNAME - $(if ($Issues.Count -eq 0) { 'HEALTHY' } else { 'ISSUES' })" `
                 -Body $Summary `
                 -SmtpServer "smtp.company.com" `
                 -Attachments (Get-ChildItem $ReportPath -Filter *.html).FullName
```

### Example 2: Monthly Server Maintenance

Comprehensive monthly maintenance tasks.

```powershell
# Monthly-ServerMaintenance.ps1
# Schedule via Task Scheduler: 1st Sunday of month at 2:00 AM

$MaintenanceDate = Get-Date -Format "yyyy-MM"
$OutputPath = "C:\Maintenance\$MaintenanceDate"
New-Item -Path $OutputPath -ItemType Directory -Force

Write-Host "=== Monthly Server Maintenance ===" -ForegroundColor Cyan
Write-Host "Server: $env:COMPUTERNAME"
Write-Host "Date: $(Get-Date)`n"

# 1. Backup Group Policies
Write-Host "[1/8] Backing up Group Policies..." -ForegroundColor Yellow
.\Backup-GroupPolicies.ps1 -BackupPath "$OutputPath\GPO-Backup" -GenerateReport

# 2. AD Health Check
Write-Host "[2/8] Running AD health check..." -ForegroundColor Yellow
.\Get-ADHealthCheck.ps1 -Detailed -IncludeReplication -ExportHTML -OutputPath $OutputPath

# 3. Find Inactive Computers
Write-Host "[3/8] Finding inactive computers..." -ForegroundColor Yellow
.\Find-InactiveADComputers.ps1 -DaysInactive 90 -ExportCSV -OutputPath $OutputPath

# 4. User Account Audit
Write-Host "[4/8] Auditing user accounts..." -ForegroundColor Yellow
.\Get-InactiveUserReport.ps1 -DaysInactive 90 -ExportHTML -OutputPath $OutputPath

# 5. Service Account Audit
Write-Host "[5/8] Auditing service accounts..." -ForegroundColor Yellow
.\Get-ServiceAccountAudit.ps1 -ExportCSV -OutputPath $OutputPath

# 6. Storage Optimization
Write-Host "[6/8] Optimizing storage..." -ForegroundColor Yellow
.\Optimize-ServerStorage.ps1 -CleanTemp -CleanLogs -DefragmentDisks -ExportReport -OutputPath $OutputPath

# 7. System Integrity Check
Write-Host "[7/8] Checking system integrity..." -ForegroundColor Yellow
.\Check-SystemIntegrity.ps1 -RunSFC -RunDISM -ExportLog -OutputPath $OutputPath

# 8. Create System Restore Point
Write-Host "[8/8] Creating restore point..." -ForegroundColor Yellow
.\Manage-RestorePoints.ps1 -Create -Description "Monthly Maintenance - $MaintenanceDate"

Write-Host "`n=== Maintenance Complete ===" -ForegroundColor Green
Write-Host "Reports saved to: $OutputPath"

# Email summary
$Summary = @"
Monthly Server Maintenance Complete
Server: $env:COMPUTERNAME
Date: $(Get-Date)

Tasks Completed:
✓ Group Policy backup
✓ Active Directory health check
✓ Inactive computer cleanup
✓ User account audit
✓ Service account audit
✓ Storage optimization
✓ System integrity verification
✓ System restore point created

Reports and backups saved to: $OutputPath

Next maintenance: $(( Get-Date).AddMonths(1).ToString('yyyy-MM-dd'))
"@

Send-MailMessage -To "serveradmins@company.com" `
                 -From "maintenance@company.com" `
                 -Subject "Monthly Maintenance Complete - $env:COMPUTERNAME" `
                 -Body $Summary `
                 -SmtpServer "smtp.company.com"
```

---

## Best Practices

### Monitoring
1. **Automate daily checks** - Schedule health monitoring via Task Scheduler
2. **Set alert thresholds** - Configure appropriate thresholds for your environment
3. **Centralize logging** - Store reports in central location for historical analysis
4. **Email notifications** - Send alerts for critical issues immediately
5. **Trend analysis** - Review metrics over time to identify patterns

### Backup & Recovery
1. **Test restores regularly** - Verify backups are recoverable monthly
2. **Monitor backup age** - Alert if backup older than 24 hours
3. **Check disk space** - Ensure backup target has sufficient space
4. **Multiple backup copies** - Follow 3-2-1 rule (3 copies, 2 media types, 1 offsite)
5. **Document procedures** - Maintain recovery documentation

### Active Directory
1. **Regular health checks** - Monitor AD health weekly
2. **Audit permissions** - Review admin privileges quarterly
3. **Clean up inactive objects** - Remove stale computers/users monthly
4. **Monitor replication** - Check replication status daily
5. **Backup GPOs** - Backup Group Policies before changes

### Security
1. **Monitor failed logins** - Review security events daily
2. **Certificate lifecycle** - Track certificate expiration monthly
3. **Audit privileged access** - Monitor admin account usage
4. **Patch management** - Keep servers updated with latest patches
5. **Firewall rules** - Review and document firewall rules quarterly

---

## Troubleshooting

### Common Issues

**Active Directory scripts fail with "Cannot find domain controller":**
```powershell
# Verify domain controller connectivity
Test-Connection -ComputerName "DC01.company.local" -Count 2

# Check DNS resolution
Resolve-DnsName "company.local"

# Test AD Web Services
Get-Service -Name ADWS -ComputerName "DC01.company.local"
```

**Backup status script returns no backups:**
- Verify Windows Server Backup is installed: `Get-WindowsFeature Windows-Server-Backup`
- Check if backups are configured: `Get-WBPolicy`
- Review backup event logs: `Get-WinEvent -LogName "Microsoft-Windows-Backup"`

**Performance monitoring shows high resource usage:**
- Identify top processes: `Get-Process | Sort-Object CPU -Descending | Select-Object -First 10`
- Check for memory leaks: Review process memory over time
- Analyze disk I/O: Use Resource Monitor or Performance Monitor

**Event log scripts timeout on large logs:**
- Reduce time range: Use `-Hours 24` instead of `-Days 30`
- Filter by event level: Use `-EventLevel Error,Critical`
- Archive old logs: Move historical logs to separate files

---

## 💻 Quick Start Examples

### Example 1: Comprehensive Server Health Check
```powershell
# Full health check with all metrics
.\Monitor-ServerHealth.ps1 -IncludeDiskIO `
    -CheckWindowsUpdate `
    -CheckSecurity `
    -EmailReport `
    -EmailTo "ops@company.com"
```

### Example 2: Backup Status Verification
```powershell
# Check backup status (last 7 days)
.\Get-BackupStatus.ps1 -Days 7 -ExportHTML

# Alert if no backup in 2+ days
.\Get-BackupStatus.ps1 -Days 2 -EmailIfNoBackup -EmailTo "backup-team@company.com"
```

### Example 3: Event Log Monitoring
```powershell
# Get critical errors (last 24 hours)
.\Get-EventLogReport.ps1 -LogName System -Level Error -Hours 24 -ExportHTML
```

---

## Related Resources

### Internal Documentation
- **[Prerequisites](Prerequisites.md)** - Required modules and permissions
- **[Security & Compliance](Security-Compliance.md)** - Security auditing scripts
- **[Intune Management](Intune-Management.md)** - Device management scripts
- **[FAQ](FAQ.md)** - Common questions and answers

### External Resources
- **[Windows Server Documentation](https://learn.microsoft.com/en-us/windows-server/)** - Official Microsoft docs
- **[Active Directory Best Practices](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/security-best-practices/best-practices-for-securing-active-directory)** - AD security guidance
- **[PowerShell Gallery](https://www.powershellgallery.com/)** - Community scripts and modules
- **[Windows Server Blog](https://techcommunity.microsoft.com/t5/windows-server-blog/bg-p/Windows-Server-Blog)** - Microsoft Tech Community
