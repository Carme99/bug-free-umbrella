# Microsoft 365 Management Scripts


> **⚠️ IMPORTANT NOTICE**: The vast majority of scripts in this repository have not been thoroughly tested in production environments. Please test all scripts in a non-production environment first and validate the results before relying on this data for operational decisions.

Enterprise-grade PowerShell scripts for comprehensive Microsoft 365 cloud service management.

## 📋 Overview

This category provides cloud-based management tools for Microsoft 365 services including Exchange Online, Microsoft Teams, SharePoint/OneDrive, and Azure AD (Entra ID). These scripts complement the existing Intune management tools to provide complete M365 administration.

## 🏗️ Structure

```
m365/
├── exchange-online/        # Exchange Online mailbox and mail flow management
├── teams/                  # Microsoft Teams administration
├── sharepoint-onedrive/    # SharePoint and OneDrive management
├── azure-ad/               # Azure AD / Entra ID user and license management
├── power-platform/         # Power Platform governance and compliance (NEW!)
├── defender-office365/     # Microsoft Defender for Office 365 threat reporting (NEW!)
└── purview-compliance/     # Microsoft Purview compliance management (NEW!)
```

## 🔧 Scripts by Category

### 🆕 Power Platform (2 scripts)

#### Set-PowerPlatformRegionalSettings.ps1
Power Platform environment regional settings management.

**Features:**
- Environment base language configuration
- Currency format settings
- Multi-environment support
- Regional settings audit

**Usage:**
```powershell
# Audit specific environment
.\Set-PowerPlatformRegionalSettings.ps1 -EnvironmentName "Default-xxxxx" -AuditOnly

# Audit all environments
.\Set-PowerPlatformRegionalSettings.ps1 -AllEnvironments -AuditOnly -ExportHTML
```

**Note:** Power Platform regional settings are set at environment creation time and cannot be changed post-creation without recreating the environment.

#### Get-PowerPlatformGovernance.ps1
Comprehensive Power Platform governance and compliance reporting.

**Features:**
- Power Apps inventory and ownership tracking
- Power Automate flow monitoring and status
- Connector usage and DLP compliance
- Environment capacity and licensing
- Orphaned apps and flows detection
- Guest maker access auditing
- Premium license usage tracking

**Usage:**
```powershell
Connect-AzAccount
.\Get-PowerPlatformGovernance.ps1 -TenantId "your-tenant-id" -IncludeAppDetails

# Full governance scan
.\Get-PowerPlatformGovernance.ps1 -TenantId "your-tenant-id" `
    -IncludeAppDetails `
    -IncludeFlowDetails `
    -CheckDLPCompliance `
    -OutputFormat HTML
```

---

### 🆕 Defender for Office 365 (1 script)

#### Get-DefenderO365ThreatReport.ps1
Microsoft Defender for Office 365 threat analysis and reporting.

**Features:**
- Phishing and malware detection tracking
- Safe Links click analysis
- Safe Attachments detonation reports
- Anti-spam verdict trends
- User risk analysis based on targeting frequency
- Top threat senders identification
- Geographic threat distribution

**Usage:**
```powershell
Connect-IPPSSession
.\Get-DefenderO365ThreatReport.ps1 -DaysToAnalyze 30

# Detailed threat analysis
.\Get-DefenderO365ThreatReport.ps1 -DaysToAnalyze 7 `
    -IncludeDetailedThreats `
    -IncludeUserRiskAnalysis `
    -OutputFormat HTML
```

---

### Exchange Online (3 scripts)

#### Set-MailboxRegionalSettings.ps1
Exchange Online mailbox regional and calendar settings management.

**Features:**
- Mailbox time zone configuration
- Date/time format settings
- Work week and work hours
- Language for Outlook Web App
- Calendar preferences
- Bulk remediation support

**Usage:**
```powershell
# Audit current user
.\Set-MailboxRegionalSettings.ps1 -AuditOnly

# Apply settings to specific user
.\Set-MailboxRegionalSettings.ps1 -UserPrincipalName john.doe@company.com -Apply

# Audit all mailboxes with HTML report
.\Set-MailboxRegionalSettings.ps1 -AllMailboxes -AuditOnly -ExportHTML

