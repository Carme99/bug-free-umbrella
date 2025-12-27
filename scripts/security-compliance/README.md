# Security & Compliance Scripts


> **⚠️ IMPORTANT NOTICE**: The vast majority of scripts in this repository have not been thoroughly tested in production environments. Please test all scripts in a non-production environment first and validate the results before relying on this data for operational decisions.

Comprehensive PowerShell scripts for security auditing, compliance verification, and vulnerability assessment across Windows endpoints and servers.

## Overview

This collection provides security professionals and IT administrators with tools to:
- Verify security baselines and hardening configurations
- Audit local administrator access and privileged accounts
- Identify security vulnerabilities and misconfigurations
- Monitor for suspicious activity and security events
- Generate compliance reports for audits and certifications
- Validate security features (TPM, Credential Guard, Secure Boot, etc.)

## Scripts

### 1. Get-SecurityBaseline.ps1
**Purpose**: Verify system security settings against industry-standard baselines (CIS, Microsoft Security Baseline, etc.)

**Features**:
- Password policy verification (complexity, length, age)
- Account lockout policy checks
- Audit policy configuration
- User rights assignment validation
- Security options verification
- Windows Firewall status
- UAC configuration check
- Windows Defender status

**Usage**:
```powershell
# Standard security baseline check
.\Get-SecurityBaseline.ps1

# Generate HTML report
.\Get-SecurityBaseline.ps1 -ExportReport

# Check against specific baseline type
.\Get-SecurityBaseline.ps1 -BaselineType CIS
```

**Output**: Console display with color-coded results, optional HTML/CSV reports
**Exit Code**: 0 = All checks passed, 1 = One or more issues found

---

### 2. Get-LocalAdminAudit.ps1
**Purpose**: Audit all local administrator accounts across the system

**Features**:
- Lists all members of local Administrators group
- Identifies non-standard admin accounts
- Shows last logon time for admin accounts
- Checks for disabled/enabled status
- Flags accounts without password expiration
- LAPS (Local Administrator Password Solution) validation
- Domain vs local account identification

**Usage**:
```powershell
# Audit local administrators
.\Get-LocalAdminAudit.ps1

# Include detailed account properties
.\Get-LocalAdminAudit.ps1 -Detailed

# Export to CSV
.\Get-LocalAdminAudit.ps1 -ExportReport
```

**Output**: List of administrator accounts with security details
**Exit Code**: 0 = Only expected admins, 1 = Unexpected admin accounts found

---

### 3. Get-OpenPortScan.ps1
**Purpose**: Scan for open network ports and listening services

**Features**:
- Lists all listening TCP/UDP ports
- Identifies processes using each port
- Flags unexpected or risky open ports
- Checks for common vulnerable services
- Remote Desktop (RDP) exposure check
- SMB/NetBIOS security review
- Service identification and risk assessment

**Usage**:
```powershell
# Scan all open ports
.\Get-OpenPortScan.ps1

# Show only high-risk ports
.\Get-OpenPortScan.ps1 -HighRiskOnly

# Include UDP ports (slower)
.\Get-OpenPortScan.ps1 -IncludeUDP

# Export findings
.\Get-OpenPortScan.ps1 -ExportReport
```

**Output**: Open ports with associated processes and risk ratings
**Exit Code**: 0 = No risky ports, 1 = Potentially risky ports detected

---

### 4. Test-SecurityFeatures.ps1
**Purpose**: Verify modern Windows security features are enabled and functional

**Features**:
- TPM (Trusted Platform Module) status and version
- Secure Boot verification
- Credential Guard status
- Device Guard / WDAC status
- Virtualization-based Security (VBS)
- BitLocker encryption status
- Windows Defender status and definitions
- UEFI vs Legacy BIOS detection
- Exploit Protection (DEP, ASLR, CFG)

**Usage**:
```powershell
# Check all security features
.\Test-SecurityFeatures.ps1

# Generate compliance report
.\Test-SecurityFeatures.ps1 -ExportReport

# Show recommendations for missing features
.\Test-SecurityFeatures.ps1 -ShowRecommendations
```

**Output**: Security feature status with recommendations
**Exit Code**: 0 = All features enabled, 1 = Missing security features

---

### 5. Get-ExpiredCertificates.ps1
**Purpose**: Find expired or expiring certificates in all certificate stores

**Features**:
- Scans all certificate stores (Computer and User)
- Identifies expired certificates
- Warns about certificates expiring soon (configurable threshold)
- Shows certificate details (issuer, subject, thumbprint)
- Checks for self-signed certificates
- Validates certificate chains
- Identifies revoked certificates

