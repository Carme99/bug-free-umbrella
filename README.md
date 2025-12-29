# Bug-Free Umbrella

A comprehensive collection of PowerShell scripts for Windows system administration, cloud infrastructure, DevOps automation, and Microsoft 365 management.

> **⚠️ CRITICAL NOTICE - TESTING STATUS**
> **The vast majority of scripts in this repository have not been thoroughly tested in production environments.**
> Please test all scripts in a non-production environment first and validate the results before relying on this data for operational decisions.
> Always review scripts before execution and ensure you have proper backups.

## 📖 Quick Links

### Documentation
- **[Full Documentation](docs/README.md)** - Complete guide to all scripts and usage
- **[Script Examples & Expected Outputs](docs/SCRIPT-EXAMPLES.md)** - Detailed examples with sample outputs
- **[End-to-End Workflows](docs/WORKFLOWS.md)** - Step-by-step guides for common scenarios
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[Intune Sync Guide](docs/INTUNE-SYNC-README.md)** - User group to device group synchronization

### Script Categories

**Cloud & Infrastructure**
- **[API Management](scripts/api-management/)** - Azure APIM & API health monitoring
- **[Cloud Infrastructure](scripts/cloud-infrastructure/)** - Azure & AWS resource management
- **[Container Management](scripts/container-management/)** - Docker & Kubernetes monitoring
- **[Infrastructure as Code](scripts/infrastructure-as-code/)** - Terraform & Bicep testing
- **[Virtualization](scripts/virtualization/)** - Hyper-V & VMware management

**DevOps & Development**
- **[DevOps CI/CD](scripts/devops-cicd/)** - Azure DevOps, GitHub Actions, GitLab CI monitoring
- **[Database Management](scripts/database/)** - SQL Server, MySQL, PostgreSQL, MongoDB

**Microsoft 365 & Enterprise**
- **[Microsoft 365 Cloud Services](scripts/m365/)** - Exchange Online, Teams, SharePoint, Azure AD
- **[Intune Management](scripts/intune/)** - Comprehensive Intune administration toolkit
- **[Email Services](scripts/email-services/)** - Exchange Server health and management

**Security & Compliance**
- **[Advanced Security](scripts/advanced-security/)** - Multi-framework compliance scanning
- **[Security & Compliance](scripts/security-compliance/)** - Security auditing and compliance

**Server & Infrastructure**
- **[Server Management](scripts/server/)** - Windows Server administration tools
- **[Web Services](scripts/web-services/)** - IIS health monitoring and optimization
- **[Linux Server](scripts/linux-server/)** - Linux server management scripts

**Monitoring & Operations**
- **[Monitoring](scripts/monitoring/)** - System health checks and performance monitoring
- **[Network Management](scripts/network-management/)** - Network diagnostics and troubleshooting
- **[Print Management](scripts/print-management/)** - Print server monitoring

**Device Management**
- **[Proactive Remediations](scripts/device-management/proactive-remediations/)** - Auto-fix common issues
- **[Winget Update Templates](scripts/device-management/winget-updates/)** - Application auto-update setup
- **[Utilities](scripts/utilities/)** - System utilities and helper scripts

## 🆕 What's New

### Latest Expansion: DevOps, Security & Cloud Infrastructure

**20+ production-ready scripts across 6 new categories!**

#### New Categories

**🔄 DevOps & CI/CD** (4 scripts)
- Monitor-AzureDevOpsPipelines.ps1 - Azure DevOps pipeline health monitoring
- Monitor-GitHubActions.ps1 - GitHub Actions workflow monitoring
- Monitor-GitLabCI.ps1 - GitLab CI/CD pipeline monitoring
- Analyze-BuildPerformance.ps1 - Build performance analysis

**🌐 API Management** (2 scripts)
- Monitor-AzureAPIManagement.ps1 - Azure APIM service health
- Test-APIHealth.ps1 - Universal API endpoint testing

**⚙️ Infrastructure as Code** (2 scripts)
- Test-BicepTemplates.ps1 - Azure Bicep validation
- Test-TerraformConfiguration.ps1 - Terraform validation & security scanning

**🔒 Advanced Security** (1 script)
- Invoke-SecurityComplianceScan.ps1 - Multi-framework compliance (CIS, NIST, PCI-DSS, HIPAA, SOC2, ISO27001)

