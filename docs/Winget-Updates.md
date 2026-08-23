# Winget Updates

Automate application updates using Windows Package Manager (winget) with Intune Remediations.

## Overview

The **Winget Updates** collection provides 35 application script pairs for automatically updating applications via winget in Microsoft Intune. Each application has dedicated scripts that:
- **Detect** if an update is available
- **Remediate** by installing the latest version
- Support **forced close** options for active applications
- Work with **maintenance windows** for minimal user disruption

**Location:** `scripts/endpoints/remediation/winget/`

---

## Available Applications

### Browsers
| Application | Package ID | Scripts |
|-------------|-----------|---------|
| **Google Chrome** | `Google.Chrome` | [Test-WingetGoogleChrome.ps1](../scripts/endpoints/remediation/winget/browsers/GoogleChrome/Test-WingetGoogleChrome.ps1) / [Invoke-WingetGoogleChrome.ps1](../scripts/endpoints/remediation/winget/browsers/GoogleChrome/Invoke-WingetGoogleChrome.ps1) |
| **Mozilla Firefox** | `Mozilla.Firefox` | [Test-WingetFirefox.ps1](../scripts/endpoints/remediation/winget/browsers/Firefox/Test-WingetFirefox.ps1) / [Invoke-WingetFirefox.ps1](../scripts/endpoints/remediation/winget/browsers/Firefox/Invoke-WingetFirefox.ps1) |

### Development Tools
| Application | Package ID | Scripts |
|-------------|-----------|---------|
| **Visual Studio Code** | `Microsoft.VisualStudioCode` | [Test-WingetVisualStudioCode.ps1](../scripts/endpoints/remediation/winget/development/VisualStudioCode/Test-WingetVisualStudioCode.ps1) / [Invoke-WingetVisualStudioCode.ps1](../scripts/endpoints/remediation/winget/development/VisualStudioCode/Invoke-WingetVisualStudioCode.ps1) |
| **PowerShell 7** | `Microsoft.PowerShell` | [Test-WingetPowerShell7.ps1](../scripts/endpoints/remediation/winget/development/PowerShell7/Test-WingetPowerShell7.ps1) / [Invoke-WingetPowerShell7MaintenanceWindow.ps1](../scripts/endpoints/remediation/winget/development/PowerShell7/Invoke-WingetPowerShell7MaintenanceWindow.ps1) |
| **Git** | `Git.Git` | [Test-WingetGit.ps1](../scripts/endpoints/remediation/winget/development/Git/Test-WingetGit.ps1) / [Invoke-WingetGit.ps1](../scripts/endpoints/remediation/winget/development/Git/Invoke-WingetGit.ps1) |
| **Azure CLI** | `Microsoft.AzureCLI` | [Test-WingetAzureCLI.ps1](../scripts/endpoints/remediation/winget/development/AzureCLI/Test-WingetAzureCLI.ps1) / [Invoke-WingetAzureCLI.ps1](../scripts/endpoints/remediation/winget/development/AzureCLI/Invoke-WingetAzureCLI.ps1) |

### Productivity
| Application | Package ID | Scripts |
|-------------|-----------|---------|
| **Microsoft Teams** | `Microsoft.Teams` | [Test-WingetMicrosoftTeams.ps1](../scripts/endpoints/remediation/winget/productivity/MicrosoftTeams/Test-WingetMicrosoftTeams.ps1) / [Invoke-WingetMicrosoftTeams.ps1](../scripts/endpoints/remediation/winget/productivity/MicrosoftTeams/Invoke-WingetMicrosoftTeams.ps1) |
| **Adobe Reader (64-bit)** | `Adobe.Acrobat.Reader.64-bit` | [Test-WingetAdobeReader64bit.ps1](../scripts/endpoints/remediation/winget/productivity/AdobeReader64bit/Test-WingetAdobeReader64bit.ps1) / [Invoke-WingetAdobeReader64bit.ps1](../scripts/endpoints/remediation/winget/productivity/AdobeReader64bit/Invoke-WingetAdobeReader64bit.ps1) |
| **Notepad++** | `Notepad++.Notepad++` | [Test-WingetNotepadPlusPlus.ps1](../scripts/endpoints/remediation/winget/productivity/NotepadPlusPlus/Test-WingetNotepadPlusPlus.ps1) / [Invoke-WingetNotepadPlusPlus.ps1](../scripts/endpoints/remediation/winget/productivity/NotepadPlusPlus/Invoke-WingetNotepadPlusPlus.ps1) |

### Communication
| Application | Package ID | Scripts |
|-------------|-----------|---------|
| **Zoom** | `Zoom.Zoom` | [Test-WingetZoom.ps1](../scripts/endpoints/remediation/winget/media/Zoom/Test-WingetZoom.ps1) / [Invoke-WingetZoom.ps1](../scripts/endpoints/remediation/winget/media/Zoom/Invoke-WingetZoom.ps1) |
| **Slack** | `SlackTechnologies.Slack` | [Test-WingetSlack.ps1](../scripts/endpoints/remediation/winget/communication/Slack/Test-WingetSlack.ps1) / [Invoke-WingetSlack.ps1](../scripts/endpoints/remediation/winget/communication/Slack/Invoke-WingetSlack.ps1) |
| **Discord** | `Discord.Discord` | [Test-WingetDiscord.ps1](../scripts/endpoints/remediation/winget/communication/Discord/Test-WingetDiscord.ps1) / [Invoke-WingetDiscord.ps1](../scripts/endpoints/remediation/winget/communication/Discord/Invoke-WingetDiscord.ps1) |

