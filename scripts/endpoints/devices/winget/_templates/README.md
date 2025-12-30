# Winget Update Templates for Intune

This folder contains templates for deploying winget-based application updates through Intune Proactive Remediations. All templates require **only the winget package ID** - everything else is auto-detected!

## 📊 Template Versions Overview

| Feature | V1 (Legacy) | V2 | V3 (Recommended) |
|---------|-------------|----|----|
| Config Required | 3 variables | 1 variable | 1 variable |
| Auto-detect Name | ❌ | ✅ | ✅ |
| Auto-detect Process | ❌ | ✅ | ✅ |
| Retry Logic | ❌ | ❌ | ✅ |
| Logging | ❌ | ❌ | ✅ |
| Network Check | ❌ | ❌ | ✅ |
| User Notifications | ❌ | ❌ | ✅ |
| Maintenance Windows | ❌ | ❌ | ✅ |
| Pre/Post Hooks | ❌ | ❌ | ✅ |

**Recommendation**: Use **V3** for production environments. Use **V2** for simple deployments without advanced features.

---

## 🚀 Quick Start

### Option 1: V3 Templates (Enterprise-Grade)

**Best for**: Production environments, critical apps, complex requirements

```powershell
# Minimal configuration - just one line!
$ID = 'Google.Chrome'

# Optional: Enable advanced features
$EnableLogging = $true
$MaxRetries = 5
$NotifyUserBeforeClose = $true
```

**V3 Templates Available**:
- `detect_v3.ps1` - Enhanced detection with retry logic
- `remediate_v3_standard.ps1` - Wait for app to close
- `remediate_v3_force_close.ps1` - Force close with user notifications
- `remediate_v3_maintenance_window.ps1` - Time-based update control

### Option 2: V2 Templates (Simplified)

**Best for**: Simple deployments, quick setup, minimal configuration

```powershell
# Only one line needed!
$ID = 'Google.Chrome'
```

**V2 Templates Available**:
- `detect_v2.ps1` - Basic detection
- `remediate_v2_standard.ps1` - Wait for app to close
- `remediate_v2_force_close.ps1` - Force close app

### Finding Winget Package IDs

Search for your application:

```powershell
winget search "Google Chrome"
```

Example output:
```
Name          Id              Version
------------------------------------------
Google Chrome Google.Chrome   120.0.6099.130
```

The **Id** column is what you need: `Google.Chrome`

---

## 📘 V3 Templates - Enterprise Features

### What's New in V3

- ✅ **Retry logic** with exponential backoff
- ✅ **Network connectivity** validation
- ✅ **File or event log** logging
- ✅ **User notifications** before force closing apps
- ✅ **Maintenance windows** for time-based updates
- ✅ **Pre/Post hooks** for custom actions
- ✅ **Enhanced error handling** and status reporting

### V3 Template Details

#### 1. detect_v3.ps1 - Enhanced Detection

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

---

#### 2. remediate_v3_standard.ps1 - Enhanced Standard Update

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

#### 3. remediate_v3_force_close.ps1 - Force Close with Notifications

**Purpose**: Force close apps for updates, optionally notifying users first.

⚠️ **WARNING**: This will close the application without saving user work!

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

**Best For**:
- Background services (TeamViewer, system utilities)
- Maintenance window deployments
- Critical security updates that can't wait
- After-hours updates

---

#### 4. remediate_v3_maintenance_window.ps1 - Scheduled Updates

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

## 📗 V2 Templates - Simplified Approach

### V2 Template Details

#### detect_v2.ps1

**Purpose:** Checks if an application update is available

**Configuration Required:**
```powershell
$ID = 'WINGETID'  # Replace with your package ID
```

**Exit Codes:**
- `0` = No update available or app not installed (no action)
- `1` = Update available (triggers remediation)

---

#### remediate_v2_standard.ps1

**Purpose:** Updates applications, waiting for them to close naturally

**Configuration Required:**
```powershell
$ID = 'WINGETID'  # Replace with your package ID
```