#### Expanded Categories

**☁️ Cloud Infrastructure** - Enhanced Azure/AWS scripts
- Monitor-AzureResources.ps1 - Multi-subscription Azure monitoring
- Azure Key Vault monitoring
- Azure VM security & backup compliance
- AWS resource inventory

**🗄️ Database Management** - NoSQL and advanced monitoring
- Monitor-MongoDBHealth.ps1 - MongoDB health monitoring
- Get-SQLServerHealth.ps1 - SQL Server comprehensive monitoring
- Get-MySQLHealth.ps1 - MySQL server health
- Get-PostgreSQLHealth.ps1 - PostgreSQL health checks

**🐳 Container Management** (3 scripts)
- Get-DockerHealthCheck.ps1 - Docker environment health
- Optimize-DockerCleanup.ps1 - Docker resource cleanup
- Get-KubernetesHealthCheck.ps1 - Kubernetes cluster health

**🌐 Web Services** (4 scripts)
- Get-IISHealthCheck.ps1 - IIS health monitoring
- Get-IISLogAnalyzer.ps1 - Advanced log analysis with security threat detection
- Optimize-IISConfiguration.ps1 - Performance tuning and security hardening
- Backup-IISConfiguration.ps1 - Complete IIS configuration backup

**📧 Email Services** (4 scripts)
- Get-ExchangeServerHealth.ps1 - Exchange Server health monitoring
- Plus 3 more Exchange management scripts

**☁️ Microsoft 365** (19 scripts)
- Exchange Online, Teams, SharePoint, Azure AD management
- Compliance Center, Power Platform, Defender for Office 365
- Comprehensive regional settings management (user, mailbox, site, OneDrive)
- Organization-wide configuration defaults

**🔒 Security & Compliance** (12 scripts)
- CIS Benchmark testing
- NIST framework compliance
- Security baseline verification

## Repository Structure

