# Optimize-WsusServer.ps1 - Issues to Fix Before Merge

**Status**: Documentation of critical issues identified during code review
**Priority**: Must be addressed before merging to main
**Tracked in**: PR #58 - Release v3.5.0

---

## 🚨 Critical Issues (Must Fix Before Merge)

### 1. SQL Injection Vulnerability (Line 959)

**Severity**: CRITICAL
**Location**: `Optimize-WsusDatabase` function, line ~959

**Issue**: SQL identifiers are concatenated without proper escaping in database optimization queries.

```powershell
# Current (vulnerable):
SET @sql = 'ALTER INDEX [' + @indexname + '] ON [' + @schemaname + '].[' + @tablename + '] REBUILD WITH (ONLINE = OFF)'
```

**Fix Required**: Use `QUOTENAME()` for SQL Server identifiers to prevent SQL injection.

```powershell
# Should be:
SET @sql = 'ALTER INDEX ' + QUOTENAME(@indexname) + ' ON ' + QUOTENAME(@schemaname) + '.' + QUOTENAME(@tablename) + ' REBUILD WITH (ONLINE = OFF)'
```

**Impact**: Malicious database objects with crafted names could execute arbitrary SQL.

---

### 2. Command Injection in Scheduled Tasks (Lines 1445, 1479, 1512)

**Severity**: CRITICAL
**Location**: `New-WsusDailyTask`, `New-WsusWeeklyTask`, `New-WsusMonthlyTask` functions

**Issue**: Path variables in scheduled task arguments need validation. Tasks run as SYSTEM with highest privileges - this is a privilege escalation vector.

```powershell
# Current (vulnerable):
$arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -OptimizeServer -DeclineSupersededUpdates -ConfigFile `"$script:ConfigFile`""
```

**Fix Required**:
1. Validate `$ScriptPath` and `$script:ConfigFile` paths against path traversal
2. Ensure paths don't contain command injection characters
3. Use `Test-Path` and resolve to absolute paths
4. Consider using scheduled task parameters instead of embedding in command line

**Impact**: Attacker who can control script path or config file path can execute arbitrary code as SYSTEM.

---

### 3. XML External Entity (XXE) Vulnerability (Lines 717, 813)

**Severity**: CRITICAL
**Location**: `Test-WsusIISConfig` and `Set-WsusIISConfig` functions

**Issue**: Loading XML without disabling external entities creates XXE attack vector.

```powershell
# Current (vulnerable):
[xml]$webConfig = Get-Content $webConfigPath
```

**Fix Required**: Disable DTD processing and XML resolver before loading XML.

```powershell
# Should be:
$xmlSettings = New-Object System.Xml.XmlReaderSettings
$xmlSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
$xmlSettings.XmlResolver = $null
$reader = [System.Xml.XmlReader]::Create($webConfigPath, $xmlSettings)
$webConfig = New-Object System.Xml.XmlDocument
$webConfig.Load($reader)
$reader.Close()
```

**Impact**: XXE attacks can lead to file disclosure, SSRF, or denial of service.

---

### 4. Hard-Coded SQL Server Instance (Lines 1009, 1037)

**Severity**: HIGH
**Location**: `Initialize-WsusDatabase` and `Optimize-WsusDatabase` functions

**Issue**: Assumes Windows Internal Database (WID). Fails on WSUS installations using full SQL Server.

```powershell
# Current (hard-coded):
$result = Invoke-Sqlcmd -Query $script:CreateCustomIndexesSQL -ServerInstance "\\.\pipe\MICROSOFT##WID\tsql\query" -Verbose
```

**Fix Required**:
1. Add `-SqlServerInstance` parameter to script (default to WID)
2. Auto-detect SQL instance from WSUS registry configuration
3. Store in configuration file for reuse

```powershell
# Detection logic needed:
$wsusSetupKey = "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup"
$sqlInstance = (Get-ItemProperty -Path $wsusSetupKey -Name "SqlServerName" -ErrorAction SilentlyContinue).SqlServerName
if ([string]::IsNullOrEmpty($sqlInstance)) {
    $sqlInstance = "\\.\pipe\MICROSOFT##WID\tsql\query"  # Default to WID
}
```

**Impact**: Script completely fails on WSUS servers using full SQL Server installations.

---

### 5. Dead Code Bug (Lines 1517-1518)

**Severity**: MEDIUM
**Location**: `New-WsusMonthlyTask` function

**Issue**: Creates invalid daily trigger that gets immediately replaced. Dead code that causes confusion.

```powershell
# Lines 1517-1518 (dead code):
$trigger = New-ScheduledTaskTrigger -Daily -At $time
$trigger.DaysInterval = 0

