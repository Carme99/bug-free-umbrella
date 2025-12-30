# Infrastructure Management Scripts

On-premises and hybrid infrastructure administration.

## Categories

### Windows (`windows/`)
- **active-directory/** - AD management and automation
- **group-policy/** - GPO configuration
- **backup-recovery/** - Backup operations
- **monitoring/** - Server health monitoring
- **network/** - Network configuration
- **security/** - Security hardening
- **storage/** - Storage management
- **system/** - System administration
- **user-management/** - User provisioning

### Linux (`linux/`)
- **backup-recovery/** - Linux backup automation
- **monitoring/** - System health checks
- **network/** - Network diagnostics
- **security/** - Security configuration
- **system-health/** - Health monitoring
- **user-management/** - User administration

### Network (`network/`)
- Firewall management
- Network diagnostics and troubleshooting

### Virtualization (`virtualization/`)
- Hyper-V management
- VMware health monitoring

### Web (`web/`)
- **iis/** - IIS web server management

### Print (`print/`)
- Print server administration

## Common Use Cases

- Monitor Windows/Linux server health
- Manage Active Directory users and groups
- Configure and monitor IIS websites
- Hyper-V virtual machine management
- Network troubleshooting and diagnostics

## Prerequisites

**Windows Scripts:**
- PowerShell 5.1+ on Windows Server
- Administrator privileges
- WinRM enabled for remote management

**Linux Scripts:**
- PowerShell 7+ on Linux
- sudo privileges

## Quick Start

**Server Health Check:**
```powershell
.\windows\monitoring\Monitor-ServerHealth.ps1 -CheckAll
```

**Linux System Health:**
```powershell
pwsh .\linux\monitoring\Get-SystemHealth.ps1
```

**IIS Site Monitoring:**
```powershell
.\web\iis\Monitor-IISSites.ps1
```

## Related Domains

- [Security](../security/) - Security and compliance
- [Automation](../automation/) - Monitoring automation
- [Cloud](../cloud/) - Hybrid cloud integration

---

**[← Back to Scripts](../)**