```
bug-free-umbrella/
├── docs/                              # Documentation
│   ├── README.md                      # Documentation index
│   ├── SCRIPT-EXAMPLES.md             # Script usage examples
│   ├── WORKFLOWS.md                   # End-to-end workflow guides
│   ├── TROUBLESHOOTING.md             # Common issues and solutions
│   └── INTUNE-SYNC-README.md          # Intune sync guide
│
├── scripts/
│   ├── advanced-security/             # Multi-framework compliance scanning
│   ├── api-management/                # Azure APIM & API health monitoring
│   ├── cloud-infrastructure/          # Azure & AWS management
│   │   ├── azure/                     # Azure resource health, Key Vault, VMs
│   │   └── aws/                       # AWS resource inventory
│   ├── container-management/          # Docker & Kubernetes
│   ├── database/                      # SQL Server, MySQL, PostgreSQL, MongoDB
│   ├── device-management/             # Device management scripts
│   │   ├── proactive-remediations/    # Auto-fix scripts (11 pairs)
│   │   ├── winget-updates/            # Application update scripts (40+ apps)
│   │   ├── autopatch/                 # Windows Update policies
│   │   ├── bitlocker-backup/          # BitLocker key backup
│   │   ├── device-uptime/             # Uptime monitoring
│   │   ├── l16-driver-block/          # Lenovo L16 driver management
│   │   ├── adobe-rum/                 # Adobe Remote Update Manager
│   │   └── remove-sccm/               # SCCM client removal
│   ├── devops-cicd/                   # Azure DevOps, GitHub Actions, GitLab CI
│   ├── email-services/                # Exchange Server management
│   ├── infrastructure-as-code/        # Terraform & Bicep testing
│   ├── intune/                        # Intune management tools (18+ scripts)
│   │   ├── reporting/                 # Compliance, status, and audit reports
│   │   ├── maintenance/               # Device cleanup and policy management
│   │   └── deployment/                # Packaging and deployment tools
│   ├── linux-server/                  # Linux server management
│   ├── m365/                          # Microsoft 365 cloud services (19 scripts)
│   │   ├── exchange-online/           # Exchange Online mailbox management
│   │   ├── teams/                     # Microsoft Teams administration
│   │   ├── sharepoint-onedrive/       # SharePoint and OneDrive
│   │   ├── azure-ad/                  # Azure AD / Entra ID
│   │   ├── compliance/                # Compliance Center
│   │   ├── power-platform/            # Power Platform management
│   │   └── defender/                  # Defender for Office 365
│   ├── monitoring/                    # System health checks and monitoring (6 scripts)
│   ├── network-management/            # Network diagnostics and troubleshooting (3 scripts)
│   ├── print-management/              # Print server management
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

## 💡 Common Use Cases

Find the right tool for your needs:

| I need to... | Use this script | Location |
|--------------|----------------|----------|
| **Cloud & DevOps** |
| Monitor Azure DevOps pipelines | Monitor-AzureDevOpsPipelines.ps1 | [scripts/devops-cicd/](scripts/devops-cicd/) |
| Monitor GitHub Actions workflows | Monitor-GitHubActions.ps1 | [scripts/devops-cicd/](scripts/devops-cicd/) |
| Monitor Azure API Management | Monitor-AzureAPIManagement.ps1 | [scripts/api-management/](scripts/api-management/) |
| Test API endpoint health | Test-APIHealth.ps1 | [scripts/api-management/](scripts/api-management/) |
| Validate Terraform configuration | Test-TerraformConfiguration.ps1 | [scripts/infrastructure-as-code/](scripts/infrastructure-as-code/) |
| Validate Azure Bicep templates | Test-BicepTemplates.ps1 | [scripts/infrastructure-as-code/](scripts/infrastructure-as-code/) |
| Monitor Azure resources and costs | Get-AzureResourceHealth.ps1 | [scripts/cloud-infrastructure/azure/](scripts/cloud-infrastructure/azure/) |
| Inventory AWS resources | Get-AWSResourceInventory.ps1 | [scripts/cloud-infrastructure/aws/](scripts/cloud-infrastructure/aws/) |
| **Containers & Web Services** |
| Monitor Docker container health | Get-DockerHealthCheck.ps1 | [scripts/container-management/](scripts/container-management/) |
| Check Kubernetes cluster health | Get-KubernetesHealthCheck.ps1 | [scripts/container-management/](scripts/container-management/) |
| Monitor IIS health and SSL certificates | Get-IISHealthCheck.ps1 | [scripts/web-services/](scripts/web-services/) |
| Analyze IIS logs for security threats | Get-IISLogAnalyzer.ps1 | [scripts/web-services/](scripts/web-services/) |
| **Microsoft 365 Cloud Services** |
| Check Exchange mailbox health | Get-MailboxHealth.ps1 | [scripts/m365/exchange-online/](scripts/m365/exchange-online/) |
| Monitor Microsoft Teams usage | Get-TeamsReport.ps1 | [scripts/m365/teams/](scripts/m365/teams/) |
| Check OneDrive storage usage | Get-OneDriveUsageReport.ps1 | [scripts/m365/sharepoint-onedrive/](scripts/m365/sharepoint-onedrive/) |
| Audit Azure AD guest users | Get-AzureADGuestAudit.ps1 | [scripts/m365/azure-ad/](scripts/m365/azure-ad/) |
| Review M365 license usage | Get-AzureADLicenseReport.ps1 | [scripts/m365/azure-ad/](scripts/m365/azure-ad/) |
| Configure user language settings | Set-UserLanguageSettings.ps1 | [scripts/m365/azure-ad/](scripts/m365/azure-ad/) |
| **Intune Management** |
| Find devices that haven't synced | Find-StaleDevices.ps1 | [scripts/intune/](scripts/intune/) |
| Check BitLocker encryption status | Get-BitLockerStatus.ps1 | [scripts/intune/](scripts/intune/) |
| See which devices are non-compliant | Get-DeviceComplianceReport.ps1 | [scripts/intune/](scripts/intune/) |
| Auto-update applications via winget | Winget Update Templates | [scripts/device-management/winget-updates/](scripts/device-management/winget-updates/) |
| **Server Management** |
| Fix stuck Windows Updates | Reset-WindowsUpdate.ps1 | [scripts/server/](scripts/server/) |
| Clean up server disk space | Get-DiskReport.ps1 | [scripts/server/](scripts/server/) |
| Audit Active Directory users | Get-ADUserAudit.ps1 | [scripts/server/active-directory/](scripts/server/active-directory/) |
| Backup all Group Policies | Backup-GroupPolicies.ps1 | [scripts/server/group-policy/](scripts/server/group-policy/) |
| **Database Management** |
| Check SQL Server health | Get-SQLServerHealth.ps1 | [scripts/database/](scripts/database/) |
| Monitor MySQL server | Get-MySQLHealth.ps1 | [scripts/database/](scripts/database/) |
| Monitor PostgreSQL server | Get-PostgreSQLHealth.ps1 | [scripts/database/](scripts/database/) |
| Monitor MongoDB health | Monitor-MongoDBHealth.ps1 | [scripts/database/](scripts/database/) |
| **Security & Compliance** |
| Run multi-framework compliance scan | Invoke-SecurityComplianceScan.ps1 | [scripts/advanced-security/](scripts/advanced-security/) |
| Test CIS Benchmark compliance | Test-CISBenchmark.ps1 | [scripts/security-compliance/](scripts/security-compliance/) |
| Audit local administrator accounts | Get-LocalAdminAudit.ps1 | [scripts/security-compliance/](scripts/security-compliance/) |
| Check security baseline compliance | Get-SecurityBaseline.ps1 | [scripts/security-compliance/](scripts/security-compliance/) |
| **Monitoring & Troubleshooting** |
| Check server health status | Monitor-ServerHealth.ps1 | [scripts/monitoring/](scripts/monitoring/) |
| Diagnose network issues | Test-NetworkConnectivity.ps1 | [scripts/network-management/](scripts/network-management/) |
| Monitor performance trends | Get-PerformanceTrends.ps1 | [scripts/monitoring/](scripts/monitoring/) |

## Getting Started

### Prerequisites

Before using these scripts, ensure you have the following:

#### For All Scripts
- **PowerShell 5.1 or later** (PowerShell 7+ recommended)
- **Administrator privileges** (most scripts require elevation)
- **Execution Policy** set appropriately

#### For Intune Scripts
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

### Verify Your Environment

**Check PowerShell Version**:
```powershell
$PSVersionTable.PSVersion
# Should show 5.1 or higher
```

**Check if running as Administrator**:
```powershell
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# Should return: True
```

**Check Execution Policy**:
```powershell
Get-ExecutionPolicy
# If Restricted, run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Quick Start Examples

