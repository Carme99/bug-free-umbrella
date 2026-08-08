# ☁️ AWS Management Guide

![AWS](https://img.shields.io/badge/AWS-Cloud_Management-FF9900?logo=amazonaws&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+_|_7.0+-5391FE?logo=powershell&logoColor=white)
![Scripts](https://img.shields.io/badge/scripts-1+-orange)

> **AWS automation and monitoring scripts for PowerShell**

---

## 📋 Table of Contents
- [Overview](#overview)
- [Available Scripts](#available-scripts)
- [Prerequisites](#prerequisites)
- [Common Use Cases](#common-use-cases)
- [Quick Start Examples](#quick-start-examples)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

The Bug-Free Umbrella AWS collection provides PowerShell automation for AWS resource management and monitoring.

**Coverage:**
- ✅ EC2 Instance Management
- ✅ S3 Bucket Analysis
- ✅ RDS Database Monitoring
- ✅ Lambda Function Inventory
- 🔄 VPC & Networking (Roadmap)
- 🔄 IAM Resource Audit (Roadmap)
- 🔄 Cost & Billing Analysis (Roadmap)

---

## Available Scripts

### Get-AWSResourceInventory.ps1

![Location](https://img.shields.io/badge/location-scripts/cloud/aws/core-blue)
![Type](https://img.shields.io/badge/type-monitoring-green)

**Comprehensive AWS resource inventory across multiple services**

**Features:**
- 📊 EC2 instance tracking (running vs stopped)
- 🗄️ S3 bucket inventory
- 🗃️ RDS database monitoring
- ⚡ Lambda function listing
- 📈 Resource count metrics
- 📄 HTML report generation

**Quick Example:**
```powershell
# Default region inventory
.\Get-AWSResourceInventory.ps1

# Specific region with custom profile
.\Get-AWSResourceInventory.ps1 -Region us-west-2 -ProfileName production

# Export to HTML report
.\Get-AWSResourceInventory.ps1 -Region us-east-1 -ExportHTML
```

[View Full Script →](../scripts/cloud/aws/core/Get-AWSResourceInventory.ps1)

---

## Prerequisites

### Required Software

![AWS CLI](https://img.shields.io/badge/AWS_CLI-2.0+-orange?logo=amazonaws)
![PowerShell Module](https://img.shields.io/badge/module-AWSPowerShell.NetCore-blue)

1. **AWS PowerShell Module**
```powershell
# Install AWS PowerShell Core module
Install-Module -Name AWSPowerShell.NetCore -Force

# Verify installation
Get-Module -ListAvailable AWSPowerShell.NetCore
```

2. **AWS Credentials Configuration**
```powershell
# Configure AWS credentials (interactive)
aws configure

# Or use profiles
aws configure --profile production
```

### Required Permissions

**IAM Policy Requirements:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "s3:ListAllMyBuckets",
        "rds:DescribeDBInstances",
        "lambda:ListFunctions"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## Common Use Cases

### 1. Multi-Region Resource Audit

**Scenario**: Monthly inventory across all AWS regions

```powershell
# Define regions to audit
$regions = @('us-east-1', 'us-west-2', 'eu-west-1')

# Run inventory for each region
foreach ($region in $regions) {
    Write-Host "Inventorying $region..." -ForegroundColor Cyan
    .\Get-AWSResourceInventory.ps1 -Region $region -ExportHTML
}
```

### 2. Cost Optimization Review

**Scenario**: Identify stopped EC2 instances for cost savings

```powershell
# Get inventory
.\Get-AWSResourceInventory.ps1 -Region us-east-1 |
    Where-Object { $_.ResourceType -eq 'EC2' -and $_.State -eq 'stopped' }
```

### 3. Security Compliance Auditing

**Scenario**: Track all resources for security review

```powershell
# Export comprehensive inventory
.\Get-AWSResourceInventory.ps1 -Region us-east-1 -ExportHTML

# Email to security team
Send-MailMessage -To security@company.com `
    -Subject "Monthly AWS Inventory" `
    -Body "See attached" `
    -Attachments "AWS-Inventory.html"
```

### 4. Scheduled Monitoring

**Scenario**: Automated daily resource tracking

```powershell
# Create scheduled task (Windows)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-File C:\Scripts\Get-AWSResourceInventory.ps1 -Region us-east-1 -ExportHTML"

$trigger = New-ScheduledTaskTrigger -Daily -At 6:00AM

Register-ScheduledTask -TaskName "AWS Daily Inventory" `
    -Action $action -Trigger $trigger -User "SYSTEM"
```

---

## Quick Start Examples

### Example 1: Basic Inventory
```powershell
# Run in default region (us-east-1)
.\Get-AWSResourceInventory.ps1
```

**Expected Output:**
```
[+] Found 15 EC2 instances (12 running, 3 stopped)
[+] Found 8 S3 buckets
[+] Found 3 RDS instances
[+] Found 12 Lambda functions
```

### Example 2: Custom Region with Profile
```powershell
# Production account, eu-west-1
.\Get-AWSResourceInventory.ps1 `
    -Region eu-west-1 `
    -ProfileName prod-account
```

### Example 3: Automated Reporting
```powershell
# Daily report with HTML export
.\Get-AWSResourceInventory.ps1 `
    -Region us-east-1 `
    -ExportHTML `
    -Verbose
```

---

## Best Practices

### 🔒 Security
- ✅ Use IAM roles instead of access keys when possible
- ✅ Follow principle of least privilege
- ✅ Rotate AWS credentials regularly
- ✅ Use separate profiles for different environments (dev/staging/prod)
- ⚠️ Never commit AWS credentials to version control

### 📊 Monitoring
- Run inventory scripts weekly minimum
- Compare results to detect configuration drift
- Archive reports for compliance auditing
- Set up alerting for unusual resource counts

### 💰 Cost Optimization
- Identify stopped instances monthly
- Review S3 bucket sizes for cleanup opportunities
- Monitor RDS instance types for rightsizing
- Track Lambda function usage patterns

### 🔄 Automation
- Schedule daily inventory scripts
- Export to HTML for management review
- Integrate with ticketing systems
- Archive reports for trending analysis

---

## Troubleshooting

### Issue: "AWS was not authenticated"

**Cause**: Missing or invalid AWS credentials

**Solution:**
```powershell
# Configure credentials
aws configure

# Verify credentials work
aws sts get-caller-identity

# Test with PowerShell
Get-AWSCredential -ListProfileDetail
```

### Issue: "Unable to find module AWSPowerShell.NetCore"

**Cause**: AWS PowerShell module not installed

**Solution:**
```powershell
# Install module
Install-Module -Name AWSPowerShell.NetCore -Force -AllowClobber

# Import module
Import-Module AWSPowerShell.NetCore
```

### Issue: "Access Denied" errors

**Cause**: Insufficient IAM permissions

**Solution:**
- Review required permissions section above
- Attach necessary IAM policies to user/role
- Verify permissions with AWS IAM Policy Simulator

### Issue: "Region not found"

**Cause**: Invalid AWS region specified

**Solution:**
```powershell
# List available regions
Get-AWSRegion

# Use valid region code
.\Get-AWSResourceInventory.ps1 -Region us-east-1
```

---

## Related Resources

- 📖 [Script Catalog](Script-Catalog.md)
- 📖 [scripts/cloud](../scripts/cloud/README.md)
- 📖 [Common Use Cases](Common-Use-Cases.md)
- 🔗 [AWS PowerShell Documentation](https://aws.amazon.com/powershell/)
- 🔗 [AWS CLI Reference](https://docs.aws.amazon.com/cli/)

---

**Scripts Covered:** 1 AWS script
