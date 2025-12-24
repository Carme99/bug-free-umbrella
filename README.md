# Bug-Free Umbrella

A comprehensive collection of PowerShell scripts for Windows system administration, Intune management, and automated device maintenance.

## Quick Links

### 📖 Documentation
- **[Full Documentation](docs/README.md)** - Complete guide to all scripts and usage
- **[Script Examples & Expected Outputs](docs/SCRIPT-EXAMPLES.md)** - Detailed examples with sample outputs
- **[End-to-End Workflows](docs/WORKFLOWS.md)** - Step-by-step guides for common scenarios
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)** - Common issues and solutions

### 🎯 Specialized Guides
- **[Intune Sync Guide](docs/INTUNE-SYNC-README.md)** - User group to device group synchronization
- **[Intune Management Scripts](scripts/intune/README.md)** - Comprehensive Intune administration toolkit
- **[Server Management Scripts](scripts/server/README.md)** - Windows Server administration tools
- **[Security & Compliance Scripts](scripts/security-compliance/README.md)** - Security auditing and compliance verification
- **[Proactive Remediations](scripts/device-management/proactive-remediations/README.md)** - Auto-fix common issues
- **[Winget Update Templates](scripts/device-management/winget-updates/Template/README.md)** - Application auto-update setup

## Repository Structure

```
bug-free-umbrella/
├── docs/                              # Documentation
├── scripts/
│   ├── intune/                        # Intune management tools
│   ├── server/                        # Server management tools
│   ├── security-compliance/           # Security auditing and compliance
│   ├── device-management/             # Device management scripts
│   │   ├── autopatch/                 # Windows Update policies
│   │   ├── winget-updates/            # Application update scripts
│   │   ├── bitlocker-backup/          # BitLocker key backup
│   │   ├── device-uptime/             # Uptime monitoring
│   │   ├── l16-driver-block/          # Lenovo L16 driver management
│   │   ├── adobe-rum/                 # Adobe Remote Update Manager
│   │   └── remove-sccm/               # SCCM client removal
│   └── utilities/                     # Standalone utilities
├── templates/                         # Reusable script templates
└── LICENSE
```

## Getting Started

### Prerequisites

Before using these scripts, ensure you have the following:

#### For All Scripts
- **PowerShell 5.1 or later** (PowerShell 7+ recommended)
- **Administrator privileges** (most scripts require elevation)
- **Execution Policy** set appropriately

#### For Intune Scripts
- **Microsoft Graph PowerShell SDK**
  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser
  ```
- **Required Permissions**: DeviceManagementManagedDevices.Read.All (minimum)
- **Intune Administrator** or **Global Reader** role

#### For Server Scripts
- **Windows Server 2016, 2019, or 2022**
- **Local Administrator** privileges
- No additional modules required (uses built-in cmdlets)

### Verify Your Environment

**Check PowerShell Version**:
```powershell
$PSVersionTable.PSVersion
# Should show 5.1 or higher
```

**Check if running as Administrator**:
```powershell
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# Should return: True
```

**Check Execution Policy**:
```powershell
Get-ExecutionPolicy
# If Restricted, run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Check Microsoft Graph Module** (for Intune scripts):
```powershell
Get-Module Microsoft.Graph -ListAvailable
# If not installed, run: Install-Module Microsoft.Graph -Scope CurrentUser
```

### Quick Start Examples

#### Intune Management

**Generate Monthly Compliance Report**:
```powershell
cd scripts\intune

# Device compliance status
.\Get-DeviceComplianceReport.ps1

# BitLocker encryption audit
.\Get-BitLockerStatus.ps1

# Windows Update compliance
.\Get-WindowsUpdateCompliance.ps1

# All reports saved to Desktop as HTML and CSV
```

**Find and Clean Up Stale Devices**:
```powershell
# Interactive mode - prompts for days threshold
.\Find-StaleDevices.ps1

# Or specify days directly (90 days = 3 months)
.\Find-StaleDevices.ps1 -DaysInactive 90

# Review report, then optionally retire devices >180 days
.\Find-StaleDevices.ps1 -DaysInactive 180 -Action Retire
```

**Expected Time**: 5-10 minutes per report
**Output Location**: `%USERPROFILE%\Desktop\`

#### Server Administration

**Fix Stuck Windows Updates**:
```powershell
cd scripts\server

# Standard reset (fixes most issues)
.\Reset-WindowsUpdate.ps1

# Full reset including BITS and Cryptographic services
.\Reset-WindowsUpdate.ps1 -FullReset

# Then check for updates in Windows Update
```

**Expected Time**: 2-5 minutes
**Expected Result**: Windows Update services reset, can now check for updates

**Check Server Health**:
```powershell
# Verify system file integrity
.\Check-SystemIntegrity.ps1

# Quick scan (faster, SFC only)
.\Check-SystemIntegrity.ps1 -QuickScan

# Auto-repair with HTML report
.\Check-SystemIntegrity.ps1 -AutoRepair -GenerateReport
```

**Expected Time**:
- Quick scan: 5-10 minutes
- Full scan: 15-30 minutes
- With repair: 20-45 minutes

**Analyze Disk Usage**:
```powershell
# Scan all drives
.\Get-DiskReport.ps1

