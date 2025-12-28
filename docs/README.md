# Bug-Free Umbrella - Complete Documentation

> **⚠️ IMPORTANT NOTICE**: The vast majority of scripts in this repository have not been thoroughly tested in production environments. Please test all scripts in a non-production environment first and validate the results before relying on this data for operational decisions.

A comprehensive collection of PowerShell scripts for Windows system administration, cloud infrastructure, DevOps automation, and Microsoft 365 management.

## 📚 Documentation Index

This documentation hub provides detailed information about all scripts and tools in the bug-free-umbrella repository.

### Quick Navigation

- **[Main README](../README.md)** - Repository overview and quick start
- **[Script Examples & Outputs](SCRIPT-EXAMPLES.md)** - Detailed examples with sample outputs
- **[End-to-End Workflows](WORKFLOWS.md)** - Step-by-step guides for common scenarios
- **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Common issues and solutions
- **[Intune Sync Guide](INTUNE-SYNC-README.md)** - User group to device group synchronization

### Script Categories

**Cloud & Infrastructure**
- **[API Management](../scripts/api-management/)** - Azure APIM & API health monitoring (2 scripts)
- **[Cloud Infrastructure](../scripts/cloud-infrastructure/)** - Azure & AWS resource management (5+ scripts)
- **[Container Management](../scripts/container-management/)** - Docker & Kubernetes monitoring (3 scripts)
- **[Infrastructure as Code](../scripts/infrastructure-as-code/)** - Terraform & Bicep testing (2 scripts)
- **[Virtualization](../scripts/virtualization/)** - Hyper-V & VMware management (3 scripts)

**DevOps & Development**
- **[DevOps CI/CD](../scripts/devops-cicd/)** - Azure DevOps, GitHub Actions, GitLab CI monitoring (4 scripts)
- **[Database Management](../scripts/database/)** - SQL Server, MySQL, PostgreSQL, MongoDB (4 scripts)

**Microsoft 365 & Enterprise**
- **[Microsoft 365 Cloud Services](../scripts/m365/)** - Exchange Online, Teams, SharePoint, Azure AD (12 scripts)
- **[Intune Management](../scripts/intune/)** - Comprehensive Intune administration toolkit (18+ scripts)
- **[Email Services](../scripts/email-services/)** - Exchange Server health and management (4 scripts)

**Security & Compliance**
- **[Advanced Security](../scripts/advanced-security/)** - Multi-framework compliance scanning (1 script)
- **[Security & Compliance](../scripts/security-compliance/)** - Security auditing and compliance (12 scripts)

**Server & Infrastructure**
- **[Server Management](../scripts/server/)** - Windows Server administration tools (30+ scripts)
- **[Web Services](../scripts/web-services/)** - IIS health monitoring and optimization (4 scripts)
- **[Linux Server](../scripts/linux-server/)** - Linux server management scripts

**Monitoring & Operations**
- **[Monitoring](../scripts/monitoring/)** - System health checks and performance monitoring (6 scripts)
- **[Network Management](../scripts/network-management/)** - Network diagnostics and troubleshooting (3 scripts)
- **[Print Management](../scripts/print-management/)** - Print server monitoring (1 script)

**Device Management**
- **[Proactive Remediations](../scripts/device-management/proactive-remediations/)** - Auto-fix common issues (11 pairs)
- **[Winget Updates](../scripts/device-management/winget-updates/)** - Application auto-update management (40+ apps)
- **[Utilities](../scripts/utilities/)** - System utilities and helper scripts (3 scripts)

---

## 🚀 Quick Start Guide

New to this repository? Follow these steps to get started:

1. **Choose Your Focus Area**
   - Managing DevOps pipelines? Start with [DevOps CI/CD Scripts](../scripts/devops-cicd/)
   - Managing cloud infrastructure? Check out [Cloud Infrastructure Scripts](../scripts/cloud-infrastructure/)
   - Managing Intune devices? Start with [Intune Management Scripts](../scripts/intune/)
   - Managing servers? Check out [Server Management Scripts](../scripts/server/)
   - Want to automate common fixes? Explore [Proactive Remediations](../scripts/device-management/proactive-remediations/)

2. **Check Prerequisites**
   - PowerShell 5.1 or later (PowerShell 7+ recommended)
   - Administrator privileges for most scripts
   - Microsoft Graph SDK for Intune scripts: `Install-Module Microsoft.Graph -Scope CurrentUser`
   - Azure PowerShell for Azure scripts: `Install-Module Az -Scope CurrentUser`
   - AWS Tools for AWS scripts: `Install-Module AWS.Tools.Common -Scope CurrentUser`