**Optional Configuration:**
```powershell
$name = 'Custom Display Name'  # Override auto-detected name
$AppProcess = 'customprocess'  # Override auto-detected process name
```

**Behavior:**
- Checks if app is running
- If running: Skips update and retries later
- If not running: Installs update
- Best for: User-facing applications where force closing would lose work

---

#### remediate_v2_force_close.ps1

**Purpose:** Updates applications, forcefully closing them if needed

⚠️ **WARNING:** This will close the application without saving user work!

**Configuration Required:**
```powershell
$ID = 'WINGETID'  # Replace with your package ID
```

**Optional Configuration:**
```powershell
$name = 'Custom Display Name'          # Override auto-detected name
$AppProcess = 'customprocess'          # Override auto-detected process name
$GracePeriodSeconds = 5                # Wait time after closing app
$VerifyWaitSeconds = 10                # Wait time after update to verify
```

**Behavior:**
- Checks if app is running
- If running: Force closes the application
- Waits for grace period
- Installs update
- Verifies installation
- Best for: Background services, developer tools, or maintenance windows

---

## 🎯 Real-World Examples

### Example 1: Google Chrome (User-Facing App)

**Scenario**: Update Chrome, wait for users to close it (business hours)

**V3 Configuration**:
```powershell
# detect_v3.ps1
$ID = 'Google.Chrome'

# remediate_v3_standard.ps1
$ID = 'Google.Chrome'
```

**V2 Configuration**:
```powershell
# detect_v2.ps1
$ID = 'Google.Chrome'

# remediate_v2_standard.ps1
$ID = 'Google.Chrome'
```

---

### Example 2: Microsoft Teams (Collaboration Tool)

**Scenario**: Force close with user notification for critical updates

**V3 Configuration**:
```powershell
# detect_v3.ps1
$ID = 'Microsoft.Teams'
$EnableLogging = $true

# remediate_v3_force_close.ps1
$ID = 'Microsoft.Teams'
$AppProcess = 'ms-teams'
$NotifyUserBeforeClose = $true
$UserNotificationSeconds = 120  # 2 minutes warning
```

**Why these settings?**:
- User notification critical (might be in a call)
- 2-minute warning gives time to wrap up
- Logging enabled for troubleshooting user complaints

---

### Example 3: SQL Server Management Studio (Critical Tool)

**Scenario**: Update only during weekend maintenance windows

**V3 Configuration**:
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

---

### Example 4: TeamViewer (Force Close)

**Scenario**: Force close TeamViewer for maintenance window updates

**V3 Configuration**:
```powershell
# detect_v3.ps1
$ID = 'TeamViewer.TeamViewer'

# remediate_v3_force_close.ps1
$ID = 'TeamViewer.TeamViewer'
$GracePeriodSeconds = 10
```

**V2 Configuration**:
```powershell
# detect_v2.ps1
$ID = 'TeamViewer.TeamViewer'

# remediate_v2_force_close.ps1
$ID = 'TeamViewer.TeamViewer'
$GracePeriodSeconds = 10
```

---

### Example 5: Git (Developer Tool with Hooks)

**Scenario**: Update Git with custom pre/post actions (V3 only)

**V3 Configuration**:
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

---

## 📊 Deployment to Intune

### Create Proactive Remediation Package

1. **Sign in to Intune**: https://intune.microsoft.com
2. **Navigate to**: Devices → Scripts and remediations → Proactive remediations
3. **Click**: Create script package
4. **Configure**:
   - **Name**: `Winget Update - Google Chrome`
   - **Detection script**: Upload your configured `detect_v3.ps1` or `detect_v2.ps1`
   - **Remediation script**: Upload your configured remediation script
   - **Run script in 64-bit PowerShell**: Yes
   - **Run this script using logged on credentials**: No (run as system)
5. **Assign** to device groups
6. **Schedule**:
   - Daily at 2 AM for force close templates
   - Every 4 hours for standard templates
   - Align with maintenance window for maintenance_window template

---

## 🆚 Template Comparison

### V3 vs V2 Comparison

