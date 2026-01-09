# Proactive Remediation Library


> **⚠️ IMPORTANT NOTICE**: The vast majority of scripts in this repository have not been thoroughly tested in production environments. Please test all scripts in a non-production environment first and validate the results before relying on this data for operational decisions.

A collection of ready-to-deploy Intune proactive remediation scripts for common Windows device issues.

## 📋 Overview

This library provides **50 detect/remediate script pairs** that automatically identify and fix common device issues, organized by category:

### 🔒 Security & Compliance (6 remediations)
| Remediation | Purpose | Detection Criteria | Remediation Action |
|-------------|---------|-------------------|-------------------|
| **Check-SecurityBaseline** | Security drift | Firewall, Defender, UAC issues | Enable security features |
| **Fix-BitLockerNotEscrowedKeys** | BitLocker key backup | Keys not in Azure AD | Backup recovery keys |
| **Check-DefenderHealthStatus** | Defender health | Service down, outdated signatures | Start service, update signatures |
| **Check-TPMStatus** | TPM health | TPM not enabled/activated | Initialize TPM (BIOS may be required) |
| **Check-LocalAdminAccounts** | Unauthorized admins | Unauthorized local admin accounts | Disable built-in admin account |
| **Fix-PowerShellExecutionPolicy** | PowerShell policy | Policy not RemoteSigned | Set appropriate execution policy |

### 💾 Storage & Performance (9 remediations)
| Remediation | Purpose | Detection Criteria | Remediation Action |
|-------------|---------|-------------------|-------------------|
| **Fix-DiskSpace** | Low disk space | <10% or <10GB free | Clean temp files, recycle bin, WU cache |
| **Fix-TempFiles** | Excessive temp files | >1GB of old temp files | Delete files >7 days old |
| **Fix-StaleProfiles** | Old user profiles | Profiles >90 days old | Remove profiles >120 days old |
| **Fix-EventLogSize** | Bloated event logs | Logs >100MB | Clear non-critical logs |
| **Fix-EdgeCacheSize** | Bloated Edge cache | Cache >500MB | Clear Edge browser cache |
| **Check-DiskHealth** | Disk errors | SMART errors, disk issues | Schedule disk check, optimize volumes |
| **Fix-StartMenuLayout** | Corrupted Start Menu | Start Menu not opening | Rebuild tile database |
| **Check-PageFileConfiguration** 🆕 | Page file disabled/misconfigured | Page file too small or disabled | Enable system-managed page file |
| **Check-MemoryDiagnostics** 🆕 | RAM errors in event logs | Memory errors detected | Schedule memory diagnostic on reboot |

### 🔄 System Services (13 remediations)
| Remediation | Purpose | Detection Criteria | Remediation Action |
|-------------|---------|-------------------|-------------------|
| **Fix-WindowsUpdateStuck** | Stuck Windows Update | WU service issues | Reset WU components |
| **Fix-TimeSync** | Time sync issues | W32Time not running/syncing | Configure and sync time service |
| **Fix-PrintSpooler** | Print spooler issues | Spooler stuck/not running | Restart spooler, clear queue |
| **Fix-TeamsCache** | Teams cache issues | Teams cache corrupted | Clear Teams cache |
| **Fix-WindowsSearch** | Search index issues | Search not working | Rebuild search index |
| **Fix-DNSCache** | DNS resolution issues | Stale DNS cache | Flush DNS cache |
| **Fix-WindowsStoreLicensing** | Store licensing issues | ClipSVC not running | Reset Store license cache |
| **Fix-OutdatedDrivers** | Driver updates | Critical driver updates available | Install driver updates |
| **Fix-WindowsPerformanceRecorder** 🆕 | Stuck WPR/ETW sessions | Orphaned tracing sessions causing high CPU | Stop stuck performance recorder sessions |
| **Fix-TaskSchedulerCorruption** 🆕 | Task Scheduler issues | Service not running, database corrupt | Restart Task Scheduler service |
| **Check-MicrosoftStoreAppsHealth** 🆕 | AppX registration errors | Store apps in error state | Re-register AppX packages |
| **Fix-SystemFileCorruption** 🆕 | Corrupted system files | SFC/DISM detect corruption | Run DISM RestoreHealth and SFC |
| **Fix-WindowsUpdateRebootPending** 🆕 | Stuck reboot pending state | Reboot flags stuck >7 days | Clear false positive reboot flags |