3. **Review Examples**
   - See [Script Examples](SCRIPT-EXAMPLES.md) for detailed usage examples with expected outputs
   - Follow [Workflows](WORKFLOWS.md) for complete end-to-end scenarios

4. **Test Safely**
   - Always test scripts in a non-production environment first
   - Review script contents before running
   - Check [Troubleshooting Guide](TROUBLESHOOTING.md) if you encounter issues

---

## Overview

The bug-free-umbrella repository contains production-ready PowerShell scripts designed for IT administrators managing Windows environments, cloud infrastructure, DevOps pipelines, and Microsoft 365 services. All scripts follow best practices for detection/remediation patterns and enterprise deployment.

### What's Included

#### Cloud & DevOps Management
- **API Management** - Azure APIM health monitoring, API endpoint testing, SSL validation
- **Cloud Infrastructure** - Azure & AWS resource management, cost analysis, security monitoring
- **Container Management** - Docker & Kubernetes health checks, resource cleanup
- **DevOps CI/CD** - Pipeline monitoring for Azure DevOps, GitHub Actions, GitLab CI
- **Infrastructure as Code** - Terraform & Bicep validation, security scanning
- **Database Management** - SQL Server, MySQL, PostgreSQL, MongoDB health monitoring

#### Microsoft 365 & Enterprise
- **Microsoft 365 Services** - Exchange Online, Teams, SharePoint, Azure AD management
- **Intune Management** - Device compliance, application management, policy enforcement
- **Email Services** - Exchange Server health monitoring and management

#### Security & Compliance
- **Advanced Security** - Multi-framework compliance scanning (CIS, NIST, PCI-DSS, HIPAA)
- **Security Auditing** - Baseline verification, access auditing, certificate management
- **Compliance Reporting** - Automated compliance checks and reporting

#### Server & Infrastructure Management
- **Server Management** - Windows Server administration, AD management, GPO reporting
- **Web Services** - IIS health monitoring, log analysis, security hardening
- **Virtualization** - Hyper-V & VMware management
- **Network Management** - Connectivity testing, diagnostics, troubleshooting
- **Monitoring** - System health checks, performance trending, capacity planning

#### Device Management & Automation
- **Proactive Remediations** - Auto-fix disk space, temp files, security settings
- **Application Updates** - Winget-based automatic updates for 40+ applications
- **Device Maintenance** - Uptime monitoring, BitLocker backup, driver management

---

## Repository Structure

```
bug-free-umbrella/
├── docs/                              # Documentation (you are here)
│   ├── README.md                      # This file - documentation index
│   ├── INTUNE-SYNC-README.md          # Intune user-to-device sync guide
│   ├── TROUBLESHOOTING.md             # Common issues and solutions
│   ├── WORKFLOWS.md                   # Step-by-step workflow guides
│   └── SCRIPT-EXAMPLES.md             # Detailed script examples with outputs
│
├── scripts/
│   ├── advanced-security/             # Multi-framework compliance scanning (1 script)
│   ├── api-management/                # Azure APIM & API health monitoring (2 scripts)
│   ├── cloud-infrastructure/          # Azure & AWS management (5+ scripts)
│   │   ├── azure/                     # Azure resource health, Key Vault, VMs
│   │   └── aws/                       # AWS resource inventory
│   ├── container-management/          # Docker & Kubernetes (3 scripts)
│   ├── database/                      # SQL Server, MySQL, PostgreSQL, MongoDB (4 scripts)
│   ├── device-management/             # Device management scripts
│   │   ├── proactive-remediations/    # Auto-fix scripts (11 pairs)
│   │   ├── winget-updates/            # Application update scripts (40+ apps)
│   │   ├── autopatch/                 # Windows Update policies
│   │   ├── bitlocker-backup/          # BitLocker key backup
│   │   ├── device-uptime/             # Uptime monitoring
│   │   ├── l16-driver-block/          # Lenovo L16 driver management
│   │   ├── adobe-rum/                 # Adobe Remote Update Manager
│   │   └── remove-sccm/               # SCCM client removal
│   ├── devops-cicd/                   # Azure DevOps, GitHub Actions, GitLab CI (4 scripts)
│   ├── email-services/                # Exchange Server management (4 scripts)
│   ├── infrastructure-as-code/        # Terraform & Bicep testing (2 scripts)
│   ├── intune/                        # Intune management tools (18+ scripts)
│   │   ├── reporting/                 # Compliance, status, and audit reports
│   │   ├── maintenance/               # Device cleanup and policy management
│   │   └── deployment/                # Packaging and deployment tools
│   ├── linux-server/                  # Linux server management
│   ├── m365/                          # Microsoft 365 cloud services (12 scripts)
│   │   ├── exchange-online/           # Exchange Online mailbox management
│   │   ├── teams/                     # Microsoft Teams administration
│   │   ├── sharepoint-onedrive/       # SharePoint and OneDrive
│   │   ├── azure-ad/                  # Azure AD / Entra ID
│   │   ├── compliance/                # Compliance Center
│   │   ├── power-platform/            # Power Platform management
│   │   └── defender/                  # Defender for Office 365
│   ├── monitoring/                    # System health checks and monitoring (6 scripts)
│   ├── network-management/            # Network diagnostics and troubleshooting (3 scripts)
│   ├── print-management/              # Print server management (1 script)
│   ├── security-compliance/           # Security auditing and compliance (12 scripts)
│   ├── server/                        # Windows Server management (30+ scripts)
│   │   ├── active-directory/          # AD user/service account auditing
│   │   ├── backup-recovery/           # Backup verification and restore points
│   │   ├── group-policy/              # GPO management and reporting
│   │   ├── monitoring/                # Server health and performance
│   │   ├── network/                   # Network configuration and connectivity
│   │   ├── security/                  # Security and certificates
│   │   ├── storage/                   # Disk and file management
│   │   ├── system/                    # System configuration and updates
│   │   └── user-management/           # User access and permissions
│   ├── utilities/                     # System utilities (3 scripts)
│   ├── virtualization/                # Hyper-V, VMware vSphere/ESXi (3 scripts)
│   └── web-services/                  # IIS web server management (4 scripts)
│
├── templates/                         # Reusable script templates
└── LICENSE
```

