# Backup and Disaster Recovery Scripts

This directory contains scripts for managing Windows Server Backup, system restore points, and disaster recovery verification.

## Scripts

### Get-BackupStatus.ps1
Verifies Windows Server Backup status, configuration, and validates backup integrity.

**Features:**
- Checks backup policy configuration
- Retrieves backup history
- Validates backup targets
- Identifies backup failures
- Optional email reporting
- Backup integrity validation

**Usage:**
```powershell
# Basic backup status check
.\Get-BackupStatus.ps1 -OutputPath "C:\Reports"

# Check last 7 days with alerts
.\Get-BackupStatus.ps1 -CheckDays 7 -AlertIfNoBackup -ValidateBackups

# Email report to administrator
.\Get-BackupStatus.ps1 -EmailReport -EmailTo "admin@contoso.com" -SMTPServer "mail.contoso.com"
```

**Requirements:**
- Windows Server Backup feature installed
- Administrator privileges
- `Install-WindowsFeature Windows-Server-Backup` if not installed

---

### Manage-RestorePoints.ps1
Manages system restore points for servers and workstations.

**Features:**
- Create restore points before changes
- List all available restore points
- Verify restore point health
- Cleanup old restore points
- Retention management

**Usage:**
```powershell
# List all restore points
.\Manage-RestorePoints.ps1 -Action List

# Create restore point before GPO changes
.\Manage-RestorePoints.ps1 -Action Create -Description "Before GPO changes"

# Cleanup old restore points
.\Manage-RestorePoints.ps1 -Action Cleanup -RetentionDays 30

# Verify restore point health
.\Manage-RestorePoints.ps1 -Action Verify
```

**Best Practices:**
- Create restore points before major changes
- Maintain at least 2-3 recent restore points
- Test restore procedures regularly
- Document restore point purposes

---

## Common Workflows

### 1. Pre-Change Protection
Before making system changes:
```powershell
# Create restore point
.\Manage-RestorePoints.ps1 -Action Create -Description "Before Exchange Update"

# Verify Windows Server Backup is current
.\Get-BackupStatus.ps1 -CheckDays 1 -AlertIfNoBackup
```

### 2. Backup Verification Routine
Daily/weekly backup verification:
```powershell
# Check backup status
.\Get-BackupStatus.ps1 -CheckDays 7 -ValidateBackups -OutputPath "C:\BackupReports"

# If backups found, validate integrity
# If no backups, investigate and resolve
```

### 3. Monthly Maintenance
```powershell
# Verify backups for the month
.\Get-BackupStatus.ps1 -CheckDays 30 -ValidateBackups -ExportToCSV

# Cleanup old restore points
.\Manage-RestorePoints.ps1 -Action Cleanup -RetentionDays 60
```

### 4. Scheduled Monitoring
Create a scheduled task to monitor backups:
```powershell
# Daily backup check with email alert
$trigger = New-ScheduledTaskTrigger -Daily -At "8:00AM"
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-File C:\Scripts\Get-BackupStatus.ps1 -CheckDays 2 -AlertIfNoBackup -EmailReport -EmailTo admin@contoso.com -SMTPServer mail.contoso.com"

Register-ScheduledTask -TaskName "Daily Backup Check" -Trigger $trigger -Action $action -RunLevel Highest
```

---

## Backup Strategy Recommendations

### Windows Server Backup Configuration
1. **Backup Frequency:** Daily incremental, weekly full
2. **Backup Scope:**
   - System State
   - Bare Metal Recovery
   - Critical volumes
3. **Retention:** Maintain at least 30 days of backups
4. **Storage:** Use separate physical/network storage

### System Restore Points
1. **Creation Frequency:** Before major changes only (not daily)
2. **Retention:** Keep 2-3 recent points
3. **Purpose:** Quick rollback for configuration changes
4. **Limitation:** Not a replacement for full backups

### Disaster Recovery Testing
- **Monthly:** Verify backup completion
- **Quarterly:** Test file restore
- **Annually:** Test full system recovery

---

## Troubleshooting

### Issue: Windows Server Backup not installed
```powershell
# Install the feature
Install-WindowsFeature Windows-Server-Backup
```

### Issue: Cannot create restore point (frequency limit)
**Error:** "A restore point cannot be created because one was already created within 24 hours"

**Solution:** Modify registry to allow more frequent restore points:
```powershell
# Set to 0 to allow unlimited frequency (use with caution)
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" `
    -Name "SystemRestorePointCreationFrequency" -Value 0
```

### Issue: Backup validation fails
**Causes:**
- Backup storage disconnected or full
- Corrupted backup files
- Permissions issues

**Solutions:**
- Verify backup target connectivity
- Check disk space on backup location
- Ensure backup service account has proper permissions

### Issue: Email reports not sending
**Check:**
- SMTP server reachability
- Firewall rules for SMTP (port 25)
- Email server authentication requirements

---

## Monitoring and Alerting

### Setup Automated Alerts
Create monitoring system for backup health:

1. **Daily Backup Verification:**
```powershell
.\Get-BackupStatus.ps1 -CheckDays 1 -AlertIfNoBackup -EmailReport -EmailTo "alerts@contoso.com"
```

2. **Integration with Monitoring Tools:**
- Export results to JSON for SIEM integration
- Use CSV exports for reporting dashboards
- Script exit codes for monitoring systems

### Alert Thresholds
- **Critical:** No backup in 2+ days
- **Warning:** No backup in 1 day
- **Info:** Backup older than 12 hours

---

## Disaster Recovery Planning

### Recovery Time Objective (RTO)
- Bare Metal Recovery: 4-6 hours
- File Restore: 15-30 minutes
- System State Restore: 1-2 hours

### Recovery Point Objective (RPO)
- Maximum data loss: 24 hours (daily backups)
- Recommended: 12 hours or less

### DR Checklist
- [ ] Backups configured and verified
- [ ] Backup storage separate from production
- [ ] Recovery procedures documented
- [ ] Recovery tested quarterly
- [ ] DR team trained
- [ ] Contact list updated

---

## Integration Examples

### With Group Policy Backups
```powershell
# Before GPO changes
.\Manage-RestorePoints.ps1 -Action Create -Description "Before GPO Update"
..\group-policy\Backup-GroupPolicies.ps1 -BackupPath "D:\GPO_Backups"

# Make changes
# ...

# Verify backup
.\Get-BackupStatus.ps1 -CheckDays 1
```

### With Active Directory
```powershell
# Before AD changes
.\Manage-RestorePoints.ps1 -Action Create -Description "Before AD Schema Update"

# Ensure recent AD backup
.\Get-BackupStatus.ps1 -CheckDays 1 -AlertIfNoBackup -ValidateBackups
```

---

## Additional Resources

- [Windows Server Backup Overview](https://docs.microsoft.com/en-us/windows-server/identity/ad-ds/manage/component-updates/ad-ds-operations)
- [System Restore Best Practices](https://docs.microsoft.com/en-us/windows/deployment/deploy-windows-mdt/windows-10-deployment-troubleshooting)
- [Disaster Recovery Planning](https://docs.microsoft.com/en-us/azure/site-recovery/site-recovery-overview)

---

*Last Updated: December 26, 2024*
