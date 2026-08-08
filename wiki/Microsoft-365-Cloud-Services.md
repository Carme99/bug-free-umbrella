# Microsoft 365 & Cloud Services

Comprehensive scripts for managing Microsoft 365 services including Azure AD, Exchange Online, SharePoint, OneDrive, Teams, Power Platform, and Microsoft Defender for Office 365. These scripts help automate administration and reporting across your Microsoft 365 tenant.

## Overview

The Microsoft 365 & Cloud Services category provides tools for:
- **Azure Active Directory** - User licensing, guest user audits, and organization settings
- **Exchange Online** - Mailbox health, mail flow analysis, and distribution list management
- **SharePoint & OneDrive** - Usage reports and regional settings configuration
- **Microsoft Teams** - Teams reporting and configuration
- **Power Platform** - Governance and regional settings for Power Apps/Automate
- **Microsoft Defender for Office 365** - Threat reporting and security analysis

All scripts are located in: `/scripts/collaboration/microsoft365/`

---

## Script Categories

### Azure Active Directory (Azure AD)
Manage users, licenses, and organizational settings.

| Script | Description | Location |
|--------|-------------|----------|
| **Get-AzureADLicenseReport.ps1** | Generate license assignment and consumption report | `scripts/collaboration/microsoft365/azure-ad/` |
| **Get-AzureADGuestAudit.ps1** | Audit external/guest user access | `scripts/collaboration/microsoft365/azure-ad/` |
| **Set-OrganizationDefaults.ps1** | Configure organization-wide default settings | `scripts/collaboration/microsoft365/azure-ad/` |
| **Set-UserLanguageSettings.ps1** | Set language and regional settings for users | `scripts/collaboration/microsoft365/azure-ad/` |

### Exchange Online
Manage mailboxes, mail flow, and distribution lists.

| Script | Description | Location |
|--------|-------------|----------|
| **Get-M365UserInfo.ps1** | 🆕 Interactive user management toolkit with comprehensive reporting | `scripts/collaboration/microsoft365/` |
| **Manage-QuarantinedEmails.ps1** | 🆕 Search and release quarantined emails for specific users | `scripts/collaboration/microsoft365/exchange-online/` |
| **Get-UserMailboxPermissions.ps1** | 🆕 Audit mailbox and folder-level permissions for users | `scripts/collaboration/microsoft365/exchange-online/` |
| **Get-UserMailRules.ps1** | 🆕 Investigate mail rules and forwarding for security audits | `scripts/collaboration/microsoft365/exchange-online/` |
| **Get-MailboxHealth.ps1** | Comprehensive mailbox health and usage report | `scripts/collaboration/microsoft365/exchange-online/` |
| **Get-MailFlowAnalysis.ps1** | Analyze mail flow patterns and issues | `scripts/collaboration/microsoft365/exchange-online/` |
| **Get-SharedMailboxReport.ps1** | Audit shared mailbox usage and permissions | `scripts/collaboration/microsoft365/exchange-online/` |
| **Get-DistributionListAudit.ps1** | Review distribution list membership and owners | `scripts/collaboration/microsoft365/exchange-online/` |
| **Set-MailboxRegionalSettings.ps1** | Configure mailbox language and time zone | `scripts/collaboration/microsoft365/exchange-online/` |

### SharePoint Online & OneDrive
Manage SharePoint sites and OneDrive storage.

| Script | Description | Location |
|--------|-------------|----------|
| **Get-OneDriveUsageReport.ps1** | OneDrive storage and activity report | `scripts/collaboration/microsoft365/sharepoint-onedrive/` |
| **Set-OneDriveRegionalSettings.ps1** | Configure OneDrive regional settings | `scripts/collaboration/microsoft365/sharepoint-onedrive/` |
| **Set-SiteRegionalSettings.ps1** | Set SharePoint site regional preferences | `scripts/collaboration/microsoft365/sharepoint-onedrive/` |

### Microsoft Teams
Manage Teams environments and reporting.

| Script | Description | Location |
|--------|-------------|----------|
| **Get-TeamsReport.ps1** | Teams usage and activity reporting | `scripts/collaboration/microsoft365/teams/` |
| **Set-TeamsRegionalSettings.ps1** | Configure Teams language and region settings | `scripts/collaboration/microsoft365/teams/` |

