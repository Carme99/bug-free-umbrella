# API Reference

[![Tier 3](https://img.shields.io/badge/Documentation-Tier%203-blue)]()
[![Reference](https://img.shields.io/badge/Type-Reference-informational)]()
[![API](https://img.shields.io/badge/Category-API-blue)]()

## Table of Contents

- [Overview](#overview)
- [Core Functions](#core-functions)
- [Integration Modules](#integration-modules)
- [Utility Functions](#utility-functions)
- [Data Types](#data-types)
- [Error Codes](#error-codes)
- [Version Compatibility](#version-compatibility)

## Overview

This reference documents available functions and modules in Bug-Free Umbrella. Functions are provided as individual scripts in the `scripts/` directory organized by category (cloud, infrastructure, automation, security, etc.) rather than as a monolithic module.

> **Note:** Not all functions listed here are provided as a single cohesive API module. Each category has dedicated scripts. Import specific scripts as needed for your use case.

## Core Functions

### Get-SystemInfo

```
GET-SYSTEMINFORM ATION

SYNOPSIS
Retrieve comprehensive system information.

SYNTAX
Get-SystemInfo [[-ComputerName] <string>] [-IncludeNetwork] [-IncludeStorage] [<CommonParameters>]

PARAMETERS
-ComputerName <string>
    Target computer name. Default: localhost
    Required: False
    Default value: localhost

-IncludeNetwork
    Include network adapter information
    Required: False
    Default value: False

-IncludeStorage
    Include storage information
    Required: False
    Default value: False

EXAMPLES
Get-SystemInfo -ComputerName "Server1" -IncludeNetwork -IncludeStorage

RETURN VALUE
PSCustomObject with properties:
  - ComputerName: string
  - OSVersion: string
  - CPUCount: int
  - RAM: long (bytes)
  - NetworkAdapters: object[] (if -IncludeNetwork)
  - Disks: object[] (if -IncludeStorage)
```

### Invoke-Command (Native PowerShell)

For remote script execution, use the native PowerShell `Invoke-Command` cmdlet instead of a custom function:

```powershell
Invoke-Command -ComputerName $server -FilePath $scriptPath `
    -ArgumentList $args -ErrorAction Stop
```

See [Remote Execution Patterns](Advanced-Scripting-Patterns.md) for examples and best practices.

## Available Script Categories

Bug-Free Umbrella provides scripts organized in the following categories:

### Cloud Platforms

**Azure Scripts:** `/scripts/cloud/azure/`
- AVD (Azure Virtual Desktop) management
- Compute resources (VMs, galleries)
- Core operations (health, resource monitoring)
- Key Vault operations
- API Management

**AWS Scripts:** `/scripts/cloud/aws/`
- Resource inventory
- EC2 management
- S3 operations
- Cost optimization

### Infrastructure & Monitoring

**Windows Infrastructure:** `/scripts/infrastructure/windows/`
- Server health monitoring
- Performance metrics
- System diagnostics

**Network Operations:** `/scripts/infrastructure/network/`
- DNS management
- Network diagnostics

### Collaboration & Microsoft 365

**Microsoft 365 Scripts:** `/scripts/collaboration/microsoft365/`
- Azure AD management
- User information retrieval
- Mailbox operations
- License reporting

### Security & Compliance

**Security Scripts:** `/scripts/security/`
- Vulnerability scanning
- Compliance auditing
- Access management

### Data & API

**API Management:** `/scripts/data/api/`
- Azure API Management monitoring
- API health checks

**Database Operations:** `/scripts/data/databases/`
- SQL Server management
- Database maintenance

## Utility Functions

### Creating PSCredential Objects

Use the native PowerShell `New-Object` cmdlet or `Get-Credential` for secure credential handling:

```powershell
# Interactive prompt (recommended)
$cred = Get-Credential

# Programmatic creation (only with SecureString)
$securePassword = ConvertTo-SecureString -String "Password" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("username", $securePassword)
```

⚠️ **Security Note:** Never hardcode plaintext passwords in scripts. Use:
- Azure Key Vault
- Windows Credential Manager
- Certificate-based authentication
- Managed Identity (Azure)
- Environment variables (for CI/CD)

## Data Types

### ExecutionResult

```powershell
class ExecutionResult {
    [string]$Id
    [bool]$Success
    [object]$Data
    [string]$Error
    [TimeSpan]$Duration
    [DateTime]$Timestamp
}
```

### SystemMetrics

```powershell
class SystemMetrics {
    [string]$ComputerName
    [double]$CPUPercent
    [double]$MemoryPercent
    [double]$DiskPercent
    [int]$ProcessCount
    [int]$ThreadCount
}
```

## Error Codes

| Code | Message | Cause |
|------|---------|-------|
| 0 | Success | No error |
| 1 | Authentication failed | Invalid credentials |
| 2 | Authorization failed | Insufficient permissions |
| 3 | Network error | Connection issue |
| 4 | Timeout | Operation exceeded timeout |
| 5 | Invalid argument | Parameter validation failed |
| 99 | Unknown error | Unexpected exception |

## Version Compatibility

Most scripts in Bug-Free Umbrella are compatible with:
- **PowerShell 5.1** (Windows, with WMF 5.1)
- **PowerShell 7.0+** (Windows, Linux, macOS)

Key compatibility notes:

| Feature | PS 5.1 | PS 7.0+ | Notes |
|---------|--------|---------|-------|
| `Get-CimInstance` | ✓ | ✓ | Preferred over deprecated `Get-WmiObject` |
| `ForEach-Object -Parallel` | ✗ | ✓ | Requires PS 7.0+; use `Invoke-Command -AsJob` for PS 5.1 |
| Azure CLI/SDK | ✓ | ✓ | Requires Az module |
| Cross-platform paths | ✗ | ✓ | Use `[System.IO.Path]::Combine()` for compatibility |
| `Invoke-RestMethod` | ✓ | ✓ | Native support |

---

**See Also:** [Advanced-Scripting-Patterns.md](Advanced-Scripting-Patterns.md) | [Troubleshooting.md](Troubleshooting.md)
