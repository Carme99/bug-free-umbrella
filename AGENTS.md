# AGENTS.md - Bug-Free Umbrella

> PowerShell enterprise automation toolkit (260+ scripts). PowerShell 7.0+, Pester 5.5.0+, PSScriptAnalyzer.

---

## Build / Test / Lint Commands

```powershell
# Run all tests
$config = Import-PowerShellDataFile -Path ./Tests/Pester.Config.psd1
$pesterConfig = New-PesterConfiguration -Hashtable $config
Invoke-Pester -Configuration $pesterConfig

# Run single test file
Invoke-Pester -Path ./Tests/Script.Tests.ps1

# Run single test by name
Invoke-Pester -Path ./Tests/Script.Tests.ps1 -Name "Test Name"

# Lint a script
Invoke-ScriptAnalyzer -Path ./YourScript.ps1

# Lint all scripts
Get-ChildItem -Path ./scripts -Recurse -Include *.ps1 | ForEach-Object {
    Invoke-ScriptAnalyzer -Path $_.FullName
}

# View script help
Get-Help .\YourScript.ps1 -Detailed
```

---

## Code Style Guidelines

### Formatting
- **Indentation:** 4 spaces (no tabs)
- **Line endings:** CRLF for .ps1 files
- **Max line length:** 120 characters
- **Encoding:** UTF-8 with BOM
- **Trailing whitespace:** Remove

### Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Functions | Verb-Noun (PascalCase) | `Get-UserSettings` |
| Variables | camelCase | `$userName` |
| Constants | UPPERCASE | `$MAX_RETRIES` |
| Parameters | PascalCase | `-UserName` |

Use only approved verbs: `Get-Verb` to check.

### Required Script Header

```powershell
<#
.SYNOPSIS
    Brief description.

.DESCRIPTION
    Detailed description.

.PARAMETER Name
    Parameter description.

.EXAMPLE
    PS C:\> .\Script.ps1 -Name Value

.NOTES
    File Name  : Script.ps1
    Author     : Your Name
    Prerequisite: PowerShell 7.0
    Version    : 1.0.0
    Date       : 2025-01-01
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Name
)
```

### Error Handling

```powershell
$ErrorActionPreference = 'Stop'

try {
    Write-Host "[*] Processing..." -ForegroundColor Cyan

    if (-not $Param) { throw "Parameter required" }

    $result = Get-Something -ErrorAction Stop

    Write-Host "[+] Success" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
```

### Output Messages
```powershell
Write-Host "[+] Success" -ForegroundColor Green
Write-Host "[!] Warning" -ForegroundColor Yellow
Write-Host "[-] Error"   -ForegroundColor Red
Write-Host "[*] Info"     -ForegroundColor Cyan
```

### Best Practices

1. Always use `[CmdletBinding()]` for advanced functions
2. Use `-ErrorAction Stop` for critical operations
3. Include comment-based help (REQUIRED)
4. Use `SupportsShouldProcess` for destructive operations
5. Validate parameters with `[Validate*]` attributes
6. Check module availability before use
7. Use secure methods for credentials (env vars, Key Vault - never hardcode)
8. Make scripts idempotent (safe to run multiple times)

### Test Structure
```powershell
#Requires -Modules Pester

Describe "ScriptName" {
    Context "Parameter Validation" {
        It "Should require mandatory parameters" { }
    }
    Context "Functionality" {
        It "Should perform expected action" { }
    }
}
```

---

## Project Structure

```
scripts/
├── automation/    # CI/CD, IaC
├── cloud/         # Azure, AWS, Kubernetes
├── collaboration/ # M365, Exchange
├── data/          # Databases, APIs
├── endpoints/    # Intune, devices
├── infrastructure/ # Servers, networking
├── security/      # Compliance, hardening
└── utilities/     # General tools
Tests/             # Pester tests
```

---

## Commit & Branch Style

- **Commits:** `type: description` (feat, fix, docs, test, refactor)
- **Branches:** `feature/name`, `fix/description`, `docs/changes`

---

## Required Modules

| Module | Purpose |
|--------|---------|
| Microsoft.Graph | M365, Intune, Teams APIs |
| Az | Azure management |
| ExchangeOnlineManagement | Exchange Online admin |
| MicrosoftTeams | Teams management |
| Pester 5.5+ | Unit testing |
| PSScriptAnalyzer | Linting |
| AWSPowerShell | AWS management |
| dbatools | SQL Server automation |
| ImportExcel | Excel reporting |
| Posh-SSH | Linux/SSH automation |
| Kubernetes | K8s cluster management |

---

## GitHub Issue Format

For the standard issue format, use the issue templates in [`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE/):
[`bug_report.yml`](.github/ISSUE_TEMPLATE/bug_report.yml), [`feature_request.yml`](.github/ISSUE_TEMPLATE/feature_request.yml), and [`script_request.yml`](.github/ISSUE_TEMPLATE/script_request.yml). See also the issue-format guidance in [CONTRIBUTING.md](CONTRIBUTING.md) and [GOVERNANCE.md](GOVERNANCE.md).

---

## Key Notes

- Run PSScriptAnalyzer before committing
- Test on PowerShell 7 and verify 5.1 compatibility
- Follow existing script patterns in the same directory
- Return proper exit codes (0 success, 1 failure)