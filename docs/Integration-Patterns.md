# 🔗 Integration Patterns Guide

![Automation](https://img.shields.io/badge/automation-task_scheduler-blue)
![Integration](https://img.shields.io/badge/integration-CI/CD-green)
![Monitoring](https://img.shields.io/badge/monitoring-enabled-success)

> **How to integrate Bug-Free Umbrella scripts with automation platforms and monitoring tools**

---

## 📋 Table of Contents
- [Overview](#overview)
- [Task Scheduler Integration](#task-scheduler-integration)
- [CI/CD Platform Integration](#cicd-platform-integration)
- [SIEM and Monitoring](#siem-and-monitoring-integration)
- [Email Reporting](#email-reporting)
- [Custom Integrations](#custom-integrations)

---

## Overview

![Platform Support](https://img.shields.io/badge/platforms-Task_Scheduler_|_Azure_DevOps_|_GitHub_Actions_|_GitLab_CI-blue)

Bug-Free Umbrella scripts are designed to integrate with:
- ✅ Windows Task Scheduler (native)
- ✅ Azure DevOps Pipelines (monitoring only)
- ✅ GitHub Actions (monitoring only)
- ✅ GitLab CI (monitoring only)
- ⚠️ Azure Automation (requires adaptation)
- ⚠️ SIEM platforms (via JSON export)
- ⚠️ Logic Apps (requires adaptation)

**Note**: Most scripts are designed for local execution with Task Scheduler. Cloud orchestration platforms require modification.

---

## Task Scheduler Integration

![Supported](https://img.shields.io/badge/status-fully_supported-success)
![Platform](https://img.shields.io/badge/platform-Windows-blue)

### Quick Start

**Automated Task Registration** - Use our pre-built script:

```powershell
# Register all 7 monitoring tasks
.\examples\automation\register-scheduled-tasks.ps1

# Custom prefix
.\examples\automation\register-scheduled-tasks.ps1 -TaskPrefix "MyCompany"
```

**This creates:**
- Daily IT reporting (8:00 AM)
- Weekly health checks (Sunday 6:00 AM)
- Monthly compliance audits (1st of month, 7:00 AM)
- Certificate expiration monitoring (Daily 9:00 AM)
- Stale device cleanup (Weekly Sunday 8:00 AM)
- Failed login monitoring (Daily 7:00 AM)
- Intune connectivity check (Hourly)

### Manual Task Creation

**Example: Daily Compliance Report**

```powershell
# Create scheduled task action
$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -File `"C:\Scripts\Get-IntuneDeviceCompliance.ps1`" -ComplianceState NonCompliant -ExportHTML -EmailReport -EmailTo admin@company.com"

# Create trigger (daily at 8 AM)
$trigger = New-ScheduledTaskTrigger -Daily -At 8:00AM

# Create task settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable

# Register task
Register-ScheduledTask `
    -TaskName "BFU - Daily Compliance Report" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -User "SYSTEM" `
    -RunLevel Highest `
    -Description "Daily Intune compliance report"
```

### Best Practices

**Scheduling Guidelines:**
- 🕐 **Daily tasks**: Run during off-hours (6-9 AM)
- 🕐 **Weekly tasks**: Sunday mornings
- 🕐 **Monthly tasks**: 1st of month, early morning
- ⚠️ **Avoid**: Peak business hours (9 AM - 5 PM)

**Authentication:**
```powershell
# Use SYSTEM account for local operations
-User "SYSTEM" -RunLevel Highest

# Use service account for M365/Azure operations
-User "svc-automation@company.com" -Password (Read-Host -AsSecureString)
```

---

## CI/CD Platform Integration

![Azure DevOps](https://img.shields.io/badge/Azure_DevOps-monitoring-0078D7?logo=azuredevops)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-monitoring-2088FF?logo=githubactions)
![GitLab CI](https://img.shields.io/badge/GitLab_CI-monitoring-FCA121?logo=gitlab)

### Monitoring CI/CD Pipelines

**Available Scripts:**
- `Monitor-AzureDevOpsPipelines.ps1` - Azure DevOps monitoring
- `Monitor-GitHubActions.ps1` - GitHub Actions monitoring
- `Monitor-GitLabCI.ps1` - GitLab CI monitoring

### Azure DevOps Example

```powershell
# Daily pipeline health report
.\Monitor-AzureDevOpsPipelines.ps1 `
    -Organization "mycompany" `
    -Project "ProductionApp" `
    -PAT $env:AZDO_PAT `
    -Days 7 `
    -ExportHTML `
    -EmailReport `
    -EmailTo "devops@company.com"
```

**Schedule with Task Scheduler:**
```powershell
$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-File C:\Scripts\Monitor-AzureDevOpsPipelines.ps1 -Organization mycompany -Project ProductionApp -PAT `$env:AZDO_PAT -ExportHTML"

$trigger = New-ScheduledTaskTrigger -Daily -At 9:00AM

Register-ScheduledTask -TaskName "DevOps Pipeline Monitor" -Action $action -Trigger $trigger
```

### GitHub Actions Example

```powershell
# Monitor self-hosted runner health
.\Monitor-GitHubActions.ps1 `
    -Owner "mycompany" `
    -Repository "production-api" `
    -Token $env:GITHUB_TOKEN `
    -CheckRunners `
    -ExportHTML
```

### GitLab CI Example

```powershell
# Pipeline success rate analysis
.\Monitor-GitLabCI.ps1 `
    -GitLabUrl "https://gitlab.company.com" `
    -ProjectId 123 `
    -Token $env:GITLAB_TOKEN `
    -Days 30 `
    -ExportJSON
```

---

## SIEM and Monitoring Integration

![JSON Export](https://img.shields.io/badge/format-JSON-orange)
![Monitoring](https://img.shields.io/badge/integration-via_export-yellow)

### Overview

While Bug-Free Umbrella doesn't have native SIEM connectors, most scripts support **JSON export** for consumption by monitoring platforms.

**Supported Export Formats:**
- ✅ JSON (machine-readable)
- ✅ CSV (spreadsheet/database import)
- ✅ HTML (human-readable reports)

### Integration Pattern

**Step 1: Export to JSON**
```powershell
# Export security compliance data
.\Invoke-SecurityComplianceScan.ps1 -ExportJSON -OutputPath "C:\Monitoring\compliance.json"
```

**Step 2: Push to Monitoring Platform**
```powershell
# Example: Push to custom monitoring API
$jsonData = Get-Content "C:\Monitoring\compliance.json" -Raw

Invoke-RestMethod `
    -Uri "https://monitoring.company.com/api/ingest" `
    -Method Post `
    -Body $jsonData `
    -ContentType "application/json" `
    -Headers @{ "Authorization" = "Bearer $token" }
```

### Example SIEM Integration Workflow

```powershell
# Complete workflow: Scan → Export → Ingest

# 1. Run security scan
.\Invoke-SecurityComplianceScan.ps1 -ExportJSON -OutputPath "C:\Temp\scan.json"

# 2. Load JSON
$scanData = Get-Content "C:\Temp\scan.json" -Raw | ConvertFrom-Json

# 3. Transform for SIEM
$siemPayload = @{
    timestamp = Get-Date -Format "o"
    source = $env:COMPUTERNAME
    type = "security_compliance"
    data = $scanData
} | ConvertTo-Json -Depth 10

# 4. Send to SIEM
Invoke-RestMethod -Uri "https://siem.company.com/api" -Method Post -Body $siemPayload
```

### Scheduled SIEM Integration

```powershell
# Create wrapper script: push-to-siem.ps1
param([string]$ScriptPath, [string]$SiemEndpoint)

# Run script and capture JSON output
& $ScriptPath -ExportJSON -OutputPath "C:\Temp\output.json"

# Push to SIEM
$data = Get-Content "C:\Temp\output.json" -Raw
Invoke-RestMethod -Uri $SiemEndpoint -Method Post -Body $data -ContentType "application/json"

# Cleanup
Remove-Item "C:\Temp\output.json"
```

**Schedule:**
```powershell
$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-File C:\Scripts\push-to-siem.ps1 -ScriptPath C:\Scripts\Get-SecurityStatus.ps1 -SiemEndpoint https://siem.company.com/api"

$trigger = New-ScheduledTaskTrigger -Daily -At 10:00AM
Register-ScheduledTask -TaskName "SIEM Integration" -Action $action -Trigger $trigger
```

---

## Email Reporting

![SMTP](https://img.shields.io/badge/protocol-SMTP-blue)
![Supported](https://img.shields.io/badge/status-fully_supported-success)

### Overview

Most scripts support automated email reporting with HTML attachments.

### Configuration Pattern

```powershell
# Scripts with email support typically accept:
-EmailReport              # Enable email
-EmailTo "admin@company.com"   # Recipient
-EmailFrom "automation@company.com"  # Sender (optional)
-SmtpServer "smtp.company.com"  # SMTP server (optional)
```

### Example: Daily Health Report

```powershell
# Server health with email
.\Monitor-ServerHealth.ps1 `
    -ComputerName "SERVER01" `
    -IncludeDiskIO `
    -CheckWindowsUpdate `
    -EmailReport `
    -EmailTo "ops-team@company.com" `
    -SmtpServer "smtp.office365.com"
```

### Example: Compliance Alerting

```powershell
# Alert on non-compliant devices
$nonCompliant = .\Get-IntuneDeviceCompliance.ps1 -ComplianceState NonCompliant

if ($nonCompliant.Count -gt 0) {
    Send-MailMessage `
        -To "compliance@company.com" `
        -From "automation@company.com" `
        -Subject "ALERT: $($nonCompliant.Count) Non-Compliant Devices" `
        -Body "See attached report" `
        -Attachments "C:\Reports\compliance.html" `
        -SmtpServer "smtp.company.com"
}
```

### Automated Daily Reporting

**Use Our Pre-Built Script:**
```powershell
# Run daily automated reporting (7 checks)
.\examples\automation\scheduled-daily-reporting.ps1 `
    -EmailTo "it-team@company.com" `
    -SmtpServer "smtp.company.com"
```

**This includes:**
- Device compliance report
- BitLocker encryption status
- Windows Update compliance
- Security compliance (CIS)
- Failed login attempts
- Certificate expiration warnings
- Stale device identification

---

## Custom Integrations

### Azure Automation (Requires Adaptation)

⚠️ **Note**: Scripts need modification for Azure Automation runbooks.

**Required Changes:**
1. Replace local file paths with Azure Storage
2. Use Azure Automation credentials instead of local auth
3. Modify output methods (no interactive console)

**Example Adaptation:**
```powershell
# Original local script
.\Get-ServerHealth.ps1 -ExportHTML -OutputPath "C:\Reports\health.html"

# Adapted for Azure Automation
.\Get-ServerHealth.ps1 -ExportHTML -OutputPath $env:TEMP
$htmlContent = Get-Content "$env:TEMP\health.html" -Raw

# Upload to Azure Storage
$storageAccount = Get-AutomationVariable -Name "StorageAccountName"
# ... upload logic
```

### Logic Apps (Requires Adaptation)

⚠️ **Note**: Scripts designed for local execution, not HTTP triggers.

**Integration Pattern:**
1. Create Azure Function wrapper
2. Call PowerShell script from function
3. Trigger function from Logic App

### REST API Integration

**JSON Export Pattern:**
```powershell
# Export to JSON
.\Get-IntuneDeviceCompliance.ps1 -ExportJSON -OutputPath "compliance.json"

# POST to API
$json = Get-Content "compliance.json" -Raw
Invoke-RestMethod -Uri "https://api.company.com/compliance" -Method Post -Body $json -ContentType "application/json"
```

---

## Related Resources

- 📖 [Script Catalog](Script-Catalog.md)
- 📖 [Workflows](Workflows.md)
- 📖 [Common Use Cases](Common-Use-Cases.md)
- 📂 [Automation Examples](../examples/automation/)
- 🔗 [Task Scheduler Documentation](https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page)

---

**Integration Types Covered:** 7 platforms