| Feature | V2 Standard | V2 Force Close | V3 Standard | V3 Force Close | V3 Maintenance Window |
|---------|-------------|----------------|-------------|----------------|---------------------|
| Closes app automatically | ❌ | ✅ | ❌ | ✅ | ✅ (in window) |
| User notifications | ❌ | ❌ | ❌ | ✅ | ✅ |
| Retry logic | ❌ | ❌ | ✅ | ✅ | ✅ |
| Logging | ❌ | ❌ | ✅ | ✅ | ✅ |
| Time-based control | ❌ | ❌ | ❌ | ❌ | ✅ |
| Custom hooks | ❌ | ❌ | ✅ | ✅ | ✅ |
| Network check | ❌ | ❌ | ✅ | ✅ | ✅ |

---

## 🔧 Advanced Features (V3 Only)

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

---

## 📚 Popular Winget Package IDs

Quick reference for common applications:

| Application | Winget ID |
|------------|-----------|
| Google Chrome | `Google.Chrome` |
| Mozilla Firefox | `Mozilla.Firefox` |
| Microsoft Edge | `Microsoft.Edge` |
| Microsoft Teams | `Microsoft.Teams` |
| Visual Studio Code | `Microsoft.VisualStudioCode` |
| Adobe Acrobat Reader (64-bit) | `Adobe.Acrobat.Reader.64-bit` |
| Adobe Acrobat Reader (32-bit) | `Adobe.Acrobat.Reader.32-bit` |
| 7-Zip | `7zip.7zip` |
| Notepad++ | `Notepad++.Notepad++` |
| VLC Media Player | `VideoLAN.VLC` |
| TeamViewer | `TeamViewer.TeamViewer` |
| Zoom | `Zoom.Zoom` |
| Git | `Git.Git` |
| Python 3 | `Python.Python.3.12` |
| Node.js | `OpenJS.NodeJS` |
| SQL Server Management Studio | `Microsoft.SQLServerManagementStudio` |
| PowerShell 7 | `Microsoft.PowerShell` |

Search for more: `winget search "<app name>"`

Or visit: https://winget.run/

---

## 🔍 Troubleshooting

### Issue: Script fails with "winget not found"

**Solution:** Ensure App Installer is installed and updated on target devices.

```powershell
# Check winget availability
winget --version
```

### Issue: Process name auto-detection doesn't work

**Solution:** Manually specify the process name:

```powershell
$ID = 'YourApp.ID'
$AppProcess = 'actualprocessname'  # Find in Task Manager
```

**How to find the process name:**
1. Open Task Manager (Ctrl+Shift+Esc)
2. Find your application
3. Right-click → Go to details
4. Note the process name (without .exe)

### Issue: Update detected but remediation doesn't run

**Solution:**
- Check Intune assignment and schedule
- Verify script is set to run as **system**, not user
- Check device sync status in Intune
- Ensure detection script returns exit code 1

### Issue: Force close doesn't close the app (V2/V3)

**Solution:** Increase grace period and verify process name:

```powershell
$AppProcess = 'correctprocessname'  # Verify in Task Manager
$GracePeriodSeconds = 10

# V3 only: Increase close attempts
$MaxProcessCloseAttempts = 5
```

### Issue: Updates Not Detecting (V3)

**Solutions**:
1. Enable logging: `$EnableLogging = $true`
2. Increase retries: `$MaxRetries = 5`
3. Check network: `$CheckNetworkConnectivity = $true`
4. Verify winget ID is correct

### Issue: Maintenance Window Not Triggering (V3)

**Solutions**:
1. Enable logging to see current time checks
2. Verify day names are correct (case-sensitive: 'Saturday', not 'saturday')
3. Check hour format (24-hour, 0-23)
4. Ensure Intune schedule aligns with window

### Issue: User Notifications Not Showing (V3)

**Solutions**:
1. Verify users are logged in when script runs
2. Check Windows Messenger service is running
3. Test with longer notification time
4. Firewall may block `msg.exe`

---

## 📖 Best Practices

### 1. Start Conservative

