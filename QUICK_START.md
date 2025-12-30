# Quick Start Guide

Welcome to Bug-Free Umbrella! This guide helps you quickly find the scripts you need based on your role and responsibilities.

## Table of Contents
- [Quick Start by Role](#quick-start-by-role)
- [Quick Start by Task](#quick-start-by-task)
- [First-Time Setup](#first-time-setup)
- [Common Workflows](#common-workflows)

---

## Quick Start by Role

### 🎯 I manage Intune devices and endpoints

**Start here:**
- [`scripts/intune/`](scripts/intune/) - Microsoft Intune management (18+ scripts)
- [`scripts/device-management/`](scripts/device-management/) - General device configuration
- [`scripts/intune/ProactiveRemediations/`](scripts/intune/ProactiveRemediations/) - Auto-fix script pairs (14 pairs)

**Top scripts to try:**
- `Get-IntuneDeviceCompliance.ps1` - Check device compliance status
- `Sync-IntuneDevice.ps1` - Force Intune sync
- `Get-IntuneApplicationStatus.ps1` - Monitor app deployment

**Documentation:** [Wiki → Device Management](../../wiki/Device-Management)

---

### 🖥️ I manage Windows Servers

**Start here:**
- [`scripts/server/`](scripts/server/) - Windows Server administration (30+ scripts)
- [`scripts/monitoring/`](scripts/monitoring/) - Server health monitoring
- [`scripts/web-services/`](scripts/web-services/) - IIS management

**Top scripts to try:**
- `Monitor-ServerHealth.ps1` - Comprehensive server health check
- `Get-ServerInventory.ps1` - Collect server details
- `Test-ServerConnectivity.ps1` - Network diagnostics

**Documentation:** [Wiki → Server Infrastructure](../../wiki/Server-Infrastructure)

---

### ☁️ I work with Azure/AWS Cloud

**Start here:**
- [`scripts/cloud-infrastructure/`](scripts/cloud-infrastructure/) - Multi-cloud management
- [`scripts/AzureVirtualDesktop/`](AzureVirtualDesktop/) - AVD-specific tools
- [`scripts/container-management/`](scripts/container-management/) - Docker/Kubernetes

**Top scripts to try:**
- `Get-AzureResourceInventory.ps1` - Inventory Azure resources
- `Monitor-AzureVMPerformance.ps1` - VM performance tracking
- `Get-KubernetesHealthCheck.ps1` - K8s cluster monitoring

**Documentation:** [Wiki → Cloud Infrastructure](../../wiki/Cloud-Infrastructure)

---

### 🔄 I work with DevOps/CI-CD

**Start here:**
- [`scripts/devops-cicd/`](scripts/devops-cicd/) - Pipeline monitoring
- [`scripts/infrastructure-as-code/`](scripts/infrastructure-as-code/) - Terraform, Bicep
- [`scripts/container-management/`](scripts/container-management/) - Container automation

**Top scripts to try:**
- `Monitor-AzureDevOpsPipeline.ps1` - Pipeline health monitoring
- `Test-TerraformDeployment.ps1` - Validate IaC deployments
- `Get-GitHubActionsStatus.ps1` - GitHub Actions monitoring

**Documentation:** [Wiki → DevOps](../../wiki/DevOps)

---

### 🔒 I focus on Security/Compliance

**Start here:**
- [`scripts/security-compliance/`](scripts/security-compliance/) - Multi-framework scanning
- [`scripts/advanced-security/`](scripts/advanced-security/) - Security hardening
- [`scripts/monitoring/`](scripts/monitoring/) - Security monitoring

**Top scripts to try:**
- `Invoke-SecurityComplianceScan.ps1` - Multi-framework compliance scan
- `Test-SecurityPosture.ps1` - Security posture assessment
- `Get-BitLockerStatus.ps1` - BitLocker compliance check

**Documentation:** [Wiki → Security](../../wiki/Security)

---

### 👥 I manage Microsoft 365/Exchange

**Start here:**
- [`scripts/m365/`](scripts/m365/) - Microsoft 365 services
- [`scripts/email-services/`](scripts/email-services/) - Exchange management

**Top scripts to try:**
- `Get-M365LicenseReport.ps1` - License usage reporting
- `Monitor-ExchangeOnlineHealth.ps1` - Exchange health check
- `Get-TeamsChannelActivity.ps1` - Teams usage analytics

**Documentation:** [Wiki → M365 & Enterprise](../../wiki/M365-Enterprise)

---

### 🗄️ I manage Databases

**Start here:**
- [`scripts/database/`](scripts/database/) - SQL Server, MySQL, PostgreSQL, MongoDB

**Top scripts to try:**
- `Test-DatabaseConnectivity.ps1` - Connection testing
- `Get-DatabaseBackupStatus.ps1` - Backup verification
- `Monitor-SQLServerPerformance.ps1` - SQL performance monitoring

**Documentation:** [Wiki → Database Management](../../wiki/Database-Management)

---

## Quick Start by Task

### "I need to..."

| Task | Script Location | Documentation |
|------|----------------|---------------|
| **Check server health** | `scripts/monitoring/Monitor-ServerHealth.ps1` | [Server Monitoring](../../wiki/Server-Monitoring) |
| **Deploy applications via Intune** | `scripts/intune/Deploy-IntuneApplication.ps1` | [Intune Guide](../../wiki/Intune-Management) |
| **Run compliance scan** | `scripts/security-compliance/Invoke-SecurityComplianceScan.ps1` | [Compliance Scanning](../../wiki/Compliance-Scanning) |
| **Monitor Azure resources** | `scripts/cloud-infrastructure/Monitor-AzureResources.ps1` | [Azure Monitoring](../../wiki/Cloud-Infrastructure) |
| **Check BitLocker status** | `scripts/security-compliance/Get-BitLockerStatus.ps1` | [BitLocker Management](../../wiki/Security) |
| **Install applications via Winget** | `scripts/intune/WingetUpdates/` | [Winget Guide](../../wiki/Winget-Management) |
| **Test network connectivity** | `scripts/network-management/Test-NetworkConnectivity.ps1` | [Network Diagnostics](../../wiki/Network-Management) |
| **Monitor IIS websites** | `scripts/web-services/Monitor-IISSites.ps1` | [Web Services](../../wiki/Web-Services) |
| **Backup databases** | `scripts/database/Backup-Database.ps1` | [Database Management](../../wiki/Database-Management) |
| **Check disk space** | `scripts/server/Get-DiskSpaceReport.ps1` | [Server Maintenance](../../wiki/Server-Infrastructure) |

---

## First-Time Setup

### Prerequisites

1. **PowerShell Version**
   - PowerShell 5.1+ (minimum)
   - PowerShell 7+ (recommended)
   - Check version: `$PSVersionTable.PSVersion`

2. **Administrator Privileges**
   - Most scripts require elevated permissions
   - Run PowerShell as Administrator

3. **Required Modules** (install as needed)
   ```powershell
   # For Azure scripts
   Install-Module -Name Az -Scope CurrentUser

   # For Microsoft 365 scripts
   Install-Module -Name Microsoft.Graph -Scope CurrentUser

   # For Intune scripts
   Install-Module -Name Microsoft.Graph.Intune -Scope CurrentUser

   # For AWS scripts
   Install-Module -Name AWS.Tools.Common -Scope CurrentUser
   ```

### Testing Your First Script

1. **Clone the repository**
   ```bash
   git clone https://github.com/Carme99/bug-free-umbrella.git
   cd bug-free-umbrella
   ```

2. **Navigate to a category**
   ```powershell
   cd scripts/monitoring
   ```

3. **Review the script**
   ```powershell
   Get-Help .\Monitor-ServerHealth.ps1 -Full
   ```

4. **Test in non-production first**
   ```powershell
   .\Monitor-ServerHealth.ps1 -WhatIf
   ```

5. **Run the script**
   ```powershell
   .\Monitor-ServerHealth.ps1
   ```

---

## Common Workflows

### 1. Daily Server Health Check

```powershell
# Morning health check routine
.\scripts\monitoring\Monitor-ServerHealth.ps1
.\scripts\server\Get-DiskSpaceReport.ps1 -WarningThreshold 20
.\scripts\server\Get-EventLogErrors.ps1 -Hours 24
```

### 2. Intune Device Management

```powershell
# Check device compliance
.\scripts\intune\Get-IntuneDeviceCompliance.ps1 -ExportCSV

# Force sync non-compliant devices
.\scripts\intune\Sync-IntuneDevice.ps1 -DeviceFilter "NonCompliant"

# Check application deployment status
.\scripts\intune\Get-IntuneApplicationStatus.ps1 -ApplicationName "Microsoft 365"
```

### 3. Security Compliance Audit

```powershell
# Run comprehensive compliance scan
.\scripts\security-compliance\Invoke-SecurityComplianceScan.ps1 -Framework CIS,NIST

# Check BitLocker compliance
.\scripts\security-compliance\Get-BitLockerStatus.ps1

# Audit security settings
.\scripts\advanced-security\Test-SecurityPosture.ps1
```

### 4. Azure Resource Management

```powershell
# Inventory Azure resources
.\scripts\cloud-infrastructure\Get-AzureResourceInventory.ps1 -SubscriptionId "xxx"

# Monitor VM performance
.\scripts\cloud-infrastructure\Monitor-AzureVMPerformance.ps1 -ResourceGroup "Production"

# Check cost management
.\scripts\cloud-infrastructure\Get-AzureCostReport.ps1 -Days 30
```

### 5. Database Maintenance

```powershell
# Check database backups
.\scripts\database\Get-DatabaseBackupStatus.ps1 -Server "SQL-PROD-01"

# Test connectivity
.\scripts\database\Test-DatabaseConnectivity.ps1

# Monitor performance
.\scripts\database\Monitor-SQLServerPerformance.ps1
```

---

## Need Help?

- **Full Documentation:** [Wiki Home](../../wiki)
- **Script Catalog:** [Complete Script List](../../wiki/Script-Catalog)
- **Troubleshooting:** [Common Issues](../../wiki/Troubleshooting)
- **Examples:** [Script Examples](examples/)
- **Report Issues:** [GitHub Issues](https://github.com/Carme99/bug-free-umbrella/issues)

---

## Important Notes

**Testing First:**
Most scripts in this repository have not been thoroughly tested in production environments. Always:
1. Review the script code before running
2. Test in a non-production environment first
3. Ensure you have proper backups
4. Understand what the script will do

**Script Parameters:**
Use `Get-Help <ScriptName> -Full` to see all available parameters and examples.

**Execution Policy:**
You may need to adjust your PowerShell execution policy:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

**Ready to dive deeper?** Check out the [Full Documentation Wiki](../../wiki) for comprehensive guides!
