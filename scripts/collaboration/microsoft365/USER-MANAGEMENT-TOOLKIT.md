# M365 User Management Toolkit

A comprehensive suite of PowerShell scripts designed for technicians to quickly troubleshoot and manage individual Microsoft 365 user accounts.

## 🎯 Overview

This toolkit provides a **user-centric approach** to M365 management, allowing technicians to input a user's email address and perform various operations:

- **Quick diagnostics** - View all user information in one place
- **Permission auditing** - Check mailbox access and delegates
- **Mail flow troubleshooting** - Investigate forwarding rules and inbox rules
- **Quarantine management** - Release quarantined emails for users
- **License verification** - Check assigned licenses and service plans
- **Security auditing** - Identify unauthorized forwarding or suspicious rules

## 📦 What's Included

### 1. Get-M365UserInfo.ps1 (Master Toolkit)

**The Swiss Army knife for user troubleshooting.**

Interactive menu-driven tool that consolidates all user information in one interface.

```powershell
.\Get-M365UserInfo.ps1 -UserEmail "john.doe@contoso.com" -AutoConnect
```

**Features:**
- ✅ User account verification and basic information
- ✅ Mailbox statistics (size, quota, items)
- ✅ License assignments and service plans
- ✅ Quarantine check (last 7 days)
- ✅ Sign-in activity and last logon
- ✅ Group and distribution list memberships
- ✅ Mobile device associations
- ✅ Interactive menu for detailed operations
- ✅ Quick view mode for rapid assessment
- ✅ HTML report generation

**Interactive Menu Options:**
1. View Mailbox Statistics
2. View License Assignments
3. Check Quarantined Emails
4. View Group Memberships
5. View Mobile Devices
6. View Sign-In Activity
7. Show User Summary
8. Generate Full Report (HTML)
9. Check Another User
0. Exit

**Quick View Mode:**
```powershell
# Display summary without menu
.\Get-M365UserInfo.ps1 -UserEmail "john.doe@contoso.com" -QuickView
```

**Report Generation:**
```powershell
# Generate HTML report
.\Get-M365UserInfo.ps1 -UserEmail "john.doe@contoso.com" -ExportReport
```

---

### 2. Manage-QuarantinedEmails.ps1

**Interactive quarantine management for end users.**

Allow technicians to view and release quarantined emails on behalf of users.

```powershell
.\Manage-QuarantinedEmails.ps1 -UserEmail "john.doe@contoso.com" -AutoConnect
```

**Features:**
- Search quarantined messages (1-30 days)
- View detailed quarantine information (sender, subject, reason, policy)
- Select and release messages interactively
- Release to original or alternate recipient
- Auto-refresh list after release
- Support for all quarantine types (Spam, Phishing, Malware)

**Workflow:**
1. Enter user's email address
2. View quarantined messages in formatted table
3. Select message by number
4. Review detailed information
5. Release to recipient with confirmation
6. List automatically refreshes

**Use Cases:**
- False positive spam detection
- Urgent business emails caught by filters
- Phishing education (show user why it was quarantined)
- VIP user support

---

### 3. Get-UserMailboxPermissions.ps1

**Comprehensive mailbox permission audit.**

Identify who has access to a user's mailbox and what permissions they have.

```powershell
.\Get-UserMailboxPermissions.ps1 -UserEmail "john.doe@contoso.com"
```

**Features:**
- Full Access permissions (who can open the mailbox)
- Send As permissions (who can send as the user)
- Send on Behalf permissions
- Folder-level permissions (calendar, inbox, contacts, tasks)
- Auto-mapping status
- HTML export for documentation

**With Folder Permissions:**
```powershell
.\Get-UserMailboxPermissions.ps1 -UserEmail "john.doe@contoso.com" -IncludeFolderPermissions -ExportReport
```

**Security Use Cases:**
- Investigate unauthorized mailbox access
- Audit shared mailbox permissions
- Verify delegate access for executives
- Compliance documentation
- Troubleshoot calendar permission issues

