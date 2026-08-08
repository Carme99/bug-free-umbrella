# Security & Compliance

Comprehensive security auditing, compliance testing, and system hardening scripts for enterprise environments. These scripts help ensure your infrastructure meets security standards and regulatory requirements.

## Overview

The Security & Compliance category provides tools for:
- **Compliance Testing** - CIS Benchmarks, security baselines, and regulatory frameworks
- **Security Auditing** - Local admin rights, failed logins, USB devices, and antivirus status
- **Microsoft Defender** - Endpoint health monitoring and threat detection
- **System Monitoring** - Health checks, performance tracking, and battery monitoring
- **Security Hardening** - Automated compliance scanning and remediation

All scripts are located in: [scripts/security/](../scripts/security/README.md)

---

## Script Categories

### Compliance & Frameworks
Testing and auditing against industry-standard security frameworks.

| Script | Description | Location |
|--------|-------------|----------|
| **Test-CISBenchmark.ps1** | CIS Benchmark compliance testing for Windows Server | [`scripts/security/compliance/frameworks/`](../scripts/security/compliance/frameworks/README.md) |
| **Test-SecurityFeatures.ps1** | Validate Windows security features configuration | [`scripts/security/compliance/frameworks/`](../scripts/security/compliance/frameworks/README.md) |
| **Get-SecurityBaseline.ps1** | Retrieve and compare security baseline settings | [`scripts/security/compliance/frameworks/`](../scripts/security/compliance/frameworks/README.md) |
| **Get-AntivirusStatus.ps1** | Audit antivirus installation and update status | [`scripts/security/compliance/frameworks/`](../scripts/security/compliance/frameworks/README.md) |
| **Get-LocalAdminAudit.ps1** | Audit local administrator group membership | [`scripts/security/compliance/frameworks/`](../scripts/security/compliance/frameworks/README.md) |
| **Get-FailedLoginReport.ps1** | Generate report of failed login attempts | [`scripts/security/compliance/frameworks/`](../scripts/security/compliance/frameworks/README.md) |
| **Get-USBDeviceAudit.ps1** | Track USB device connections and usage | [`scripts/security/compliance/frameworks/`](../scripts/security/compliance/frameworks/README.md) |
| **Get-ExpiredCertificates.ps1** | Find expired or expiring certificates | [`scripts/security/compliance/frameworks/`](../scripts/security/compliance/frameworks/README.md) |
| **Get-OpenPortScan.ps1** | Scan for open network ports and services | [`scripts/security/compliance/frameworks/`](../scripts/security/compliance/frameworks/README.md) |
| **Get-SoftwareLicenseCompliance.ps1** | Audit software license compliance | [`scripts/security/compliance/frameworks/`](../scripts/security/compliance/frameworks/README.md) |

### Microsoft Defender Endpoint
Monitor and manage Microsoft Defender for Endpoint (MDE) devices.

| Script | Description | Location |
|--------|-------------|----------|
| **Get-MDEDeviceHealth.ps1** | Retrieve MDE device health and onboarding status | [`scripts/security/compliance/defender-endpoint/`](../scripts/security/compliance/defender-endpoint/) |

### Security Hardening
Automated security compliance scanning and hardening.

| Script | Description | Location |
|--------|-------------|----------|
| **Invoke-SecurityComplianceScan.ps1** | Comprehensive security compliance scanning | [`scripts/security/hardening/`](../scripts/security/hardening/README.md) |

### System Monitoring
Monitor system health, performance, and hardware status.

| Script | Description | Location |
|--------|-------------|----------|
| **Get-SystemHealthCheck.ps1** | Comprehensive system health assessment | [`scripts/security/monitoring/`](../scripts/security/monitoring/README.md) |
| **Get-BatteryHealth.ps1** | Monitor battery health and performance | [`scripts/security/monitoring/`](../scripts/security/monitoring/README.md) |
| **Get-PerformanceTrends.ps1** | Track system performance trends over time | [`scripts/security/monitoring/`](../scripts/security/monitoring/README.md) |
| **Get-SystemResourceTrends.ps1** | Monitor CPU, memory, and disk trends | [`scripts/security/monitoring/`](../scripts/security/monitoring/README.md) |

---

## Prerequisites

### Required Permissions
- **Administrator privileges** - Most security scripts require elevation
- **Security audit permissions** - For reading security policies and logs
- **Windows Event Log access** - For failed login and security event auditing

### Required Modules
```powershell
# No additional modules required for most scripts
# Built-in cmdlets used: Get-WmiObject, Get-EventLog, secedit.exe, auditpol.exe
```

### System Requirements
- **Windows 10/11** or **Windows Server 2016+**
- **PowerShell 5.1+** (PowerShell 7+ recommended)
- **Execution policy** set to RemoteSigned or Bypass

