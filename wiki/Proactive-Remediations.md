# Proactive Remediations

Automated detect-and-remediate script pairs for Microsoft Intune that identify and fix common endpoint issues before users report them. These scripts help maintain healthy, compliant devices with minimal IT intervention.

## Overview

Proactive Remediations (formerly Analytics Remediations) are pairs of PowerShell scripts that:
- **Detect** - Identify issues on managed devices
- **Remediate** - Automatically fix detected problems

Benefits:
- **Reduce help desk tickets** - Fix problems before users notice
- **Improve device health** - Maintain optimal performance and compliance
- **Automate maintenance** - Run on schedules without manual intervention
- **Provide visibility** - Track issues across your device fleet

All scripts are located in: `/scripts/endpoints/devices/proactive-remediations/`

---

## Available Remediations

### System Performance

| Remediation | Issue Detected | Remediation Action | Location |
|-------------|----------------|-------------------|----------|
| **Fix-DiskSpace** | Low disk space (<10% or <10GB free) | Cleanup temporary files, Windows Update cache, recycle bin | `proactive-remediations/Fix-DiskSpace/` |
| **Fix-TempFiles** | Excessive temporary files | Remove old temp files, browser cache, system temp | `proactive-remediations/Fix-TempFiles/` |
| **Fix-StaleProfiles** | Inactive user profiles (90+ days) | Remove stale local user profiles | `proactive-remediations/Fix-StaleProfiles/` |

### Application Issues

| Remediation | Issue Detected | Remediation Action | Location |
|-------------|----------------|-------------------|----------|
| **Fix-TeamsCache** | Microsoft Teams cache issues | Clear Teams cache, reset configuration | `proactive-remediations/Fix-TeamsCache/` |
| **Fix-BrokenShortcuts** | Broken desktop shortcuts | Remove invalid shortcuts | `proactive-remediations/Fix-BrokenShortcuts/` |
| **Fix-WindowsSearch** | Windows Search indexer not running | Restart Windows Search service, rebuild index | `proactive-remediations/Fix-WindowsSearch/` |

### System Services

| Remediation | Issue Detected | Remediation Action | Location |
|-------------|----------------|-------------------|----------|
| **Fix-PrintSpooler** | Print Spooler service stopped or stuck | Restart Print Spooler, clear print queue | `proactive-remediations/Fix-PrintSpooler/` |
| **Fix-DNSCache** | DNS cache corruption or issues | Flush DNS cache, re-register DNS | `proactive-remediations/Fix-DNSCache/` |
| **Fix-WindowsUpdateStuck** | Windows Update stuck or failing | Reset Windows Update components | `proactive-remediations/Fix-WindowsUpdateStuck/` |

### Security & Compliance

| Remediation | Issue Detected | Remediation Action | Location |
|-------------|----------------|-------------------|----------|
| **Check-SecurityBaseline** | Security settings not meeting baseline | Apply security baseline configurations | `proactive-remediations/Check-SecurityBaseline/` |
| **Fix-BitLockerNotEscrowedKeys** | BitLocker recovery key not escrowed to Azure AD | Force BitLocker key backup to Azure AD | `proactive-remediations/Fix-BitLockerNotEscrowedKeys/` |

### Regional Settings

| Remediation | Issue Detected | Remediation Action | Location |
|-------------|----------------|-------------------|----------|
| **region-language-settings** | Incorrect regional/language settings | Set correct region, language, and time zone | `proactive-remediations/region-language-settings/` |
| **keyboard-layout** | Wrong keyboard layout | Configure correct keyboard layout | `proactive-remediations/keyboard-layout/` |
| **language-pack-audit** | Missing or incorrect language packs | Install required language packs | `proactive-remediations/language-pack-audit/` |

---

## Prerequisites

### Intune Requirements
- **Microsoft Intune subscription** (part of Microsoft 365 E3/E5 or EMS E3/E5)
- **Endpoint Manager access** via Azure portal
- **Intune Administrator** or **Endpoint Security Administrator** role
- **Windows 10/11 devices** enrolled in Intune