### 🌐 Network & Connectivity (3 remediations)
| Remediation | Purpose | Detection Criteria | Remediation Action |
|-------------|---------|-------------------|-------------------|
| **Fix-NetworkAdapterPowerManagement** | Network disconnects | Adapters allow power saving | Disable adapter power management |
| **Fix-SMBv1Protocol** | SMBv1 security risk | SMBv1 enabled | Disable insecure SMBv1 protocol |
| **Check-SharedFolders** | Unauthorized shares | Unauthorized network shares | Remove unauthorized shares |

### 📱 Apps & Licensing (6 remediations)
| Remediation | Purpose | Detection Criteria | Remediation Action |
|-------------|---------|-------------------|-------------------|
| **Fix-OneDriveKnownFolderMove** | OneDrive KFM issues | OneDrive not running/syncing | Restart OneDrive, configure KFM |
| **Fix-CredentialManager** | Stale credentials | Orphaned credentials | Remove stale credentials |
| **Fix-WindowsLicenseActivation** | Windows activation | Windows not activated | Trigger online activation |
| **Fix-BrokenShortcuts** | Broken shortcuts | Invalid .lnk files | Remove broken shortcuts |
| **Check-WindowsActivationGracePeriod** 🆕 | Activation expiring | Grace period <30 days | Trigger activation before expiry |
| **Check-BatteryHealth** 🆕 | Battery degradation (laptops) | Capacity <70% of design | Report battery health for replacement |

### 🌍 Regional & Localization (3 remediations)
| Remediation | Purpose | Detection Criteria | Remediation Action |
|-------------|---------|-------------------|-------------------|
| **region-language-settings** | UK regional settings | Culture, locale, time zone not en-GB/GMT | Set UK region, locale, and GMT time zone |
| **keyboard-layout** | UK keyboard layout | Keyboard not UK English | Set UK keyboard as primary input method |
| **language-pack-audit** | Unnecessary language packs | Non-UK language packs installed | Remove unnecessary language packs |

### 🆕 Certificate Management (1 remediation)
| Remediation | Purpose | Detection Criteria | Remediation Action |
|-------------|---------|-------------------|-------------------|
| **Fix-CertificateExpiry** | Expired certificates | Expired or expiring certs | Remove expired certificates |

### 📊 Device Health & Uptime Monitoring (8 remediations)
| Remediation | Purpose | Detection Criteria | Remediation Action |
|-------------|---------|-------------------|-------------------|
| **Check-DeviceUptime** 🆕 | Excessive uptime tracking | Uptime >14 days or pending reboots | Log for IT review, recommend reboot |
| **Check-UnexpectedReboots** 🆕 | Crash and BSOD tracking | Unexpected reboots, bugchecks, crash dumps | Log for IT investigation |
| **Check-SystemStabilityIndex** 🆕 | Windows Reliability Monitor score | Stability index <5.0 | Provide stability improvement guidance |
| **Check-BootPerformance** 🆕 | Slow boot detection | Boot time >120 seconds | Optimize startup programs |
| **Check-ServiceFailures** 🆕 | Service crash monitoring | Service crashes/failures >3 events | Restart critical services |
| **Check-ApplicationCrashes** 🆕 | Application crash tracking | App crashes >10 events/week | Provide troubleshooting guidance |
| **Check-SystemEventErrors** 🆕 | Critical system events | Critical errors in System log | Flag for urgent IT investigation |
| **Check-HardwareErrors** 🆕 | Hardware failure detection | WHEA errors, disk SMART failures | URGENT: Flag for hardware replacement |
| **Check-DeviceHealthScore** 🆕 | Comprehensive health scoring | Overall health score <70/100 | Prioritized improvement plan |

## 🚀 Deployment

### Via Intune Portal

1. Go to **Devices** > **Remediations** > **Create script package**
2. Upload the detect.ps1 and remediate.ps1 scripts
3. Configure schedule and assignments
4. Deploy to device groups

### Recommended Settings

| Setting | Value |
|---------|-------|
| Run script in 64-bit PowerShell | Yes |
| Run this script using logged-on credentials | No (run as SYSTEM) |
| Enforce script signature check | No (unless you sign the scripts) |

### Schedule Recommendations

