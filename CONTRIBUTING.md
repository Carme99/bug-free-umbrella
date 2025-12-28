# Contributing to Bug-Free Umbrella

Thank you for your interest in contributing to Bug-Free Umbrella! This document provides guidelines for contributing to the repository.

## 🤖 Development Tools

This repository uses **[Claude Code](https://github.com/anthropics/claude-code)**, Anthropic's official CLI for Claude AI, to assist with script development and maintenance.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Testing Requirements](#testing-requirements)
- [Pull Request Process](#pull-request-process)
- [Style Guide](#style-guide)

## Code of Conduct

This project adheres to a Code of Conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to the repository maintainers.

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
3. **Make your changes**
4. **Test thoroughly**
5. **Commit your changes** (`git commit -m 'Add some AmazingFeature'`)
6. **Push to the branch** (`git push origin feature/AmazingFeature`)
7. **Open a Pull Request**

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

### Test Coverage Requirements

- **Minimum 70% code coverage** for new scripts
- **100% coverage** for critical functions
- Include tests for:
  - Parameter validation
  - Error handling
  - Edge cases
  - Success scenarios

## Pull Request Process

### Before Submitting

1. **Run PSScriptAnalyzer**
   ```powershell
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings .vscode/PSScriptAnalyzerSettings.psd1
   ```

2. **Run Tests**
   ```powershell
   Invoke-Pester -Configuration (New-PesterConfiguration -Hashtable (Import-PowerShellDataFile ./Tests/Pester.Config.psd1))
   ```

3. **Update Documentation**
   - Update relevant README files
   - Add examples to documentation
   - Update CHANGELOG.md

4. **Test Manually**
   - Test in PowerShell 5.1 and 7+
   - Test on Windows 10/11 and Server 2019/2022
   - Verify expected behavior

### PR Checklist

- [ ] Code passes PSScriptAnalyzer with no errors
- [ ] All Pester tests pass
- [ ] New functionality has tests
- [ ] Comment-based help is complete
- [ ] README.md updated (if needed)
- [ ] CHANGELOG.md updated
- [ ] Examples tested and working
- [ ] No breaking changes (or documented)

### PR Title Format

Use conventional commit format:

- `feat: Add new feature`
- `fix: Fix bug in script`
- `docs: Update documentation`
- `test: Add tests for feature`
- `refactor: Refactor script structure`
- `perf: Improve performance`
- `chore: Update build process`

### PR Description Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
Describe testing performed

## Checklist
- [ ] Code passes PSScriptAnalyzer
- [ ] Tests pass
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
```

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
- Questions about contributing
- Clarification on guidelines
- Discussion of proposed changes

## Recognition

Contributors will be recognized in:
- Repository README
- Release notes
- Contributor list

Thank you for contributing to Bug-Free Umbrella! 🎉
