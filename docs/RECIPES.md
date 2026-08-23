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
.\scripts\collaboration\microsoft365\Get-M365UserInfo.ps1 -UserEmail "user@company.com"
```

### Review and clean up quarantined emails (interactive menu)
```powershell
.\scripts\collaboration\microsoft365\exchange-online\Manage-QuarantinedEmails.ps1 -UserEmail "user@company.com" -Days 30 -AutoConnect
```

### Check mailbox health and size
```powershell
.\scripts\collaboration\microsoft365\exchange-online\Get-MailboxHealth.ps1 -IncludeArchive
```

### Audit shared mailbox permissions
```powershell
.\scripts\collaboration\microsoft365\exchange-online\Get-SharedMailboxReport.ps1 -ExportHTML
```

### Find suspicious mail rules
```powershell
.\scripts\collaboration\microsoft365\exchange-online\Get-UserMailRules.ps1 -UserEmail "user@company.com" -ExportReport
```

### Analyze mail flow issues
```powershell
.\scripts\collaboration\microsoft365\exchange-online\Get-MailFlowAnalysis.ps1 -DaysToAnalyze 7
```

### Get Microsoft 365 license usage
```powershell
.\scripts\collaboration\microsoft365\azure-ad\Get-AzureADLicenseReport.ps1 -ExportCSV
```

### Audit guest users in Azure AD
```powershell
.\scripts\collaboration\microsoft365\azure-ad\Get-AzureADGuestAudit.ps1 -InactivityDays 30
```

### Get Teams usage report
```powershell
.\scripts\collaboration\microsoft365\teams\Get-TeamsReport.ps1 -IncludeGuests -ExportHTML
```

### Get OneDrive storage usage
```powershell
.\scripts\collaboration\microsoft365\sharepoint-onedrive\Get-OneDriveUsageReport.ps1 -ExportHTML
```

### Check Defender for Office 365 threats
```powershell
.\scripts\collaboration\microsoft365\defender-office365\Get-DefenderO365ThreatReport.ps1 -DaysToAnalyze 7
```

---

## Intune & Device Management

### Get device compliance status report (HTML by default)
```powershell
.\scripts\endpoints\intune\reporting\Get-DeviceComplianceReport.ps1
```

### Include compliant devices in the report
```powershell
.\scripts\endpoints\intune\reporting\Get-DeviceComplianceReport.ps1 -IncludeCompliant
```

### Check BitLocker encryption status
```powershell
.\scripts\endpoints\intune\reporting\Get-BitLockerStatus.ps1 -ShowMissingKeys -ExportFormat CSV
```

### Find stale/inactive devices
```powershell
.\scripts\endpoints\intune\maintenance\Find-StaleDevices.ps1 -DaysInactive 90
```

### Check Windows Update compliance
```powershell
.\scripts\endpoints\intune\reporting\Get-WindowsUpdateCompliance.ps1 -ShowNonCompliantOnly
```

### Get Winget update compliance (outdated apps shown by default)
```powershell
.\scripts\endpoints\intune\reporting\Get-WingetUpdateCompliance.ps1
```

### Audit Autopilot deployment status
```powershell
.\scripts\endpoints\intune\reporting\Get-AutopilotDeploymentReport.ps1 -Days 30
```

### Export Intune configuration for backup
```powershell
.\scripts\endpoints\intune\maintenance\Export-IntuneConfiguration.ps1 -OutputPath "C:\Backup\Intune"
```

### Find policy conflicts
```powershell
.\scripts\endpoints\intune\maintenance\Find-PolicyConflicts.ps1 -CheckSettingsCatalog -CheckCompliancePolicies
```

### Check configuration drift against a saved baseline
```powershell
# Capture a baseline first...
.\scripts\endpoints\intune\maintenance\Compare-ConfigurationDrift.ps1 -CreateBaseline
# ...then compare any time with -BaselinePath <path-to-baseline>
```

### Perform bulk device actions
```powershell
.\scripts\endpoints\intune\maintenance\Invoke-DeviceBulkActions.ps1 -Action Sync -NonCompliantOnly
```

### Test Intune connectivity
```powershell
.\scripts\endpoints\intune\maintenance\Test-IntuneConnectivity.ps1 -Verbose
```

### Get policy assignment report
```powershell
.\scripts\endpoints\intune\reporting\Get-PolicyAssignmentReport.ps1
```

### Get device group membership
```powershell
.\scripts\endpoints\intune\reporting\Get-DeviceGroupMembership.ps1 -DeviceName "DESKTOP-ABC123"
```

---

## Security & Compliance

### Run comprehensive security scan (CIS Benchmark)
```powershell
.\scripts\security\hardening\Invoke-SecurityComplianceScan.ps1 -Framework CIS -TargetSystem Windows
```

### Run NIST compliance scan
```powershell
.\scripts\security\hardening\Invoke-SecurityComplianceScan.ps1 -Framework NIST -TargetSystem Windows
```

### Run PCI-DSS compliance check
```powershell
.\scripts\security\hardening\Invoke-SecurityComplianceScan.ps1 -Framework PCI-DSS -TargetSystem Windows
```

### Check antivirus status (runs locally)
```powershell
.\scripts\security\compliance\frameworks\Get-AntivirusStatus.ps1 -CheckThirdParty
```

### Find expiring certificates (next 30 days)
```powershell
.\scripts\security\compliance\frameworks\Get-ExpiredCertificates.ps1 -DaysToExpire 30
```

### Audit failed login attempts
```powershell
.\scripts\security\compliance\frameworks\Get-FailedLoginReport.ps1 -Hours 24 -ExportReport
```

### Audit local administrator accounts
```powershell
.\scripts\security\compliance\frameworks\Get-LocalAdminAudit.ps1 -ExportReport
```

### Scan for open ports
```powershell
.\scripts\security\compliance\frameworks\Get-OpenPortScan.ps1 -HighRiskOnly
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
.\scripts\security\compliance\frameworks\Get-USBDeviceAudit.ps1 -IncludeHistory
```

### Check software license compliance
```powershell
.\scripts\security\compliance\frameworks\Get-SoftwareLicenseCompliance.ps1
```

---

## Server Monitoring & Health

### Run comprehensive server health check (run locally on the server)
```powershell
.\scripts\infrastructure\windows\monitoring\Monitor-ServerHealth.ps1 -IncludeSecurity -IncludeWindowsUpdate -ExportReport
```

### Browse the interactive health-check menu
```powershell
.\scripts\infrastructure\windows\monitoring\Monitor-ServerHealth.ps1
```

### Include disk I/O metrics in the health check
```powershell
.\scripts\infrastructure\windows\monitoring\Monitor-ServerHealth.ps1 -IncludeDiskIO
```

### Check certificate expiration
```powershell
.\scripts\infrastructure\windows\monitoring\Monitor-ServerHealth.ps1 -IncludeCertificates -CertificateWarningDays 30
```

### Check Windows Update status
```powershell
.\scripts\infrastructure\windows\monitoring\Monitor-ServerHealth.ps1 -IncludeWindowsUpdate
```

### Get performance metrics report
```powershell
.\scripts\infrastructure\windows\monitoring\Get-PerformanceReport.ps1 -DurationMinutes 60
```

### Get event log errors (last 24 hours)
```powershell
.\scripts\infrastructure\windows\monitoring\Get-EventLogReport.ps1 -Hours 24 -Severity Error -ExportHTML
```

### Get error events (last 7 days)
```powershell
.\scripts\infrastructure\windows\monitoring\Get-EventLogReport.ps1 -Days 7 -Severity Error
```

---

## User Management

### Get detailed mailbox permissions for a user
```powershell
.\scripts\collaboration\microsoft365\exchange-online\Get-UserMailboxPermissions.ps1 -UserEmail "user@company.com"
```

### Audit distribution list membership
```powershell
.\scripts\collaboration\microsoft365\exchange-online\Get-DistributionListAudit.ps1 -ExportCSV
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
.\scripts\collaboration\microsoft365\teams\Set-TeamsRegionalSettings.ps1 -UserPrincipalName "user@company.com" -TimeZone "Pacific Standard Time"
```

### Set organization-wide defaults (audit first, apply with -Apply)
```powershell
.\scripts\collaboration\microsoft365\azure-ad\Set-OrganizationDefaults.ps1 -PreferredLanguage "en-US" -AuditOnly
```

---

## Azure & Cloud

### Create Winget update packages for Intune
```powershell
.\scripts\endpoints\intune\deployment\New-BulkWingetUpdater.ps1 -AppName "Google Chrome" -WingetID "Google.Chrome" -ProcessName "chrome"
```

### Create Win32 app template
```powershell
.\scripts\endpoints\intune\deployment\New-Win32AppTemplate.ps1 -AppName "CustomApp" -InstallCommand "msiexec /i app.msi /qn" -DetectionType MSI
```

### Package app as .intunewin
```powershell
.\scripts\endpoints\intune\deployment\New-IntuneWinPackage.ps1 -SourceFolder "C:\Apps\MyApp" -SetupFile "setup.exe"
```

### Export Winget package list
```powershell
.\scripts\endpoints\intune\deployment\Export-WingetPackageList.ps1 -ExportFormat JSON -OutputPath "C:\Exports\winget-packages.json"
```

---

## Backup & Recovery

### Export Intune configuration (full backup)
```powershell
.\scripts\endpoints\intune\maintenance\Export-IntuneConfiguration.ps1 -OutputPath "C:\Backup\Intune_$(Get-Date -Format 'yyyyMMdd')" -IncludeAssignments -CompressOutput
```

---

## Active Directory

### Audit local administrator accounts (run locally on each host)
```powershell
.\scripts\security\compliance\frameworks\Get-LocalAdminAudit.ps1 -Detailed -ExportReport
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

