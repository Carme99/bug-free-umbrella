# Web Services Management Scripts

Comprehensive PowerShell scripts for IIS (Internet Information Services) management, monitoring, and optimization.

## 📋 Overview

This collection provides enterprise-grade tools for managing Windows web servers, focusing on:

- **Health Monitoring**: Real-time IIS health checks and performance analysis
- **Log Analysis**: Advanced IIS log parsing with security threat detection
- **Configuration Optimization**: Performance tuning and security hardening
- **Backup & Recovery**: Complete IIS configuration backup and restoration

## 🚀 Scripts

### IIS Management (4 scripts)

#### 1. Get-IISHealthCheck.ps1

Comprehensive IIS web server health assessment.

**Features**:
- Application pool status and performance monitoring
- Website status and binding validation
- SSL certificate expiration checking
- Worker process health analysis
- Request queue monitoring
- Failed request tracing
- Performance counter collection
- HTML and CSV reporting

**Usage**:
```powershell
# Basic health check
.\Get-IISHealthCheck.ps1

# Full check with SSL validation and HTML report
.\Get-IISHealthCheck.ps1 -CheckSSLCertificates -ExportHTML

# Comprehensive check with performance data and log analysis
.\Get-IISHealthCheck.ps1 -IncludePerformanceCounters -AnalyzeLogFiles -DaysToAnalyze 14 -ExportHTML
```

**Parameters**:
- `-IncludePerformanceCounters` - Collect IIS performance counter data
- `-CheckSSLCertificates` - Validate SSL certificates for all HTTPS bindings
- `-AnalyzeLogFiles` - Analyze IIS log files for errors and patterns
- `-DaysToAnalyze` - Number of days of logs to analyze (default: 7)
- `-ExportHTML` - Generate detailed HTML report
- `-ExportCSV` - Export data to CSV format

**Requirements**:
- IIS 8.0 or later
- WebAdministration PowerShell module
- Administrator privileges

**Output**:
- Overall health score (0-100)
- Application pool analysis
- Website status report
- SSL certificate expiration warnings
- Performance metrics
- Recommendations for improvements

---

#### 2. Get-IISLogAnalyzer.ps1

Advanced IIS log file analysis with security threat detection.

**Features**:
- Top requested URLs and resources identification
- HTTP status code distribution analysis
- Client IP analysis and patterns
- User agent analysis (browsers, bots, crawlers)
- Performance metrics (response times, slow requests)
- Error pattern detection (4xx, 5xx status codes)
- Security threat analysis (SQL injection, XSS, path traversal)
- Bandwidth usage by resource

**Usage**:
```powershell
# Analyze last 7 days of IIS logs
.\Get-IISLogAnalyzer.ps1

# 30-day analysis with security scanning
.\Get-IISLogAnalyzer.ps1 -DaysToAnalyze 30 -IncludeSecurityAnalysis -ExportHTML

# Custom log path and top entries count
.\Get-IISLogAnalyzer.ps1 -LogPath "D:\IISLogs" -Top 50 -ExportHTML
```

**Parameters**:
- `-LogPath` - Path to IIS log files (default: C:\inetpub\logs\LogFiles)
- `-DaysToAnalyze` - Number of days to analyze (default: 7)
- `-Top` - Number of top entries to show (default: 20)
- `-IncludeSecurityAnalysis` - Perform security threat analysis
- `-ExportHTML` - Generate HTML report
- `-ExportCSV` - Export analysis to CSV

**Security Analysis**:
- SQL injection attempt detection
- Cross-site scripting (XSS) detection
- Path traversal attack detection
- Command injection detection
- Unique attacker IP tracking

**Log Format Support**:
- W3C Extended Log Format
- IIS Log Format
- NCSA Common Log Format

---

#### 3. Optimize-IISConfiguration.ps1

Performance tuning and security hardening for IIS.