| Remediation | Frequency | Priority |
|-------------|-----------|----------|
| **Security & Compliance** |
| Check-DefenderHealthStatus | Every 4 hours | High |
| Check-SecurityBaseline | Every 4 hours | High |
| Fix-BitLockerNotEscrowedKeys | Daily | High |
| Check-TPMStatus | Daily | Medium |
| Check-LocalAdminAccounts | Daily | High |
| Fix-PowerShellExecutionPolicy | Daily | Medium |
| **System Critical** |
| Fix-TimeSync | Every 4 hours | Critical |
| Fix-WindowsUpdateStuck | Hourly | High |
| Fix-NetworkAdapterPowerManagement | Daily | High |
| Test-IntuneConnectivity | Daily | High |
| **Storage & Maintenance** |
| Fix-DiskSpace | Daily | High |
| Fix-TempFiles | Daily | Medium |
| Fix-EventLogSize | Weekly | Medium |
| Fix-StaleProfiles | Weekly | Medium |
| Check-DiskHealth | Daily | High |
| **Applications & Services** |
| Fix-OneDriveKnownFolderMove | Daily | High |
| Fix-EdgeCacheSize | Weekly | Low |
| Fix-WindowsStoreLicensing | Daily | Medium |
| Fix-StartMenuLayout | Daily | Medium |
| **Network & Security** |
| Fix-SMBv1Protocol | Once (until compliant) | Critical |
| Check-SharedFolders | Daily | High |
| **Certificates & Licensing** |
| Fix-CertificateExpiry | Daily | High |
| Fix-WindowsLicenseActivation | Daily | High |
| **Regional Settings** |
| region-language-settings | Once or Daily | Low |
| keyboard-layout | Once or Daily | Low |
| language-pack-audit | Weekly | Low |
| **Periodic Maintenance** |
| Fix-CredentialManager | Weekly | Low |
| Fix-OutdatedDrivers | Weekly | Medium |
| Fix-PrintSpooler | As needed | Medium |
| Fix-TeamsCache | As needed | Low |
| Fix-WindowsSearch | As needed | Low |
| Fix-DNSCache | As needed | Medium |
| Fix-BrokenShortcuts | Weekly | Low |
| **Device Health & Uptime Monitoring** 🆕 |
| Check-DeviceHealthScore | Daily | High |
| Check-DeviceUptime | Daily | Medium |
| Check-UnexpectedReboots | Daily | High |
| Check-SystemStabilityIndex | Daily | Medium |
| Check-BootPerformance | Daily | Medium |
| Check-ServiceFailures | Daily | Medium |
| Check-ApplicationCrashes | Daily | Medium |
| Check-SystemEventErrors | Daily | High |
| Check-HardwareErrors | Daily | Critical |

## 📖 Detailed Descriptions

### High-Priority Remediations

#### Check-DefenderHealthStatus
**Detects**: Windows Defender service status, real-time protection, signature age (>7 days), scan status
**Remediates**: Starts Defender service, enables real-time protection, updates signatures, initiates quick scan
**Safe**: Yes - only enables security features
**Critical**: Ensures endpoint protection is active

#### Fix-TimeSync
**Detects**: W32Time service status, time sync configuration, last sync time (>24 hours)
**Remediates**: Starts W32Time, configures time.windows.com, forces sync
**Safe**: Yes - critical for Kerberos authentication
**Critical**: Required for domain authentication and certificate validation

#### Fix-NetworkAdapterPowerManagement
**Detects**: Network adapters with "Allow computer to turn off device" enabled
**Remediates**: Disables power management on all physical network adapters
**Safe**: Yes - prevents network disconnects
**Critical**: Prevents devices from losing Intune connection

#### Check-TPMStatus
**Detects**: TPM presence, enabled status, activation, ownership
**Remediates**: Attempts to initialize and take ownership of TPM
**Safe**: Mostly - some issues require BIOS configuration
**Note**: TPM required for BitLocker and Windows 11

#### Fix-OneDriveKnownFolderMove
**Detects**: OneDrive running status, Known Folder Move configuration
**Remediates**: Starts OneDrive, configures KFM registry settings
**Safe**: Yes - works with Intune policies
**Note**: Full KFM requires Intune policy configuration

### Storage & Performance

#### Fix-DiskSpace

**Detects**: Drives with less than 10% or 10GB free space

**Remediates**:
- Cleans Windows temp folder (files >7 days old)
- Empties recycle bin
- Clears Windows Update download cache
- Reports total space recovered

**Safe**: Yes - only removes temp files and caches

### 2. Fix-TempFiles

**Detects**: More than 1GB of temporary files older than 7 days

**Remediates**:
- Cleans user temp folder
- Cleans system temp folder
- Only removes files >7 days old