# Apply to all mailboxes
.\Set-MailboxRegionalSettings.ps1 -AllMailboxes -Apply
```

#### Get-MailboxHealth.ps1
Comprehensive Exchange Online mailbox health and usage analysis.

**Features:**
- Mailbox size and quota monitoring
- Archive mailbox status
- Litigation hold tracking
- Permission auditing
- Inactive mailbox detection
- Quota violation alerts

**Usage:**
```powershell
# Basic health check
.\Get-MailboxHealth.ps1

# Shared mailboxes with permissions
.\Get-MailboxHealth.ps1 -MailboxType SharedMailbox -IncludePermissions -ExportHTML

# Check for quota issues
.\Get-MailboxHealth.ps1 -QuotaWarningThreshold 90 -InactivityDays 180
```

#### Get-SharedMailboxReport.ps1
Shared mailbox audit for usage, permissions, and compliance.

**Features:**
- Permission analysis (Full Access, Send As, Send on Behalf)
- Sign-in status verification
- Inactive shared mailbox detection
- Shared mailboxes without owners

**Usage:**
```powershell
# Basic audit
.\Get-SharedMailboxReport.ps1

# Comprehensive audit
.\Get-SharedMailboxReport.ps1 -IncludePermissions -CheckInactive -ExportHTML
```

---

### Microsoft Teams (2 scripts)

#### Set-TeamsRegionalSettings.ps1
Microsoft Teams regional settings configuration guide.

**Features:**
- Teams inherits settings from M365 user and Exchange mailbox
- Guidance on configuring Teams regional preferences
- References to related configuration scripts

**Usage:**
```powershell
# View Teams regional settings guidance
.\Set-TeamsRegionalSettings.ps1
```

**Note:** Teams primarily inherits regional settings from Exchange Online and M365 user settings. Use Set-MailboxRegionalSettings.ps1 and Set-UserLanguageSettings.ps1 for comprehensive control.

#### Get-TeamsReport.ps1
Microsoft Teams usage and compliance reporting.

**Features:**
- Team count and membership statistics
- Guest user access monitoring
- Channel analysis
- Teams without owners detection
- Privacy settings audit
- Archived teams tracking

**Usage:**
```powershell
# Basic report
.\Get-TeamsReport.ps1

# Comprehensive audit
.\Get-TeamsReport.ps1 -IncludeGuests -CheckOwnership -ExportHTML
```

---

### SharePoint / OneDrive (3 scripts)

#### Set-SiteRegionalSettings.ps1
SharePoint site collection regional settings management.

**Features:**
- Site time zone configuration
- Locale settings (affects date/number formatting)
- Calendar type and format
- Work week configuration
- Bulk site remediation
- HTML/CSV reporting

**Usage:**
```powershell
# Audit specific site
.\Set-SiteRegionalSettings.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/TeamSite" -AuditOnly

# Apply to specific site
.\Set-SiteRegionalSettings.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/TeamSite" -Apply

# Audit all sites with report
.\Set-SiteRegionalSettings.ps1 -AllSites -AuditOnly -ExportHTML

# Apply to all sites
.\Set-SiteRegionalSettings.ps1 -AllSites -Apply
```

#### Set-OneDriveRegionalSettings.ps1
OneDrive for Business personal site regional settings.

**Features:**
- OneDrive time zone configuration
- Locale settings for personal sites
- User-specific OneDrive configuration
- Bulk OneDrive remediation

**Usage:**
```powershell
# Audit specific user's OneDrive
.\Set-OneDriveRegionalSettings.ps1 -UserPrincipalName john.doe@company.com -AuditOnly

# Apply to specific user
.\Set-OneDriveRegionalSettings.ps1 -UserPrincipalName john.doe@company.com -Apply

# Audit all OneDrive sites
.\Set-OneDriveRegionalSettings.ps1 -AllOneDriveSites -AuditOnly
```

#### Get-OneDriveUsageReport.ps1
OneDrive for Business usage and storage analysis.

**Features:**
- Storage usage per user
- Quota monitoring and warnings
- Inactive OneDrive sites
- File count statistics
- External sharing tracking

**Usage:**
```powershell
# Basic usage report
.\Get-OneDriveUsageReport.ps1

# Custom thresholds
.\Get-OneDriveUsageReport.ps1 -StorageWarningThreshold 90 -InactivityDays 180 -ExportHTML
```

---

### Azure AD / Entra ID (4 scripts)

#### Set-OrganizationDefaults.ps1
Organization-wide default settings for new M365 users.

**Features:**
- Tenant-wide default usage location
- Default preferred language
- Affects newly created users
- Organization settings audit

**Usage:**
```powershell
# Audit organization defaults
.\Set-OrganizationDefaults.ps1 -AuditOnly