# Line 1522 (overwrites above):
$trigger = New-CimInstance -CimClass $class -ClientOnly
```

**Fix Required**: Remove lines 1517-1518 entirely.

**Impact**: Confusing code that doesn't affect functionality but indicates poor code quality.

---

### 6. Broken Configuration Check (Line 662)

**Severity**: MEDIUM
**Location**: `Start-InteractiveWizard` function

**Issue**: Configuration structure doesn't have a `CheckConfig` property. Condition always evaluates to false/null.

```powershell
# Line 662 (broken):
if ($config.CheckConfig) {
    Test-WsusIISConfig -Config $config
}
```

**Fix Required**: Either remove this check or fix the logic to check a valid property.

```powershell
# Should probably be:
if ($config.Features.AutomaticCleanup) {
    Test-WsusIISConfig -Config $config
}
```

**Impact**: IIS config validation never runs in interactive mode, even when it should.

---

## ⚠️ High Priority Issues

### 7. Shallow Clone Bug (Line 328)

**Severity**: MEDIUM
**Location**: `Get-WsusConfig` function

**Issue**: `.Clone()` creates shallow copy of hashtables. Nested hashtables are still references to original.

```powershell
# Line 328 (problematic):
return $script:DefaultConfig.Clone()
```

**Fix Required**: Implement deep clone function.

```powershell
function Copy-Hashtable {
    param($InputObject)

    $clone = @{}
    foreach ($key in $InputObject.Keys) {
        if ($InputObject[$key] -is [hashtable]) {
            $clone[$key] = Copy-Hashtable $InputObject[$key]
        }
        elseif ($InputObject[$key] -is [Array]) {
            $clone[$key] = @($InputObject[$key])
        }
        else {
            $clone[$key] = $InputObject[$key]
        }
    }
    return $clone
}
```

**Impact**: Modifications to returned config can affect default config template.

---

### 8. Inconsistent Error Handling

**Severity**: MEDIUM
**Location**: Multiple functions throughout

**Issue**: Some functions throw exceptions, others return null. Makes error handling unpredictable for callers.

**Fix Required**: Standardize error handling:
- Use `Write-Error` for non-terminating errors
- Use `throw` only for critical failures
- Document error behavior in function help
- Consider using `[CmdletBinding()]` with `-ErrorAction` support consistently

**Impact**: Unpredictable error propagation, difficult to handle errors properly in calling code.

---

### 9. Missing ShouldProcess Support

**Severity**: MEDIUM
**Location**: Update decline functions (`Remove-UpdatesByProduct`, `Remove-UpdatesByTitle`, etc.)

**Issue**: Functions that decline updates don't support `-WhatIf` parameter, but they modify WSUS state.

**Fix Required**: Add `ShouldProcess` support to all state-modifying functions.

```powershell
[CmdletBinding(SupportsShouldProcess = $true)]
param(...)

