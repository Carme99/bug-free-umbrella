# Proactive Remediation Library

A collection of ready-to-deploy Intune proactive remediation scripts for common Windows device issues.

## 📋 Overview

This library provides 6 detect/remediate script pairs that automatically identify and fix common device issues:

| Remediation | Purpose | Detection Criteria | Remediation Action |
|-------------|---------|-------------------|-------------------|
| **Fix-DiskSpace** | Low disk space | <10% or <10GB free | Clean temp files, recycle bin, WU cache |
| **Fix-TempFiles** | Excessive temp files | >1GB of old temp files | Delete files >7 days old |
| **Fix-StaleProfiles** | Old user profiles | Profiles >90 days old | Remove profiles >120 days old |
| **Fix-WindowsUpdateStuck** | Stuck Windows Update | WU service issues | Reset WU components |
| **Fix-BitLockerNotEscrowedKeys** | BitLocker key backup | Keys not in Azure AD | Backup recovery keys |
| **Check-SecurityBaseline** | Security drift | Firewall, Defender, UAC issues | Enable security features |

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
| Run script in 64-bit PowerShell | Yes |

### Schedule Recommendations

| Remediation | Frequency |
|-------------|-----------|
| Fix-DiskSpace | Daily |
| Fix-TempFiles | Daily |
| Fix-StaleProfiles | Weekly |
| Fix-WindowsUpdateStuck | Hourly |
| Fix-BitLockerNotEscrowedKeys | Daily |
| Check-SecurityBaseline | Every 4 hours |

## 📖 Detailed Descriptions

### 1. Fix-DiskSpace

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
    Updated: 2024-12-23
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

**Version**: 1.0
**Last Updated**: 2024-12-23
**Compatible**: Windows 10/11, Windows Server 2016+