### Power Platform
Govern Power Apps, Power Automate, and Power BI.

| Script | Description | Location |
|--------|-------------|----------|
| **Get-PowerPlatformGovernance.ps1** | Audit Power Platform environments and apps | `scripts/collaboration/microsoft365/power-platform/` |
| **Set-PowerPlatformRegionalSettings.ps1** | Configure Power Platform regional settings | `scripts/collaboration/microsoft365/power-platform/` |

### Microsoft Defender for Office 365
Monitor email security and threats.

| Script | Description | Location |
|--------|-------------|----------|
| **Get-DefenderO365ThreatReport.ps1** | Generate threat detection and response report | `scripts/collaboration/microsoft365/defender-office365/` |

---

## Prerequisites

### Required Permissions
- **Global Administrator** or service-specific admin roles:
  - **Exchange Administrator** (for Exchange scripts)
  - **SharePoint Administrator** (for SharePoint/OneDrive scripts)
  - **Teams Administrator** (for Teams scripts)
  - **Power Platform Administrator** (for Power Platform scripts)
  - **Security Administrator** (for Defender scripts)

### Required Modules
```powershell
# Microsoft Graph (recommended for most operations)
Install-Module Microsoft.Graph -Scope CurrentUser -Force

# Exchange Online Management
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force

# SharePoint Online
Install-Module Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser -Force

# Microsoft Teams
Install-Module MicrosoftTeams -Scope CurrentUser -Force
```

> **Note**: The legacy `AzureAD` module was deprecated on March 30, 2024 and is not compatible with PowerShell 7. Use the Microsoft Graph PowerShell SDK (`Microsoft.Graph`) instead, as shown above.

### Connect to Services
```powershell
# Connect to Microsoft Graph
Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All", "Organization.Read.All"

# Connect to Exchange Online
Connect-ExchangeOnline -UserPrincipalName admin@company.com

# Connect to SharePoint Online
Connect-SPOService -Url https://company-admin.sharepoint.com

# Connect to Microsoft Teams
Connect-MicrosoftTeams
```

### License Requirements
- **Microsoft 365 E3/E5** or **Business Premium**
- **Exchange Online** licenses for mailbox scripts
- **Microsoft Defender for Office 365** for security scripts
- **Power Apps/Automate** licenses for Power Platform scripts

---

## Common Use Cases

### 1. Azure AD License Management

Generate comprehensive reports on license assignments and identify optimization opportunities.

**Basic License Report:**
```powershell
# Get all license assignments
.\Get-AzureADLicenseReport.ps1

# Export to CSV for analysis
.\Get-AzureADLicenseReport.ps1 -ExportCSV

# Include disabled users
.\Get-AzureADLicenseReport.ps1 -IncludeDisabled -ExportHTML
```

**Advanced License Analysis:**
```powershell
# Generate detailed license report with recommendations
.\Get-AzureADLicenseReport.ps1 -Detailed -IncludeUnused -ExportBoth

# Find users with multiple licenses
.\Get-AzureADLicenseReport.ps1 -FindDuplicates -ExportCSV

# Calculate license costs
.\Get-AzureADLicenseReport.ps1 -IncludeCosts -ExportHTML
```

**Sample Output:**
```
=== Azure AD License Report ===
Generated: 2025-12-31 10:00:00
Total Users: 1,500

License Summary:
┌────────────────────────────┬──────────┬──────────┬───────────┬────────────┐
│ License Type               │ Assigned │ Available│ Total     │ Cost/Month │
├────────────────────────────┼──────────┼──────────┼───────────┼────────────┤
│ Microsoft 365 E5           │ 250      │ 50       │ 300       │ $9,000     │
│ Microsoft 365 E3           │ 800      │ 100      │ 900       │ $18,000    │
│ Microsoft 365 Business     │ 400      │ 25       │ 425       │ $8,500     │
│ Exchange Online Plan 1     │ 50       │ 0        │ 50        │ $400       │
└────────────────────────────┴──────────┴──────────┴───────────┴────────────┘

Optimization Opportunities:
1. 75 unused licenses detected (potential savings: $1,650/month)
2. 12 disabled users still have licenses assigned
3. 18 users have duplicate license assignments

Recommendations:
- Reclaim 12 licenses from disabled users
- Investigate 75 unused licenses (users may not need all features)
- Review duplicate assignments for cost optimization
```