### Script Execution
- Scripts run as **SYSTEM** account (highest privileges)
- Execution policy is bypassed automatically by Intune
- Scripts must complete within **60 minutes** (Microsoft limitation)
- Detection script runs first; remediation only runs if detection returns exit code 1

### Exit Codes
All detection scripts use standardized exit codes:
```powershell
# Detection script exit codes
Exit 0  # Compliant - No issue detected, remediation not needed
Exit 1  # Non-compliant - Issue detected, run remediation script

# Remediation script exit codes
Exit 0  # Success - Issue resolved
Exit 1  # Failure - Could not resolve issue
```

---

## How Proactive Remediations Work

### Execution Flow
```
1. Schedule triggers (e.g., daily at 3:00 AM)
   ↓
2. Detect.ps1 runs on device
   ↓
3. If Exit 0 → No issue, stop
   If Exit 1 → Issue found, continue
   ↓
4. Remediate.ps1 runs on device
   ↓
5. Results reported to Intune
   ↓
6. Admin reviews in Endpoint Manager
```

### Detection Script Structure
```powershell
<#
.SYNOPSIS
    Detect [issue description]

.DESCRIPTION
    Checks for [specific condition]
    Reports non-compliant if [criteria]

.NOTES
    Exit 0 = Compliant (no issue)
    Exit 1 = Non-compliant (issue detected)
#>

[CmdletBinding()]
param()

# Configuration
$THRESHOLD = 10

# Check for issue
$IssueExists = Test-Condition

if ($IssueExists) {
    Write-Host "Issue detected: [description]"
    exit 1  # Non-compliant
}

Write-Host "No issue found"
exit 0  # Compliant
```

### Remediation Script Structure
```powershell
<#
.SYNOPSIS
    Remediate [issue description]

.DESCRIPTION
    Fixes [specific issue] by [action taken]

.NOTES
    Exit 0 = Success
    Exit 1 = Failure
#>

[CmdletBinding()]
param()

try {
    # Perform remediation
    Invoke-Fix

    Write-Host "Remediation successful"
    exit 0  # Success
}
catch {
    Write-Host "Remediation failed: $_"
    exit 1  # Failure
}
```

---

## Common Use Cases

### 1. Fix Low Disk Space

Automatically clean up disk space when drives are running low.

**Detection Script (`detect.ps1`):**
```powershell
<#
.SYNOPSIS
    Detect low disk space on fixed drives

.DESCRIPTION
    Checks all fixed disk volumes for low disk space conditions.
    Reports non-compliant if any volume has less than 10% or 10 GB free.

.NOTES
    Exit 0 = Compliant (sufficient disk space)
    Exit 1 = Non-compliant (low disk space detected)
#>

[CmdletBinding()]
param()

$DISK_SPACE_WARNING_PERCENT = 10
$DISK_SPACE_WARNING_GB = 10

$volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
$issues = @()

foreach ($vol in $volumes) {
    $freePercent = ($vol.SizeRemaining / $vol.Size) * 100
    $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 2)

    if ($freePercent -lt $DISK_SPACE_WARNING_PERCENT -or $freeGB -lt $DISK_SPACE_WARNING_GB) {
        $issues += "$($vol.DriveLetter): $freeGB GB free ($([math]::Round($freePercent, 1))%)"
    }
}

if ($issues.Count -gt 0) {
    Write-Host "Low disk space detected: $($issues -join ', ')"
    exit 1
}

Write-Host "Disk space healthy"
exit 0
```