### Remote Access
| Application | Package ID | Scripts |
|-------------|-----------|---------|
| **TeamViewer (Full)** | `TeamViewer.TeamViewer` | [Test-WingetTeamViewerFull.ps1](../scripts/endpoints/remediation/winget/remote-access/TeamViewerFull/Test-WingetTeamViewerFull.ps1) / [Invoke-WingetTeamViewerFull.ps1](../scripts/endpoints/remediation/winget/remote-access/TeamViewerFull/Invoke-WingetTeamViewerFull.ps1) |
| **WinSCP** | `WinSCP.WinSCP` | [Test-WingetWinSCP.ps1](../scripts/endpoints/remediation/winget/remote-access/WinSCP/Test-WingetWinSCP.ps1) / [Invoke-WingetWinSCP.ps1](../scripts/endpoints/remediation/winget/remote-access/WinSCP/Invoke-WingetWinSCP.ps1) |

### Runtimes
| Application | Package ID | Scripts |
|-------------|-----------|---------|
| **Visual C++ 2015-2022 (x64)** | `Microsoft.VCRedist.2015+.x64` | [Test-WingetCpp20152019RedistX64.ps1](../scripts/endpoints/remediation/winget/runtimes/Cpp2015-2019Redist-x64/Test-WingetCpp20152019RedistX64.ps1) / [Invoke-WingetCpp20152019RedistX64.ps1](../scripts/endpoints/remediation/winget/runtimes/Cpp2015-2019Redist-x64/Invoke-WingetCpp20152019RedistX64.ps1) |
| **Microsoft Edge WebView2** | `Microsoft.EdgeWebView2Runtime` | [Test-WingetEdgeWebView2.ps1](../scripts/endpoints/remediation/winget/runtimes/EdgeWebView2/Test-WingetEdgeWebView2.ps1) / [Invoke-WingetEdgeWebView2.ps1](../scripts/endpoints/remediation/winget/runtimes/EdgeWebView2/Invoke-WingetEdgeWebView2.ps1) |

**Complete list:** Browse the [winget directory](../scripts/endpoints/remediation/winget/README.md) for all 35 applications.

---

## How It Works

### Detection Script (`Test-Winget<App>.ps1`)
Checks if an update is available:
```powershell
# Example: Check if VS Code update available
winget list --id Microsoft.VisualStudioCode --exact
# Exit 1 if update available (triggers remediation)
# Exit 0 if up to date (no action needed)
```

### Remediation Script (`Invoke-Winget<App>.ps1`)
Installs the latest version:
```powershell
# Example: Update VS Code
winget upgrade --id Microsoft.VisualStudioCode --exact --silent --accept-source-agreements
```

### Script Variants

Most applications ship a single `Test-`/`Invoke-` pair. Where user impact requires it, dedicated variants exist:

| Variant | Description | Use Case |
|---------|-------------|----------|
| **Invoke-Winget<App>.ps1** | Standard update | App not running or can wait |
| **Invoke-WingetTeamViewerFullForceClose.ps1** | Force close before update | Update during business hours |
| **Invoke-WingetPowerShell7MaintenanceWindow.ps1** | Scheduled update | Update outside business hours |

---

## Deployment to Intune

### Step 1: Create Remediation
1. Navigate to **Endpoint Manager** → **Devices** → **Remediations**
2. Click **Create script package**
3. Configure:
   - **Name:** "Winget - Update Google Chrome"
   - **Detection script:** Upload `Test-WingetGoogleChrome.ps1`
   - **Remediation script:** Upload `Invoke-WingetGoogleChrome.ps1`
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
# Update all winget-managed applications (installs dependencies if needed)
.\Update-AllAppsWinget.ps1

# With custom log path and retry count
.\Update-AllAppsWinget.ps1 -LogPath "C:\Logs\winget-updates.log" -MaxRetries 5

# Skip dependency installation if already configured
.\Update-AllAppsWinget.ps1 -SkipDependencyCheck
```

**Features:**
- Updates all installed applications
- Automatic winget configuration detection and setup
- Installs VCLibs and UI.Xaml dependencies if needed
- Comprehensive logging (`-LogPath`) and error handling
- Runs in SYSTEM context (suitable for scheduled tasks)

---

## Creating Custom Templates

Use the template generator to create scripts for new applications:

**`scripts/endpoints/remediation/winget/_generate-winget-scripts.ps1`**

The generator takes no parameters. Instead, add an entry to the `$AppDefinitions` array at the top of the script, then run it:

```powershell
# 1. Edit $AppDefinitions in _generate-winget-scripts.ps1:
#    @{ WingetId = 'NewVendor.NewApp'; Category = 'utilities'; FolderName = 'NewApp'; ForceClose = $false; NotifySeconds = 0 }
#
# 2. Run the generator (creates detect.ps1/remediate.ps1-style pair from the v3 templates):
.\_generate-winget-scripts.ps1
```

Templates are located in: `scripts/endpoints/remediation/winget/_templates/`

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
