# Security Policy

## Supported Versions

We release patches for security vulnerabilities for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 2.0.x   | :white_check_mark: |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

The Bug-Free Umbrella team takes security bugs seriously. We appreciate your efforts to responsibly disclose your findings.

### How to Report

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to the repository maintainers:

1. **Email**: [Create a private security advisory](https://github.com/Carme99/bug-free-umbrella/security/advisories/new)
2. **Alternatively**: Open a private issue with the `security` label

### What to Include

When reporting a vulnerability, please include:

- **Type of issue** (e.g., buffer overflow, SQL injection, cross-site scripting, etc.)
- **Full paths** of source file(s) related to the manifestation of the issue
- **Location** of the affected source code (tag/branch/commit or direct URL)
- **Step-by-step instructions** to reproduce the issue
- **Proof-of-concept or exploit code** (if possible)
- **Impact** of the issue, including how an attacker might exploit it

### Response Timeline

- **Initial Response**: Within 48 hours
- **Status Update**: Within 7 days
- **Fix Timeline**: Depends on severity
  - Critical: 1-7 days
  - High: 7-30 days
  - Medium: 30-90 days
  - Low: 90+ days or next release

## Security Best Practices

### For Script Usage

1. **Review Before Execution**
   - Always review scripts before running them
   - Understand what the script does
   - Check for hardcoded credentials or sensitive data

2. **Use Least Privilege**
   - Run scripts with minimum required permissions
   - Avoid running as Domain Admin unless necessary
   - Use service accounts with limited scope

3. **Secure Credentials**
   - Never hardcode passwords or API keys
   - Use secure credential storage (Azure Key Vault, Windows Credential Manager)
   - Implement proper secret management

4. **Validate Input**
   - Scripts validate parameters where possible
   - Review user input validation in custom modifications
   - Be cautious with external data sources

5. **Audit Logging**
   - Enable logging for audit trails
   - Monitor script execution
   - Review generated reports for sensitive data

### For Development

1. **Code Review**
   - All code changes require review
   - Security-sensitive changes require security review
   - Use PSScriptAnalyzer for static analysis

2. **Dependencies**
   - Keep PowerShell modules updated
   - Review module dependencies
   - Use trusted module sources (PowerShell Gallery)

3. **Testing**
   - Test in isolated environments first
   - Include security test cases
   - Validate error handling

4. **Sensitive Data**
   - Never commit credentials
   - Use .gitignore for sensitive files
   - Sanitize logs and reports

## Known Security Considerations

### Proactive Remediations

**Run as SYSTEM**: Proactive remediation scripts run with SYSTEM privileges in Intune.

- **Risk**: Malicious modifications could compromise devices
- **Mitigation**:
  - Review all scripts before deployment
  - Test in pilot groups
  - Use code signing
  - Monitor execution results

### M365 Scripts

**Required Permissions**: M365 scripts require elevated permissions.

- **Risk**: Misuse could modify user settings organization-wide
- **Mitigation**:
  - Use AuditOnly mode first
  - Implement approval workflows
  - Log all changes
  - Limit script access to authorized personnel

### API Credentials

**Graph API / Azure Connections**: Scripts connect to Microsoft services.

- **Risk**: Credential exposure or misuse
- **Mitigation**:
  - Use interactive authentication where possible
  - Implement MFA for admin accounts
  - Use application permissions with least privilege
  - Rotate credentials regularly

## Security Features

### Input Validation

Scripts implement parameter validation:
- Mandatory parameters checked
- Email format validation
- Path existence verification
- Range validation for numeric values

### Error Handling

- Try-catch blocks prevent information leakage
- Error messages avoid exposing sensitive details
- Failed operations logged for review

### Audit Trail

- All major operations generate output
- HTML/CSV reports for tracking
- Timestamps on all actions
- Success/failure tracking

## Compliance

### Standards Adherence

Scripts follow security best practices from:
- Microsoft Security Best Practices
- CIS Benchmarks (where applicable)
- NIST Cybersecurity Framework
- PowerShell Security Best Practices

### Data Privacy

- **PII Handling**: Scripts may process personal identifiable information
- **Data Residency**: Respect data residency requirements
- **GDPR**: Be aware of data protection regulations
- **Retention**: Implement appropriate data retention policies

## Secure Configuration

### Recommended Settings

```powershell
# Use TLS 1.2 or higher
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Set execution policy appropriately
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Enable script block logging (for audit)
# Via GPO: Computer Configuration > Administrative Templates > Windows Components >
# Windows PowerShell > Turn on PowerShell Script Block Logging
```

### Code Signing

For production environments:

1. **Obtain Code Signing Certificate**
   - Internal CA or trusted public CA
   - Protect private key appropriately

2. **Sign Scripts**
   ```powershell
   $cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert
   Set-AuthenticodeSignature -FilePath script.ps1 -Certificate $cert
   ```

3. **Enforce Signature**
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy AllSigned
   ```

## Third-Party Dependencies

### PowerShell Modules

Current dependencies:
- Microsoft.Graph (Microsoft)
- ExchangeOnlineManagement (Microsoft)
- MicrosoftTeams (Microsoft)
- PnP.PowerShell (Community - verify source)
- Pester (Community - testing only)

### Verification

```powershell
# Verify module publisher
Get-Module -Name ModuleName -ListAvailable | Select-Object Name, Version, CompanyName

# Check module signature
Get-AuthenticodeSignature -FilePath "C:\Path\To\Module.psm1"
```

## Incident Response

### If You Discover a Vulnerability

1. **Stop Using**: Discontinue use of affected scripts
2. **Assess Impact**: Determine scope of potential exposure
3. **Report**: Follow reporting guidelines above
4. **Monitor**: Watch for unusual activity
5. **Update**: Apply patches when available

### If Credentials Are Exposed

1. **Rotate Immediately**: Change all affected credentials
2. **Review Audit Logs**: Check for unauthorized access
3. **Notify**: Inform affected parties
4. **Investigate**: Determine scope of exposure

## Security Updates

Security updates will be:
- Announced via GitHub Security Advisories
- Documented in CHANGELOG.md
- Released as soon as possible after verification

## Contact

For security concerns:
- GitHub Security Advisories (preferred)
- Repository maintainer email (via GitHub profile)
- Private GitHub issue with `security` label

**Do not disclose security issues publicly until a fix is available.**

---

**Last Updated**: 2025-12-28
**Security Policy Version**: 1.0
