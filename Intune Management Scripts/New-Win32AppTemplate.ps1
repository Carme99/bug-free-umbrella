<#
.SYNOPSIS
    Generates a Win32 app deployment template with all necessary files and documentation.

.DESCRIPTION
    This script creates a complete deployment package template for Win32 apps in Intune,
    including:
    - Detection script
    - Requirement script
    - Installation script (if needed)
    - Uninstall script (if needed)
    - Deployment documentation
    - README with instructions

    Perfect for standardizing app deployments and onboarding new admins.

.PARAMETER AppName
    Name of the application.

.PARAMETER InstallCommand
    Installation command line.

.PARAMETER UninstallCommand
    Uninstallation command line.

.PARAMETER DetectionType
    Type of detection: Registry, File, MSI, or Script (default: Registry).

.PARAMETER OutputFolder
    Where to save the template (default: Desktop\Win32AppTemplates).

.EXAMPLE
    .\New-Win32AppTemplate.ps1 -AppName "7-Zip" -InstallCommand "7z-x64.exe /S" -DetectionType "Registry"
    Creates a complete deployment template for 7-Zip.

.EXAMPLE
    .\New-Win32AppTemplate.ps1
    Interactive mode - prompts for all required information.

.NOTES
    No Graph API connection needed - this is a local template generator
    Output files are ready to use with Intune Win32 app deployment
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$AppName,

    [Parameter(Mandatory=$false)]
    [string]$InstallCommand,

    [Parameter(Mandatory=$false)]
    [string]$UninstallCommand,

    [Parameter(Mandatory=$false)]
    [ValidateSet('Registry', 'File', 'MSI', 'Script')]
    [string]$DetectionType = 'Registry',

    [Parameter(Mandatory=$false)]
    [string]$OutputFolder
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Win32 App Deployment Template Generator" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Interactive mode if parameters not provided
if (-not $AppName) {
    $AppName = Read-Host "Enter application name (e.g., '7-Zip', 'Google Chrome')"
}

if (-not $InstallCommand) {
    Write-Host "`nEnter installation command (e.g., 'setup.exe /S', 'msiexec /i app.msi /qn')" -ForegroundColor Yellow
    $InstallCommand = Read-Host "Install command"
}

if (-not $UninstallCommand) {
    Write-Host "`nEnter uninstallation command (or press Enter to skip)" -ForegroundColor Yellow
    $UninstallCommand = Read-Host "Uninstall command"
}

if (-not $DetectionType) {
    Write-Host "`nSelect detection method:" -ForegroundColor Yellow
    Write-Host "1. Registry key/value" -ForegroundColor Gray
    Write-Host "2. File or folder exists" -ForegroundColor Gray
    Write-Host "3. MSI product code" -ForegroundColor Gray
    Write-Host "4. Custom PowerShell script" -ForegroundColor Gray

    $choice = Read-Host "Enter choice (1-4)"
    $DetectionType = switch ($choice) {
        "1" { "Registry" }
        "2" { "File" }
        "3" { "MSI" }
        "4" { "Script" }
        default { "Registry" }
    }
}

# Set output folder
if (-not $OutputFolder) {
    $appNameClean = $AppName -replace '[\\/:*?"<>|]', '_'
    $OutputFolder = Join-Path $env:USERPROFILE "Desktop\Win32AppTemplates\$appNameClean"
}