### 2. Guest User Auditing

Monitor external user access and ensure guest access compliance.

```powershell
# Audit all guest users
.\Get-AzureADGuestAudit.ps1

# Find inactive guests (not signed in for 90 days)
.\Get-AzureADGuestAudit.ps1 -InactiveDays 90

# Export detailed guest report
.\Get-AzureADGuestAudit.ps1 -IncludePermissions -IncludeGroups -ExportHTML

# Find guests with admin privileges
.\Get-AzureADGuestAudit.ps1 -AdminOnly -ExportCSV
```

**Sample Output:**
```
=== Azure AD Guest User Audit ===
Total Guest Users: 234
Active (last 30 days): 189
Inactive (90+ days): 45

Guest User Risk Assessment:
High Risk (Admin access): 2
Medium Risk (Member of 5+ groups): 18
Low Risk: 214

Inactive Guests Needing Review:
User: guest.user@partner.com
Last Sign-In: 2025-09-15 (108 days ago)
Groups: 3 (Marketing, External Vendors, Project Alpha)
Recommendation: Review access and remove if no longer needed

Guests with Admin Privileges:
1. contractor@vendor.com - Global Administrator
   WARNING: External user has admin access!
2. consultant@partner.com - SharePoint Administrator
   Last Sign-In: 2025-12-29 (2 days ago)
```

### 3. Mailbox Health Monitoring

Analyze mailbox health, quota usage, and identify potential issues.

**Basic Mailbox Health Check:**
```powershell
# Check all user mailboxes
.\Get-MailboxHealth.ps1

# Check shared mailboxes
.\Get-MailboxHealth.ps1 -MailboxType SharedMailbox

# Include archive mailbox statistics
.\Get-MailboxHealth.ps1 -IncludeArchive -ExportHTML
```

**Advanced Mailbox Analysis:**
```powershell
# Comprehensive health check with permissions
.\Get-MailboxHealth.ps1 -MailboxType All `
                        -IncludeArchive `
                        -IncludePermissions `
                        -QuotaWarningThreshold 90 `
                        -InactivityDays 180 `
                        -ExportHTML

# Find mailboxes approaching quota
.\Get-MailboxHealth.ps1 -QuotaWarningThreshold 85 -ExportCSV

# Identify inactive mailboxes
.\Get-MailboxHealth.ps1 -InactivityDays 90 -ExportHTML
```

**Sample Output:**
```
=== Exchange Online Mailbox Health Report ===
Total Mailboxes: 1,500
User Mailboxes: 1,450
Shared Mailboxes: 50

Quota Analysis:
┌─────────────────┬───────┬─────────┬──────────┬────────────┐
│ Status          │ Count │ Average │ Largest  │ % of Total │
├─────────────────┼───────┼─────────┼──────────┼────────────┤
│ Critical (>95%) │ 12    │ 49.2 GB │ 50 GB    │ 0.8%       │
│ Warning (>80%)  │ 87    │ 42.8 GB │ 49 GB    │ 5.8%       │
│ Healthy (<80%)  │ 1,401 │ 18.3 GB │ 39 GB    │ 93.4%      │
└─────────────────┴───────┴─────────┴──────────┴────────────┘

Mailboxes Requiring Attention:
1. john.doe@company.com
   Size: 49.8 GB / 50 GB (99.6% full)
   Items: 156,842
   Last Logon: 2025-12-30
   Action: Enable archive or increase quota

2. sales@company.com (Shared)
   Size: 48.2 GB / 50 GB (96.4% full)
   Delegates: 5 users
   Last Activity: 2025-12-31
   Action: Clean up old items or expand quota

Inactive Mailboxes (90+ days):
1. contractor@company.com - Last logon: 2025-08-15 (138 days)
2. temp.user@company.com - Last logon: 2025-07-22 (162 days)
   Recommendation: Review and consider disabling
```

### 4. User Management Toolkit (NEW in v3.3.0)

🆕 Comprehensive toolkit for managing individual user accounts with interactive menus and detailed reporting.

**Master Toolkit - Get-M365UserInfo.ps1:**
```powershell
# Interactive menu-driven user management
.\Get-M365UserInfo.ps1

# Auto-load specific user and run interactive menu
.\Get-M365UserInfo.ps1 -UserEmail "john.doe@company.com"

