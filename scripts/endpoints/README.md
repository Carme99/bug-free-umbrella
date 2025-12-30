# Endpoint & Device Management Scripts

Modern endpoint management for Intune and Windows devices.

## Categories

### Intune (`intune/`)
- **deployment/** - Application deployment scripts
- **maintenance/** - Device maintenance automation
- **reporting/** - Compliance and status reporting

### Devices (`devices/`)
- **proactive-remediations/** - Auto-detect and fix common issues (14 pairs)
- **winget/** - Windows Package Manager automation (40+ apps)
- **autopatch/** - Windows Update automation (V1-V5)
- **bitlocker/** - BitLocker key backup and compliance
- **drivers/** - Driver management and blocking
- **adobe-rum/** - Adobe Runtime Update Manager
- **uptime/** - Device uptime monitoring
- **sccm/** - SCCM removal automation

## Common Use Cases

- Deploy applications via Intune
- Auto-remediate common device issues
- Manage BitLocker encryption compliance
- Automate Windows updates
- Install/update applications via Winget

## Prerequisites

**Intune Scripts:**
```powershell
Install-Module -Name Microsoft.Graph.Intune
Install-Module -Name Microsoft.Graph
```

**Device Scripts:**
- Administrator privileges
- PowerShell 5.1+ (7+ recommended)

## Quick Start

**Check Intune Compliance:**
```powershell
.\intune\reporting\Get-IntuneDeviceCompliance.ps1
```

**Deploy Proactive Remediation:**
```powershell
# Upload detect/remediate pair to Intune
.\devices\proactive-remediations\Fix-DiskSpace\detect.ps1
.\devices\proactive-remediations\Fix-DiskSpace\remediate.ps1
```

**Install App via Winget:**
```powershell
.\devices\winget\productivity\MicrosoftTeams\detect.ps1
.\devices\winget\productivity\MicrosoftTeams\remediate.ps1
```

## Related Domains

- [Collaboration](../collaboration/) - Microsoft 365 management
- [Security](../security/) - Compliance and hardening

---

**[← Back to Scripts](../)**
