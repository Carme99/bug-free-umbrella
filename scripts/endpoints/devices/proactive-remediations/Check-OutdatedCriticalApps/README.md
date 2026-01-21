# Check-OutdatedCriticalApps

Proactive remediation for detecting and updating security-critical applications using winget.

## 🎯 Overview

This remediation automatically identifies and updates applications with known security vulnerabilities or those requiring frequent security patches. Designed for rapid response to zero-day vulnerabilities and maintaining a secure application baseline across your fleet.

**Key Benefits:**
- **Faster CVE response** - Updates critical apps within hours of patch release
- **Reduced security surface** - Keeps browsers, VPN clients, and security tools current
- **Automated compliance** - Ensures security baselines without manual intervention
- **Measurable impact** - Track patch rates and time-to-remediation metrics

---

## 📋 Files

| File | Purpose | Use Case |
|------|---------|----------|
| `detect.ps1` | Detection script | Identifies outdated critical apps |
| `remediate.ps1` | Standard remediation | Updates all critical/standard apps |
| `remediate_priority_only.ps1` | Priority-only remediation | Updates ONLY highest-priority apps (browsers, VPN, security tools) |

---

## 🚀 Quick Start

### Recommended Deployment

**Deploy TWO proactive remediations for best results:**

#### 1. **Priority Updates** (High Frequency)
- **Detection**: `detect.ps1` with `PriorityAppsOnly = $true`
- **Remediation**: `remediate_priority_only.ps1`
- **Schedule**: Every 4 hours
- **Purpose**: Rapid security response for browsers, VPN, security tools

#### 2. **Comprehensive Updates** (Daily)
- **Detection**: `detect.ps1` (default settings)
- **Remediation**: `remediate.ps1`
- **Schedule**: Once daily during business hours
- **Purpose**: Keep all approved apps up-to-date

---

## ⚙️ Configuration

### Priority Applications (Security-Critical)

These applications are **always checked and updated** when using priority mode:

**Browsers** (High CVE Frequency)
- Google Chrome (`Google.Chrome`)
- Mozilla Firefox (`Mozilla.Firefox`)
- Microsoft Edge (`Microsoft.Edge`)
- Brave Browser (`BraveSoftware.BraveBrowser`)

**VPN & Remote Access** (Security-Critical)
- Cisco AnyConnect (`Cisco.CiscoAnyConnect`)
- OpenVPN (`OpenVPN.OpenVPN`)
- WireGuard (`WireGuard.WireGuard`)

**Development Tools** (Supply Chain Security)
- Visual Studio Code (`Microsoft.VisualStudioCode`)
- Git (`Git.Git`)
- Python 3.11/3.12

**Security Tools**
- PowerShell 7 (`Microsoft.PowerShell`)
- 1Password (`1Password.1Password`)
- Bitwarden (`Bitwarden.Bitwarden`)

### Standard Applications

Additional apps checked in **standard mode** (non-priority):
- Adobe Acrobat Reader
- VLC Media Player
- Zoom
- Microsoft Teams
- Notepad++
- 7-Zip
- PowerToys

### Customizing App Lists

Edit the scripts to add/remove applications:

```powershell
# In detect.ps1 or remediate.ps1
$PriorityApps = @(
    'Google.Chrome',
    'Your.CustomApp',  # Add your apps here
    'Mozilla.Firefox'
)
```

---

## 📖 Usage Examples

### Example 1: Standard Detection (All Apps)

```powershell
.\detect.ps1
```

**Output:**
```
CRITICAL UPDATES DETECTED: 5 applications

Applications requiring updates:
  [PRIORITY] Google Chrome (Google.Chrome)
    Current: 119.0.6045.159 → Available: 120.0.6099.109
  [PRIORITY] Mozilla Firefox (Mozilla.Firefox)
    Current: 120.0 → Available: 121.0
  [STANDARD] Adobe Acrobat Reader (Adobe.Acrobat.Reader.64-bit)
    Current: 23.001.20687 → Available: 23.006.20360

Summary: 2 priority, 3 standard updates needed
```

### Example 2: Priority Apps Only

```powershell
.\detect.ps1 -PriorityAppsOnly $true -EnableLogging $true
```

Only checks/reports priority applications. Logs to `%TEMP%\WingetUpdateDetection.log`.

### Example 3: Standard Remediation

```powershell
.\remediate.ps1
```