# Create output folder
if (-not (Test-Path $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
}

Write-Host "`n✓ App Name: $AppName" -ForegroundColor Green
Write-Host "✓ Detection Type: $DetectionType" -ForegroundColor Green
Write-Host "✓ Output Folder: $OutputFolder" -ForegroundColor Green

# Generate Detection Script based on type
$detectionScript = ""

switch ($DetectionType) {
    "Registry" {
        $detectionScript = @"
<#
.SYNOPSIS
    Detection script for $AppName (Registry-based)

.DESCRIPTION
    Checks if $AppName is installed by verifying registry key.
#>

# Configure these values for your app
`$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{APP-GUID}"
# Or for user-based: "HKCU:\SOFTWARE\..."
# Or for both: Check both HKLM and HKCU

`$registryValue = "DisplayVersion"  # Optional: Check specific value
`$expectedValue = "1.0.0"  # Optional: Expected version

try {
    if (Test-Path `$registryPath) {
        if (`$registryValue) {
            `$actualValue = Get-ItemPropertyValue -Path `$registryPath -Name `$registryValue -ErrorAction Stop

            if (`$actualValue -eq `$expectedValue) {
                Write-Output "$AppName installed (Version: `$actualValue)"
                exit 0  # Detected
            }
            else {
                Write-Output "Wrong version: `$actualValue"
                exit 1  # Not detected
            }
        }
        else {
            Write-Output "$AppName registry key found"
            exit 0  # Detected
        }
    }
    else {
        Write-Output "$AppName not found in registry"
        exit 1  # Not detected
    }
}
catch {
    Write-Output "Detection error: `$(`$_.Exception.Message)"
    exit 1  # Not detected
}
"@
    }

    "File" {
        $detectionScript = @"
<#
.SYNOPSIS
    Detection script for $AppName (File-based)

.DESCRIPTION
    Checks if $AppName is installed by verifying file/folder exists.
#>

# Configure these values for your app
`$filePath = "C:\Program Files\$AppName\app.exe"
# Or folder: "C:\Program Files\$AppName"

`$checkVersion = `$false
`$expectedVersion = "1.0.0.0"

try {
    if (Test-Path `$filePath) {
        if (`$checkVersion) {
            `$file = Get-Item `$filePath
            `$actualVersion = `$file.VersionInfo.FileVersion

            if (`$actualVersion -eq `$expectedVersion) {
                Write-Output "$AppName found (Version: `$actualVersion)"
                exit 0  # Detected
            }
            else {
                Write-Output "Wrong version: `$actualVersion (Expected: `$expectedVersion)"
                exit 1  # Not detected
            }
        }
        else {
            Write-Output "$AppName found at `$filePath"
            exit 0  # Detected
        }
    }
    else {
        Write-Output "$AppName not found at `$filePath"
        exit 1  # Not detected
    }
}
catch {
    Write-Output "Detection error: `$(`$_.Exception.Message)"
    exit 1  # Not detected
}
"@
    }

    "MSI" {
        $detectionScript = @"
<#
.SYNOPSIS
    Detection script for $AppName (MSI-based)

.DESCRIPTION
    Checks if $AppName is installed by verifying MSI product code.
#>

# Configure these values for your app
`$productCode = "{PRODUCT-GUID-HERE}"  # Get from MSI or registry
`$expectedVersion = "1.0.0"  # Optional

try {
    `$installedProducts = Get-WmiObject -Class Win32_Product | Where-Object { `$_.IdentifyingNumber -eq `$productCode }

    if (`$installedProducts) {
        `$version = `$installedProducts.Version

        if (`$expectedVersion -and `$version -ne `$expectedVersion) {
            Write-Output "Wrong version: `$version (Expected: `$expectedVersion)"
            exit 1  # Not detected
        }

        Write-Output "$AppName installed (Version: `$version)"
        exit 0  # Detected
    }
    else {
        Write-Output "$AppName MSI not found"
        exit 1  # Not detected
    }
}
catch {
    Write-Output "Detection error: `$(`$_.Exception.Message)"
    exit 1  # Not detected
}
"@
    }

    "Script" {
        $detectionScript = @"
<#
.SYNOPSIS
    Detection script for $AppName (Custom logic)

.DESCRIPTION
    Custom detection logic for $AppName installation.
#>

try {
    # Add your custom detection logic here
    # Examples:
    # - Check multiple registry keys
    # - Verify service is installed
    # - Check file version AND registry
    # - Verify configuration files exist

    # Example: Check registry AND file
    `$regPath = "HKLM:\SOFTWARE\$AppName"
    `$filePath = "C:\Program Files\$AppName\app.exe"

    if ((Test-Path `$regPath) -and (Test-Path `$filePath)) {
        Write-Output "$AppName detected"
        exit 0  # Detected
    }
    else {
        Write-Output "$AppName not detected"
        exit 1  # Not detected
    }
}
catch {
    Write-Output "Detection error: `$(`$_.Exception.Message)"
    exit 1  # Not detected
}
"@
    }
}

