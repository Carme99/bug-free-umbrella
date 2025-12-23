# Winget Update Scripts - V3 Templates

## Overview

V3 templates are the next evolution of our winget update scripts, featuring enterprise-grade enhancements for production environments.

### What's New in V3

**Enhanced Detection (detect_v3.ps1)**
- ✅ Retry logic with exponential backoff
- ✅ Network connectivity validation
- ✅ Optional file or event log logging
- ✅ More detailed error messages and status reporting
- ✅ Configurable retry attempts and delays

**Enhanced Remediation Variants**
1. **remediate_v3_standard.ps1** - Standard with retry logic and hooks
2. **remediate_v3_force_close.ps1** - Force close with user notifications
3. **remediate_v3_maintenance_window.ps1** - Time-based update control

## Quick Start

### Minimal Configuration (Same as V2)

All V3 templates require **only the winget package ID** for basic functionality:

```powershell
# In detect_v3.ps1
$ID = 'Google.Chrome'

# In remediate_v3_*.ps1
$ID = 'Google.Chrome'
```

Everything else is auto-detected or uses sensible defaults!

### Enhanced Configuration Example

```powershell
# Enable advanced V3 features
$ID = 'Microsoft.Teams'
$EnableLogging = $true
$LogPath = "C:\ProgramData\IntuneScripts\Logs\Teams.log"
$MaxRetries = 5
$NotifyUserBeforeClose = $true
$UserNotificationSeconds = 120
```

---

## Template Comparison

| Feature | V1 | V2 | V3 |
|---------|----|----|-----|
| Config Required | 3 vars | 1 var | 1 var |
| Auto-detect Name | ❌ | ✅ | ✅ |
| Auto-detect Process | ❌ | ✅ | ✅ |
| Retry Logic | ❌ | ❌ | ✅ |
| Logging | ❌ | ❌ | ✅ |
| Network Check | ❌ | ❌ | ✅ |
| User Notifications | ❌ | ❌ | ✅ |
| Maintenance Windows | ❌ | ❌ | ✅ |
| Pre/Post Hooks | ❌ | ❌ | ✅ |

---

## V3 Templates Guide

### 1. detect_v3.ps1 - Enhanced Detection

**Purpose**: Detect available updates with retry logic and better error handling.

**Required Configuration**:
```powershell
$ID = 'WINGETID'  # Your winget package ID
```

**Optional Advanced Settings**:
```powershell
$MaxRetries = 3                    # Number of retry attempts
$RetryDelaySeconds = 2             # Initial delay (doubles each retry)
$EnableLogging = $false            # Enable file logging
$LogPath = "C:\ProgramData\..."    # Where to write logs
$CheckNetworkConnectivity = $true  # Validate internet before checking
```

**Features**:
- Automatically retries failed winget commands
- Validates network connectivity before attempting updates
- Logs detailed information for troubleshooting
- Exponential backoff prevents overwhelming the system

**Example Use Cases**:
- Unreliable network environments
- Troubleshooting update detection issues
- Compliance reporting requirements

---

### 2. remediate_v3_standard.ps1 - Enhanced Standard Update

**Purpose**: Update apps when they're not running, with retry logic and hooks.

**Required Configuration**:
```powershell
$ID = 'WINGETID'
```

**Optional Settings**:
```powershell
# Retry Configuration
$MaxRetries = 3
$RetryDelaySeconds = 2
$VerifyWaitSeconds = 5

# Logging
$EnableLogging = $false
$LogPath = "C:\ProgramData\IntuneScripts\Logs\..."

# Custom Actions (Hooks)
$PreUpdateScriptBlock = $null   # Run before update
$PostUpdateScriptBlock = $null  # Run after update
```

**Hook Examples**:
```powershell
# Stop a service before updating
$PreUpdateScriptBlock = {
    Stop-Service -Name "MyService" -ErrorAction SilentlyContinue
}

# Restart service after update
$PostUpdateScriptBlock = {
    Start-Service -Name "MyService" -ErrorAction SilentlyContinue
}
```

