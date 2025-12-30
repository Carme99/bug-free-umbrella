# Active Directory Management Scripts

This directory contains scripts for Active Directory user auditing, service account management, and AD health monitoring.

## Scripts

### Get-ADUserAudit.ps1
Performs comprehensive audits of Active Directory user accounts for security and compliance.

**Features:**
- Identifies inactive accounts
- Finds accounts with passwords that never expire
- Detects privileged account memberships
- Lists recently created/modified accounts
- Identifies accounts that never logged in
- Finds locked out and expired accounts

**Usage:**
```powershell
# Basic user audit
.\Get-ADUserAudit.ps1 -OutputPath "C:\Reports"

# Audit with custom inactive threshold and privileged account check
.\Get-ADUserAudit.ps1 -InactiveDays 60 -CheckPrivilegedAccounts -ExportToCSV

# Include disabled accounts in audit
.\Get-ADUserAudit.ps1 -IncludeDisabledAccounts -CheckPrivilegedAccounts
```

**Audit Categories:**
- Inactive accounts (configurable threshold)
- Accounts never logged in (>30 days old)
- Passwords that never expire
- Locked out accounts
- Expired accounts
- Recently created accounts (last 30 days)
- Recently modified accounts
- Privileged group memberships

---

### Get-ServiceAccountAudit.ps1
Audits service accounts for security risks and compliance issues.

**Features:**
- Identifies service accounts by naming convention
- Finds accounts with Service Principal Names (SPNs)
- Detects privileged service accounts
- Checks password policies and age
- Analyzes Kerberos delegation settings
- Inventories Managed Service Accounts (MSA) and Group MSAs (gMSA)

**Usage:**
```powershell
# Basic service account audit
.\Get-ServiceAccountAudit.ps1 -OutputPath "C:\Reports"

# Comprehensive audit with SPN and delegation analysis
.\Get-ServiceAccountAudit.ps1 -IncludeSPNAnalysis -CheckKerberosDelegation -ExportToCSV
```

**Security Checks:**
- Service accounts in privileged groups (critical risk)
- Passwords never expire
- Passwords not required
- Password age >1 year
- Kerberos delegation (unconstrained/constrained)
- Accounts never logged in

**Recommendations Provided:**
- Migrate to Group Managed Service Accounts (gMSA)
- Remove from privileged groups
- Implement password rotation
- Review and minimize delegation

---

### Get-ADHealthCheck.ps1
Performs health checks on Active Directory domain controllers and domain configuration.

**Features:**
- Domain controller replication status
- FSMO role holder identification
- DNS configuration verification
- Domain and forest functional levels
- Trust relationship status
- GPO replication health

**Usage:**
```powershell
# Run comprehensive AD health check
.\Get-ADHealthCheck.ps1 -OutputPath "C:\Reports"
```

---

### Find-InactiveADComputers.ps1
Identifies and reports on inactive computer accounts in Active Directory.

**Features:**
- Finds computers not authenticated in X days
- Identifies stale computer accounts
- Detects disabled computer accounts
- Reports on computer object creation dates

**Usage:**
```powershell
# Find computers inactive for 90+ days
.\Find-InactiveADComputers.ps1 -InactiveDays 90 -OutputPath "C:\Reports"

# Export results for cleanup
.\Find-InactiveADComputers.ps1 -InactiveDays 60 -ExportToCSV
```

---

## Common Workflows

### 1. Monthly Security Audit
Perform regular security audits:
```powershell
# Audit user accounts
.\Get-ADUserAudit.ps1 -InactiveDays 90 -CheckPrivilegedAccounts -ExportToCSV -OutputPath "C:\Audits\$(Get-Date -Format 'yyyyMM')"

# Audit service accounts
.\Get-ServiceAccountAudit.ps1 -IncludeSPNAnalysis -CheckKerberosDelegation -ExportToCSV -OutputPath "C:\Audits\$(Get-Date -Format 'yyyyMM')"

# Check AD health
.\Get-ADHealthCheck.ps1 -OutputPath "C:\Audits\$(Get-Date -Format 'yyyyMM')"
```

### 2. Compliance Reporting
Generate compliance reports for auditors:
```powershell
# Comprehensive user audit with privileged account focus
.\Get-ADUserAudit.ps1 -CheckPrivilegedAccounts -IncludeDisabledAccounts -ExportToCSV

# Service account security audit
.\Get-ServiceAccountAudit.ps1 -IncludeSPNAnalysis -CheckKerberosDelegation -ExportToCSV
```

### 3. Account Cleanup
Identify accounts for cleanup:
```powershell
# Find inactive users
.\Get-ADUserAudit.ps1 -InactiveDays 180 -ExportToCSV

# Find inactive computers
.\Find-InactiveADComputers.ps1 -InactiveDays 180 -ExportToCSV

# Review CSV outputs and disable/delete as appropriate
```

### 4. Privileged Access Review
Quarterly privileged access audits:
```powershell
# Audit all privileged user accounts
.\Get-ADUserAudit.ps1 -CheckPrivilegedAccounts -ExportToCSV

# Check for service accounts with excessive privileges
.\Get-ServiceAccountAudit.ps1 -CheckKerberosDelegation -ExportToCSV

# Review results:
# - Remove unnecessary privileged access
# - Document and approve remaining privileged accounts
# - Ensure MFA enabled for privileged accounts
```