# Export comprehensive user report to HTML
.\Get-M365UserInfo.ps1 -UserEmail "john.doe@company.com" -ExportReport
```

**Features:**
- Comprehensive user information (Azure AD, mailbox, licenses, groups)
- Quarantine management (search and release quarantined emails)
- Permission auditing (mailbox, folder, Send As, Send on Behalf)
- Mail rules investigation (forwarding, inbox rules, suspicious patterns)
- HTML export with security protections (XSS-safe, path sanitization)
- Interactive menu for guided workflows

**Sample Output:**
```
=== M365 User Information ===
User: john.doe@company.com

[*] Azure AD Information
Display Name: John Doe
UPN: john.doe@company.com
Job Title: Senior Engineer
Department: IT
Account Status: Enabled
MFA Status: Enabled

[*] Mailbox Information
Mailbox Type: UserMailbox
Size: 15.8 GB / 50 GB (32%)
Item Count: 42,567
Archive Enabled: Yes
Archive Size: 8.2 GB

[*] License Assignments
  • Microsoft 365 E5
  • Power BI Pro

[*] Group Memberships (5 groups)
  • IT Department
  • Engineering Team
  • Office 365 Users
  • VPN Access
  • Admin Tools

[+] Data collection complete!
```

**Standalone Scripts:**

**Manage Quarantined Emails:**
```powershell
# Interactive quarantine management
.\Manage-QuarantinedEmails.ps1 -UserEmail "john.doe@company.com"

# Shows last 7 days of quarantined messages
# Allows viewing details and releasing messages
```

**Audit Mailbox Permissions:**
```powershell
# Basic permission audit
.\Get-UserMailboxPermissions.ps1 -UserEmail "john.doe@company.com"

# Include folder-level permissions and export report
.\Get-UserMailboxPermissions.ps1 -UserEmail "john.doe@company.com" `
                                  -IncludeFolderPermissions `
                                  -ExportReport
```

**Investigate Mail Rules:**
```powershell
# Check forwarding and rules
.\Get-UserMailRules.ps1 -UserEmail "john.doe@company.com"

# Include disabled rules and export report
.\Get-UserMailRules.ps1 -UserEmail "john.doe@company.com" `
                        -ShowDisabledRules `
                        -ExportReport
```

**Common Workflows:**

1. **User Can't Find Email:**
   ```powershell
   # Check quarantine first
   .\Manage-QuarantinedEmails.ps1 -UserEmail "user@company.com"

   # If not in quarantine, check rules
   .\Get-UserMailRules.ps1 -UserEmail "user@company.com"
   ```

2. **Security Audit - Unauthorized Access:**
   ```powershell
   # Check mailbox permissions
   .\Get-UserMailboxPermissions.ps1 -UserEmail "executive@company.com" `
                                     -IncludeFolderPermissions -ExportReport

   # Check for forwarding rules
   .\Get-UserMailRules.ps1 -UserEmail "executive@company.com" -ExportReport
   ```

3. **Comprehensive User Investigation:**
   ```powershell
   # Use master toolkit for complete analysis
   .\Get-M365UserInfo.ps1 -UserEmail "user@company.com" -ExportReport

   # Interactive menu provides access to:
   # - User details
   # - Quarantine search
   # - Permission auditing
   # - Mail rules investigation
   ```

### 5. Mail Flow Analysis

Analyze email traffic patterns, identify bottlenecks, and detect anomalies.

```powershell
# Analyze mail flow for last 7 days
.\Get-MailFlowAnalysis.ps1 -Days 7

# Detailed analysis with external domain tracking
.\Get-MailFlowAnalysis.ps1 -Days 30 -IncludeExternalDomains -ExportHTML

# Focus on failed/delayed messages
.\Get-MailFlowAnalysis.ps1 -Days 14 -OnlyFailures -ExportCSV
```

**Sample Output:**
```
=== Mail Flow Analysis ===
Period: Last 7 days (2025-12-24 to 2025-12-31)

Message Volume:
Total Messages: 45,623
Inbound: 28,942 (63.4%)
Outbound: 16,681 (36.6%)

Daily Average: 6,518 messages/day
Peak Day: 2025-12-27 (8,234 messages)

Message Status:
Delivered: 45,102 (98.9%)
Failed: 312 (0.7%)
Delayed: 209 (0.5%)

Top External Domains (Inbound):
1. gmail.com (5,234 messages)
2. outlook.com (3,892 messages)
3. partner.com (2,156 messages)

Failed Messages Analysis:
Top Failure Reasons:
1. Recipient not found (142 messages)
2. Mailbox full (89 messages)
3. Message rejected by spam filter (81 messages)

Recommendations:
- 142 messages to invalid recipients - update address lists
- 89 mailboxes full - expand quotas or enable archiving
```