# Generate Requirement Script
$requirementScript = @"
<#
.SYNOPSIS
    Requirement script for $AppName

.DESCRIPTION
    Checks if the device meets minimum requirements for $AppName installation.
    Return exit code 0 if requirements are met, exit code 1 if not.
#>

try {
    # Check OS version
    `$os = Get-WmiObject -Class Win32_OperatingSystem
    `$osVersion = [System.Version]`$os.Version

    # Require Windows 10 or later (10.0+)
    if (`$osVersion.Major -lt 10) {
        Write-Output "OS version too old: `$osVersion"
        exit 1  # Requirements not met
    }

    # Check available disk space (in GB)
    `$requiredDiskSpaceGB = 1
    `$systemDrive = Get-PSDrive -Name C
    `$freeSpaceGB = [math]::Round(`$systemDrive.Free / 1GB, 2)

    if (`$freeSpaceGB -lt `$requiredDiskSpaceGB) {
        Write-Output "Insufficient disk space: `$freeSpaceGB GB (Required: `$requiredDiskSpaceGB GB)"
        exit 1  # Requirements not met
    }

    # Check RAM (in GB)
    `$requiredRAMGB = 2
    `$totalRAMGB = [math]::Round((Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)

    if (`$totalRAMGB -lt `$requiredRAMGB) {
        Write-Output "Insufficient RAM: `$totalRAMGB GB (Required: `$requiredRAMGB GB)"
        exit 1  # Requirements not met
    }

    # Add any additional requirements here
    # Examples:
    # - Check for prerequisite software
    # - Verify .NET version
    # - Check for conflicting software

    Write-Output "All requirements met"
    exit 0  # Requirements met
}
catch {
    Write-Output "Requirement check error: `$(`$_.Exception.Message)"
    exit 1  # Requirements not met (error)
}
"@

# Generate README
$readmeContent = @"
# Win32 App Deployment: $AppName

**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Detection Type:** $DetectionType

## Overview

This package contains all files needed to deploy **$AppName** as a Win32 app in Intune.

## Files Included

- **detection.ps1** - Detects if the app is installed
- **requirements.ps1** - Checks if device meets requirements
- **README.md** - This file

## Deployment Steps

### 1. Package the Installer

1. Place your installer file(s) in a folder
2. Use **IntuneWinAppUtil.exe** to create .intunewin package:
   ``````
   IntuneWinAppUtil.exe -c <source_folder> -s <setup_file.exe> -o <output_folder>
   ``````

   Or use the **New-IntuneWinPackage.ps1** script from this toolkit.

### 2. Create Win32 App in Intune

1. Go to **Intune > Apps > Windows > Add**
2. Select **Windows app (Win32)**
3. Upload the **.intunewin** package

### 3. Configure App Information

| Field | Value |
|-------|-------|
| **Name** | $AppName |
| **Description** | $AppName for Windows |
| **Publisher** | [Publisher Name] |
| **App Version** | [Version] |

### 4. Program Configuration

**Install command:**
``````
$InstallCommand
``````

$(if ($UninstallCommand) { "**Uninstall command:**`n``````````n$UninstallCommand`n```````" } else { "**Uninstall command:** (Configure based on your app)" })

**Install behavior:** System
**Device restart behavior:** Determine behavior based on return codes

### 5. Requirements

Use the included **requirements.ps1** script, OR configure manually:

| Requirement | Value |
|-------------|-------|
| **Operating system** | Windows 10 1607+ / Windows 11 |
| **Architecture** | x64 (or as needed) |
| **Minimum OS** | Windows 10 1607 |

**Script requirements:**
- Run script as: 32-bit or 64-bit PowerShell
- Enforce script signature check: No
- Exit code 0 = Requirements met

### 6. Detection Rules

**Option A: Use Detection Script (Recommended)**
- Upload **detection.ps1**
- Run script as 32-bit or 64-bit PowerShell
- Enforce script signature check: No