Begin with standard remediation, add force close only if needed:
```powershell
# Start with this
remediate_v3_standard.ps1 or remediate_v2_standard.ps1

# Upgrade to this if updates aren't completing
remediate_v3_force_close.ps1 (with notifications)
```

### 2. Enable Logging During Testing (V3)

Always enable logging when testing new configurations:
```powershell
$EnableLogging = $true
```

Disable in production once stable to reduce disk I/O.

### 3. Use Maintenance Windows for Critical Apps (V3)

Don't risk production outages - use maintenance windows:
```powershell
# Production databases, development tools, system utilities
remediate_v3_maintenance_window.ps1
```

### 4. Notify Users for Collaboration Tools (V3)

Always notify before closing collaboration apps:
```powershell
$NotifyUserBeforeClose = $true
$UserNotificationSeconds = 120  # 2 minutes
```

### 5. Test Locally Before Deploying

```powershell
# Test detection
.\detect_v3.ps1  # or .\detect_v2.ps1

# Test remediation
.\remediate_v3_standard.ps1  # or your chosen template
```

### 6. Document Your Configuration

Add comments explaining why you chose specific settings:
```powershell
# User notification: 2 minutes because users are often in calls
$UserNotificationSeconds = 120

# Force close: Required for security compliance
$ForceCloseInMaintenanceWindow = $true
```

---

## 🔄 Migration Guide

### From V1 to V2/V3

**V1 Configuration**:
```powershell
$name = 'Google Chrome'
$ID = 'Google.Chrome'
$AppProcess = 'chrome'
```

**V2/V3 Configuration**:
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

## 📋 Quick Reference Cards

### V2 Templates

**Detection**:
```powershell
$ID = 'WINGETID'  # Required
```

**Standard Remediation**:
```powershell
$ID = 'WINGETID'                     # Required
$name = 'Custom Name'                # Optional
$AppProcess = 'processname'          # Optional
```

**Force Close Remediation**:
```powershell
$ID = 'WINGETID'                     # Required
$AppProcess = 'processname'          # Optional
$GracePeriodSeconds = 5              # Optional
$VerifyWaitSeconds = 10              # Optional
```

### V3 Templates

**Detection**:
```powershell
$ID = 'WINGETID'                     # Required
$MaxRetries = 3                      # Optional
$EnableLogging = $false              # Optional
$CheckNetworkConnectivity = $true    # Optional
```

**Standard Remediation**:
```powershell
$ID = 'WINGETID'                     # Required
$AppProcess = $null                  # Optional (auto-detect)
$MaxRetries = 3                      # Optional
$EnableLogging = $false              # Optional
```

**Force Close Remediation**:
```powershell
$ID = 'WINGETID'                     # Required
$NotifyUserBeforeClose = $false      # Optional
$UserNotificationSeconds = 60        # Optional
$GracePeriodSeconds = 5              # Optional
$MaxProcessCloseAttempts = 3         # Optional
```

**Maintenance Window Remediation**:
```powershell
$ID = 'WINGETID'                              # Required
$MaintenanceWindowDays = @('Sat','Sun')       # Required
$MaintenanceWindowStartHour = 2               # Required
$MaintenanceWindowEndHour = 6                 # Required
$ForceCloseInMaintenanceWindow = $true        # Optional
```

---

## 🏷️ Version History

| Version | Key Features |
|---------|-------------|
| **V1** (Legacy) | Basic templates, manual configuration of all variables |
| **V2** | Auto-detection, simplified one-variable configuration |
| **V3** (Current) | Retry logic, logging, notifications, maintenance windows, hooks |

---

## 📖 Learn More

- **Winget Documentation**: https://learn.microsoft.com/en-us/windows/package-manager/winget/
- **Intune Proactive Remediations**: https://learn.microsoft.com/en-us/mem/intune/fundamentals/remediations
- **Find Package IDs**: https://winget.run/

---

**Pro Tip:** Start with V2 templates for simple deployments. Upgrade to V3 when you need advanced features like retry logic, user notifications, or maintenance windows.

**Happy Updating! 🚀**