# Apply organization defaults
.\Set-OrganizationDefaults.ps1 -Apply
```

**Note:** This configures defaults for NEW users only. Existing users must be configured with Set-UserLanguageSettings.ps1

#### Set-UserLanguageSettings.ps1
Audits and configures M365 user language and region settings.

**Features:**
- Display language configuration (en-GB)
- Preferred language settings
- Regional format configuration
- Time zone settings (GMT Standard Time)
- Audit mode for compliance checking
- Bulk user remediation
- Single user or all users support

**Usage:**
```powershell
# Audit current user settings
.\Set-UserLanguageSettings.ps1 -AuditOnly

# Apply settings to current user
.\Set-UserLanguageSettings.ps1 -Apply

# Audit specific user
.\Set-UserLanguageSettings.ps1 -UserPrincipalName john.doe@company.com -AuditOnly

# Apply to specific user
.\Set-UserLanguageSettings.ps1 -UserPrincipalName john.doe@company.com -Apply

# Audit all users with HTML report
.\Set-UserLanguageSettings.ps1 -AllUsers -AuditOnly -ExportHTML

# Apply settings to all users (bulk remediation)
.\Set-UserLanguageSettings.ps1 -AllUsers -Apply
```

#### Get-AzureADGuestAudit.ps1
Guest user security and compliance audit.

**Features:**
- Guest user inventory
- Inactive guest detection
- Privileged guest identification (security risk)
- Domain analysis
- Guest permission tracking

**Usage:**
```powershell
# Basic guest audit
.\Get-AzureADGuestAudit.ps1

# Comprehensive security audit
.\Get-AzureADGuestAudit.ps1 -CheckPrivilegedGuests -GroupByDomain -ExportHTML
```

#### Get-AzureADLicenseReport.ps1
Microsoft 365 license assignment and usage reporting.

**Features:**
- License consumption by SKU
- Unused license identification
- Cost optimization opportunities
- Unlicensed user detection
- Service plan details

**Usage:**
```powershell
# Basic license report
.\Get-AzureADLicenseReport.ps1

# Comprehensive audit
.\Get-AzureADLicenseReport.ps1 -IncludeServicePlans -IdentifyUnassigned -ExportHTML
```

---

## 📊 Common Use Cases

### Monthly M365 Audit
```powershell
# Exchange Online
cd m365\exchange-online
.\Get-MailboxHealth.ps1 -QuotaWarningThreshold 80 -ExportHTML
.\Get-SharedMailboxReport.ps1 -IncludePermissions -CheckInactive -ExportHTML

# Teams
cd ..\teams
.\Get-TeamsReport.ps1 -IncludeGuests -CheckOwnership -ExportHTML

# OneDrive
cd ..\sharepoint-onedrive
.\Get-OneDriveUsageReport.ps1 -StorageWarningThreshold 85 -ExportHTML

# Azure AD
cd ..\azure-ad
.\Get-AzureADGuestAudit.ps1 -CheckPrivilegedGuests -ExportHTML
.\Get-AzureADLicenseReport.ps1 -IdentifyUnassigned -ExportHTML
.\Set-UserLanguageSettings.ps1 -AllUsers -AuditOnly -ExportHTML
```

### Security Compliance Check
```powershell
# Check for security risks
.\Get-SharedMailboxReport.ps1  # Sign-in enabled on shared mailboxes
.\Get-AzureADGuestAudit.ps1 -CheckPrivilegedGuests  # Guest admins
.\Get-TeamsReport.ps1 -IncludeGuests  # External collaboration
```

### Cost Optimization
```powershell
# Identify savings opportunities
.\Get-AzureADLicenseReport.ps1 -IdentifyUnassigned  # Unused licenses
.\Get-MailboxHealth.ps1 -InactivityDays 180  # Inactive mailboxes
.\Get-OneDriveUsageReport.ps1  # Storage usage
```

## 🎯 Prerequisites

### Required PowerShell Modules

**Exchange Online:**
```powershell
Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser
```

**Microsoft Teams:**
```powershell
Install-Module -Name MicrosoftTeams -Scope CurrentUser
```

**Microsoft Graph (for Azure AD, SharePoint, OneDrive):**
```powershell
Install-Module -Name Microsoft.Graph -Scope CurrentUser
```

**SharePoint Online:**
```powershell
Install-Module -Name Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser
```

### Required Permissions

| Service | Required Roles | Graph API Permissions |
|---------|---------------|----------------------|
| Exchange Online | Exchange Administrator, Global Reader | - |
| Microsoft Teams | Teams Administrator, Global Reader | - |
| Azure AD | User Administrator, Global Reader | User.Read.All, Directory.Read.All |
| SharePoint/OneDrive | SharePoint Administrator | Reports.Read.All |
| Licensing | License Administrator, Global Reader | Organization.Read.All |

## 🔐 Authentication

All scripts use modern authentication with the respective PowerShell modules:

**Exchange Online:**
```powershell
Connect-ExchangeOnline
```

**Microsoft Teams:**
```powershell
Connect-MicrosoftTeams
```

**Microsoft Graph:**
```powershell
Connect-MgGraph -Scopes "User.Read.All","Directory.Read.All"
```

## 📈 Output Examples

### Mailbox Health
```
=== Exchange Online Mailbox Health Report ===

