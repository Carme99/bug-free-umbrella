# Device Management Scripts

This directory contains PowerShell scripts for general device configuration, inventory, and management tasks across Windows endpoints.

## Overview

Device management scripts provide tools for configuring, inventorying, and maintaining Windows workstations and endpoints. These complement Intune-specific scripts with general device administration capabilities.

## Common Use Cases

- **Device Inventory**: Hardware and software inventory collection
- **Configuration Management**: Apply device settings and configurations
- **Compliance Checking**: Verify device compliance with corporate standards
- **Troubleshooting**: Diagnostic and repair tools for endpoints
- **User Profile Management**: Profile cleanup and management

## Prerequisites

### PowerShell Version
- PowerShell 5.1+ (Windows 10/11)
- PowerShell 7+ recommended

### Permissions
- Local Administrator rights
- Appropriate domain permissions for AD-joined devices

## Quick Start

### 1. Device Inventory
```powershell
# Collect device inventory
.\Get-DeviceInventory.ps1

# Export to CSV
.\Get-DeviceInventory.ps1 -ExportCSV -OutputPath "C:\Inventory\"
```

### 2. Configuration Management
```powershell
# Apply standard configuration
.\Set-DeviceConfiguration.ps1

# Verify configuration compliance
.\Test-DeviceCompliance.ps1
```

### 3. Troubleshooting
```powershell
# Run device diagnostics
.\Test-DeviceHealth.ps1

# Collect diagnostic logs
.\Get-DeviceDiagnostics.ps1 -IncludeLogs
```

## Related Categories

- [Intune](../intune/) - Microsoft Intune endpoint management
- [Server](../server/) - Server management scripts
- [Security Compliance](../security-compliance/) - Compliance scanning

## Additional Resources

- [Docs: Proactive Remediations](../../../docs/Proactive-Remediations.md)
- [Examples: Device Management](../../examples/device-management/)

## Contributing

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines on adding new device management scripts.

## License

Apache License 2.0 - See [LICENSE](../../LICENSE) for details
