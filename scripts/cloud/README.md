# Cloud Infrastructure Management Scripts

PowerShell scripts for managing cloud infrastructure across Azure, AWS, and multi-cloud environments.

## 📋 Overview

Enterprise cloud management tools for:
- **Azure**: Resource health monitoring, cost analysis, compliance
- **AWS**: Resource inventory, security auditing, cost optimization
- **Multi-Cloud**: Unified monitoring across providers

## 🚀 Scripts

### Azure Management

#### Get-AzureResourceHealth.ps1

Azure subscription resource health check and cost analysis.

**Features**:
- Virtual Machine status and sizing analysis
- Storage account monitoring
- Network resource inventory (VNets, NSGs, Load Balancers)
- Cost analysis and optimization recommendations
- Resource group organization
- Subscription quota usage
- Security recommendations

**Usage**:
```powershell
# Basic health check
.\azure\Get-AzureResourceHealth.ps1

# Specific subscription with cost analysis
.\azure\Get-AzureResourceHealth.ps1 -SubscriptionId "xxx-xxx-xxx" -IncludeCostAnalysis -ExportHTML
```

**Requirements**: Az PowerShell module, Azure account connection

---

#### Monitor-AzureResources.ps1

Multi-subscription Azure resource monitoring and cost analysis.

**Features**:
- Multi-subscription monitoring
- Cost analysis and optimization recommendations
- Orphaned resource detection
- Resource health status
- Security recommendations
- Compliance reporting

**Usage**:
```powershell
# Monitor single subscription
.\azure\Monitor-AzureResources.ps1 -SubscriptionId "sub-id"

# Multi-subscription with cost analysis
.\azure\Monitor-AzureResources.ps1 -SubscriptionId "sub-id" `
    -IncludeCostAnalysis `
    -DetectOrphanedResources `
    -OutputFormat HTML
```

---

#### Azure Key Vault Management

**Monitor-AzureKeyVaults.ps1**

Azure Key Vault health and security monitoring.

**Features**:
- Key Vault health status
- Secret, key, and certificate inventory
- Access policy auditing
- Expiration monitoring
- Network security configuration
- Soft delete and purge protection status

**Usage**:
```powershell
# Monitor all Key Vaults in subscription
.\azure\Azure-KeyVault\Monitor-AzureKeyVaults.ps1 -SubscriptionId "sub-id"

# Monitor specific Key Vault
.\azure\Azure-KeyVault\Monitor-AzureKeyVaults.ps1 -SubscriptionId "sub-id" `
    -KeyVaultName "myvault" `
    -OutputFormat HTML
```

---

#### Azure Virtual Machines Management

**Get-VMSecurityConfig.ps1**

Azure VM security configuration audit.

**Features**:
- Security extension status (Antimalware, monitoring agents)
- Disk encryption status
- Network security group configuration
- Public IP exposure analysis
- Managed identity configuration
- Update management status

**Usage**:
```powershell
# Audit all VMs
.\azure\Azure-VirtualMachines\Get-VMSecurityConfig.ps1 -SubscriptionId "sub-id"

# Specific resource group
.\azure\Azure-VirtualMachines\Get-VMSecurityConfig.ps1 -SubscriptionId "sub-id" `
    -ResourceGroupName "rg-prod" `
    -OutputFormat HTML
```

**Get-VMBackupCompliance.ps1**

Azure VM backup compliance validation.

**Features**:
- Backup policy assignment status
- Last backup verification
- Backup retention compliance
- Recovery vault configuration
- Unprotected VM detection

**Usage**:
```powershell
# Check backup compliance
.\azure\Azure-VirtualMachines\Get-VMBackupCompliance.ps1 -SubscriptionId "sub-id"

# With detailed reporting
.\azure\Azure-VirtualMachines\Get-VMBackupCompliance.ps1 -SubscriptionId "sub-id" `
    -OutputFormat HTML `
    -IncludeRecommendations
```

**Optimize-AzureVMs.ps1**

Azure VM cost optimization and right-sizing recommendations.

**Features**:
- Underutilized VM detection
- Right-sizing recommendations
- Cost savings estimation
- Performance metrics analysis
- Shut down recommendations

**Usage**:
```powershell
# Analyze all VMs for optimization
.\azure\Azure-VirtualMachines\Optimize-AzureVMs.ps1 -SubscriptionId "sub-id"

# Generate savings report
.\azure\Azure-VirtualMachines\Optimize-AzureVMs.ps1 -SubscriptionId "sub-id" `
    -DaysToAnalyze 30 `
    -OutputFormat HTML
```

---

### AWS Management

#### Get-AWSResourceInventory.ps1

AWS cloud resource inventory and health monitoring.

**Features**:
- EC2 instance inventory and status
- S3 bucket analysis and security
- RDS database monitoring
- Lambda function inventory
- VPC and networking resources
- IAM resource audit
- Cost and billing analysis

**Usage**:
```powershell
# Default region inventory
.\aws\Get-AWSResourceInventory.ps1

# Specific region with profile
.\aws\Get-AWSResourceInventory.ps1 -Region us-east-1 -ProfileName production -ExportHTML
```

**Requirements**: AWS PowerShell module (AWSPowerShell.NetCore), configured AWS credentials

---

## ⚙️ Requirements

| Provider | Module | Authentication |
|----------|--------|----------------|
| **Azure** | Az PowerShell | Connect-AzAccount |
| **AWS** | AWSPowerShell.NetCore | AWS CLI configured |

### Installation

**Azure**:
```powershell
Install-Module Az -AllowClobber -Scope CurrentUser
Connect-AzAccount
```

**AWS**:
```powershell
Install-Module AWSPowerShell.NetCore -Scope CurrentUser
# Configure: aws configure
```

---

## 📊 Common Workflows

**Monthly Azure Health Check**:
```powershell
.\azure\Get-AzureResourceHealth.ps1 -IncludeCostAnalysis -ExportHTML
.\azure\Monitor-AzureResources.ps1 -SubscriptionId "sub-id" -IncludeCostAnalysis
```

**Azure VM Compliance Audit**:
```powershell
# Security configuration
.\azure\Azure-VirtualMachines\Get-VMSecurityConfig.ps1 -SubscriptionId "sub-id" -OutputFormat HTML

# Backup compliance
.\azure\Azure-VirtualMachines\Get-VMBackupCompliance.ps1 -SubscriptionId "sub-id" -OutputFormat HTML

# Cost optimization
.\azure\Azure-VirtualMachines\Optimize-AzureVMs.ps1 -SubscriptionId "sub-id" -DaysToAnalyze 30
```

**Azure Key Vault Monitoring**:
```powershell
# Monitor all Key Vaults
.\azure\Azure-KeyVault\Monitor-AzureKeyVaults.ps1 -SubscriptionId "sub-id" -OutputFormat HTML
```

**AWS Multi-Region Audit**:
```powershell
$regions = "us-east-1", "us-west-2", "eu-west-1"
foreach ($region in $regions) {
    .\aws\Get-AWSResourceInventory.ps1 -Region $region -ExportHTML
}
```

---

**Total Scripts**: 8
**Azure Scripts**: 7
**AWS Scripts**: 1
**Platforms**: Azure, AWS, Multi-Cloud
