# Network Management Scripts

Comprehensive network diagnostics and troubleshooting tools for Windows devices.

## Overview

This category contains scripts for diagnosing network connectivity issues, testing network performance, and troubleshooting common network problems. These tools help identify and resolve network-related issues quickly and efficiently.

## Available Scripts

### Test-NetworkConnectivity.ps1

Performs comprehensive network diagnostics and connectivity testing.

**Features:**
- Network adapter status and configuration
- Gateway reachability testing
- DNS resolution verification
- Internet connectivity tests to multiple endpoints
- Network performance metrics
- Wi-Fi signal strength (for wireless adapters)
- Generates detailed HTML and CSV diagnostic reports

**Usage:**
```powershell
# Basic network diagnostic
.\Test-NetworkConnectivity.ps1

# Test specific endpoints
.\Test-NetworkConnectivity.ps1 -TestEndpoints @("google.com", "microsoft.com", "office.com")

# Generate HTML diagnostic report
.\Test-NetworkConnectivity.ps1 -OutputFormat HTML -OutputPath "C:\Reports"

# Test with custom DNS servers
.\Test-NetworkConnectivity.ps1 -DNSServers @("8.8.8.8", "1.1.1.1", "208.67.222.222")

# Generate both HTML and CSV reports
.\Test-NetworkConnectivity.ps1 -OutputFormat All -OutputPath "C:\NetworkReports"
```

**Parameters:**
- `OutputFormat`: None, HTML, CSV, or All (default: None)
- `OutputPath`: Directory for report files (default: current directory)
- `TestEndpoints`: Array of URLs/IPs to test connectivity (default: common Microsoft and public services)
- `DNSServers`: Array of DNS servers to test (default: Google DNS and Cloudflare DNS)

**Health Status Levels:**
- **Excellent**: No issues, all endpoints reachable
- **Good**: Minor issues, 80%+ endpoints reachable
- **Degraded**: Some connectivity problems, issue count ≤ 2
- **Poor**: Significant connectivity issues, issue count > 2

**Example Output:**
```
=== Network Connectivity Diagnostic ===

Adapter: Ethernet - Up - IP: 192.168.1.100
Gateway (192.168.1.1): Reachable (Avg: 1.2ms)

DNS Resolution: Working
  Public DNS (8.8.8.8): Working
  Public DNS (1.1.1.1): Working

Testing internet connectivity...
  google.com : Reachable (15ms)
  microsoft.com : Reachable (22ms)
  office.com : Reachable (18ms)
  login.microsoftonline.com : Reachable (25ms)

=== Network Diagnostic Summary ===
Overall Status: Excellent
Endpoints Reachable: 6 / 6

No network issues detected.
```

**Common Use Cases:**
- Troubleshooting "no internet" complaints
- Verifying network configuration after changes
- Testing connectivity to specific services
- Diagnosing slow network performance
- Documenting network status for support tickets
- Automated network health monitoring

## Network Troubleshooting Workflow

When diagnosing network issues, follow this systematic approach:

### 1. Run Basic Diagnostic
```powershell
.\Test-NetworkConnectivity.ps1
```

### 2. Review Adapter Status
- Check if adapters are "Up"
- Verify IP address is assigned (not 169.254.x.x)
- Confirm gateway is configured

### 3. Test Layer by Layer
- **Gateway**: Can you reach your default gateway?
- **DNS**: Is DNS resolution working?
- **Internet**: Can you reach external sites?

### 4. Generate Report if Needed
```powershell
.\Test-NetworkConnectivity.ps1 -OutputFormat HTML -OutputPath "C:\Temp"
# Attach report to support ticket
```

## Common Network Issues

### Issue: No Internet Connectivity

**Symptoms:**
- Cannot reach any external sites
- Gateway may or may not be reachable

**Diagnostic Steps:**
```powershell
# Run full diagnostic
.\Test-NetworkConnectivity.ps1

# Check for:
# 1. Valid IP address (not 169.254.x.x)
# 2. Gateway reachability
# 3. DNS resolution
```

**Common Causes:**
- DHCP issues (no IP assigned)
- Gateway unreachable (network cable, switch issue)
- DNS misconfiguration
- Firewall blocking outbound traffic

### Issue: Intermittent Connectivity

**Symptoms:**
- Some sites work, others don't
- Connectivity works sometimes

**Diagnostic Steps:**
```powershell
# Test specific problematic endpoints
.\Test-NetworkConnectivity.ps1 -TestEndpoints @("problematic-site.com")

# Run multiple times to check consistency
```

**Common Causes:**
- DNS issues (some queries failing)
- Firewall rules blocking specific traffic
- Routing issues
- ISP problems

### Issue: Slow Network Performance

**Symptoms:**
- High latency to gateway or internet
- Slow file transfers

