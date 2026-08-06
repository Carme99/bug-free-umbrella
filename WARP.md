# WARP.md - Bug-Free Umbrella Working Agreement & Repository Practices

> Working agreement and repository practices for the Bug-Free Umbrella PowerShell enterprise automation toolkit (260+ scripts).

---

## Common Development Commands

Run the standard commands documented in [AGENTS.md](./AGENTS.md) for building, testing, and linting:

```powershell
# Run all tests
$config = Import-PowerShellDataFile -Path ./Tests/Pester.Config.psd1
$pesterConfig = New-PesterConfiguration -Hashtable $config
Invoke-Pester -Configuration $pesterConfig

# Run a single test file
Invoke-Pester -Path ./Tests/Script.Tests.ps1

# Lint a script
Invoke-ScriptAnalyzer -Path ./YourScript.ps1

# Lint all scripts
Get-ChildItem -Path ./scripts -Recurse -Include *.ps1 | ForEach-Object {
    Invoke-ScriptAnalyzer -Path $_.FullName
}

# View script help
Get-Help .\YourScript.ps1 -Detailed
```

See the `examples/` directory for runnable usage examples of common patterns.

---

## Repository Architecture

The repository is organised around **7 technology domains** (plus a `utilities/` folder for general tools). Every script lives under one of these top-level folders:

```
scripts/
├── automation/    # CI/CD, IaC
├── cloud/         # Azure, AWS, containers
├── collaboration/ # Microsoft 365, Exchange, Teams
├── data/          # Databases, APIs
├── endpoints/     # Intune, devices, proactive remediations
├── infrastructure/ # Windows servers, monitoring, AD
├── security/      # Compliance, hardening
└── utilities/     # General tools
Tests/             # Pester tests (mirrors the scripts/ layout)
```

Examples of the concrete layout:

- `scripts/endpoints/intune/reporting` - Intune compliance and device reporting
- `scripts/infrastructure/windows/monitoring` - Windows server and endpoint monitoring
- `scripts/cloud/azure/core` - Core Azure resource automation

The layout was restructured in **v3.0.0** to group scripts by technology domain rather than by task type, so related automation lives together and is easy to discover.

---

## Testing Strategy

- All tests use **Pester 5.5.0+**. Test files live under `./Tests` and mirror the `scripts/` directory structure.
- Configuration is centralised in `./Tests/Pester.Config.psd1`, which runs the suite, enables **code coverage** against `./scripts`, and excludes `Integration`-tagged tests by default.
- Each test file follows the `Describe` / `Context` / `It` structure with `#Requires -Modules Pester` at the top.
- See the `Tests/Common/HelperFunctions.Tests.ps1` file for the shared helper test conventions.
- Always test in **non-production** environments first; most scripts are **NOT recommended** for direct production use until validated.

---

## Contributing Guidelines

Contributors should follow the guidance in [CONTRIBUTING.md](./CONTRIBUTING.md) and the working practices recorded here:

- Use **semantic commit** messages (`feat:`, `fix:`, `docs:`, etc.) as described in [AGENTS.md](./AGENTS.md).
- Ensure every script is **PSScriptAnalyzer** compliant by running `Invoke-ScriptAnalyzer` before committing.
- Include comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`) on every script.
- Run Pester tests for your changes and keep the full suite green.
- Keep the GitHub **wiki** up to date (it is the primary documentation source); update the relevant pages when you change scripts or paths.
- Follow the existing script patterns in the same directory.

---

## Important Notes

- **PowerShell version requirement:** Supports **PowerShell 5.1+** and is developed and tested on **PowerShell 7**; verify 5.1 compatibility as noted in AGENTS.md.
- Many scripts require **Administrator** privileges (most perform device, server, or tenant-level operations).
- Credentials must never be hardcoded - use environment variables or Key Vault / secure methods.
- All `.ps1` files use CRLF line endings and UTF-8 with BOM.

---

**Maintainers:** [Carme99](https://github.com/Carme99) with Claude Code.