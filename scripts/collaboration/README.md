# Collaboration & Communication Scripts

Microsoft 365, Exchange, and communication platform management.

## Categories

### Microsoft 365 (`microsoft365/`)
- **azure-ad/** - Azure AD/Entra ID management
- **defender-office365/** - Microsoft Defender for Office 365
- **exchange-online/** - Exchange Online management
- **power-platform/** - Power Platform automation
- **sharepoint-onedrive/** - SharePoint and OneDrive
- **teams/** - Microsoft Teams management

### Email (`email/`)
- **exchange-server/** - On-premises Exchange Server

## Common Use Cases

- Manage Microsoft 365 licenses
- Monitor Exchange Online health
- Audit Azure AD guest users
- Manage Teams channels and settings
- SharePoint site administration
- Power Platform environment management

## Prerequisites

**Microsoft 365 Scripts:**
```powershell
Install-Module -Name Microsoft.Graph
Install-Module -Name ExchangeOnlineManagement
```

**Exchange Server Scripts:**
- Exchange Management Shell
- Administrator privileges

## Quick Start

**M365 License Report:**
```powershell
.\microsoft365\Get-M365LicenseReport.ps1
```

**Exchange Online Health:**
```powershell
.\microsoft365\exchange-online\Monitor-ExchangeOnlineHealth.ps1
```

**Azure AD Guest Audit:**
```powershell
.\microsoft365\azure-ad\Get-AzureADGuestAudit.ps1
```

**Teams Activity:**
```powershell
.\microsoft365\teams\Get-TeamsChannelActivity.ps1
```

## Microsoft 365 Services

| Service | Scripts Available | Common Tasks |
|---------|-------------------|--------------|
| **Azure AD** | User management, guest auditing | Identity governance |
| **Exchange Online** | Health monitoring, mailbox management | Email administration |
| **Teams** | Channel activity, settings | Collaboration management |
| **SharePoint** | Site management, OneDrive | Document management |
| **Power Platform** | Environment management | Low-code automation |

## Related Domains

- [Endpoints](../endpoints/) - Intune device management
- [Security](../security/) - Microsoft 365 security
- [Data](../data/) - API management

---

**[← Back to Scripts](../)**