**Remediation Script (`remediate.ps1`):**
```powershell
<#
.SYNOPSIS
    Free up disk space by cleaning temporary files

.DESCRIPTION
    Cleans:
    - Windows Update cache
    - Temporary files
    - Recycle Bin
    - Browser caches
    - Windows Error Reports

.NOTES
    Exit 0 = Success
    Exit 1 = Failure
#>

[CmdletBinding()]
param()

try {
    $SpaceFreed = 0

    # Clean Windows Update cache
    Write-Host "Cleaning Windows Update cache..."
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    $UpdateCacheSize = (Get-ChildItem C:\Windows\SoftwareDistribution\Download -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Remove-Item C:\Windows\SoftwareDistribution\Download\* -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service -Name wuauserv
    $SpaceFreed += $UpdateCacheSize

    # Clean temp folders
    Write-Host "Cleaning temp folders..."
    $TempSize = (Get-ChildItem $env:TEMP -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    $SpaceFreed += $TempSize

    # Empty Recycle Bin
    Write-Host "Emptying Recycle Bin..."
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue

    # Clean Windows Error Reports
    Write-Host "Cleaning Windows Error Reports..."
    Remove-Item "C:\ProgramData\Microsoft\Windows\WER\*" -Recurse -Force -ErrorAction SilentlyContinue

    $SpaceFreedGB = [math]::Round($SpaceFreed / 1GB, 2)
    Write-Host "Remediation successful. Freed approximately $SpaceFreedGB GB"
    exit 0
}
catch {
    Write-Host "Remediation failed: $_"
    exit 1
}
```

**Deployment in Intune:**
1. Navigate to **Endpoint Manager** > **Reports** > **Endpoint Analytics** > **Proactive remediations**
2. Click **Create script package**
3. Configure:
   - **Name:** Fix Low Disk Space
   - **Detection script:** Upload `detect.ps1`
   - **Remediation script:** Upload `remediate.ps1`
   - **Run in 64-bit PowerShell:** Yes
   - **Run script in logged-on credentials:** No (run as SYSTEM)
4. Assign to device groups
5. Set schedule: Daily at 3:00 AM

### 2. Fix Microsoft Teams Cache Issues

Clear Teams cache when users experience performance problems.

**Common Teams Issues Fixed:**
- Teams not loading or crashing
- Missing messages or channels
- Slow performance
- Sign-in issues
- Notification problems

**Detection Script:**
```powershell
# Checks for:
# - Teams cache size >1 GB
# - Teams crash logs
# - Teams startup failures
```

**Remediation Script:**
```powershell
# Actions:
# 1. Close Teams process
# 2. Clear cache folders:
#    - %AppData%\Microsoft\Teams\Cache
#    - %AppData%\Microsoft\Teams\blob_storage
#    - %AppData%\Microsoft\Teams\databases
#    - %AppData%\Microsoft\Teams\GPUcache
#    - %AppData%\Microsoft\Teams\IndexedDB
#    - %AppData%\Microsoft\Teams\Local Storage
# 3. Restart Teams
```

### 3. Fix Windows Update Stuck

Reset Windows Update components when updates fail repeatedly.

**Detection Criteria:**
- Windows Update service stuck or not running
- Update error codes in Event Log (last 48 hours)
- Pending updates failing for 7+ days
- BITS service issues

**Remediation Actions:**
```powershell
# 1. Stop Windows Update services
Stop-Service -Name wuauserv, bits, cryptsvc -Force

# 2. Rename SoftwareDistribution folder
Rename-Item C:\Windows\SoftwareDistribution C:\Windows\SoftwareDistribution.old

# 3. Clear BITS queue
Remove-Item C:\Windows\System32\catroot2 -Recurse -Force

# 4. Re-register DLLs
regsvr32 /s wuaueng.dll
regsvr32 /s wuapi.dll

# 5. Restart services
Start-Service -Name wuauserv, bits, cryptsvc

# 6. Trigger update check
wuauclt /resetauthorization /detectnow
```

### 4. Fix BitLocker Key Escrow

Ensure BitLocker recovery keys are backed up to Azure AD.

**Detection:**
```powershell
# Check if:
# 1. BitLocker is enabled
# 2. Recovery key exists in Azure AD
# 3. Key is current (not stale)

$BitLockerVolume = Get-BitLockerVolume -MountPoint C:
if ($BitLockerVolume.ProtectionStatus -eq 'On') {
    $KeyProtector = $BitLockerVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }

    if (-not $KeyProtector) {
        Write-Host "BitLocker enabled but no recovery password found"
        exit 1
    }

    # Check if key is escrowed to Azure AD
    $KeyBackedUp = # Check Azure AD backup status
    if (-not $KeyBackedUp) {
        Write-Host "Recovery key not escrowed to Azure AD"
        exit 1
    }
}

Write-Host "BitLocker key properly escrowed"
exit 0
```

