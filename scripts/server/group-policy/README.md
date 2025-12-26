# Group Policy Management Scripts

This directory contains scripts for managing, auditing, and maintaining Active Directory Group Policy Objects (GPOs).

## Scripts

### Get-GPOReport.ps1
Generates comprehensive Group Policy Object reports for domain analysis.

**Features:**
- Exports all GPO configurations to HTML/XML
- Identifies unlinked and empty GPOs
- Detects disabled GPOs
- Creates searchable index of all policies
- Highlights potential issues

**Usage:**
```powershell
# Generate both HTML and XML reports
.\Get-GPOReport.ps1 -OutputPath "C:\GPOReports"

# Include unlinked GPOs and export CSV summary
.\Get-GPOReport.ps1 -OutputPath "C:\GPOReports" -IncludeUnlinkedGPOs -ExportToCSV
```

**Requirements:**
- GroupPolicy PowerShell module
- Domain Admin or equivalent permissions

---

### Backup-GroupPolicies.ps1
Creates complete backups of all Group Policy Objects with versioning and retention management.

**Features:**
- Backs up all GPOs or specific GPO by name
- Includes GPO settings, permissions, and WMI filters
- Automated retention and cleanup
- Optional compression
- Detailed backup logs and manifests

**Usage:**
```powershell
# Backup all GPOs
.\Backup-GroupPolicies.ps1 -BackupPath "D:\GPO_Backups"

# Backup with comment and compression
.\Backup-GroupPolicies.ps1 -BackupPath "D:\GPO_Backups" -Comment "Pre-migration backup" -CompressBackup

# Backup specific GPO
.\Backup-GroupPolicies.ps1 -BackupPath "D:\GPO_Backups" -GPOName "Corporate Security Policy"
```

**Best Practices:**
- Schedule regular automated backups
- Store backups on separate storage
- Test restore procedures periodically
- Document backup locations

---

### Find-GPOConflicts.ps1
Identifies potential Group Policy conflicts and configuration issues.

**Features:**
- Detects duplicate or conflicting settings
- Identifies disabled configurations
- Checks security filtering issues
- Analyzes inheritance blocking
- Reports on loopback processing
- Finds empty linked GPOs

**Usage:**
```powershell
# Basic conflict analysis
.\Find-GPOConflicts.ps1 -OutputPath "C:\Reports"

# Analyze specific OU with inheritance
.\Find-GPOConflicts.ps1 -Scope OU -TargetOU "OU=Workstations,DC=contoso,DC=com" -IncludeInheritance
```

**Common Issues Detected:**
- Multiple GPOs with same name
- Loopback processing conflicts
- Security filtering misconfiguration
- Empty GPOs consuming resources
- Inheritance blocking problems

---

## Common Workflows

### 1. Pre-Change GPO Backup
Before making significant GPO changes:
```powershell
# Create timestamped backup with description
.\Backup-GroupPolicies.ps1 -BackupPath "D:\GPO_Backups" -Comment "Before AD migration" -CompressBackup
```

### 2. GPO Audit and Documentation
Generate complete GPO documentation:
```powershell
# Step 1: Generate detailed reports
.\Get-GPOReport.ps1 -OutputPath "C:\GPO_Documentation" -ExportToCSV

# Step 2: Check for conflicts
.\Find-GPOConflicts.ps1 -OutputPath "C:\GPO_Documentation" -IncludeInheritance
```

### 3. GPO Cleanup
Identify and clean up unused GPOs:
```powershell
# Find unlinked and empty GPOs
.\Get-GPOReport.ps1 -IncludeUnlinkedGPOs -IncludeEmptyGPOs -ExportToCSV

# Review the CSV output and delete unused GPOs manually
```

### 4. Regular Maintenance
Schedule these tasks monthly:
```powershell
# Backup GPOs
.\Backup-GroupPolicies.ps1 -BackupPath "D:\GPO_Backups" -RetentionDays 90

# Generate reports
.\Get-GPOReport.ps1 -OutputPath "C:\Monthly_Reports\GPO_$(Get-Date -Format 'yyyyMM')"

# Check for conflicts
.\Find-GPOConflicts.ps1 -OutputPath "C:\Monthly_Reports\GPO_$(Get-Date -Format 'yyyyMM')"
```

---

## Troubleshooting

### Issue: GPO report generation fails
**Solution:** Ensure you have read access to all GPOs and the GroupPolicy module is installed.

### Issue: Backup fails for specific GPOs
**Solution:** Check permissions on the GPO and ensure you have Domain Admin rights.

### Issue: Conflict detection shows false positives
**Solution:** Review the specific conflicts - some may be intentional (e.g., enforced vs. non-enforced GPOs).

---

## Security Considerations

- **Backup Security:** Store GPO backups in a secure location with appropriate access controls
- **Sensitive Data:** GPO backups may contain passwords and sensitive configurations
- **Audit Access:** Log all GPO backup and restore operations
- **Retention:** Follow your organization's data retention policies

---

## Integration with Other Tools

### Intune Migration
Before migrating from GPO to Intune:
1. Run Get-GPOReport.ps1 to document all policies
2. Create backup with Backup-GroupPolicies.ps1
3. Use reports to map GPO settings to Intune policies

### Disaster Recovery
Include GPO backups in your disaster recovery plan:
1. Automated daily backups with retention
2. Off-site backup storage
3. Documented restore procedures
4. Regular restore testing

---

## Additional Resources

- [Group Policy Overview](https://docs.microsoft.com/en-us/windows-server/identity/ad-ds/manage/group-policy)
- [Group Policy Best Practices](https://docs.microsoft.com/en-us/windows-server/identity/ad-ds/plan/security-best-practices)
- [GPO Backup and Restore](https://docs.microsoft.com/en-us/powershell/module/grouppolicy/)

---

*Last Updated: 2025-12-25*