### 6. Shared Mailbox Management

Audit shared mailbox usage, permissions, and identify security issues.

```powershell
# Basic shared mailbox report
.\Get-SharedMailboxReport.ps1

# Include permission details
.\Get-SharedMailboxReport.ps1 -IncludePermissions -ExportHTML

# Find unused shared mailboxes
.\Get-SharedMailboxReport.ps1 -InactiveDays 90 -ExportCSV

# Comprehensive audit
.\Get-SharedMailboxReport.ps1 -IncludePermissions `
                              -IncludeSize `
                              -IncludeActivity `
                              -ExportBoth
```

**Sample Output:**
```
=== Shared Mailbox Report ===
Total Shared Mailboxes: 45
Active (used in last 30 days): 38
Inactive (90+ days): 7

Shared Mailbox Details:

1. sales@company.com
   Size: 12.4 GB
   Items: 42,567
   Last Activity: 2025-12-31
   Delegates (Full Access):
     - sales.team@company.com
     - john.doe@company.com
     - jane.smith@company.com
   Send As Permissions:
     - sales.team@company.com
   Status: Healthy

2. oldproject@company.com
   Size: 2.1 GB
   Items: 8,234
   Last Activity: 2025-08-12 (141 days ago)
   Delegates: 0
   WARNING: Inactive shared mailbox with no delegates
   Recommendation: Review and consider deletion

Security Concerns:
- 3 shared mailboxes have excessive delegates (10+ users)
- 2 shared mailboxes have external delegates
- 7 inactive mailboxes should be reviewed
```

### 7. OneDrive Usage Reporting

Monitor OneDrive storage consumption and user activity.

```powershell
# Basic OneDrive usage report
.\Get-OneDriveUsageReport.ps1

# Include external sharing analysis
.\Get-OneDriveUsageReport.ps1 -IncludeSharing -ExportHTML

# Find users approaching storage limits
.\Get-OneDriveUsageReport.ps1 -QuotaThreshold 90 -ExportCSV

# Comprehensive usage report
.\Get-OneDriveUsageReport.ps1 -IncludeSharing `
                              -IncludeActivity `
                              -InactiveDays 180 `
                              -ExportBoth
```

**Sample Output:**
```
=== OneDrive Usage Report ===
Total Users: 1,500
OneDrive Enabled: 1,487
Total Storage Used: 18.7 TB
Average per User: 12.9 GB

Storage Distribution:
┌──────────────────┬───────┬─────────────┬────────────┐
│ Category         │ Users │ Total Size  │ % of Users │
├──────────────────┼───────┼─────────────┼────────────┤
│ Critical (>95%)  │ 23    │ 1.15 TB     │ 1.5%       │
│ High (>75%)      │ 145   │ 5.80 TB     │ 9.7%       │
│ Medium (>50%)    │ 412   │ 8.24 TB     │ 27.7%      │
│ Low (<50%)       │ 907   │ 3.51 TB     │ 61.0%      │
└──────────────────┴───────┴─────────────┴────────────┘

External Sharing Analysis:
Files Shared Externally: 2,345
Users Sharing Externally: 287
Anonymous Links: 156 (WARNING: Review anonymous sharing policy)

Top Storage Consumers:
1. john.doe@company.com - 98 GB (98% of quota)
2. design.team@company.com - 95 GB (95% of quota)
3. video.editor@company.com - 89 GB (89% of quota)

Inactive OneDrive Accounts (180+ days):
1. former.employee@company.com - 45 GB (Last active: 2025-05-12)
   Recommendation: Backup and remove
```

### 8. Microsoft Teams Reporting

Generate usage reports and monitor Teams adoption.