# Scan specific drive with report
.\Get-DiskReport.ps1 -DriveLetter C -ExportReport

# Shows cleanup suggestions with potential space savings
```

**Expected Output**: Detailed disk analysis with cleanup recommendations

#### Security & Compliance

**Run Security Baseline Check**:
```powershell
cd scripts\security-compliance

# Check system against security baseline
.\Get-SecurityBaseline.ps1

# Generate detailed report
.\Get-SecurityBaseline.ps1 -ExportReport
```

**Expected Time**: 30-60 seconds
**Expected Output**: Security compliance report with pass/fail status

**Audit Local Administrators**:
```powershell
# Audit administrator accounts
.\Get-LocalAdminAudit.ps1

# Generate detailed report
.\Get-LocalAdminAudit.ps1 -Detailed -ExportReport
```

**Expected Time**: 10-20 seconds
**Expected Output**: List of admin accounts with risk assessment

**Monthly Security Audit**:
```powershell
# Run comprehensive security checks
.\Get-SecurityBaseline.ps1 -ExportReport
.\Get-LocalAdminAudit.ps1 -ExportReport
.\Test-SecurityFeatures.ps1 -ExportReport
.\Get-ExpiredCertificates.ps1 -DaysToExpire 60 -ExportReport
.\Get-FailedLoginReport.ps1 -Hours 720 -ExportReport

# All reports saved to Desktop
```

**Expected Time**: 2-5 minutes
**Expected Output**: Comprehensive security and compliance reports

#### Winget Application Updates

**Set Up Auto-Updates for Google Chrome**:

```powershell
cd scripts\device-management\winget-updates\Template

# 1. Copy template files
New-Item -Path "..\Google Chrome" -ItemType Directory
Copy-Item "detect_v2.ps1" -Destination "..\Google Chrome\detect.ps1"
Copy-Item "remediate_v2_standard.ps1" -Destination "..\Google Chrome\remediate.ps1"

# 2. Edit detect.ps1 - Change line 1 to:
#    $ID = 'Google.Chrome'

# 3. Edit remediate.ps1 - Change line 1 to:
#    $ID = 'Google.Chrome'

# 4. Upload both files to Intune > Devices > Proactive Remediations
#    Schedule: Daily, Run as SYSTEM
```

**Deployment Time**: 20-30 minutes (including Intune configuration)
**For More Apps**: See [Winget Templates README](scripts/device-management/winget-updates/Template/README.md)

### Common Workflows

For detailed step-by-step guides, see our workflow documentation:

- **[Monthly Compliance Audit](docs/WORKFLOWS.md#monthly-compliance-audit-workflow)** - Complete compliance review process
- **[Automated Winget Updates](docs/WORKFLOWS.md#setting-up-automated-winget-updates)** - Deploy application auto-updates
- **[New Server Setup](docs/WORKFLOWS.md#new-windows-server-setup)** - Initial server configuration
- **[Device Cleanup](docs/WORKFLOWS.md#intune-device-cleanup-workflow)** - Remove stale devices
- **[BitLocker Deployment](docs/WORKFLOWS.md#bitlocker-deployment-and-monitoring)** - Enable encryption across devices

### What to Expect

**Script Execution Times**:
| Script Type | Typical Duration |
|-------------|------------------|
| Detection Scripts | 10-30 seconds |
| Winget Updates | 2-5 minutes |
| Intune Reports | 3-10 minutes |
| Server Health Checks | 15-30 minutes |
| Disk Analysis | 5-15 minutes |

**Output Formats**:
- Most scripts generate **HTML** and **CSV** reports
- Reports saved to: `C:\Users\[YourName]\Desktop\`
- Color-coded console output for quick status checks

**Exit Codes**:
- **0** = Success / No issues found
- **1** = Issues detected / Remediation needed
- See [Script Examples](docs/SCRIPT-EXAMPLES.md) for detailed behavior

### Getting Help

**Built-in Help**:
```powershell
# View detailed help for any script
Get-Help .\ScriptName.ps1 -Detailed

# See examples
Get-Help .\ScriptName.ps1 -Examples

# Full help including parameters
Get-Help .\ScriptName.ps1 -Full
```

**Documentation**:
- **Questions about usage?** → [Script Examples](docs/SCRIPT-EXAMPLES.md)
- **Following a process?** → [Workflow Guides](docs/WORKFLOWS.md)
- **Something not working?** → [Troubleshooting](docs/TROUBLESHOOTING.md)
- **Script reference?** → [Full Documentation](docs/README.md)

**Support**:
- Check existing documentation first
- Review script comments (all scripts are well-documented)
- Test in non-production environment
- Report issues with detailed error messages

## Requirements Summary

| Component | Requirement |
|-----------|-------------|
| **PowerShell** | 5.1 minimum (7.x recommended) |
| **OS (Intune)** | Windows 10/11, any supported OS |
| **OS (Server)** | Windows Server 2016/2019/2022 |
| **Privileges** | Administrator / Elevated |
| **Intune Role** | Intune Admin or Global Reader |
| **Graph Module** | Microsoft.Graph (for Intune scripts) |
| **Network** | Internet access for Intune/Graph API |

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.
