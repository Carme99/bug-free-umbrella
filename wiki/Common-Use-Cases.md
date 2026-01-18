# Common Use Cases

Find the right script for your task quickly. This page organizes scripts by common IT scenarios and goals.

## 🎯 Quick Navigation

- [Device Management](#device-management)
- [Security & Compliance](#security--compliance)
- [Cloud Management](#cloud-management)
- [Microsoft 365](#microsoft-365)
- [Server Administration](#server-administration)
- [Monitoring & Health](#monitoring--health)
- [Automation & DevOps](#automation--devops)

---

## Device Management

### I want to... keep applications up to date

**Scenario:** Automatically update applications across managed devices

**Solutions:**
- **`scripts/endpoints/devices/winget/`** - 40+ Winget auto-update templates
  - `browsers/GoogleChrome/` - Auto-update Chrome
  - `development/VisualStudioCode/` - Auto-update VS Code
  - `productivity/MicrosoftTeams/` - Auto-update Teams
- **`scripts/utilities/Update-AllAppsWinget.ps1`** - System-wide winget updater
- **`scripts/utilities/Update-DotNetRuntimes.ps1`** (v2.5) - .NET runtime maintenance with interactive menu and security-hardened updates

**Documentation:** [Winget Updates](Winget-Updates) | [Script Catalog](Script-Catalog#winget-updates)

### I want to... fix common device issues automatically

**Scenario:** Proactive detection and remediation of device problems

**Solutions:**
- **`scripts/endpoints/devices/proactive-remediations/Fix-DiskSpace/`** - Clean up disk space
- **`scripts/endpoints/devices/proactive-remediations/Fix-WindowsUpdateStuck/`** - Fix stuck updates
- **`scripts/endpoints/devices/proactive-remediations/Fix-TeamsCache/`** - Clear Teams cache
- **`scripts/endpoints/devices/proactive-remediations/Fix-TempFiles/`** - Clean temporary files
- **`scripts/endpoints/devices/proactive-remediations/Fix-DNSCache/`** - Flush DNS cache

**Documentation:** [Proactive Remediations](Proactive-Remediations)

### I want to... manage BitLocker encryption

**Scenario:** Deploy and monitor BitLocker across devices

**Solutions:**
- **`scripts/endpoints/devices/bitlocker/Detect_BitLockerKeyBackup.ps1`** - Verify key backup
- **`scripts/endpoints/devices/bitlocker/Fix_BitLockerKeyBackup.ps1`** - Backup missing keys
- **`scripts/endpoints/devices/proactive-remediations/Fix-BitLockerNotEscrowedKeys/`** - Escrow keys to Azure AD

**Documentation:** [Script Examples](Script-Examples#bitlocker)

### I want to... remove unwanted software

**Scenario:** Clean up bloatware or unwanted applications

**Solutions:**
- **`scripts/endpoints/devices/adobe-rum/`** - Remove Adobe Reader Update Manager
- **`scripts/endpoints/devices/sccm/`** - Remove SCCM client remnants
- **`scripts/cloud/azure/avd/removeUSlangpack.ps1`** - Remove US language packs

**Documentation:** [Script Catalog](Script-Catalog#device-cleanup)

---

## Security & Compliance

### I want to... test CIS Benchmark compliance

**Scenario:** Audit systems against CIS security benchmarks

**Solutions:**
- **`scripts/security/compliance/frameworks/Test-CISBenchmark.ps1`** - CIS Windows Server compliance
  - Tests 15+ controls (password policies, account lockout, audit policies)
  - Supports Level 1 and Level 2 benchmarks
  - Generates HTML compliance reports

**Example:**
```powershell
.\Test-CISBenchmark.ps1 -Level 2 -ExportHTML
```

**Documentation:** [Security & Compliance](Security-Compliance)

### I want to... audit local administrator accounts

**Scenario:** Find who has local admin rights on devices

**Solutions:**
- **`scripts/security/compliance/frameworks/Get-LocalAdminAudit.ps1`** - Audit local administrators
- **`scripts/infrastructure/windows/active-directory/Get-ADUserAudit.ps1`** - Audit AD user permissions
- **`scripts/infrastructure/windows/active-directory/Get-ServiceAccountAudit.ps1`** - Audit service accounts

**Documentation:** [Security & Compliance](Security-Compliance#auditing)

### I want to... check for security vulnerabilities

**Scenario:** Scan systems for security weaknesses

**Solutions:**
- **`scripts/security/compliance/frameworks/Get-SecurityBaseline.ps1`** - Check security baseline
- **`scripts/security/compliance/frameworks/Get-AntivirusStatus.ps1`** - Verify antivirus status
- **`scripts/security/compliance/frameworks/Get-OpenPortScan.ps1`** - Scan for open ports
- **`scripts/security/compliance/frameworks/Get-ExpiredCertificates.ps1`** - Find expired certificates

**Documentation:** [Security & Compliance](Security-Compliance)

---

## Cloud Management

### I want to... build Azure Virtual Desktop images

**Scenario:** Create custom AVD images with Azure Compute Gallery

**Solutions:**
- **`scripts/cloud/azure/avd/New-AzureComputeGalleryImage.ps1`** - Interactive ACG image builder
  - Clones VMs, configures settings, captures images
  - Handles sysprep blockers automatically
  - Creates ACG image versions

**Documentation:** [Azure Virtual Desktop](Azure-Virtual-Desktop) | [ACG Image Builder](Azure-Compute-Gallery-Image-Builder)

### I want to... monitor Azure resources

**Scenario:** Check health and status of Azure resources

**Solutions:**
- **`scripts/cloud/azure/core/Get-AzureResourceHealth.ps1`** - Resource health check
- **`scripts/cloud/azure/core/Monitor-AzureResources.ps1`** - Monitor Azure resources
- **`scripts/cloud/azure/Azure-VirtualMachines/Get-VMBackupCompliance.ps1`** - Check VM backups
- **`scripts/cloud/azure/Azure-VirtualMachines/Get-VMSecurityConfig.ps1`** - Audit VM security

**Documentation:** [Script Catalog](Script-Catalog) (Cloud Infrastructure category page coming soon)

### I want to... optimize cloud costs

**Scenario:** Reduce Azure or AWS spending

**Solutions:**
- **`scripts/cloud/azure/Azure-VirtualMachines/Optimize-AzureVMs.ps1`** - Optimize Azure VMs
- **`scripts/cloud/aws/core/Get-AWSResourceInventory.ps1`** - Inventory AWS resources

**Documentation:** [Script Catalog](Script-Catalog) (Cloud Infrastructure category page coming soon)

---

## Microsoft 365

### I want to... manage Exchange Online mailboxes

**Scenario:** Administer Exchange Online mailboxes and distribution lists

**Solutions:**
- **`scripts/collaboration/microsoft365/exchange-online/Get-MailboxHealth.ps1`** - Check mailbox health
- **`scripts/collaboration/microsoft365/exchange-online/Get-SharedMailboxReport.ps1`** - Audit shared mailboxes
- **`scripts/collaboration/microsoft365/exchange-online/Get-DistributionListAudit.ps1`** - Audit distribution lists
- **`scripts/collaboration/microsoft365/exchange-online/Get-MailFlowAnalysis.ps1`** - Analyze mail flow

**Documentation:** [Microsoft 365 Cloud Services](Microsoft-365-Cloud-Services)

### I want to... audit Azure AD users

**Scenario:** Review Azure AD user accounts and permissions

**Solutions:**
- **`scripts/collaboration/microsoft365/azure-ad/Get-AzureADGuestAudit.ps1`** - Audit guest users
- **`scripts/collaboration/microsoft365/azure-ad/Get-AzureADLicenseReport.ps1`** - Check license assignments
- **`scripts/infrastructure/windows/active-directory/Get-ADUserAudit.ps1`** - Audit AD users

**Documentation:** [Microsoft 365 Cloud Services](Microsoft-365-Cloud-Services#azure-ad)

### I want to... manage regional settings in M365

**Scenario:** Set language, timezone, and regional settings for users

**Solutions:**
- **`scripts/collaboration/microsoft365/azure-ad/Set-UserLanguageSettings.ps1`** - Set user language
- **`scripts/collaboration/microsoft365/exchange-online/Set-MailboxRegionalSettings.ps1`** - Set mailbox region
- **`scripts/collaboration/microsoft365/sharepoint/Set-SiteRegionalSettings.ps1`** - Set SharePoint region
- **`scripts/collaboration/microsoft365/teams/Set-TeamsRegionalSettings.ps1`** - Set Teams region

**Documentation:** [Microsoft 365 Cloud Services](Microsoft-365-Cloud-Services#regional-settings)

---

## Server Administration

### I want to... monitor server health

**Scenario:** Check Windows Server health and performance

**Solutions:**
- **`scripts/infrastructure/windows/monitoring/Monitor-ServerHealth.ps1`** - Comprehensive server health check
- **`scripts/infrastructure/windows/monitoring/Get-PerformanceReport.ps1`** - Performance metrics
- **`scripts/infrastructure/windows/monitoring/Get-EventLogReport.ps1`** - Event log analysis

**Documentation:** [Server Management](Server-Management)

### I want to... manage Active Directory

**Scenario:** Administer Active Directory users, computers, and policies

**Solutions:**
- **`scripts/infrastructure/windows/active-directory/Get-ADHealthCheck.ps1`** - AD health check
- **`scripts/infrastructure/windows/active-directory/Find-InactiveADComputers.ps1`** - Find stale computer accounts
- **`scripts/infrastructure/windows/active-directory/Get-ADUserAudit.ps1`** - Audit AD users
- **`scripts/infrastructure/windows/group-policy/Get-GPOReport.ps1`** - Generate GPO reports

**Documentation:** [Server Management](Server-Management#active-directory)

### I want to... manage IIS web servers

**Scenario:** Administer IIS websites and applications

**Solutions:**
- **`scripts/infrastructure/web/iis/Get-IISHealthCheck.ps1`** - IIS health check
- **`scripts/infrastructure/web/iis/Backup-IISConfiguration.ps1`** - Backup IIS config
- **`scripts/infrastructure/web/iis/Optimize-IISConfiguration.ps1`** - Optimize IIS settings
- **`scripts/infrastructure/web/iis/Get-IISLogAnalyzer.ps1`** - Analyze IIS logs

**Documentation:** [Script Catalog](Script-Catalog) (Web Services category page coming soon)

---

## Monitoring & Health

### I want to... monitor Intune device compliance

**Scenario:** Check device compliance status in Microsoft Endpoint Manager

**Solutions:**
- **`scripts/endpoints/intune/reporting/Get-DeviceComplianceReport.ps1`** - Device compliance report
- **`scripts/endpoints/intune/reporting/Get-WindowsUpdateCompliance.ps1`** - Windows Update status
- **`scripts/endpoints/intune/reporting/Get-BitLockerStatus.ps1`** - BitLocker encryption status
- **`scripts/endpoints/intune/reporting/Get-AppInstallationStatus.ps1`** - App deployment status

**Documentation:** [Intune Management](Intune-Management)

### I want to... track application deployment

**Scenario:** Monitor application installation success/failure

**Solutions:**
- **`scripts/endpoints/intune/reporting/Get-AppInstallErrorReport.ps1`** - App installation errors
- **`scripts/endpoints/intune/reporting/Get-WingetUpdateCompliance.ps1`** - Winget update status

**Documentation:** [Intune Management](Intune-Management#reporting)

### I want to... monitor database health

**Scenario:** Check database server health and performance

**Solutions:**
- **`scripts/data/databases/Get-SQLServerHealth.ps1`** - SQL Server health check
- **`scripts/data/databases/Get-MySQLHealth.ps1`** - MySQL health check
- **`scripts/data/databases/Get-PostgreSQLHealth.ps1`** - PostgreSQL health check
- **`scripts/data/databases/Monitor-MongoDBHealth.ps1`** - MongoDB monitoring

**Documentation:** [Script Catalog](Script-Catalog) (Database Management category page coming soon)

---

## Automation & DevOps

### I want to... monitor CI/CD pipelines

**Scenario:** Track pipeline health and build status

**Solutions:**
- **`scripts/automation/cicd/Monitor-AzureDevOpsPipelines.ps1`** - Monitor Azure Pipelines
- **`scripts/automation/cicd/Monitor-GitHubActions.ps1`** - Monitor GitHub Actions
- **`scripts/automation/cicd/Monitor-GitLabCI.ps1`** - Monitor GitLab CI
- **`scripts/automation/cicd/Analyze-BuildPerformance.ps1`** - Analyze build performance

**Documentation:** [Script Catalog](Script-Catalog) (DevOps & CI/CD category page coming soon)

### I want to... validate infrastructure as code

**Scenario:** Test Terraform or Bicep templates

**Solutions:**
- **`scripts/automation/iac/Test-TerraformConfiguration.ps1`** - Validate Terraform
- **`scripts/automation/iac/Test-BicepTemplates.ps1`** - Validate Bicep templates

**Documentation:** [Script Catalog](Script-Catalog) (Infrastructure as Code category page coming soon)

### I want to... monitor container health

**Scenario:** Check Docker or Kubernetes cluster health

**Solutions:**
- **`scripts/cloud/containers/Get-DockerHealthCheck.ps1`** - Docker health check
- **`scripts/cloud/containers/Get-KubernetesHealthCheck.ps1`** - Kubernetes health check
- **`scripts/cloud/containers/Optimize-DockerCleanup.ps1`** - Clean up Docker

**Documentation:** [Script Catalog](Script-Catalog) (Container Management category page coming soon)

---

## Complete Workflows

For end-to-end processes, see:

- **[Workflows](Workflows)** - Complete step-by-step guides
- **[Azure Virtual Desktop](Azure-Virtual-Desktop)** - AVD deployment workflow
- **[Azure Compute Gallery Image Builder](Azure-Compute-Gallery-Image-Builder)** - ACG image creation workflow

---

## Can't Find What You Need?

Try these resources:

1. **[Script Catalog](Script-Catalog)** - Browse all 260+ scripts by category
2. **[Script Examples](Script-Examples)** - See detailed usage examples
3. **[Repository Search](https://github.com/Carme99/bug-free-umbrella)** - Search GitHub repository
4. **[GitHub Issues](https://github.com/Carme99/bug-free-umbrella/issues)** - Request new scripts

---

**Last Updated:** 2026-01-05
**Version:** 1.1.0
