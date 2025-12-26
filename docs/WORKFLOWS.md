# End-to-End Workflow Guides

This document provides step-by-step walkthroughs for common administrative scenarios using the bug-free-umbrella toolkit.

## Table of Contents

- [Monthly Compliance Audit Workflow](#monthly-compliance-audit-workflow)
- [Setting Up Automated Winget Updates](#setting-up-automated-winget-updates)
- [New Windows Server Setup](#new-windows-server-setup)
- [Intune Device Cleanup Workflow](#intune-device-cleanup-workflow)
- [Troubleshooting Failed Windows Updates](#troubleshooting-failed-windows-updates)
- [BitLocker Deployment and Monitoring](#bitlocker-deployment-and-monitoring)
- [Proactive Remediation Deployment](#proactive-remediation-deployment)

---

## Monthly Compliance Audit Workflow

**Goal**: Generate comprehensive compliance reports for monthly security review.

**Time Required**: 30-45 minutes

**Prerequisites**:
- Microsoft.Graph PowerShell module installed
- Intune Administrator or Global Reader role
- Access to Intune tenant

### Step 1: Device Compliance Check (10 minutes)

```powershell
# Navigate to scripts directory
cd "C:\bug-free-umbrella\scripts\intune"

# Run compliance report
.\Get-DeviceComplianceReport.ps1
```

**Expected Output**:
- HTML report on desktop
- Shows all non-compliant devices
- Breakdown by compliance failure reason

**Action Items**:
1. Review non-compliant devices list
2. Note common failure patterns
3. Identify devices requiring immediate attention

### Step 2: BitLocker Encryption Audit (8 minutes)

```powershell
# Still in scripts\intune directory
.\Get-BitLockerStatus.ps1
```

**Expected Output**:
- Encryption status for all Windows devices
- Recovery key backup verification
- List of unencrypted devices

**Action Items**:
1. Verify all corporate devices are encrypted
2. Check recovery key backup status
3. Flag devices with missing key backups

### Step 3: Windows Update Compliance (5 minutes)

```powershell
.\Get-WindowsUpdateCompliance.ps1
```

**Expected Output**:
- Update status for all devices
- Devices with pending updates
- Devices not checking for updates

**Action Items**:
1. Identify devices behind on updates
2. Note devices with update failures
3. Check for devices needing Windows Update reset

### Step 4: Stale Device Review (7 minutes)

```powershell
# Find devices inactive for 90+ days
.\Find-StaleDevices.ps1 -DaysInactive 90
```

**Expected Output**:
- List of devices not synced in 90+ days
- User information for each device
- HTML and CSV reports

**Action Items**:
1. Review list with department managers
2. Identify devices for retirement
3. Schedule cleanup for next month

### Step 5: Generate Summary Report (10 minutes)

**Consolidate Findings**:

Create a summary document with:

```
Monthly Compliance Report - [Month Year]
=========================================

Executive Summary:
- Total Devices: 847
- Compliant Devices: 789 (93.15%)
- Non-Compliant: 45 (5.31%)
- Not Evaluated: 13 (1.54%)

Key Findings:
1. BitLocker Compliance
   • Encrypted: 695/750 (92.67%)
   • Missing key backups: 15 devices ⚠
   • Action: Deploy key backup remediation

2. Windows Updates
   • Up to date: 712/750 (94.93%)
   • Pending updates: 38 devices
   • Action: Monitor over next week

3. Stale Devices
   • 90+ days inactive: 23 devices
   • 180+ days inactive: 8 devices
   • Action: Schedule retirement Q1 2025

4. Policy Failures
   • Password policy: 12 devices
   • Firewall disabled: 8 devices
   • Action: Notify users, enforce policies

Recommendations:
☐ Deploy BitLocker remediation to 15 devices
☐ Investigate update failures on 12 devices
☐ Schedule stale device cleanup
☐ Review password policy enforcement

Next Month Actions:
☐ Re-audit after remediation
☐ Track improvement trends
☐ Review policy effectiveness
```

**Attach Reports**:
- ComplianceReport_[DATE].html
- BitLockerStatus_[DATE].html
- WindowsUpdateCompliance_[DATE].html
- StaleDevices_90days_[DATE].csv

---

## Setting Up Automated Winget Updates

**Goal**: Deploy automated updates for Google Chrome across all devices.

**Time Required**: 20-30 minutes

**Prerequisites**:
- Access to Intune admin portal
- Winget package ID (Google.Chrome)
- Test device group created

### Step 1: Prepare Scripts (5 minutes)

```powershell
# Navigate to winget templates
cd "C:\bug-free-umbrella\scripts\device-management\winget-updates\Template"

# Copy template files to new folder
$appName = "Google Chrome"
New-Item -Path "..\$appName" -ItemType Directory
Copy-Item "detect_v2.ps1" -Destination "..\$appName\detect.ps1"
Copy-Item "remediate_v2_standard.ps1" -Destination "..\$appName\remediate.ps1"
```

### Step 2: Configure Scripts (2 minutes)

**Edit detect.ps1**:
```powershell
# Open in editor
notepad "..\$appName\detect.ps1"
```

Change line 1:
```powershell
$ID = 'Google.Chrome'  # That's it!
```

**Edit remediate.ps1**:
```powershell
notepad "..\$appName\remediate.ps1"
```

Change line 1:
```powershell
$ID = 'Google.Chrome'  # Same ID
```

Save both files.

### Step 3: Test Locally (Optional, 5 minutes)

```powershell
# Test detection on your device
powershell.exe -ExecutionPolicy Bypass -File "..\$appName\detect.ps1"
```

**Expected Output**:
```
Application update available for Google Chrome.
Current version is 120.0.6099.109, version available is 120.0.6099.130
Exit Code: 1
```

Or:
```
Google Chrome upgraded to 120.0.6099.130, or Google Chrome was already up to date.
Exit Code: 0
```

### Step 4: Deploy to Intune (10 minutes)

**Via Intune Portal**:

1. Sign in to https://intune.microsoft.com

2. Navigate to:
   **Devices → Scripts and remediations → Proactive remediations**

3. Click **+ Create script package**

4. **Basics** tab:
   - Name: `Winget Update - Google Chrome`
   - Description: `Automatically updates Google Chrome via winget`
   - Publisher: `IT Department`

5. **Settings** tab:
   - **Detection script**: Upload `detect.ps1`
   - **Remediation script**: Upload `remediate.ps1`
   - **Run this script using the logged-on credentials**: No
   - **Enforce script signature check**: No
   - **Run script in 64-bit PowerShell**: Yes

6. **Assignments** tab:
   - Click **+ Add group**
   - Select test group: `IT-TestDevices` (5-10 devices)
   - Schedule: **Daily at 2:00 AM**

7. **Review + Create**

8. Click **Create**

### Step 5: Monitor Deployment (Wait 24-48 hours)

**Check Status**:

1. Go to **Devices → Scripts and remediations → Proactive remediations**
2. Click on `Winget Update - Google Chrome`
3. View **Device status** tab

**Expected Results**:

After first run (detection):
```
Status: Detection succeeded
Devices with issues: 3 (update available)
Devices without issues: 2 (up to date)
```

After remediation run:
```
Status: Remediation succeeded
Devices remediated: 3
Devices without issues: 5
```

**Troubleshooting**:

If "Detection failed":
- Check device has winget installed
- Verify script runs as SYSTEM
- Check Intune logs on device

If "Remediation failed":
- App may be running (will retry)
- Check network connectivity
- Verify winget package ID is correct

### Step 6: Expand Deployment (5 minutes)

**After successful test**:

1. Return to the remediation package
2. Click **Assignments**
3. **Edit** the existing assignment
4. Change group from `IT-TestDevices` to `All-Windows-Devices`
5. Adjust schedule if needed (e.g., `Every 4 hours`)
6. Save changes

### Step 7: Repeat for Other Applications (10 minutes per app)

Common applications to add:

```powershell
# Mozilla Firefox
$ID = 'Mozilla.Firefox'

# Adobe Acrobat Reader
$ID = 'Adobe.Acrobat.Reader.64-bit'

# 7-Zip
$ID = '7zip.7zip'

# Visual Studio Code
$ID = 'Microsoft.VisualStudioCode'

# Notepad++
$ID = 'Notepad++.Notepad++'
```

Repeat Steps 1-6 for each application.

---

## New Windows Server Setup

**Goal**: Configure a newly deployed Windows Server with recommended settings.

**Time Required**: 45-60 minutes

**Prerequisites**:
- Administrator access to new server
- Server is domain-joined (if applicable)
- Scripts downloaded to server

### Phase 1: Regional Settings (10 minutes)

**If deploying in UK environment**:

```powershell
# Set English UK regional settings
cd "C:\bug-free-umbrella\scripts\server"
.\Set-EnglishUKRegion.ps1 -ApplyToExistingUsers
```

**Expected Output**:
```
Setting English (UK) regional settings...
✓ System locale set to en-GB
✓ Timezone set to GMT Standard Time
✓ Date format set to DD/MM/YYYY
✓ Currency set to GBP (£)
✓ Keyboard layout set to UK
✓ Settings applied to all users

Restart recommended: Yes
```

**Optional - Remove US Language Pack**:
```powershell
.\Remove-USLanguagePack.ps1 -BackupFirst
```

**Action**: Restart server before continuing.

### Phase 2: System Health Baseline (20 minutes)

**Run integrity check**:

```powershell
# After restart
cd "C:\bug-free-umbrella\scripts\server"
.\Check-SystemIntegrity.ps1 -GenerateReport
```

**Expected Output**:
```
✓ System files: OK
✓ Component store: Healthy
✓ No issues detected

Report saved to: C:\Users\Administrator\Desktop\SystemIntegrity_[Server]_[Date].html
```

**Action Items**:
1. Review generated report
2. Archive baseline report for future reference
3. If issues found, address before proceeding

### Phase 3: Disk Health and Cleanup (15 minutes)

**Analyze disk usage**:

```powershell
.\Get-DiskReport.ps1 -ExportReport
```

**Expected Output**:
```
C:\ - 85.2 GB used (42.6%), 114.8 GB free
D:\ - 23.5 GB used (2.4%), 976.5 GB free

Cleanup suggestions:
- Windows Temp: 2.3 GB (safe to clear)
- Windows Update cache: 3.8 GB (safe to clear)

Report saved: DiskReport_[Date].html
```

**Perform initial cleanup**:

```powershell
.\Optimize-ServerStorage.ps1 -IncludeWindowsUpdate -Force
```

**Expected Savings**: 5-10 GB

### Phase 4: Windows Update Setup (15 minutes)

**Verify Windows Update is working**:

```powershell
# Check for updates manually first
Start-Service wuauserv
```

Open Windows Update in Settings and check for updates.

**If updates fail**, run reset:

```powershell
.\Reset-WindowsUpdate.ps1 -FullReset
```

**Install all pending updates before proceeding**.

### Phase 5: Security Baseline (Optional, 10 minutes)

**Check Active Directory health** (if domain controller):

```powershell
.\Get-ADHealthCheck.ps1 -ExportHTML
```

**Review firewall rules**:

```powershell
.\Get-FirewallRulesReport.ps1 -ExportHTML
```

**Check certificate expiration**:

```powershell
.\Test-CertificateExpiration.ps1 -CheckLocal -ExportHTML
```

### Phase 6: Document Configuration (5 minutes)

**Generate network configuration**:

```powershell
.\Get-NetworkConfiguration.ps1 -IncludeRouting -IncludeFirewall -ExportHTML
```

**Create server documentation folder**:

```powershell
New-Item -Path "C:\ServerDocumentation" -ItemType Directory
Move-Item "$env:USERPROFILE\Desktop\*Report*.html" -Destination "C:\ServerDocumentation\"
```

### Phase 7: Schedule Recurring Maintenance (5 minutes)

**Create scheduled task for monthly integrity checks**:

```powershell
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
    -Argument '-ExecutionPolicy Bypass -File "C:\bug-free-umbrella\scripts\server\Check-SystemIntegrity.ps1" -GenerateReport'

$trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 4 -DaysOfWeek Sunday -At 2am

Register-ScheduledTask -Action $action -Trigger $trigger `
    -TaskName "Monthly System Integrity Check" `
    -Description "Automated system health verification" `
    -RunLevel Highest -User "SYSTEM"
```

**Verify task created**:
```powershell
Get-ScheduledTask -TaskName "Monthly System Integrity Check"
```

---

## Intune Device Cleanup Workflow

**Goal**: Clean up stale devices and improve Intune hygiene.

**Time Required**: 60-90 minutes (includes review time)

**Prerequisites**:
- DeviceManagementManagedDevices.ReadWrite.All permissions
- Stakeholder approval for device retirement

### Week 1: Identification Phase

#### Day 1: Generate Stale Device Report

```powershell
cd "C:\bug-free-umbrella\scripts\intune"

# Find devices inactive 90+ days
.\Find-StaleDevices.ps1 -DaysInactive 90 -Action Report
```

**Expected Output**:
```
Found 23 devices inactive for 90+ days

Reports saved:
- StaleDevices_90days_[DATE].html
- StaleDevices_90days_[DATE].csv
```

**Actions**:
1. Open HTML report
2. Export device list
3. Cross-reference with:
   - Employee termination list
   - Device return records
   - Department managers

#### Day 2-3: Stakeholder Review

**Email template for review**:

```
Subject: Stale Device Cleanup - Review Required

Hi [Department Manager],

I've identified the following devices from your department that haven't
synced with Intune in over 90 days:

[Paste relevant device list]

Please review and respond with one of the following for each device:
- KEEP: Device is still in use (provide justification)
- RETIRE: User has left, device can be unenrolled
- UNKNOWN: Need to investigate further

Response needed by: [DATE]

Thanks,
IT Department
```

#### Day 4-5: Consolidate Feedback

Create approval list:

```
Devices Approved for Retirement:
- LAPTOP-ABC123 (User left company)
- DESKTOP-XYZ789 (Device replaced)
- SURFACE-DEF456 (Lost/stolen)
[...]

Devices to Keep:
- LAPTOP-KEEP001 (Remote worker, infrequent sync)
- TABLET-KEEP002 (Spare device for department)
[...]
```

### Week 2: Cleanup Phase

#### Day 1: Test Retirement (Pilot)

**Retire 1-2 test devices first**:

```powershell
# Test with manual device IDs
$testDevices = @("device-id-1", "device-id-2")

foreach ($deviceId in $testDevices) {
    Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$deviceId/retire"
}
```

**Verify**:
1. Check device status in Intune (should show "Retire pending")
2. Wait 24 hours
3. Confirm device is removed

#### Day 2: Bulk Retirement

**After successful test**:

```powershell
# Retire devices inactive 180+ days
.\Find-StaleDevices.ps1 -DaysInactive 180 -Action Retire
```

**Expected Interaction**:
```
Found 8 devices inactive for 180+ days

⚠ WARNING: RETIRE ACTION REQUESTED ⚠

Devices to be retired:
  1. LAPTOP-OLD001 (191 days inactive)
  2. DESKTOP-OLD002 (196 days inactive)
  [...]

To confirm, type 'YES': YES

Retiring devices:
  ✓ LAPTOP-OLD001... Successfully retired
  ✓ DESKTOP-OLD002... Successfully retired
  [...]

Successfully retired: 8 devices
```

**Monitor**:
- Check Intune console
- Verify devices show "Retire pending"
- Wait for removal (24-48 hours)

#### Day 3: Delete Old Records (Optional)

**For devices retired >30 days ago**:

```powershell
.\Find-StaleDevices.ps1 -DaysInactive 365 -Action Delete
```

⚠ **WARNING**: This permanently deletes device records. Use with extreme caution.

### Week 3: Verification Phase

#### Verify Cleanup Success

```powershell
# Re-run stale device finder
.\Find-StaleDevices.ps1 -DaysInactive 90
```

**Expected Result**:
```
Found 5 devices inactive for 90+ days
(Down from 23 - 18 devices removed)
```

#### Generate Post-Cleanup Report

**Create summary**:

```
Intune Device Cleanup - [Month Year]
====================================

Initial State:
- Total devices: 847
- Stale (90+ days): 23 (2.72%)

Actions Taken:
- Devices retired: 18
- Devices kept (approved): 5
- Devices deleted: 0

Current State:
- Total devices: 829 (-18)
- Stale (90+ days): 5 (0.60%)

Results:
✓ Reduced stale device count by 78%
✓ Improved tenant hygiene
✓ Removed 18 unused licenses

Next Cleanup: [3 months from now]
```

---

## Troubleshooting Failed Windows Updates

**Goal**: Fix Windows Update failures on Windows Server.

**Time Required**: 15-30 minutes per server

**Prerequisites**:
- Administrator access to affected server
- Ability to restart server (if needed)

### Step 1: Identify the Problem (5 minutes)

**Check Windows Update status**:

```powershell
# Open Windows Update
control update

# Or via PowerShell
Get-WindowsUpdateLog
```

**Common Error Codes**:
- `0x80070002`: Files not found
- `0x8024402F`: Connection issue
- `0x80244007`: Server not available
- `0x80070643`: Installation failure

**Check Update History**:
1. Open Windows Update
2. Click "View update history"
3. Note which updates are failing
4. Note error codes

### Step 2: Run Windows Update Reset (10 minutes)

```powershell
cd "C:\bug-free-umbrella\scripts\server"
.\Reset-WindowsUpdate.ps1
```

**Expected Output**:
```
[INFO] Starting Windows Update Reset Process
[SUCCESS] Stopped all services
[SUCCESS] Cleared cache
[INFO] Registered 35 DLLs
[SUCCESS] Restarted services
[SUCCESS] Windows Update reset completed!
```

**Immediately after**:
1. Open Windows Update
2. Click "Check for updates"
3. Observe if updates begin downloading

### Step 3: Verify System Integrity (If Reset Didn't Work)

**Corrupted files can prevent updates**:

```powershell
.\Check-SystemIntegrity.ps1 -AutoRepair
```

**Expected Duration**: 20-30 minutes

**If corruption found and repaired**:
1. Restart server
2. Try Windows Update again

### Step 4: Advanced Troubleshooting (If Still Failing)

**Check Windows Update service configuration**:

```powershell
# Verify services are set to automatic
Get-Service wuauserv, bits, cryptsvc | Format-Table Name, StartType, Status
```

**Should show**:
```
Name      StartType Status
----      --------- ------
wuauserv  Automatic Running
bits      Automatic Running
cryptsvc  Automatic Running
```

**If not running, start them**:
```powershell
Set-Service wuauserv -StartupType Automatic
Start-Service wuauserv
Set-Service bits -StartupType Automatic
Start-Service bits
Set-Service cryptsvc -StartupType Automatic
Start-Service cryptsvc
```

**Run full reset**:
```powershell
.\Reset-WindowsUpdate.ps1 -FullReset
```

### Step 5: Manual Update Installation (Last Resort)

**If automatic updates still fail**:

1. Go to [Microsoft Update Catalog](https://www.catalog.update.microsoft.com)
2. Search for the failing update KB number
3. Download manually
4. Install with:
   ```powershell
   # For .msu files
   wusa.exe KB5034441.msu /quiet /norestart

   # For .cab files
   dism /online /add-package /packagepath:KB5034441.cab
   ```

### Step 6: Verify Success

**Check update status**:

```powershell
# View installed updates
Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 10
```

**Check Windows Update**:
1. Open Windows Update
2. Verify "You're up to date" message
3. Note last checked time

### Decision Tree

```
Updates failing?
├─ Yes → Run Reset-WindowsUpdate.ps1
│   ├─ Fixed? → Done ✓
│   └─ Still failing?
│       └─ Run Check-SystemIntegrity.ps1
│           ├─ Corruption found?
│           │   ├─ Yes → Repair → Restart → Retry updates
│           │   └─ No → Manual installation
│           └─ Fixed? → Done ✓
└─ No → Monitor for future issues
```

---

## BitLocker Deployment and Monitoring

**Goal**: Enable BitLocker across all Windows devices and ensure recovery keys are backed up.

**Time Required**: 2-3 hours (initial setup) + ongoing monitoring

**Prerequisites**:
- Intune enrollment for devices
- TPM 1.2 or higher on target devices
- Azure AD joined or Hybrid Azure AD joined devices

### Phase 1: Planning (30 minutes)

#### Assess Current State

```powershell
cd "C:\bug-free-umbrella\scripts\intune"
.\Get-BitLockerStatus.ps1
```

**Analyze results**:
```
Current encryption status:
- Fully Encrypted: 695/750 (92.67%)
- Not Encrypted: 35/750 (4.67%)
- Partially Encrypted: 15/750 (2.00%)

Recovery key issues:
- Keys not backed up: 15 devices
```

**Create deployment plan**:
1. Group 1 (Week 1): IT Department - 50 devices
2. Group 2 (Week 2): Finance - 50 devices
3. Group 3 (Week 3): Sales - 100 devices
4. Group 4 (Week 4): All Others - 550 devices

#### Create Device Groups in Azure AD

```powershell
# Connect to Graph
Connect-MgGraph -Scopes "Group.ReadWrite.All"

# Create groups for phased rollout
New-MgGroup -DisplayName "BitLocker-Phase1-IT" `
    -MailEnabled:$false -MailNickname "bitlocker-phase1" `
    -SecurityEnabled:$true

# Repeat for Phase 2, 3, 4...
```

### Phase 2: Policy Creation (30 minutes)

#### Create BitLocker Policy in Intune

1. Sign in to https://intune.microsoft.com
2. Navigate to: **Endpoint Security → Disk encryption**
3. Click **+ Create Policy**
4. Platform: **Windows 10 and later**
5. Profile: **BitLocker**

**Recommended Settings**:

```
BitLocker - OS Drive Settings:
✓ Require startup authentication: Yes
✓ Compatible TPM startup: Allowed
✓ Compatible TPM startup PIN: Not allowed
✓ Compatible TPM startup key: Not allowed
✓ Encryption method: XTS-AES 256-bit

BitLocker - Fixed Drive Settings:
✓ Encryption method: XTS-AES 256-bit
✓ Auto-unlock fixed drive: Yes

BitLocker - Recovery:
✓ Recovery key file creation: Required
✓ Rotation of recovery passwords: Enabled every 180 days
✓ Hide recovery options: No
✓ Recovery key to Azure AD: Required
```

6. **Assignments**:
   - Assign to: `BitLocker-Phase1-IT`
7. Save and deploy

### Phase 3: Recovery Key Backup Remediation (15 minutes)

**Deploy backup script for devices with missing keys**:

```powershell
# Navigate to remediation scripts
cd "C:\bug-free-umbrella\scripts\device-management\bitlocker-backup"
```

**Upload to Intune**:
1. Devices → Scripts and remediations → Proactive remediations
2. Create new package: "BitLocker - Backup Recovery Keys"
3. Upload detect.ps1 and remediate.ps1
4. Schedule: Daily at 12:00 PM
5. Assign to: All Windows Devices

### Phase 4: Monitor Phase 1 Deployment (Week 1)

#### Day 1: Initial Check

```powershell
# 24 hours after policy deployment
.\Get-BitLockerStatus.ps1
```

**Expected Progress**:
```
BitLocker-Phase1-IT devices (50 total):
- Fully Encrypted: 12 (24%)
- Encryption in Progress: 35 (70%)
- Not Started: 3 (6%)
```

**Investigate "Not Started" devices**:
- Check TPM status
- Verify device compliance
- Check Intune sync status

#### Day 3: Mid-Week Check

**Expected Progress**:
```
BitLocker-Phase1-IT devices:
- Fully Encrypted: 45 (90%)
- Encryption in Progress: 3 (6%)
- Issues: 2 (4%)
```

**Address issues**:
```powershell
# For devices with issues, check compliance
.\Get-DeviceComplianceReport.ps1
```

#### Day 7: Phase 1 Complete

**Final verification**:
```powershell
.\Get-BitLockerStatus.ps1
```

**Expected Result**:
```
BitLocker-Phase1-IT devices:
- Fully Encrypted: 50 (100%)
- Recovery Keys Backed Up: 50 (100%)
✓ Phase 1 deployment successful!
```

**Before proceeding to Phase 2**:
1. Review any issues from Phase 1
2. Adjust policy if needed
3. Communicate lessons learned

### Phase 5: Phased Rollout (Weeks 2-4)

**Repeat for each phase**:

Week 2:
```powershell
# Assign policy to BitLocker-Phase2-Finance
# Monitor daily
# Verify completion
```

Week 3:
```powershell
# Assign policy to BitLocker-Phase3-Sales
# Monitor daily
# Verify completion
```

Week 4:
```powershell
# Assign policy to BitLocker-Phase4-AllOthers
# Monitor daily
# Verify completion
```

### Phase 6: Ongoing Monitoring (Monthly)

**Create monthly check scheduled task**:

```powershell
# PowerShell script to run monthly
$script = @'
cd "C:\bug-free-umbrella\scripts\intune"
.\Get-BitLockerStatus.ps1

# Email results
$report = Get-ChildItem "$env:USERPROFILE\Desktop\BitLockerStatus_*.html" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

Send-MailMessage -To "it-team@company.com" `
    -From "intune-reports@company.com" `
    -Subject "Monthly BitLocker Status Report" `
    -Body "See attached report" `
    -Attachments $report.FullName `
    -SmtpServer "smtp.company.com"
'@

# Save script
$script | Out-File "C:\Scripts\Monthly-BitLocker-Check.ps1"

# Create scheduled task
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
    -Argument '-ExecutionPolicy Bypass -File "C:\Scripts\Monthly-BitLocker-Check.ps1"'

$trigger = New-ScheduledTaskTrigger -Monthly -At 9am -DaysOfWeek Monday

Register-ScheduledTask -Action $action -Trigger $trigger `
    -TaskName "Monthly BitLocker Audit" `
    -Description "Automated BitLocker compliance check" `
    -RunLevel Highest
```

**Monthly Review Checklist**:
```
☐ Run BitLocker status report
☐ Verify encryption on new devices
☐ Check recovery key backups
☐ Review devices with multiple keys
☐ Investigate any unencrypted devices
☐ Update compliance documentation
```

---

## Proactive Remediation Deployment

**Goal**: Deploy the complete proactive remediation library to automatically fix common issues.

**Time Required**: 2-3 hours

**Prerequisites**:
- Intune administrator access
- Test device group created
- Scripts downloaded locally

### Overview of Remediations to Deploy

From `scripts/device-management/proactive-remediations`:

1. Fix-DiskSpace - Cleans low disk space
2. Fix-TempFiles - Removes old temp files
3. Fix-StaleProfiles - Removes old user profiles
4. Fix-WindowsUpdateStuck - Resets stuck Windows Update
5. Fix-BitLockerNotEscrowedKeys - Backs up BitLocker keys
6. Check-SecurityBaseline - Enforces security settings

### Deployment Strategy

**Phase 1 (Week 1)**: Test with IT devices (5-10 devices)
**Phase 2 (Week 2)**: Expand to pilot group (50 devices)
**Phase 3 (Week 3)**: Deploy to all devices (full rollout)

### Step-by-Step Deployment

#### Remediation 1: Fix-DiskSpace

**Step 1: Prepare Scripts**

```powershell
cd "C:\bug-free-umbrella\scripts\device-management\proactive-remediations\Fix-DiskSpace"

# Verify scripts exist
dir detect.ps1, remediate.ps1
```

**Step 2: Create in Intune**

1. Go to https://intune.microsoft.com
2. **Devices → Scripts and remediations → Proactive remediations**
3. Click **+ Create script package**

**Basics**:
- Name: `PR01 - Fix Disk Space`
- Description: `Automatically cleans disk space when below 10% or 10GB free`
- Publisher: `IT Department`

**Settings**:
- Detection script: Upload `detect.ps1`
- Remediation script: Upload `remediate.ps1`
- Run this script using logged-on credentials: **No** (run as SYSTEM)
- Enforce script signature check: **No**
- Run script in 64-bit PowerShell: **Yes**

**Assignments**:
- Add group: `IT-TestDevices`
- Schedule: **Daily at 3:00 AM**
- Restart behavior: **No restart**

**Review + Create**: Click Create

**Step 3: Monitor Test Deployment (24-48 hours)**

After 48 hours, review results:

1. Go to the remediation package
2. Click **Device status** tab

**Expected Results**:
```
Status               Count
------               -----
Without issues       3 (no action needed)
With issues - before remediation  2 (low disk space detected)
With issues - remediated          2 (cleaned successfully)
Failed                           0
```

**Review output messages**:
- Click on a remediated device
- View detection and remediation output
- Verify disk space was freed

**Sample output**:
```
Detection: Low disk space detected on C:\ drive (8.5% free)
Remediation: Total space freed: 9.7 GB. C:\ now has 24.9 GB free (14.0%)
```

**Step 4: Expand to Pilot (if test successful)**

1. Edit the assignment
2. Remove `IT-TestDevices`
3. Add `All-Windows-Devices` (or pilot group)
4. Save

#### Remediation 2: Fix-TempFiles

**Repeat same process**:

**Name**: `PR02 - Fix Temp Files`
**Schedule**: **Daily at 3:30 AM**

**Expected behavior**:
- Detects: >1GB of temp files older than 7 days
- Remediates: Deletes old temp files
- Typical savings: 1-5 GB per device

#### Remediation 3: Fix-StaleProfiles

⚠ **CAUTION**: Test thoroughly before wide deployment

**Name**: `PR03 - Fix Stale Profiles`
**Schedule**: **Weekly on Sunday at 2:00 AM**

**Assignments**: Start with test group only

**Review carefully**:
1. Monitor first week
2. Verify no active profiles were removed
3. Check no user data loss
4. Expand slowly (don't rush this one!)

**Expected behavior**:
- Detects: Profiles not accessed in 90+ days
- Remediates: Removes profiles not accessed in 120+ days
- Excludes: System profiles (Public, Default, etc.)

#### Remediation 4: Fix-WindowsUpdateStuck

**Name**: `PR04 - Fix Windows Update`
**Schedule**: **Every 4 hours** (more frequent)

**Why frequent?**: Detects and fixes stuck updates quickly

**Expected behavior**:
- Detects: Windows Update service issues
- Remediates: Resets Windows Update components
- Impact: Minimal, safe operation

#### Remediation 5: Fix-BitLockerNotEscrowedKeys

**Name**: `PR05 - BitLocker Key Backup`
**Schedule**: **Daily at 12:00 PM**

**Prerequisites**: Devices must be Azure AD joined

**Expected behavior**:
- Detects: BitLocker keys not backed up to Azure AD
- Remediates: Backs up recovery keys
- Critical: Prevents data loss scenarios

#### Remediation 6: Check-SecurityBaseline

**Name**: `PR06 - Security Baseline`
**Schedule**: **Every 4 hours**

**Expected behavior**:
- Detects: Disabled firewall, antivirus, UAC, etc.
- Remediates: Enables security features
- Impact: May re-enable settings users disabled

**Warning**: May conflict with intentionally disabled features

### Complete Deployment Timeline

**Week 1: Test Phase**
```
Monday:    Deploy all 6 remediations to IT-TestDevices
Tuesday:   Monitor first results
Wednesday: Review detection rates
Thursday:  Verify remediation success
Friday:    Adjust thresholds if needed
Weekend:   Monitor weekend runs
```

**Week 2: Pilot Phase**
```
Monday:    Expand to pilot group (50-100 devices)
Daily:     Monitor results
Friday:    Review week's data
```

**Week 3: Production Phase**
```
Monday:    Deploy to all devices
Ongoing:   Monitor and adjust
```

### Monitoring Dashboard

**Create monitoring routine**:

**Daily Check (5 minutes)**:
1. Review remediation overview dashboard
2. Check failure count (investigate if >5%)
3. Review any new error messages

**Weekly Review (30 minutes)**:
1. Generate summary report
2. Review trends:
   - Detection rates
   - Remediation success rates
   - Average space freed
   - Common issues
3. Adjust thresholds if needed

**Monthly Review (1 hour)**:
1. Comprehensive analysis
2. Cost/benefit review:
   - Disk space saved
   - Issues prevented
   - Support tickets reduced
3. Plan improvements

### Sample Monthly Report

```
Proactive Remediation Summary - December 2025
==============================================

Overall Statistics:
- Devices monitored: 750
- Total runs: 22,500 (across all remediations)
- Issues detected: 1,847
- Issues remediated: 1,793 (97.1% success rate)
- Failed remediations: 54 (2.9%)

By Remediation:

PR01 - Fix Disk Space
- Detections: 234
- Successful: 228 (97.4%)
- Total space freed: 2.1 TB
- Average per device: 9.2 GB

PR02 - Fix Temp Files
- Detections: 692
- Successful: 685 (99.0%)
- Total space freed: 3.8 TB
- Average per device: 5.5 GB

PR03 - Fix Stale Profiles
- Detections: 12
- Successful: 12 (100%)
- Total space freed: 145 GB
- Profiles removed: 18

PR04 - Fix Windows Update
- Detections: 45
- Successful: 42 (93.3%)
- Updates fixed: 42 devices
- Support tickets prevented: ~15

PR05 - BitLocker Key Backup
- Detections: 23
- Successful: 23 (100%)
- Keys backed up: 23
- Data loss risk mitigated: High

PR06 - Security Baseline
- Detections: 841
- Successful: 803 (95.5%)
- Security features enabled: 1,247
- Most common: Firewall re-enabled (523)

Impact Assessment:
✓ Total disk space freed: 6.0 TB
✓ Estimated cost savings: $X,XXX (reduced support time)
✓ Security improvements: 23 devices now have key backups
✓ Update compliance: 42 devices unblocked

Recommendations:
1. Adjust Fix-WindowsUpdateStuck schedule to every 2 hours
2. Review failed disk space cleanups (investigate 6 persistent failures)
3. Consider stricter thresholds for temp file cleanup
4. Deploy additional remediation for outdated software
```

---

## Summary

These workflows demonstrate end-to-end processes for:
- ✓ Regular compliance auditing
- ✓ Automated application updates
- ✓ Server provisioning
- ✓ Device lifecycle management
- ✓ Issue remediation
- ✓ Security enforcement

**Next Steps**:
1. Choose a workflow relevant to your current needs
2. Follow step-by-step instructions
3. Document your specific customizations
4. Share feedback for workflow improvements

**Additional Resources**:
- [Script Examples](SCRIPT-EXAMPLES.md) - Detailed script outputs
- [Troubleshooting Guide](TROUBLESHOOTING.md) - Common issues
- [Main Documentation](README.md) - Complete reference

---

**Version**: 1.0
