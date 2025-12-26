# Troubleshooting Guide

This guide covers common issues and solutions for the bug-free-umbrella PowerShell toolkit.

## Table of Contents

- [Microsoft Graph API Issues](#microsoft-graph-api-issues)
- [Authentication Problems](#authentication-problems)
- [PowerShell Execution Policy](#powershell-execution-policy)
- [Module Installation Issues](#module-installation-issues)
- [Intune Script Deployment](#intune-script-deployment)
- [Winget Update Scripts](#winget-update-scripts)
- [BitLocker Backup Issues](#bitlocker-backup-issues)
- [Network and Proxy Issues](#network-and-proxy-issues)
- [Permission Errors](#permission-errors)
- [Script Performance Issues](#script-performance-issues)

---

## Microsoft Graph API Issues

### Error: "Connect-MgGraph: The term 'Connect-MgGraph' is not recognized"

**Cause:** Microsoft Graph PowerShell SDK is not installed.

**Solution:**
```powershell
# Install the Microsoft.Graph module
Install-Module Microsoft.Graph -Scope CurrentUser -Force

# Verify installation
Get-Module Microsoft.Graph.* -ListAvailable
```

### Error: "Insufficient privileges to complete the operation"

**Cause:** The authenticated account lacks required Graph API permissions.

**Solution:**
1. Ensure you have the necessary permissions assigned in Azure AD
2. Common required permissions for Intune management scripts:
   - `DeviceManagementManagedDevices.Read.All`
   - `DeviceManagementConfiguration.Read.All`
   - `DeviceManagementApps.Read.All`
   - `User.Read.All`
   - `Group.Read.All`

3. Grant admin consent in Azure AD:
   - Go to **Azure AD** > **Enterprise Applications** > **Microsoft Graph PowerShell**
   - Click **Permissions** > **Grant admin consent**

### Error: "Authentication needed. Please call Connect-MgGraph"

**Cause:** Graph API session expired or not established.

**Solution:**
```powershell
# Disconnect any existing sessions
Disconnect-MgGraph -ErrorAction SilentlyContinue

# Reconnect with required scopes
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All", "DeviceManagementConfiguration.Read.All"

# Verify connection
Get-MgContext
```

### Error: "Too many requests" or "429 error"

**Cause:** Graph API throttling due to too many requests.

**Solution:**
- Implement retry logic with exponential backoff
- Add delays between batch operations
- Reduce the number of concurrent requests

Example retry logic:
```powershell
$retryCount = 0
$maxRetries = 3
$delay = 2

while ($retryCount -lt $maxRetries) {
    try {
        # Your Graph API call here
        $result = Invoke-MgGraphRequest -Uri $uri
        break
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 429) {
            $retryCount++
            Start-Sleep -Seconds ($delay * [Math]::Pow(2, $retryCount))
        }
        else {
            throw
        }
    }
}
```

---

## Authentication Problems

### Error: "Interactive authentication is needed"

**Cause:** Scripts requiring user interaction are running non-interactively (e.g., in Azure Automation).

**Solution:**
- Use service principal authentication for automated scenarios
- Create an app registration in Azure AD
- Use certificate-based authentication

Example with service principal:
```powershell
$tenantId = "your-tenant-id"
$clientId = "your-app-id"
$clientSecret = "your-secret" | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($clientId, $clientSecret)

Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $credential
```

### Error: "AADSTS50076: Due to a configuration change made by your administrator..."

**Cause:** Conditional Access policy requires multi-factor authentication.

**Solution:**
- Complete MFA enrollment for your account
- Use device code flow for interactive authentication
- Configure Conditional Access to exclude service principals if using automation

```powershell
# Use device code flow
Connect-MgGraph -UseDeviceCode
```

### Error: "The user or administrator has not consented to use the application"

**Cause:** Application permissions not consented.

**Solution:**
1. Admin consent required for organization
2. Go to Azure AD > App registrations > Your app > API permissions
3. Click "Grant admin consent for [Your Organization]"

---

## PowerShell Execution Policy

### Error: "cannot be loaded because running scripts is disabled on this system"

**Cause:** Execution policy prevents script execution.

**Solution:**
```powershell
# Check current execution policy
Get-ExecutionPolicy

# Set execution policy for current user (recommended)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Bypass execution policy for a single script
powershell.exe -ExecutionPolicy Bypass -File ".\script.ps1"
```

### Error: "File is not digitally signed"

**Cause:** Execution policy requires signed scripts (AllSigned).

**Solution:**
- Option 1: Change execution policy to RemoteSigned
- Option 2: Sign the scripts with a code signing certificate
- Option 3: Unblock downloaded files

```powershell
# Unblock a downloaded script
Unblock-File -Path ".\script.ps1"

# Unblock all scripts in a directory
Get-ChildItem -Path ".\Intune Management Scripts\" -Recurse | Unblock-File
```

---

## Module Installation Issues

### Error: "WARNING: Unable to download from URI"

**Cause:** PowerShell Gallery connectivity issues or proxy blocking.

**Solution:**
```powershell
# Check TLS version (PowerShell Gallery requires TLS 1.2)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Configure proxy if needed
$proxy = New-Object System.Net.WebProxy("http://proxy.company.com:8080")
$proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
[System.Net.WebRequest]::DefaultWebProxy = $proxy

# Then try installing again
Install-Module Microsoft.Graph -Scope CurrentUser
```

### Error: "PackageManagement\Install-Package: No match was found for the specified search criteria"

**Cause:** PSGallery repository not registered or untrusted.

**Solution:**
```powershell
# Register PSGallery if missing
Register-PSRepository -Default

# Set PSGallery as trusted
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted

# Verify repositories
Get-PSRepository
```

### Error: "Unable to resolve package source"

**Cause:** Outdated PowerShellGet or PackageManagement modules.

**Solution:**
```powershell
# Update PowerShellGet
Install-Module -Name PowerShellGet -Force -AllowClobber

# Update PackageManagement
Install-Module -Name PackageManagement -Force

# Restart PowerShell session
```

---

## Intune Script Deployment

### Detect Script Exits with Code 0 but Doesn't Trigger Remediation

**Cause:** Detection script must exit with code 1 to trigger remediation.

**Solution:**
```powershell
# Detection script should exit with 1 when remediation is needed
if ($needsRemediation) {
    Write-Output "Remediation required"
    exit 1  # Triggers remediation
}
else {
    Write-Output "Compliant"
    exit 0  # No remediation needed
}
```

### Script Fails on Client but Works Locally

**Cause:** Scripts run as SYSTEM account in Intune, not as user.

**Solution:**
- Test scripts in SYSTEM context using PsExec
```powershell
# Download PsExec from Sysinternals
# Run PowerShell as SYSTEM
psexec.exe -i -s powershell.exe

# Test your script
.\detect.ps1
```

### Error: "This script requires to run as Administrator"

**Cause:** Script requires elevation but Intune runs in user context.

**Solution:**
- Configure the remediation script to run in **System context** in Intune portal
- Remove explicit Administrator checks from scripts deployed via Intune

### Remediation Script Runs but Doesn't Persist

**Cause:** Detection runs before remediation completes or registry/file changes are cached.

**Solution:**
- Add delays in detection script after remediation
- Ensure remediation writes persistent indicators
- Restart-Service or Restart-Computer if needed

---

## Winget Update Scripts

### Error: "winget: The term 'winget' is not recognized"

**Cause:** Windows Package Manager (winget) not installed or not in PATH for SYSTEM account.

**Solution:**
```powershell
# Check if winget is available
$winget = Get-Command winget -ErrorAction SilentlyContinue

# If not found, resolve winget path (for SYSTEM context)
if (-not $winget) {
    $wingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" |
                  Select-Object -Last 1 -ExpandProperty Path

    if ($wingetPath) {
        & $wingetPath upgrade --id <package-id> --silent
    }
}
```

### Error: "No package found matching input criteria"

**Cause:** Package ID changed or not available in winget repository.

**Solution:**
```powershell
# Search for the package
winget search "Adobe Reader"

# List installed packages
winget list

# Update package ID in script if changed
```

### Winget Hangs or Times Out

**Cause:** Interactive prompts or network issues.

**Solution:**
- Always use `--silent` and `--accept-source-agreements` flags
- Add timeout handling

```powershell
# Example with timeout
$process = Start-Process winget -ArgumentList "upgrade --id Adobe.Acrobat.Reader.64-bit --silent --accept-source-agreements" -PassThru -NoNewWindow
$timeout = 300 # 5 minutes

if (-not $process.WaitForExit($timeout * 1000)) {
    $process.Kill()
    throw "Winget process timed out after $timeout seconds"
}
```

---

## BitLocker Backup Issues

### Error: "BitLocker key protector not found"

**Cause:** Device doesn't have BitLocker enabled or no recovery key exists.

**Solution:**
```powershell
# Check BitLocker status
Get-BitLockerVolume -MountPoint "C:"

# Enable BitLocker if needed
Enable-BitLocker -MountPoint "C:" -RecoveryPasswordProtector

# Verify recovery key exists
(Get-BitLockerVolume -MountPoint "C:").KeyProtector | Where-Object {$_.KeyProtectorType -eq "RecoveryPassword"}
```

### Error: "Failed to backup key to Azure AD"

**Cause:** Device not Azure AD joined or insufficient permissions.

**Solution:**
- Verify device is Azure AD joined: `dsregcmd /status`
- Ensure device has connectivity to Azure AD
- Check device has required permissions to write BitLocker keys

```powershell
# Check Azure AD join status
$dsregcmd = dsregcmd /status
if ($dsregcmd -match "AzureAdJoined\s+:\s+YES") {
    Write-Output "Device is Azure AD joined"
}
else {
    Write-Warning "Device is not Azure AD joined"
}

# Manual backup to Azure AD
$BLV = Get-BitLockerVolume -MountPoint "C:"
$RecoveryKey = $BLV.KeyProtector | Where-Object {$_.KeyProtectorType -eq "RecoveryPassword"}
BackupToAAD-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $RecoveryKey.KeyProtectorId
```

---

## Network and Proxy Issues

### Error: "Unable to connect to Graph API endpoint"

**Cause:** Firewall or proxy blocking connections.

**Solution:**
```powershell
# Configure proxy for PowerShell session
$proxy = "http://proxy.company.com:8080"
[System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy($proxy)
[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

# Test connectivity to Graph API
Test-NetConnection -ComputerName graph.microsoft.com -Port 443

# Add bypass for local addresses
$webProxy = New-Object System.Net.WebProxy($proxy, $true)
[System.Net.WebRequest]::DefaultWebProxy = $webProxy
```

### Required Endpoints Not Accessible

**Ensure these endpoints are accessible:**
- `https://graph.microsoft.com`
- `https://login.microsoftonline.com`
- `https://management.azure.com`
- `https://enterpriseregistration.windows.net`

---

## Permission Errors

### Error: "Access Denied" when accessing registry/files

**Cause:** Insufficient permissions even when running as admin.

**Solution:**
```powershell
# Take ownership of registry key
$key = "HKLM:\SOFTWARE\Example"
$acl = Get-Acl $key
$acl.SetOwner([System.Security.Principal.NTAccount]"Administrators")
Set-Acl -Path $key -AclObject $acl

# Grant permissions
$rule = New-Object System.Security.AccessControl.RegistryAccessRule(
    "Administrators",
    "FullControl",
    "ContainerInherit,ObjectInherit",
    "None",
    "Allow"
)
$acl.AddAccessRule($rule)
Set-Acl -Path $key -AclObject $acl
```

### Error: "The requested operation requires elevation"

**Cause:** UAC blocking operation.

**Solution:**
- Run PowerShell as Administrator
- Or use Intune's system context for deployment

```powershell
# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator"
    exit 1
}
```

---

## Script Performance Issues

### Scripts Run Slowly or Time Out

**Cause:** Large dataset queries or inefficient Graph API calls.

**Solution:**
- Use pagination for large result sets
- Implement parallel processing for independent operations
- Use `$select` to request only needed properties
- Use batch requests when possible

```powershell
# Use $select to reduce payload
$devices = Get-MgDeviceManagementManagedDevice -All -Select "deviceName,operatingSystem,complianceState"

# Parallel processing example
$devices | ForEach-Object -Parallel {
    # Process each device
} -ThrottleLimit 10
```

### Error: "Out of memory"

**Cause:** Processing too much data at once.

**Solution:**
- Process data in batches
- Clear variables when no longer needed
- Use streaming/paging

```powershell
# Process in batches of 1000
$batchSize = 1000
$skip = 0

do {
    $batch = Get-MgDeviceManagementManagedDevice -Top $batchSize -Skip $skip

    # Process batch
    foreach ($device in $batch) {
        # Your processing here
    }

    $skip += $batchSize

    # Clean up
    [System.GC]::Collect()

} while ($batch.Count -eq $batchSize)
```

---

## Common PowerShell Errors

### Error: "You cannot call a method on a null-valued expression"

**Cause:** Attempting to access a property/method on $null.

**Solution:**
```powershell
# Always check for null before accessing properties
if ($object -ne $null) {
    $object.Property
}

# Or use null-conditional operator (PowerShell 7+)
$object?.Property
```

### Error: "Cannot bind argument to parameter 'Path' because it is an empty string"

**Cause:** Path variable is empty or null.

**Solution:**
```powershell
# Validate parameters
if ([string]::IsNullOrWhiteSpace($path)) {
    throw "Path cannot be empty"
}

# Use default value
$path = if ($customPath) { $customPath } else { "C:\Default\Path" }
```

---

## Getting Additional Help

### Enable Verbose Output

```powershell
# Run scripts with verbose output
.\script.ps1 -Verbose

# Or use $VerbosePreference
$VerbosePreference = "Continue"
.\script.ps1
```

### Enable Debug Output

```powershell
# Run with debug output
.\script.ps1 -Debug

# Or set debug preference
$DebugPreference = "Continue"
```

### Capture Detailed Errors

```powershell
# Get full error details
$Error[0] | Format-List * -Force

# Get inner exceptions
$Error[0].Exception.InnerException

# Error stack trace
$Error[0].ScriptStackTrace
```

### Check Event Logs

```powershell
# Check for script errors in event log
Get-WinEvent -LogName "Microsoft-Windows-PowerShell/Operational" -MaxEvents 50 |
    Where-Object {$_.LevelDisplayName -eq "Error"}
```

---

## Reporting Issues

If you encounter issues not covered in this guide:

1. **Check the Error Details:**
   - Full error message
   - PowerShell version: `$PSVersionTable`
   - Module versions: `Get-Module Microsoft.Graph.* -ListAvailable`

2. **Gather Environment Info:**
   - Windows version: `Get-ComputerInfo | Select-Object WindowsVersion, OsArchitecture`
   - Execution context: User vs SYSTEM
   - Network configuration: Proxy settings, firewall rules

3. **Enable Logging:**
   - Use `-Verbose` and `-Debug` parameters
   - Check script logs if generated
   - Review Intune device logs

4. **Report the Issue:**
   - Create a GitHub issue with detailed information
   - Include sanitized error messages (remove sensitive data)
   - Provide steps to reproduce

---

## Useful Resources

- [Microsoft Graph PowerShell SDK Documentation](https://learn.microsoft.com/en-us/powershell/microsoftgraph/)
- [Microsoft Intune Documentation](https://learn.microsoft.com/en-us/mem/intune/)
- [PowerShell Documentation](https://learn.microsoft.com/en-us/powershell/)
- [Windows Package Manager (winget)](https://learn.microsoft.com/en-us/windows/package-manager/)
- [Azure AD App Registration](https://learn.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app)

---