```powershell
# Basic Teams usage report
.\Get-TeamsReport.ps1

# Detailed team activity report
.\Get-TeamsReport.ps1 -IncludeActivity -Days 30 -ExportHTML

# Find inactive teams
.\Get-TeamsReport.ps1 -InactiveDays 90 -ExportCSV

# Comprehensive Teams audit
.\Get-TeamsReport.ps1 -IncludeActivity `
                      -IncludeMembers `
                      -IncludeChannels `
                      -ExportBoth
```

### 9. Power Platform Governance

Audit Power Apps, Power Automate flows, and environments for compliance.

```powershell
# Basic Power Platform audit
.\Get-PowerPlatformGovernance.ps1

# Include all environments and apps
.\Get-PowerPlatformGovernance.ps1 -AllEnvironments -ExportHTML

# Find apps with external connections
.\Get-PowerPlatformGovernance.ps1 -IncludeConnections -ExportCSV

# Comprehensive governance report
.\Get-PowerPlatformGovernance.ps1 -AllEnvironments `
                                  -IncludeConnections `
                                  -IncludeFlows `
                                  -ExportBoth
```

**Sample Output:**
```
=== Power Platform Governance Report ===
Total Environments: 12
Production: 2
Sandbox: 7
Developer: 3

Power Apps Summary:
Total Apps: 234
Canvas Apps: 198
Model-Driven Apps: 36

App Status:
Published: 187
Draft: 47

Power Automate Flows:
Total Flows: 456
Running: 398
Stopped: 58

Security Concerns:
1. 12 apps shared with "Everyone"
2. 8 flows using unmanaged connections
3. 23 apps not updated in 180+ days

Recommendations:
- Review apps shared with "Everyone" for data exposure
- Update 8 flows to use managed connections
- Archive 23 inactive apps
```

### 10. Microsoft Defender for Office 365 Threat Reporting

Monitor email threats and security incidents.

```powershell
# Get threat report for last 7 days
.\Get-DefenderO365ThreatReport.ps1 -Days 7

# Detailed threat analysis
.\Get-DefenderO365ThreatReport.ps1 -Days 30 -IncludeDetails -ExportHTML

# Focus on specific threat types
.\Get-DefenderO365ThreatReport.ps1 -ThreatType Phish -Days 14 -ExportCSV
```

**Sample Output:**
```
=== Microsoft Defender for Office 365 Threat Report ===
Period: Last 7 days

Threat Summary:
Total Threats Detected: 1,247
Malware: 89 (7.1%)
Phishing: 456 (36.6%)
Spam: 702 (56.3%)

Threats Blocked: 1,238 (99.3%)
Threats Delivered (false negative): 9 (0.7%)

Top Threat Sources (IP Addresses):
1. 203.0.113.45 (89 messages) - Blacklisted
2. 198.51.100.12 (67 messages) - Suspicious
3. 192.0.2.78 (54 messages) - Known phishing source

Top Targeted Users:
1. ceo@company.com (45 phishing attempts)
2. finance@company.com (38 phishing attempts)
3. hr@company.com (34 phishing attempts)

Recent Security Incidents:
1. 2025-12-30 14:23 - Credential phishing email
   Target: 15 users
   Status: Blocked and quarantined
   Action: Users notified via security awareness email

Recommendations:
- Increase security training for CEO and finance team
- Consider implementing additional email authentication (DMARC)
- Review and update Safe Links policies
```

---

## Script Examples

### Example 1: Monthly Microsoft 365 Health Check

Comprehensive monthly health check across all M365 services.

```powershell
# Monthly M365 Health Check
$ReportDate = Get-Date -Format "yyyy-MM"
$ReportPath = "C:\Reports\M365\Monthly\$ReportDate"
New-Item -Path $ReportPath -ItemType Directory -Force

Write-Host "=== Monthly Microsoft 365 Health Check ===" -ForegroundColor Cyan
Write-Host "Date: $(Get-Date)`n" -ForegroundColor White

# Connect to all services
Write-Host "Connecting to Microsoft 365 services..." -ForegroundColor Yellow
Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All"
Connect-ExchangeOnline
Connect-SPOService -Url https://company-admin.sharepoint.com
Connect-MicrosoftTeams

# 1. Azure AD License Report
Write-Host "`n[1/7] Generating license report..." -ForegroundColor Yellow
.\Get-AzureADLicenseReport.ps1 -Detailed -IncludeUnused -ExportBoth -OutputPath $ReportPath

