# System Monitoring Scripts

Comprehensive system health checks and performance monitoring tools for Windows devices.

## Overview

This category contains scripts for monitoring system health, performance metrics, and overall device status. These scripts help identify potential issues before they become critical and provide detailed diagnostic information.

## Available Scripts

### Get-SystemHealthCheck.ps1

Performs a comprehensive multi-point health check on Windows systems.

**Features:**
- CPU, memory, and disk usage monitoring with configurable thresholds
- Critical service status verification
- Windows Update status check
- Event log error analysis (last 24 hours)
- System uptime tracking with reboot recommendations
- Overall health scoring (0-100)
- Generates detailed HTML and CSV reports

**Usage:**
```powershell
# Basic health check (console output only)
.\Get-SystemHealthCheck.ps1

# Generate HTML report
.\Get-SystemHealthCheck.ps1 -OutputFormat HTML -OutputPath "C:\Reports"

# Custom resource thresholds
.\Get-SystemHealthCheck.ps1 -DiskThresholdPercent 85 -MemoryThresholdPercent 85

# Check specific critical services
.\Get-SystemHealthCheck.ps1 -CheckServices @('wuauserv', 'BITS', 'Winmgmt')

# Generate both HTML and CSV reports
.\Get-SystemHealthCheck.ps1 -OutputFormat All -OutputPath "C:\Reports"
```

**Parameters:**
- `OutputFormat`: None, HTML, CSV, or All (default: None)
- `OutputPath`: Directory for report files (default: current directory)
- `CheckServices`: Array of services to monitor (default: common Windows services)
- `DiskThresholdPercent`: Warning threshold for disk usage (default: 80)
- `MemoryThresholdPercent`: Warning threshold for memory usage (default: 90)

**Health Scoring:**
- **90-100**: Healthy - System is running optimally
- **70-89**: Warning - Some issues detected, attention recommended
- **Below 70**: Critical - Immediate attention required

**Example Output:**
```
=== System Health Check ===
Overall Health: Healthy (Score: 95/100)

CPU: Intel Core i7-9700K - Load: 23.5%
Memory: 12.5 GB / 32.0 GB (39%)
Disk C:: 245.3 GB / 500.0 GB (49%)
Disk D:: 150.2 GB / 1000.0 GB (15%)
Uptime: 5.2 days (Last boot: 2025-12-19 08:15)
Pending Windows Updates: 3
System errors (24h): 5

No critical issues detected.
```

**Common Use Cases:**
- Daily health monitoring via scheduled task
- Pre-maintenance system verification
- Troubleshooting performance complaints
- Regular audit compliance checks
- Capacity planning data collection

## Integration with Intune

These monitoring scripts can be deployed as Intune Proactive Remediations for automated health checking across your fleet:

1. **Detection Script**: Use Get-SystemHealthCheck.ps1 with exit code based on health score
2. **Remediation Script**: Create custom remediation based on detected issues
3. **Schedule**: Run daily or weekly depending on requirements
4. **Reporting**: Collect HTML/CSV output to central location for analysis

## Best Practices

1. **Establish Baselines**: Run scripts regularly to establish normal operating parameters
2. **Customize Thresholds**: Adjust disk/memory thresholds based on your environment
3. **Automate Collection**: Schedule regular execution and centralize report storage
4. **Review Trends**: Monitor health scores over time to identify degradation
5. **Combine with Alerts**: Set up alerts for health scores below acceptable thresholds

## Troubleshooting

**"Access Denied" errors:**
- Run PowerShell as Administrator
- Some metrics require elevated privileges

**Performance counter errors:**
- Verify Performance Counter service is running
- Rebuild performance counters if corrupted: `lodctr /r`

**Event log access issues:**
- Check Event Log service status
- Verify user has rights to read System event log

## Requirements

- **PowerShell**: 5.1 or later
- **Privileges**: Administrator recommended (some checks work with standard user)
- **OS**: Windows 10/11, Windows Server 2016+
- **Dependencies**: None (uses built-in cmdlets)

## Related Scripts

- **[Security & Compliance](../security-compliance/)** - Security-specific health checks
- **[Network Management](../network-management/)** - Network connectivity diagnostics
- **[Server Management](../server/)** - Server-specific health tools
- **[Proactive Remediations](../device-management/proactive-remediations/)** - Automated fixes

### Get-BatteryHealth.ps1

Monitors laptop and tablet battery health with detailed analysis and reporting.

**Features:**
- Battery health percentage calculation
- Design vs. full charge capacity comparison
- Wear level detection
- Battery age calculation (from manufacture date)
- Current charge and runtime estimation
- Optional Windows battery report generation
- Configurable health alert thresholds
- CSV export for trend tracking

**Usage:**
```powershell
# Basic battery health check
.\Get-BatteryHealth.ps1 -OutputPath "C:\Reports"

# Generate detailed Windows report with 70% alert threshold
.\Get-BatteryHealth.ps1 -GenerateDetailedReport -AlertThreshold 70

# Export to CSV for historical tracking
.\Get-BatteryHealth.ps1 -ExportToCSV -OutputPath "C:\BatteryTracking"
```

**Battery Health Indicators:**
- **80-100%**: Excellent - Battery in good condition, no action needed
- **60-79%**: Fair - Monitor performance, consider replacement in 6-12 months
- **Below 60%**: Poor - Battery replacement recommended soon

**Use Cases:**
- Laptop fleet asset management
- Battery warranty claims
- Replacement planning
- User satisfaction monitoring

---

### Get-PerformanceTrends.ps1

Monitors system performance trends over time to identify patterns and anomalies.

**Features:**
- Real-time performance data collection (CPU, Memory, Disk, Network)
- Configurable monitoring duration and sample intervals
- Alert threshold monitoring with real-time notifications
- Top process tracking (optional)
- Statistical analysis (average, min, max)
- Performance spike detection
- Comprehensive HTML and CSV reporting

**Usage:**
```powershell
# Monitor for 30 minutes with default settings
.\Get-PerformanceTrends.ps1 -DurationMinutes 30 -OutputPath "C:\Reports"

# Extended 2-hour monitoring with process tracking
.\Get-PerformanceTrends.ps1 -DurationMinutes 120 -MonitorProcesses -SampleInterval 60

# Custom alert thresholds
$thresholds = @{ CPU = 80; Memory = 90; Disk = 95 }
.\Get-PerformanceTrends.ps1 -DurationMinutes 60 -AlertThresholds $thresholds
```

**Monitoring Metrics:**
- CPU utilization percentage
- Memory usage (percentage and GB)
- Disk activity percentage
- Network throughput (MB/s)
- Top 5 resource-consuming processes (when enabled)

**Common Scenarios:**
- Performance troubleshooting during slow periods
- Establishing performance baselines
- Capacity planning data collection
- Pre/post-deployment performance comparison
- Resource leak detection

---

## Future Enhancements

Planned additions to this category:
- Temperature monitoring via WMI
- Application-specific performance tracking
- Integration with Azure Monitor
- Predictive failure detection

## Support

For issues or feature requests related to monitoring scripts, please check:
1. Script help: `Get-Help .\ScriptName.ps1 -Detailed`
2. Main documentation: [Full Documentation](../../docs/README.md)
3. Troubleshooting guide: [Troubleshooting](../../docs/TROUBLESHOOTING.md)