---

### 4. Get-UserMailRules.ps1

**Mail rules and forwarding investigation.**

Detect unauthorized forwarding and troubleshoot mail flow issues.

```powershell
.\Get-UserMailRules.ps1 -UserEmail "john.doe@contoso.com"
```

**Features:**
- Mailbox-level forwarding (internal and external)
- Inbox rules (client-side rules)
- Forwarding rule detection and warnings
- Auto-reply/Out of Office status
- Rule priority and conditions
- Security warnings for suspicious rules
- HTML report with detailed analysis

**Security Warnings:**
- 🔴 External forwarding detected
- 🔴 Auto-delete rules found
- 🔴 Suspicious forwarding patterns

**Troubleshooting Use Cases:**
- "I'm not receiving certain emails"
- "My emails are going to the wrong folder"
- Security incident investigation
- Audit for unauthorized forwarding
- Verify Out of Office is working

**Include Disabled Rules:**
```powershell
.\Get-UserMailRules.ps1 -UserEmail "john.doe@contoso.com" -ShowDisabledRules -ExportReport
```

---

## 🚀 Quick Start

### Prerequisites

**PowerShell Modules:**
```powershell
# Exchange Online Management
Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser

# Microsoft Graph (for Azure AD operations)
Install-Module -Name Microsoft.Graph -Scope CurrentUser
```

**Required Permissions:**
- Exchange Administrator or Global Reader (for mailbox operations)
- User Administrator or Global Reader (for Azure AD operations)
- Quarantine role in Security & Compliance Center (for quarantine management)

### Connect to Services

**Exchange Online:**
```powershell
Connect-ExchangeOnline
```

**Microsoft Graph:**
```powershell
Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All", "Reports.Read.All"
```

**Or use AutoConnect:**
```powershell
# Scripts will connect automatically
.\Get-M365UserInfo.ps1 -AutoConnect
```

---

## 📋 Common Workflows

### Workflow 1: New Support Ticket - User Can't Find Email

```powershell
# Step 1: Quick user assessment
.\Get-M365UserInfo.ps1 -UserEmail "john.doe@contoso.com" -QuickView

# Step 2: Check for forwarding or rules
.\Get-UserMailRules.ps1 -UserEmail "john.doe@contoso.com"

# Step 3: Check quarantine
.\Manage-QuarantinedEmails.ps1 -UserEmail "john.doe@contoso.com"

# Step 4: Release if found in quarantine
```

**Result:** Email found in quarantine (spam filter), released to user. Ticket resolved.

---

### Workflow 2: Security Investigation - Potential Account Compromise

```powershell
# Step 1: Full user assessment
.\Get-M365UserInfo.ps1 -UserEmail "suspicious.user@contoso.com" -AutoConnect

# From menu, check:
# - Sign-in activity (option 6)
# - Mobile devices (option 5)

# Step 2: Check for unauthorized forwarding
.\Get-UserMailRules.ps1 -UserEmail "suspicious.user@contoso.com" -ExportReport

# Step 3: Check mailbox permissions
.\Get-UserMailboxPermissions.ps1 -UserEmail "suspicious.user@contoso.com" -ExportReport

# Step 4: Review licenses and group memberships
```

**Result:** Identified unauthorized external forwarding rule. Removed rule, reset password, revoked sessions.

---

### Workflow 3: VIP User - Urgent Email Needed

```powershell
# VIP executive needs urgent email that hasn't arrived

# Quick quarantine check
.\Manage-QuarantinedEmails.ps1 -UserEmail "ceo@contoso.com" -Days 1

# Select and release the urgent message
# VIP receives email immediately
```

**Result:** Email released from quarantine in under 2 minutes.

---

### Workflow 4: Mailbox Delegation Audit

