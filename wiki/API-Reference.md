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

This reference documents all public APIs in Bug-Free Umbrella.

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

### Invoke-RemoteScript

```
INVOKE-REMOTESCRIPT

SYNOPSIS
Execute script on remote computer with error handling.

SYNTAX
Invoke-RemoteScript -ComputerName <string> -FilePath <string> [-ArgumentList <object[]>] [-TimeoutSeconds <int>] [<CommonParameters>]

PARAMETERS
-ComputerName <string>
    Target computer
    Required: True

-FilePath <string>
    Script file path
    Required: True

-ArgumentList <object[]>
    Arguments to pass to script
    Required: False

-TimeoutSeconds <int>
    Execution timeout
    Required: False
    Default value: 600

RETURN VALUE
PSCustomObject with properties:
  - Success: bool
  - Output: object
  - ExecutionTime: TimeSpan
  - Error: string (if failed)
```

## Integration Modules

### Azure Integration

```
MODULE: AzureIntegration

FUNCTIONS
Connect-AzureAccount
Get-AzureVMs
Start-AzureVM
Stop-AzureVM
Get-AzureStorageAccount

DEPENDENCIES
- Az.Accounts
- Az.Compute
- Az.Storage
```

### Microsoft 365 Integration

```
MODULE: M365Integration

FUNCTIONS
Connect-M365Service
Get-M365Users
Set-M365UserLicense
Get-M365MailboxPermissions
Enable-M365Compliance

DEPENDENCIES
- ExchangeOnlineManagement
- MSOnline
```

## Utility Functions

### ConvertTo-SecureCredential

```
CONVERTTO-SECURECREDENTIAL

SYNOPSIS
Convert plaintext to PSCredential object safely.

SYNTAX
ConvertTo-SecureCredential -Username <string> -Password <string> [<CommonParameters>]

PARAMETERS
-Username <string>
    Username
    Required: True

-Password <string>
    Password (will be converted to SecureString)
    Required: True

EXAMPLES
$cred = ConvertTo-SecureCredential -Username "user@domain.com" -Password "P@ssw0rd!"
```

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

| Function | PS 5.1 | PS 7.0+ | Notes |
|----------|--------|---------|-------|
| Get-SystemInfo | ✓ | ✓ | Cross-platform in PS7+ |
| Invoke-RemoteScript | ✓ | ✓ | Requires WinRM |
| ConvertTo-SecureCredential | ✓ | ✓ | Native support |

---

**See Also:** [Advanced-Scripting-Patterns.md](Advanced-Scripting-Patterns.md) | [Troubleshooting.md](../wiki/Troubleshooting.md)