**Diagnostic Steps:**
```powershell
# Check gateway latency and endpoint response times
.\Test-NetworkConnectivity.ps1

# Look for:
# - High gateway latency (>10ms on local network)
# - Packet loss
# - Poor Wi-Fi signal strength
```

**Common Causes:**
- Network congestion
- Poor Wi-Fi signal
- Faulty network hardware
- Bandwidth saturation

## Integration with Intune

Deploy as Intune Proactive Remediation for fleet-wide network monitoring:

**Detection Script**:
```powershell
# Exit 1 if network issues detected, 0 if healthy
$result = .\Test-NetworkConnectivity.ps1
if ($result.OverallStatus -in @('Poor', 'Degraded')) {
    exit 1  # Trigger remediation
} else {
    exit 0  # No action needed
}
```

**Remediation Script**:
```powershell
# Reset network adapters
# Flush DNS
# Release/renew DHCP
# Report results
```

## Advanced Diagnostics

For deeper network troubleshooting, combine with these native Windows tools:

```powershell
# Network adapter details
Get-NetAdapter | Format-List *

# IP configuration
Get-NetIPConfiguration

# Routing table
Get-NetRoute

# DNS cache
Get-DnsClientCache

# Network statistics
netstat -e

# Detailed adapter info
ipconfig /all
```

## Best Practices

1. **Baseline Normal Performance**: Establish what "good" looks like
2. **Document Network Topology**: Know your network layout
3. **Test Systematically**: Work from inside out (local → gateway → internet)
4. **Collect Evidence**: Generate reports for support tickets
5. **Automate Monitoring**: Schedule regular network health checks

## Requirements

- **PowerShell**: 5.1 or later
- **Privileges**: Standard user (Administrator for some metrics)
- **OS**: Windows 10/11, Windows Server 2016+
- **Dependencies**: None (uses built-in cmdlets)
- **Network**: Active network connection (for testing)

## Related Scripts

- **[Monitoring](../monitoring/)** - System health checks
- **[Server Management](../server/)** - Server network configuration
- **[Proactive Remediations](../device-management/proactive-remediations/)** - Network adapter fixes

### Test-NetworkDiagnostics.ps1

Performs comprehensive network diagnostics including adapter analysis, DNS testing, connectivity testing, traceroute, and port scanning.

**Features:**
- Network adapter configuration and status
- DNS resolution testing (multiple DNS servers)
- Internet connectivity tests with latency measurement
- Packet loss detection
- Traceroute to specified destinations
- Port scanning for common services
- Network statistics and error counts
- Detailed HTML reporting

**Usage:**
```powershell
# Basic network diagnostics
.\Test-NetworkDiagnostics.ps1 -OutputPath "C:\Reports"

# Comprehensive diagnostics with all tests
.\Test-NetworkDiagnostics.ps1 -TestInternetConnectivity -TraceRoute -TestDNS -ScanPorts

# Test DNS functionality
.\Test-NetworkDiagnostics.ps1 -TestDNS -OutputPath "C:\Reports"
```

**Common Scenarios:**
- Deep network troubleshooting
- Network infrastructure validation
- Performance baseline establishment
- Security audit (port scanning)
- Documentation for support tickets

---

### Reset-NetworkStack.ps1

Resets Windows network stack to resolve persistent connectivity issues.

**Features:**
- Winsock catalog reset
- TCP/IP stack reset (IPv4 and IPv6)
- DNS cache flush
- Proxy settings reset
- Windows Firewall reset (optional)
- Network adapter reset (optional)
- System restore point creation (optional)
- DHCP lease renewal

**Usage:**
```powershell
# Basic network stack reset
.\Reset-NetworkStack.ps1

# Comprehensive reset with restore point
.\Reset-NetworkStack.ps1 -FlushDNS -ResetProxy -CreateRestorePoint

# Full reset including firewall and adapters
.\Reset-NetworkStack.ps1 -ResetFirewall -ResetAdapters -FlushDNS -ResetProxy -CreateRestorePoint

# Skip confirmation prompts
.\Reset-NetworkStack.ps1 -FlushDNS -ResetProxy -Force
```

**WARNING:** This script makes significant system changes. A system restart may be required after completion.

**When to Use:**
- Persistent "no internet" issues after other troubleshooting
- After malware removal
- Corrupt network stack symptoms
- DNS resolution failures
- Network adapter errors

---

## Future Enhancements

Planned additions to this category:
- VPN connectivity testing
- Bandwidth throughput testing
- Network drive connectivity testing
- Wireless network optimization

## Support

For issues or feature requests related to network management scripts:
1. Script help: `Get-Help .\ScriptName.ps1 -Detailed`
2. Main documentation: [Wiki](https://github.com/Carme99/bug-free-umbrella/wiki)
3. Troubleshooting guide: [Troubleshooting](https://github.com/Carme99/bug-free-umbrella/wiki/Troubleshooting)