**Best For**:
- User-facing applications (Chrome, VS Code, VLC)
- Apps where data loss would be problematic
- Business hours updates

**Behavior**:
- ✅ If app is NOT running → Update immediately
- ⏭️ If app IS running → Skip and retry later (exit 1)

---

### 3. remediate_v3_force_close.ps1 - Force Close with Notifications

**Purpose**: Force close apps for updates, optionally notifying users first.

**Required Configuration**:
```powershell
$ID = 'WINGETID'
```

**Optional Settings**:
```powershell
# User Notification Settings
$NotifyUserBeforeClose = $false     # Show warning to users
$UserNotificationSeconds = 60       # How long to wait after notification

# Force Close Settings
$GracePeriodSeconds = 5             # Wait after closing
$VerifyWaitSeconds = 10             # Wait after update
$MaxProcessCloseAttempts = 3        # Retry closing process

# Advanced
$MaxRetries = 3
$EnableLogging = $false
$PreUpdateScriptBlock = $null
$PostUpdateScriptBlock = $null
```

**User Notification Feature**:

When `$NotifyUserBeforeClose = $true`, users see a Windows message:

```
Application Update Required

Microsoft Teams will be closed in 60 seconds for an
important update. Please save your work and finish any calls.
```

The notification uses `msg.exe` to reach all logged-in users, even when running as SYSTEM.

**Best For**:
- Background services (TeamViewer, system utilities)
- Maintenance window deployments
- Critical security updates that can't wait
- After-hours updates

**Behavior**:
1. Check if app is running
2. If running AND notifications enabled → Show notification → Wait → Close
3. If running AND no notifications → Close immediately
4. Install update
5. Verify installation

---

### 4. remediate_v3_maintenance_window.ps1 - Scheduled Updates

**Purpose**: Only update during specified days/times. Perfect for production systems.

**Required Configuration**:
```powershell
$ID = 'WINGETID'

# Define maintenance window
$MaintenanceWindowDays = @('Saturday', 'Sunday')
$MaintenanceWindowStartHour = 2    # 2 AM
$MaintenanceWindowEndHour = 6      # 6 AM
```

**Optional Settings**:
```powershell
$ForceCloseInMaintenanceWindow = $true  # Close app during window
$MaxRetries = 3
$GracePeriodSeconds = 5
$VerifyWaitSeconds = 10
$EnableLogging = $false
$PreUpdateScriptBlock = $null
$PostUpdateScriptBlock = $null
```

**How It Works**:
1. Check current day and hour
2. If OUTSIDE maintenance window → Exit without action (exit 0)
3. If INSIDE maintenance window → Proceed with update

**Example Configurations**:

**Weekends Only (2-6 AM)**:
```powershell
$MaintenanceWindowDays = @('Saturday', 'Sunday')
$MaintenanceWindowStartHour = 2
$MaintenanceWindowEndHour = 6
```

**Every Night (2-4 AM)**:
```powershell
$MaintenanceWindowDays = @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')
$MaintenanceWindowStartHour = 2
$MaintenanceWindowEndHour = 4
```

**Weekday Nights Only**:
```powershell
$MaintenanceWindowDays = @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday')
$MaintenanceWindowStartHour = 22  # 10 PM
$MaintenanceWindowEndHour = 6     # 6 AM (next day)
```

**Best For**:
- Critical production applications (SQL Server, databases)
- Development tools (PowerShell, Visual Studio)
- Apps with scheduled tasks/jobs
- Systems requiring guaranteed uptime during business hours

---

## Real-World Examples

### Example 1: 7-Zip (Simple Utility)

**Scenario**: Compression utility, safe to force close, minimal user impact

