# Script Catalog

This directory contains metadata and compatibility information for all scripts in the bug-free-umbrella repository.

## Files in This Directory

| File | Description |
|------|-------------|
| **COMPATIBILITY.md** | Human-readable compatibility matrix showing platform, PowerShell version, and dependency compatibility for key scripts |
| **compatibility-matrix.json** | Machine-readable JSON compatibility data for automated tooling and validation |
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

**Automated compatibility checking:**
```powershell
# Load compatibility data
$compat = Get-Content "scripts/.catalog/compatibility-matrix.json" | ConvertFrom-Json

# Check if a script supports Linux
$script = $compat.compatibility.'monitoring/Monitor-ServerHealth.ps1'
$linuxSupported = $script.platforms.linux.supported

# Get all cross-platform scripts
$crossPlatform = $compat.compatibility.PSObject.Properties | Where-Object {
    $_.Value.platforms.linux.supported -eq $true -and
    $_.Value.platforms.macos.supported -eq $true
}
```

**CI/CD integration:**
- Use `compatibility-matrix.json` in automated testing
- Validate script compatibility before deployment
- Generate platform-specific package lists

## Compatibility Data Structure

### compatibility-matrix.json Schema

```json
{
  "compatibility": {
    "category/ScriptName.ps1": {
      "platforms": { ... },
      "powershell": { ... },
      "dependencies": { ... },
      "tested": { ... }
    }
  },
  "platformSummary": { ... },
  "powershellVersions": { ... },
  "categorySummary": { ... }
}
```

### Key Fields

- **platforms** - OS compatibility (windows, linux, macos)
- **powershell** - PowerShell version requirements
- **dependencies** - Required modules, features, permissions
- **tested** - Production vs non-production testing status
- **cloudServices** - Required cloud service dependencies

## Contributing

When adding new scripts:

1. **Update compatibility-matrix.json** with full compatibility data
2. **Add example to COMPATIBILITY.md** if the script is notable
3. **Update category summaries** with new script counts
4. **Test on target platforms** before marking as supported

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for detailed guidelines.

## Statistics

- **Total Scripts:** 358
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

- [x] Complete metadata.json with all 358 scripts
- [ ] Automated compatibility testing in CI/CD
- [ ] Platform-specific script bundles
- [ ] Interactive web-based script browser
- [ ] Tag-based search and filtering
- [ ] Dependency graph visualization

## Questions?

- **General usage:** See [Getting Started Guide](../../docs/Getting-Started.md)
- **Detailed docs:** Visit the [Documentation Hub](../../docs/README.md)
- **Issues:** [GitHub Issues](https://github.com/Carme99/bug-free-umbrella/issues)