```powershell
# Audit all shared mailbox permissions for compliance

$sharedMailboxes = Get-EXOMailbox -RecipientTypeDetails SharedMailbox

foreach ($mailbox in $sharedMailboxes) {
    .\Get-UserMailboxPermissions.ps1 -UserEmail $mailbox.PrimarySmtpAddress -ExportReport
}
```

**Result:** Compliance report generated for all shared mailboxes.

---

### Workflow 5: Monthly User Account Review

```powershell
# Generate comprehensive report for specific user

.\Get-M365UserInfo.ps1 -UserEmail "john.doe@contoso.com" -ExportReport
```

**Result:** HTML report with all user information for documentation.

---

## 🎓 Technician Training Guide

### For Help Desk Technicians

**Most Common Tasks:**

1. **Check why user can't receive email:**
   ```powershell
   .\Get-UserMailRules.ps1 -UserEmail "user@contoso.com"
   .\Manage-QuarantinedEmails.ps1 -UserEmail "user@contoso.com"
   ```

2. **Verify user account status:**
   ```powershell
   .\Get-M365UserInfo.ps1 -UserEmail "user@contoso.com" -QuickView
   ```

3. **Release quarantined email:**
   ```powershell
   .\Manage-QuarantinedEmails.ps1 -UserEmail "user@contoso.com"
   # Follow interactive prompts
   ```

### For System Administrators

**Advanced Operations:**

1. **Security audit for user:**
   ```powershell
   .\Get-UserMailRules.ps1 -UserEmail "user@contoso.com" -ExportReport
   .\Get-UserMailboxPermissions.ps1 -UserEmail "user@contoso.com" -IncludeFolderPermissions -ExportReport
   ```

2. **Comprehensive user assessment:**
   ```powershell
   .\Get-M365UserInfo.ps1 -UserEmail "user@contoso.com"
   # Use interactive menu for detailed investigation
   ```

---

## 🔍 Troubleshooting

### "Not connected to Exchange Online"

```powershell
# Check connection
Get-ConnectionInformation

# Reconnect
Connect-ExchangeOnline -ShowBanner:$false

# Or use AutoConnect parameter
.\Get-M365UserInfo.ps1 -AutoConnect
```

### "User not found"

- Verify email address is correct
- Check if user is licensed
- Ensure user has a mailbox (not just Azure AD account)

### "Insufficient permissions"

Required roles:
- **Exchange Administrator** or **Global Reader** for mailbox operations
- **Quarantine role** for quarantine management
- **User Administrator** for Azure AD operations

### Connection timeouts

```powershell
# Increase timeout (if experiencing slow connections)
$PSSessionOption = New-PSSessionOption -IdleTimeout 600000
```

---

## 📊 Output Examples

### User Summary
```
╔══════════════════════════════════════════════════════════════╗
║                      USER SUMMARY                            ║
╠══════════════════════════════════════════════════════════════╣
║ Display Name    : John Doe
║ Email (Primary) : john.doe@contoso.com
║ UPN             : john.doe@contoso.com
║ Job Title       : Senior Developer
║ Department      : Engineering
║ Mailbox Type    : UserMailbox
║ Account Status  : Enabled
║ Created         : 2023-01-15
╚══════════════════════════════════════════════════════════════╝
```

### Mailbox Statistics
```
╔══════════════════════════════════════════════════════════════╗
║                   MAILBOX STATISTICS                         ║
╠══════════════════════════════════════════════════════════════╣
║ Mailbox Size    : 23.45 GB
║ Quota           : 50 GB
║ Quota Used      : 47%
║ Item Count      : 45,231
║ Last Logon      : 2025-01-08 09:15:23
║ Archive Status  : Active
╚══════════════════════════════════════════════════════════════╝
```

### Security Warning Example
```
[!] WARNING: Found 1 active rule(s) with forwarding or deletion actions
[!] Review these rules for potential security concerns

  Rule: Forward to Personal Email
    Condition: From contains 'invoice'
    Action: Forward to personal@gmail.com ⚠️
```

---

## 🔐 Security Considerations

### Permission Model

These scripts follow the **principle of least privilege:**