---

## Getting Started

### Prerequisites

#### For All Scripts
- **PowerShell 5.1 or later** (PowerShell 7+ recommended)
- **Administrator privileges** (most scripts require elevation)
- **Execution Policy** set appropriately

#### For Intune & M365 Scripts
- **Microsoft Graph PowerShell SDK**
  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser
  ```
- **Required Permissions**: DeviceManagementManagedDevices.Read.All (minimum)
- **Intune Administrator** or **Global Reader** role

#### For Cloud Scripts (Azure/AWS)
- **Azure PowerShell** (for Azure scripts)
  ```powershell
  Install-Module Az -Scope CurrentUser
  ```
- **AWS Tools for PowerShell** (for AWS scripts)
  ```powershell
  Install-Module AWS.Tools.Common -Scope CurrentUser
  ```

#### For Server Scripts
- **Windows Server 2016, 2019, or 2022**
- **Local Administrator** privileges
- No additional modules required (uses built-in cmdlets)

### Quick Start

1. **Clone or download the repository**
   ```powershell
   git clone https://github.com/Carme99/bug-free-umbrella.git
   cd bug-free-umbrella
   ```

2. **Choose your script category**
   - Browse to the appropriate folder (devops-cicd/, cloud-infrastructure/, intune/, server/, etc.)
   - Read the category README for script descriptions

3. **Run a script**
   ```powershell
   # View script help
   Get-Help .\ScriptName.ps1 -Detailed

   # Execute the script
   .\ScriptName.ps1 -Parameters
   ```

---

## Documentation Guides

### [Script Examples & Expected Outputs](SCRIPT-EXAMPLES.md)

Comprehensive guide showing:
- Exact command syntax for common scenarios
- Sample output with interpretation
- Exit codes and their meanings
- Execution time expectations
- Best practices for each script category

**When to use**: Learning how scripts behave, understanding expected results, troubleshooting unexpected output

### [End-to-End Workflows](WORKFLOWS.md)

Step-by-step guides for complete processes:
- Monthly compliance audits
- Automated winget updates deployment
- New server setup procedures
- Intune device cleanup
- BitLocker deployment and monitoring
- Proactive remediation deployment
- DevOps pipeline monitoring setup
- Cloud infrastructure auditing

**When to use**: Following a complete process from start to finish, onboarding new team members

### [Troubleshooting Guide](TROUBLESHOOTING.md)

Solutions for common issues:
- Microsoft Graph API authentication problems
- PowerShell execution policy errors
- Module installation issues
- Intune script deployment problems
- Winget update failures
- BitLocker backup issues
- Network and proxy problems
- Permission errors
- Cloud authentication issues

**When to use**: Resolving errors, investigating failures, fixing deployment issues

### [Intune Sync Guide](INTUNE-SYNC-README.md)

Detailed guide for synchronizing user groups to device groups:
- Use case and benefits
- Prerequisites and permissions
- Step-by-step configuration
- Interactive device selection
- Full sync process
- Troubleshooting

**When to use**: Implementing user-to-device group synchronization for autopatch or similar scenarios

---

## Common Use Cases

### Cloud & DevOps Operations

#### Monitor DevOps Pipelines
```powershell
cd scripts/devops-cicd