# Before declining:
if ($PSCmdlet.ShouldProcess($update.Title, "Decline update")) {
    $update.Decline()
    $declinedCount++
}
```

**Impact**: Users can't safely test deep clean operations with `-WhatIf`.

---

### 10. No Input Validation in Interactive Mode

**Severity**: MEDIUM
**Location**: `Start-InteractiveWizard` function, multiple `Read-Host` calls

**Issue**: User input needs length limits and sanitization to prevent issues.

**Fix Required**: Add validation to all user inputs:
- Limit string lengths (prevent memory exhaustion)
- Validate product/title names against allowed characters
- Sanitize inputs before using in file paths or SQL

```powershell
# Example validation:
do {
    $product = Read-Host "Product"
    if ($product.Length -gt 255) {
        Write-Host "Product name too long (max 255 characters)" -ForegroundColor Red
        $product = $null
    }
    if ($product -match '[<>:"|?*]') {
        Write-Host "Product name contains invalid characters" -ForegroundColor Red
        $product = $null
    }
} while ($product -and [string]::IsNullOrWhiteSpace($product))
```

**Impact**: Potential for malformed data in configuration, edge case bugs.

---

### 11. No Path Validation for ConfigFile Parameter

**Severity**: MEDIUM
**Location**: Script parameter block, `Get-WsusConfig`, `Save-WsusConfig` functions

**Issue**: Should validate `$ConfigFile` parameter against path traversal attacks.

**Fix Required**: Add path validation function.

```powershell
function Test-SafePath {
    param([string]$Path)

    # Resolve to absolute path
    $resolved = [System.IO.Path]::GetFullPath($Path)

    # Check for path traversal attempts
    if ($resolved -notmatch '^[A-Za-z]:\\') {
        throw "Invalid path format: $Path"
    }

    # Ensure path doesn't contain dangerous patterns
    if ($resolved -match '\.\.[/\\]') {
        throw "Path traversal detected: $Path"
    }

    return $resolved
}

# Use in parameter validation:
[ValidateScript({Test-SafePath $_})]
[string]$ConfigFile = "C:\Scripts\WSUS\wsus-config.json"
```

**Impact**: Potential for reading/writing files outside intended directories.

---

## 📝 Testing Checklist (Post-Fix)

Before merging, ensure:

- [ ] **Security Scan**: Run PowerShell security analyzer (PSScriptAnalyzer with security rules)
- [ ] **SQL Injection Tests**: Test with malicious database object names
- [ ] **XXE Tests**: Test with malicious XML content in web.config
- [ ] **Path Traversal Tests**: Test with `../../` patterns in paths
- [ ] **Command Injection Tests**: Test with special characters in script paths
- [ ] **Full SQL Server Test**: Verify works with full SQL Server (not just WID)
- [ ] **WhatIf Testing**: Verify all `-WhatIf` scenarios work correctly
- [ ] **Input Validation**: Test with extremely long inputs, special characters
- [ ] **Deep Clone Test**: Verify config modifications don't affect defaults
- [ ] **Error Handling**: Test all error paths, ensure consistent behavior

---

## 🔐 Security Review Required

**Before merging to main**, this script needs:

1. ✅ Security code review by someone with PowerShell security expertise
2. ✅ Testing in isolated environment with malicious inputs
3. ✅ Validation that scheduled tasks can't be exploited for privilege escalation
4. ✅ Confirmation that SQL queries are properly parameterized
5. ✅ XXE vulnerability testing and mitigation
6. ✅ Path validation for all file operations

---

## 📚 References

- [OWASP SQL Injection Prevention](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html)
- [OWASP XXE Prevention](https://cheatsheetseries.owasp.org/cheatsheets/XML_External_Entity_Prevention_Cheat_Sheet.html)
- [PowerShell Security Best Practices](https://docs.microsoft.com/en-us/powershell/scripting/dev-cross-plat/security/security-best-practices)
- [PSScriptAnalyzer Rules](https://github.com/PowerShell/PSScriptAnalyzer)

---

**Created**: 2026-01-09
**Last Updated**: 2026-01-09
**Status**: Issues documented, fixes pending
**Estimated Fix Time**: 4-6 hours for critical issues, 2-3 hours for high priority