---

## Common Use Cases

### 1. CIS Benchmark Compliance Testing

Test your Windows Server against CIS security benchmarks to ensure compliance with industry standards.

**Basic Level 1 Test:**
```powershell
# Run Level 1 CIS benchmark tests (essential security)
.\Test-CISBenchmark.ps1

# Run with HTML report output
.\Test-CISBenchmark.ps1 -ExportHTML
```

**Advanced Level 2 Test:**
```powershell
# Run Level 2 tests (high-security environments)
.\Test-CISBenchmark.ps1 -Level 2 -ExportHTML

# Custom output path
.\Test-CISBenchmark.ps1 -Level 2 -ExportHTML -OutputPath "C:\Reports"
```

**What it checks:**
- Password policies and account lockout settings
- Audit policies and security event logging
- User rights assignments
- Security options and registry settings
- Service configurations
- Network security settings

**Sample Output:**
```
=== CIS Benchmark Compliance Test ===
Level: 1 (Essential Security)
Computer: SERVER01
Date: 2025-12-31 10:30:00

Password Policies:
[PASS] Minimum password length: 14 characters
[PASS] Password complexity: Enabled
[PASS] Maximum password age: 60 days
[FAIL] Minimum password age: 0 days (Should be 1+)

Audit Policies:
[PASS] Audit account logon events: Success, Failure
[PASS] Audit logon events: Success, Failure
[PASS] Audit object access: Success, Failure

Results: 45 Passed, 3 Failed, 2 Warnings
Compliance Score: 94%
```

### 2. Local Administrator Audit

Identify all accounts with local administrator privileges across your environment.

```powershell
# Audit local administrators on current system
.\Get-LocalAdminAudit.ps1

# Export to CSV for review
.\Get-LocalAdminAudit.ps1 -ExportCSV

# Include domain administrator groups
.\Get-LocalAdminAudit.ps1 -IncludeDomainAdmins -ExportHTML
```

**Sample Output:**
```
=== Local Administrator Audit ===
Computer: WORKSTATION01
Date: 2025-12-31

Local Administrators Group Members:
1. Administrator (Built-in account)
2. Domain Admins (Domain group)
3. john.doe (Local user) - WARNING: Non-standard admin
4. IT-Support (Domain group)

Total Admins: 4
Non-Standard Admins: 1
Recommendation: Review john.doe's admin access
```

### 3. Failed Login Report

Monitor failed login attempts to detect potential security threats.

```powershell
# Check failed logins in last 24 hours
.\Get-FailedLoginReport.ps1

# Check last 7 days with details
.\Get-FailedLoginReport.ps1 -Days 7 -Detailed

# Export HTML report
.\Get-FailedLoginReport.ps1 -Days 30 -ExportHTML
```

**Sample Output:**
```
=== Failed Login Report ===
Period: Last 24 hours
Computer: DC01

Failed Login Attempts: 47

Top Failed Accounts:
1. admin (32 attempts) - Multiple IPs detected
2. root (8 attempts) - Suspicious activity
3. administrator (5 attempts)
4. guest (2 attempts)

Top Source IPs:
1. 192.168.1.150 (20 attempts) - Internal
2. 203.0.113.45 (15 attempts) - EXTERNAL WARNING
3. 10.0.0.25 (12 attempts) - Internal

ALERT: External IP detected attempting logins
Recommendation: Review firewall rules and enable account lockout
```

### 4. USB Device Audit

Track USB device connections for security and compliance purposes.

```powershell
# List all USB devices ever connected
.\Get-USBDeviceAudit.ps1

# Show only currently connected devices
.\Get-USBDeviceAudit.ps1 -CurrentOnly

# Export full history to CSV
.\Get-USBDeviceAudit.ps1 -ExportCSV -IncludeHistory
```

### 5. System Health Check

Comprehensive system health assessment for workstations and servers.

```powershell
# Quick health check
.\Get-SystemHealthCheck.ps1

# Detailed check with HTML report
.\Get-SystemHealthCheck.ps1 -Detailed -ExportHTML

# Check specific components
.\Get-SystemHealthCheck.ps1 -CheckDisk -CheckMemory -CheckServices
```

### 6. Certificate Expiration Monitoring

Find certificates that are expired or expiring soon.

```powershell
# Find certificates expiring in next 30 days
.\Get-ExpiredCertificates.ps1

# Custom expiration window (90 days)
.\Get-ExpiredCertificates.ps1 -DaysToExpire 90

# Check specific certificate store
.\Get-ExpiredCertificates.ps1 -CertStore "LocalMachine\My" -ExportHTML
```

### 7. Antivirus Status Check

Audit antivirus installation and update status across endpoints.

