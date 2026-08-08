# Virtualization Management Scripts

Enterprise-grade PowerShell scripts for Hyper-V management, monitoring, and troubleshooting.

## 📋 Overview

This category provides comprehensive Hyper-V infrastructure management tools for monitoring host health, virtual machine status, and identifying configuration issues.

## 🔧 Scripts

### Get-HyperVHealth.ps1
Performs comprehensive health check of Hyper-V host and virtual machines.

**Features:**
- Hyper-V service status monitoring
- Host resource utilization (CPU, memory)
- Virtual machine status and health
- Integration Services verification
- Virtual switch configuration
- Snapshot/checkpoint detection
- Hyper-V Replica health monitoring
- Memory pressure analysis
- Virtual processor allocation

**Usage:**
```powershell
# Basic host health check
.\Get-HyperVHealth.ps1

# Comprehensive check including VMs
.\Get-HyperVHealth.ps1 -IncludeVMs -CheckSnapshots -ExportHTML

# Check replication status
.\Get-HyperVHealth.ps1 -CheckReplication
```

**Parameters:**
- `-IncludeVMs`: Include detailed VM health checks
- `-CheckReplication`: Check Hyper-V Replica status
- `-CheckSnapshots`: Identify VMs with snapshots/checkpoints
- `-ExportHTML`: Export to HTML report
- `-ExportCSV`: Export to CSV file

**Requirements:**
- Hyper-V PowerShell module
- Administrator privileges
- Compatible with Windows Server 2016, 2019, 2022

## 📊 Common Use Cases

### Daily Health Monitoring
```powershell
# Quick host check
.\Get-HyperVHealth.ps1

# Full infrastructure check
.\Get-HyperVHealth.ps1 -IncludeVMs -CheckSnapshots -CheckReplication -ExportHTML
```

### VM Troubleshooting
```powershell
# Check VM integration services
.\Get-HyperVHealth.ps1 -IncludeVMs

# Identify memory pressure issues
.\Get-HyperVHealth.ps1 -IncludeVMs -ExportHTML
```

### Snapshot Management
```powershell
# Find VMs with old snapshots
.\Get-HyperVHealth.ps1 -CheckSnapshots -ExportCSV
```

## 🎯 Health Check Metrics

The health check evaluates:

1. **Host Status**
   - VMMS service health
   - Physical CPU count
   - Total memory capacity
   - Memory utilization

2. **Virtual Machines**
   - VM state (Running, Stopped, Saved, Paused)
   - Integration Services status
   - Memory pressure
   - Virtual processor count

3. **Integration Services**
   - Guest services status
   - Heartbeat monitoring
   - Data exchange health
   - Time synchronization

4. **Virtual Switches**
   - Switch configuration
   - Network adapter binding
   - Management OS settings

5. **Snapshots/Checkpoints**
   - VMs with snapshots
   - Snapshot age
   - Storage impact

6. **Replication (Optional)**
   - Replication health
   - Replication state
   - Last replication time

## 📈 Output Examples

### Healthy Host
```
=== Hyper-V Health Check ===
Host: HV-HOST-01

[+] Hyper-V Virtual Machine Management service is running

Host Resources:
    Physical Processors: 32
    Memory Total: 256.00 GB
    Memory Used: 65%

[+] Total VMs: 12
    Running: 10
    Stopped: 2

[+] No VMs with snapshots

Health Score: 95%
```

### Issues Detected
```
[Warning] VM-WEB-01: Integration Services need attention
[Warning] VM-SQL-02: Memory pressure 98%
[Warning] VM-APP-03: 3 snapshot(s), oldest is 45 days old

Health Score: 72%
Issues: 0
Warnings: 3
```

## 🔍 Troubleshooting

### Hyper-V Module Not Found
```powershell
# Install Hyper-V management tools
Install-WindowsFeature -Name Hyper-V-PowerShell

# Verify module
Get-Module -Name Hyper-V -ListAvailable
```

### Permission Issues
Ensure you're running as Administrator:
```powershell
# Check if running as admin
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

### VMMS Service Issues
```powershell
# Check service status
Get-Service -Name vmms

# Restart if needed
Restart-Service -Name vmms -Force
```

## 📝 Best Practices

1. **Regular Monitoring**
   - Run health checks daily on production Hyper-V hosts
   - Monitor memory pressure on all running VMs
   - Track snapshot age and clean up old snapshots

2. **Integration Services**
   - Keep Integration Services up to date
   - Address IS warnings immediately
   - Verify heartbeat on critical VMs

3. **Snapshot Management**
   - Remove snapshots older than 7 days
   - Use snapshots for testing only, not backups
   - Monitor storage impact of snapshots

4. **Resource Allocation**
   - Avoid memory overcommitment
   - Monitor CPU contention
   - Balance VM load across hosts

## 🚨 Common Issues

### Memory Pressure
**Symptom**: VMs showing high memory pressure
**Solution**: Increase VM memory allocation or reduce host load

### Outdated Integration Services
**Symptom**: IS status shows "Update Required"
**Solution**: Install latest Integration Services in guest OS

### Old Snapshots
**Symptom**: VMs with snapshots older than 7 days
**Solution**: Review and delete unnecessary snapshots

### Replication Failures
**Symptom**: Replica health shows Error
**Solution**: Check network connectivity, verify replica settings

## 🚀 Future Enhancements

Planned additions:
- Live migration health checks
- Storage performance analysis
- VM resource optimization recommendations
- Cluster health monitoring
- Backup integration verification

## 📚 Additional Resources

- [Hyper-V PowerShell Documentation](https://docs.microsoft.com/powershell/module/hyper-v/)
- [Hyper-V Best Practices](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/best-practices-analyzer/best-practices-analyzer-for-hyper-v)
- [Hyper-V Troubleshooting](https://learn.microsoft.com/en-us/troubleshoot/windows-server/virtualization/troubleshoot-hyper-v-virtual-machine-performance)

---

**Version**: 1.0
**Last Updated**: 2025