**Remediation:**
```powershell
# Force BitLocker key backup to Azure AD
$BitLockerVolume = Get-BitLockerVolume -MountPoint C:
$KeyProtector = $BitLockerVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }

foreach ($Key in $KeyProtector) {
    BackupToAAD-BitLockerKeyProtector -MountPoint C: -KeyProtectorId $Key.KeyProtectorId
}

Write-Host "BitLocker recovery key escrowed to Azure AD"
exit 0
```

### 5. Fix Print Spooler Issues

Restart stuck Print Spooler and clear print queue.

**Detection:**
```powershell
# Check for:
# - Print Spooler service stopped
# - Stuck print jobs (older than 1 hour)
# - Spooler consuming >100 MB memory

$SpoolerService = Get-Service -Name Spooler
if ($SpoolerService.Status -ne 'Running') {
    Write-Host "Print Spooler service not running"
    exit 1
}

$StuckJobs = Get-Printer | Get-PrintJob | Where-Object { $_.JobStatus -eq 'Paused' -or $_.JobStatus -eq 'Error' }
if ($StuckJobs.Count -gt 0) {
    Write-Host "$($StuckJobs.Count) stuck print jobs detected"
    exit 1
}

Write-Host "Print Spooler healthy"
exit 0
```

**Remediation:**
```powershell
# 1. Stop Print Spooler
Stop-Service -Name Spooler -Force

# 2. Clear print queue
Remove-Item C:\Windows\System32\spool\PRINTERS\* -Force

# 3. Start Print Spooler
Start-Service -Name Spooler

# 4. Verify service started
$SpoolerService = Get-Service -Name Spooler
if ($SpoolerService.Status -eq 'Running') {
    Write-Host "Print Spooler restarted successfully"
    exit 0
} else {
    Write-Host "Failed to restart Print Spooler"
    exit 1
}
```

### 6. Fix Stale User Profiles

Remove inactive local user profiles to free disk space.

**Detection:**
```powershell
# Find user profiles not accessed in 90+ days
$StaleProfiles = Get-CimInstance -ClassName Win32_UserProfile |
    Where-Object { -not $_.Special -and $_.LastUseTime -lt (Get-Date).AddDays(-90) }

if ($StaleProfiles.Count -gt 0) {
    $TotalSize = ($StaleProfiles | ForEach-Object {
        (Get-ChildItem $_.LocalPath -Recurse -ErrorAction SilentlyContinue |
         Measure-Object -Property Length -Sum).Sum
    } | Measure-Object -Sum).Sum

    $TotalSizeGB = [math]::Round($TotalSize / 1GB, 2)
    Write-Host "$($StaleProfiles.Count) stale profiles found ($TotalSizeGB GB)"
    exit 1
}

Write-Host "No stale profiles found"
exit 0
```

**Remediation:**
```powershell
$StaleProfiles = Get-CimInstance -ClassName Win32_UserProfile |
    Where-Object { -not $_.Special -and $_.LastUseTime -lt (Get-Date).AddDays(-90) }

$RemovedCount = 0
foreach ($Profile in $StaleProfiles) {
    try {
        Remove-CimInstance -InputObject $Profile
        $RemovedCount++
    }
    catch {
        Write-Host "Failed to remove profile: $($Profile.LocalPath)"
    }
}

Write-Host "Removed $RemovedCount stale user profiles"
exit 0
```

---

## Deployment Guide

### Step 1: Prepare Scripts

1. **Review script pairs** in `/scripts/endpoints/devices/proactive-remediations/`
2. **Test locally** on representative devices
3. **Customize thresholds** if needed (e.g., disk space warnings)
4. **Verify exit codes** are correct

### Step 2: Create Script Package in Intune

