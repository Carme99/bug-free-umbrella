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
.\Get-AzureResourceHealth.ps1

# Specific subscription with cost analysis
.\Get-AzureResourceHealth.ps1 -SubscriptionId "xxx-xxx-xxx" -IncludeCostAnalysis -ExportHTML
```

**Requirements**: Az PowerShell module, Azure account connection

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
.\Get-AWSResourceInventory.ps1

# Specific region with profile
.\Get-AWSResourceInventory.ps1 -Region us-east-1 -ProfileName production -ExportHTML
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
.\Get-AzureResourceHealth.ps1 -IncludeCostAnalysis -ExportHTML
```

**AWS Multi-Region Audit**:
```powershell
$regions = "us-east-1", "us-west-2", "eu-west-1"
foreach ($region in $regions) {
    .\Get-AWSResourceInventory.ps1 -Region $region -ExportHTML
}
```

---

**Total Scripts**: 5
**Platforms**: Azure, AWS, Multi-Cloud