- **Read-only operations** use Global Reader role
- **Quarantine release** requires Quarantine role
- **No modifications** to user accounts or settings (except quarantine release)

### Audit Trail

All operations are logged in Microsoft 365 audit logs:

```powershell
# View audit logs for user operations
Search-UnifiedAuditLog -UserIds "admin@contoso.com" -Operations "Release-QuarantineMessage"
```

### Sensitive Data

- Scripts do not display email content
- Personal information is only shown to authorized administrators
- Reports should be stored securely (contain PII)

---

## 📈 Best Practices

1. **Use QuickView for Initial Assessment**
   ```powershell
   .\Get-M365UserInfo.ps1 -UserEmail "user@contoso.com" -QuickView
   ```

2. **Generate Reports for Documentation**
   - Always export reports for security incidents
   - Keep reports for compliance audits

3. **Automate Repetitive Tasks**
   ```powershell
   # Check quarantine for multiple users
   $users = Get-Content .\vip-users.txt
   foreach ($user in $users) {
       .\Manage-QuarantinedEmails.ps1 -UserEmail $user
   }
   ```

4. **Schedule Regular Audits**
   - Weekly quarantine checks for VIP users
   - Monthly permission audits for shared mailboxes
   - Quarterly mail rule reviews

---

## 🔄 Integration Examples

### Task Scheduler

Create scheduled task to check VIP user quarantine daily:

```powershell
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-File C:\Scripts\Manage-QuarantinedEmails.ps1 -UserEmail ceo@contoso.com -QuickView"

$trigger = New-ScheduledTaskTrigger -Daily -At 8am

Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "VIP Quarantine Check"
```

### Email Notifications

Send report via email:

```powershell
$report = .\Get-M365UserInfo.ps1 -UserEmail "user@contoso.com" -ExportReport

Send-MailMessage -To "admin@contoso.com" `
    -Subject "User Report: user@contoso.com" `
    -Body "Attached is the user report" `
    -Attachments $report `
    -SmtpServer "smtp.office365.com"
```

---

## 🆕 What's Next

Planned enhancements:

- [ ] Reset user MFA methods
- [ ] View OneDrive storage details
- [ ] Check Teams membership and activity
- [ ] Mailbox calendar permissions management
- [ ] Litigation hold status
- [ ] eDiscovery hold information
- [ ] Bulk user operations

---

## 📚 Related Scripts

This toolkit complements existing M365 scripts:

- `Get-MailboxHealth.ps1` - Bulk mailbox health checks
- `Get-MailFlowAnalysis.ps1` - Organization-wide mail flow
- `Set-MailboxRegionalSettings.ps1` - User regional settings
- `Get-SharedMailboxReport.ps1` - Shared mailbox auditing

---

## 💡 Tips & Tricks

### Keyboard Shortcuts in Interactive Menu

- Press `1-9` to select menu options
- Press `0` to exit
- Press `9` to quickly switch to another user

### Quick Commands for Common Tasks

```powershell
# Aliases for faster typing
Set-Alias -Name m365user -Value Get-M365UserInfo.ps1
Set-Alias -Name quarantine -Value Manage-QuarantinedEmails.ps1
Set-Alias -Name mailrules -Value Get-UserMailRules.ps1

# Add to PowerShell profile
Add-Content $PROFILE @"
Set-Alias m365user C:\Scripts\Get-M365UserInfo.ps1
Set-Alias quarantine C:\Scripts\Manage-QuarantinedEmails.ps1
"@
```

### Batch Operations

```powershell
# Check quarantine for multiple users from CSV
$users = Import-Csv .\users.csv

foreach ($user in $users) {
    Write-Host "`n=== Checking $($user.Email) ===" -ForegroundColor Cyan
    .\Manage-QuarantinedEmails.ps1 -UserEmail $user.Email
}
```

---

**Version:** 1.0
**Last Updated:** 2025-01-08
**Author:** IT Operations
**License:** Internal Use Only