**Option B: Manual Detection ($DetectionType)**
$(switch ($DetectionType) {
    "Registry" { "- Type: Registry`n- Path: [Configure based on your app]`n- Value name: DisplayVersion (or similar)`n- Detection method: Key exists OR Value equals X" }
    "File" { "- Type: File or folder`n- Path: C:\Program Files\$AppName\app.exe`n- Detection method: File or folder exists" }
    "MSI" { "- Type: MSI`n- MSI product code: [Get from MSI properties]" }
    "Script" { "- Use the provided detection.ps1 script with your custom logic" }
})

### 7. Return Codes

Standard return codes:
- **0** - Success
- **1707** - Success (reboot required)
- **3010** - Soft reboot
- **1641** - Hard reboot
- **1618** - Retry

Add custom return codes as needed for your installer.

### 8. Assignment

1. **Required** - For devices that must have the app
2. **Available** - For optional installation via Company Portal
3. **Uninstall** - To remove the app from devices

Assign to appropriate device or user groups.

## Testing

### Test Detection Script Locally

``````powershell
# Run as admin
.\detection.ps1
echo `$LASTEXITCODE
# 0 = Detected, 1 = Not detected
``````

### Test Requirements Script Locally

``````powershell
# Run as admin
.\requirements.ps1
echo `$LASTEXITCODE
# 0 = Requirements met, 1 = Requirements not met
``````

### Test Installation

1. Deploy to test device group
2. Monitor Intune logs on device:
   - **C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log**
   - **C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AgentExecutor.log**

## Troubleshooting

### App Not Installing

1. Check device meets requirements
2. Verify .intunewin package is valid
3. Check install command is correct
4. Review device logs
5. Test installer manually with same command

### Detection Not Working

1. Test detection script locally
2. Verify detection logic is correct
3. Check for typos in paths/registry keys
4. Ensure detection runs in correct context (system vs user)

### App Shows as "Not Detected" After Install

1. Run detection script manually after install
2. Verify installer actually completed successfully
3. Check detection script exit codes
4. Update detection logic if needed

## Customization

### Modify Detection Script

Edit **detection.ps1** to match your app's specifics:
- Update registry paths
- Change file paths
- Adjust version checking logic

### Modify Requirements

Edit **requirements.ps1** to add:
- Prerequisite software checks
- Specific OS version requirements
- Additional hardware requirements

## Additional Resources

- **Intune Win32 App Management:** https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management
- **Win32 Content Prep Tool:** https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool
- **Troubleshooting:** https://learn.microsoft.com/en-us/troubleshoot/mem/intune/app-management/troubleshoot-win32-app-install

---

**Generated by:** New-Win32AppTemplate.ps1
**Toolkit:** Intune Management Scripts
"@

# Save files
$detectionPath = Join-Path $OutputFolder "detection.ps1"
$requirementPath = Join-Path $OutputFolder "requirements.ps1"
$readmePath = Join-Path $OutputFolder "README.md"

$detectionScript | Out-File -FilePath $detectionPath -Encoding UTF8 -Force
$requirementScript | Out-File -FilePath $requirementPath -Encoding UTF8 -Force
$readmeContent | Out-File -FilePath $readmePath -Encoding UTF8 -Force

Write-Host "`n✓ Detection script: $detectionPath" -ForegroundColor Green
Write-Host "✓ Requirement script: $requirementPath" -ForegroundColor Green
Write-Host "✓ README: $readmePath" -ForegroundColor Green

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "TEMPLATE GENERATED!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "1. Review and customize detection.ps1 for your app" -ForegroundColor White
Write-Host "2. Review and customize requirements.ps1" -ForegroundColor White
Write-Host "3. Package your installer with IntuneWinAppUtil.exe" -ForegroundColor White
Write-Host "4. Upload to Intune and configure settings" -ForegroundColor White
Write-Host "5. Follow README.md for detailed deployment instructions" -ForegroundColor White

Write-Host "`nFiles Location: $OutputFolder" -ForegroundColor Cyan

# Open folder
Write-Host "`nOpening template folder..." -ForegroundColor Cyan
Start-Process $OutputFolder

Write-Host "`n✓ Win32 app template created successfully!" -ForegroundColor Green