**Features**:
- **Performance Optimizations**:
  - Static and dynamic compression enablement
  - Application pool recycling optimization
  - Request queue tuning
  - Output caching configuration
  - HTTP/2 support enablement

- **Security Hardening**:
  - Server header removal
  - Security headers configuration (HSTS, X-Frame-Options, CSP)
  - Directory browsing disablement
  - Request filtering
  - SSL/TLS configuration

**Usage**:
```powershell
# Preview performance optimizations
.\Optimize-IISConfiguration.ps1 -ApplyPerformanceOptimizations -WhatIf

# Apply both performance and security optimizations
.\Optimize-IISConfiguration.ps1 -ApplyPerformanceOptimizations -ApplySecurityHardening

# Enable HTTP/2 support
.\Optimize-IISConfiguration.ps1 -EnableHTTP2
```

**Parameters**:
- `-ApplyPerformanceOptimizations` - Apply performance-related settings
- `-ApplySecurityHardening` - Apply security hardening configurations
- `-EnableHTTP2` - Enable HTTP/2 support (requires restart)
- `-WhatIf` - Preview changes without applying them

**Performance Improvements**:
- Typical performance gain: 20-40% for static content
- Reduced CPU usage through compression
- Faster response times with output caching
- Better handling of concurrent requests

**Security Enhancements**:
- Protection against clickjacking (X-Frame-Options)
- MIME type sniffing prevention (X-Content-Type-Options)
- XSS attack mitigation (X-XSS-Protection)
- HTTPS enforcement (HSTS)
- Content Security Policy headers

---

#### 4. Backup-IISConfiguration.ps1

Complete IIS configuration backup and restoration.

**Features**:
- ApplicationHost.config backup
- Web.config files for all sites
- Application pool configurations
- SSL certificate information
- Site bindings and settings
- Virtual directories
- Custom modules and handlers
- Optional website content backup
- Restoration from backups

**Usage**:
```powershell
# Basic configuration backup
.\Backup-IISConfiguration.ps1

# Full backup including SSL certificates
.\Backup-IISConfiguration.ps1 -IncludeCertificates -BackupPath "D:\IISBackups"

# Backup with custom name
.\Backup-IISConfiguration.ps1 -BackupName "Pre-Migration-Backup" -IncludeCertificates

# Restore from backup
.\Backup-IISConfiguration.ps1 -Restore -RestoreFrom "C:\IISBackups\IIS_Backup_20241226_120000"
```

**Parameters**:
- `-BackupPath` - Directory for backup files (default: C:\IISBackups)
- `-BackupName` - Custom backup name (default: timestamped)
- `-IncludeCertificates` - Include SSL certificate details
- `-IncludeContentFiles` - Include website content (warning: large backups)
- `-Restore` - Restore mode
- `-RestoreFrom` - Path to backup to restore

**Backup Contents**:
- ApplicationHost.config (master configuration)
- Web.config files (per-site configurations)
- Application pool settings (CSV export)
- Site configurations (CSV export)
- SSL certificate metadata
- Backup manifest with metadata

**Typical Backup Size**:
- Configuration only: 1-5 MB
- With certificates: 5-10 MB
- With content files: Varies (100+ MB to several GB)

**Recovery Time**:
- Configuration restore: 2-5 minutes
- Full site restoration: 10-30 minutes (depending on content size)

---

## 📊 Common Workflows

### Weekly Health Check
```powershell
# Run comprehensive health check every week
.\Get-IISHealthCheck.ps1 -IncludePerformanceCounters -CheckSSLCertificates -AnalyzeLogFiles -ExportHTML
```

### Monthly Log Analysis
```powershell
# Analyze month's worth of logs with security scanning
.\Get-IISLogAnalyzer.ps1 -DaysToAnalyze 30 -IncludeSecurityAnalysis -ExportHTML
```

