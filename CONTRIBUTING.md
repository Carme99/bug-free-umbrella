# Contributing to Bug-Free Umbrella

Thanks for your interest in this project! Bug-Free Umbrella is a solo project maintained by one developer using [Claude Code](https://github.com/anthropics/claude-code). While this is primarily a personal toolkit, contributions and suggestions are welcome.

## 🤖 Development Approach

All scripts are developed with assistance from **[Claude Code](https://github.com/anthropics/claude-code)**, Anthropic's official CLI for Claude AI.

## 📋 Table of Contents

- [How You Can Help](#how-you-can-help)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Testing Requirements](#testing-requirements)
- [Pull Request Process](#pull-request-process)
- [Style Guide](#style-guide)

## How You Can Help

Since this is a solo project, the most helpful contributions are:

- **Bug Reports** - Found an issue? Let me know!
- **Script Suggestions** - Need a specific automation? Open an issue
- **Documentation Improvements** - Spotted a typo or unclear instruction? PRs welcome
- **Script Enhancements** - Improvements to existing scripts are appreciated

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues. When creating a bug report, include:

- **Clear title and description**
- **Steps to reproduce** the behavior
- **Expected behavior**
- **Actual behavior**
- **PowerShell version** (`$PSVersionTable.PSVersion`)
- **Operating system** and version
- **Error messages** and stack traces
- **Screenshots** if applicable

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, include:

- **Clear title and description**
- **Use case** - Why is this enhancement useful?
- **Expected behavior** - What should happen?
- **Alternative solutions** - Have you considered alternatives?

### Contributing Code

1. **Fork the repository**
2. **Create a feature branch** (`git checkout -b feature/AmazingFeature`)
3. **Make your changes** (follow the coding standards below)
4. **Test your changes**
5. **Open a Pull Request** with a clear description

Note: As a solo maintainer, PR reviews may take some time. Patience is appreciated!

## Development Setup

### Prerequisites

- **PowerShell 7.0+** (recommended) or PowerShell 5.1+
- **Git** for version control
- **Visual Studio Code** (recommended IDE)

### Recommended VS Code Extensions

- PowerShell
- EditorConfig for VS Code
- GitLens

### Install Development Dependencies

```powershell
# Install PSScriptAnalyzer
Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck

# Install Pester for testing
Install-Module -Name Pester -MinimumVersion 5.5.0 -Force -SkipPublisherCheck

# Install platyPS for help generation
Install-Module -Name platyPS -Force -SkipPublisherCheck
```

### Clone and Setup

```powershell
# Clone your fork
git clone https://github.com/YOUR-USERNAME/bug-free-umbrella.git
cd bug-free-umbrella

# Add upstream remote
git remote add upstream https://github.com/Carme99/bug-free-umbrella.git

# Create a branch
git checkout -b feature/my-feature
```

## Coding Standards

### PowerShell Script Requirements

All PowerShell scripts MUST:

1. **Pass PSScriptAnalyzer** with no errors
   ```powershell
   Invoke-ScriptAnalyzer -Path ./YourScript.ps1 -Settings .vscode/PSScriptAnalyzerSettings.psd1
   ```

2. **Include Comment-Based Help**
   - `.SYNOPSIS`
   - `.DESCRIPTION`
   - `.PARAMETER` for each parameter
   - `.EXAMPLE` (at least one)
   - `.NOTES` with author, version, prerequisites

3. **Use Approved Verbs**
   - `Get-Verb` shows approved verbs
   - Use `Get-`, `Set-`, `New-`, `Remove-`, etc.

4. **Follow Naming Conventions**
   - PascalCase for functions: `Get-UserSettings`
   - camelCase for variables: `$userName`
   - UPPERCASE for constants: `$MAX_RETRIES`

5. **Error Handling**
   - Use `try-catch` blocks
   - Set `$ErrorActionPreference` appropriately
   - Provide meaningful error messages

### Script Structure Template

```powershell
<#
.SYNOPSIS
    Brief description of what the script does.

.DESCRIPTION
    Detailed description including:
    - What problem it solves
    - How it works
    - Important behavioral notes

.PARAMETER ParameterName
    Description of the parameter.

.EXAMPLE
    PS C:\> .\YourScript.ps1 -Parameter Value

    Description of what this example does.

.NOTES
    File Name      : YourScript.ps1
    Author         : Your Name
    Prerequisite   : PowerShell 7.0
    Version        : 1.0.0
    Date           : 2025-12-28
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ParameterName
)

$ErrorActionPreference = 'Stop'

try {
    # Your code here
    Write-Host "Processing..." -ForegroundColor Cyan

    # Main logic

    Write-Host "Completed successfully!" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
```

## Testing Requirements

### Unit Tests with Pester

All new scripts MUST include Pester tests:

```powershell
# Create test file in Tests/ directory
# Tests/YourScript.Tests.ps1

#Requires -Modules Pester

Describe "YourScript" {
    Context "Parameter Validation" {
        It "Should require mandatory parameters" {
            # Test here
        }
    }

    Context "Functionality" {
        It "Should perform expected action" {
            # Test here
        }
    }

    Context "Error Handling" {
        It "Should handle errors gracefully" {
            # Test here
        }
    }
}
```

### Running Tests

```powershell
# Run all tests
$config = Import-PowerShellDataFile -Path ./Tests/Pester.Config.psd1
$pesterConfig = New-PesterConfiguration -Hashtable $config
Invoke-Pester -Configuration $pesterConfig

# Run specific test file
Invoke-Pester -Path ./Tests/YourScript.Tests.ps1
```

### Test Coverage Guidelines

While formal test coverage isn't strictly enforced for this project, good tests are appreciated:
- Parameter validation tests
- Error handling tests
- Basic functionality tests

Pester tests are welcome but not required for contributions.

## Pull Request Process

### Before Submitting

1. **Run PSScriptAnalyzer** - Ensure no major errors
   ```powershell
   Invoke-ScriptAnalyzer -Path ./YourScript.ps1
   ```

2. **Test Your Changes** - Verify the script works as expected

3. **Update Documentation** - Add examples or update README if needed

### PR Guidelines

- Clear title and description
- Explain what the change does and why
- Include usage examples if adding new functionality
- Note any breaking changes

As a solo project, PR reviews may take time. I'll do my best to respond within a week or two.

## Style Guide

### Indentation and Whitespace

- **4 spaces** for indentation (no tabs)
- **No trailing whitespace**
- **One blank line** between functions
- **Consistent bracing** (opening brace on same line)

### Comments

```powershell
# Good: Descriptive comment
$users = Get-MgUser -All

# Bad: Obvious comment
$users = Get-MgUser -All  # Get all users
```

### Variable Naming

```powershell
# Good
$userPrincipalName = "user@contoso.com"
$maxRetries = 3
$COMPANY_DOMAIN = "contoso.com"

# Bad
$upn = "user@contoso.com"  # Too abbreviated
$max_retries = 3           # Wrong case
$companyDomain = "contoso.com"  # Should be constant
```

### Function Naming

```powershell
# Good
function Get-UserSettings { }
function Set-RegionalConfiguration { }

# Bad
function GetUser { }  # Missing approved verb
function Update_Settings { }  # Underscore not allowed
```

### Output Messages

```powershell
# Use color coding
Write-Host "[+] Success message" -ForegroundColor Green
Write-Host "[!] Warning message" -ForegroundColor Yellow
Write-Host "[-] Error message" -ForegroundColor Red
Write-Host "[*] Information message" -ForegroundColor Cyan
```

## Documentation

### README Updates

When adding new scripts:

1. Update category README with script description
2. Add usage examples
3. List features
4. Document prerequisites
5. Update script count

### Comment-Based Help

All functions and scripts must have complete help:

```powershell
<#
.SYNOPSIS
    One-line description

.DESCRIPTION
    Detailed description with multiple lines if needed

.PARAMETER Name
    Parameter description

.EXAMPLE
    PS C:\> Example usage

    Explanation of example

.NOTES
    Additional information

.LINK
    Related links
#>
```

## Version Control

### Commit Messages

Write clear, descriptive commit messages:

```
feat: Add parallel processing to user settings script

- Implement ForEach-Object -Parallel for bulk operations
- Add throttle limit of 10 concurrent operations
- Fall back to sequential for PowerShell 5.1
- Improves performance by ~5x for 100+ users
```

### Branch Naming

- `feature/feature-name` - New features
- `fix/bug-description` - Bug fixes
- `docs/what-changed` - Documentation updates
- `test/test-description` - Test additions
- `refactor/what-refactored` - Code refactoring

## Questions?

Feel free to open an issue for:
- Questions about the scripts
- Suggestions for improvements
- Bug reports or feature requests

## Recognition

All contributors will be acknowledged in the release notes and README.

Thanks for helping improve Bug-Free Umbrella! 🎉