1. Navigate to **[Endpoint Manager](https://endpoint.microsoft.com)**
2. Go to **Reports** > **Endpoint Analytics** > **Proactive remediations**
3. Click **+ Create script package**
4. Configure basic settings:
   - **Name:** Descriptive name (e.g., "Fix Low Disk Space")
   - **Description:** What the remediation does
   - **Publisher:** Your organization name

### Step 3: Upload Scripts

1. **Detection script:** Upload `detect.ps1`
2. **Remediation script:** Upload `remediate.ps1`
3. **Settings:**
   - ✅ Run this script using the logged-on credentials: **No** (run as SYSTEM)
   - ✅ Enforce script signature check: No (unless scripts are signed)
   - ✅ Run script in 64-bit PowerShell: **Yes** (recommended)

### Step 4: Configure Schedule

**Schedule options:**
- **Daily:** For critical issues (disk space, security)
- **Weekly:** For maintenance tasks (stale profiles, cache cleanup)
- **Custom:** Specific days/times

**Recommended schedules:**
- **Disk space:** Daily at 3:00 AM
- **Teams cache:** Weekly on Sunday at 2:00 AM
- **Windows Update:** Daily at 4:00 AM
- **Security baseline:** Daily at 5:00 AM
- **Stale profiles:** Monthly on 1st at 3:00 AM

### Step 5: Assign to Groups

1. **Select device groups** (not user groups)
2. **Start with pilot group** (10-20 devices)
3. **Monitor for 1 week**
4. **Expand to production** groups

### Step 6: Monitor Results

1. Navigate to **Proactive remediations** in Endpoint Manager
2. Click on script package
3. Review:
   - **Device status:** Compliant vs. Non-compliant
   - **Remediation success rate**
   - **Errors and failures**
4. Investigate failures and adjust scripts if needed

---

## Monitoring & Reporting

### View Remediation Status

```powershell
# In Endpoint Manager:
# Reports > Endpoint Analytics > Proactive remediations > [Select package]

# Status summary:
# - Total devices
# - Detected issues
# - Successfully remediated
# - Failed remediations
# - Last run time
```

### Key Metrics to Track

1. **Detection rate** - % of devices with issues
2. **Remediation success rate** - % of issues fixed
3. **Failure rate** - % of failed remediations
4. **Trends over time** - Are issues increasing/decreasing?

### Sample Report
```
=== Fix Low Disk Space - Status Report ===
Reporting Period: Last 30 days

Total Devices: 1,500
Issues Detected: 234 (15.6%)
Successfully Remediated: 221 (94.4%)
Failed: 13 (5.6%)

Average Disk Space Freed: 8.2 GB per device
Total Space Freed: 1.8 TB

Trend:
Week 1: 67 issues detected
Week 2: 54 issues detected (-19%)
Week 3: 58 issues detected
Week 4: 55 issues detected

Top Failure Reasons:
1. Insufficient permissions (5 devices)
2. Disk errors preventing cleanup (4 devices)
3. Windows Update service locked (4 devices)
```

---

## Best Practices

### Script Development
1. **Keep it simple** - Focus on single, well-defined issues
2. **Test thoroughly** - Test on multiple device configurations
3. **Use exit codes correctly** - Always use 0 (success) and 1 (failure/non-compliant)
4. **Add logging** - Use Write-Host for detailed output visible in Intune
5. **Handle errors gracefully** - Use try/catch blocks

### Deployment Strategy
1. **Pilot first** - Always test on pilot group before production
2. **Stagger rollout** - Deploy to 10%, then 50%, then 100% of devices
3. **Monitor closely** - Check results daily for first week
4. **Adjust thresholds** - Fine-tune detection criteria based on results
5. **Document changes** - Track script versions and modifications

### Scheduling
1. **Off-hours execution** - Run during low-usage times (2-5 AM)
2. **Avoid conflicts** - Don't schedule multiple remediations simultaneously
3. **Consider time zones** - Account for global device distribution
4. **Reboot awareness** - Some remediations may require reboots
5. **Frequency balance** - Don't over-remediate (weekly is often sufficient)

### Maintenance
1. **Review monthly** - Check success rates and failure patterns
2. **Update scripts** - Keep detection logic current with Windows updates
3. **Retire unused** - Remove remediations that are no longer needed
4. **Archive results** - Export reports quarterly for trend analysis
5. **User communication** - Inform users about automatic maintenance

---

## Troubleshooting

### Common Issues

**Remediation doesn't run:**
- Check detection script returns exit code 1 when issue exists
- Verify remediation script is uploaded correctly
- Ensure device is online and checking in to Intune
- Check schedule hasn't been paused

**Detection succeeds but remediation fails:**
```powershell
# Review remediation output in Intune device report
# Common causes:
# - Insufficient permissions (ensure running as SYSTEM)
# - File in use (add retry logic)
# - Timeout (script must complete in 60 minutes)
```

**False positives in detection:**
- Review detection logic and thresholds
- Test detection script manually on affected devices
- Adjust detection criteria to be more specific

**Script times out:**
- Optimize script performance
- Remove unnecessary loops or delays
- Break complex remediations into multiple script packages
- Consider reducing scope (e.g., clean one folder instead of many)

**Devices not reporting status:**
- Check device enrollment status in Intune
- Verify device is syncing (last sync time)
- Ensure device has network connectivity
- Review Event Viewer logs on device (Event ID 400-500 in Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider)

---

## Creating Custom Remediations

### Template Structure

Create two files in a new folder:

**Folder:** `/scripts/endpoints/devices/proactive-remediations/Fix-YourIssue/`

**File 1: `detect.ps1`**
```powershell
<#
.SYNOPSIS
    Detect [your issue description]

.DESCRIPTION
    Checks for [specific condition]
    Reports non-compliant if [criteria]

.NOTES
    Exit 0 = Compliant
    Exit 1 = Non-compliant
#>

[CmdletBinding()]
param()

# Configuration constants
$THRESHOLD = 10

try {
    # Your detection logic here
    $IssueDetected = $false

    # Example: Check disk space
    $FreeSpace = (Get-Volume -DriveLetter C).SizeRemaining / 1GB
    if ($FreeSpace -lt $THRESHOLD) {
        $IssueDetected = $true
    }

    # Report results
    if ($IssueDetected) {
        Write-Host "Issue detected: [description]"
        exit 1  # Non-compliant
    } else {
        Write-Host "No issue found"
        exit 0  # Compliant
    }
}
catch {
    Write-Host "Detection error: $_"
    exit 0  # Don't remediate on detection errors
}
```

**File 2: `remediate.ps1`**
```powershell
<#
.SYNOPSIS
    Remediate [your issue description]

.DESCRIPTION
    Fixes [specific issue] by [action]

.NOTES
    Exit 0 = Success
    Exit 1 = Failure
#>

[CmdletBinding()]
param()

try {
    # Your remediation logic here
    Write-Host "Starting remediation..."

    # Example: Clean disk space
    Remove-Item C:\Temp\* -Recurse -Force

    # Verify fix
    $Fixed = Test-Condition
    if ($Fixed) {
        Write-Host "Remediation successful"
        exit 0  # Success
    } else {
        Write-Host "Remediation did not resolve issue"
        exit 1  # Failure
    }
}
catch {
    Write-Host "Remediation failed: $_"
    exit 1  # Failure
}
```

### Testing Custom Remediations

```powershell
# Test detection script
.\detect.ps1
Write-Host "Exit code: $LASTEXITCODE"

# If exit code is 1, test remediation
if ($LASTEXITCODE -eq 1) {
    .\remediate.ps1
    Write-Host "Remediation exit code: $LASTEXITCODE"

    # Re-run detection to verify fix
    .\detect.ps1
    Write-Host "Post-remediation detection: $LASTEXITCODE"
}
```

---

## Related Resources

### Internal Documentation
- **[Prerequisites](Prerequisites)** - Required modules and permissions
- **[Intune Management](Intune-Management)** - Device management scripts
- **[Security & Compliance](Security-Compliance)** - Security auditing
- **[FAQ](FAQ)** - Common questions and answers

### External Resources
- **[Microsoft Endpoint Manager](https://endpoint.microsoft.com)** - Intune admin portal
- **[Proactive Remediations Documentation](https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations)** - Official Microsoft docs
- **[PowerShell Gallery](https://www.powershellgallery.com/)** - Community scripts
- **[Intune Community](https://techcommunity.microsoft.com/t5/microsoft-intune/bd-p/Microsoft-Intune)** - Microsoft Tech Community

---

**Last Updated:** 2025-12-31
**Version:** 1.0.0
