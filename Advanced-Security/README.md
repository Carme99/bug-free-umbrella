# Advanced Security & Compliance Scripts

> **⚠️ IMPORTANT NOTICE**: The vast majority of scripts in this repository have not been thoroughly tested in production environments. Please test all scripts in a non-production environment first and validate the results before relying on this data for operational decisions.

This category contains advanced security scanning and compliance validation scripts for enterprise environments.

## 📋 Available Scripts

### 1. Invoke-SecurityComplianceScan.ps1
Multi-framework security compliance scanner for enterprise systems.

**Supported Frameworks:**
- **CIS Benchmarks**: Windows, Linux security configurations
- **NIST 800-53**: Federal security controls
- **PCI-DSS**: Payment card industry standards
- **HIPAA**: Healthcare security requirements
- **SOC 2**: Service organization controls
- **ISO 27001**: Information security management

**Features:**
- Automated compliance scanning
- Severity-based filtering
- Compliance score calculation
- Remediation guidance
- Multi-format reporting

**Example:**
```powershell
# Scan against CIS Benchmarks
.\Invoke-SecurityComplianceScan.ps1 -Framework "CIS" -TargetSystem "Windows"

# Comprehensive scan with remediation guidance
.\Invoke-SecurityComplianceScan.ps1 -Framework "All" `
    -TargetSystem "Windows" `
    -Severity "High" `
    -RemediationGuidance `
    -OutputFormat HTML

# PCI-DSS compliance check
.\Invoke-SecurityComplianceScan.ps1 -Framework "PCI-DSS" `
    -TargetSystem "Windows" `
    -OutputFormat JSON
```

---

## 🎯 Common Use Cases

### Compliance Auditing
```powershell
# Generate compliance report for audit
.\Invoke-SecurityComplianceScan.ps1 -Framework "NIST" `
    -TargetSystem "Windows" `
    -OutputFormat HTML `
    -RemediationGuidance
```

### Security Hardening Validation
```powershell
# Check critical/high severity issues only
.\Invoke-SecurityComplianceScan.ps1 -Framework "CIS" `
    -TargetSystem "Windows" `
    -Severity "High" `
    -RemediationGuidance
```

### Continuous Compliance Monitoring
```powershell
# Daily compliance check via scheduled task
$trigger = New-ScheduledTaskTrigger -Daily -At 2am
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument @"
-File C:\Scripts\Invoke-SecurityComplianceScan.ps1 -Framework 'All' -TargetSystem 'Windows' -OutputFormat JSON
"@
Register-ScheduledTask -TaskName "Daily Compliance Scan" -Trigger $trigger -Action $action
```

---

## 📊 Compliance Frameworks

### CIS Benchmarks
Industry consensus security configuration baselines:
- Password policies and account management
- Firewall and network security
- Audit logging configuration
- Service hardening
- LAPS implementation

### NIST 800-53
Federal security controls:
- Access Control (AC)
- Audit and Accountability (AU)
- Identification and Authentication (IA)
- System and Communications Protection (SC)

### PCI-DSS
Payment card industry requirements:
- Firewall configuration
- Password and access controls
- Encryption and secure protocols
- Security monitoring and testing

### HIPAA
Healthcare security standards:
- Access controls
- Audit controls
- Integrity controls
- Transmission security

---

## 🔐 Requirements

- **PowerShell**: 5.1 or later
- **Privileges**: Administrator rights for Windows system scans
- **Access**: Local or remote system access
- **Disk Space**: Minimal (reports < 5 MB typically)

---

## 📈 Compliance Scoring

Compliance scores are calculated based on finding severity:
- **Critical**: -4 points
- **High**: -3 points
- **Medium**: -2 points
- **Low**: -1 point

**Score Interpretation:**
| Score Range | Status | Action Required |
|-------------|--------|-----------------|
| 90-100% | Excellent | Minor improvements |
| 80-89% | Good | Address high/critical findings |
| 60-79% | Fair | Significant remediation needed |
| < 60% | Poor | Immediate action required |

---

## 🛠️ Troubleshooting

### Administrator Privileges Required
```
Warning: Some checks require Administrator privileges
```
**Solution:** Run PowerShell as Administrator:
```powershell
Start-Process powershell -Verb RunAs
```

### Audit Policy Check Fails
```
Error: auditpol command not found
```
**Solution:** Ensure auditpol.exe is available (built-in Windows tool)

---

## 🔄 Integration Examples

### Azure DevOps Pipeline
```yaml
- task: PowerShell@2
  displayName: 'Security Compliance Scan'
  inputs:
    filePath: '$(System.DefaultWorkingDirectory)/Scripts/Invoke-SecurityComplianceScan.ps1'
    arguments: '-Framework "CIS" -TargetSystem "Windows" -OutputFormat JSON'
    pwsh: true
```

### Alerting on Critical Findings
```powershell
$results = .\Invoke-SecurityComplianceScan.ps1 -Framework "All" -TargetSystem "Windows" -OutputFormat JSON
$data = Get-Content $results | ConvertFrom-Json

if ($data.Summary.CriticalFindings -gt 0) {
    Send-MailMessage -To "security@company.com" `
        -Subject "⚠️ Critical Security Findings Detected" `
        -Body "Found $($data.Summary.CriticalFindings) critical security issues" `
        -SmtpServer "smtp.company.com"
}
```

---

## 📚 Additional Resources

- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks/)
- [NIST 800-53 Documentation](https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final)
- [PCI DSS Requirements](https://www.pcisecuritystandards.org/)
- [HIPAA Security Rule](https://www.hhs.gov/hipaa/for-professionals/security/index.html)

---

## ⚠️ Testing Notice

**IMPORTANT:** These scripts have not been thoroughly tested in all environments. Before using in production:

1. **Test in non-production environment**
2. **Validate findings accuracy**
3. **Review remediation steps before applying**
4. **Understand impact of changes**
5. **Maintain change control process**

---

*Generated: 2025-12-27*