# Monitor Azure DevOps
.\Monitor-AzureDevOpsPipelines.ps1 -Organization "myorg" -Project "*" -PersonalAccessToken $pat

# Monitor GitHub Actions
.\Monitor-GitHubActions.ps1 -Owner "myorg" -Repository "*" -GitHubToken $token

# Monitor GitLab CI
.\Monitor-GitLabCI.ps1 -GitLabUrl "https://gitlab.com" -ProjectId "*" -PrivateToken $token
```

#### Cloud Infrastructure Management
```powershell
cd scripts/cloud-infrastructure

# Azure resource monitoring
.\azure\Monitor-AzureResources.ps1 -SubscriptionId "sub-id" -IncludeCostAnalysis

# AWS resource inventory
.\aws\Get-AWSResourceInventory.ps1 -Region "us-east-1" -IncludeEC2 -IncludeS3
```

#### API Health Monitoring
```powershell
cd scripts/api-management

# Test API endpoints
.\Test-APIHealth.ps1 -EndpointsFile ".\endpoints.json" -OutputFormat HTML

# Monitor Azure APIM
.\Monitor-AzureAPIManagement.ps1 -SubscriptionId "sub-id" -ServiceName "myapim"
```

### Microsoft 365 & Intune

#### Monthly Compliance Reporting
```powershell
# Intune device compliance
cd scripts\intune
.\Get-DeviceComplianceReport.ps1
.\Get-BitLockerStatus.ps1
.\Get-WindowsUpdateCompliance.ps1
.\Find-StaleDevices.ps1 -DaysInactive 90

# M365 cloud services
cd ..\m365
.\exchange-online\Get-MailboxHealth.ps1
.\azure-ad\Get-AzureADGuestAudit.ps1
.\teams\Get-TeamsReport.ps1

# Review generated reports on Desktop
```

### Server Management & Security

#### Security Audit
```powershell
cd scripts\security-compliance

# Run comprehensive security checks
.\Get-SecurityBaseline.ps1 -ExportReport
.\Get-LocalAdminAudit.ps1 -ExportReport
.\Test-SecurityFeatures.ps1 -ExportReport
.\Get-FailedLoginReport.ps1 -Hours 720 -ExportReport

# Advanced multi-framework compliance
cd ..\advanced-security
.\Invoke-SecurityComplianceScan.ps1 -Frameworks @("CIS", "NIST", "PCI-DSS")
```

#### Server Maintenance
```powershell
cd scripts\server

# Pre-change checklist
.\backup-recovery\Manage-RestorePoints.ps1 -Action Create -Description "Before updates"
.\Check-SystemIntegrity.ps1 -GenerateReport
.\group-policy\Backup-GroupPolicies.ps1 -BackupPath "D:\Backups"

# Post-change verification
.\Check-SystemIntegrity.ps1 -AutoRepair
.\monitoring\Get-SystemHealthCheck.ps1 -OutputFormat HTML
.\network\Test-NetworkConnectivity.ps1 -OutputFormat HTML
```

### Application Management

#### Deploy Winget Auto-Updates
```powershell
cd scripts\device-management\winget-updates

# Use pre-built scripts for popular apps
# or generate new ones from templates

# Example: Deploy Chrome updates
# Upload GoogleChrome/detect.ps1 and remediate.ps1 to Intune
# Configure as Proactive Remediation, schedule daily
```

#### Monitor Application Deployments
```powershell
cd scripts\intune
.\Get-AppInstallationStatus.ps1 -AppName "Google Chrome"
.\Get-AppInstallErrorReport.ps1 -Days 7 -ExportHTML
```

---

## Integration Scenarios

### DevOps + Cloud Monitoring
```powershell
# Monitor infrastructure and pipelines together
.\scripts\devops-cicd\Monitor-AzureDevOpsPipelines.ps1 -Organization "myorg" -Project "*"
.\scripts\cloud-infrastructure\azure\Monitor-AzureResources.ps1 -SubscriptionId "sub-id"
```

### Intune + Server Management
```powershell
# Sync user group to device group for Autopatch
.\scripts\utilities\Sync-UserGroupToPrimaryDeviceGroup.ps1

