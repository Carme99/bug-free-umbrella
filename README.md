# Bug-Free Umbrella

A comprehensive collection of PowerShell scripts for Windows system administration, Intune management, and automated device maintenance.

## Quick Links

- **[Full Documentation](docs/README.md)** - Complete guide to all scripts and usage
- **[Intune Sync Guide](docs/INTUNE-SYNC-README.md)** - User group to device group synchronization
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## Repository Structure

```
bug-free-umbrella/
├── docs/                              # Documentation
├── scripts/
│   ├── intune/                        # Intune management tools
│   ├── server/                        # Server management tools
│   ├── device-management/             # Device management scripts
│   │   ├── autopatch/                 # Windows Update policies
│   │   ├── winget-updates/            # Application update scripts
│   │   ├── bitlocker-backup/          # BitLocker key backup
│   │   ├── device-uptime/             # Uptime monitoring
│   │   ├── l16-driver-block/          # Lenovo L16 driver management
│   │   ├── adobe-rum/                 # Adobe Remote Update Manager
│   │   └── remove-sccm/               # SCCM client removal
│   └── utilities/                     # Standalone utilities
├── templates/                         # Reusable script templates
└── LICENSE
```

## Quick Start

### Intune Management
```powershell
# Check BitLocker status across devices
.\scripts\intune\Get-BitLockerStatus.ps1

# Find stale devices
.\scripts\intune\Find-StaleDevices.ps1
```

### Server Administration
```powershell
# Generate disk health report
.\scripts\server\Get-DiskReport.ps1

# Reset Windows Update components
.\scripts\server\Reset-WindowsUpdate.ps1
```

### Device Management
```powershell
# Sync user group to device group
.\scripts\utilities\Sync-UserGroupToPrimaryDeviceGroup.ps1
```

## Requirements

- PowerShell 5.1 or later
- Administrator privileges for most scripts
- Microsoft Graph PowerShell SDK for Intune scripts

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.