Total Mailboxes: 245
Quota Warnings (>80%): 12
Quota Exceeded: 3
Inactive (>90 days): 8

=== Mailboxes Requiring Attention ===
Name                    Size(GB)  Quota(GB)  Used%   Status
----                    --------  ---------  -----   ------
John Doe               48.5      50         97%     Warning
Jane Smith             50.1      50         100%    Critical
```

### Guest User Audit
```
=== Azure AD Guest User Audit ===

Total Guest Users: 127
Inactive Guests (>90 days): 23
Never Signed In: 15
Privileged Guests (CRITICAL): 2

=== Privileged Guest Users ===
Display Name            Email                      Roles
------------            -----                      -----
External Admin          admin@partner.com          Global Administrator
```

### License Report
```
=== Microsoft 365 License Report ===

Total Licenses Purchased: 500
Total Licenses Assigned: 456
Total Unused Licenses: 44

License Name              Purchased  Assigned  Unused  Usage%
------------              ---------  --------  ------  ------
Microsoft 365 E3         400        385       15      96%
Microsoft 365 E5         100        71        29      71%
```

## 🔍 Troubleshooting

### Connection Issues
```powershell
# Check if connected to Exchange Online
Get-ConnectionInformation

# Reconnect if needed
Connect-ExchangeOnline -ShowBanner:$false
```

### Module Not Found
```powershell
# List installed modules
Get-Module -ListAvailable | Where-Object {$_.Name -like "*Exchange*" -or $_.Name -like "*Teams*" -or $_.Name -like "*Graph*"}

# Install missing modules
Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser
```

### Permission Denied
Ensure you have the required administrator roles:
- Exchange Administrator for mailbox operations
- Teams Administrator for Teams management
- User Administrator or Global Reader for Azure AD
- SharePoint Administrator for OneDrive/SharePoint

## 📝 Best Practices

1. **Regular Auditing**
   - Run reports monthly for compliance
   - Track trends over time
   - Export to CSV for historical analysis

2. **Security Focus**
   - Always check for privileged guest users
   - Monitor sign-in enabled shared mailboxes
   - Review external access in Teams

3. **Cost Optimization**
   - Identify unused licenses monthly
   - Remove inactive mailboxes
   - Clean up inactive OneDrive sites

4. **Automation**
   - Schedule reports via Task Scheduler
   - Email reports to management
   - Integrate with monitoring systems

## 🚀 Future Enhancements

Planned additions:
- SharePoint site collection audit
- Teams governance policies
- Mail flow analysis
- Conditional Access policy reporting
- Azure AD sign-in logs analysis
- DLP policy compliance

## 📚 Additional Resources

- [Exchange Online PowerShell](https://docs.microsoft.com/powershell/exchange/exchange-online-powershell)
- [Microsoft Teams PowerShell](https://docs.microsoft.com/microsoftteams/teams-powershell-overview)
- [Microsoft Graph PowerShell SDK](https://docs.microsoft.com/graph/powershell/get-started)
- [SharePoint Online Management Shell](https://docs.microsoft.com/powershell/sharepoint/sharepoint-online/introduction-sharepoint-online-management-shell)

---

**Version**: 2.0
**Last Updated**: 2025
**Total Scripts**: 14

## 🤖 Development

Scripts in this repository were created with the assistance of **[Claude Code](https://github.com/anthropics/claude-code)**, Anthropic's official CLI for Claude AI.

---
