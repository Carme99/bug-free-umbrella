# Script Catalog

This directory contains metadata and compatibility information for all scripts in the bug-free-umbrella repository.

## Files in This Directory

| File | Description |
|------|-------------|
| **COMPATIBILITY.md** | How compatibility claims are derived, and what is actually machine-checked |
| **metadata.json** | Script index with tags, categories, parameters and quick reference (auto-generated via `tools/Build-Catalog.ps1`) |

## Purpose

The `.catalog` directory serves as a central registry for:

1. **Discoverability** - Find scripts by capability, platform, or use case
2. **Compatibility** - Understand which scripts work on your platform
3. **Dependencies** - Know what modules and permissions are required
4. **Automation** - Machine-readable data for CI/CD and tooling integration

## Using the Compatibility Matrix

### For Users

**Quick compatibility check:**
1. Open [COMPATIBILITY.md](COMPATIBILITY.md)
2. Find your script in the examples section
3. Check platform compatibility, PowerShell version, and dependencies

**Category-level compatibility:**
- See the "Category Compatibility" section for general guidance
- Cross-platform categories work on Windows, Linux, and macOS with PowerShell 7+
- Windows-only categories require Windows Server or Windows Client

### For Developers

**What is machine-checked:**

```powershell
# Every catalogued script, with its tags, parameters and required modules
$catalog = (Get-Content "scripts/.catalog/metadata.json" -Raw | ConvertFrom-Json).scripts

# Scripts that need the Microsoft.Graph module
$catalog | Where-Object { $_.requiresModules -contains 'Microsoft.Graph' } |
    Select-Object -ExpandProperty path

# Scripts that took the IoC route (no native exe reachable outside a wrapper)
$catalog | Where-Object { $_.hasCmdletBinding } | Measure-Object
```

`metadata.json` is the only machine-readable artifact here. There is no per-operating-system
matrix: the earlier `compatibility-matrix.json` covered 6 scripts with pre-relaunch data, was
consumed by nothing, and contradicted the counts reported everywhere else, so it was removed.
Read [COMPATIBILITY.md](COMPATIBILITY.md) for what is and is not claimed.

## Contributing

When adding new scripts:

1. **Regenerate metadata.json** with `tools/Build-Catalog.ps1` (never hand-edit it)
2. **Add example to COMPATIBILITY.md** if the script is notable
3. **State platform support honestly** - only claim what the script's tests actually exercise

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for detailed guidelines.

## Statistics

- **Total Scripts:** 381 catalogued (566 on disk including 185 excluded shims)
- **Cross-Platform:** ~200 (56%)
- **Windows-Only:** ~158 (44%)
- **Categories:** 30+

## Metadata Catalog (metadata.json)

`metadata.json` is auto-generated — do not edit by hand.

```powershell
# Regenerate
pwsh -File tools/Build-Catalog.ps1

# CI gate — exits 1 if stale
pwsh -File tools/Build-Catalog.ps1 -Validate

# With progress
pwsh -File tools/Build-Catalog.ps1 -Verbose
```

Schema and tooling are documented in [docs/Catalog-Automation.md](../../docs/Catalog-Automation.md).
Use `Invoke-Umbrella.ps1` at the repo root for interactive discovery:
`pwsh -File ./Invoke-Umbrella.ps1 -Search intune`.

## Roadmap

- [x] Complete metadata.json with all 381 catalogued scripts
- [ ] Automated compatibility testing in CI/CD
- [ ] Platform-specific script bundles
- [ ] Interactive web-based script browser
- [ ] Tag-based search and filtering
- [ ] Dependency graph visualization

## Questions?

- **General usage:** See [Getting Started Guide](../../docs/Getting-Started.md)
- **Detailed docs:** Visit the [Documentation Hub](../../docs/README.md)
- **Issues:** [GitHub Issues](https://github.com/Carme99/bug-free-umbrella/issues)