# 2. Guest User Audit
Write-Host "[2/7] Auditing guest users..." -ForegroundColor Yellow
.\Get-AzureADGuestAudit.ps1 -InactiveDays 90 -IncludePermissions -ExportHTML -OutputPath $ReportPath

# 3. Mailbox Health
Write-Host "[3/7] Checking mailbox health..." -ForegroundColor Yellow
.\Get-MailboxHealth.ps1 -MailboxType All -IncludeArchive -QuotaWarningThreshold 85 -ExportHTML -OutputPath $ReportPath

# 4. Mail Flow Analysis
Write-Host "[4/7] Analyzing mail flow..." -ForegroundColor Yellow
.\Get-MailFlowAnalysis.ps1 -Days 30 -IncludeExternalDomains -ExportHTML -OutputPath $ReportPath

# 5. Shared Mailbox Report
Write-Host "[5/7] Auditing shared mailboxes..." -ForegroundColor Yellow
.\Get-SharedMailboxReport.ps1 -IncludePermissions -InactiveDays 90 -ExportCSV -OutputPath $ReportPath

# 6. OneDrive Usage
Write-Host "[6/7] Checking OneDrive usage..." -ForegroundColor Yellow
.\Get-OneDriveUsageReport.ps1 -IncludeSharing -QuotaThreshold 90 -ExportHTML -OutputPath $ReportPath

# 7. Teams Activity
Write-Host "[7/7] Generating Teams report..." -ForegroundColor Yellow
.\Get-TeamsReport.ps1 -IncludeActivity -Days 30 -ExportHTML -OutputPath $ReportPath

Write-Host "`n=== Health Check Complete ===" -ForegroundColor Green
Write-Host "Reports saved to: $ReportPath" -ForegroundColor Cyan

# Disconnect
Disconnect-MgGraph
Disconnect-ExchangeOnline -Confirm:$false
Disconnect-SPOService
Disconnect-MicrosoftTeams
```

### Example 2: License Optimization Campaign

Identify and reclaim unused licenses to reduce costs.

```powershell
# License Optimization Campaign
$OutputPath = "C:\Reports\LicenseOptimization"
New-Item -Path $OutputPath -ItemType Directory -Force

Write-Host "=== License Optimization Campaign ===" -ForegroundColor Cyan

# Step 1: Generate comprehensive license report
Write-Host "`n[1/4] Analyzing license assignments..." -ForegroundColor Yellow
$LicenseReport = .\Get-AzureADLicenseReport.ps1 -Detailed `
                                                 -IncludeUnused `
                                                 -IncludeCosts `
                                                 -ExportBoth `
                                                 -OutputPath $OutputPath

# Step 2: Identify disabled users with licenses
Write-Host "[2/4] Finding disabled users with licenses..." -ForegroundColor Yellow
$DisabledUsers = Get-MgUser -Filter "accountEnabled eq false" -All |
    Where-Object { $_.AssignedLicenses.Count -gt 0 }

Write-Host "  Found $($DisabledUsers.Count) disabled users with licenses" -ForegroundColor Yellow

# Step 3: Calculate potential savings
$PotentialSavings = $LicenseReport.UnusedLicenseCost +
                   ($DisabledUsers.Count * $LicenseReport.AverageLicenseCost)

Write-Host "`n[3/4] Optimization Opportunities:" -ForegroundColor Yellow
Write-Host "  Unused licenses: $($LicenseReport.UnusedCount)" -ForegroundColor White
Write-Host "  Disabled users with licenses: $($DisabledUsers.Count)" -ForegroundColor White
Write-Host "  Potential monthly savings: `$$PotentialSavings" -ForegroundColor Green

# Step 4: Generate action plan
Write-Host "`n[4/4] Generating action plan..." -ForegroundColor Yellow
$ActionPlan = @"
License Optimization Action Plan
Generated: $(Get-Date)

Immediate Actions:
1. Remove licenses from $($DisabledUsers.Count) disabled users
   Savings: `$$($DisabledUsers.Count * $LicenseReport.AverageLicenseCost)/month

2. Review $($LicenseReport.UnusedCount) unused licenses
   Potential Savings: `$$($LicenseReport.UnusedLicenseCost)/month

3. Audit users with multiple licenses ($($LicenseReport.DuplicateCount) users)
   Review for necessary features vs. cost

Total Potential Savings: `$$PotentialSavings/month (`$$($PotentialSavings * 12)/year)