**Configuration**:
```powershell
# detect_v3.ps1
$ID = '7zip.7zip'

# remediate_v3_force_close.ps1
$ID = '7zip.7zip'
$AppProcess = '7zFM'
$NotifyUserBeforeClose = $false
$GracePeriodSeconds = 2
```

**Why these settings?**:
- No user notification needed (utility app)
- Force close is safe (no data loss risk)
- Quick grace period (lightweight app)

---

### Example 2: Microsoft Teams (Collaboration Tool)

**Scenario**: Active collaboration, potential calls in progress

**Configuration**:
```powershell
# detect_v3.ps1
$ID = 'Microsoft.Teams'
$EnableLogging = $true

# remediate_v3_force_close.ps1
$ID = 'Microsoft.Teams'
$AppProcess = 'ms-teams'
$NotifyUserBeforeClose = $true
$UserNotificationSeconds = 120  # 2 minutes warning
$GracePeriodSeconds = 5
```

**Why these settings?**:
- User notification critical (might be in a call)
- 2-minute warning gives time to wrap up
- Logging enabled for troubleshooting user complaints

---

### Example 3: SQL Server Management Studio (SSMS)

**Scenario**: Database tool with potential active connections

**Configuration**:
```powershell
# detect_v3.ps1
$ID = 'Microsoft.SQLServerManagementStudio'
$EnableLogging = $true

# remediate_v3_maintenance_window.ps1
$ID = 'Microsoft.SQLServerManagementStudio'
$MaintenanceWindowDays = @('Saturday', 'Sunday')
$MaintenanceWindowStartHour = 3
$MaintenanceWindowEndHour = 5
$ForceCloseInMaintenanceWindow = $true
$EnableLogging = $true
```

**Why these settings?**:
- Weekend maintenance window (no business impact)
- Early morning hours (3-5 AM)
- Force close during window (no one should be working)
- Logging for audit trail

---

### Example 4: VLC Media Player (Media Player)

**Scenario**: Personal media player, shouldn't interrupt playback

**Configuration**:
```powershell
# detect_v3.ps1
$ID = 'VideoLAN.VLC'

# remediate_v3_standard.ps1
$ID = 'VideoLAN.VLC'
$AppProcess = 'vlc'
$MaxRetries = 3
```

**Why these settings?**:
- Standard remediation (wait for user to close)
- Don't interrupt movie watching
- Retry logic ensures eventual update

---

### Example 5: Git (Developer Tool with Hooks)

**Scenario**: Developer tool with potential running operations

**Configuration**:
```powershell
# detect_v3.ps1
$ID = 'Git.Git'

# remediate_v3_force_close.ps1
$ID = 'Git.Git'
$AppProcess = 'git'
$GracePeriodSeconds = 2

# Pre-update hook: Clear Git credential cache
$PreUpdateScriptBlock = {
    & git credential-cache exit 2>$null
}

# Post-update hook: Verify git is accessible
$PostUpdateScriptBlock = {
    $gitVersion = & git --version 2>$null
    Write-Host "Git version after update: $gitVersion"
}
```

**Why these settings?**:
- Force close safe (git operations typically quick)
- Pre-hook clears credentials (prevents lock issues)
- Post-hook validates installation

---

## Migration Guide

### From V1 to V3

**V1 Configuration**:
```powershell
$name = 'Google Chrome'
$ID = 'Google.Chrome'
$AppProcess = 'chrome'
```

**V3 Configuration**:
```powershell
$ID = 'Google.Chrome'
# That's it! Name and process auto-detected
```

### From V2 to V3

**V2 Configuration**:
```powershell
$ID = 'Google.Chrome'
```

**V3 Configuration** (basic):
```powershell
$ID = 'Google.Chrome'
# Same as V2!
```

**V3 Configuration** (with enhancements):
```powershell
$ID = 'Google.Chrome'
$EnableLogging = $true
$MaxRetries = 5
$NotifyUserBeforeClose = $true
```