### Discover scripts with the BugFreeUmbrella module
```powershell
# Bootstrap once per session, then search the catalog
Import-Module ./src/BugFreeUmbrella
Get-BUScript -Search bitlocker
```

### Schedule reports with Task Scheduler
```powershell
# Create a scheduled task for daily compliance report
$Action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-File C:\Scripts\bug-free-umbrella\scripts\endpoints\intune\reporting\Get-DeviceComplianceReport.ps1"
$Trigger = New-ScheduledTaskTrigger -Daily -At 8:00AM
Register-ScheduledTask -TaskName "Daily Compliance Report" -Action $Action -Trigger $Trigger
```

### Export to multiple formats
```powershell
# Reporting scripts use -ExportFormat HTML, CSV, or Both
.\scripts\endpoints\intune\reporting\Get-DeviceComplianceReport.ps1 -ExportFormat Both
```

### Use -Verbose for troubleshooting
```powershell
# Get detailed execution information
.\scripts\security\hardening\Invoke-SecurityComplianceScan.ps1 -Framework CIS -TargetSystem Windows -Verbose
```

### Find a script when you only know the topic
```powershell
# Fuzzy search the catalog from the launcher CLI
pwsh -File ./Invoke-Umbrella.ps1 -Search certificate -List
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

**Last Updated**: 2026-08-23
**Repository**: [bug-free-umbrella](https://github.com/Carme99/bug-free-umbrella)
**License**: Apache License 2.0