**Usage**:
```powershell
# Find expired certificates
.\Get-ExpiredCertificates.ps1

# Check for certificates expiring in 30 days
.\Get-ExpiredCertificates.ps1 -DaysToExpire 30

# Include all certificate stores
.\Get-ExpiredCertificates.ps1 -AllStores

# Export findings
.\Get-ExpiredCertificates.ps1 -ExportReport
```

**Output**: List of expired/expiring certificates with details
**Exit Code**: 0 = No issues, 1 = Expired/expiring certificates found

---

### 6. Get-FailedLoginReport.ps1
**Purpose**: Analyze security event logs for failed login attempts and suspicious activity

**Features**:
- Failed login attempt detection (Event ID 4625)
- Account lockout monitoring (Event ID 4740)
- Successful logins after failures (Event ID 4624)
- Brute force attack pattern detection
- Remote Desktop login failures
- Groups accounts by failure count
- Time-based analysis (last 24h, 7d, 30d)
- Source IP identification (for network logins)

**Usage**:
```powershell
# Analyze last 24 hours
.\Get-FailedLoginReport.ps1

# Check last 7 days
.\Get-FailedLoginReport.ps1 -Hours 168

# Show top 10 most targeted accounts
.\Get-FailedLoginReport.ps1 -TopCount 10

# Export detailed report
.\Get-FailedLoginReport.ps1 -ExportReport
```

**Output**: Failed login statistics with pattern analysis
**Exit Code**: 0 = No suspicious activity, 1 = Failed logins or lockouts detected

---

### 7. Get-USBDeviceAudit.ps1
**Purpose**: Audit USB device connections and usage history

**Features**:
- Lists currently connected USB devices
- Shows historical USB device connections from registry
- Identifies device serial numbers and manufacturers
- Detects unauthorized USB devices (with authorized vendor list)
- Extracts vendor ID (VID) and product ID (PID)
- Tracks first connection time
- Export to HTML and CSV formats

**Usage**:
```powershell
# Basic USB device audit
.\Get-USBDeviceAudit.ps1

# Include historical connections
.\Get-USBDeviceAudit.ps1 -IncludeHistory $true

# Highlight unauthorized devices
.\Get-USBDeviceAudit.ps1 -AuthorizedVendors @("045E", "046D") -HighlightUnauthorized

# Generate HTML report
.\Get-USBDeviceAudit.ps1 -OutputFormat HTML -OutputPath "C:\Reports"
```

**Output**: List of USB devices with authorization status
**Exit Code**: 0 = Audit completed successfully

---

### 8. Get-SoftwareLicenseCompliance.ps1
**Purpose**: Inventory installed software and check license compliance

**Features**:
- Complete software inventory from registry
- License key detection for major applications (Office, Windows)
- Software installation dates and publishers
- Identification of unlicensed software
- Duplicate software installation detection
- License status verification (Licensed/Unlicensed/Unknown)
- Export to HTML and CSV formats

**Usage**:
```powershell
# Basic software inventory
.\Get-SoftwareLicenseCompliance.ps1

# Enable license key checking
.\Get-SoftwareLicenseCompliance.ps1 -CheckLicenseKeys $true

# Highlight potentially unlicensed software
.\Get-SoftwareLicenseCompliance.ps1 -HighlightUnlicensed $true

# Generate compliance report
.\Get-SoftwareLicenseCompliance.ps1 -OutputFormat HTML -OutputPath "C:\Reports"
```

**Output**: Software inventory with license compliance status
**Exit Code**: 0 = Inventory completed successfully

---

### 9. Get-AntivirusStatus.ps1
**Purpose**: Check antivirus and endpoint protection status

**Features**:
- Windows Defender/Microsoft Defender status
- Third-party antivirus detection
- Real-time protection verification
- Signature/definition update status
- Scan history and last scan time
- Threat detection history
- Windows Firewall status across all profiles
- Export to HTML and CSV formats

**Usage**:
```powershell
# Check antivirus status
.\Get-AntivirusStatus.ps1

# Include third-party AV detection
.\Get-AntivirusStatus.ps1 -CheckThirdParty $true

# Generate detailed report
.\Get-AntivirusStatus.ps1 -OutputFormat HTML -OutputPath "C:\Reports"
```

**Output**: Comprehensive antivirus and firewall status
**Exit Code**: 0 = Protection is active, 1 = Issues detected

---

## Common Workflows

### Monthly Security Audit
```powershell
# Run all security checks
cd scripts\security-compliance

.\Get-SecurityBaseline.ps1 -ExportReport
.\Get-LocalAdminAudit.ps1 -ExportReport
.\Test-SecurityFeatures.ps1 -ExportReport
.\Get-ExpiredCertificates.ps1 -DaysToExpire 60 -ExportReport
.\Get-FailedLoginReport.ps1 -Hours 720 -ExportReport

# Review all reports on Desktop
```