**No breaking changes!** V3 is fully backward compatible with V2.

---

## Advanced Features

### Logging

Enable detailed logging for troubleshooting:

```powershell
$EnableLogging = $true
$LogPath = "C:\ProgramData\IntuneScripts\Logs\WingetDetection_$ID.log"
```

**Log Output Example**:
```
[2025-01-15 14:32:10] [Info] === Starting winget detection for package: Google.Chrome ===
[2025-01-15 14:32:10] [Info] Checking network connectivity...
[2025-01-15 14:32:11] [Info] Network connectivity confirmed
[2025-01-15 14:32:11] [Info] Found winget: C:\Program Files\WindowsApps\...
[2025-01-15 14:32:12] [Info] Update available: 120.0.6099.109 -> 120.0.6099.130
[2025-01-15 14:32:12] [Info] === Detection script completed ===
```

### Pre/Post Update Hooks

Execute custom actions before and after updates:

```powershell
# Stop dependent services before update
$PreUpdateScriptBlock = {
    Write-Host "Stopping dependent services..."
    Stop-Service -Name "ServiceA" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "ServiceB" -Force -ErrorAction SilentlyContinue
}

# Restart services and verify after update
$PostUpdateScriptBlock = {
    Write-Host "Restarting services..."
    Start-Service -Name "ServiceA"
    Start-Service -Name "ServiceB"

    # Send notification
    Write-Host "Update completed at $(Get-Date)"
}
```

**Common Hook Use Cases**:
- Stop/start services
- Clear caches
- Backup configuration files
- Send notifications
- Run validation tests
- Update registry settings

### Retry Logic

V3 templates automatically retry failed operations:

```powershell
$MaxRetries = 3              # Total attempts (default: 3)
$RetryDelaySeconds = 2       # Initial delay (default: 2)
```

**Retry Behavior**:
- Attempt 1: Immediate
- Attempt 2: Wait 2 seconds
- Attempt 3: Wait 4 seconds (exponential backoff)

### Network Connectivity Check

Validate internet connectivity before attempting updates:

```powershell
$CheckNetworkConnectivity = $true  # Enabled by default
```

If network is unavailable, script exits gracefully (exit 0) without triggering remediation.

---

## Deployment Guide

### 1. Choose Your Template

| App Type | Recommended Template | Example Apps |
|----------|---------------------|--------------|
| User Apps (business hours) | remediate_v3_standard.ps1 | Chrome, VS Code, VLC |
| Background Services | remediate_v3_force_close.ps1 | TeamViewer, utilities |
| Critical Production Tools | remediate_v3_maintenance_window.ps1 | SSMS, PowerShell 7 |
| Collaboration Tools | remediate_v3_force_close.ps1 (with notifications) | Teams, Zoom |

### 2. Configure Scripts

1. Copy `detect_v3.ps1` to your app folder
2. Copy appropriate remediation template to your app folder
3. Set the `$ID` variable in both scripts
4. Customize optional settings as needed

### 3. Test Locally

```powershell
# Test detection
.\detect.ps1

# Test remediation
.\remediate.ps1
```

### 4. Deploy to Intune

1. Navigate to: **Endpoint Manager** → **Reports** → **Endpoint Analytics** → **Proactive Remediations**
2. Click **Create script package**
3. Upload `detect_v3.ps1` as detection script
4. Upload `remediate_v3_*.ps1` as remediation script
5. Configure:
   - **Run this script using logged-on credentials**: No
   - **Run script in 64-bit PowerShell**: Yes
6. Assign to device groups
7. Set schedule (daily, weekly, etc.)

### 5. Monitor Results

- Check Intune reports for success/failure rates
- Review logs if `$EnableLogging = $true`
- Adjust retry counts or timings based on results

---

## Troubleshooting

### Issue: Updates Not Detecting