#### DevOps Monitoring

**Monitor Azure DevOps Pipelines**:
```powershell
cd scripts/devops-cicd

.\Monitor-AzureDevOpsPipelines.ps1 -Organization "myorg" `
    -Project "*" `
    -PersonalAccessToken $env:AZURE_DEVOPS_PAT `
    -DaysToAnalyze 30 `
    -IncludeAgentPools
```

**Monitor GitHub Actions**:
```powershell
.\Monitor-GitHubActions.ps1 -Owner "myorg" `
    -Repository "*" `
    -GitHubToken $env:GITHUB_TOKEN `
    -DaysToAnalyze 30 `
    -IncludeRunners
```

#### Cloud Infrastructure

**Monitor Azure Resources**:
```powershell
cd scripts/cloud-infrastructure/azure

Connect-AzAccount
.\Monitor-AzureResources.ps1 -SubscriptionId "your-sub-id" `
    -IncludeCostAnalysis `
    -DetectOrphanedResources
```

**Inventory AWS Resources**:
```powershell
cd scripts/cloud-infrastructure/aws

.\Get-AWSResourceInventory.ps1 -Region "us-east-1" `
    -IncludeEC2 `
    -IncludeS3 `
    -IncludeRDS
```

#### API Management

**Test API Health**:
```powershell
cd scripts/api-management

.\Test-APIHealth.ps1 -EndpointsFile ".\api-endpoints.json" `
    -OutputFormat HTML `
    -MaxResponseTime 1000
```

#### Infrastructure as Code

**Validate Terraform Configuration**:
```powershell
cd scripts/infrastructure-as-code

.\Test-TerraformConfiguration.ps1 -TerraformPath "C:\Projects\terraform" `
    -RunSecurityScan `
    -GenerateReport
```

#### Intune Management

**Generate Monthly Compliance Report**:
```powershell
cd scripts/intune

# Device compliance status
.\Get-DeviceComplianceReport.ps1

# BitLocker encryption audit
.\Get-BitLockerStatus.ps1

# Windows Update compliance
.\Get-WindowsUpdateCompliance.ps1

# All reports saved to Desktop as HTML and CSV
```

#### Server Administration

**Fix Stuck Windows Updates**:
```powershell
cd scripts/server

