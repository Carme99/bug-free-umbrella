# Winget Update Templates for Intune

This folder contains simplified templates for deploying winget-based application updates through Intune Proactive Remediations. Technicians only need to provide the **winget package ID** - everything else is auto-detected!

## 🚀 Quick Start

### Step 1: Find the Winget Package ID

Search for your application on winget:

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

### Step 2: Choose Your Template

| Template | Use Case | Behavior |
|----------|----------|----------|
| **detect_v2.ps1** | Detection script | Checks if update is available |
| **remediate_v2_standard.ps1** | Standard update | Waits for app to close before updating |
| **remediate_v2_force_close.ps1** | Force close update | Automatically closes app before updating ⚠️ |

### Step 3: Configure (One Line!)

Open your chosen template and set the winget ID:

```powershell
$ID = 'Google.Chrome'  # That's it!
```

**Everything else is auto-detected:**
- ✅ Application name (from winget)
- ✅ Process name (from package ID)
- ✅ Version checking
- ✅ Update logic

## 📋 Template Details

### detect_v2.ps1

**Purpose:** Checks if an application update is available

**Configuration Required:**
```powershell
$ID = 'WINGETID'  # Replace with your package ID
```

**Exit Codes:**
- `0` = No update available or app not installed (no action)
- `1` = Update available (triggers remediation)

**Example:**
```powershell
$ID = 'Mozilla.Firefox'
```

---

### remediate_v2_standard.ps1

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

**Example:**
```powershell
# Minimal configuration
$ID = 'Google.Chrome'

# With optional customization
$ID = 'Google.Chrome'
$name = 'Google Chrome Browser'
$AppProcess = 'chrome'  # Usually auto-detected correctly
```

---

### remediate_v2_force_close.ps1

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

**Example:**
```powershell
# Minimal configuration
$ID = 'TeamViewer.TeamViewer'

# With optional customization
$ID = 'TeamViewer.TeamViewer'
$name = 'TeamViewer Full'
$AppProcess = 'TeamViewer'
$GracePeriodSeconds = 10  # Wait 10 seconds after force close
```

## 🎯 Common Use Cases

### Scenario 1: Update Google Chrome (Wait for User)

**Use:** `remediate_v2_standard.ps1`

```powershell
$ID = 'Google.Chrome'
```

Users must close Chrome before update installs. Good for business hours.

### Scenario 2: Update TeamViewer (Force Close)

**Use:** `remediate_v2_force_close.ps1`

```powershell
$ID = 'TeamViewer.TeamViewer'
```

TeamViewer will be forcefully closed and updated. Good for maintenance windows.

### Scenario 3: Update Adobe Reader (Wait for User)

**Use:** `remediate_v2_standard.ps1`

```powershell
$ID = 'Adobe.Acrobat.Reader.64-bit'
```

Won't close Adobe Reader if user has documents open.

### Scenario 4: Update Visual Studio Code (Force Close)

**Use:** `remediate_v2_force_close.ps1`

```powershell
$ID = 'Microsoft.VisualStudioCode'
```

VS Code will be forcefully closed. Ensure users are notified beforehand!

## 🔧 Advanced: When Auto-Detection Fails

In rare cases, you may need to manually specify the process name:

```powershell
# If the app has a different process name than the package ID suggests
$ID = 'Adobe.Acrobat.Reader.64-bit'
$AppProcess = 'AcroRd32'  # Adobe Reader's actual process name
```

**How to find the process name:**
1. Open Task Manager (Ctrl+Shift+Esc)
2. Find your application
3. Right-click → Go to details
4. Note the process name (without .exe)

## 📊 Deployment to Intune

### Create Proactive Remediation Package

1. **Sign in to Intune**: https://intune.microsoft.com
2. **Navigate to**: Devices → Scripts and remediations → Proactive remediations
3. **Click**: Create script package
4. **Configure**:
   - **Name**: `Winget Update - Google Chrome`
   - **Detection script**: Upload your configured `detect_v2.ps1`
   - **Remediation script**: Upload your configured `remediate_v2_standard.ps1` or `remediate_v2_force_close.ps1`
   - **Run script in 64-bit PowerShell**: Yes
   - **Run this script using logged on credentials**: No (run as system)
5. **Assign** to device groups
6. **Schedule** (e.g., daily at 2 AM for force close, or every 4 hours for standard)

## 🆚 Template Comparison

| Feature | Standard | Force Close |
|---------|----------|-------------|
| Closes app automatically | ❌ No | ✅ Yes |
| User data loss risk | ❌ None | ⚠️ Possible |
| Best for business hours | ✅ Yes | ❌ No |
| Best for maintenance windows | ❌ No | ✅ Yes |
| Guarantees update install | ❌ No | ✅ Yes |
| Requires user action | ✅ Yes | ❌ No |

## 📚 Popular Winget Package IDs

Quick reference for common applications:

| Application | Winget ID |
|------------|-----------|
| Google Chrome | `Google.Chrome` |
| Mozilla Firefox | `Mozilla.Firefox` |
| Adobe Acrobat Reader (64-bit) | `Adobe.Acrobat.Reader.64-bit` |
| Adobe Acrobat Reader (32-bit) | `Adobe.Acrobat.Reader.32-bit` |
| Microsoft Edge | `Microsoft.Edge` |
| Visual Studio Code | `Microsoft.VisualStudioCode` |
| 7-Zip | `7zip.7zip` |
| Notepad++ | `Notepad++.Notepad++` |
| VLC Media Player | `VideoLAN.VLC` |
| TeamViewer | `TeamViewer.TeamViewer` |
| Zoom | `Zoom.Zoom` |
| Git | `Git.Git` |
| Python 3 | `Python.Python.3.12` |
| Node.js | `OpenJS.NodeJS` |

Search for more: `winget search "<app name>"`

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

### Issue: Update detected but remediation doesn't run

**Solution:**
- Check Intune assignment and schedule
- Verify script is set to run as **system**, not user
- Check device sync status in Intune

### Issue: Force close doesn't close the app

**Solution:** Increase grace period and try multiple close attempts:

```powershell
$GracePeriodSeconds = 10
# Script already retries force close if first attempt fails
```

## 📖 Learn More

- **Winget Documentation**: https://learn.microsoft.com/en-us/windows/package-manager/winget/
- **Intune Proactive Remediations**: https://learn.microsoft.com/en-us/mem/intune/fundamentals/remediations
- **Find Package IDs**: https://winget.run/

## 🏷️ Version History

- **v2 Templates** (Current): Simplified configuration with auto-detection
  - `detect_v2.ps1`
  - `remediate_v2_standard.ps1`
  - `remediate_v2_force_close.ps1`

- **v1 Templates** (Legacy): Required manual configuration of all variables
  - `detect.ps1`
  - `remediate.ps1`

---

**Pro Tip:** Start with the standard template for user-facing apps during business hours. Use force close templates during scheduled maintenance windows or for background services.