### Pre-Production Optimization
```powershell
# Preview optimizations
.\Optimize-IISConfiguration.ps1 -ApplyPerformanceOptimizations -ApplySecurityHardening -WhatIf

# Apply optimizations
.\Optimize-IISConfiguration.ps1 -ApplyPerformanceOptimizations -ApplySecurityHardening
```

### Pre-Migration Backup
```powershell
# Complete backup before major changes
.\Backup-IISConfiguration.ps1 -IncludeCertificates -BackupName "Pre-Migration-$(Get-Date -Format 'yyyyMMdd')"
```

---

## ⚙️ Requirements

| Component | Requirement |
|-----------|-------------|
| **IIS Version** | 8.0, 8.5, 10.0 (Server 2012+, Windows 8+) |
| **PowerShell** | 5.1 minimum (7.x recommended) |
| **Modules** | WebAdministration (included with IIS) |
| **Privileges** | Administrator / Elevated |
| **OS** | Windows Server 2012-2022, Windows 8-11 |

---

## 🔧 Installation & Setup

1. **Verify IIS Installation**:
```powershell
Get-WindowsFeature -Name Web-Server
```

2. **Import WebAdministration Module**:
```powershell
Import-Module WebAdministration
```

3. **Run Scripts as Administrator**:
```powershell
# Right-click PowerShell > Run as Administrator
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
```

---

## 📈 Performance Metrics

**Health Check Performance**:
- Basic health check: 10-30 seconds
- With SSL validation: 30-60 seconds
- With log analysis (7 days): 1-3 minutes
- With log analysis (30 days): 5-10 minutes

**Log Analysis Performance**:
- 1 GB of logs: ~2-3 minutes
- 10 GB of logs: ~15-20 minutes
- Parsing rate: ~300-500 MB/min

---

## 🛡️ Security Considerations

- Backup files contain sensitive configuration data - store securely
- SSL certificate backups do not include private keys
- Review security header configurations for your specific needs
- Test optimizations in non-production first
- Log files may contain sensitive information (IPs, user agents)

---

## 📝 Best Practices

1. **Regular Health Checks**: Run weekly health checks with HTML reports
2. **Log Analysis**: Analyze logs monthly for trends and security threats
3. **Backup Before Changes**: Always backup before applying optimizations
4. **Test in Staging**: Test all optimizations in staging environment first
5. **Monitor After Changes**: Verify improvements after applying optimizations
6. **Review Security Alerts**: Investigate any security threats from log analysis
7. **SSL Certificate Monitoring**: Check certificates monthly (30-90 days before expiry)

---

## 🚨 Troubleshooting

### Issue: Health Check Reports Errors

**Symptoms**: Script reports errors accessing IIS
**Solution**:
```powershell
# Verify IIS services are running
Get-Service W3SVC, WAS

# Restart IIS if needed
iisreset /restart

# Check WebAdministration module
Import-Module WebAdministration -Verbose
```

### Issue: Log Analyzer Running Slow

**Symptoms**: Log analysis takes too long
**Solutions**:
- Reduce `-DaysToAnalyze` parameter
- Increase `-Top` parameter to reduce processing
- Archive old logs to separate location
- Run during off-peak hours

### Issue: Optimization Fails

**Symptoms**: Optimization script errors or doesn't apply changes
**Solutions**:
- Run as Administrator
- Check for Group Policy conflicts
- Verify no manual locks on configuration files
- Review ApplicationHost.config permissions

---

## 📚 Additional Resources

- [IIS Administration Guide](https://docs.microsoft.com/en-us/iis/manage/managing-your-configuration-settings)
- [Security Best Practices for IIS](https://docs.microsoft.com/en-us/iis/manage/configuring-security/security-best-practices-for-iis-8)
- [Performance Tuning IIS](https://docs.microsoft.com/en-us/iis/configuration/performance-tuning-iis)

---

**Compatible**: Windows Server 2012 R2, 2016, 2019, 2022, Windows 10/11
**IIS Versions**: 8.0, 8.5, 10.0
**Total Scripts**: 4
**Total Features**: 40+
