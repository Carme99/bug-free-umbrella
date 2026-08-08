# 🛠️ Custom Development Guide

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+_|_7.0+-5391FE?logo=powershell&logoColor=white)
![Contributions](https://img.shields.io/badge/contributions-welcome-brightgreen)
![License](https://img.shields.io/badge/license-Apache%202.0-red)

> **Developer guide for extending and customizing Bug-Free Umbrella scripts**

---

## 📋 Table of Contents
- [Overview](#overview)
- [Development Prerequisites](#development-prerequisites)
- [Script Structure Standards](#script-structure-standards)
- [Creating New Scripts](#creating-new-scripts)
- [Extending Existing Scripts](#extending-existing-scripts)
- [Testing Your Changes](#testing-your-changes)
- [Contributing Back](#contributing-back)
- [Common Patterns](#common-patterns)

---

## Overview

Bug-Free Umbrella follows PowerShell best practices and consistent patterns across all scripts. This guide will help you:
- ✅ Create new scripts following repository standards
- ✅ Extend existing functionality
- ✅ Maintain consistency with the codebase
- ✅ Prepare contributions for submission

---

## Development Prerequisites

### Required Tools

![VS Code](https://img.shields.io/badge/VS_Code-recommended-007ACC?logo=visualstudiocode)
![Git](https://img.shields.io/badge/Git-required-F05032?logo=git&logoColor=white)
![PSScriptAnalyzer](https://img.shields.io/badge/PSScriptAnalyzer-required-blue)

**Essential:**
1. **PowerShell 7+** (recommended) or PowerShell 5.1+
2. **Git** for version control
3. **PSScriptAnalyzer** for code quality
4. **Pester** for testing (optional but recommended)

**Recommended:**
- Visual Studio Code with PowerShell extension
- PowerShell-related VS Code extensions

**Installation:**
```powershell
# Install PSScriptAnalyzer
Install-Module -Name PSScriptAnalyzer -Force

# Install Pester (testing framework)
Install-Module -Name Pester -Force -SkipPublisherCheck

# Verify installations
Get-Module -ListAvailable PSScriptAnalyzer, Pester
```

### Clone Repository
```powershell
# Clone the repository
git clone https://github.com/Carme99/bug-free-umbrella.git
cd bug-free-umbrella
```

---

## Script Structure Standards

### Mandatory Components

Every script MUST include:

1. **Requires Statements** (at top)
2. **Comment-Based Help**
3. **Parameter Validation**
4. **Error Handling**
5. **Logging/Output**

### Template Script Structure

```powershell
#Requires -Version 5.1
#Requires -RunAsAdministrator  # If needed

<#
.SYNOPSIS
    Brief one-line description

.DESCRIPTION
    Detailed multi-line description of what the script does,
    when to use it, and important notes.

.PARAMETER ParameterName
    Description of the parameter

.EXAMPLE
    .\Script-Name.ps1 -ParameterName "Value"
    Description of what this example does

.EXAMPLE
    .\Script-Name.ps1 -Verbose
    Another usage example

.NOTES
    Author: Your Name
    Version: 1.0.0
    Last Updated: YYYY-MM-DD

    Requirements:
    - PowerShell 5.1 or later
    - Required modules: ModuleName

    Change Log:
    - v1.0.0 (YYYY-MM-DD): Initial release

.LINK
    https://github.com/Carme99/bug-free-umbrella
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true,
               HelpMessage = "Enter parameter description")]
    [ValidateNotNullOrEmpty()]
    [string]$ParameterName,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML
)

#region Variables
$ScriptVersion = "1.0.0"
$ErrorActionPreference = "Stop"
#endregion

#region Functions
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "INFO"  { "Cyan" }
        default { "White" }
    }

    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}
#endregion

#region Main Script Logic
try {
    Write-Log "Script started - Version $ScriptVersion"

    # Your main script logic here

    Write-Log "Script completed successfully" -Level "INFO"
}
catch {
    Write-Log "Script failed: $_" -Level "ERROR"
    exit 1
}
#endregion
```

---

## Creating New Scripts

### Step 1: Choose Location

Scripts are organized by technology domain:

```
scripts/
├── cloud/              # Azure, AWS, containers
├── endpoints/          # Intune, device management
├── infrastructure/     # Windows/Linux servers, network
├── security/           # Compliance, hardening
├── automation/         # CI/CD, IaC
├── collaboration/      # M365, Exchange, Teams
└── data/               # Databases, APIs
```

**Example**: Creating an Azure monitoring script
```powershell
# Create file in appropriate location
New-Item -Path "scripts/cloud/azure/monitoring/Monitor-AzureVMHealth.ps1" -ItemType File
```

### Step 2: Use Standard Template

Copy the template structure above and customize for your needs.

### Step 3: Add Comment-Based Help

```powershell
<#
.SYNOPSIS
    Monitor Azure VM health and performance

.DESCRIPTION
    Comprehensive Azure Virtual Machine health monitoring including:
    - VM status (running/stopped/deallocated)
    - Performance metrics (CPU, memory, disk)
    - Diagnostic data collection
    - Alert generation

.PARAMETER ResourceGroupName
    Name of the Azure Resource Group

.PARAMETER VMName
    Name of the Virtual Machine (optional, monitors all if not specified)

.EXAMPLE
    .\Monitor-AzureVMHealth.ps1 -ResourceGroupName "Production-RG"
    Monitors all VMs in the Production-RG resource group

.EXAMPLE
    .\Monitor-AzureVMHealth.ps1 -ResourceGroupName "Production-RG" -VMName "WebServer01" -ExportHTML
    Monitors specific VM and exports HTML report
#>
```

### Step 4: Implement Parameters

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$VMName,

    [Parameter(Mandatory = $false)]
    [switch]$ExportHTML,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeMetrics
)
```

### Step 5: Add Error Handling

```powershell
try {
    # Check for required module
    if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
        throw "Az.Compute module not found. Install with: Install-Module -Name Az.Compute"
    }

    # Your logic here

} catch {
    Write-Log "Error: $_" -Level "ERROR"
    exit 1
}
```

### Step 6: Run PSScriptAnalyzer

```powershell
# Analyze your script
Invoke-ScriptAnalyzer -Path ".\Monitor-AzureVMHealth.ps1" -Severity Warning,Error

# Fix any issues found
```

---

## Extending Existing Scripts

### Finding Scripts to Extend

```powershell
# Search for scripts by keyword
Get-ChildItem -Path scripts\ -Recurse -Filter "*Intune*.ps1"

# Find scripts with specific functionality
Select-String -Path "scripts\**\*.ps1" -Pattern "Export-HTML" -List
```

### Best Practices for Extensions

1. **Read the Existing Script First**
   - Understand current functionality
   - Identify extension points
   - Check for TODO comments

2. **Maintain Backward Compatibility**
   - Don't break existing parameters
   - Add new parameters as optional
   - Use version numbers to track changes

3. **Follow Existing Patterns**
   - Match coding style
   - Use similar parameter naming
   - Maintain consistent output format

### Example: Adding HTML Export

```powershell
# Add parameter
[Parameter(Mandatory = $false)]
[string]$OutputPath = "$env:USERPROFILE\Desktop"

# Add export function
function Export-HTMLReport {
    param($Data, $Path)

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Report</title>
    <style>
        body { font-family: Arial; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; }
        th { background-color: #4CAF50; color: white; }
    </style>
</head>
<body>
    <h1>Script Report</h1>
    $($Data | ConvertTo-Html -Fragment)
</body>
</html>
"@

    $html | Out-File -FilePath $Path -Encoding UTF8
    Write-Log "Report exported to: $Path"
}
```

---

## Testing Your Changes

### Manual Testing Checklist

- [ ] Script runs without errors
- [ ] All parameters work as expected
- [ ] Help documentation displays correctly
- [ ] Error handling works (test failure scenarios)
- [ ] Output is formatted correctly
- [ ] Export functions create valid files

### Get Help Display
```powershell
# Test your help documentation
Get-Help .\Your-Script.ps1 -Full
Get-Help .\Your-Script.ps1 -Examples
```

### PSScriptAnalyzer Validation
```powershell
# Run analyzer
Invoke-ScriptAnalyzer -Path .\Your-Script.ps1

# Should return no errors/warnings
```

### Pester Testing (Optional)

```powershell
# Create test file: Your-Script.Tests.ps1
Describe "Your-Script Tests" {
    It "Should have help documentation" {
        Get-Help .\Your-Script.ps1 | Should -Not -BeNullOrEmpty
    }

    It "Should have synopsis" {
        $help = Get-Help .\Your-Script.ps1
        $help.Synopsis | Should -Not -BeNullOrEmpty
    }

    # Add more tests...
}

# Run tests
Invoke-Pester -Path .\Your-Script.Tests.ps1
```

---

## Contributing Back

### Before Submitting

1. **Test thoroughly** in your environment
2. **Run PSScriptAnalyzer** with no errors/warnings
3. **Update documentation** if needed
4. **Add examples** to your script help

### Submission Process

1. **Fork the repository**
2. **Create a feature branch**
```powershell
git checkout -b feature/my-new-script
```

3. **Commit your changes**
```powershell
git add .
git commit -m "Add Monitor-AzureVMHealth.ps1 script

- Monitors Azure VM health
- Includes performance metrics
- Exports to HTML
"
```

4. **Push to your fork**
```powershell
git push origin feature/my-new-script
```

5. **Create Pull Request** on GitHub

### Pull Request Guidelines

- Clear title describing the change
- Detailed description of functionality
- List any new requirements/dependencies
- Include usage examples

See [CONTRIBUTING](../CONTRIBUTING.md) for full details.

---

## Common Patterns

### Pattern 1: Module Availability Check

```powershell
function Test-ModuleAvailable {
    param([string]$ModuleName)

    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Log "Module '$ModuleName' not found" -Level "ERROR"
        Write-Log "Install with: Install-Module -Name $ModuleName" -Level "INFO"
        return $false
    }
    return $true
}

# Usage
if (-not (Test-ModuleAvailable -ModuleName "Microsoft.Graph")) {
    exit 1
}
```

### Pattern 2: Progress Indicators

```powershell
$items = @(1..100)
$i = 0

foreach ($item in $items) {
    $i++
    $percent = [math]::Round(($i / $items.Count) * 100)

    Write-Progress -Activity "Processing items" `
        -Status "$percent% Complete" `
        -PercentComplete $percent

    # Process item
}

Write-Progress -Activity "Processing items" -Completed
```

### Pattern 3: HTML Report Generation

```powershell
function New-HTMLReport {
    param($Title, $Data, $OutputPath)

    $css = @"
<style>
    body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; }
    h1 { color: #2c3e50; }
    table { border-collapse: collapse; width: 100%; margin-top: 20px; }
    th { background-color: #3498db; color: white; padding: 12px; text-align: left; }
    td { border: 1px solid #ddd; padding: 8px; }
    tr:nth-child(even) { background-color: #f2f2f2; }
    .success { color: green; font-weight: bold; }
    .error { color: red; font-weight: bold; }
</style>
"@

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>$Title</title>
    $css
</head>
<body>
    <h1>$Title</h1>
    <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    $($Data | ConvertTo-Html -Fragment)
</body>
</html>
"@

    $html | Out-File -FilePath $OutputPath -Encoding UTF8
}
```

### Pattern 4: Color-Coded Console Output

```powershell
function Write-ColorOutput {
    param(
        [string]$Message,
        [ValidateSet("Success", "Error", "Warning", "Info")]
        [string]$Type = "Info"
    )

    $colors = @{
        Success = "Green"
        Error   = "Red"
        Warning = "Yellow"
        Info    = "Cyan"
    }

    $symbols = @{
        Success = "[+]"
        Error   = "[-]"
        Warning = "[!]"
        Info    = "[i]"
    }

    Write-Host "$($symbols[$Type]) $Message" -ForegroundColor $colors[$Type]
}

# Usage
Write-ColorOutput "Operation completed" -Type Success
Write-ColorOutput "File not found" -Type Error
Write-ColorOutput "Proceeding with caution" -Type Warning
```

### Pattern 5: Email Reporting

```powershell
function Send-EmailReport {
    param(
        [string]$To,
        [string]$Subject,
        [string]$Body,
        [string[]]$Attachments
    )

    $params = @{
        To         = $To
        From       = "automation@company.com"
        Subject    = $Subject
        Body       = $Body
        BodyAsHtml = $true
        SmtpServer = "smtp.company.com"
    }

    if ($Attachments) {
        $params.Attachments = $Attachments
    }

    Send-MailMessage @params
}
```

---

## Related Resources

- 📖 [CONTRIBUTING](../CONTRIBUTING.md)
- 📖 [Script Catalog](Script-Catalog.md)
- 📖 [Code of Conduct](../CODE_OF_CONDUCT.md)
- 🔗 [PowerShell Best Practices](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines)
- 🔗 [PSScriptAnalyzer Rules](https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/rules/readme)

---

**For Contributors:** This guide is for Bug-Free Umbrella developers