Next Steps:
- Review disabled users list and confirm license removal
- Survey users with unused features
- Consolidate duplicate license assignments
- Implement monthly license usage review
"@

$ActionPlan | Out-File "$OutputPath\ActionPlan.txt"
Write-Host $ActionPlan
Write-Host "`nAction plan saved to: $OutputPath\ActionPlan.txt" -ForegroundColor Cyan
```

---

## Best Practices

### License Management
1. **Monthly reviews** - Review license assignments monthly for optimization
2. **Automated cleanup** - Remove licenses from disabled users automatically
3. **Right-sizing** - Assign appropriate licenses based on actual feature usage
4. **Track costs** - Monitor license costs and identify savings opportunities
5. **Grace periods** - Allow 30-day grace period before removing licenses from inactive users

### Security & Compliance
1. **Guest access reviews** - Audit external users quarterly
2. **Shared mailbox audits** - Review shared mailbox permissions monthly
3. **External sharing** - Monitor and restrict external sharing where appropriate
4. **Threat monitoring** - Review Defender reports weekly during initial setup
5. **MFA enforcement** - Ensure all users have multi-factor authentication enabled

### Performance & Storage
1. **Quota monitoring** - Alert when mailboxes reach 85% capacity
2. **Archive policies** - Implement auto-archiving for mailboxes approaching limits
3. **OneDrive cleanup** - Educate users on storage management
4. **Inactive account management** - Archive or delete accounts after 180 days of inactivity

---

## Troubleshooting

### Common Issues

**Connection failures to Exchange Online:**
```powershell
# Clear cached credentials
Disconnect-ExchangeOnline -Confirm:$false

# Reconnect with explicit credentials
Connect-ExchangeOnline -UserPrincipalName admin@company.com -ShowBanner:$false

# Verify connection
Get-OrganizationConfig | Select-Object Name
```

**"Insufficient permissions" errors:**
- Verify you have appropriate admin role (Global Admin, Exchange Admin, etc.)
- Check that required API permissions are granted
- Wait 10-15 minutes after granting permissions for changes to propagate

**License report shows incorrect counts:**
- Refresh license cache: `Update-MgUser -UserId "user@company.com"`
- Re-sync license assignment: Wait 24 hours for full synchronization
- Verify against Azure AD portal for accuracy

**Mail flow analysis returns no data:**
- Ensure you have sufficient Exchange administrator permissions
- Check message trace is enabled in your tenant
- Verify date range (message trace limited to 10 days by default)

---

## 💻 Quick Start Examples

### Example 1: User Information Lookup
```powershell
# Interactive user management
.\Get-M365UserInfo.ps1 -Interactive

# Specific user with all details
.\Get-M365UserInfo.ps1 -UserPrincipalName "user@company.com" -IncludeAllDetails
```

### Example 2: Mailbox Permission Audit
```powershell
# Check mailbox permissions
.\Get-UserMailboxPermissions.ps1 -UserPrincipalName "executive@company.com" -ExportHTML

# Find all delegated mailboxes
.\Get-UserMailboxPermissions.ps1 -FindAllDelegated
```

### Example 3: Quarantined Email Management
```powershell
# List quarantined emails (last 7 days)
.\Manage-QuarantinedEmails.ps1 -Days 7 -Action List

# Release specific email
.\Manage-QuarantinedEmails.ps1 -MessageId "abc123" -Action Release
```

---

## Related Resources

### Internal Documentation
- **[Prerequisites](Prerequisites)** - Required modules and permissions
- **[Security & Compliance](Security-Compliance)** - Security auditing scripts
- **[Intune Management](Intune-Management)** - Device management scripts
- **[FAQ](FAQ)** - Common questions and answers

### External Resources
- **[Microsoft 365 Admin Center](https://admin.microsoft.com)** - M365 administration portal
- **[Exchange Admin Center](https://admin.exchange.microsoft.com)** - Exchange Online management
- **[SharePoint Admin Center](https://admin.microsoft.com/sharepoint)** - SharePoint and OneDrive
- **[Teams Admin Center](https://admin.teams.microsoft.com)** - Microsoft Teams management
- **[Power Platform Admin Center](https://admin.powerplatform.microsoft.com)** - Power Apps/Automate/BI

---

**Last Updated:** 2026-01-05
**Version:** 1.1.0