**Solutions**:
1. Enable logging: `$EnableLogging = $true`
2. Increase retries: `$MaxRetries = 5`
3. Check network: `$CheckNetworkConnectivity = $true`
4. Verify winget ID is correct

### Issue: Force Close Not Working

**Solutions**:
1. Verify process name: `$AppProcess = 'correctname'`
2. Increase close attempts: `$MaxProcessCloseAttempts = 5`
3. Add pre-hook to kill child processes

### Issue: Maintenance Window Not Triggering

**Solutions**:
1. Enable logging to see current time checks
2. Verify day names are correct (case-sensitive)
3. Check hour format (24-hour, 0-23)
4. Ensure Intune schedule aligns with window

### Issue: User Notifications Not Showing

**Solutions**:
1. Verify users are logged in when script runs
2. Check Windows Messenger service is running
3. Test with longer notification time
4. Firewall may block `msg.exe`

---

## Best Practices

### 1. **Start Conservative**

Begin with standard remediation, add force close only if needed:
```powershell
# Start with this
remediate_v3_standard.ps1

# Upgrade to this if updates aren't completing
remediate_v3_force_close.ps1(with notifications)
```

### 2. **Enable Logging During Testing**

Always enable logging when testing new configurations:
```powershell
$EnableLogging = $true
```

Disable in production once stable to reduce disk I/O.

### 3. **Use Maintenance Windows for Critical Apps**

Don't risk production outages - use maintenance windows:
```powershell
# Production databases, development tools, system utilities
remediate_v3_maintenance_window.ps1
```

### 4. **Notify Users for Collaboration Tools**

Always notify before closing collaboration apps:
```powershell
$NotifyUserBeforeClose = $true
$UserNotificationSeconds = 120  # 2 minutes
```

### 5. **Test Hooks Thoroughly**

Pre/post hooks can break updates if they fail:
```powershell
$PreUpdateScriptBlock = {
    try {
        # Your action
    } catch {
        Write-Warning "Hook failed but continuing: $_"
    }
}
```

### 6. **Document Your Configuration**

Add comments explaining why you chose specific settings:
```powershell
# User notification: 2 minutes because users are often in calls
$UserNotificationSeconds = 120

# Force close: Required for security compliance
$ForceCloseInMaintenanceWindow = $true
```

---

## Version History

| Version | Release | Key Features |
|---------|---------|-------------|
| **V1** | 2023 | Basic templates, manual configuration |
| **V2** | 2024 | Auto-detection, simplified configuration |
| **V3** | 2025 | Retry logic, logging, notifications, maintenance windows, hooks |

---

## Support & Feedback

For issues, enhancements, or questions:
- Check existing app folders for working examples
- Review Intune deployment logs
- Enable `$EnableLogging = $true` for detailed diagnostics

---

## Quick Reference Card

### Detection Configuration
```powershell
$ID = 'WINGETID'                     # Required
$MaxRetries = 3                      # Optional
$EnableLogging = $false              # Optional
$CheckNetworkConnectivity = $true    # Optional
```

### Standard Remediation
```powershell
$ID = 'WINGETID'                     # Required
$AppProcess = $null                  # Optional (auto-detect)
$MaxRetries = 3                      # Optional
$EnableLogging = $false              # Optional
```

### Force Close Remediation
```powershell
$ID = 'WINGETID'                     # Required
$NotifyUserBeforeClose = $false      # Optional
$UserNotificationSeconds = 60        # Optional
$GracePeriodSeconds = 5              # Optional
$MaxProcessCloseAttempts = 3         # Optional
```

### Maintenance Window Remediation
```powershell
$ID = 'WINGETID'                     # Required
$MaintenanceWindowDays = @('Sat','Sun')  # Required
$MaintenanceWindowStartHour = 2      # Required
$MaintenanceWindowEndHour = 6        # Required
$ForceCloseInMaintenanceWindow = $true  # Optional
```

---

**Happy Updating! 🚀**
