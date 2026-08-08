# Winget Updates

Automate application updates using Windows Package Manager (winget) with Intune Remediations.

## Overview

The **Winget Updates** collection provides 40+ detect/remediate script pairs for automatically updating applications via winget in Microsoft Intune. Each application has dedicated scripts that:
- **Detect** if an update is available
- **Remediate** by installing the latest version
- Support **forced close** options for active applications
- Work with **maintenance windows** for minimal user disruption

**Location:** `scripts/endpoints/devices/winget/`

---

## Available Applications

### Browsers
| Application | Package ID | Scripts |
|-------------|-----------|---------|
| **Google Chrome** | `Google.Chrome` | [detect.ps1](../scripts/endpoints/devices/winget/browsers/GoogleChrome/detect.ps1) / [remediate.ps1](../scripts/endpoints/devices/winget/browsers/GoogleChrome/remediate.ps1) |
| **Mozilla Firefox** | `Mozilla.Firefox` | [detect.ps1](../scripts/endpoints/devices/winget/browsers/Firefox/detect.ps1) / [remediate.ps1](../scripts/endpoints/devices/winget/browsers/Firefox/remediate.ps1) |

### Development Tools
| Application | Package ID | Scripts |
|-------------|-----------|---------|
| **Visual Studio Code** | `Microsoft.VisualStudioCode` | [detect.ps1](../scripts/endpoints/devices/winget/development/VisualStudioCode/detect.ps1) / [remediate.ps1](../scripts/endpoints/devices/winget/development/VisualStudioCode/remediate.ps1) |
| **PowerShell 7** | `Microsoft.PowerShell` | [detect.ps1](../scripts/endpoints/devices/winget/development/PowerShell7/detect.ps1) / [remediate_maintenance_window.ps1](../scripts/endpoints/devices/winget/development/PowerShell7/remediate_maintenance_window.ps1) |
| **Git** | `Git.Git` | [detect.ps1](../scripts/endpoints/devices/winget/development/Git/detect.ps1) / [remediate.ps1](../scripts/endpoints/devices/winget/development/Git/remediate.ps1) |
| **Azure CLI** | `Microsoft.AzureCLI` | [detect.ps1](../scripts/endpoints/devices/winget/development/AzureCLI/detect.ps1) / [remediate.ps1](../scripts/endpoints/devices/winget/development/AzureCLI/remediate.ps1) |

### Productivity
| Application | Package ID | Scripts |
|-------------|-----------|---------|
| **Microsoft Teams** | `Microsoft.Teams` | [detect.ps1](../scripts/endpoints/devices/winget/productivity/MicrosoftTeams/detect.ps1) / [remediate.ps1](../scripts/endpoints/devices/winget/productivity/MicrosoftTeams/remediate.ps1) |
| **Adobe Reader (64-bit)** | `Adobe.Acrobat.Reader.64-bit` | [detect.ps1](../scripts/endpoints/devices/winget/productivity/AdobeReader64bit/detect.ps1) / [remediate.ps1](../scripts/endpoints/devices/winget/productivity/AdobeReader64bit/remediate.ps1) |
| **Notepad++** | `Notepad++.Notepad++` | [detect.ps1](../scripts/endpoints/devices/winget/productivity/NotepadPlusPlus/detect.ps1) / [remediate.ps1](../scripts/endpoints/devices/winget/productivity/NotepadPlusPlus/remediate.ps1) |

### Communication
| Application | Package ID | Scripts |
|-------------|-----------|---------|
| **Zoom** | `Zoom.Zoom` | [detect.ps1](../scripts/endpoints/devices/winget/media/Zoom/detect.ps1) / [remediate.ps1](../scripts/endpoints/devices/winget/media/Zoom/remediate.ps1) |
| **Slack** | `SlackTechnologies.Slack` | [detect.ps1](../scripts/endpoints/devices/winget/communication/Slack/detect.ps1) / [remediate.ps1](../scripts/endpoints/devices/winget/communication/Slack/remediate.ps1) |
| **Discord** | `Discord.Discord` | [detect.ps1](../scripts/endpoints/devices/winget/communication/Discord/detect.ps1) / [remediate.ps1](../scripts/endpoints/devices/winget/communication/Discord/remediate.ps1) |

### Remote Access
| Application | Package ID | Scripts |
|-------------|-----------|---------|
| **TeamViewer (Full)** | `TeamViewer.TeamViewer` | [detect.ps1](../scripts/endpoints/devices/winget/remote-access/TeamViewerFull/detect.ps1) / [remediate.ps1](../scripts/endpoints/devices/winget/remote-access/TeamViewerFull/remediate.ps1) |
| **WinSCP** | `WinSCP.WinSCP` | [detect.ps1](../scripts/endpoints/devices/winget/remote-access/WinSCP/detect.ps1) / [remediate.ps1](../scripts/endpoints/devices/winget/remote-access/WinSCP/remediate.ps1) |

