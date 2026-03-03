# Changelog

![Version](https://img.shields.io/badge/version-4.0.0-blue)
![Release Date](https://img.shields.io/badge/release-2026--03--03-green)
![Total Scripts](https://img.shields.io/badge/scripts-260+-orange)
![License](https://img.shields.io/badge/license-Apache%202.0-red)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## 📑 Table of Contents

- [🌂 About Our Release Names](#-about-our-release-names)
- [Unreleased](#unreleased)
- **Latest Releases:**
  - [v4.0.0 (2026-03-03) 🌪️ Hurricane - Security Hardening](#400---2026-03-03-️-hurricane---security-hardening-release)
  - [v3.7.1 (2026-01-29) 🌂 Drizzle - Documentation & Security Hardening](#371---2026-01-29-️-drizzle---documentation--security-hardening-update)
  - [v3.7.0 (2026-01-21) 🌧️ Shower - Security & Maintenance](#370---2026-01-21-️-shower---security--maintenance-release)
  - [v3.6.0 (2026-01-16) 🌧️ Shower - Intune Device Management](#360---2026-01-16-️-shower---intune-device-management-scripts)
  - [v3.5.0 (2026-01-15) 🌧️ Shower - AVD Image Builder](#350---2026-01-15-️-shower---avd-image-builder-enhancement)
  - [v3.4.0 (2026-01-09) 🌈 Rainbow - Documentation](#340---2026-01-09--rainbow---documentation--examples-enhancement)
  - [v3.3.0 (2026-01-08) 🌧️ Rainfall - M365 User Management](#330---2026-01-08-️-rainfall---m365-user-management-toolkit)
  - [v3.2.0 (2026-01-06) 🌧️ Sprinkle - M365 Apps](#320---2026-01-06-️-sprinkle---m365-apps-management)
  - [v3.2.0 (2026-01-06) 🌧️ Monsoon - Device Health](#320---2026-01-06-️-monsoon---device-health--uptime-monitoring)
  - [v3.1.0 (2026-01-05) 🌧️ Shower - Expanded Intune](#310---2026-01-05-️-shower---expanded-intune-operations)
  - [v3.0.3 (2026-01-04) ☔ Drizzle - Wiki Version Fix](#303---2026-01-04--drizzle---wiki-version-reference-fix)
  - [v3.0.2 (2026-01-03) ☔ Drizzle - Documentation Cleanup](#302---2026-01-03--drizzle---documentation-cleanup)
  - [v3.0.1 (2025-12-31) ☔ Drizzle - Bug Fix](#301---2025-12-31--drizzle---bug-fix-release)
  - [v3.0.0 (2025-12-30) 🌪️ Hurricane - Repository Restructure](#300---2025-12-30-️-hurricane---repository-restructure)
  - [v2.2.0 (2025-12-30) 🌧️ Shower - Navigation & Usability](#220---2025-12-30-️-shower---navigation--usability-release)
  - [v2.1.0 (2025-12-29) 🌈 Rainbow - Quality & Reliability](#210---2025-12-29--rainbow---quality--reliability-release)
  - [v2.0.0 (2025-12-28) ⛈️ Thunderstorm - Regional Settings](#200---2025-12-28-️-thunderstorm---regional-settings-major-release)
  - [v1.0.0 (2025-12-27) ⛈️ Thunderstorm - Initial Production](#100---2025-12-27-️-thunderstorm---initial-production-release)
  - [v0.9.0 (2025-12-15) ☔ Drizzle - Initial Setup](#090---2025-12-15--drizzle---initial-setup)
- [Version History Summary](#version-history-summary)
- [Upgrade Notes](#upgrade-notes)

---

## 🌂 About Our Release Names

Bug-Free Umbrella uses **weather-themed codenames** to make releases memorable:

| Icon | Name | Type | Meaning |
|------|------|------|---------|
| ☔ | **Drizzle** | Patch (x.x.1) | Bug fixes, minor improvements |
| 🌧️ | **Shower** | Minor (x.1.x) | New scripts, small features |
| ⛈️ | **Thunderstorm** | Major (1.x.x) | Significant expansions |
| 🌪️ | **Hurricane** | Breaking | Major overhauls, breaking changes |
| 🌈 | **Rainbow** | Quality | Polish, documentation, testing |

---

## [Unreleased]

---

## [3.7.1] - 2026-01-29 🌂 **"Drizzle"** - Documentation & Security Hardening Update

> **Focus**: Critical security documentation improvements, code quality updates, and accuracy corrections

**📊 [Compare v3.7.0...v3.7.1](https://github.com/Carme99/bug-free-umbrella/compare/v3.7.0...v3.7.1)**

### Security Improvements 🔒

#### Documentation Security Hardening
- **Security-Troubleshooting.md**: Added prominent security warnings for diagnostic code patterns
  - ⚠️ Bold warnings for SSL certificate bypass (diagnostic testing ONLY)
  - Explicit MITM attack risk disclosure
  - Recommended safer alternatives: `-UseDefaultCredentials`, certificate-based auth, Azure Key Vault, managed identity
  - Comprehensive security guidance for plaintext credential handling
  - Clear documentation of when to use vs. when NOT to use diagnostic patterns

### Code Quality Improvements 📝

#### PowerShell Compatibility & Modernization
- **Scaling-&-Load-Balancing.md**: Replaced deprecated `Get-WmiObject` with `Get-CimInstance`
  - Full PowerShell 7.0+ compatibility
  - Future-proof CIM-based approach
  - Added migration notes for maintainers

#### Version Compatibility Warnings
- **Scaling-&-Load-Balancing.md**: Added prominent PS 7.0+ requirement notices
  - `ForEach-Object -Parallel` now clearly marked as PS 7.0+ only
  - Suggested `Invoke-Command -AsJob` workaround for PowerShell 5.1
  - Helps users avoid runtime errors

### Documentation Accuracy Fixes 📚

#### API Reference Corrections
- **API-Reference.md**: Removed references to non-existent internal functions
  - Removed hypothetical `Invoke-RemoteScript` (replaced with native `Invoke-Command` guidance)
  - Removed hypothetical `ConvertTo-SecureCredential` (replaced with security best practices)
  - Clarified that functions are distributed by category, not provided as monolithic module

#### Script Organization Documentation
- **API-Reference.md**: Added accurate available script categories and locations
  - Cloud Platforms: Azure, AWS integration scripts
  - Infrastructure & Monitoring: Windows, network operations
  - Collaboration & Microsoft 365: AD, mailbox, licensing
  - Security & Compliance: Vulnerability, audit scripts
  - Data & API: Management and monitoring

#### Improved Security Guidance in API Docs
- Added best practices for credential handling (Key Vault, Managed Identity, env vars)
- Updated version compatibility table with accurate feature support matrix
- Cross-references to security documentation from utility function sections

### Resolved Issues
- ✅ **HIGH**: Credential Handling security warnings (Security-Troubleshooting.md:131)
- ✅ **HIGH**: SSL Certificate Bypass security warnings (Security-Troubleshooting.md:42)
- ✅ **MEDIUM**: Deprecated WMI Usage (Scaling-&-Load-Balancing.md:171)
- ✅ **MEDIUM**: PowerShell Version Compatibility (Scaling-&-Load-Balancing.md:232, 243)
- ✅ **MEDIUM**: Incomplete API Reference (API-Reference.md - full accuracy review)

---

## [4.0.0] - 2026-03-03 🌪️ **"Hurricane"** - Security Hardening Release

> **Focus**: Comprehensive security hardening across database, network, and winget scripts

**📊 [Compare v3.7.1...v4.0.0](https://github.com/Carme99/bug-free-umbrella/compare/v3.7.1...v4.0.0)**

### 🛡️ Security Hardening Initiative

#### Winget Script Security (75+ scripts)
- **Replaced `Invoke-Expression` with `ProcessStartInfo`**: Eliminated code injection vulnerabilities across all winget detect/remediate scripts
- **Removed dangerous patterns**: `Invoke-Expression "sysget $Arguments 2>&1"` patterns replaced with secure process execution
- **Standardized security**: Consistent secure execution pattern across all application categories (browsers, development tools, productivity, communication, remote access, runtimes, utilities, vendor-specific)

#### Database Script Security
- **MongoDB Health Monitor**: Implemented `SecureString` with proper `ZeroFreeBSTR` memory cleanup and `Uri.EscapeDataString` encoding
- **MySQL Health Script**: Converted plaintext credentials to `SecureString` implementation
- **PostgreSQL Health Script**: Fixed BSTR memory leaks by storing pointer once, using it, and freeing the same pointer
- **Credential Security**: All database scripts now handle credentials securely in memory

#### Network & Infrastructure Security
- **Reset-NetworkStack.ps1**: Added comprehensive `-WhatIf` and `-Confirm` support for safe operation
- **IPv6, DNS, Proxy, Adapters, DHCP**: All network reset operations now support dry-run and confirmation
- **Safety Features**: Prevents accidental network disruption with user confirmation prompts

#### Error Handling & Code Quality
- **Update-DotNetRuntimes.ps1**: Fixed empty catch blocks with proper error logging and handling
- **Duplicate flag removal**: Eliminated duplicate `--accept-*` flags in 33 remediate.ps1 files
- **Consistency improvements**: Standardized error handling patterns across scripts

### 🧹 Code Quality & Cleanup

#### Dead Code Removal
- **Removed redundant `Resolve-Path` calls**: Eliminated 34+ instances of unused winget executable resolution in main script body
- **Fixed unused variables**: Removed `$stderr` capture that was never used in `Invoke-WingetWithRetry` functions
- **Cleaned commented code**: Removed obsolete commented-out code in Adobe RUM scripts
- **Addressed unused functions**: Handled `Invoke-IntuneGraphRequest` function defined but never called

#### Error Handling Improvements
- **Empty catch blocks**: Fixed silent error swallowing in `Invoke-WingetWithRetry` functions with proper error logging
- **Consistent patterns**: Standardized try-catch-error handling across all modified scripts

### 📚 Documentation Updates

#### Version References
- **Updated all wiki documentation**: Changed version references from v3.7.0/v3.0.2 to v4.0.0
- **Home.md, Release-Notes.md, Script-Catalog.md, FAQ.md, Intune-Management.md, Prerequisites.md, Azure-Compute-Gallery-Image-Builder.md, Getting-Started.md, WIKI-SETUP.md**: All updated to reflect v4.0.0 release

#### Documentation Accuracy
- **CHANGELOG alignment**: Ensured all security hardening work is properly documented
- **Version badges**: Updated README.md and documentation badges to v4.0.0
- **British English spelling**: Applied EN GB spelling corrections to CONTRIBUTING.md

### 🧪 Testing & Validation

#### Security Validation
- **Created security tests**: `tests/Security.Tests.ps1` for Pester-based security validation
- **Helper functions module**: `scripts/.shared/WARP-HelperFunctions.psm1` with security utilities
- **Comprehensive coverage**: Tests validate secure execution patterns and credential handling

### 🔄 Breaking Changes & Migration Notes

#### Security Pattern Changes
- **Winget execution**: All scripts now use `System.Diagnostics.ProcessStartInfo` instead of `Invoke-Expression`
- **Credential handling**: Database scripts require `SecureString` or proper credential management
- **Network operations**: `Reset-NetworkStack.ps1` now requires `-Confirm` for destructive operations

#### Backward Compatibility
- **API remains unchanged**: Function signatures and parameters unchanged
- **Behavior identical**: Same functionality with enhanced security
- **Migration path**: Existing scripts continue working with improved security

### 📈 Performance & Reliability

#### Execution Stability
- **Reduced attack surface**: Eliminated code injection vectors
- **Memory safety**: Proper credential handling and memory cleanup
- **Error resilience**: Improved error handling prevents silent failures

#### Maintenance Benefits
- **Code consistency**: Standardized patterns across all scripts
- **Security auditing**: Clear security patterns for future development
- **Testing framework**: Established security testing baseline

### Resolved Issues
- ✅ **CRITICAL**: Code injection vulnerabilities in winget scripts (75+ files)
- ✅ **HIGH**: Plaintext credentials in database scripts (MongoDB, MySQL, PostgreSQL)
- ✅ **HIGH**: Empty catch blocks swallowing errors (Update-DotNetRuntimes.ps1)
- ✅ **MEDIUM**: Missing safety controls in network scripts (Reset-NetworkStack.ps1)
- ✅ **MEDIUM**: Dead code and unused variables (34+ winget scripts)
- ✅ **LOW**: Documentation version mismatches (11 wiki files)

**Upgrade Instructions**: This is a **security hardening release** with no breaking API changes. All existing functionality works with enhanced security. Review network script usage as `-Confirm` is now required for safety.

**Security Advisory**: This release addresses critical security vulnerabilities and should be deployed as soon as possible.

---

## [3.7.0] - 2026-01-21 🌧️ **"Shower"** - Security & Maintenance Release

> **Focus**: Winget security updates automation and critical .NET script bug fixes

**📊 [Compare v3.6.0...v3.7.0](https://github.com/Carme99/bug-free-umbrella/compare/v3.6.0...v3.7.0)**

### Added

#### 📱 Winget Security Updates - Check-OutdatedCriticalApps (NEW!)

**Proactive Remediation Package** ([`scripts/endpoints/devices/proactive-remediations/Check-OutdatedCriticalApps/`](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Check-OutdatedCriticalApps))

- **Rapid Security Patching** - Automated updates for security-critical applications using winget
  - Priority app classification (browsers, VPN, security tools) vs standard apps
  - Dual deployment strategy: Priority updates every 4 hours, comprehensive updates daily
  - Process management with graceful/force close options
  - Retry logic with exponential backoff (2-3 attempts)
  - Timeout handling per application (5-10 minutes configurable)
  - Optional logging to %TEMP% for troubleshooting

- **Three Script Variants**
  - [`detect.ps1`](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/endpoints/devices/proactive-remediations/Check-OutdatedCriticalApps/detect.ps1) - Identifies outdated critical applications with priority filtering
  - [`remediate.ps1`](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/endpoints/devices/proactive-remediations/Check-OutdatedCriticalApps/remediate.ps1) - Standard remediation for all critical/standard apps
  - [`remediate_priority_only.ps1`](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/endpoints/devices/proactive-remediations/Check-OutdatedCriticalApps/remediate_priority_only.ps1) - Emergency variant for highest-priority apps only

- **Priority Applications** (Always Updated First)
  - Browsers: Chrome, Firefox, Edge, Brave
  - VPN & Remote Access: Cisco AnyConnect, OpenVPN, WireGuard
  - Development Tools: VS Code, Git, Python
  - Security Tools: PowerShell 7, 1Password, Bitwarden

- **Standard Applications** (Comprehensive Mode)
  - Adobe Acrobat Reader, VLC, Zoom, Microsoft Teams
  - Notepad++, 7-Zip, PowerToys

- **Comprehensive Documentation**
  - Complete [`README.md`](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/endpoints/devices/proactive-remediations/Check-OutdatedCriticalApps/README.md) with 4 deployment scenarios
  - Quick start guide with recommended deployment (TWO remediations)
  - Configuration examples for customizing app lists
  - Monitoring and reporting guidance
  - Troubleshooting section for common issues
  - Security considerations and best practices

**Use Cases:**
- Rapid CVE response (patch critical vulnerabilities within 4 hours)
- Reduced security surface (keep browsers and VPN clients current)
- Automated compliance (maintain security baselines)
- Measurable impact (track patch rates and time-to-remediation)

#### 🔧 .NET Runtime Maintenance Script v2.5 Upgrade (MAJOR UPDATE)

[**`Update-DotNetRuntimes.ps1`**](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/utilities/Update-DotNetRuntimes.ps1) ([utilities folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/utilities))

- **Interactive Menu System** - 8 maintenance options with user-friendly interface
  - Update all runtimes (patches only)
  - Remove EOL runtimes
  - Install specific runtime versions
  - Cleanup lower patches
  - Generate disk usage reports
  - Show system dependencies
  - Create system restore points
  - Refresh system status (force scan)

- **Enhanced Security** 🔒
  - **CRITICAL FIX**: Mandatory Authenticode signature validation (no bypass allowed)
  - SHA512 hash verification for all downloads
  - Prevents installation of tampered or malicious MSI files
  - Security-hardened installation process

- **Dependency Detection & Safety** 🔒
  - Scans for IIS and ANCM (ASP.NET Core Module)
  - Detects Windows Services using .NET runtimes
  - Identifies Scheduled Tasks with .NET dependencies
  - Monitors running .NET processes
  - Configurable dependency handling: Warn / Block / Off
  - Protected channels feature prevents accidental removal

- **Performance & Reliability** ⚡
  - **CRITICAL FIX**: Robust error handling in disk usage calculations
  - **FIX**: Cache invalidation bug with Force parameter
  - .NET DirectoryInfo API for 10-100x faster disk operations
  - Smart caching (5-minute TTL) with Force override
  - Lazy loading for optional operations

- **New CLI Parameters**
  - `OneShotCleanup` - Single parameter for complete automation
  - `DependencyCheck` - Control dependency validation behavior
  - `ProtectChannels` - Prevent accidental removal of critical versions
  - `CreateRestorePoint` / `RestorePointName` - System restore support
  - `Force` - Bypass cache for fresh scans
  - `NonInteractive` - Explicit CLI mode control
  - `SkipDiskScan` - Fast execution without disk analysis

- **Enhanced Logging & Reporting**
  - Proper PowerShell streams (Write-Warning, Write-Error, Write-Information)
  - Structured logging with context
  - Automation-friendly output
  - Real-time status display in menu mode

### Changed

- [**`Update-DotNetRuntimes.ps1`**](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/utilities/Update-DotNetRuntimes.ps1): Upgraded from v1.0.0 to v2.5
  - Complete rewrite with dual-mode operation (interactive menu + CLI automation)
  - Parameter defaults changed for safer operations (require explicit approval)
  - Admin enforcement with user-friendly error messages
  - Enhanced documentation in [`scripts/utilities/README.md`](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/utilities/README.md)

#### 🔧 .NET Runtime Maintenance Script v2.6 Bug Fixes (8 CRITICAL FIXES)

> **⚠️ CRITICAL FIXES**: All 8 menu options now functional (previously 5 failed)

[**`Update-DotNetRuntimes.ps1`**](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/utilities/Update-DotNetRuntimes.ps1) - Comprehensive bug fix release addressing all menu failures

**Bug #1: AspNetGroups Null Parameter Error** (Lines 495-507)
- **CRITICAL**: Fixed null parameter binding error when no ASP.NET Core runtimes installed
- **Root Cause**: `Where-Object { $_ }` returns `$null` instead of empty array when no items match
- **Solution**: Removed problematic filter since `Get-InstalledProductByArch` already returns `@()`
- **Impact**: Fixed menu options 1, 3, 4 (Quick Maintenance, Automated Update, Interactive Update)

**Bug #2: Disk Usage Analyzer Hang** (Lines 787-799, 1368-1380)
- **CRITICAL**: Fixed script hang at "Press any key" with immediate close
- **Root Cause**: No error handling, no null checks, no user feedback when data unavailable
- **Solution**: Added try-catch blocks, null/empty checks, user feedback messages
- **Impact**: Fixed menu option 7 (Disk Usage Analyzer)

**Bug #3: MSI Publisher Validation Too Strict** (Lines 681-684)
- **HIGH**: Fixed legitimate Microsoft certificate rejection for .NET uninstall tool
- **Root Cause**: Validation only checked for `CN=Microsoft Corporation` but Microsoft uses `CN=.NET, O=Microsoft Corporation`
- **Solution**: Updated validation to accept EITHER `CN=Microsoft Corporation` OR `O=Microsoft Corporation`
- **Impact**: Fixed menu option 5 (EOL Removal Wizard) when installing uninstall tool

**Bug #4: Null Reference in Runtime Update Planning** (Lines 876, 917, 1257, 1265)
- **HIGH**: Fixed potential null reference crashes during update planning
- **Root Cause**: Direct access to `$grp.Group` without null checks
- **Solution**: Added validation: `if (-not $grp.Group -or $grp.Group.Count -eq 0) { continue }`
- **Impact**: Prevents crashes in update planning and system status display

**Bug #5: Array Bounds Errors in EOL Removal** (Lines 1354-1356, 1380-1381)
- **HIGH**: Fixed array index out of bounds when parsing malformed EOL channel strings
- **Root Cause**: Code assumed EOL channel format "X.X (arch)" without validation
- **Solution**: Added array bounds check: `if ($parts.Count -lt 2) { continue }`
- **Impact**: Prevents crashes from unexpected EOL channel string formats

**Bug #6: Undefined Variable in WhatIf Mode** (Lines 986-990)
- **MEDIUM**: Fixed undefined variable access in dry-run/preview mode
- **Root Cause**: `$installResult` accessed after if block but only defined inside non-WhatIf branch
- **Solution**: Added null check before property access and else block for WhatIf logging
- **Impact**: Fixes dry-run mode crashes when previewing updates

**Bug #7: Missing Process Timeouts** (Lines 620-621, 706, 741, 858)
- **HIGH**: Fixed indefinite hangs on stuck installer processes
- **Root Cause**: `WaitForExit()` called without timeout parameter
- **Solution**: Added timeout parameter: `$proc.WaitForExit($timeoutMs)` with default 10 minutes
- **Impact**: Prevents script hanging indefinitely on problematic installers

**Bug #8: Measure-Object Null Handling** (Lines 1085-1086)
- **MEDIUM**: Fixed null reference when calculating disk usage on empty collections
- **Root Cause**: `Measure-Object` returns `$null` for `.Sum` property when collection is empty
- **Solution**: Added null coalescing: `if ($null -eq $sum) { 0 } else { $sum }`
- **Impact**: Prevents crashes in disk usage calculations for edge cases

**Testing Results:**
- All 8 menu options now function correctly (previously 5 failed: options 1, 3, 4, 5, 7)
- Comprehensive error handling prevents crashes across all scenarios
- Improved user feedback and logging throughout

### Fixed

> **🔒 SECURITY**: Critical security fix in v2.5

- **SECURITY**: Signature validation bypass vulnerability in MSI installation (v2.5)
- **PERFORMANCE**: Null reference errors in disk usage calculation (v2.5)
- **BUG**: Cache invalidation not honoring Force parameter (v2.5)
- **CRITICAL**: 8 major bugs in Update-DotNetRuntimes.ps1 causing menu failures (v2.6)

### Statistics

**Winget Security Updates:**
- **New Remediations**: 1 (Check-OutdatedCriticalApps)
- **Total Remediations**: 51 proactive remediation pairs
- **New Scripts**: 3 PowerShell files (detect + 2 remediate variants)
- **Documentation**: 1 comprehensive README (~500 lines)
- **Priority Apps Tracked**: 13 (browsers, VPN, security tools, dev tools)
- **Standard Apps Tracked**: 7 (productivity applications)

**.NET Runtime Script:**
- **Updated Scripts**: 1 production-ready PowerShell script ([`Update-DotNetRuntimes.ps1`](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/utilities/Update-DotNetRuntimes.ps1))
- **Version**: v2.5 → v2.6
- **Lines Changed (v2.5)**: +1,100 / -1,246 (net -146 lines, more efficient code)
- **Lines Changed (v2.6)**: Bug fixes across 8 locations (improved error handling)
- **New Features (v2.5)**: 10+ new parameters, 8-option menu system
- **Critical Fixes (v2.5)**: 3 (1 security, 2 reliability)
- **Critical Fixes (v2.6)**: 8 (5 critical, 2 high, 1 medium) - ALL menu options now functional
- **Documentation**: Comprehensive README update with 15 best practices

[⬆️ Back to top](#-table-of-contents)

---

## [3.6.0] - 2026-01-16 🌧️ **"Shower"** - Intune Device Management Scripts

> **Focus**: Two powerful new Intune management scripts for device reporting and Lenovo device enrichment

**📊 [Compare v3.5.0...v3.6.0](https://github.com/Carme99/bug-free-umbrella/compare/v3.5.0...v3.6.0)**

### Added

#### 📱 Intune Device Primary Users Script (NEW!)

[**`Get-IntuneDevicePrimaryUsers.ps1`**](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/endpoints/intune/reporting/Get-IntuneDevicePrimaryUsers.ps1) ([intune/reporting](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/intune/reporting))

- Comprehensive device reporting tool for primary user resolution and hardware specs
- **Primary User Detection**: Uses Graph API `managedDevice/users` (beta) with intelligent fallback chain
- **Hardware Collection**: RAM, storage, CPU, model, serial, OS, last sync timestamp
- **Flexible Input**: Direct parameters, CSV/TXT files, interactive mode, GUID support
- **Output Options**: Console display, CSV export (UTF-8), configurable paths
- **Data Enrichment**: Retrieves friendly model names from Entra extension attributes
- **Graph API Best Practices**: OData escaping, progress indicators, graceful error handling

**Use Cases:**
- Primary user auditing and compliance reporting
- Hardware inventory and capacity planning
- Device-user assignment verification
- Help desk quick lookups
- Asset management integration

#### 🖥️ Lenovo Friendly Model Names Script (NEW!)

[**`Add-LenovoFriendlyModelNames.ps1`**](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/endpoints/intune/maintenance/Add-LenovoFriendlyModelNames.ps1) ([intune/maintenance](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/intune/maintenance))

- Automates enrichment of Lenovo device records with human-readable model names
- **MTM Code Mapping**: Maps 4-character codes to product families using official Lenovo dataset
- **Dual Updates**: Intune Notes (append) + Entra extension attributes (set/overwrite)
- **Reliability**: Retry logic (3 attempts), rate limiting (100ms), error logging to CSV
- **Safety**: Audit mode, WhatIf/Confirm support, selective updates
- **Authentication**: Robust sign-in with automatic device code fallback
- **Validation**: MTM format checks, mapping coverage reports, strict mode option

**Key Improvements over v1.0:**
- ✅ Fixed switch parameter declarations
- ✅ Added network resilience with exponential backoff
- ✅ Added progress indicators and rate limiting
- ✅ Improved MTM matching with targeted regex
- ✅ Added comprehensive error logging with CSV export
- ✅ Enhanced validation and status reporting

#### 📚 Comprehensive Documentation

**New Documentation Files:**
- [`docs/intune/Get-IntuneDevicePrimaryUsers.md`](https://github.com/Carme99/bug-free-umbrella/blob/main/docs/intune/Get-IntuneDevicePrimaryUsers.md) - Complete usage guide (88KB)
- [`docs/intune/Add-LenovoFriendlyModelNames.md`](https://github.com/Carme99/bug-free-umbrella/blob/main/docs/intune/Add-LenovoFriendlyModelNames.md) - Enterprise deployment guide (95KB)
- `RELEASE_NOTES_Intune_Scripts_v2.0.md` - Detailed release notes (75KB)

**Documentation Includes:**
- Parameter reference tables with descriptions
- Real-world usage examples and integration scenarios
- Troubleshooting guides with common issues
- Performance optimization guidance
- Security and compliance notes
- MTM code reference guide

### Changed

- **Wiki**: Updated Intune Management page with new scripts
- **Stats**: Intune scripts increased from 18 to 20
- **Documentation URLs**: Updated Microsoft documentation links from `docs.microsoft.com` to `learn.microsoft.com` (8 URLs)

### Statistics

- **New Scripts**: 2 production-ready PowerShell scripts
- **Total Lines**: ~1,300 lines of PowerShell code
- **Documentation**: 3 comprehensive guides (~260KB total)
- **Examples**: 20+ usage examples across documentation
- **Required Permissions**: 6 Graph API scopes documented
- **Test Coverage**: Windows 10/11, Server 2019/2022, PowerShell 5.1-7.x

### Migration Notes

**Get-IntuneDevicePrimaryUsers.ps1** - New Script (No Migration)
- Fresh installation, follow documentation in [`docs/intune/`](https://github.com/Carme99/bug-free-umbrella/tree/main/docs/intune)
- Compatible with existing Intune management workflows
- Can be integrated with scheduled tasks, Power BI, compliance reporting

**Add-LenovoFriendlyModelNames.ps1 v2.0** - Backward Compatible
```powershell
# v1.0 (if existed) - switches had issues
-UpdateNotes $true  # Always true, couldn't disable

# v2.0 (correct behavior)
-UpdateNotes              # Enabled by default
-UpdateNotes:$false       # Can now be disabled
-UpdateExtensionAttributes:$false  # Works correctly
```

**Recommended Upgrade Process:**
1. Test with `-WhatIf` to preview behavior
2. Run `-AuditOnly` to validate mapping coverage
3. Deploy to production

[⬆️ Back to top](#-table-of-contents)

---

## [3.5.0] - 2026-01-15 🌧️ **"Shower"** - AVD Image Builder Enhancement

> **Focus**: Production-ready enhancements for Azure Virtual Desktop image building automation based on real-world feedback

**📊 [Compare v3.4.0...v3.5.0](https://github.com/Carme99/bug-free-umbrella/compare/v3.4.0...v3.5.0)**

### Added

#### 🖼️ AVD Image Builder v3.5 Enhancements

[**`New-AzureComputeGalleryImage.ps1`**](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/cloud/azure/avd/New-AzureComputeGalleryImage.ps1) ([cloud/azure/avd](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/cloud/azure/avd))

**JSON Auto-Discovery**
- Automatically detects `*-config.json` files in script directory
- Interactive menu for configuration file selection
- Displays available configurations with numbered selection
- Option to fall back to interactive mode (select `[0]`)
- Backward compatible with `-ConfigFile` parameter

**Pre-Flight Validation System** (7 comprehensive checks)
- Source VM existence and accessibility verification
- Gallery and image definition validation
- Network configuration (VNet/Subnet) validation
- RBAC permissions verification
- VM size availability in target region
- Disk encryption status detection (warns if encrypted)
- Subscription access validation
- **Benefit**: Catches errors before 15-20 minute wait, saves Azure compute costs

**Configuration Schema Validation**
- Validates JSON structure and required fields
- UUID format validation for Tenant and Subscription IDs (case-insensitive)
- VM size naming convention checks (`Standard_*` format)
- Region validation against supported Azure locations
- Versioning strategy validation (Major/Minor/Patch)
- Actionable error messages with field-level details

**Configuration Preview**
- Visual summary before execution starts
- Shows source VM, target gallery, location, versioning strategy
- User confirmation prompt (skippable with `-Force`)
- Available for ConfigFile mode

**Dry-Run Mode (`-WhatIf`)**
- Test configurations without creating resources
- Validates entire config and runs all pre-flight checks
- Shows what resources would be created
- Zero Azure costs for testing
- Perfect for CI/CD pipeline validation

**Execution Time Tracking & Audit Logging**
- Automatic timestamped log files: `image-build-YYYYMMDD-HHmmss.log`
- Per-step timing captured for all 12 steps
- Final summary with total execution duration
- Comprehensive audit trail for compliance
- Log file created only after validation succeeds

**New Parameters**
- `-WhatIf`: Dry-run mode, validates without creating resources
- `-SkipPreFlightChecks`: Skip pre-flight validation (advanced users/CI-CD)

### Changed

- **Script Version**: 3.2 → 3.5
- **Banner**: Updated to display version dynamically from `$ScriptVersion` variable
- **JSON Discovery Filter**: Changed from `*.json` to `*-config.json` for better specificity
- **Log File Creation**: Moved after validation to prevent log creation for invalid configs
- **Last Updated**: 15/01/2026

### Fixed

- **Undefined Variable**: Fixed `$VersioningStrategy` reference in config preview functions (used `$config.VersioningStrategy` instead)
- **Scope Issue**: Fixed `$vm` variable scope in pre-flight disk encryption check (re-fetches VM to avoid undefined variable)
- **Incomplete Feature**: Completed step time tracking for all 12 execution steps (was only tracking Step 1)
- **Case-Sensitivity**: Fixed UUID regex to accept uppercase characters in GUIDs (`[0-9a-fA-F]` instead of `[0-9a-f]`)

### Improved

**Configuration Management**
- More robust config file handling
- Better error messages for configuration issues
- Clearer validation feedback
- Reduced false positives in validation

**Operational Excellence**
- Faster failure feedback (5-10 seconds vs 15-20 minutes)
- Reduced wasted Azure costs from failed runs
- Better audit trails for troubleshooting
- Improved debugging with per-step timing

**User Experience**
- Auto-discovery reduces parameter typing
- Interactive menu for easy config selection
- Clear visual previews before execution
- Professional timestamped logging

### Statistics

- **Script Size**: 1,928 → 2,100+ lines
- **New Features**: 6 major capabilities added
- **Bug Fixes**: 4 critical issues resolved
- **New Parameters**: 2 (`-WhatIf`, `-SkipPreFlightChecks`)
- **Validation Checks**: 7 pre-flight checks
- **Step Timing**: 12 steps tracked
- **Lines Changed**: +250 / -20

### Migration Notes

**Fully Backward Compatible** - No breaking changes!

- Existing scripts and workflows continue to work without modification
- New features are opt-in through parameters or auto-discovery
- All previous parameters and behavior preserved

**Recommended Workflow:**
```powershell
# 1. Test configuration with dry-run
.\New-AzureComputeGalleryImage.ps1 -ConfigFile "prod.json" -WhatIf

# 2. If validation passes, run for real
.\New-AzureComputeGalleryImage.ps1 -ConfigFile "prod.json"

# 3. Review log file for audit trail
Get-Content image-build-*.log | Select-Object -Last 50
```

**Auto-Discovery Workflow:**
```powershell
# Place configs in script directory:
# - prod-config.json
# - test-config.json
# - dev-config.json

# Run script, select from menu
.\New-AzureComputeGalleryImage.ps1
# Select [1] prod-config.json
```

### Performance Impact

- Pre-flight checks add: 5-10 seconds
- Saves on failed runs: 15-20 minutes
- **Net time savings**: 10-15 minutes per configuration error

[⬆️ Back to top](#-table-of-contents)

---

## [3.4.0] - 2026-01-09 🌈 **"Rainbow"** - Documentation & Examples Enhancement

> **Focus**: Quick-win content additions for improved user experience and accessibility

**📊 [Compare v3.3.0...v3.4.0](https://github.com/Carme99/bug-free-umbrella/compare/v3.3.0...v3.4.0)** | **📖 [Wiki: Getting Started](https://github.com/Carme99/bug-free-umbrella/wiki/Getting-Started)**

### Added

#### 📚 Command Recipes Cookbook

**RECIPES.md** - Comprehensive quick-reference guide with 80+ ready-to-run commands
  - 🔗 [View Documentation](https://github.com/Carme99/bug-free-umbrella/blob/main/docs/RECIPES.md)

Contents:
- Organized by category: M365, Intune, Security, Server Monitoring, User Management, Azure, Backup, Active Directory
- Copy-paste ready commands with real-world examples
- Pro tips for combining scripts and scheduling tasks
- PowerShell pipeline filtering examples
- Task Scheduler integration guides
- Multiple export format examples (HTML, CSV, JSON)
- Verbose mode troubleshooting tips
- Links to full documentation and script catalog

#### 🚨 Incident Response Examples (2 workflows, 700+ lines)

**security-incident-response.ps1** - Complete security breach investigation workflow
  - 🔗 [View Source](https://github.com/Carme99/bug-free-umbrella/blob/main/examples/incident-response/security-incident-response.ps1) | [Browse Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/examples/incident-response)

Features:
- 8-step comprehensive investigation process
- User account information gathering
- Failed login attempt analysis (last 48 hours)
- Suspicious mail rule detection (forwarding, deletion, exfiltration)
- Mailbox permission auditing (unauthorized access)
- Threat detection review (Defender for Office 365)
- Device compliance verification
- Mail flow pattern analysis
- Account isolation capabilities (revoke sessions, disable, block sign-in)
- HTML incident report generation with severity indicators
- Email alerting with incident details
- Comprehensive logging for audit trails
- Recommendations engine for remediation actions
- Timeline tracking for incident response

**performance-degradation-investigation.ps1** - System performance diagnostics workflow
  - 🔗 [View Source](https://github.com/Carme99/bug-free-umbrella/blob/main/examples/incident-response/performance-degradation-investigation.ps1) | [Browse Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/examples/incident-response)

Features:
- 9-step diagnostic process for troubleshooting slow systems
- System information collection (OS, uptime, hardware specs)
- Real-time resource usage (CPU, memory, disk queue)
- Top CPU and memory consumer identification (top 5 processes)
- Disk space analysis with threshold warnings
- Performance metrics collection (configurable duration)
- Event log analysis (errors/critical events, last 24 hours)
- Comprehensive health check integration
- Windows Update status verification
- HTML report with performance metrics dashboard
- Color-coded severity indicators (red/yellow/green)
- Automated recommendations based on findings
- Email reporting for IT operations teams
- Performance issue tracking and documentation

#### ⚙️ Automation Examples (2 workflows, 1,000+ lines)

**scheduled-daily-reporting.ps1** - Automated daily IT operations reporting
  - 🔗 [View Source](https://github.com/Carme99/bug-free-umbrella/blob/main/examples/automation/scheduled-daily-reporting.ps1) | [Browse Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/examples/automation)

Features:
- 7 daily automated checks:
  1. Device compliance report (Intune)
  2. BitLocker encryption status
  3. Windows Update compliance
  4. Security compliance scan (CIS Framework)
  5. Failed login attempts (last 24 hours)
  6. Certificate expiration check (30-day warning)
  7. Stale device identification (90+ days inactive)
- Executive summary dashboard with pass/fail metrics
- HTML email reports with detailed findings
- 30-day report retention policy with automatic cleanup
- Warning threshold tracking and escalation
- Comprehensive error handling and logging
- Designed for Task Scheduler execution (unattended)
- SMTP email delivery with configurable recipients
- Report archival and organization
- Success/failure tracking across all checks

**register-scheduled-tasks.ps1** - Bulk Task Scheduler registration
  - 🔗 [View Source](https://github.com/Carme99/bug-free-umbrella/blob/main/examples/automation/register-scheduled-tasks.ps1) | [Browse Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/examples/automation)

Features:
- Registers 7 automated monitoring tasks
- SYSTEM account configuration with highest privileges
- Network-aware scheduling (run only if network available)
- Battery-friendly settings (continue on battery)
- Start when available (missed schedule recovery)
- Email configuration for all reports
- Customizable task prefix for organization
- Existing task removal and recreation
- Task management command reference
- Next run time display and tracking
- Administrator privilege enforcement

#### 📖 Updated Documentation

**examples/README.md** - Updated with new script descriptions
  - 🔗 [View Documentation](https://github.com/Carme99/bug-free-umbrella/blob/main/examples/README.md)

**wiki/Home.md** - Three strategic RECIPES.md placements
  - 🔗 [View Wiki](https://github.com/Carme99/bug-free-umbrella/wiki/Home)

**wiki/_Sidebar.md** - Navigation enhancement
  - 🔗 [View Wiki](https://github.com/Carme99/bug-free-umbrella/wiki/_Sidebar)

### Benefits

**User Experience Improvements**
- Reduced learning curve with ready-to-run commands
- Quick access to common operations without searching documentation
- Real-world workflow examples for incident response and automation
- Task Scheduler integration eliminates manual daily operations
- Copy-paste convenience for rapid deployment

**Time Savings**
- Command cookbook reduces script discovery time from minutes to seconds
- Pre-built workflows eliminate need to create automation from scratch
- Task registration script saves 30+ minutes of manual configuration
- Automated reporting reduces daily manual checks from 2+ hours to 15 minutes

**Operational Excellence**
- Standardized incident response procedures
- Automated daily monitoring and reporting
- Consistent security investigation processes
- Proactive system health monitoring
- Compliance reporting automation

### Statistics

- **New Files**: 5 (1 documentation, 4 example workflows)
- **Updated Files**: 3 (README, wiki Home, wiki Sidebar)
- **Total Lines Added**: 2,229+ lines
- **Command Recipes**: 80+ copy-paste ready commands
- **Automation Tasks**: 7 scheduled monitoring tasks
- **Example Workflows**: 4 production-ready scripts
- **Documentation Enhancements**: Prominent wiki integration

[⬆️ Back to top](#-table-of-contents)

---

## [3.3.0] - 2026-01-08 🌧️ **"Rainfall"** - M365 User Management Toolkit

_For complete details of this version, see the full sample we created._

**📊 [Compare v3.2.0...v3.3.0](https://github.com/Carme99/bug-free-umbrella/compare/v3.2.0...v3.3.0)** | **📖 [Wiki: M365 Scripts](https://github.com/Carme99/bug-free-umbrella/wiki/Script-Catalog#microsoft-365-cloud-services)**

**Key Scripts Added:**
- **Get-M365UserInfo.ps1** - Interactive user management toolkit
  - 🔗 [View Source](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/collaboration/microsoft365/user-management/Get-M365UserInfo.ps1)
- **Manage-QuarantinedEmails.ps1** - Quarantine management
  - 🔗 [View Source](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/collaboration/microsoft365/exchange-online/Manage-QuarantinedEmails.ps1)
- **Get-UserMailboxPermissions.ps1** - Permission auditing
  - 🔗 [View Source](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/collaboration/microsoft365/exchange-online/Get-UserMailboxPermissions.ps1)
- **Get-UserMailRules.ps1** - Mail rules investigation
  - 🔗 [View Source](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/collaboration/microsoft365/exchange-online/Get-UserMailRules.ps1)

**Statistics**: 5 new scripts, 2,800+ lines, M365 scripts: 15 → 19 (+27%)

[⬆️ Back to top](#-table-of-contents)

---

## [3.2.0] - 2026-01-06 🌧️ **"Sprinkle"** - M365 Apps Management

**📊 [Compare v3.1.0...v3.2.0](https://github.com/Carme99/bug-free-umbrella/compare/v3.1.0...v3.2.0)**

### Added

#### 📦 M365 Apps Management

**Update-M365Apps.ps1** - Comprehensive M365 Apps update manager for environments without Microsoft AutoUpdate
  - 🔗 [View Source](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/collaboration/microsoft365/office-apps/Update-M365Apps.ps1) | [Browse Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/collaboration/microsoft365/office-apps)

Features:
- Automatic detection of installed M365 Apps with version comparison against Microsoft CDN
- Real-time update checking using Microsoft Office Releases API
- Interactive update channel selection (Monthly, Enterprise, Semi-Annual, Beta, LTSB)
- Local update download using Office Deployment Tool
- Automated installation with progress tracking and exit code handling
- Post-installation cleanup to reclaim disk space
- Rotating log files with automatic retention management (30-day default)
- Support for fresh installations on new systems
- Color-coded console output for interactive technician workflows
- Channel switching with registry CDNBaseUrl updates
- User confirmations for download, install, and cleanup operations
- Available in both `scripts/collaboration/microsoft365/office-apps/` and `scripts/cloud/azure/avd/` (reference copy for AVD workflows)

**Example ODT Configuration Files** - 5 ready-to-use XML templates
  - 🔗 [Browse Templates](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/collaboration/microsoft365/office-apps)

Templates include:
- `example-install-monthly-enterprise.xml` - Recommended for most organizations
- `example-install-semi-annual.xml` - Maximum stability for regulated industries
- `example-install-current-channel.xml` - Fastest updates for early adopters
- `example-install-avd-shared.xml` - Azure Virtual Desktop with SharedComputerLicensing
- `example-install-minimal.xml` - Minimal installation for limited disk space

**Comprehensive Troubleshooting Guide**
  - 🔗 [View Documentation](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/collaboration/microsoft365/office-apps/TROUBLESHOOTING.md)

Includes:
- 10 major troubleshooting sections with detailed solutions
- Prerequisites issues (ODT not found, XML missing, permissions)
- Network & connectivity (proxy settings, firewall, CDN access)
- Complete ODT exit code reference
- Installation failures handling
- Channel switching issues
- Registry & detection problems
- Activation & licensing guidance
- Performance & disk space optimization
- Log file analysis
- Common error messages with solutions

**Enhanced Documentation**
  - 🔗 [View Documentation](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/collaboration/microsoft365/office-apps/README.md)

**Comprehensive Pester test suite**
  - 🔗 [View Tests](https://github.com/Carme99/bug-free-umbrella/blob/main/Tests/Collaboration/Update-M365Apps.Tests.ps1)

Test coverage:
- 100+ test cases covering script structure, documentation, functions, error handling, security
- Validates all 11 primary functions and logging infrastructure
- Tests channel GUID mapping for 8 update channels
- Verifies registry operations, ODT integration, API interactions
- Validates user interaction prompts and color-coded output

[⬆️ Back to top](#-table-of-contents)

---

## [3.2.0] - 2026-01-06 🌧️ **"Monsoon"** - Device Health & Uptime Monitoring

**📊 [Compare v3.1.0...v3.2.0](https://github.com/Carme99/bug-free-umbrella/compare/v3.1.0...v3.2.0)**

### Added

#### 📊 Device Health & Uptime Monitoring (+8 remediations, 16 PowerShell files)

**Comprehensive Health Reporting** (1 remediation)

**Check-DeviceHealthScore** - Calculate weighted 0-100 health score from 8 categories
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Check-DeviceHealthScore)

Categories:
- Uptime health (10% weight)
- Crash stability (20% weight)
- Application stability (10% weight)
- Service health (10% weight)
- System errors (15% weight)
- Hardware health (20% weight)
- Boot performance (5% weight)
- Security posture (10% weight)
- JSON export for reporting dashboards
- Prioritized improvement plans

**Uptime & Reboot Tracking** (2 remediations)

**Check-DeviceUptime** - Monitor excessive uptime and pending reboots
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Check-DeviceUptime)

**Check-UnexpectedReboots** - Track crashes, blue screens, and system failures
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Check-UnexpectedReboots)

**System Stability & Performance** (3 remediations)

**Check-SystemStabilityIndex** - Windows Reliability Monitor scoring
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Check-SystemStabilityIndex)

**Check-BootPerformance** - Boot and shutdown time monitoring
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Check-BootPerformance)

**Check-ServiceFailures** - Service crash and failure monitoring
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Check-ServiceFailures)

**Application & Event Monitoring** (2 remediations)

**Check-ApplicationCrashes** - Application failure tracking
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Check-ApplicationCrashes)

**Check-SystemEventErrors** - Critical system event monitoring
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Check-SystemEventErrors)

**Hardware Health** (1 remediation)

**Check-HardwareErrors** - Hardware failure detection
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Check-HardwareErrors)

### Statistics

- **New Scripts**: 8 proactive remediations (16 PowerShell files)
- **Total Remediations**: 50 detect/remediate pairs (100 PowerShell files)
- **Lines of Code Added**: ~1,600
- **New Capabilities**: Comprehensive health scoring, uptime reporting, crash analytics

[⬆️ Back to top](#-table-of-contents)

---

## [3.1.0] - 2026-01-05 🌧️ **"Shower"** - Expanded Intune Operations

> **Focus**: Comprehensive expansion of Intune management and proactive remediation capabilities

**📊 [Compare v3.0.3...v3.1.0](https://github.com/Carme99/bug-free-umbrella/compare/v3.0.3...v3.1.0)**

### Added

#### 🆕 Proactive Remediations (+10 scripts, 20 PowerShell files)

**Performance & Reliability** (5 remediations)

**Fix-WindowsPerformanceRecorder** - Stop stuck WPR/ETW tracing sessions causing high CPU
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Fix-WindowsPerformanceRecorder)

**Fix-TaskSchedulerCorruption** - Repair Task Scheduler service and database issues
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Fix-TaskSchedulerCorruption)

**Check-MicrosoftStoreAppsHealth** - Detect and fix AppX package registration errors
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Check-MicrosoftStoreAppsHealth)

**Fix-SystemFileCorruption** - Run DISM RestoreHealth and SFC to repair corrupted system files
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Fix-SystemFileCorruption)

**Fix-WindowsUpdateRebootPending** - Clear stuck reboot pending flags (>7 days old)
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Fix-WindowsUpdateRebootPending)

**Hardware & Diagnostics** (3 remediations)

**Check-PageFileConfiguration** - Verify page file is enabled and properly sized
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Check-PageFileConfiguration)

**Check-MemoryDiagnostics** - Detect RAM errors and schedule Windows Memory Diagnostic
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Check-MemoryDiagnostics)

**Check-BatteryHealth** - Monitor laptop battery degradation (<70% capacity threshold)
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Check-BatteryHealth)

**Licensing & Activation** (2 remediations)

**Check-WindowsActivationGracePeriod** - Alert when activation expiring within 30 days
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Check-WindowsActivationGracePeriod)

### Changed

**Proactive Remediation Library**
- Total remediations: 32 → 42 (+31%)
- Storage & Performance category: 7 → 9 scripts
- System Services category: 8 → 13 scripts
- Apps & Licensing category: 4 → 6 scripts
- Enhanced hardware monitoring and diagnostics coverage
- Added proactive activation monitoring

### Statistics

- **New Scripts**: 10 proactive remediations (20 PowerShell files)
- **Total Remediations**: 42 detect/remediate pairs (84 PowerShell files)
- **Lines of Code Added**: ~1,800

[⬆️ Back to top](#-table-of-contents)

---

## [3.0.3] - 2026-01-04 ☔ **"Drizzle"** - Wiki Version Reference Fix

> **Focus**: Correct outdated version references in wiki documentation

**📊 [Compare v3.0.2...v3.0.3](https://github.com/Carme99/bug-free-umbrella/compare/v3.0.2...v3.0.3)**

### Fixed

**Wiki Version References** - Updated outdated v2.1.0 references to correct v3.0.2
  - 🔗 [View Wiki](https://github.com/Carme99/bug-free-umbrella/wiki)

Files updated:
- **wiki/Home.md**: Updated all version references to v3.0.2
- **wiki/Script-Catalog.md**: Updated 3 version references to v3.0.2
- **wiki/WIKI-SETUP.md**: Updated footer metadata to v3.0.2
- **wiki/Getting-Started.md**: Updated footer metadata to v3.0.2

### Statistics

- **Files Modified**: 5 (CHANGELOG.md + 4 wiki documentation files)
- **Version References Updated**: 11+ references corrected across all wiki files
- **Wiki Version**: 1.0.0 → 1.1.0

[⬆️ Back to top](#-table-of-contents)

---

## [3.0.2] - 2026-01-03 ☔ **"Drizzle"** - Documentation Cleanup

> **Focus**: Remove deprecated documentation and fix all broken links

**📊 [Compare v3.0.1...v3.0.2](https://github.com/Carme99/bug-free-umbrella/compare/v3.0.1...v3.0.2)**

### Removed

**5 Deprecated Documentation Files** (~3,988 lines removed)
- `docs/NAVIGATION.md` - Migrated to wiki
- `docs/SCRIPT-EXAMPLES.md` - Migrated to wiki
- `docs/WORKFLOWS.md` - Migrated to wiki
- `docs/TROUBLESHOOTING.md` - Migrated to wiki
- `docs/INTUNE-SYNC-README.md` - Migrated to wiki

### Fixed

**44 Broken or Outdated Documentation References**
- **28 Critical Broken Wiki Links**: Fixed all references in wiki files
- **14 Outdated References**: Updated to reflect current file locations
- **2 Script READMEs**: Updated to point to wiki URLs

### Statistics

- **Files Deleted**: 5
- **Files Modified**: 10
- **Lines Removed**: 3,988
- **Broken Links Fixed**: 44

[⬆️ Back to top](#-table-of-contents)

---

## [3.0.1] - 2025-12-31 ☔ **"Drizzle"** - Bug Fix Release

> **Focus**: Critical bug fixes and code quality improvements

**📊 [Compare v3.0.0...v3.0.1](https://github.com/Carme99/bug-free-umbrella/compare/v3.0.0...v3.0.1)**

### Fixed

#### Security & Compliance Scripts

> **⚠️ CRITICAL**: Complete rewrite to fix broken functionality

**Test-CISBenchmark.ps1 v2.0.0** - Complete rewrite to fix broken functionality
  - 🔗 [View Source](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/security/compliance/frameworks/Test-CISBenchmark.ps1) | [Browse Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/security/compliance/frameworks)

Critical fixes:
- **CRITICAL**: Replaced non-existent `Get-LocalGroupPolicy` cmdlet with working alternatives
- **NEW**: Implemented `Get-SecurityPolicy` helper function using `secedit.exe`
- **NEW**: Implemented `Test-CISControl` helper function for consistent test execution

**Expanded Test Coverage** (3 → 15+ CIS controls):
- Password Policies (6 controls)
- Account Lockout Policies (3 controls)
- Audit Policies (6+ controls)

Enhanced features:
- Added `#Requires -Version 5.1` directive
- Added `#Requires -RunAsAdministrator` directive
- Added comprehensive comment-based help
- Enhanced HTML report with detailed control results
- Proper exit codes (0 for success, 1 for failures)
- Increased from 61 lines to 481 lines of production-ready code

### Statistics

- **Files Modified**: 1
- **Lines Changed**: +461, -40
- **Version Bump**: Test-CISBenchmark.ps1 v1.0 → v2.0.0
- **CIS Controls Added**: 12 new controls tested

### Related Changes

See [v2.1.0](#210---2025-12-29--rainbow---quality--reliability-release) for related security improvements.

[⬆️ Back to top](#-table-of-contents)

---

## [3.0.0] - 2025-12-30 🌪️ **"Hurricane"** - Repository Restructure

> **⚠️ BREAKING CHANGE**: Complete repository reorganization with technology-based hierarchy

**📊 [Compare v2.2.0...v3.0.0](https://github.com/Carme99/bug-free-umbrella/compare/v2.2.0...v3.0.0)** | **📖 [Migration Guide](https://github.com/Carme99/bug-free-umbrella/wiki/Migration-Guide)**

### Restructuring Overview

Reorganized 260+ scripts from 20 flat categories into 7 technology-based domains for improved navigation and discoverability.

### New Structure

**7 Technology Domains:**
- **cloud/** - Cloud platforms (Azure, AWS, Containers)
  - 🔗 [Browse Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/cloud)
- **endpoints/** - Endpoint management (Intune, Devices)
  - 🔗 [Browse Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints)
- **infrastructure/** - On-premises systems (Windows, Linux, Network, Virtualization, Web, Print)
  - 🔗 [Browse Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/infrastructure)
- **security/** - Security & compliance (Compliance, Hardening, Monitoring)
  - 🔗 [Browse Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/security)
- **automation/** - DevOps & automation (CI/CD, IaC)
  - 🔗 [Browse Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/automation)
- **collaboration/** - M365 & communication (Microsoft 365, Email)
  - 🔗 [Browse Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/collaboration)
- **data/** - Data management (Databases, APIs)
  - 🔗 [Browse Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/data)

### Migration Mapping

| Old Location | New Location |
|--------------|--------------|
| `scripts/intune/` | [`scripts/endpoints/intune/`](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/intune) |
| `scripts/device-management/` | [`scripts/endpoints/devices/`](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices) |
| `scripts/server/` | [`scripts/infrastructure/windows/`](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/infrastructure/windows) |
| `scripts/m365/` | [`scripts/collaboration/microsoft365/`](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/collaboration/microsoft365) |
| `scripts/cloud-infrastructure/` | [`scripts/cloud/`](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/cloud) |

### Added

**Domain Documentation** - 7 new README files
  - 🔗 [View All Domains](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts)

### Breaking Changes

> **⚠️ BREAKING**: All script paths have changed

**All script paths have changed.** External references to scripts must be updated:
- Documentation referencing old paths
- Automation scripts calling these scripts
- Wiki pages with script links
- Scheduled tasks with script paths

**No symlinks created.** This is a clean break to avoid confusion.

### Statistics

- **Scripts moved:** 260+
- **Directories restructured:** 20 categories → 7 domains
- **Git history:** Preserved for all files
- **Documentation updates:** 30+ files updated
- **New READMEs:** 7 domain-level guides created

[⬆️ Back to top](#-table-of-contents)

---

## [2.2.0] - 2025-12-30 🌧️ **"Shower"** - Navigation & Usability Release

> **Focus**: Improved repository navigation, discoverability, and user experience

**📊 [Compare v2.1.0...v2.2.0](https://github.com/Carme99/bug-free-umbrella/compare/v2.1.0...v2.2.0)**

### Added

**QUICK_START.md** - Comprehensive role-based quick start guide
  - 🔗 [View Documentation](https://github.com/Carme99/bug-free-umbrella/blob/main/QUICK_START.md)

Contents:
- 7 role-specific entry points
- "I need to..." task-based navigation tables
- Common workflow examples by role
- First-time setup instructions
- Prerequisites checklist and testing guidelines

**examples/** - New directory with real-world workflow examples
  - 🔗 [Browse Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/examples)

**Enhanced Issue Templates** - 4 new templates
  - 🔗 [View Templates](https://github.com/Carme99/bug-free-umbrella/tree/main/.github/ISSUE_TEMPLATE)

### Statistics

- **New files created**: 12
- **Enhanced files**: 2
- **Documentation quality**: Significantly improved

[⬆️ Back to top](#-table-of-contents)

---

## [2.1.0] - 2025-12-29 🌈 **"Rainbow"** - Quality & Reliability Release

> **Focus**: Code quality, reliability improvements, and bug fixes

**📊 [Compare v2.0.0...v2.1.0](https://github.com/Carme99/bug-free-umbrella/compare/v2.0.0...v2.1.0)**

### Added

**Monitor-ServerHealth.ps1** - Massive expansion with 13 major new capabilities
  - 🔗 [View Source](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/infrastructure/windows/monitoring/Monitor-ServerHealth.ps1) | [Browse Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/infrastructure/windows/monitoring)

New features:
- Interactive Mode with 4 quick presets
- Disk I/O Performance monitoring
- Windows Update Status checking
- Security Monitoring
- Network Connectivity tests
- Certificate Monitoring
- Scheduled Tasks monitoring
- Application Monitoring (IIS, SQL Server, Hyper-V)
- Advanced Performance Metrics
- JSON Export
- Email Reporting
- Progress Indicators
- Enhanced Error Handling

Script grew from 541 to ~1,928 lines with backward compatibility maintained.

### Fixed

> **🔒 SECURITY**: Critical syntax and security fixes

**Critical Syntax Errors:**
- **Invoke-SecurityComplianceScan.ps1**: Fixed space in filename
  - 🔗 [View Source](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/security/compliance/Invoke-SecurityComplianceScan.ps1)
- **Get-KubernetesHealthCheck.ps1**: Fixed variable interpolation
  - 🔗 [View Source](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/cloud/containers/Get-KubernetesHealthCheck.ps1)

**High-Severity Improvements:**
- **Fix-BitLockerNotEscrowedKeys**: Added robust error handling
  - 🔗 [View Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations/Fix-BitLockerNotEscrowedKeys)

### Statistics

- **Files modified**: 19 PowerShell scripts
- **Critical syntax errors fixed**: 2
- **High-severity issues fixed**: 4
- **Documentation blocks added**: 6 scripts
- **Performance optimizations**: 1 major fix

### Related Changes

See [v3.0.1](#301---2025-12-31--drizzle---bug-fix-release) for continued bug fixes.

[⬆️ Back to top](#-table-of-contents)

---

## [2.0.0] - 2025-12-28 ⛈️ **"Thunderstorm"** - Regional Settings Major Release

> **Focus**: Comprehensive M365 regional settings management suite

**📊 [Compare v1.0.0...v2.0.0](https://github.com/Carme99/bug-free-umbrella/compare/v1.0.0...v2.0.0)**

### Added

#### M365 Regional Settings Suite (14 New Scripts)

Complete solution for managing regional settings across Microsoft 365.

**Key Scripts:**
- **Set-UserLanguageSettings.ps1** - M365 user account language settings
  - 🔗 [View Source](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/collaboration/microsoft365/regional-settings/Set-UserLanguageSettings.ps1)
- **Set-MailboxRegionalSettings.ps1** - Exchange Online mailbox configuration
  - 🔗 [View Source](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/collaboration/microsoft365/regional-settings/Set-MailboxRegionalSettings.ps1)
- **Set-SiteRegionalSettings.ps1** - SharePoint site settings
  - 🔗 [View Source](https://github.com/Carme99/bug-free-umbrella/blob/main/scripts/collaboration/microsoft365/regional-settings/Set-SiteRegionalSettings.ps1)
- Plus 11 more regional settings scripts

#### Proactive Remediations (6 New Scripts - 3 Pairs)

Windows client regional settings management:
  - 🔗 [Browse Folder](https://github.com/Carme99/bug-free-umbrella/tree/main/scripts/endpoints/devices/proactive-remediations)

### Statistics

- **M365 Scripts**: 12 → 19 (+7 scripts, +58%)
- **Proactive Remediations**: 11 → 14 pairs (+3 pairs, +27%)
- **Total Scripts**: 246 → 260+ (+14 scripts)

[⬆️ Back to top](#-table-of-contents)

---

## [1.0.0] - 2025-12-27 ⛈️ **"Thunderstorm"** - Initial Production Release

> **Focus**: Comprehensive enterprise IT management toolkit

**📊 [View Release](https://github.com/Carme99/bug-free-umbrella/releases/tag/v1.0.0)** | **📖 [Wiki Home](https://github.com/Carme99/bug-free-umbrella/wiki)**

### Initial Release

**Complete enterprise IT automation toolkit with 245+ scripts across 20 categories:**

- Microsoft 365 Cloud Services (12 scripts)
- Intune Management (18+ scripts)
- Proactive Remediations (11 pairs - 22 scripts)
- Winget Application Updates (40+ templates)
- DevOps & CI/CD (4 scripts)
- Cloud Infrastructure (15+ scripts)
- Security & Compliance (13 scripts)
- Server Management (30+ scripts)
- Web Services (4 scripts)
- Database Management (4 scripts)
- Infrastructure as Code (2 scripts)

### Documentation

Comprehensive documentation suite:
  - 🔗 [Wiki Home](https://github.com/Carme99/bug-free-umbrella/wiki)
  - 🔗 [Contributing Guide](https://github.com/Carme99/bug-free-umbrella/blob/main/CONTRIBUTING.md)
  - 🔗 [Security Policy](https://github.com/Carme99/bug-free-umbrella/blob/main/SECURITY.md)

### Statistics

- **Total Scripts**: 245+
- **Script Categories**: 20
- **Proactive Remediations**: 11 pairs (22 scripts)
- **Lines of Code**: 50,000+

[⬆️ Back to top](#-table-of-contents)

---

## [0.9.0] - 2025-12-15 ☔ **"Drizzle"** - Initial Setup

### Initial Repository Setup

- Repository structure established
- Basic script organization and categorization
- Initial documentation framework
- License and governance files (Apache 2.0)

[⬆️ Back to top](#-table-of-contents)

---

## Version History Summary

| Version | Date | Codename | Type | Major Changes |
|---------|------|----------|------|---------------|
| **3.7.0** | 2026-01-21 | 🌧️ Shower | Minor | Winget security updates, .NET runtime fixes |
| **3.6.0** | 2026-01-16 | 🌧️ Shower | Minor | Intune device management scripts |
| **3.5.0** | 2026-01-15 | 🌧️ Shower | Minor | AVD image builder enhancements |
| **3.4.0** | 2026-01-09 | 🌈 Rainbow | Minor | Documentation & examples |
| **3.3.0** | 2026-01-08 | 🌧️ Rainfall | Minor | M365 user management toolkit |
| **3.2.0** | 2026-01-06 | 🌧️ Sprinkle/Monsoon | Minor | M365 apps & device health |
| **3.1.0** | 2026-01-05 | 🌧️ Shower | Minor | Expanded Intune operations |
| **3.0.3** | 2026-01-04 | ☔ Drizzle | Patch | Wiki version fix |
| **3.0.2** | 2026-01-03 | ☔ Drizzle | Patch | Documentation cleanup |
| **3.0.1** | 2025-12-31 | ☔ Drizzle | Patch | CIS Benchmark fixes |
| **3.0.0** | 2025-12-30 | 🌪️ Hurricane | Breaking | Repository restructure |
| **2.2.0** | 2025-12-30 | 🌧️ Shower | Minor | Navigation improvements |
| **2.1.0** | 2025-12-29 | 🌈 Rainbow | Minor | Quality & reliability |
| **2.0.0** | 2025-12-28 | ⛈️ Thunderstorm | Major | Regional settings suite |
| **1.0.0** | 2025-12-27 | ⛈️ Thunderstorm | Major | Initial production release |
| **0.9.0** | 2025-12-15 | ☔ Drizzle | Patch | Repository initialization |

---

## Upgrade Notes

### Upgrading to 3.7.0 (Shower)
- ✅ **No breaking changes** - fully backward compatible
- 🔧 **New scripts**: Check-OutdatedCriticalApps proactive remediation
- 🔧 **Updated**: Update-DotNetRuntimes.ps1 v2.6 - all menu options now functional

### Upgrading to 3.0.0 (Hurricane)

> **⚠️ BREAKING CHANGES** - All script paths have changed

- 📂 Scripts reorganized: 20 flat categories → 7 technology domains
- 🔄 **Action required**: Update any references to script paths
- 📖 See [Migration Guide](https://github.com/Carme99/bug-free-umbrella/wiki/Migration-Guide) for path mappings
- ✅ Git history preserved for all files

**Quick Migration:**
```powershell
# Old path
.\scripts\intune\Get-IntuneDeviceCompliance.ps1

# New path
.\scripts\endpoints\intune\Get-IntuneDeviceCompliance.ps1
```

### Other Versions
- **v2.x → v3.x (pre-3.0.0)**: No breaking changes, fully backward compatible
- **v1.x → v2.x**: No breaking changes, opt-in new features
- **v0.9 → v1.0**: Initial production release

---

## Deprecation Notices

**None at this time.**

All scripts and features are actively maintained and supported.

---

## Contributing

We welcome contributions! Please see:
- 🔗 [CONTRIBUTING.md](https://github.com/Carme99/bug-free-umbrella/blob/main/CONTRIBUTING.md) for development guidelines
- 🔗 [CODE_OF_CONDUCT.md](https://github.com/Carme99/bug-free-umbrella/blob/main/CODE_OF_CONDUCT.md) for community guidelines
- 🔗 [SECURITY.md](https://github.com/Carme99/bug-free-umbrella/blob/main/SECURITY.md) for security vulnerability reporting

---

## Recognition

Scripts in this repository were created with the assistance of **[Claude Code](https://github.com/anthropics/claude-code)**, Anthropic's official CLI for Claude AI.

---

**Note**: This changelog follows [Keep a Changelog](https://keepachangelog.com/) principles.

For detailed commit history, see [Git Log](https://github.com/Carme99/bug-free-umbrella/commits/main).

**Last Updated**: 2026-01-25

[⬆️ Back to top](#-table-of-contents)
