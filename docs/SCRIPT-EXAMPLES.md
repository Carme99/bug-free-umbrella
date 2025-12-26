# Script Execution Examples and Expected Outputs

This guide provides detailed examples of running scripts from the bug-free-umbrella repository, including expected outputs, execution times, and common scenarios.

## Table of Contents

- [Server Management Scripts](#server-management-scripts)
  - [Reset-WindowsUpdate.ps1](#reset-windowsupdateps1)
  - [Check-SystemIntegrity.ps1](#check-systemintegrityps1)
  - [Get-DiskReport.ps1](#get-diskreportps1)
- [Intune Management Scripts](#intune-management-scripts)
  - [Find-StaleDevices.ps1](#find-staledevicesps1)
  - [Get-DeviceComplianceReport.ps1](#get-devicecompliancereportps1)
  - [Get-BitLockerStatus.ps1](#get-bitlockerstatusps1)
- [Winget Update Scripts](#winget-update-scripts)
  - [Detection Script Behavior](#detection-script-behavior)
  - [Remediation Script Behavior](#remediation-script-behavior)
- [Proactive Remediation Scripts](#proactive-remediation-scripts)

---

## Server Management Scripts

### Reset-WindowsUpdate.ps1

**Purpose**: Fixes stuck Windows Update by resetting all update components.

**Execution Time**: 2-5 minutes

**Prerequisites**:
- Administrator privileges
- Windows Server 2016, 2019, or 2022

#### Example 1: Standard Reset

```powershell
.\Reset-WindowsUpdate.ps1
```

**Expected Output**:
```
[2025-12-23 10:30:15] [INFO] Starting Windows Update Reset Process
[2025-12-23 10:30:15] [INFO] Server: SERVER01 | OS: Microsoft Windows Server 2019 Datacenter
[2025-12-23 10:30:16] [INFO] Stopping Windows Update services...
[2025-12-23 10:30:17] [SUCCESS] Stopped service: wuauserv
[2025-12-23 10:30:18] [SUCCESS] Stopped service: cryptSvc
[2025-12-23 10:30:19] [SUCCESS] Stopped service: bits
[2025-12-23 10:30:20] [SUCCESS] Stopped service: msiserver
[2025-12-23 10:30:20] [INFO] Clearing Windows Update cache...
[2025-12-23 10:30:25] [SUCCESS] Cleared cache: C:\Windows\SoftwareDistribution
[2025-12-23 10:30:28] [SUCCESS] Cleared cache: C:\Windows\System32\catroot2
[2025-12-23 10:30:28] [INFO] Re-registering Windows Update DLLs...
[2025-12-23 10:31:45] [INFO] Registered 35 DLLs successfully
[2025-12-23 10:31:45] [INFO] Restarting Windows Update services...
[2025-12-23 10:31:48] [SUCCESS] Started service: wuauserv
[2025-12-23 10:31:49] [SUCCESS] Started service: cryptSvc
[2025-12-23 10:31:50] [SUCCESS] Started service: bits
[2025-12-23 10:31:51] [SUCCESS] Started service: msiserver
[2025-12-23 10:31:51] [SUCCESS] Windows Update reset completed successfully!
[2025-12-23 10:31:51] [INFO] Recommendation: Run Windows Update check now
```

**What Happened**:
1. All Windows Update services were stopped
2. Cache directories were cleared (freed ~500MB-2GB typically)
3. 35 system DLLs were re-registered
4. Services were restarted
5. Total time: ~1.5 minutes

**Next Steps**:
- Open Windows Update and click "Check for updates"
- Updates should now download/install normally
- If issues persist, try `-FullReset` parameter

#### Example 2: Full Reset (Advanced)

```powershell
.\Reset-WindowsUpdate.ps1 -FullReset
```

**Expected Output** (additional to standard):
```
[2025-12-23 10:30:20] [INFO] Performing full reset (including BITS and Cryptographic services)...
[2025-12-23 10:30:21] [INFO] Resetting BITS queue...
[2025-12-23 10:30:25] [SUCCESS] BITS queue cleared
[2025-12-23 10:30:25] [INFO] Resetting Cryptographic services...
[2025-12-23 10:30:30] [SUCCESS] Cryptographic services reset
```

**When to Use Full Reset**:
- Standard reset didn't fix the issue
- Error code 0x8024402F (connection issues)
- BITS transfer errors
- Execution time: ~3-5 minutes

---

### Check-SystemIntegrity.ps1

**Purpose**: Verifies system file integrity and detects corruption.

**Execution Time**:
- Quick Scan: 5-10 minutes
- Full Scan: 15-30 minutes
- With Auto-Repair: 20-45 minutes

#### Example 1: Quick Scan

```powershell
.\Check-SystemIntegrity.ps1 -QuickScan
```

**Expected Output**:
```
[2025-12-23 11:00:00] Starting System Integrity Check (Quick Scan)
[2025-12-23 11:00:00] Server: SERVER01 | OS: Windows Server 2019

========================================
PHASE 1: System File Checker (SFC)
========================================
[2025-12-23 11:00:05] Running SFC scan...
[2025-12-23 11:04:32] SFC Scan Progress: 100%
[2025-12-23 11:04:32] SFC Result: No integrity violations found

========================================
PHASE 2: DISM Health Check
========================================
[2025-12-23 11:04:35] Checking component store health...
[2025-12-23 11:05:20] Component Store Status: Healthy
[2025-12-23 11:05:20] Repairable: Yes

========================================
SUMMARY
========================================
✓ System files: OK
✓ Component store: Healthy
✓ No issues detected

Total scan time: 5 minutes 20 seconds
```

**Interpretation**:
- ✓ = Passed (no action needed)
- ⚠ = Warning (monitor)
- ✗ = Failed (action required)

#### Example 2: Full Scan with Issues Detected

```powershell
.\Check-SystemIntegrity.ps1
```

**Expected Output** (with corruption):
```
[2025-12-23 11:10:00] Starting System Integrity Check (Full Scan)
[2025-12-23 11:10:00] Server: SERVER02 | OS: Windows Server 2022

========================================
PHASE 1: System File Checker (SFC)
========================================
[2025-12-23 11:10:05] Running SFC scan...
[2025-12-23 11:17:45] SFC Scan Progress: 100%
[2025-12-23 11:17:45] SFC Result: ⚠ Corrupt files found
[2025-12-23 11:17:45] Details: 3 files could not be repaired

Corrupt Files:
  - C:\Windows\System32\msvcrt.dll
  - C:\Windows\System32\kernel32.dll
  - C:\Windows\System32\ntdll.dll

========================================
PHASE 2: DISM Health Check
========================================
[2025-12-23 11:17:50] Scanning component store...
[2025-12-23 11:20:15] Component Store Status: ⚠ Repairable
[2025-12-23 11:20:15] Corruption detected: Yes
[2025-12-23 11:20:15] Repair source required: No (online repair possible)

========================================
PHASE 3: DISM Repair
========================================
[2025-12-23 11:20:20] Starting component store repair...
[2025-12-23 11:30:45] Repair Progress: 100%
[2025-12-23 11:30:45] Repair Result: ✓ Successfully repaired

========================================
PHASE 4: Event Log Analysis
========================================
[2025-12-23 11:30:50] Scanning last 24 hours for critical errors...
[2025-12-23 11:31:10] Found 2 critical events:
  - EventID 41 (Kernel-Power): Unexpected shutdown at 2025-12-22 03:15
  - EventID 7001 (Service Control Manager): Dependency service failed

========================================
SUMMARY
========================================
✓ System files: Repaired
✓ Component store: Repaired
⚠ Event log: 2 critical events (review recommended)

Recommendations:
  1. Investigate unexpected shutdown on 2025-12-22
  2. Check service dependencies
  3. Restart server to complete repairs
  4. Run SFC again after restart to verify

Total scan time: 21 minutes 10 seconds
```

**Next Steps After Detecting Issues**:
1. Restart the server (required for repairs to take effect)
2. Run the script again to verify repairs
3. Investigate any remaining critical events

#### Example 3: Auto-Repair with Report

```powershell
.\Check-SystemIntegrity.ps1 -AutoRepair -GenerateReport
```

**Expected Output**:
```
[2025-12-23 12:00:00] Starting System Integrity Check (Auto-Repair Mode)
[2025-12-23 12:00:00] HTML report will be generated on completion

... [scan output] ...

========================================
SUMMARY
========================================
✓ All checks passed
✓ All issues repaired

Report saved to: C:\Users\Administrator\Desktop\SystemIntegrity_SERVER01_20251223_120000.html

The HTML report contains:
  - Detailed scan results
  - Event log analysis
  - Repair actions taken
  - Recommendations
```

**Report Contents**:
- Executive summary with pass/fail status
- Detailed results from each scan phase
- Before/after comparison
- Timeline of repair actions
- Recommended next steps
- Full event log details

---

### Get-DiskReport.ps1

**Purpose**: Analyzes disk usage and identifies cleanup opportunities.

**Execution Time**: 5-15 minutes (depends on disk size)

#### Example 1: Analyze All Drives

```powershell
.\Get-DiskReport.ps1
```

**Expected Output**:
```
[2025-12-23 13:00:00] Starting disk analysis on SERVER01...
[2025-12-23 13:00:01] Scanning all fixed drives...

========================================
DRIVE ANALYSIS
========================================

--- Drive C: (System) ---
Total Size:     500.00 GB
Used Space:     387.50 GB (77.50%)
Free Space:     112.50 GB (22.50%)
Status:         ✓ OK (>20% free)

Top 10 Largest Folders:
  1.  45.2 GB  C:\Windows\WinSxS
  2.  38.7 GB  C:\Program Files
  3.  28.3 GB  C:\inetpub\logs\LogFiles
  4.  22.1 GB  C:\Windows\SoftwareDistribution
  5.  18.9 GB  C:\Users
  6.  15.4 GB  C:\Windows\Installer
  7.  12.8 GB  C:\ProgramData
  8.   9.3 GB  C:\Windows\Temp
  9.   7.6 GB  C:\Windows\System32
 10.   5.2 GB  C:\Windows\Logs

--- Drive D: (Data) ---
Total Size:    1000.00 GB
Used Space:     856.20 GB (85.62%)
Free Space:     143.80 GB (14.38%)
Status:         ⚠ WARNING (<20% free)

Top 10 Largest Folders:
  1. 420.5 GB  D:\Backups
  2. 185.3 GB  D:\Database
  3.  98.7 GB  D:\Logs
  4.  67.2 GB  D:\Files
  5.  45.8 GB  D:\Archive
  [...]

========================================
CLEANUP SUGGESTIONS
========================================
Total Potential Savings: 68.5 GB

Category                    Path                                Size      Risk    Action
--------                    ----                                ----      ----    ------
IIS Log Files              C:\inetpub\logs\LogFiles            28.3 GB   LOW     Archive logs >90 days
Windows Update Cache       C:\Windows\SoftwareDistribution\    22.1 GB   LOW     Clear download folder
Windows Temp Files         C:\Windows\Temp                      9.3 GB   LOW     Delete files >7 days
Windows Installer Cache    C:\Windows\Installer                 5.8 GB   MED     Use Disk Cleanup
Old User Profiles          C:\Users\olduser*                    3.0 GB   LOW     Remove unused profiles

Detailed Cleanup Commands:
-------------------------

# 1. Clean IIS logs older than 90 days (saves ~25 GB)
Get-ChildItem "C:\inetpub\logs\LogFiles" -Recurse -File |
    Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-90)} |
    Remove-Item -Force

# 2. Clear Windows Update cache (saves ~22 GB)
Stop-Service wuauserv
Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force
Start-Service wuauserv

# 3. Clean Windows Temp (saves ~9 GB)
Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

Total scan time: 8 minutes 35 seconds
```

**Interpretation**:
- **Risk Levels**:
  - LOW: Safe to delete, no impact
  - MEDIUM: Generally safe, but verify first
  - HIGH: Requires careful consideration

- **Status Indicators**:
  - ✓ OK: >20% free space
  - ⚠ WARNING: 10-20% free
  - ✗ CRITICAL: <10% free

#### Example 2: Specific Drive with HTML Report

```powershell
.\Get-DiskReport.ps1 -DriveLetter D -ExportReport
```

**Expected Output**:
```
[2025-12-23 13:15:00] Analyzing drive D:...
[2025-12-23 13:20:45] Analysis complete
[2025-12-23 13:20:50] HTML report generated: C:\Users\Administrator\Desktop\DiskReport_D_20251223.html

Report includes:
  ✓ Visual charts of disk usage
  ✓ Folder size breakdown
  ✓ Cleanup recommendations
  ✓ Historical trend (if previous reports exist)
  ✓ Interactive cleanup commands

Opening report in default browser...
```

**HTML Report Features**:
- Pie charts showing space distribution
- Bar graphs for top folders
- Color-coded risk indicators
- Copy-paste ready cleanup commands
- Before/after cleanup tracking

---

## Intune Management Scripts

### Find-StaleDevices.ps1

**Purpose**: Identifies devices that haven't synced with Intune recently.

**Execution Time**: 2-10 minutes (depends on device count)

**Prerequisites**:
- Microsoft.Graph PowerShell module
- Permissions: DeviceManagementManagedDevices.Read.All (or ReadWrite for delete/retire)

#### Example 1: Interactive Report Mode

```powershell
.\Find-StaleDevices.ps1
```

**Expected Output**:
```
========================================
Stale Device Finder
========================================

How many days of inactivity should be considered 'stale'?
Common values:
  30  - 1 month
  60  - 2 months
  90  - 3 months (recommended minimum)
  180 - 6 months
  365 - 1 year

Enter number of days: 90

Searching for devices inactive for 90+ days...
Action mode: Report

Connecting to Microsoft Graph...
✓ Connected successfully as admin@company.com

Retrieving all Intune managed devices...
Found 847 total devices

Analyzing last sync times...
Progress: [████████████████████] 100% (847/847)

========================================
STALE DEVICES FOUND
========================================
Found 23 devices inactive for 90+ days

Device Name           Last Sync       Days Ago  User                  OS
-----------           ---------       --------  ----                  --
LAPTOP-ABC123         2025-09-15      99        john.doe@company.com  Windows 10
DESKTOP-XYZ789        2025-09-10      104       jane.smith@company.com Windows 11
SURFACE-DEF456        2025-08-25      120       bob.jones@company.com Windows 10
TABLET-GHI789         2025-08-01      144       alice.brown@company.com Windows 11
[... 19 more devices ...]

========================================
SUMMARY
========================================
Total devices scanned:      847
Devices inactive 90+ days:  23 (2.72%)
Devices inactive 180+ days: 8 (0.94%)

Breakdown by OS:
  Windows 10:  15 devices
  Windows 11:   8 devices

Breakdown by last sync age:
  90-119 days:  12 devices
  120-179 days:  3 devices
  180+ days:     8 devices

Reports saved:
  ✓ HTML: C:\Users\Administrator\Desktop\StaleDevices_90days_20251223.html
  ✓ CSV:  C:\Users\Administrator\Desktop\StaleDevices_90days_20251223.csv

Recommendation: Review devices inactive >180 days for removal

Disconnected from Microsoft Graph
Total execution time: 3 minutes 42 seconds
```

**HTML Report Contains**:
- Interactive sortable table of all stale devices
- Visual charts showing distribution
- Device details (serial, model, enrolled date)
- Last logged-in user information
- Recommended actions per device

#### Example 2: Retire Stale Devices (with safety checks)

```powershell
.\Find-StaleDevices.ps1 -DaysInactive 180 -Action Retire
```

**Expected Output**:
```
========================================
Stale Device Finder
========================================

Searching for devices inactive for 180+ days...
Action mode: Retire ⚠

Connecting to Microsoft Graph...
✓ Connected successfully as admin@company.com

Retrieving all Intune managed devices...
Found 847 total devices

Analyzing last sync times...
Progress: [████████████████████] 100% (847/847)

Found 8 devices inactive for 180+ days

========================================
⚠ WARNING: RETIRE ACTION REQUESTED ⚠
========================================

You are about to RETIRE 8 devices from Intune.

What happens when you retire a device:
  • Company data is removed
  • Device is unenrolled from Intune
  • Personal data remains on device
  • Device can be re-enrolled
  • This action cannot be easily undone

Devices to be retired:
  1. LAPTOP-OLD001  (Last sync: 2025-06-15, 191 days ago) - User: old.employee@company.com
  2. DESKTOP-OLD002 (Last sync: 2025-06-10, 196 days ago) - User: former.worker@company.com
  3. TABLET-OLD003  (Last sync: 2025-05-20, 217 days ago) - User: departed.user@company.com
  [... 5 more devices ...]

To confirm, type 'YES' in capital letters and press Enter.
Type anything else to cancel.
Confirm: YES

Confirmed. Proceeding with retire operation...

Retiring devices:
  [1/8] LAPTOP-OLD001... ✓ Successfully retired
  [2/8] DESKTOP-OLD002... ✓ Successfully retired
  [3/8] TABLET-OLD003... ✓ Successfully retired
  [4/8] SURFACE-OLD004... ✓ Successfully retired
  [5/8] PHONE-OLD005... ⚠ Failed (device not found - may have been deleted)
  [6/8] LAPTOP-OLD006... ✓ Successfully retired
  [7/8] DESKTOP-OLD007... ✓ Successfully retired
  [8/8] TABLET-OLD008... ✓ Successfully retired

========================================
RETIRE OPERATION SUMMARY
========================================
Successfully retired: 7 devices
Failed to retire:     1 device (see details above)

Detailed log saved to: C:\Users\Administrator\Desktop\DeviceRetire_Log_20251223.txt

Disconnected from Microsoft Graph
Total execution time: 2 minutes 15 seconds
```

**Safety Features**:
- Explicit confirmation required
- Shows exactly what will happen
- Lists all affected devices
- Detailed logging of all actions
- Reports any failures

#### Example 3: Delete Action (Most Dangerous)

```powershell
.\Find-StaleDevices.ps1 -DaysInactive 365 -Action Delete
```

**Expected Output** (similar to retire, but more warnings):
```
========================================
⚠⚠⚠ WARNING: DELETE ACTION REQUESTED ⚠⚠⚠
========================================

You are about to PERMANENTLY DELETE 3 devices from Intune.

What happens when you delete a device:
  • Device is permanently removed from Intune
  • All device history is deleted
  • Device policies are removed
  • This action CANNOT be undone
  • Device must be fully re-enrolled to manage again

This is a DESTRUCTIVE operation. Only proceed if you're certain.

Devices to be deleted:
  [Lists devices...]

To confirm this DANGEROUS operation:
  1. Type 'DELETE' in capital letters
  2. Then type the number of devices (3)
  3. Press Enter

Confirm (DELETE [space] 3): DELETE 3

Final confirmation - are you absolutely sure? (yes/no): yes

Proceeding with deletion...
  [Deletion process with progress...]
```

---

### Get-DeviceComplianceReport.ps1

**Purpose**: Generates detailed reports on device compliance status.

**Execution Time**: 3-8 minutes (varies with device count)

#### Example: Generate Full Compliance Report

```powershell
.\Get-DeviceComplianceReport.ps1
```

**Expected Output**:
```
========================================
Device Compliance Report Generator
========================================

Connecting to Microsoft Graph...
✓ Connected successfully

Retrieving compliance policies...
Found 5 active compliance policies:
  • Windows 10/11 - Security Baseline
  • iOS - Standard Configuration
  • Android - Corporate Owned
  • macOS - Security Requirements
  • Windows - BitLocker Required

Retrieving all managed devices...
Found 847 devices

Checking compliance status...
Progress: [████████████████████] 100% (847/847)

========================================
COMPLIANCE SUMMARY
========================================

Overall Compliance:
  ✓ Compliant:     789 devices (93.15%)
  ✗ Non-Compliant:  45 devices (5.31%)
  ⚠ Not Evaluated:  13 devices (1.54%)

By Platform:
  Windows: 712/750 compliant (94.93%)
  iOS:      45/50 compliant (90.00%)
  Android:  28/35 compliant (80.00%)
  macOS:     4/12 compliant (33.33%)

========================================
NON-COMPLIANT DEVICES (45 total)
========================================

Device Name          User                  OS           Reason
-----------          ----                  --           ------
LAPTOP-ABC123        john.doe@company      Windows 11   BitLocker not enabled
DESKTOP-XYZ789       jane.smith@company    Windows 10   Password doesn't meet requirements
PHONE-IOS001         bob.jones@company     iOS 17.2     Device lock timeout >5 minutes
MACBOOK-M1-001       alice.brown@company   macOS 14     Firewall disabled
[... 41 more devices ...]

Top Non-Compliance Reasons:
  1. BitLocker not enabled (18 devices)
  2. Password requirements not met (12 devices)
  3. Firewall disabled (8 devices)
  4. Device lock timeout too long (5 devices)
  5. Antivirus not running (2 devices)

========================================
DETAILED NON-COMPLIANCE BREAKDOWN
========================================

Policy: Windows 10/11 - Security Baseline
Non-compliant devices: 30

  LAPTOP-ABC123 (john.doe@company.com)
    ✗ BitLocker: Not enabled on system drive
    ✗ Password: Minimum length not met (requires 14, has 8)
    ✓ Windows Defender: Enabled
    ✓ Firewall: Enabled
    Last checked: 2025-12-23 08:15:23

  DESKTOP-XYZ789 (jane.smith@company.com)
    ✓ BitLocker: Enabled and backed up
    ✗ Password: Password expiration disabled (requires 90 days)
    ✗ Screen lock: Timeout set to 30 minutes (requires ≤15 minutes)
    ✓ Windows Defender: Enabled
    Last checked: 2025-12-23 07:42:11

[... continues for all non-compliant devices ...]

========================================
RECOMMENDED ACTIONS
========================================

Immediate Actions Required (Critical):
  1. Enable BitLocker on 18 devices
     Devices: LAPTOP-ABC123, DESKTOP-DEF456, [...]
     Risk: Data loss if device is lost/stolen
     Fix: Deploy BitLocker remediation script

  2. Fix password policies on 12 devices
     Devices: DESKTOP-XYZ789, LAPTOP-GHI789, [...]
     Risk: Weak authentication
     Fix: Notify users to update passwords

  3. Enable firewall on 8 macOS devices
     Devices: MACBOOK-M1-001, MACBOOK-M1-002, [...]
     Risk: Network vulnerabilities
     Fix: Deploy configuration profile

Reports generated:
  ✓ HTML: C:\Users\Administrator\Desktop\ComplianceReport_20251223.html
  ✓ CSV:  C:\Users\Administrator\Desktop\ComplianceReport_20251223.csv

HTML report includes:
  • Executive summary with charts
  • Detailed device-by-device breakdown
  • Compliance trend over time
  • Remediation recommendations
  • Exportable device lists

Disconnected from Microsoft Graph
Total execution time: 5 minutes 38 seconds
```

**Understanding the Report**:

**Compliance States**:
- ✓ **Compliant**: Device meets all policy requirements
- ✗ **Non-Compliant**: Device fails one or more policy checks
- ⚠ **Not Evaluated**: Device hasn't checked in recently or evaluation pending

**Common Non-Compliance Reasons**:
| Reason | Impact | Fix |
|--------|--------|-----|
| BitLocker not enabled | HIGH | Deploy BitLocker remediation |
| Weak password | HIGH | Force password change |
| Firewall disabled | MEDIUM | Enable via configuration profile |
| Antivirus disabled | HIGH | Deploy security baseline |
| Screen lock timeout | LOW | Adjust device settings |

---

### Get-BitLockerStatus.ps1

**Purpose**: Audits BitLocker encryption and key backup status.

**Execution Time**: 5-12 minutes

#### Example: Full BitLocker Audit

```powershell
.\Get-BitLockerStatus.ps1
```

**Expected Output**:
```
========================================
BitLocker Status Audit
========================================

Connecting to Microsoft Graph...
✓ Connected successfully

Retrieving all Windows devices...
Found 750 Windows devices

Checking BitLocker status...
Progress: [████████████████████] 100% (750/750)

========================================
ENCRYPTION SUMMARY
========================================

Overall Status:
  ✓ Fully Encrypted:           695 devices (92.67%)
  ⚠ Partially Encrypted:        15 devices (2.00%)
  ✗ Not Encrypted:              35 devices (4.67%)
  ❓ Unknown/Not Reported:       5 devices (0.67%)

Recovery Key Backup Status:
  ✓ Keys Backed Up:            680 devices (97.84% of encrypted)
  ✗ Keys NOT Backed Up:         15 devices (2.16% of encrypted)
  ⚠ Multiple Keys:              10 devices (needs review)

========================================
ENCRYPTION DETAILS
========================================

✓ FULLY ENCRYPTED DEVICES (695)
Example entries:

Device Name         User                  Volumes  Key Backup  Last Checked
-----------         ----                  -------  ----------  ------------
LAPTOP-ABC123       john.doe@company      C:       ✓ Azure AD  2025-12-23 08:00
DESKTOP-XYZ789      jane.smith@company    C:, D:   ✓ Azure AD  2025-12-23 07:45
SURFACE-PRO-001     bob.jones@company     C:       ✓ Azure AD  2025-12-23 09:12
[... 692 more ...]

⚠ PARTIALLY ENCRYPTED DEVICES (15)
These devices have BitLocker enabled but encryption is in progress:

Device Name         User                  Status              Progress  ETA
-----------         ----                  ------              --------  ---
LAPTOP-NEW001       alice.brown@company   Encrypting C:       45%       ~2 hours
DESKTOP-NEW002      charlie.davis@company Encrypting C:       78%       ~45 min
LAPTOP-NEW003       david.evans@company   Encrypting C:, D:   C:100%, D:12%  ~6 hours
[... 12 more ...]

✗ NOT ENCRYPTED DEVICES (35)
⚠ HIGH RISK - These devices need immediate attention:

Device Name         User                  OS            Last Seen     Risk Level
-----------         ----                  --            ---------     ----------
LAPTOP-RISK001      eve.foster@company    Windows 11    2 hours ago   HIGH
DESKTOP-RISK002     frank.garcia@company  Windows 10    5 hours ago   HIGH
LAPTOP-RISK003      grace.hill@company    Windows 11    1 day ago     MEDIUM
LAPTOP-OLD001       hannah.ivan@company   Windows 10    45 days ago   LOW (stale)
[... 31 more ...]

========================================
RECOVERY KEY ISSUES
========================================

✗ KEYS NOT BACKED UP (15 devices)
⚠ CRITICAL - Recovery keys not in Azure AD/Intune:

Device Name         User                  Encrypted  Key Status       Action Required
-----------         ----                  ---------  ----------       ---------------
LAPTOP-NOKEY001     ivan.jackson@company  ✓ Yes      ✗ No backup      Backup key immediately
DESKTOP-NOKEY002    julia.king@company    ✓ Yes      ✗ No backup      Backup key immediately
[... 13 more ...]

Remediation Command:
Deploy the BitLocker key backup remediation script to these devices.
Script location: scripts/device-management/bitlocker-backup/

⚠ MULTIPLE RECOVERY KEYS (10 devices)
These devices have multiple BitLocker key protectors (review recommended):

Device Name         User                  Key Count  Key IDs
-----------         ----                  ---------  -------
LAPTOP-MULTI001     kate.lopez@company    3          ABC-123-DEF, GHI-456-JKL, MNO-789-PQR
DESKTOP-MULTI002    leo.martinez@company  2          STU-111-VWX, YZA-222-BCD
[... 8 more ...]

Cause: Usually from re-encryption or recovery operations
Action: Verify current key is backed up, remove old keys

========================================
COMPLIANCE BREAKDOWN
========================================

By Department:
  IT Department:        100% encrypted (50/50 devices)
  Finance:              98% encrypted (49/50 devices)
  Sales:                95% encrypted (95/100 devices)
  Marketing:            88% encrypted (44/50 devices)
  Operations:           90% encrypted (450/500 devices)

Devices Requiring Attention:
  Priority 1 (Critical):    15 devices (keys not backed up)
  Priority 2 (High):        35 devices (not encrypted)
  Priority 3 (Medium):      15 devices (encryption in progress)
  Priority 4 (Low):         10 devices (multiple keys)

========================================
RECOMMENDED ACTIONS
========================================

1. IMMEDIATE (within 24 hours):
   ☐ Backup recovery keys for 15 devices
      Command: Deploy bitlocker-backup remediation script
      Target: Devices in "Keys NOT Backed Up" section

2. HIGH PRIORITY (within 1 week):
   ☐ Enable BitLocker on 35 unencrypted devices
      Command: Deploy BitLocker enablement policy
      Target: Devices in "NOT Encrypted" section
      Note: Check if devices support BitLocker (TPM 1.2+)

3. MONITOR (ongoing):
   ☐ Track encryption progress on 15 partially encrypted devices
      Expected completion: 24-48 hours
      Action if stuck: Investigate and restart encryption

4. CLEANUP (within 1 month):
   ☐ Review and remove old recovery keys on 10 devices
      Verify current key is backed up first
      Remove obsolete key protectors

Reports generated:
  ✓ HTML: C:\Users\Administrator\Desktop\BitLockerStatus_20251223.html
  ✓ CSV:  C:\Users\Administrator\Desktop\BitLockerStatus_20251223.csv
  ✓ Priority Devices CSV: C:\Users\Administrator\Desktop\BitLocker_Priority_20251223.csv

The HTML report includes:
  • Visual dashboard with pie charts
  • Encryption status over time (trend)
  • Interactive device tables
  • One-click remediation commands
  • Compliance by department
  • Export capabilities

Disconnected from Microsoft Graph
Total execution time: 8 minutes 22 seconds
```

**Understanding Risk Levels**:
- **HIGH**: Unencrypted device actively in use
- **MEDIUM**: Unencrypted but seen recently
- **LOW**: Old/stale device (likely decommissioned)

**Key Backup Methods**:
- **Azure AD**: Recommended for cloud-only
- **Intune**: Synced with Azure AD
- **Active Directory**: On-premises domain
- **None**: ⚠ No backup (risky)

---

## Winget Update Scripts

### Detection Script Behavior

Detection scripts check if an application update is available and return:
- **Exit 0**: No update needed (compliant)
- **Exit 1**: Update available (triggers remediation)

#### Example: Google Chrome Detection

**Detection Running**:
```
[Intune Console - Device Proactive Remediation Log]

Detection started: 2025-12-23 10:00:00
Running as: SYSTEM
PowerShell: 5.1 (64-bit)

=== Script Output ===
Application update available for Google Chrome.
Current version is 120.0.6099.109, version available is 120.0.6099.130

Exit Code: 1 (Update needed)
Detection completed: 2025-12-23 10:00:15 (15 seconds)
```

**Scenarios**:

**Scenario 1: Update Available, Chrome Not Running**
```
Application update available for Google Chrome.
Current version is 120.0.6099.109, version available is 120.0.6099.130
Exit Code: 1
Result: Remediation will run
```

**Scenario 2: Update Available, Chrome Running**
```
Application update available for Google Chrome.
Current version is 120.0.6099.109, version available is 120.0.6099.130.
Google Chrome is currently running, will try again later.
Exit Code: 1
Result: Remediation will run (but may skip if app is running)
```

**Scenario 3: No Update Available**
```
Google Chrome upgraded to 120.0.6099.130, or Google Chrome was already up to date.
Exit Code: 0
Result: No remediation needed
```

**Scenario 4: App Not Installed**
```
Google Chrome is not installed on this device.
Exit Code: 0
Result: No action taken
```

---

### Remediation Script Behavior

Remediation scripts perform the actual update.

#### Example: Standard Remediation (Wait for App to Close)

**Remediation Running - App Open**:
```
[Intune Console - Device Proactive Remediation Log]

Remediation started: 2025-12-23 10:05:00
Running as: SYSTEM
PowerShell: 5.1 (64-bit)

=== Script Output ===
Google Chrome is currently running, will try again later.

Exit Code: 1 (Failed - will retry)
Remediation completed: 2025-12-23 10:05:05 (5 seconds)
Next retry: 2025-12-23 14:00:00 (based on schedule)
```

**Remediation Running - App Closed**:
```
[Intune Console - Device Proactive Remediation Log]

Remediation started: 2025-12-23 14:00:00
Running as: SYSTEM
PowerShell: 5.1 (64-bit)

=== Script Output ===
Application update available for Google Chrome
Downloading and Installing Google Chrome
[winget download and install progress...]

Name: Google Chrome
InstalledVersion: 120.0.6099.130

Exit Code: 0 (Success)
Remediation completed: 2025-12-23 14:03:45 (3 minutes 45 seconds)
```

#### Example: Force Close Remediation

**Remediation Running - Forcing App Closure**:
```
[Intune Console - Device Proactive Remediation Log]

Remediation started: 2025-12-23 02:00:00
Running as: SYSTEM
PowerShell: 5.1 (64-bit)

=== Script Output ===
Application update available for TeamViewer
TeamViewer is currently running
Force close enabled - terminating TeamViewer processes...
Found 2 processes: TeamViewer.exe (PID: 1234, 5678)
Terminated TeamViewer.exe (PID: 1234)
Terminated TeamViewer.exe (PID: 5678)
Waiting 5 seconds grace period...
Downloading and Installing TeamViewer
[winget installation progress...]
Installation completed successfully
Verifying installation...
✓ TeamViewer version 15.48.4 installed

Name: TeamViewer
InstalledVersion: 15.48.4

Exit Code: 0 (Success)
Remediation completed: 2025-12-23 02:04:30 (4 minutes 30 seconds)
```

**Timeline**:
1. 02:00:00 - Detection runs (Update found, Exit 1)
2. 02:00:15 - Remediation starts
3. 02:00:16 - Checks if app running (Yes)
4. 02:00:17 - Force closes app
5. 02:00:22 - Grace period complete
6. 02:00:23 - Winget download starts
7. 02:03:15 - Download complete
8. 02:03:16 - Installation starts
9. 02:04:20 - Installation complete
10. 02:04:25 - Verification complete
11. 02:04:30 - Remediation finishes (Exit 0)

---

## Proactive Remediation Scripts

### Fix-DiskSpace Example

**Detection Phase**:
```
[Detection Output]
Checking disk space on all drives...

C:\ - 15.2 GB free (8.5%) - ⚠ BELOW THRESHOLD
D:\ - 145.8 GB free (24.2%) - ✓ OK
E:\ - 892.4 GB free (78.1%) - ✓ OK

Low disk space detected on C:\ drive
Exit Code: 1
```

**Remediation Phase**:
```
[Remediation Output]
=== Disk Space Cleanup ===
Target: C:\ (15.2 GB free, 8.5%)

Cleaning Windows Temp folder...
  Deleted 1,247 files
  Freed: 3.2 GB

Emptying Recycle Bin...
  Deleted 89 items
  Freed: 1.8 GB

Clearing Windows Update cache...
  Cleared download folder
  Freed: 4.7 GB

=== Cleanup Summary ===
Total space freed: 9.7 GB
C:\ now has: 24.9 GB free (14.0%)
Status: ✓ Above threshold

Exit Code: 0
```

### Fix-WindowsUpdateStuck Example

**Detection Phase**:
```
[Detection Output]
Checking Windows Update service...
Service 'wuauserv' status: Stopped ⚠
Expected: Running

Checking pending updates...
Found 3 updates stuck in 'Downloading' state for >24 hours

Windows Update issues detected
Exit Code: 1
```

**Remediation Phase**:
```
[Remediation Output]
=== Windows Update Reset ===

Stopping services...
  ✓ Stopped wuauserv
  ✓ Stopped bits
  ✓ Stopped cryptSvc

Renaming SoftwareDistribution folder...
  ✓ C:\Windows\SoftwareDistribution → SoftwareDistribution.old

Renaming catroot2 folder...
  ✓ C:\Windows\System32\catroot2 → catroot2.old

Starting services...
  ✓ Started wuauserv
  ✓ Started bits
  ✓ Started cryptSvc

Triggering update check...
  ✓ Update check initiated

Windows Update reset completed
Exit Code: 0
```

---

## Exit Codes Reference

### Standard Exit Codes

| Code | Meaning | Detection | Remediation |
|------|---------|-----------|-------------|
| 0 | Success/Compliant | No issue found | Fix applied successfully |
| 1 | Needs Remediation/Failed | Issue detected | Fix failed, will retry |

### Intune Behavior

**Detection Exit Codes**:
- **0**: Device is compliant, no remediation needed
- **1**: Device needs remediation, run remediation script
- **Other**: Error occurred, marked as "Error" in Intune

**Remediation Exit Codes**:
- **0**: Remediation successful
- **1**: Remediation failed (Intune will retry based on schedule)
- **Other**: Error occurred, marked as "Error" in Intune

---

## Execution Time Expectations

### Quick Reference

| Script Type | Typical Duration | Factors Affecting Time |
|-------------|------------------|----------------------|
| Detection Scripts | 10-30 seconds | App installation check, version query |
| Remediation Scripts (Winget) | 2-5 minutes | Download size, internet speed |
| Server Health Checks | 1-3 minutes | Number of checks, server load |
| Disk Analysis | 5-15 minutes | Disk size, file count |
| System Integrity | 15-30 minutes | Corruption level, repair needed |
| Intune Reporting | 3-10 minutes | Device count, network speed |

### Performance Tips

**For Faster Execution**:
1. Use `-QuickScan` parameters where available
2. Filter to specific devices/drives
3. Run during off-peak hours for large operations
4. Use SSDs for better disk analysis speed

**For Slower Devices**:
- Expect 1.5-2x normal execution time
- Consider timeout settings
- Monitor for hanging processes

---

## Getting Help

If script outputs don't match these examples:
1. Check PowerShell version (`$PSVersionTable`)
2. Verify module versions
3. Check execution context (User vs SYSTEM)
4. Review prerequisites section
5. Check troubleshooting guide: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

---

**Version**: 1.0
