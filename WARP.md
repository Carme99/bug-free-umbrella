# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Common Development Commands

### Running Tests
```powershell
# Run all tests using Pester
$pesterConfig = Import-PowerShellDataFile -Path ./Tests/Pester.Config.psd1
Invoke-Pester -Configuration $NewPesterConfig

# Run specific test file
Invoke-Pester -Path ./Tests/Common/HelperFunctions.Tests.ps1

# Run tests for a specific script
Invoke-Pester -Path ./scripts/collaboration/microsoft365/exchange-online/Manage-QuarantinedEmails.Tests.ps1
```

### Linting and Analysis
```powershell
# Run PSScriptAnalyzer with custom settings (more lenient than defaults)
Invoke-ScriptAnalyzer -Path ./scripts -Settings .vscode/PSScriptAnalyzerSettings.psd1 -Recurse

# Run PSScriptAnalyzer with default strict rules
Invoke-ScriptAnalyzer -Path ./scripts -Severity Error,Warning -Recurse

# Check syntax of all PowerShell scripts
Get-ChildItem -Path ./scripts -Filter *.ps1 -Recurse | ForEach-Object {
    try { $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $_.FullName -Raw), [ref]$null) }
    catch { Write-Host "$($_.FullName): $($_.Exception.Message)" -ForegroundColor Red }
}
```

### Running Individual Scripts
```powershell
# Example: Check Intune device compliance
cd scripts/endpoints/intune/reporting
.\Get-DeviceComplianceReport.ps1

# Example: Monitor server health
cd scripts/infrastructure/windows/monitoring
.\Monitor-ServerHealth.ps1

# Example: Check Azure resources
cd scripts/cloud/azure/core
.\Monitor-AzureResources.ps1

# Always test with -WhatIf parameter when available
.\Your-Script.ps1 -WhatIf
```

## Repository Architecture

This is a PowerShell automation repository containing 260+ production-ready scripts organized by technology domains:

### Top-Level Structure
- **scripts/**: All PowerShell scripts organized by technology (not flat categories)
- **Tests/**: Pester test files organized by domain
- **examples/**: Practical workflow examples using multiple scripts
- **wiki/**: Comprehensive documentation (primary documentation source)

### Script Organization (v3.0.0+ Technology-Based Hierarchy)

The repository moved from 20 flat categories to 7 technology domains in v3.0.0:

1. **cloud/**: ☁️ Cloud Platforms & Services
   - azure/ (AVD, compute, KeyVault, core)
   - aws/ (core services)
   - containers/ (Docker & Kubernetes)

2. **endpoints/**: 📱 Endpoint & Device Management
   - intune/ (deployment, maintenance, reporting)
   - devices/ (proactive-remediations, winget, autopatch, bitlocker, drivers)

3. **infrastructure/**: 🖥️ On-Premises & Hybrid
   - windows/ (Active Directory, Group Policy, monitoring, storage, system, updates)
   - linux/ (administration)
   - network/, virtualization/, web/, print/

4. **security/**: 🔒 Security & Compliance
   - compliance/frameworks/ (CIS, NIST, PCI-DSS, HIPAA, SOC2, ISO27001)
   - hardening/, monitoring/

5. **automation/**: ⚙️ DevOps & Automation
   - cicd/ (Azure DevOps, GitHub Actions, GitLab)
   - iac/ (Terraform, Bicep)

6. **collaboration/**: 👥 Microsoft 365 & Communication
   - microsoft365/ (azure-ad, exchange-online, teams, sharepoint, power-platform)
   - email/ (Exchange Server)

7. **data/**: 🗄️ Data Management
   - databases/ (SQL Server, MySQL, PostgreSQL, MongoDB)
   - api/ (API management)

8. **utilities/**: 🔧 General Utilities

## Script Development Requirements

### Essential Elements
1. **Comment-Based Help** with .SYNOPSIS, .DESCRIPTION, .PARAMETER, .EXAMPLE, .NOTES
2. **Error Handling** with try-catch blocks and meaningful error messages
3. **Parameter Validation** using PowerShell validation attributes
4. **Approved Verbs** from `Get-Verb` (Get-, Set-, New-, Remove-, etc.)
5. **PSScriptAnalyzer Compliance** - must pass with custom settings (see .vscode/PSScriptAnalyzerSettings.psd1)

### Naming Conventions
- Functions: PascalCase with approved verbs (Get-UserSettings)
- Variables: camelCase ($userName)
- Constants: UPPERCASE ($MAX_RETRIES)

### Module Dependencies
Scripts may require these modules (install as needed):
- Az (for Azure scripts)
- Microsoft.Graph and Microsoft.Graph.Intune (for Microsoft 365/Intune scripts)
- AWS.Tools.Common (for AWS scripts)

## Testing Strategy

### Pester Configuration
- Tests located in Tests/ directory, mirroring scripts/ structure
- Configuration in Tests/Pester.Config.psd1
- Excludes integration tests by default (tagged with 'Integration')
- Code coverage enabled for all scripts in ./scripts

### Test Types
- **HelperFunctions.Tests.ps1**: Common utility function tests
- Domain-specific test files: Each script should have a corresponding .Tests.ps1
- Integration tests: Tagged with 'Integration', excluded from default runs

## Contributing Guidelines

1. All scripts must pass PSScriptAnalyzer with custom settings
2. Scripts should be tested in non-production environments first
3. Documentation should be updated in the wiki, not in README files
4. Use semantic commit messages (feat:, fix:, docs:, etc.)
5. Include practical examples in examples/ directory for multi-script workflows

## Important Notes

- Most scripts require Administrator privileges and PowerShell 5.1+ (7+ recommended)
- This is a solo project maintained with Claude Code assistance
- Scripts are personal automation tools shared publicly
- Testing in production environments is NOT recommended
- Documentation has migrated to the GitHub wiki (primary source of truth)
- v3.0.0 introduced major restructuring from flat categories to technology domains