### Incident Response - Initial Assessment
```powershell
# Quick security posture check
.\Get-FailedLoginReport.ps1 -Hours 24
.\Get-OpenPortScan.ps1 -HighRiskOnly
.\Get-LocalAdminAudit.ps1
.\Test-SecurityFeatures.ps1
```

### Compliance Preparation
```powershell
# Generate compliance documentation
.\Get-SecurityBaseline.ps1 -BaselineType CIS -ExportReport
.\Test-SecurityFeatures.ps1 -ExportReport
.\Get-LocalAdminAudit.ps1 -Detailed -ExportReport
```

### Pre-Deployment Hardening Check
```powershell
# Verify system meets security requirements
.\Test-SecurityFeatures.ps1 -ShowRecommendations
.\Get-SecurityBaseline.ps1
.\Get-OpenPortScan.ps1
```

## Requirements

### All Scripts
- **PowerShell 5.1 or later** (PowerShell 7+ recommended)
- **Administrator privileges** (required for security auditing)
- **Windows 10/11** or **Windows Server 2016+**

### Specific Scripts
- **Get-FailedLoginReport.ps1**: Requires access to Security event log
- **Test-SecurityFeatures.ps1**: Works best on UEFI systems with TPM 2.0
- **Get-ExpiredCertificates.ps1**: No additional requirements

## Permissions Required

Most scripts require **Administrator** or **elevated** privileges to:
- Read security event logs
- Query system security settings
- Access certificate stores
- Enumerate local accounts and groups
- Check network configurations

## Expected Execution Times

| Script | Typical Duration |
|--------|------------------|
| Get-SecurityBaseline.ps1 | 30-60 seconds |
| Get-LocalAdminAudit.ps1 | 10-20 seconds |
| Get-OpenPortScan.ps1 | 20-40 seconds |
| Test-SecurityFeatures.ps1 | 15-30 seconds |
| Get-ExpiredCertificates.ps1 | 30-90 seconds |
| Get-FailedLoginReport.ps1 | 1-5 minutes (depends on log size) |

## Output Locations

All scripts save reports to: `C:\Users\[YourName]\Desktop\`

**Report Formats**:
- HTML reports with color-coded results
- CSV exports for data analysis
- Console output with real-time progress

## Security Considerations

- Scripts perform **read-only** operations (no system modifications)
- No credentials are stored or transmitted
- All operations are logged locally
- Reports may contain sensitive information - handle appropriately
- Review scripts before running in production environments

## Troubleshooting

### "Access Denied" Errors
- Ensure you're running PowerShell as Administrator
- Check that execution policy allows script execution
- Verify you have permissions to read event logs

### No Events Found in Get-FailedLoginReport.ps1
- Verify audit policy is enabled: `auditpol /get /category:*`
- Check Event Viewer for Security log access
- Ensure "Audit logon events" is enabled in Group Policy

### TPM Not Detected in Test-SecurityFeatures.ps1
- Verify TPM is enabled in BIOS/UEFI
- Check Device Manager for TPM device
- Run: `Get-Tpm` to verify TPM availability

### Certificate Store Access Issues
- Ensure running as Administrator
- Some stores require specific permissions
- Check Windows Certificate Manager (certmgr.msc)

## Integration with Intune

These scripts can be deployed via Intune Proactive Remediations:

1. **Detection Script**: Run security check (e.g., Get-SecurityBaseline.ps1)
2. **Remediation Script**: Apply fixes or generate alerts
3. **Schedule**: Weekly or monthly for compliance monitoring
4. **Reporting**: Centralized compliance status in Intune portal

See the [Proactive Remediations guide](../device-management/proactive-remediations/README.md) for deployment details.

## Best Practices

1. **Regular Audits**: Run security checks monthly at minimum
2. **Baseline Documentation**: Establish and document your security baseline
3. **Change Tracking**: Compare reports over time to detect configuration drift
4. **Incident Response**: Use scripts for initial triage and evidence collection
5. **Compliance**: Align checks with your industry standards (CIS, NIST, HIPAA, etc.)
6. **Test First**: Always test in non-production before deploying widely

## Contributing

When adding new security scripts:
- Follow existing naming conventions (Verb-Noun.ps1)
- Include comprehensive comment-based help
- Implement -ExportReport parameter for HTML/CSV output
- Use consistent exit codes (0 = pass, 1 = issues found)
- Add usage examples to this README
- Test on both client and server OS versions

## Support

For issues or questions:
1. Check script's built-in help: `Get-Help .\ScriptName.ps1 -Detailed`
2. Review [Troubleshooting Guide](../../docs/TROUBLESHOOTING.md)
3. Test with `-Verbose` parameter for detailed output
4. Verify prerequisites and permissions

## License

Licensed under the Apache License 2.0. See [LICENSE](../../LICENSE) for details.