```powershell
# Check antivirus status
.\Get-AntivirusStatus.ps1

# Include definition age and scan status
.\Get-AntivirusStatus.ps1 -Detailed -ExportCSV

# Alert if definitions older than 7 days
.\Get-AntivirusStatus.ps1 -MaxDefinitionAge 7
```

---

## Script Examples

### Example 1: Monthly Security Audit

Perform a comprehensive monthly security audit and generate reports.

```powershell
# Create audit directory
$AuditPath = "C:\SecurityAudits\$(Get-Date -Format 'yyyy-MM')"
New-Item -Path $AuditPath -ItemType Directory -Force

# Run CIS Benchmark
.\Test-CISBenchmark.ps1 -Level 2 -ExportHTML -OutputPath $AuditPath

# Audit local administrators
.\Get-LocalAdminAudit.ps1 -ExportCSV -OutputPath $AuditPath

# Check failed logins
.\Get-FailedLoginReport.ps1 -Days 30 -ExportHTML -OutputPath $AuditPath

# Review certificates
.\Get-ExpiredCertificates.ps1 -DaysToExpire 90 -ExportHTML -OutputPath $AuditPath

# USB device tracking
.\Get-USBDeviceAudit.ps1 -ExportCSV -OutputPath $AuditPath

Write-Host "Monthly security audit complete. Reports saved to: $AuditPath" -ForegroundColor Green
```

### Example 2: Automated Compliance Scanning

Daily automated compliance scan with email alerts.

```powershell
# Daily compliance scan script
$ReportPath = "C:\Compliance\Daily"
$Date = Get-Date -Format "yyyy-MM-dd"

# Security baseline check
$BaselineResult = .\Get-SecurityBaseline.ps1 -ExportHTML -OutputPath $ReportPath

# Security features check
$FeaturesResult = .\Test-SecurityFeatures.ps1

# Antivirus status
$AVResult = .\Get-AntivirusStatus.ps1 -Detailed

# Check for issues
$Issues = @()
if ($BaselineResult.FailedChecks -gt 0) {
    $Issues += "Security baseline: $($BaselineResult.FailedChecks) failed checks"
}
if ($FeaturesResult.ComplianceScore -lt 90) {
    $Issues += "Security features: Compliance score $($FeaturesResult.ComplianceScore)%"
}
if ($AVResult.DefinitionAge -gt 7) {
    $Issues += "Antivirus: Definitions $($AVResult.DefinitionAge) days old"
}

# Send alert if issues found
if ($Issues.Count -gt 0) {
    $EmailBody = "Security compliance issues detected:`n`n" + ($Issues -join "`n")
    Send-MailMessage -To "security@company.com" `
                     -From "compliance@company.com" `
                     -Subject "Security Compliance Alert - $Date" `
                     -Body $EmailBody `
                     -SmtpServer "smtp.company.com"
}
```

### Example 3: Pre-Audit Preparation

Prepare for security audits by collecting all necessary compliance data.

```powershell
# Pre-audit data collection
$AuditDate = Get-Date -Format "yyyy-MM-dd"
$OutputPath = "C:\Audits\PreAudit_$AuditDate"
New-Item -Path $OutputPath -ItemType Directory -Force

Write-Host "Collecting audit data..." -ForegroundColor Cyan

# Collect all compliance data
$Scripts = @{
    "CIS_Benchmark"         = ".\Test-CISBenchmark.ps1 -Level 2 -ExportHTML"
    "Security_Features"     = ".\Test-SecurityFeatures.ps1 -ExportHTML"
    "Security_Baseline"     = ".\Get-SecurityBaseline.ps1 -ExportHTML"
    "Local_Admins"          = ".\Get-LocalAdminAudit.ps1 -ExportHTML"
    "Failed_Logins"         = ".\Get-FailedLoginReport.ps1 -Days 90 -ExportHTML"
    "USB_Devices"           = ".\Get-USBDeviceAudit.ps1 -ExportHTML"
    "Certificates"          = ".\Get-ExpiredCertificates.ps1 -ExportHTML"
    "Antivirus_Status"      = ".\Get-AntivirusStatus.ps1 -ExportHTML"
    "Open_Ports"            = ".\Get-OpenPortScan.ps1 -ExportHTML"
    "License_Compliance"    = ".\Get-SoftwareLicenseCompliance.ps1 -ExportHTML"
}

foreach ($Name in $Scripts.Keys) {
    Write-Host "Running $Name..." -ForegroundColor Yellow
    $ScriptCmd = $Scripts[$Name] + " -OutputPath '$OutputPath'"
    Invoke-Expression $ScriptCmd
}

