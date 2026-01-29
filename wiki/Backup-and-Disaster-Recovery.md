# 💾 Backup & Disaster Recovery Guide

![Backup](https://img.shields.io/badge/backup-Windows_Server_Backup-0078D6?logo=windows)
![Recovery](https://img.shields.io/badge/recovery-System_Restore-success)
![Scripts](https://img.shields.io/badge/scripts-3-orange)

> **Comprehensive backup verification and disaster recovery management for Windows environments**

---

## 📋 Table of Contents
- [Overview](#overview)
- [Available Scripts](#available-scripts)
- [Prerequisites](#prerequisites)
- [Quick Start Examples](#quick-start-examples)
- [Common Workflows](#common-workflows)
- [Backup Strategy](#backup-strategy)
- [Disaster Recovery Planning](#disaster-recovery-planning)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

![Coverage](https://img.shields.io/badge/coverage-Windows_Servers-blue)
![RTO](https://img.shields.io/badge/RTO-4--6_hours-yellow)
![RPO](https://img.shields.io/badge/RPO-24_hours-green)

Bug-Free Umbrella provides **3 comprehensive backup & disaster recovery scripts**:

| Script | Purpose | Key Features |
|--------|---------|--------------|
| **Get-BackupStatus.ps1** | Verify backup status | History, targets, alerting |
| **Manage-RestorePoints.ps1** | System restore points | Create, list, cleanup |
| **Test-BackupIntegrity.ps1** | Backup validation | Integrity testing |

**Recovery Objectives:**
- **RTO** (Recovery Time Objective): 4-6 hours for bare metal recovery
- **RPO** (Recovery Point Objective): 24 hours maximum data loss

---

## Available Scripts

### Get-BackupStatus.ps1

![Location](https://img.shields.io/badge/location-scripts/infrastructure/windows/backup--recovery-blue)
![Type](https://img.shields.io/badge/type-monitoring-green)

**Windows Server Backup status verification and reporting**

**Features:**
- ✅ Backup history retrieval (configurable days)
- ✅ Backup target validation
- ✅ Integrity status checking
- ✅ Email alerting (no backup warnings)
- ✅ HTML and JSON report generation
- ✅ Critical/Warning thresholds

**Thresholds:**
- 🔴 **Critical**: No backup in 2+ days
- 🟡 **Warning**: No backup in 1 day
- 🟢 **Success**: Recent backup found

[View Script →](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/infrastructure/windows/backup-recovery/Get-BackupStatus.ps1)

---

### Manage-RestorePoints.ps1

![Location](https://img.shields.io/badge/location-scripts/infrastructure/windows/backup--recovery-blue)
![Type](https://img.shields.io/badge/type-management-orange)

**System restore point creation and management**

**Features:**
- ✅ Create restore points
- ✅ List existing restore points
- ✅ Verify restore point availability
- ✅ Cleanup old restore points
- ✅ Retention management

**Actions:**
- `Create` - Create new restore point
- `List` - Show all restore points
- `Verify` - Check restore point integrity
- `Cleanup` - Remove old restore points

[View Script →](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/infrastructure/windows/backup-recovery/Manage-RestorePoints.ps1)

---

### Test-BackupIntegrity.ps1

![Location](https://img.shields.io/badge/location-scripts/infrastructure/windows/backup--recovery-blue)
![Type](https://img.shields.io/badge/type-validation-yellow)

**Backup integrity verification and testing**

**Features:**
- ✅ Backup file integrity checks
- ✅ Validation testing
- ✅ Corruption detection
- ✅ Detailed reporting

[View Script →](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/infrastructure/windows/backup-recovery/Test-BackupIntegrity.ps1)

---

## Prerequisites

### Required Software

![Windows Server Backup](https://img.shields.io/badge/feature-Windows_Server_Backup-blue)
![Admin Rights](https://img.shields.io/badge/permissions-administrator-red)

```powershell
# Install Windows Server Backup feature
Install-WindowsFeature -Name Windows-Server-Backup -IncludeManagementTools

# Verify installation
Get-WindowsFeature -Name Windows-Server-Backup
```

### Required Permissions

- ✅ Local Administrator rights
- ✅ Backup Operators group membership (minimum)

---

## Quick Start Examples

### Example 1: Check Backup Status

```powershell
# Quick backup status check (last 7 days)
.\Get-BackupStatus.ps1 -Days 7 -ExportHTML
```

**Expected Output:**
```
[+] Checking backup status for last 7 days...
[+] Found 7 successful backups
[+] Last backup: 2026-01-27 02:00:00 (0 days ago)
[+] Backup target: \\NAS\Backups\SERVER01
[✓] Status: Healthy
```

### Example 2: Create Pre-Change Restore Point

```powershell
# Before making system changes
.\Manage-RestorePoints.ps1 -Action Create -Description "Pre-Windows Update"
```

**Expected Output:**
```
[+] Creating system restore point...
[+] Description: Pre-Windows Update
[+] Restore point created successfully
[+] ID: 112
```

### Example 3: Daily Backup Verification with Email Alert

```powershell
# Alert if no backup in last 2 days
.\Get-BackupStatus.ps1 `
    -Days 2 `
    -EmailIfNoBackup `
    -EmailTo "backup-team@company.com" `
    -ExportHTML
```

### Example 4: List All Restore Points

```powershell
# View all available restore points
.\Manage-RestorePoints.ps1 -Action List
```

**Expected Output:**
```
Restore Points:
ID: 112 | Date: 2026-01-27 08:00:00 | Pre-Windows Update
ID: 111 | Date: 2026-01-26 14:30:00 | Before IIS Config Change
ID: 110 | Date: 2026-01-25 09:15:00 | Weekly Automatic
```

### Example 5: Backup Integrity Test

```powershell
# Verify backup integrity
.\Test-BackupIntegrity.ps1 -BackupLocation "\\NAS\Backups\SERVER01"
```

---

## Common Workflows

### Workflow 1: Pre-Change Protection

**Scenario**: Before making critical system changes

```powershell
# Step 1: Verify recent backup exists
.\Get-BackupStatus.ps1 -Days 1 -ExportHTML

# Step 2: Create restore point
.\Manage-RestorePoints.ps1 -Action Create -Description "Pre-SQL Server Upgrade"

# Step 3: Proceed with change
# ... perform your change ...

# Step 4: Verify system stability
# Wait 24-48 hours, monitor for issues

# Step 5: Optional - Cleanup restore point after successful change
.\Manage-RestorePoints.ps1 -Action Cleanup -OlderThanDays 30
```

### Workflow 2: Backup Verification Routine

**Scenario**: Daily automated backup verification

```powershell
# Daily verification script
$Days = 1
$AlertEmail = "backup-team@company.com"

# Check backup status
.\Get-BackupStatus.ps1 `
    -Days $Days `
    -ExportHTML `
    -EmailIfNoBackup `
    -EmailTo $AlertEmail `
    -SmtpServer "smtp.company.com"

# Log result
Write-Host "Backup verification completed at $(Get-Date)" | Out-File -Append "C:\Logs\backup-checks.log"
```

### Workflow 3: Monthly Maintenance

**Scenario**: Monthly backup system maintenance

```powershell
# Month-end backup maintenance

# Step 1: Comprehensive backup history (30 days)
.\Get-BackupStatus.ps1 -Days 30 -ExportHTML -ExportCSV

# Step 2: Integrity test
.\Test-BackupIntegrity.ps1 -BackupLocation "\\NAS\Backups\SERVER01"

# Step 3: Cleanup old restore points (>90 days)
.\Manage-RestorePoints.ps1 -Action Cleanup -OlderThanDays 90

# Step 4: Email consolidated report
Send-MailMessage `
    -To "it-management@company.com" `
    -Subject "Monthly Backup Maintenance Report - $(Get-Date -Format 'MMMM yyyy')" `
    -Attachments "BackupStatus.html","IntegrityTest.html" `
    -SmtpServer "smtp.company.com"
```

### Workflow 4: Scheduled Monitoring Setup

**Scenario**: Automated daily backup monitoring with Task Scheduler

```powershell
# Create scheduled task for daily backup monitoring
$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-File C:\Scripts\Get-BackupStatus.ps1 -Days 2 -EmailIfNoBackup -EmailTo backup-team@company.com -ExportHTML"

$trigger = New-ScheduledTaskTrigger -Daily -At 8:00AM

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName "BFU - Daily Backup Verification" `
    -Description "Verifies Windows Server Backup ran successfully" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -User "SYSTEM" `
    -RunLevel Highest
```

---

## Backup Strategy

### Recommended Backup Configuration

![Frequency](https://img.shields.io/badge/daily-incremental-blue)
![Weekly](https://img.shields.io/badge/weekly-full-green)
![Retention](https://img.shields.io/badge/retention-30_days-orange)

**Backup Schedule:**
- 🕐 **Daily**: Incremental backups at 2:00 AM
- 🕐 **Weekly**: Full backup every Sunday at 12:00 AM
- 📦 **Retention**: 30 days minimum, 90 days recommended

**What to Backup:**
- ✅ **System State** (Registry, boot files, system databases)
- ✅ **Bare Metal Recovery** (full server image)
- ✅ **Critical volumes** (C:\ and data drives)
- ✅ **Application data** (SQL databases, Exchange, etc.)
- ⚠️ **Not needed**: Temp files, page file, hibernation file

### Backup Targets

**Primary Target**: Network storage (NAS/SAN)
```powershell
# Configure backup to network location
wbadmin enable backup -addtarget:\\NAS\Backups\SERVER01 -schedule:02:00
```

**Secondary Target**: External drive (for critical servers)
```powershell
# Additional backup to external disk
wbadmin start backup -backupTarget:E: -include:C:,D: -allCritical
```

### Testing Backups

![Testing](https://img.shields.io/badge/testing-mandatory-critical)

**Monthly Backup Tests:**
```powershell
# Test backup integrity
.\Test-BackupIntegrity.ps1 -BackupLocation "\\NAS\Backups\SERVER01"

# Quarterly: Perform test restore to verify
# 1. Restore to isolated VM
# 2. Verify application functionality
# 3. Document recovery time
```

---

## Disaster Recovery Planning

### Recovery Time Objectives (RTO)

| Scenario | RTO | Notes |
|----------|-----|-------|
| **File restore** | 15-30 minutes | Individual files/folders |
| **System State restore** | 1-2 hours | Registry, boot files |
| **Bare Metal Recovery** | 4-6 hours | Complete server rebuild |
| **Application restore** | 2-4 hours | SQL, Exchange, etc. |

### Recovery Point Objectives (RPO)

| Priority | RPO | Backup Frequency |
|----------|-----|------------------|
| **Critical** | 1 hour | Continuous/hourly backups |
| **Production** | 24 hours | Daily backups |
| **Development** | 1 week | Weekly backups |

### Disaster Recovery Checklist

**Before Disaster:**
- [ ] Document all servers and backup schedules
- [ ] Test restore procedures quarterly
- [ ] Maintain updated network diagrams
- [ ] Store recovery media offsite
- [ ] Document administrator credentials (secure)
- [ ] Create runbooks for common scenarios

**During Recovery:**
- [ ] Assess damage and prioritize systems
- [ ] Locate most recent clean backup
- [ ] Prepare recovery hardware/VM
- [ ] Restore System State or Bare Metal
- [ ] Verify application functionality
- [ ] Document recovery steps taken

**After Recovery:**
- [ ] Conduct post-mortem analysis
- [ ] Update disaster recovery plan
- [ ] Test restored systems thoroughly
- [ ] Communicate with stakeholders
- [ ] Review and improve backup strategy

### Testing Procedures

**Monthly Testing:**
```powershell
# Quick restore test (single file)
wbadmin start recovery -version:01/27/2026-02:00 -itemType:File -items:C:\Test\sample.txt -recoverytarget:C:\Temp
```

**Quarterly Testing:**
- Full System State restore to test VM
- Bare Metal Recovery to isolated environment
- Application restore and functionality verification
- Performance validation
- Document recovery duration

**Annual Testing:**
- Full disaster recovery simulation
- Complete site failover (if applicable)
- All critical systems recovery
- Business continuity validation
- Stakeholder involvement

---

## Best Practices

### 🔒 Security

![Security](https://img.shields.io/badge/priority-high-critical)

- ✅ **Encrypt backups** (BitLocker on backup volumes)
- ✅ **Secure backup locations** (network share permissions)
- ✅ **Offsite storage** (copy critical backups offsite)
- ✅ **Access control** (limit who can delete backups)
- ✅ **Test restores** (verify backups are restorable)

### 📊 Monitoring

![Monitoring](https://img.shields.io/badge/frequency-daily-blue)

**Daily Checks:**
```powershell
# Run daily backup verification
.\Get-BackupStatus.ps1 -Days 1 -EmailIfNoBackup -EmailTo ops@company.com
```

**Weekly Reviews:**
- Review backup reports for trends
- Check backup storage capacity
- Verify backup targets are accessible
- Test random file restore

### 💾 Storage Management

![Storage](https://img.shields.io/badge/capacity-plan_ahead-yellow)

**Capacity Planning:**
- Monitor backup storage growth (track in CSV exports)
- Plan for 3x source data size minimum
- Implement retention policies (30-90 days)
- Archive old backups to cheaper storage

### 🔄 Automation

![Automation](https://img.shields.io/badge/automation-recommended-success)

**Recommended Automation:**
```powershell
# Register automated daily verification
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Scripts\Get-BackupStatus.ps1 -Days 2 -EmailIfNoBackup -EmailTo backup-team@company.com"
$trigger = New-ScheduledTaskTrigger -Daily -At 8:00AM
Register-ScheduledTask -TaskName "Daily Backup Check" -Action $action -Trigger $trigger
```

---

## Troubleshooting

### Issue: "No backups found"

**Symptoms**: Script reports no backups exist

**Possible Causes:**
1. Windows Server Backup not installed
2. No backup schedule configured
3. Backups failing silently

**Solution:**
```powershell
# Check if Windows Server Backup is installed
Get-WindowsFeature -Name Windows-Server-Backup

# Verify backup schedule
wbadmin get schedule

# Check recent backup attempts
wbadmin get versions
```

---

### Issue: "Backup target not accessible"

**Symptoms**: Cannot verify backup location

**Possible Causes:**
1. Network share offline
2. Permission issues
3. Credential problems

**Solution:**
```powershell
# Test network path
Test-Path "\\NAS\Backups\SERVER01"

# Check permissions
Get-Acl "\\NAS\Backups\SERVER01"

# Test with explicit credentials
New-PSDrive -Name "BackupTest" -PSProvider FileSystem -Root "\\NAS\Backups" -Credential (Get-Credential)
```

---

### Issue: "Cannot create restore point"

**Symptoms**: Restore point creation fails

**Possible Causes:**
1. System Protection disabled
2. Insufficient disk space
3. Restore points disabled for volume

**Solution:**
```powershell
# Enable System Protection on C:\
Enable-ComputerRestore -Drive "C:\"

# Check available space
Get-PSDrive C

# Verify System Protection is enabled
vssadmin list shadowstorage
```

---

### Issue: "Email alerts not working"

**Symptoms**: No email notifications received

**Possible Causes:**
1. SMTP server unreachable
2. Authentication required
3. Firewall blocking

**Solution:**
```powershell
# Test SMTP connectivity
Test-NetConnection -ComputerName smtp.company.com -Port 25

# Test Send-MailMessage
Send-MailMessage -To "test@company.com" -From "server@company.com" -Subject "Test" -Body "Test" -SmtpServer "smtp.company.com"
```

---

## Related Resources

- 📖 [Script Catalog](Script-Catalog)
- 📖 [Server Management](Server-Management)
- 📖 [Integration Patterns](Integration-Patterns)
- 📂 [Backup Scripts Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/infrastructure/windows/backup-recovery)
- 📂 [Backup README](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/infrastructure/windows/backup-recovery/README.md)
- 🔗 [Windows Server Backup Cmdlets](https://learn.microsoft.com/en-us/powershell/module/windowsserverbackup/)

---

**Last Updated:** 2026-01-27
**Wiki Version:** 1.2.0
**RTO:** 4-6 hours | **RPO:** 24 hours
