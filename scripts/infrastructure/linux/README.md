# Linux Server Administration Scripts

A collection of bash scripts for managing and monitoring Ubuntu Server and Rocky Linux systems.

## Overview

This directory contains production-ready bash scripts designed for Linux server administration. All scripts are compatible with both **Ubuntu Server** (20.04, 22.04, 24.04) and **Rocky Linux** (8.x, 9.x), with automatic distribution detection where needed.

## Directory Structure

```
linux-server/
├── system-health/       # System health monitoring and reporting
├── security/            # Security auditing and hardening
├── monitoring/          # Resource monitoring and alerting
├── user-management/     # User account auditing and management
├── backup-recovery/     # Backup verification and validation
└── network/             # Network diagnostics and connectivity
```

## Quick Start

### Prerequisites

- **Bash 4.0+** (standard on modern Linux distributions)
- **Root or sudo privileges** (most scripts require elevated permissions)
- **Standard Linux utilities** (grep, awk, sed, systemctl, etc.)

### Making Scripts Executable

```bash
# Make all scripts executable
chmod +x scripts/linux-server/**/*.sh

# Or individual script
chmod +x scripts/linux-server/system-health/system-health-check.sh
```

### Running Scripts

```bash
# With sudo
sudo ./system-health-check.sh

# Or as root
./system-health-check.sh
```

## Available Scripts

### System Health (`system-health/`)

| Script | Description | Usage |
|--------|-------------|-------|
| `system-health-check.sh` | Comprehensive system health check with CPU, memory, disk, and service monitoring | `sudo ./system-health-check.sh` |

**Features:**
- Distribution detection (Ubuntu/Rocky Linux)
- CPU, memory, and disk usage analysis
- Critical service status verification
- Load average and uptime monitoring
- HTML/text report generation

---

### Security (`security/`)

| Script | Description | Usage |
|--------|-------------|-------|
| `security-audit.sh` | Security baseline audit including firewall, SSH, updates, and user permissions | `sudo ./security-audit.sh` |

**Features:**
- Firewall status (UFW/firewalld)
- SSH configuration review
- Security updates check
- User privilege audit (sudo/wheel)
- Password policy verification
- SELinux/AppArmor status

---

### Monitoring (`monitoring/`)

| Script | Description | Usage |
|--------|-------------|-------|
| `disk-monitor.sh` | Disk space monitoring with threshold alerts | `sudo ./disk-monitor.sh [threshold]` |
| `service-monitor.sh` | Critical service monitoring and auto-restart capability | `sudo ./service-monitor.sh` |

**Features:**
- Configurable disk space thresholds
- Automatic service health checks
- Failed service detection
- Optional auto-restart
- Email alerting support (if configured)

---

### User Management (`user-management/`)

| Script | Description | Usage |
|--------|-------------|-------|
| `user-audit.sh` | Comprehensive user account audit including inactive users and privilege escalation | `sudo ./user-audit.sh` |

**Features:**
- Active/inactive user detection
- Last login tracking
- Sudo/wheel group membership
- UID 0 account detection
- Password expiry checking
- Home directory analysis

---

### Backup & Recovery (`backup-recovery/`)

| Script | Description | Usage |
|--------|-------------|-------|
| `backup-verify.sh` | Backup directory verification and integrity checks | `sudo ./backup-verify.sh /path/to/backups` |

**Features:**
- Backup file age verification
- Size validation
- Integrity checking
- Oldest/newest backup detection
- Space usage analysis

---

### Network (`network/`)

| Script | Description | Usage |
|--------|-------------|-------|
| `network-diagnostics.sh` | Network connectivity and configuration diagnostics | `sudo ./network-diagnostics.sh` |

**Features:**
- Network interface status
- DNS resolution testing
- Gateway connectivity
- Internet connectivity verification
- Routing table analysis
- Port listening detection

---

## Common Use Cases

### Daily Health Check
```bash
cd scripts/linux-server/system-health
sudo ./system-health-check.sh
```

### Weekly Security Audit
```bash
cd scripts/linux-server/security
sudo ./security-audit.sh > /var/log/security-audit-$(date +%Y%m%d).log
```

### Monitor Critical Services
```bash
cd scripts/linux-server/monitoring
sudo ./service-monitor.sh
```

