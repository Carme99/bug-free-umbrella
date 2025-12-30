# Security & Compliance Scripts

Security hardening, compliance scanning, and monitoring.

## Categories

### Compliance (`compliance/`)
- **frameworks/** - Multi-framework compliance scanning
  - CIS Benchmarks
  - NIST Cybersecurity Framework
  - PCI-DSS
  - HIPAA
  - SOC2
  - ISO27001
- **defender-endpoint/** - Microsoft Defender for Endpoint

### Hardening (`hardening/`)
- Security baseline configuration
- System hardening scripts

### Monitoring (`monitoring/`)
- Security event monitoring
- Server health checks
- Performance tracking

## Common Use Cases

- Run multi-framework compliance scans
- Harden Windows systems
- Monitor security events
- Generate compliance reports
- Track security posture

## Prerequisites

**Compliance Scripts:**
- PowerShell 5.1+
- Administrator privileges
- Target systems to scan

**Hardening Scripts:**
- Administrator privileges
- Backup before hardening

## Quick Start

**Run Compliance Scan:**
```powershell
.\compliance\frameworks\Invoke-SecurityComplianceScan.ps1 -Framework CIS
```

**Multi-Framework Audit:**
```powershell
.\compliance\frameworks\Invoke-SecurityComplianceScan.ps1 -Framework CIS,NIST,PCI-DSS -ExportHTML
```

**Security Monitoring:**
```powershell
.\monitoring\Monitor-ServerHealth.ps1 -SecurityAudit
```

## Supported Frameworks

| Framework | Coverage | Use Case |
|-----------|----------|----------|
| **CIS** | Comprehensive | General best practices |
| **NIST** | Risk management | Federal compliance |
| **PCI-DSS** | Payment security | Payment processing |
| **HIPAA** | Healthcare | PHI protection |
| **SOC2** | Service controls | SaaS compliance |
| **ISO27001** | ISMS | International standard |

## Related Domains

- [Endpoints](../endpoints/) - Device compliance
- [Infrastructure](../infrastructure/) - Server security
- [Collaboration](../collaboration/) - Microsoft 365 security

---

**[← Back to Scripts](../)**