# Then monitor update compliance
.\scripts\intune\Get-WindowsUpdateCompliance.ps1 -IncludeAutoPatchInfo
```

### Security + Compliance Automation
```powershell
# Deploy security baseline enforcement
cd scripts\device-management\proactive-remediations\Check-SecurityBaseline
# Upload to Intune as Proactive Remediation

# Monitor compliance
cd ..\..\security-compliance
.\Get-SecurityBaseline.ps1 -ExportReport
```

---

## Best Practices

### Script Execution
1. **Always read script help first**
   ```powershell
   Get-Help .\ScriptName.ps1 -Detailed
   ```

2. **Test in non-production first**
   - Use test device groups
   - Verify expected behavior
   - Check for unintended side effects

3. **Monitor execution and outputs**
   - Review console output
   - Check generated reports
   - Verify expected results

### Automation
1. **Use appropriate scheduling**
   - Daily: System health, disk space, API monitoring
   - Weekly: Stale devices, profile cleanup, pipeline health
   - Monthly: Compliance audits, security reviews

2. **Centralize report storage**
   - Create consistent output paths
   - Implement retention policies
   - Archive for compliance

3. **Implement alerting**
   - Email reports for critical items
   - Integrate with monitoring systems
   - Set appropriate thresholds

### Security
1. **Secure script storage**
   - Use version control (Git)
   - Restrict access appropriately
   - Review changes before deployment

2. **Protect sensitive outputs**
   - Reports may contain PII
   - Secure report storage locations
   - Implement data retention policies

3. **Audit script usage**
   - Log script executions
   - Review who runs what
   - Track configuration changes

---

## Script Categories Quick Reference

| Category | Script Count | Primary Use Cases |
|----------|--------------|-------------------|
| **Advanced Security** | 1 | Multi-framework compliance scanning (CIS, NIST, PCI-DSS, HIPAA) |
| **API Management** | 2 | Azure APIM monitoring, API endpoint health testing |
| **Cloud Infrastructure** | 5+ | Azure & AWS resource management, cost analysis |
| **Container Management** | 3 | Docker & Kubernetes health checks and cleanup |
| **Database Management** | 4 | SQL Server, MySQL, PostgreSQL, MongoDB monitoring |
| **DevOps CI/CD** | 4 | Azure DevOps, GitHub Actions, GitLab CI pipeline monitoring |
| **Email Services** | 4 | Exchange Server health monitoring and management |
| **Infrastructure as Code** | 2 | Terraform & Bicep validation, security scanning |
| **Intune Management** | 18+ | Compliance reporting, app deployment, device maintenance |
| **Microsoft 365** | 11 | Exchange Online, Teams, SharePoint, Azure AD management |
| **Monitoring** | 6 | System health, battery health, performance trending |
| **Network Management** | 3 | Connectivity testing, diagnostics, network stack reset |
| **Print Management** | 1 | Print server health monitoring |
| **Security & Compliance** | 12 | Security auditing, baseline verification, access reviews |
| **Server Management** | 30+ | System maintenance, AD/GPO management, backup verification |
| **Virtualization** | 3 | Hyper-V, VMware vSphere/ESXi management |
| **Web Services** | 4 | IIS health monitoring, log analysis, security hardening |
| **Proactive Remediations** | 11 pairs | Auto-fix disk space, temp files, Windows Update, security |
| **Winget Updates** | 40+ apps | Application auto-updates via Intune remediations |
| **Utilities** | 3 | System utilities and helper scripts |

---

## Support and Resources

### Getting Help
1. **Check built-in help**
   ```powershell
   Get-Help .\ScriptName.ps1 -Full
   ```

2. **Review documentation**
   - Script Examples for usage patterns
   - Troubleshooting Guide for common issues
   - Workflow Guides for complete processes

3. **Check script comments**
   - All scripts include detailed comments
   - Parameter descriptions
   - Example usage

### Contributing
When adding new scripts or documentation:
- Follow existing patterns and structures
- Include comprehensive help
- Test thoroughly
- Update relevant README files
- Add examples to documentation

### Feedback
- Report issues with detailed error messages
- Suggest improvements
- Share success stories
- Contribute enhancements

---

## License

Licensed under the Apache License 2.0. See [LICENSE](../LICENSE) for details.

---

**Documentation Version**: 3.0
**Last Updated**: 2025-12-27