**Safe**: Yes - preserves recent temp files

### 3. Fix-StaleProfiles

**Detects**: User profiles not accessed in 90+ days

**Remediates**:
- Removes profiles not accessed in 120+ days
- Excludes system profiles (Public, Default, etc.)
- Reports space recovered

**Safe**: Use with caution - test on pilot group first

### 4. Fix-WindowsUpdateStuck

**Detects**:
- Windows Update service not running
- Pending updates stuck for extended periods

**Remediates**:
- Stops WU services
- Renames SoftwareDistribution folder
- Renames catroot2 folder
- Restarts WU services

**Safe**: Yes - standard WU troubleshooting procedure

### 5. Fix-BitLockerNotEscrowedKeys

**Detects**: BitLocker recovery keys not backed up to Azure AD

**Remediates**:
- Backs up recovery keys to Azure AD
- Reports keys successfully escrowed

**Safe**: Yes - only backs up keys, doesn't change encryption

### 6. Check-SecurityBaseline

**Detects**:
- Disabled firewall profiles
- Real-time protection disabled
- Outdated antivirus signatures (>7 days)
- UAC disabled
- Automatic updates disabled

**Remediates**:
- Enables all firewall profiles
- Enables real-time protection
- Updates antivirus signatures
- Enables UAC
- Re-enables automatic updates (if safe)

**Safe**: Generally yes - enforces security best practices

## 🔧 Customization

### Adjusting Thresholds

Each script includes configurable thresholds at the top of the file:

```powershell
# Example: Fix-DiskSpace/detect.ps1
$threshold = 10  # Percentage
$minGB = 10      # Minimum GB

# Example: Fix-StaleProfiles/detect.ps1
$threshold = 90  # Days for detection
# remediate.ps1 uses 120 days (more conservative)
```

### Adding Custom Logic

You can extend scripts with additional checks or actions:

```powershell
# Add to detect.ps1
if($customCondition) {
    Write-Host "Custom issue detected"
    exit 1
}

# Add to remediate.ps1
# Perform custom remediation
Write-Host "Custom remediation applied"
```

## 📊 Monitoring

### Viewing Results

1. Go to **Devices** > **Remediations**
2. Select your remediation package
3. View **Device status** tab for:
   - Detection results
   - Remediation success/failure
   - Output messages

### Success Criteria

| Exit Code | Detection | Remediation |
|-----------|-----------|-------------|
| 0 | Issue not detected | Remediation successful |
| 1 | Issue detected | Remediation failed |

## ⚠️ Important Notes

### Testing

Always test remediations on a pilot group before wide deployment:
1. Create a test device group (5-10 devices)
2. Deploy remediation
3. Monitor for 1-2 weeks
4. Verify no adverse effects
5. Expand deployment

### Permissions

All scripts run in SYSTEM context and have full admin rights. Ensure:
- Scripts are from trusted sources
- Review code before deployment
- Test thoroughly
- Monitor for unexpected behavior

### Logging

Intune captures all Write-Host output. Use descriptive messages:

```powershell
Write-Host "Fixed 5.2 GB disk space by cleaning temp files"
Write-Host "Remediation failed: Access denied to C:\Windows\Temp"
```

## 🔄 Updates and Maintenance

### Version Control

Track script versions with comments:

```powershell
<#
.NOTES
    Version: 1.1
    Changes: Added additional temp folder cleanup
#>
```

### Regular Reviews

Review remediation effectiveness monthly:
- Check detection rates
- Review remediation success rates
- Adjust thresholds as needed
- Update for new Windows versions

## 📚 Additional Resources

- [Microsoft Intune Remediations Documentation](https://docs.microsoft.com/en-us/mem/intune/fundamentals/remediations)
- [PowerShell Exit Codes](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_exit)
- [Windows Cleanup Best Practices](https://docs.microsoft.com/en-us/windows/deployment/update/windows-update-troubleshooting)

## 🤝 Contributing

To add new remediations:
1. Create a new folder with descriptive name
2. Add detect.ps1 and remediate.ps1
3. Include detailed comments
4. Test thoroughly
5. Update this README

---

**Version**: 3.1
**Total Remediations**: 50 detect/remediate pairs
**Compatible**: Windows 10/11, Windows Server 2016+
**Last Updated**: January 2026

## 🤖 Development

Scripts in this repository were created with the assistance of **[Claude Code](https://github.com/anthropics/claude-code)**, Anthropic's official CLI for Claude AI.