Write-Host "`nAudit data collection complete!" -ForegroundColor Green
Write-Host "Reports saved to: $OutputPath" -ForegroundColor Cyan
```

---

## Integration Examples

### Intune Deployment

Deploy security compliance checks via Intune as detection scripts.

**Step 1: Package the script**
```powershell
# Use Intune Win32 app packaging
.\New-IntuneWinPackage.ps1 -SourcePath ".\Test-CISBenchmark.ps1" `
                            -OutputPath "C:\IntunePackages"
```
The packaging script lives at [scripts/endpoints/intune/deployment/New-IntuneWinPackage.ps1](../scripts/endpoints/intune/deployment/New-IntuneWinPackage.ps1).

**Step 2: Deploy via Intune**
- Upload .intunewin package to Endpoint Manager
- Configure as Required assignment
- Schedule daily execution
- Monitor compliance in reports

### Azure Automation

Run security audits centrally using Azure Automation.

```powershell
# Azure Automation Runbook
workflow Invoke-SecurityAudit {
    param(
        [string[]]$ComputerNames
    )

    foreach -parallel ($Computer in $ComputerNames) {
        InlineScript {
            $Results = Invoke-Command -ComputerName $using:Computer -ScriptBlock {
                # Run security checks
                $CIS = .\Test-CISBenchmark.ps1 -Level 2
                $Admin = .\Get-LocalAdminAudit.ps1
                $Logins = .\Get-FailedLoginReport.ps1 -Days 7

                @{
                    Computer = $env:COMPUTERNAME
                    CISScore = $CIS.ComplianceScore
                    AdminCount = $Admin.Count
                    FailedLogins = $Logins.Count
                }
            }

            # Store results in Azure Table Storage or Log Analytics
        }
    }
}
```

---

## Best Practices

### Security Considerations
1. **Run with least privilege** - Use separate admin accounts for security audits
2. **Secure report storage** - Store audit reports in encrypted, access-controlled locations
3. **Regular scheduling** - Automate security checks on a regular cadence
4. **Review alerts promptly** - Investigate failed login attempts and security violations immediately
5. **Baseline comparisons** - Maintain security baselines and track changes over time

### Performance Tips
1. **Schedule during off-hours** - Run comprehensive audits during maintenance windows
2. **Filter results** - Use parameters to focus on specific security areas
3. **Batch processing** - Group multiple checks together efficiently
4. **Cache results** - Store audit results to avoid repeated scans

### Compliance Management
1. **Document exceptions** - Maintain records of compliance exceptions and justifications
2. **Version control** - Track changes to security baselines and policies
3. **Remediation tracking** - Document and track security remediation efforts
4. **Audit trails** - Maintain logs of all security audits and findings

---

## Troubleshooting

### Common Issues

**"Access Denied" errors:**
- Ensure you're running PowerShell as Administrator
- Check that you have security audit permissions
- Verify you can read Event Logs: `Get-EventLog -LogName Security -Newest 1`

**"secedit.exe failed" error:**
```powershell
# Test secedit manually
secedit /export /cfg C:\temp\secpol.cfg
# If this fails, check Windows security services are running
```

**No failed logins reported:**
- Verify audit policy is enabled: `auditpol /get /category:*`
- Enable logon auditing: `auditpol /set /subcategory:"Logon" /success:enable /failure:enable`

**USB audit returns no devices:**
- USB tracking is stored in registry keys that may be cleared
- Enable USB audit logging via Group Policy for future tracking

**CIS Benchmark tests fail to run:**
- Requires Administrator privileges
- Requires access to `secedit.exe` and `auditpol.exe`
- Windows Firewall must allow local security policy access

---

## 💻 Quick Start Examples

### Example 1: CIS Benchmark Audit
```powershell
# Run CIS Level 1 audit
.\Test-CISBenchmark.ps1 -Level 1 -ExportHTML

# Result: HTML compliance report
```

### Example 2: Security Compliance Scan
```powershell
# Full security scan with all checks
.\Invoke-SecurityComplianceScan.ps1 -Verbose -ExportHTML

# Quick scan (basic checks only)
.\Invoke-SecurityComplianceScan.ps1 -QuickScan
```

### Example 3: Certificate Monitoring
```powershell
# Check for expiring certificates (30 days)
.\Get-ExpiringCertificates.ps1 -DaysUntilExpiration 30 -ExportHTML
```

---

## Related Resources

### Internal Documentation
- **[Prerequisites](Prerequisites.md)** - Required modules and permissions
- **[Intune Management](Intune-Management.md)** - Deploy security scripts via Intune
- **[Server Management](Server-Management.md)** - Server-specific security scripts
- **[FAQ](FAQ.md)** - Common questions and answers

### External Resources
- **[CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks/)** - Industry security standards
- **[Microsoft Security Baselines](https://learn.microsoft.com/en-us/windows/security/threat-protection/windows-security-baselines)** - Microsoft recommended settings
- **[NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)** - Comprehensive security framework
