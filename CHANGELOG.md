# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- PSScriptAnalyzer integration for code quality validation
- Pester testing framework with test coverage
- GitHub Actions CI/CD pipeline for automated validation
- Performance optimizations using parallel processing (PowerShell 7+)
- Comprehensive comment-based help documentation
- CONTRIBUTING.md with development guidelines
- SECURITY.md with security policy
- CODE_OF_CONDUCT.md for community guidelines

### Changed
- Set-UserLanguageSettings.ps1 now uses parallel processing for 50+ users
- Improved error handling across all regional settings scripts

## [2.0.0] - 2025-12-28

### Added

#### M365 Regional Settings Suite
- **Set-MailboxRegionalSettings.ps1**: Exchange Online mailbox regional settings management
- **Set-SiteRegionalSettings.ps1**: SharePoint site collection regional settings
- **Set-OneDriveRegionalSettings.ps1**: OneDrive personal site regional settings
- **Set-TeamsRegionalSettings.ps1**: Teams regional settings guidance
- **Set-PowerPlatformRegionalSettings.ps1**: Power Platform environment settings
- **Set-OrganizationDefaults.ps1**: Tenant-wide default settings for new users
- **Set-UserLanguageSettings.ps1**: M365 user account language settings (v1.1)

#### Proactive Remediations
- **region-language-settings**: Windows client regional settings management
- **keyboard-layout**: UK keyboard layout enforcement
- **language-pack-audit**: Unnecessary language pack removal

### Features
- Comprehensive UK standards support (en-GB, GMT, GBP)
- Audit and apply modes for all scripts
- Single and bulk operation support
- HTML and CSV reporting
- Compliant/non-compliant tracking
- Automatic remediation capabilities

### Documentation
- Updated M365 README with 7 new scripts
- Updated Proactive Remediations README with 3 new pairs
- Added Claude Code attribution across all documentation
- Updated main README with new script counts

### Statistics
- M365 Scripts: 12 → 19 (+7)
- Proactive Remediations: 11 → 14 pairs (+3)
- Total Scripts: 246+ → 260+ (+14)

## [1.0.0] - 2025-12-27

### Added

#### Microsoft 365 Cloud Services
- Exchange Online mailbox health monitoring
- Shared mailbox audit and reporting
- Microsoft Teams usage and compliance reporting
- OneDrive usage and storage analysis
- Azure AD guest user audit
- Azure AD license reporting
- Power Platform governance
- Defender for Office 365 threat reporting

#### Intune Management
- Device compliance reporting
- BitLocker status checking
- Windows Update compliance
- Stale device detection
- Application deployment status
- Policy deployment reporting
- Device cleanup utilities

#### Proactive Remediations
- Fix-DiskSpace: Low disk space remediation
- Fix-TempFiles: Temporary file cleanup
- Fix-StaleProfiles: Old user profile removal
- Fix-WindowsUpdateStuck: Windows Update reset
- Fix-BitLockerNotEscrowedKeys: BitLocker key backup
- Fix-TeamsCache: Teams cache cleanup
- Fix-PrintSpooler: Print spooler service fix
- Fix-DNSCache: DNS cache flush
- Fix-WindowsSearch: Search index rebuild
- Fix-BrokenShortcuts: Broken shortcut cleanup
- Check-SecurityBaseline: Security settings enforcement

#### Winget Updates
- 40+ application auto-update templates
- Remote access tools (TeamViewer, WinSCP)
- Development tools (VS Code, Git, Python)
- Productivity tools (7-Zip, Notepad++)
- Runtimes (C++ Redistributables, .NET, EdgeWebView2)

#### DevOps & Cloud
- Azure DevOps pipeline monitoring
- GitHub Actions workflow monitoring
- GitLab CI pipeline monitoring
- Azure resource health monitoring
- AWS resource inventory
- Docker and Kubernetes health checks
- API health monitoring
- Terraform and Bicep validation

#### Security & Compliance
- Multi-framework compliance scanning (CIS, NIST, PCI-DSS, HIPAA, SOC2, ISO27001)
- Security baseline verification
- Local admin auditing
- Failed login reporting
- Certificate expiration checking
- Security feature testing

#### Server Management
- Active Directory health and auditing
- Group Policy backup and reporting
- Backup status verification
- Disk space management
- Performance monitoring
- Network diagnostics
- System integrity checking

#### Web Services
- IIS health monitoring
- IIS log analysis with security threat detection
- IIS configuration optimization
- IIS configuration backup

### Documentation
- Comprehensive README files for all categories
- Script examples with expected outputs
- End-to-end workflow guides
- Troubleshooting guide
- Intune sync guide

## [0.9.0] - 2025-12-15

### Initial Repository Setup
- Repository structure established
- Basic script organization
- Initial documentation

---

## Version History Summary

| Version | Date | Major Changes |
|---------|------|---------------|
| 2.0.0 | 2025-12-28 | Regional settings management suite (14 new scripts) |
| 1.0.0 | 2025-12-27 | Initial comprehensive release (245+ scripts) |
| 0.9.0 | 2025-12-15 | Repository initialization |

## Upgrade Notes

### Upgrading to 2.0.0
- No breaking changes
- All existing scripts remain compatible
- New regional settings scripts available for opt-in use
- PowerShell 7+ recommended for parallel processing features

### Upgrading to 1.0.0
- Initial production release
- All scripts tested and documented
- No migration required for new installations

## Deprecation Notices

No deprecated features at this time.

## Planned Features

See [GitHub Issues](https://github.com/Carme99/bug-free-umbrella/issues) for planned enhancements and feature requests.

---

**Note**: This changelog follows [Keep a Changelog](https://keepachangelog.com/) principles.
For detailed commit history, see [Git Log](https://github.com/Carme99/bug-free-umbrella/commits/main).