### Runtimes
| Application | Package ID | Scripts |
|-------------|-----------|---------|
| **Visual C++ 2015-2022 (x64)** | `Microsoft.VCRedist.2015+.x64` | [detect.ps1](../scripts/endpoints/devices/winget/runtimes/Cpp2015-2019Redist-x64/detect.ps1) / [remediate.ps1](../scripts/endpoints/devices/winget/runtimes/Cpp2015-2019Redist-x64/remediate.ps1) |
| **Microsoft Edge WebView2** | `Microsoft.EdgeWebView2Runtime` | [detect.ps1](../scripts/endpoints/devices/winget/runtimes/EdgeWebView2/detect.ps1) / [remediate.ps1](../scripts/endpoints/devices/winget/runtimes/EdgeWebView2/remediate.ps1) |

**Complete list:** Browse the [winget directory](../scripts/endpoints/devices/winget/README.md) for all 40+ applications.

---

## How It Works

### Detection Script (detect.ps1)
Checks if an update is available:
```powershell
# Example: Check if VS Code update available
winget list --id Microsoft.VisualStudioCode --exact
# Exit 1 if update available (triggers remediation)
# Exit 0 if up to date (no action needed)
```

### Remediation Script (remediate.ps1)
Installs the latest version:
```powershell
# Example: Update VS Code
winget upgrade --id Microsoft.VisualStudioCode --exact --silent --accept-source-agreements
```

### Versions Available

Each application may have multiple remediation versions:

| Version | Description | Use Case |
|---------|-------------|----------|
| **remediate.ps1** | Standard update | App not running or can wait |
| **remediate_v2_force_close.ps1** | Force close before update | Update during business hours |
| **remediate_v3_maintenance_window.ps1** | Scheduled update | Update outside business hours |

---

## Deployment to Intune

### Step 1: Create Remediation
1. Navigate to **Endpoint Manager** → **Devices** → **Remediations**
2. Click **Create script package**
3. Configure:
   - **Name:** "Winget - Update Google Chrome"
   - **Detection script:** Upload `detect.ps1`
   - **Remediation script:** Upload `remediate.ps1`
   - **Run in 32-bit:** No
   - **Run as user:** No (run as System)

### Step 2: Assign to Devices
1. **Assignments** → Add groups
2. **Schedule:**
   - Frequency: Daily or Weekly
   - Time: During maintenance window

### Step 3: Monitor
- Check **Device status** for compliance
- Review **Detection output** for errors
- Monitor **Remediation status**

---

## System-Wide Update Script

For updating ALL applications at once, use:

**`scripts/utilities/Update-AllAppsWinget.ps1`**

```powershell
# Update all winget-managed applications
.\Update-AllAppsWinget.ps1

# With auto-configuration (sets winget settings)
.\Update-AllAppsWinget.ps1 -AutoConfigure
```

**Features:**
- Updates all installed applications
- Configures winget settings automatically
- Generates detailed reports
- Handles errors gracefully

---

## Creating Custom Templates

Use the template generator to create scripts for new applications:

**`scripts/endpoints/devices/winget/_generate-winget-scripts.ps1`**

```powershell
# Generate scripts for a new application
.\_generate-winget-scripts.ps1 -PackageId "NewVendor.NewApp" -AppName "New Application"
```

Templates are located in: `scripts/endpoints/devices/winget/_templates/`

---

## Best Practices

### Testing
1. **Test in pilot group** before broad deployment
2. **Verify compatibility** with your environment
3. **Check app versions** are compatible with winget

### Scheduling
- **Non-critical apps:** Update during business hours
- **Critical apps:** Use maintenance windows
- **Browsers/productivity:** Consider user impact

### Monitoring
- Review **detection compliance** weekly
- Check **remediation failures** for patterns
- Monitor **winget source updates** for package changes

### Error Handling
Common issues:
- **Winget not installed:** Deploy winget via Intune
- **Package not found:** Verify package ID on [winget.run](https://winget.run)
- **Update fails:** Check application is not in use

---

## Prerequisites

### Client Requirements
- **Windows 10 1809+** or **Windows 11**
- **App Installer** (includes winget) - Auto-installed on modern Windows
- **Internet connectivity** to winget repository

### Intune Requirements
- **Microsoft Intune license**
- **Remediations** add-on (included in some licenses)
- Devices must be **Azure AD joined** or **Hybrid joined**

### Permissions
- Scripts run as **SYSTEM** (no user permissions needed)
- Requires **Intune Administrator** or **Endpoint Security Manager** role

---

## Related Scripts

- **[Update-AllAppsWinget.ps1](../scripts/utilities/Update-AllAppsWinget.ps1)** - System-wide winget updater
- **[Update-DotNetRuntimes.ps1](../scripts/utilities/Update-DotNetRuntimes.ps1)** (v2.5) - .NET runtime maintenance with interactive menu, EOL detection, and security-hardened updates
- **[Proactive Remediations](Proactive-Remediations.md)** - Other auto-fix scripts

---

## Additional Resources

- **[Winget Documentation](https://learn.microsoft.com/windows/package-manager/)** - Official Microsoft docs
- **[Winget Package Search](https://winget.run)** - Find package IDs
- **[Intune Remediations](https://learn.microsoft.com/mem/intune/fundamentals/remediations)** - Microsoft Endpoint Manager docs
- **[Script Catalog](Script-Catalog.md)** - Browse all scripts