# Standard reset (fixes most issues)
.\Reset-WindowsUpdate.ps1

# Full reset including BITS and Cryptographic services
.\Reset-WindowsUpdate.ps1 -FullReset
```

**Check Server Health**:
```powershell
# Verify system file integrity
.\Check-SystemIntegrity.ps1

# Auto-repair with HTML report
.\Check-SystemIntegrity.ps1 -AutoRepair -GenerateReport
```

#### Security & Compliance

**Run Multi-Framework Compliance Scan**:
```powershell
cd scripts/advanced-security

.\Invoke-SecurityComplianceScan.ps1 -Frameworks @("CIS", "NIST", "PCI-DSS") `
    -GenerateReport `
    -ExportFormat HTML
```

**Run Security Baseline Check**:
```powershell
cd scripts/security-compliance

# Check system against security baseline
.\Get-SecurityBaseline.ps1 -ExportReport
```

### Common Workflows

For detailed step-by-step guides, see our workflow documentation:

- **[Monthly Compliance Audit](docs/WORKFLOWS.md#monthly-compliance-audit-workflow)** - Complete compliance review process
- **[Automated Winget Updates](docs/WORKFLOWS.md#setting-up-automated-winget-updates)** - Deploy application auto-updates
- **[New Server Setup](docs/WORKFLOWS.md#new-windows-server-setup)** - Initial server configuration
- **[Device Cleanup](docs/WORKFLOWS.md#intune-device-cleanup-workflow)** - Remove stale devices
- **[BitLocker Deployment](docs/WORKFLOWS.md#bitlocker-deployment-and-monitoring)** - Enable encryption across devices

### What to Expect

**Script Execution Times**:
| Script Type | Typical Duration |
|-------------|------------------|
| Detection Scripts | 10-30 seconds |
| Winget Updates | 2-5 minutes |
| Intune Reports | 3-10 minutes |
| Server Health Checks | 15-30 minutes |
| Cloud Infrastructure Scans | 5-15 minutes |
| CI/CD Pipeline Monitoring | 1-5 minutes |

**Output Formats**:
- Most scripts generate **HTML** and **CSV** reports
- Reports saved to: `C:\Users\[YourName]\Desktop\`
- Color-coded console output for quick status checks

**Exit Codes**:
- **0** = Success / No issues found
- **1** = Issues detected / Remediation needed
- See [Script Examples](docs/SCRIPT-EXAMPLES.md) for detailed behavior

### Getting Help

**Built-in Help**:
```powershell
# View detailed help for any script
Get-Help .\ScriptName.ps1 -Detailed

# See examples
Get-Help .\ScriptName.ps1 -Examples

# Full help including parameters
Get-Help .\ScriptName.ps1 -Full
```

**Documentation**:
- **Questions about usage?** → [Script Examples](docs/SCRIPT-EXAMPLES.md)
- **Following a process?** → [Workflow Guides](docs/WORKFLOWS.md)
- **Something not working?** → [Troubleshooting](docs/TROUBLESHOOTING.md)
- **Script reference?** → [Full Documentation](docs/README.md)

**Support**:
- Check existing documentation first
- Review script comments (all scripts are well-documented)
- Test in non-production environment
- Report issues with detailed error messages

## Requirements Summary

| Component | Requirement |
|-----------|-------------|
| **PowerShell** | 5.1 minimum (7.x recommended) |
| **OS (Intune)** | Windows 10/11, any supported OS |
| **OS (Server)** | Windows Server 2016/2019/2022 |
| **Privileges** | Administrator / Elevated |
| **Intune Role** | Intune Admin or Global Reader |
| **Cloud Access** | Azure PowerShell, AWS Tools (for cloud scripts) |
| **Graph Module** | Microsoft.Graph (for Intune/M365 scripts) |
| **Network** | Internet access for cloud APIs |

## Script Statistics

- **Total Scripts**: 260+
- **Script Categories**: 20
- **Proactive Remediations**: 14 pairs
- **Winget App Templates**: 40+
- **Documentation Pages**: 5

## 🤖 Development

Scripts in this repository were created with the assistance of **[Claude Code](https://github.com/anthropics/claude-code)**, Anthropic's official CLI for Claude AI.

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.

---

**Last Updated**: 2025-12-28