Updates all detected critical apps (skips running applications).

### Example 4: Force Close and Update (Maintenance Window)

```powershell
.\remediate.ps1 -ForceCloseApps $true -EnableLogging $true
```

Closes running applications before updating. **Use during maintenance windows only.**

### Example 5: Priority-Only Emergency Response

```powershell
.\remediate_priority_only.ps1 -ForceCloseApps $true
```

Rapidly updates ONLY browsers, VPN, and security tools with forced closure.

---

## 🔧 Parameters

### detect.ps1

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `EnableLogging` | bool | `$false` | Log to `%TEMP%\WingetUpdateDetection.log` |
| `MaxRetries` | int | `3` | Retry attempts for winget operations |
| `PriorityAppsOnly` | bool | `$false` | Check only priority apps |

### remediate.ps1

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `EnableLogging` | bool | `$false` | Log to `%TEMP%\WingetUpdateRemediation.log` |
| `MaxRetries` | int | `3` | Retry attempts per application |
| `PriorityAppsOnly` | bool | `$false` | Update only priority apps |
| `UpdateOnlyIfNotRunning` | bool | `$true` | Skip apps that are currently running |
| `ForceCloseApps` | bool | `$false` | Force close running apps before updating |
| `TimeoutPerAppMinutes` | int | `10` | Timeout per application (minutes) |

### remediate_priority_only.ps1

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `EnableLogging` | bool | `$true` | Log to `%TEMP%\WingetUpdateRemediation_Priority.log` |
| `ForceCloseApps` | bool | `$false` | Force close running apps |

---

## 🎯 Deployment Scenarios

### Scenario 1: Rapid Security Response (Recommended)

**Goal**: Patch critical vulnerabilities within 4 hours of detection

**Setup:**
1. Create proactive remediation package
   - Detection: `detect.ps1 -PriorityAppsOnly $true`
   - Remediation: `remediate_priority_only.ps1`
2. Schedule: Every 4 hours
3. Assignment: All devices
4. Run as: SYSTEM
5. 64-bit PowerShell: Yes

**Result**: Browsers and VPN clients auto-update 6 times/day

---

### Scenario 2: Business Hours Updates

**Goal**: Update all apps during work hours, skip running applications

**Setup:**
1. Detection: `detect.ps1` (default)
2. Remediation: `remediate.ps1` (default)
3. Schedule: Once daily at 10 AM
4. Assignment: All devices

**Result**: Comprehensive updates without disrupting users

---

### Scenario 3: Maintenance Window Updates

**Goal**: Force-close and update all apps during off-hours

**Setup:**
1. Detection: `detect.ps1`
2. Remediation: `remediate.ps1 -ForceCloseApps $true -EnableLogging $true`
3. Schedule: Once daily at 2 AM
4. Assignment: All devices

**Result**: Guaranteed updates, apps closed if necessary

---

### Scenario 4: Audit Mode (Detection Only)

**Goal**: Report outdated apps without updating

