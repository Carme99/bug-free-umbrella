# Script Recipes - Quick Command Reference

A cookbook of common IT tasks with ready-to-run commands. Copy, customize, and execute!

## 🎯 Quick Navigation

- [Microsoft 365 & Exchange](#microsoft-365--exchange)
- [Intune & Device Management](#intune--device-management)
- [Security & Compliance](#security--compliance)
- [Server Monitoring & Health](#server-monitoring--health)
- [User Management](#user-management)
- [Azure & Cloud](#azure--cloud)
- [Backup & Recovery](#backup--recovery)
- [Active Directory](#active-directory)
- [Reporting & Auditing](#reporting--auditing)

---

## Microsoft 365 & Exchange

### Get comprehensive user information
```powershell
.\scripts\collaboration\microsoft365\Get-M365UserInfo.ps1 -UserPrincipalName "user@company.com"
```

### Clean up quarantined spam emails
```powershell
.\scripts\collaboration\microsoft365\exchange-online\Manage-QuarantinedEmails.ps1 -Action Delete -OlderThanDays 30
```

### Review quarantined emails before deletion
```powershell
.\scripts\collaboration\microsoft365\exchange-online\Manage-QuarantinedEmails.ps1 -Action List -ExportToCSV
```

### Check mailbox health and size
```powershell
.\scripts\collaboration\microsoft365\exchange-online\Get-MailboxHealth.ps1 -UserPrincipalName "user@company.com"
```

### Audit shared mailbox permissions
```powershell
.\scripts\collaboration\microsoft365\exchange-online\Get-SharedMailboxReport.ps1 -ExportHTML
```

### Find suspicious mail rules
```powershell
.\scripts\collaboration\microsoft365\exchange-online\Get-UserMailRules.ps1 -CheckForSuspicious
```

### Analyze mail flow issues
```powershell
.\scripts\collaboration\microsoft365\exchange-online\Get-MailFlowAnalysis.ps1 -Days 7
```

### Get Microsoft 365 license usage
```powershell
.\scripts\collaboration\microsoft365\azure-ad\Get-AzureADLicenseReport.ps1 -ExportToCSV
```

### Audit guest users in Azure AD
```powershell
.\scripts\collaboration\microsoft365\azure-ad\Get-AzureADGuestAudit.ps1 -IncludeInactive
```

### Get Teams usage report
```powershell
.\scripts\collaboration\microsoft365\teams\Get-TeamsReport.ps1 -ReportType Activity -Days 30
```

### Get OneDrive storage usage
```powershell
.\scripts\collaboration\microsoft365\sharepoint-onedrive\Get-OneDriveUsageReport.ps1 -ExportHTML
```

### Check Defender for Office 365 threats
```powershell
.\scripts\collaboration\microsoft365\defender-office365\Get-DefenderO365ThreatReport.ps1 -Days 7
```

---

## Intune & Device Management

### Get device compliance status report
```powershell
.\scripts\endpoints\intune\reporting\Get-DeviceComplianceReport.ps1 -ExportHTML
```

### Find only non-compliant devices
```powershell
.\scripts\endpoints\intune\reporting\Get-DeviceComplianceReport.ps1 -ComplianceState NonCompliant
```

### Check BitLocker encryption status
```powershell
.\scripts\endpoints\intune\reporting\Get-BitLockerStatus.ps1 -ExportToCSV
```

### Find stale/inactive devices
```powershell
.\scripts\endpoints\intune\maintenance\Find-StaleDevices.ps1 -InactiveDays 90
```

### Check Windows Update compliance
```powershell
.\scripts\endpoints\intune\reporting\Get-WindowsUpdateCompliance.ps1 -ExportHTML
```

### Get Winget update compliance
```powershell
.\scripts\endpoints\intune\reporting\Get-WingetUpdateCompliance.ps1 -ShowOutdated
```

### Audit Autopilot deployment status
```powershell
.\scripts\endpoints\intune\reporting\Get-AutopilotDeploymentReport.ps1 -Last30Days
```

### Export Intune configuration for backup
```powershell
.\scripts\endpoints\intune\maintenance\Export-IntuneConfiguration.ps1 -ExportPath "C:\Backup\Intune"
```

### Find policy conflicts
```powershell
.\scripts\endpoints\intune\maintenance\Find-PolicyConflicts.ps1 -DeviceId "device-id-here"
```

### Check configuration drift
```powershell
.\scripts\endpoints\intune\maintenance\Compare-ConfigurationDrift.ps1 -BaselineDate "2025-01-01"
```

### Perform bulk device actions
```powershell
.\scripts\endpoints\intune\maintenance\Invoke-DeviceBulkActions.ps1 -Action Sync -DeviceIds @("id1", "id2")
```

### Test Intune connectivity
```powershell
.\scripts\endpoints\intune\maintenance\Test-IntuneConnectivity.ps1 -Verbose
```

### Get policy assignment report
```powershell
.\scripts\endpoints\intune\reporting\Get-PolicyAssignmentReport.ps1 -PolicyType All -ExportHTML
```

### Get device group membership
```powershell
.\scripts\endpoints\intune\reporting\Get-DeviceGroupMembership.ps1 -DeviceName "DESKTOP-ABC123"
```

---

## Security & Compliance

### Run comprehensive security scan (CIS Benchmark)
```powershell
.\scripts\security\compliance\frameworks\Invoke-SecurityComplianceScan.ps1 -Framework CIS -ExportHTML
```

### Run NIST compliance scan
```powershell
.\scripts\security\compliance\frameworks\Invoke-SecurityComplianceScan.ps1 -Framework NIST -Detailed
```

### Run HIPAA compliance check
```powershell
.\scripts\security\compliance\frameworks\Invoke-SecurityComplianceScan.ps1 -Framework HIPAA
```

### Check antivirus status
```powershell
.\scripts\security\compliance\frameworks\Get-AntivirusStatus.ps1 -ComputerName SERVER01
```

### Find expiring certificates (next 30 days)
```powershell
.\scripts\security\compliance\frameworks\Get-ExpiredCertificates.ps1 -DaysBeforeExpiration 30
```

### Audit failed login attempts
```powershell
.\scripts\security\compliance\frameworks\Get-FailedLoginReport.ps1 -Hours 24 -ExportHTML
```

### Audit local administrator accounts
```powershell
.\scripts\security\compliance\frameworks\Get-LocalAdminAudit.ps1 -ExportToCSV
```

### Scan for open ports
```powershell
.\scripts\security\compliance\frameworks\Get-OpenPortScan.ps1 -ComputerName SERVER01
```

### Check security baseline compliance
```powershell
.\scripts\security\compliance\frameworks\Get-SecurityBaseline.ps1 -BaselineType Microsoft
```

### Test security features (Firewall, Defender, etc.)
```powershell
.\scripts\security\compliance\frameworks\Test-SecurityFeatures.ps1 -Verbose
```

### Audit USB device usage
```powershell
.\scripts\security\compliance\frameworks\Get-USBDeviceAudit.ps1 -Days 30
```

### Check software license compliance
```powershell
.\scripts\security\compliance\frameworks\Get-SoftwareLicenseCompliance.ps1 -ExportHTML
```

---

## Server Monitoring & Health

### Run comprehensive server health check
```powershell
.\scripts\infrastructure\windows\monitoring\Monitor-ServerHealth.ps1 -ComputerName SERVER01 -CheckAll
```

### Quick health check (fast)
```powershell
.\scripts\infrastructure\windows\monitoring\Monitor-ServerHealth.ps1 -QuickCheck
```

### Check disk space only
```powershell
.\scripts\infrastructure\windows\monitoring\Monitor-ServerHealth.ps1 -CheckDiskSpace -WarningThresholdGB 50
```

### Check certificate expiration
```powershell
.\scripts\infrastructure\windows\monitoring\Monitor-ServerHealth.ps1 -CheckCertificates -DaysBeforeExpiration 30
```

### Check Windows Update status
```powershell
.\scripts\infrastructure\windows\monitoring\Monitor-ServerHealth.ps1 -CheckWindowsUpdate
```

### Get performance metrics report
```powershell
.\scripts\infrastructure\windows\monitoring\Get-PerformanceReport.ps1 -ComputerName SERVER01 -Duration 60
```

### Get event log errors (last 24 hours)
```powershell
.\scripts\infrastructure\windows\monitoring\Get-EventLogReport.ps1 -Hours 24 -Level Error -ExportHTML
```

### Get critical and error events (last 7 days)
```powershell
.\scripts\infrastructure\windows\monitoring\Get-EventLogReport.ps1 -Hours 168 -Level Critical,Error
```

---

## User Management

### Get detailed mailbox permissions for a user
```powershell
.\scripts\collaboration\microsoft365\exchange-online\Get-UserMailboxPermissions.ps1 -UserPrincipalName "user@company.com"
```

### Audit distribution list membership
```powershell
.\scripts\collaboration\microsoft365\exchange-online\Get-DistributionListAudit.ps1 -ExportToCSV
```

### Set mailbox regional settings (bulk)
```powershell
.\scripts\collaboration\microsoft365\exchange-online\Set-MailboxRegionalSettings.ps1 -TimeZone "Pacific Standard Time" -Language "en-US"
```

### Set OneDrive regional settings
```powershell
.\scripts\collaboration\microsoft365\sharepoint-onedrive\Set-OneDriveRegionalSettings.ps1 -UserPrincipalName "user@company.com" -TimeZone "Pacific Standard Time"
```

### Set Teams regional settings
```powershell
.\scripts\collaboration\microsoft365\teams\Set-TeamsRegionalSettings.ps1 -UserPrincipalName "user@company.com" -Language "en-US"
```

### Set organization-wide defaults
```powershell
.\scripts\collaboration\microsoft365\azure-ad\Set-OrganizationDefaults.ps1 -TimeZone "Pacific Standard Time" -Language "en-US"
```

---

## Azure & Cloud

### Create Winget update packages for Intune
```powershell
.\scripts\endpoints\intune\deployment\New-BulkWingetUpdater.ps1 -AppIds @("Google.Chrome", "Mozilla.Firefox")
```

### Create Win32 app template
```powershell
.\scripts\endpoints\intune\deployment\New-Win32AppTemplate.ps1 -AppName "CustomApp" -Version "1.0"
```

### Package app as .intunewin
```powershell
.\scripts\endpoints\intune\deployment\New-IntuneWinPackage.ps1 -SourceFolder "C:\Apps\MyApp" -SetupFile "setup.exe"
```

### Export Winget package list
```powershell
.\scripts\endpoints\intune\deployment\Export-WingetPackageList.ps1 -ExportPath "C:\Exports\winget-packages.json"
```

---

## Backup & Recovery

### Export Intune configuration (full backup)
```powershell
.\scripts\endpoints\intune\maintenance\Export-IntuneConfiguration.ps1 -ExportPath "C:\Backup\Intune_$(Get-Date -Format 'yyyyMMdd')" -IncludeAll
```

---

## Active Directory

### Audit local administrator accounts across domain
```powershell
.\scripts\security\compliance\frameworks\Get-LocalAdminAudit.ps1 -ComputerName (Get-ADComputer -Filter *).Name -ExportToCSV
```

---

## Reporting & Auditing

### Generate monthly compliance audit
```powershell
# Use the example workflow
.\examples\compliance\monthly-compliance-audit.ps1 -EmailReport -SMTPServer "smtp.company.com" -To "compliance@company.com"
```

### Run weekly health checks
```powershell
# Use the example workflow
.\examples\maintenance\weekly-health-check.ps1 -EmailReport -SMTPServer "smtp.company.com" -To "it-team@company.com"
```

### New employee onboarding workflow
```powershell
# Use the example workflow
.\examples\onboarding\new-employee-setup.ps1 -EmployeeName "John Doe" -Department "Sales"
```

---

## 💡 Pro Tips

### Combine scripts for powerful workflows
```powershell
# Find non-compliant devices and export BitLocker status
$NonCompliant = .\scripts\endpoints\intune\reporting\Get-DeviceComplianceReport.ps1 -ComplianceState NonCompliant
$NonCompliant | ForEach-Object { .\scripts\endpoints\intune\reporting\Get-BitLockerStatus.ps1 -DeviceId $_.DeviceId }
```

### Schedule reports with Task Scheduler
```powershell
# Create a scheduled task for daily compliance report
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Scripts\Get-DeviceComplianceReport.ps1 -ExportHTML"
$Trigger = New-ScheduledTaskTrigger -Daily -At 8:00AM
Register-ScheduledTask -TaskName "Daily Compliance Report" -Action $Action -Trigger $Trigger
```

### Export to multiple formats
```powershell
# Most scripts support -ExportHTML, -ExportToCSV, or -ExportToJSON
.\scripts\endpoints\intune\reporting\Get-DeviceComplianceReport.ps1 -ExportHTML -ExportToCSV
```

### Use -Verbose for troubleshooting
```powershell
# Get detailed execution information
.\scripts\security\compliance\frameworks\Invoke-SecurityComplianceScan.ps1 -Framework CIS -Verbose
```

### Filter results with PowerShell pipeline
```powershell
# Get only critical certificate expirations
.\scripts\security\compliance\frameworks\Get-ExpiredCertificates.ps1 -DaysBeforeExpiration 30 | Where-Object { $_.DaysUntilExpiration -lt 7 }
```

---

## 📚 Additional Resources

- [Script Catalog](Script-Catalog.md) - Complete list of all scripts
- [Workflows Documentation](Workflows.md) - End-to-end process guides
- [Common Use Cases](Common-Use-Cases.md) - Task-oriented navigation
- [Examples Directory](../examples/README.md) - Real-world workflow examples
- [Troubleshooting Guide](Troubleshooting.md) - Common issues and solutions
- [FAQ](FAQ.md) - Frequently asked questions

---

## 🔍 Finding the Right Script

**Can't find what you need?** Try these approaches:

1. **Search by technology**: Check [Script Catalog](Script-Catalog.md)
2. **Search by task**: Check [Common Use Cases](Common-Use-Cases.md)
3. **Browse by category**: Explore the `/scripts/` directory structure
4. **Search file contents**: Use `Get-ChildItem -Recurse -Filter "*.ps1" | Select-String "keyword"`

---

## 🤝 Contributing

Found a useful recipe? Add it to this guide! See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines.

---

**Last Updated**: 2025-01-09
**Repository**: [bug-free-umbrella](https://github.com/Carme99/bug-free-umbrella)
**License**: Apache License 2.0