### Monthly User Audit
```bash
cd scripts/linux-server/user-management
sudo ./user-audit.sh > /var/log/user-audit-$(date +%Y%m%d).log
```

### Disk Space Monitoring (Alert at 80%)
```bash
cd scripts/linux-server/monitoring
sudo ./disk-monitor.sh 80
```

## Automation with Cron

### Daily Health Check at 6 AM
```bash
0 6 * * * /path/to/scripts/linux-server/system-health/system-health-check.sh > /var/log/health-check.log 2>&1
```

### Weekly Security Audit (Sundays at 2 AM)
```bash
0 2 * * 0 /path/to/scripts/linux-server/security/security-audit.sh > /var/log/security-audit-$(date +\%Y\%m\%d).log 2>&1
```

### Hourly Service Monitoring
```bash
0 * * * * /path/to/scripts/linux-server/monitoring/service-monitor.sh >> /var/log/service-monitor.log 2>&1
```

### Daily Disk Space Check
```bash
0 7 * * * /path/to/scripts/linux-server/monitoring/disk-monitor.sh 85 >> /var/log/disk-monitor.log 2>&1
```

## Script Features

All scripts include:
- ✅ **Distribution detection** - Automatic Ubuntu/Rocky Linux detection
- ✅ **Error handling** - Comprehensive error checking
- ✅ **Logging support** - Standard output suitable for log files
- ✅ **Exit codes** - Proper exit codes (0=success, 1=warning, 2=error)
- ✅ **Color output** - Terminal-friendly color-coded output
- ✅ **Root checking** - Automatic privilege verification
- ✅ **Help documentation** - Built-in usage instructions

## Distribution Compatibility

| Feature | Ubuntu Server | Rocky Linux | Notes |
|---------|---------------|-------------|-------|
| Package Manager | `apt` | `dnf/yum` | Auto-detected |
| Firewall | `ufw` | `firewalld` | Auto-detected |
| SELinux | N/A (AppArmor) | Supported | Conditional checks |
| Service Manager | `systemd` | `systemd` | Universal |
| Init System | `systemd` | `systemd` | Universal |

## Requirements by Distribution

### Ubuntu Server
```bash
# Update package list
sudo apt update

# Install recommended utilities (usually pre-installed)
sudo apt install -y curl wget net-tools sysstat
```

### Rocky Linux
```bash
# Update system
sudo dnf update

# Install recommended utilities
sudo dnf install -y curl wget net-tools sysstat
```

## Exit Codes

Scripts use standardized exit codes:

| Code | Meaning | Example |
|------|---------|---------|
| `0` | Success / All checks passed | System healthy, no issues |
| `1` | Warning / Minor issues | Disk usage at 85%, some updates available |
| `2` | Error / Critical issues | Critical service down, disk full |

## Security Considerations

- **Always review scripts** before running with elevated privileges
- **Test in non-production** environments first
- **Audit logs regularly** - Scripts output to stdout for easy logging
- **Restrict permissions** - Keep scripts readable only by authorized users
- **Use sudo** instead of running as root user when possible

## Logging Best Practices

### Centralized Logging
```bash
# Create log directory
sudo mkdir -p /var/log/server-scripts

# Run script with logging
sudo ./system-health-check.sh | tee -a /var/log/server-scripts/health-$(date +%Y%m%d).log
```

### Log Rotation
Create `/etc/logrotate.d/server-scripts`:
```
/var/log/server-scripts/*.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
}
```

## Troubleshooting

### Script Permission Denied
```bash
# Make executable
chmod +x script-name.sh
```

### Command Not Found
```bash
# Check if required utilities are installed
which systemctl curl awk sed grep
```

### SELinux Blocking Execution (Rocky Linux)
```bash
# Temporarily set to permissive (for testing)
sudo setenforce 0

# Or add proper SELinux context
sudo chcon -t bin_t script-name.sh
```

## Contributing

When adding new scripts:
1. Include proper shebang: `#!/bin/bash`
2. Add distribution detection if needed
3. Include error handling and exit codes
4. Add color output for terminal use
5. Document usage and examples
6. Test on both Ubuntu and Rocky Linux

## Support

For issues or questions:
- Check script help: `./script-name.sh --help`
- Review built-in documentation in script comments
- Test with verbose output: `bash -x ./script-name.sh`

## License

Licensed under the Apache License 2.0. See repository LICENSE for details.