### 5. Service Account Migration
Migrate to Group Managed Service Accounts:
```powershell
# Step 1: Audit current service accounts
.\Get-ServiceAccountAudit.ps1 -IncludeSPNAnalysis -ExportToCSV

# Step 2: Review standard service accounts vs. gMSAs
# Step 3: Plan migration of standard accounts to gMSAs
# Step 4: Create gMSAs and migrate applications
# Step 5: Run audit again to verify migration
```

---

## Security Best Practices

### User Account Management
1. **Password Policies:**
   - No passwords set to never expire (except break-glass accounts)
   - Maximum password age: 90 days
   - Complex passwords required

2. **Inactive Accounts:**
   - Disable after 90 days of inactivity
   - Delete after 180 days (after backup)
   - Exception process for temporary inactivity

3. **Privileged Accounts:**
   - Dedicated admin accounts (no everyday use)
   - MFA required for privileged access
   - Regular access review (quarterly)
   - Privileged Access Workstation (PAW) for Domain Admins

### Service Account Management
1. **Prefer gMSAs:**
   - Automatic password management
   - No password expiration issues
   - Improved security

2. **Standard Service Accounts:**
   - Complex 25+ character passwords
   - Change passwords annually minimum
   - Never use privileged accounts
   - Document purpose and owner

3. **Kerberos Delegation:**
   - Minimize unconstrained delegation
   - Use constrained delegation when needed
   - Regular audit of delegation settings

---

## Compliance Mapping

### Common Frameworks

**SOC 2:**
- User access reviews (quarterly)
- Privileged access monitoring
- Inactive account removal
- Service account inventory

**HIPAA:**
- Access control reviews
- User authentication auditing
- Privileged access logging
- Account lifecycle management

**PCI-DSS:**
- User access reviews (quarterly)
- Privileged account management
- Inactive account deactivation (90 days)
- Service account controls

**NIST 800-53:**
- AC-2: Account Management
- IA-4: Identifier Management
- IA-5: Authenticator Management
- AC-6: Least Privilege

---

## Troubleshooting

### Issue: Cannot query AD users
**Solution:** Ensure ActiveDirectory PowerShell module is installed and you have appropriate permissions.
```powershell
Import-Module ActiveDirectory
```

### Issue: "Access Denied" errors
**Solution:** Run scripts with an account that has:
- Domain Admin rights (for full audit), OR
- Account Operators (for user audits), OR
- Delegated permissions to read AD objects

### Issue: Slow performance on large domains
**Solution:**
- Use `-Username` parameter to audit specific users
- Schedule audits during off-peak hours
- Export to CSV and analyze offline

### Issue: Missing service accounts in audit
**Cause:** Non-standard naming conventions

**Solution:** Modify the `$serviceAccountPatterns` array in Get-ServiceAccountAudit.ps1:
```powershell
$serviceAccountPatterns = @(
    "svc*",
    "*service*",
    "sa_*",
    # Add your custom patterns here
    "app_*",
    "*_app"
)
```

---

## Automation Examples

### Scheduled Monthly Audit
```powershell
# Create scheduled task for monthly audit
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-File C:\Scripts\Get-ADUserAudit.ps1 -CheckPrivilegedAccounts -ExportToCSV -OutputPath C:\Audits\$(Get-Date -Format 'yyyyMM')"

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "6:00AM" -WeeksInterval 4

Register-ScheduledTask -TaskName "Monthly AD User Audit" -Trigger $trigger -Action $action -RunLevel Highest
```

### Email Alert for Excessive Privileged Accounts
```powershell
# Run audit and email if issues found
$audit = .\Get-ADUserAudit.ps1 -CheckPrivilegedAccounts -ExportToCSV

if ((Import-Csv $audit.CSVPath).Count -gt 50) {
    Send-MailMessage -To "security@contoso.com" `
        -Subject "Alert: High number of privileged accounts" `
        -Body "Review required: $($audit.CSVPath)" `
        -SmtpServer "mail.contoso.com"
}
```

---

## Integration with Other Scripts

### With Group Policy Management
```powershell
# Before GPO changes affecting users
.\Get-ADUserAudit.ps1 -ExportToCSV

# Make GPO changes
..\group-policy\Backup-GroupPolicies.ps1 -BackupPath "D:\Backups"

# Verify no unexpected account changes
.\Get-ADUserAudit.ps1 -ExportToCSV
```

### With Backup Scripts
```powershell
# Before major AD cleanup
..\backup-recovery\Manage-RestorePoints.ps1 -Action Create -Description "Before AD cleanup"

# Identify accounts to remove
.\Get-ADUserAudit.ps1 -InactiveDays 180 -ExportToCSV

# Disable/delete accounts (manual step)
# ...

# Verify changes
.\Get-ADUserAudit.ps1 -IncludeDisabledAccounts -ExportToCSV
```

---

## Additional Resources

- [Active Directory Security Best Practices](https://docs.microsoft.com/en-us/windows-server/identity/ad-ds/plan/security-best-practices)
- [Securing Privileged Access](https://docs.microsoft.com/en-us/windows-server/identity/securing-privileged-access/securing-privileged-access)
- [Group Managed Service Accounts](https://docs.microsoft.com/en-us/windows-server/security/group-managed-service-accounts/group-managed-service-accounts-overview)
- [AD Account Cleanup Guidance](https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-R2-and-2012/hh831702(v=ws.11))

---
