# Script Compatibility

How the collection's compatibility claims are derived, and what is actually machine-checked.

**Last Updated:** 2026-09-17
**Standard revision:** 2.0.0

---

## Counting convention

One convention, stated once, used everywhere:

```
onDiskScripts = totalScripts + excludedScripts
```

- **566** non-test `.ps1` files on disk under `scripts/`.
- **381** catalogued in `scripts/.catalog/metadata.json` — this is what `totalScripts` reports,
  and what the generated module and `docs/Module.md` cover.
- **185** excluded: the deprecated forwarding-shim trees
  `scripts/endpoints/devices/winget/` and `scripts/endpoints/devices/proactive-remediations/`,
  whose files forward to canonical implementations under `scripts/endpoints/remediation/`.

`tools/Build-Catalog.ps1` emits all three counts plus `excludedPaths` and `countingConvention`,
and `scripts/.catalog/metadata.schema.json` defines them.

## PowerShell version support

Derived from each script's `.NOTES` `Prerequisite` field and its `#Requires` directive across the
381 catalogued scripts:

| Declaration | Scripts |
|---|---|
| `PowerShell 7.0` | 288 |
| `PowerShell 5.1+` | 74 |
| Other variants (5.1+ plus a module, privilege, or platform qualifier) | 19 |
| `#Requires -Version` opt-out present | 8 |
| No opt-out — must remain parse-clean under both 7.x and 5.1 semantics | 373 |

The version story is enforced mechanically: `tools/Test-Standards.ps1` fails a script that uses
PowerShell 7-only syntax (ternary, `??`, `&&`, `||`) without a `#Requires -Version 7.0` opt-out on
line 1, and CI runs that check on every pull request.

## Platform support

**There is no machine-checked per-operating-system matrix in this repository, and this page does not
claim one.** The published figures that previously appeared here (percentage tables for Windows,
Linux and macOS) were not reproducible from any data source in the tree and were removed in v2.0.0
rather than carried forward.

What is true and checkable:

- The Pester suite runs offline on **Linux** `pwsh` — that is the CI environment — so every catalogued
  script has a mirrored suite that executes without Windows, network access, elevation, or installed
  product modules.
- Windows-only surface (registry providers, `Get-CimInstance`/WMI classes, `Get-SmbShare`,
  service control, `DnsServer`/`DhcpServer`/`FailoverClusters`) is exercised through declared stub
  functions that Pester mocks, which keeps the suite portable but does **not** prove the script
  behaves correctly on Windows.
- PSScriptAnalyzer's `PSUseCompatibleCmdlets` rule is deliberately excluded from the settings of
  record (`.vscode/PSScriptAnalyzerSettings.psd1`), so no analyzer pass validates cmdlet availability
  per platform.
- Scripts that require a product module (`Az.*`, `ExchangeOnlineManagement`, VMware PowerCLI,
  `Hyper-V`, `IISAdministration`, …) guard the import inside `Main` and exit 1 with a `[-]` line when
  it is absent; that guard is tested, the module itself is not.

To establish platform support for a specific script, read its `.NOTES` `Prerequisite` field and its
`#Requires` line, and run it on the target platform. Do not infer support from the script's presence
in the catalog.

## See also

- [Catalog Automation](../../docs/Catalog-Automation.md) — how the catalog and its counts are produced.
- [STANDARDS](../../docs/STANDARDS.md) — the compatibility rules a script must satisfy.
- [Prerequisites](../../docs/Prerequisites.md) — modules and setup for running the collection.