**Setup:**
1. Detection: `detect.ps1 -EnableLogging $true`
2. Remediation: None (don't assign)
3. Schedule: Daily
4. Review logs and Intune reports

**Result**: Visibility into update needs without auto-remediation

---

## 📊 Monitoring & Reporting

### Intune Reports

**View Results:**
1. Go to **Devices** > **Remediations**
2. Select **Check-OutdatedCriticalApps**
3. Review:
   - **Device status**: See which devices detected issues
   - **Remediation status**: Track successful updates
   - **Failure reasons**: Investigate stuck updates

### Log Files

**When `EnableLogging = $true`:**

**Detection Log**: `%TEMP%\WingetUpdateDetection.log`
```
[2024-01-21 14:30:15] [INFO] === Winget Critical App Update Detection Started ===
[2024-01-21 14:30:16] [INFO] Winget found at: C:\Program Files\WindowsApps\...
[2024-01-21 14:30:18] [INFO] Found 12 total outdated applications
[2024-01-21 14:30:18] [INFO] CRITICAL UPDATES DETECTED: 5 applications
```

**Remediation Log**: `%TEMP%\WingetUpdateRemediation.log`
```
[2024-01-21 14:35:10] [INFO] === Winget Critical App Update Remediation Started ===
[2024-01-21 14:35:12] [PRIORITY] Updating: Google Chrome (Google.Chrome)
[2024-01-21 14:36:45] [SUCCESS] Successfully updated Google Chrome
[2024-01-21 14:36:46] [INFO] === Remediation Complete ===
[2024-01-21 14:36:46] [INFO] Successfully Updated: 5
```

---

## ⚠️ Important Considerations

### Process Detection

The script attempts to detect running applications before updating. Process name mappings are configurable:

```powershell
$ProcessNameMap = @{
    'Google.Chrome' = 'chrome'
    'Mozilla.Firefox' = 'firefox'
    'Microsoft.Edge' = 'msedge'
}
```

**Note**: If an app uses a non-standard process name, add it to the mapping.

### Force Close Behavior

When `ForceCloseApps = $true`:
1. Attempt graceful close (`CloseMainWindow()`)
2. Wait 3 seconds
3. Force kill if still running (`Stop-Process -Force`)

**Recommendation**: Only use force close during maintenance windows to avoid data loss.

### Timeouts

- **Default timeout**: 10 minutes per app
- **Priority timeout**: 5 minutes per app
- Apps that timeout are skipped and logged

### Network Requirements

- Requires internet connectivity to winget CDN
- Validates connectivity before attempting updates
- Retries failed connections with exponential backoff

---

## 🐛 Troubleshooting

### Issue: "Winget not found"

**Cause**: Winget not installed or not in PATH

**Solution**:
```powershell
# Check winget availability
winget --version

# Reinstall App Installer (includes winget)
# Via Intune: Deploy "App Installer" from Microsoft Store
```

---

### Issue: Updates not detecting

**Cause**: Winget cache outdated or source unreachable

**Solution**:
1. Enable logging: `-EnableLogging $true`
2. Check network connectivity
3. Reset winget sources:
```powershell
winget source reset --force
winget source update
```

---

### Issue: Apps marked as running but they're not

**Cause**: Orphaned processes or incorrect process name mapping

**Solution**:
1. Check process name in Task Manager
2. Update `$ProcessNameMap` in script:
```powershell
$ProcessNameMap = @{
    'YourApp.Id' = 'actual-process-name'
}
```

---

### Issue: Some apps update, others fail

**Cause**: Individual app issues (corrupted installation, insufficient permissions)

**Solution**:
1. Check remediation logs
2. Manually test winget upgrade for failing app:
```powershell
winget upgrade --id FailingApp.Id --silent
```
3. If consistent failures, remove from monitored list

---

## 🔒 Security Considerations

### Permissions

- **Runs as**: SYSTEM account
- **Reason**: Required to update apps installed machine-wide
- **Risk**: Minimal - only updates signed packages from Microsoft winget repository

### Package Validation

- All packages validated by winget before installation
- Only official winget sources used
- Package signatures verified by Windows

### Data Privacy

- No user data collected or transmitted
- Logs contain only app names, versions, and update status
- Logs stored locally, deleted on device wipe

---

## 📚 Related Documentation

- **Winget Documentation**: [docs.microsoft.com/windows/package-manager/winget](https://docs.microsoft.com/windows/package-manager/winget/)
- **Intune Proactive Remediations**: [learn.microsoft.com/mem/intune/fundamentals/remediations](https://learn.microsoft.com/mem/intune/fundamentals/remediations)
- **Bug-Free Umbrella Repository**: [github.com/yourorg/bug-free-umbrella](https://github.com/yourorg/bug-free-umbrella)

---

## 📝 Version History

**Version 1.0** (2024-01-21)
- Initial release
- Priority/standard app classification
- Multiple remediation variants
- Comprehensive logging and error handling
- Process detection and force-close capabilities

---

## 🤝 Contributing

To add new applications to the priority or standard lists:

1. Find the winget package ID:
   ```powershell
   winget search "Application Name"
   ```

2. Add to appropriate array in scripts:
   ```powershell
   $PriorityApps = @(
       'Existing.App',
       'Your.NewApp'  # Add here
   )
   ```

3. If app uses non-standard process name, add mapping:
   ```powershell
   $ProcessNameMap = @{
       'Your.NewApp' = 'actual-process-name'
   }
   ```

4. Test locally before deploying

---

## 📄 License

Part of the Bug-Free Umbrella project. See repository LICENSE file.

---

## ✉️ Support

For issues or questions:
1. Check troubleshooting section above
2. Review Intune deployment logs
3. Enable logging and analyze log files
4. Consult Bug-Free Umbrella documentation
