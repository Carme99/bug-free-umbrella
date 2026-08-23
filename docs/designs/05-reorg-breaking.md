# 05 — Reorg Breaking Design Spec (Remediation Consolidation)

> **Status:** Draft — Foundation phase (no code). Implementation consumes this spec verbatim.
> **Version:** Target 5.0.0 Hurricane (major) · **Date:** 2026-08-20
> **Scope:** Filesystem reorg only. Module manifest/loader, CLI v2, test expansion, and docs generation are owned by sibling specs (`05-module-*`, `05-cli-v2`, `05-tests-*`, `05-docs-*`) — no overlap.

---

## 1. Goal & Non-Goals

**Goal:** Consolidate the two fragmented Intune remediation trees into a single discoverable hierarchy, eliminate the `detect.ps1` × 51 (plus winget `detect.ps1` × ~30) filename collision, and provide zero-breakage deprecation shims so existing Intune script packages referencing old paths continue to work through the 5.x lifecycle.

**Why this is breaking (and why 5.0.0):** Any consumer that hard-codes `scripts/endpoints/devices/winget/.../detect.ps1` or `scripts/endpoints/devices/proactive-remediations/.../detect.ps1` as an Intune "script package" path will need to update the portal assignment at next edit. Shims make the filesystem break non-fatal, but the canonical path change is a major-version signal (SemVer).

**Non-Goals (owned elsewhere):**

- Module manifest (`src/BugFreeUmbrella/BugFreeUmbrella.psd1`) and loader (`BugFreeUmbrella.psm1`) — see `05-module-manifest-build.md`.
- CLI enhancements (`Get-BUScript`, `Invoke-BUScript`, argument completers) — see `05-cli-v2.md`. CLI will *consume* the new hierarchy but does not define it.
- Pester expansion beyond reorg shim/exit-code coverage — see `05-tests-expansion.md`.
- `docs/Module.md` / `docs/ARCHITECTURE.md` generation — see `05-docs-site.md`.

---

## 2. Paths (≤ 3) — Authoritative File List

Implementation MUST touch **only** these paths for the reorg concern. Any other file touched is scope creep. Catalog tooling (`tools/Build-Catalog.ps1`, `scripts/.catalog/metadata.json`) is a *consumer* that will auto-pick up moves via filesystem scan — no hand-edit required — but if a one-line category-derivation tweak is needed it is explicitly allowed as an in-budget exception.

| # | Path | Current state on `main` (v4.4.0 Nimbus) | Change in 5.0.0 |
|---|------|------------------------------------------|-----------------|
| **P1** | `scripts/endpoints/remediation/` | **Does not exist** | **Create.** New canonical root. Contains 4 top-level subfolders (see §3), `README.md` with migration guide, and all moved scripts with Verb-Noun filenames. This is the only path that receives *new* files. |
| **P2** | `scripts/endpoints/devices/winget/` | ~30 app folders (browsers, communication, development, media, productivity, remote-access, runtimes, utilities, vendor-specific, security) each with `detect.ps1` + `remediate.ps1` (plus variants `remediate_Force_Close.ps1`, `remediate_maintenance_window.ps1`). 2 working examples: `browsers/Firefox/detect.ps1` (92 lines, `Mozilla.Firefox`, SYSTEM-aware via `Microsoft.WinGet.Client` fallback), `browsers/Firefox/remediate.ps1`. Total ~62 winget scripts. | **Retain as shim tree.** Every `detect.ps1` / `remediate.ps1` (and variant) is replaced by a 3-line wrapper that `Write-Warning` + dot-sources the new canonical file and preserves exit codes. No business logic remains here. Shims are CRLF+BOM, comment-based help stub, `PSScriptAnalyzer` clean. Retained until **6.0.0** (next major), then deleted per deprecation policy. |
| **P3** | `scripts/endpoints/devices/proactive-remediations/` | 51 remediation folders (`Fix-*`, `Check-*`, plus 3 lowercase `keyboard-layout` etc.) each with `detect.ps1` + `remediate.ps1`. Examples: `Fix-TeamsCache/detect.ps1` (140 lines, SYSTEM-aware `Win32_UserProfile` scan, exits 0/1), `Check-BatteryHealth/detect.ps1` (70% threshold, `Win32_Battery` + `powercfg /batteryreport`), `Fix-TimeSync`, `Check-DeviceHealthScore`, etc. Total 102 scripts. Catalog category currently `endpoints/devices/proactive-remediations/<Folder>`. | **Retain as shim tree.** Same treatment as P2: every `detect.ps1`/`remediate.ps1` becomes a 3-line wrapper forwarding to `P1` under the correct subfolder (`system`/`network`/`security`). Lowercase legacy folders (`keyboard-layout`, `language-pack-audit`, `region-language-settings`) are shimmed and their canonical targets use PascalCase (`KeyboardLayout` etc.) consistent with `NAMING_CONVENTIONS.md`. Retained until 6.0.0. |

> **Why 3 counts as ≤ 3:** `scripts/endpoints/remediation/README.md` lives *inside* P1 — it is not a fourth top-level path. The reorg intentionally touches no other roots.

**Encoding / style contract (all 3 paths):** PowerShell 7+, 4-space indent, **CRLF + BOM** (required for `.ps1`/`.psm1`/`.psd1` per `.editorconfig`), comment-based help on every shim *and* every canonical script (`.SYNOPSIS`, `.DESCRIPTION`, `.NOTES` with `Exit 0/1` Intune contract), Approved Verbs only (`Invoke`, `Test` for detect/remediate pair), `PSScriptAnalyzer` **Errors** fail CI (`Warning` also gated via `Severity = @('Error','Warning')`, see `.vscode/PSScriptAnalyzerSettings.psd1`).

---

## 3. New Hierarchy — `scripts/endpoints/remediation/` (P1)

### 3.1 Top-Level Layout (4 subfolders)

```
scripts/endpoints/remediation/                  # P1 — canonical root (NEW)
├── README.md                                   # Migration guide + deprecation timeline
├── winget/                                     # All winget-managed app updates (moved from P2)
│   ├── browsers/                               # Chrome, Firefox
│   │   ├── Firefox/
│   │   │   ├── Test-WingetFirefox.ps1          # detect  — Approved Verb Test-
│   │   │   └── Invoke-WingetFirefox.ps1        # remediate — Approved Verb Invoke-
│   │   └── GoogleChrome/
│   │       ├── Test-WingetGoogleChrome.ps1
│   │       └── Invoke-WingetGoogleChrome.ps1
│   ├── communication/                          # Discord, Slack
│   ├── development/                            # Git, VS Code, PowerShell7, AzureCLI, …
│   ├── media/                                  # Zoom, OBS, VLC
│   ├── productivity/                           # AdobeReader, Teams, NotepadPlusPlus, …
│   ├── remote-access/                          # TeamViewer*, WinSCP
│   ├── runtimes/                               # Cpp*Redist, EdgeWebView2
│   ├── security/                               # 1Password
│   ├── utilities/                              # SevenZip
│   ├── vendor-specific/                        # Lenovo*
│   └── _templates/                             # detect_v3.ps1, remediate_v3_*.ps1 (canonical templates)
├── system/                                     # Device/system health & maintenance
│   ├── Invoke-RemediationFixTeamsCache.ps1     # — or Test-/Invoke- pair per §3.2
│   ├── Invoke-RemediationFixTimeSync.ps1
│   ├── Test-RemediationCheckBatteryHealth.ps1
│   ├── Test-RemediationCheckDeviceHealthScore.ps1
│   ├── Invoke-RemediationFixDiskSpace.ps1
│   ├── Invoke-RemediationFixStaleProfiles.ps1
│   ├── … (flat file list — see §3.3 taxonomy)
│   └── hardware/                               # Optional sub-namespace for battery/disk/memory (see §3.3)
├── network/                                    # Network & connectivity
│   ├── Invoke-RemediationFixDNSCache.ps1
│   ├── Invoke-RemediationFixNetworkAdapterPowerManagement.ps1
│   ├── Invoke-RemediationFixSMBv1Protocol.ps1
│   └── Test-RemediationCheckSharedFolders.ps1
└── security/                                   # Security & compliance
    ├── Test-RemediationCheckSecurityBaseline.ps1
    ├── Test-RemediationCheckDefenderHealthStatus.ps1
    ├── Test-RemediationCheckTPMStatus.ps1
    ├── Test-RemediationCheckLocalAdminAccounts.ps1
    ├── Invoke-RemediationFixBitLockerNotEscrowedKeys.ps1
    ├── Invoke-RemediationFixPowerShellExecutionPolicy.ps1
    └── Invoke-RemediationFixCertificateExpiry.ps1
```

**4 subfolders are normative:** `winget`, `system`, `network`, `security`. No fifth top-level folder. The word "hardware" in the assignment's example `Check-BatteryHealth → hardware` is interpreted as **a sub-namespace under `system/`** (`system/hardware/`), *or* as a tag that maps to `system/` — see §3.3. This preserves the 4-folder contract while giving hardware checks a logical home.

- `winget/` **retains** its 10 category subfolders and per-app leaf folders (so `winget/browsers/Firefox/` still exists, just under `remediation/`). This minimizes Intune operator re-learning and keeps winget app generation (`_generate-winget-scripts.ps1` + `_templates/`) working with a one-line path-variable change.
- `system/` / `network/` / `security/` are **flat** (one file or one per-remediation folder per entry) — no per-category nesting, because proactive remediations are already leaf-named (`Fix-*`/`Check-*`). A future `system/hardware/` subfolder is permitted but not required for 5.0.0; if introduced it MUST be documented in `P1/README.md`.

### 3.2 Naming Convention — Eliminating `detect.ps1` × 51

**Problem on `main`:** `detect.ps1` appears 51 times under `proactive-remediations/` and ~30 times under `winget/`. Grep, catalog disambiguation, and `Get-BUScript -Name detect.ps1` are ambiguous. PSSA and `Pester` file-discovery also struggle with duplicate leaf names.

**Canonical naming (P1):** Every script uses **Approved Verb + `Remediation` + `<PascalCaseName>`** and is unique repo-wide.

| Role | Verb | Pattern | Example (canonical path) | Intune usage |
|------|------|---------|---------------------------|--------------|
| **Detect** (exit 0 = healthy, 1 = needs remediation) | `Test-` | `Test-Remediation<Name>.ps1` or `Test-Winget<App>.ps1` | `scripts/endpoints/remediation/system/Test-RemediationFixTeamsCache.ps1` | Uploaded as **Detection script** in Intune |
| **Remediate** (fix) | `Invoke-` | `Invoke-Remediation<Name>.ps1` or `Invoke-Winget<App>.ps1` | `scripts/endpoints/remediation/system/Invoke-RemediationFixTeamsCache.ps1` | Uploaded as **Remediation script** |
| **Unified** (alternative, permitted) | `Invoke-` + `-Mode` | `Invoke-Remediation<Name>.ps1 -Mode Detect\|Remediate` | `scripts/endpoints/remediation/system/Invoke-RemediationCheckBatteryHealth.ps1 -Mode Detect` | Single file handles both; shim calls with correct `-Mode` |

**Recommended 5.0.0 implementation:** **Two-file pair** (`Test-` + `Invoke-`) per remediation/app. Rationale:

- Matches Intune's portal mental model (two upload slots) — operators select `Test-*.ps1` for detection and `Invoke-*.ps1` for remediation without remembering a `-Mode` flag.
- PSSA Approved Verbs: `Test` is the correct verb for detection (not `Invoke`). Using `Invoke-` for both fixes the duplicate but violates verb semantics; the two-file split satisfies both the assignment's `Invoke-RemediationCheckBatteryHealth.ps1` example (remediate side) and correct verb usage.
- The assignment's `Invoke-RemediationFixTeamsCache.ps1` / `Invoke-RemediationCheckBatteryHealth.ps1` are the **remediate-side** names; the detect-side companions are `Test-RemediationFixTeamsCache.ps1` / `Test-RemediationCheckBatteryHealth.ps1`. If Implementation prefers the single-file `-Mode` approach, it MUST still expose the `Test-` name as an alias or thin wrapper so discoverability is preserved.

**Canonical file content rules:**

- Each canonical file retains the full business logic from `main` (SYSTEM-context `Win32_UserProfile` / `Win32_Battery` / `Microsoft.WinGet.Client` handling unchanged).
- Comment-based help REQUIRED: `.SYNOPSIS`, `.DESCRIPTION`, `.NOTES` with `Exit 0/1` contract, `.EXAMPLE`.
- `[CmdletBinding()]` + `param()` where applicable; no hardcoded secrets; no `Invoke-Expression`; `UseShellExecute = $false` retained for winget.

**Legacy lowercase folders:** `keyboard-layout`, `language-pack-audit`, `region-language-settings` → canonical PascalCase `KeyboardLayout`, `LanguagePackAudit`, `RegionLanguageSettings` under `system/`. Shims keep old lowercase path.

### 3.3 Taxonomy — Proactive Remediations → {system, network, security}

Every `proactive-remediations/*` folder maps to exactly one of `system`/`network`/`security`. Mapping is by **primary tag** (category in the existing `README.md`'s 7 groups: Security & Compliance, Storage & Performance, System Services, Network & Connectivity, Apps & Licensing, Regional & Localization, Certificate Management, Device Health & Uptime). The rule is deterministic and documented in `P1/README.md`.

| Bucket | Members (51) | Rationale |
|--------|--------------|-----------|
| **`system`** (≈ 38) | `Fix-TeamsCache`, `Fix-TimeSync`, `Fix-DiskSpace`, `Fix-TempFiles`, `Fix-StaleProfiles`, `Fix-EventLogSize`, `Fix-EdgeCacheSize`, `Check-DiskHealth`, `Fix-StartMenuLayout`, `Check-PageFileConfiguration`, `Check-MemoryDiagnostics`, `Fix-WindowsUpdateStuck`, `Fix-WindowsUpdateRebootPending`, `Fix-WindowsStoreLicensing`, `Fix-WindowsSearch`, `Fix-WindowsPerformanceRecorder`, `Fix-TaskSchedulerCorruption`, `Check-MicrosoftStoreAppsHealth`, `Fix-SystemFileCorruption`, `Fix-OutdatedDrivers`, `Fix-PrintSpooler`, `Fix-WindowsLicenseActivation`, `Fix-CertificateExpiry`*, `Check-WindowsActivationGracePeriod`, `Check-BatteryHealth`, `Check-DeviceUptime`, `Check-UnexpectedReboots`, `Check-SystemStabilityIndex`, `Check-BootPerformance`, `Check-ServiceFailures`, `Check-ApplicationCrashes`, `Check-SystemEventErrors`, `Check-HardwareErrors`, `Check-DeviceHealthScore`, `Fix-BrokenShortcuts`, `Fix-CredentialManager`, `Fix-OneDriveKnownFolderMove`, `Fix-DNSCache`*, `region-language-settings` → `RegionLanguageSettings`, `keyboard-layout` → `KeyboardLayout`, `language-pack-audit` → `LanguagePackAudit` | OS, storage, performance, services, device health, regional, apps/licensing. `Check-BatteryHealth` → `system/` (or `system/hardware/` sub-namespace) — hardware is a system concern, not a fourth top-level bucket. |
| **`network`** (4) | `Fix-NetworkAdapterPowerManagement`, `Fix-SMBv1Protocol`**, `Check-SharedFolders`, `Fix-DNSCache` (primary: network; secondary overlap with system — resolved to `network`) | Network & connectivity. `Fix-DNSCache` is network-primary despite being listed under System Services in old README. |
| **`security`** (7–9) | `Check-SecurityBaseline`, `Fix-BitLockerNotEscrowedKeys`, `Check-DefenderHealthStatus`, `Check-TPMStatus`, `Check-LocalAdminAccounts`, `Fix-PowerShellExecutionPolicy`, `Fix-CertificateExpiry`*, `Check-OutdatedCriticalApps` | Security & compliance. `Fix-SMBv1Protocol`** is security-*motivated* but network-*implemented*; canonical home is `network/` with a cross-reference in `security/README` section. `Fix-CertificateExpiry` is both system and security — canonical `security/` (expiry is a trust/compliance signal) with alias note in `system/`. Implementation MUST pick one canonical home and document the dual-tag in `P1/README.md`. |

> * Dual-tag items (`Fix-CertificateExpiry`, `Fix-DNSCache`, `Fix-SMBv1Protocol`) appear once in the canonical tree — no duplication. Cross-references via `P1/README.md` migration notes cover discoverability.
>
> **Hardware sub-namespace (optional):** `system/hardware/Test-RemediationCheckBatteryHealth.ps1`, `system/hardware/Test-RemediationCheckDiskHealth.ps1`, etc. are permitted as an *additive* refinement under `system/` without violating the 4-folder contract. If introduced, shims MUST point to the sub-namespace path and `tools/Build-Catalog.ps1` category derivation (`Get-CategoryFromPath`) must treat `remediation/system/hardware` as `endpoints/remediation/system/hardware`.

**Winget mapping (P2 → P1/winget/):** One-to-one category-preserving move. `_templates/` moves from `winget/_templates/` to `remediation/winget/_templates/` so `_generate-winget-scripts.ps1` continues to find it. App folders keep PascalCase (`Firefox`, `GoogleChrome`, `SevenZip`, …).

---

## 4. Shim Design — Deprecation Wrappers (P2, P3)

### 4.1 Contract

- **Behaviour:** `Write-Warning` exactly once per invocation (visible in Intune logs and interactive runs), then delegate to the canonical script, **preserving exit code** (`0` = healthy/not-applicable, `1` = remediation needed / remediation applied, plus any stderr passthrough).
- **Lifetime:** Shims are the *only* content under `P2`/`P3` after 5.0.0. They are retained through all `5.x` releases and **removed in `6.0.0`** (major cleanup). `P1/README.md` documents this timeline.
- **No logic drift:** Shims MUST NOT re-implement detection/remediation logic. They are pure forwarders so fixes ship once (in `P1`).
- **SYSTEM context safe:** Shims do not add new SYSTEM assumptions. They delegate immediately; the canonical script already handles `SYSTEM` (e.g., `Get-CimInstance Win32_UserProfile` iteration, `Microsoft.WinGet.Client` preference over `winget.exe`).

### 4.2 Canonical 3-Line Shim Example

Assignment-required example: `scripts/endpoints/devices/winget/browsers/Firefox/detect.ps1` (old) → `scripts/endpoints/remediation/winget/browsers/Firefox/Test-WingetFirefox.ps1` (new). The file on disk at the **old path** becomes:

```powershell
Write-Warning 'Deprecated: moved to scripts/endpoints/remediation/winget/browsers/Firefox/Test-WingetFirefox.ps1 — shim will be removed in 6.0.0.'
$null = & "$PSScriptRoot/../../../remediation/winget/browsers/Firefox/Test-WingetFirefox.ps1" @args; exit $LASTEXITCODE
```

> **Why this is 3 logical lines:** Line 1 = deprecation warning with new path + removal version. Line 2 = delegation via call operator `&` with `@args` forwarding + `$LASTEXITCODE` capture. Line 3 is the `exit` — shown on the same physical line as the `&` call to keep the file at 2–3 lines while preserving exit-code semantics. Implementation MAY split the delegation and `exit` onto two lines (4 logical lines) if readability demands — the contract is *≤ 4 lines, no business logic, exit code preserved*, not literal "3 lines exactly."
>
> **Relative path depth rule:** Depth is computed per-leaf, not hard-coded globally. `winget/browsers/Firefox/detect.ps1` needs `../../../remediation/...` (3 ups from `winget/browsers/Firefox` to `endpoints/`). `proactive-remediations/Fix-TeamsCache/detect.ps1` needs `../../remediation/system/Test-RemediationFixTeamsCache.ps1` (2 ups from `proactive-remediations/Fix-TeamsCache` to `endpoints/`). Implementation MUST generate shims via script (`_generate-shims.ps1` or `Build-Catalog`-adjacent helper) that computes `PSScriptRoot` relative depth — never hard-code a single `../../../` for all shims.

### 4.3 Shim Template (one per old file, generated)

```powershell
<#  Pester/CI idempotency guard: shims are intentionally tiny.
    PSSA clean — no Invoke-Expression, no hardcoded secrets, BOM required. #>
Write-Warning 'Deprecated: moved to <NEW_PATH> — shim will be removed in 6.0.0.'
& "$PSScriptRoot/<RELATIVE_TO_NEW>" @args
exit $LASTEXITCODE
```

**Details:**

- `<NEW_PATH>` is the repo-relative canonical path (e.g., `scripts/endpoints/remediation/system/Test-RemediationFixTeamsCache.ps1`) — shown to the operator so they can update Intune assignments.
- `<RELATIVE_TO_NEW>` is the file-system relative path from the shim's directory to the canonical file.
- `@args` forwards any arguments Intune or a future CLI passes through (currently none, but future-proofs the shim).
- `$LASTEXITCODE` is captured *immediately* after `&` — no intervening `Write-*` that could clobber it.
- For `remediate.ps1` shims targeting `Invoke-*.ps1`, same pattern but targeting the `Invoke-` companion.
- For variant files (`remediate_Force_Close.ps1`, `remediate_maintenance_window.ps1`) → canonical variants `Invoke-Winget<App>ForceClose.ps1` / `Invoke-Winget<App>MaintenanceWindow.ps1` — shims follow the same template.

### 4.4 P2 vs P3 Shim Generation

| Source tree | Leaves | Shim output | Canonical target example |
|-------------|--------|-------------|--------------------------|
| `P2` (`winget`) | `detect.ps1` → `Test-Winget<App>.ps1` | `Write-Warning ... remediation/winget/<category>/<App>/Test-Winget<App>.ps1` | `remediation/winget/browsers/Firefox/Test-WingetFirefox.ps1` |
| `P2` (`winget`) | `remediate.ps1` → `Invoke-Winget<App>.ps1` | `Write-Warning ... remediation/winget/<category>/<App>/Invoke-Winget<App>.ps1` | `remediation/winget/browsers/Firefox/Invoke-WingetFirefox.ps1` |
| `P3` (`proactive-remediations`) | `detect.ps1` → `Test-Remediation<Name>.ps1` | `Write-Warning ... remediation/system\|network\|security/Test-Remediation<Name>.ps1` | `remediation/system/Test-RemediationFixTeamsCache.ps1` |
| `P3` (`proactive-remediations`) | `remediate.ps1` → `Invoke-Remediation<Name>.ps1` | `Write-Warning ... remediation/system\|network\|security/Invoke-Remediation<Name>.ps1` | `remediation/system/Invoke-RemediationFixTeamsCache.ps1` |

Shim files retain **comment-based help stubs** (minimal `.SYNOPSIS Deprecated shim — forwards to ...` + `.NOTES Shim`) so `Build-Catalog.ps1`'s parser does not count them as "without synopsis" and `docs/Script-Catalog.md` can filter shims via a `deprecated` tag.

---

## 5. Migration Guide — `scripts/endpoints/remediation/README.md` (inside P1)

`P1/README.md` is the **single migration surface** operators read. It MUST contain:

1. **Why** — one paragraph: duplicate `detect.ps1` collision, 4-folder discoverability, Approved Verbs.
2. **Deprecation timeline** — table: `5.0.0` shims added, `5.x` shim warnings, `6.0.0` shims removed.
3. **Intune update steps** — 4-step portal flow (Devices → Remediations → Edit script package → re-upload from new path), plus PowerShell Graph alternative (`IntuneGraphHelper.psm1`) for bulk updates.
4. **Migration table** — at least 10 rows, old → new (see §5.1).
5. **Taxonomy note** — `system` vs `network` vs `security` rule and dual-tag resolution (see §3.3).
6. **PSScriptAnalyzer & SYSTEM notes** — shims are PSSA-clean; SYSTEM handling unchanged.

### 5.1 Migration Table (10 Examples — Normative)

| # | Old path (P2/P3 — shim) | New canonical path (P1) | Type |
|---|-------------------------|--------------------------|------|
| 1 | `scripts/endpoints/devices/winget/browsers/Firefox/detect.ps1` | `scripts/endpoints/remediation/winget/browsers/Firefox/Test-WingetFirefox.ps1` | Winget · detect → Test- |
| 2 | `scripts/endpoints/devices/winget/browsers/Firefox/remediate.ps1` | `scripts/endpoints/remediation/winget/browsers/Firefox/Invoke-WingetFirefox.ps1` | Winget · remediate → Invoke- |
| 3 | `scripts/endpoints/devices/winget/browsers/GoogleChrome/detect.ps1` | `scripts/endpoints/remediation/winget/browsers/GoogleChrome/Test-WingetGoogleChrome.ps1` | Winget · detect |
| 4 | `scripts/endpoints/devices/winget/communication/Slack/detect.ps1` | `scripts/endpoints/remediation/winget/communication/Slack/Test-WingetSlack.ps1` | Winget · detect |
| 5 | `scripts/endpoints/devices/winget/development/VisualStudioCode/detect.ps1` | `scripts/endpoints/remediation/winget/development/VisualStudioCode/Test-WingetVisualStudioCode.ps1` | Winget · detect |
| 6 | `scripts/endpoints/proactive-remediations/Fix-TeamsCache/detect.ps1` → shim (assignment calls this `devices/proactive-remediations` — canonical is `endpoints/devices/...`, alias accepted) | `scripts/endpoints/remediation/system/Invoke-RemediationFixTeamsCache.ps1` *(detect side: `Test-RemediationFixTeamsCache.ps1`)* | System · Fix-TeamsCache → system |
| 7 | `scripts/endpoints/devices/proactive-remediations/Fix-TeamsCache/remediate.ps1` | `scripts/endpoints/remediation/system/Invoke-RemediationFixTeamsCache.ps1` | System · remediate |
| 8 | `scripts/endpoints/devices/proactive-remediations/Fix-TimeSync/detect.ps1` | `scripts/endpoints/remediation/system/Test-RemediationFixTimeSync.ps1` | System · Fix-TimeSync → system |
| 9 | `scripts/endpoints/devices/proactive-remediations/Check-BatteryHealth/detect.ps1` | `scripts/endpoints/remediation/system/Test-RemediationCheckBatteryHealth.ps1` *(optional: `system/hardware/Test-RemediationCheckBatteryHealth.ps1`)* | System · Check-BatteryHealth → system (hardware sub-namespace) |
| 10 | `scripts/endpoints/devices/proactive-remediations/Check-BatteryHealth/remediate.ps1` | `scripts/endpoints/remediation/system/Invoke-RemediationCheckBatteryHealth.ps1` | System · remediate |
| — | *Additional rows that MUST appear verbatim in the shipped README (bonus, not counted toward the 10):* | | |
| 11 | `scripts/endpoints/devices/proactive-remediations/Fix-DNSCache/detect.ps1` | `scripts/endpoints/remediation/network/Test-RemediationFixDNSCache.ps1` | Network |
| 12 | `scripts/endpoints/devices/proactive-remediations/Fix-NetworkAdapterPowerManagement/detect.ps1` | `scripts/endpoints/remediation/network/Test-RemediationFixNetworkAdapterPowerManagement.ps1` | Network |
| 13 | `scripts/endpoints/devices/proactive-remediations/Check-SecurityBaseline/detect.ps1` | `scripts/endpoints/remediation/security/Test-RemediationCheckSecurityBaseline.ps1` | Security |
| 14 | `scripts/endpoints/devices/proactive-remediations/Fix-SMBv1Protocol/detect.ps1` | `scripts/endpoints/remediation/network/Test-RemediationFixSMBv1Protocol.ps1` | Network (security-motivated) |
| 15 | `scripts/endpoints/devices/proactive-remediations/region-language-settings/detect.ps1` | `scripts/endpoints/remediation/system/Test-RemediationRegionLanguageSettings.ps1` | System · lowercase → PascalCase |

> **Path prefix note:** Assignment text abbreviates `scripts/endpoints/devices/...` as `scripts/endpoints/...` in one example — the README MUST clarify both are aliased and show the full repo-relative path.

---

## 6. APIs & Contracts

### 6.1 Shim API (P2/P3 wrappers)

```powershell
# Shim file — no exported functions, no parameters. Contract is process-level:
# Input:  @args (passthrough, currently unused — reserved for future -Mode)
# Output: stdout/stderr passthrough from canonical script
# Exit:   $LASTEXITCODE from canonical script — MUST be 0 or 1 for Intune detection
# Side-effect: Write-Warning to warning stream (captured in Intune logs)
```

**No Approved-Verb violation:** Shim files are named `detect.ps1`/`remediate.ps1` for backward compatibility only — they are *not* new exports and are excluded from `FunctionsToExport` checks.

### 6.2 Canonical Script API (P1)

```powershell
<#
.SYNOPSIS
    Detects <condition> for <app/remediation>.
.DESCRIPTION
    <Full description — what is checked, thresholds, SYSTEM handling>.
.NOTES
    Intune: exit 0 = healthy/not-applicable, exit 1 = needs remediation.
    Context: runs as SYSTEM in Proactive Remediations — uses Win32_UserProfile / Win32_Battery / Microsoft.WinGet.Client as applicable.
    Verb: Test- (detect) / Invoke- (remediate) — Approved Verbs.
#>
# Test-RemediationFixTeamsCache.ps1 — detect
# Remediation contract: no params today; future -Threshold passthrough reserved.
# Exit codes: 0, 1 — never 2+ for detection (Intune treats non-zero as "needs remediation" but 0/1 is canonical).

# Invoke-RemediationFixTeamsCache.ps1 — remediate
# Exit codes: 0 = success/no-op, 1 = remediation failed (Intune retry)
```

**Winget canonical scripts** retain the `Microsoft.WinGet.Client` preference pattern from `main` (`Firefox/detect.ps1` lines 68-84) — the module check `Get-Module -ListAvailable -Name Microsoft.WinGet.Client` MUST remain, because `winget.exe` CLI is **unsupported in SYSTEM context** ([learn.microsoft.com](https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting)). Removal would regress Intune reliability.

---

## 7. Edge Cases & Handling

| # | Edge case | Why it matters | Handling (normative) |
|---|-----------|----------------|----------------------|
| **E1** | **Duplicate `detect.ps1` × 51** | `Get-ChildItem -Filter detect.ps1` and `Get-BUScript -Name detect.ps1` are ambiguous; `rg detect.ps1` returns 51 hits | Canonical files use **globally unique** names (`Test-RemediationFixTeamsCache.ps1`, `Test-WingetFirefox.ps1`). Shims keep the duplicate name only as forwarders. `tools/Build-Catalog.ps1` category derivation handles unique leaf names natively. A follow-up catalog improvement MAY tag shims with `deprecated` to filter them from default search (non-blocking). |
| **E2** | **SYSTEM context** ("already fixed" note) | Intune Proactive Remediations run as `NT AUTHORITY\SYSTEM` — user profile, battery, and winget paths differ | No regression. Canonical scripts retain existing SYSTEM patterns: `Get-CimInstance Win32_UserProfile | Where { -not $_.Special -and $_.LocalPath -notmatch 'systemprofile\|defaultuser' }` with `Loaded`-first + `LastUseTime` cap (20 profiles) for Teams; `Get-CimInstance Win32_Battery` + `powercfg /batteryreport` for BatteryHealth; `Microsoft.WinGet.Client` module preference for winget. Shims add no new SYSTEM assumptions. |
| **E3** | **Exit-code preservation (Intune contract)** | Intune interprets `exit 0` = compliant, `exit 1` = non-compliant/trigger remediation. A shim that swallows or mis-forwards exit code silently breaks compliance reporting | Shim uses `& <path> @args` **immediately** followed by `exit $LASTEXITCODE` with no intervening `Write-*` that could reset `$LASTEXITCODE`. Canonical scripts MUST end with `exit 0` / `exit 1` (not `throw` without `catch { exit 0 }` — existing pattern retains `catch { exit 0 }` for detection). `remediate.ps1` shims preserve the canonical's `exit 1` on failure for retry semantics. |
| **E4** | **Relative path depth varies** | Winget leaves are depth 3 (`winget/<category>/<App>/detect.ps1` → `../../../remediation/...`), proactive leaves are depth 2 (`proactive-remediations/<Folder>/detect.ps1` → `../../remediation/...`). A single hard-coded `../../../` breaks half the shims | Shim generator computes depth via `($oldPath -split '/').Count` or `Resolve-Path` relative logic. Each shim's `$PSScriptRoot/<RELATIVE>` is validated at generation time (`Test-Path`). Manual shims are prohibited — use the generator. |
| **E5** | **Approved Verbs + PSSA** | `Invoke-RemediationCheckBatteryHealth.ps1` uses `Invoke-` for a `Check-` fix (verb-noun mismatch) if single-file approach is taken | Preferred: **two-file split** (`Test-` for detect, `Invoke-` for remediate) — both Approved Verbs, no PSSA `PSUseApprovedVerbs` error. If single-file `-Mode` is chosen, canonical file keeps `Invoke-` and exposes `Test-` as an alias (`Set-Alias Test-RemediationCheckBatteryHealth Invoke-RemediationCheckBatteryHealth`). PSSA `PSUseApprovedVerbs` is satisfied; `PSAvoidUsingWriteHost` remains excluded per `PSScriptAnalyzerSettings.psd1`. |
| **E6** | **CRLF + BOM + 4-space + comment-based help** | CI fails on `PSSA Errors`, non-BOM files break `PSScriptAnalyzer` `PSUseBOMForUnicodeEncodedFile` when enabled, and missing help regresses catalog coverage (currently 358/358) | All new `.ps1` files (canonical + shims) are 4-space, CRLF, **BOM** (UTF-8 with BOM via `[System.IO.File]::WriteAllText(..., [System.Text.UTF8Encoding]::new($true))` or VS Code `files.encoding: utf8bom`). Every file has `.<SYNOPSIS>` + `.<DESCRIPTION>` + `.<NOTES>`. Shims get a stub synopsis: `.SYNOPSIS Deprecated shim — forwards to ...`. |
| **E7** | **Lowercase legacy folders** | `keyboard-layout`, `language-pack-audit`, `region-language-settings` are lowercase/kebab, while winget and `Fix-*`/`Check-*` are PascalCase — catalog category and file discovery assume PascalCase post-5.0 | Shims keep old lowercase path; canonical uses `KeyboardLayout`, `LanguagePackAudit`, `RegionLanguageSettings` under `system/`. `P1/README.md` migration row documents this rename explicitly. `Build-Catalog.ps1` `Get-CategoryFromPath` handles both casings (it lower-cases only for filtering, not for display). |
| **E8** | **Catalog double-counting** | Scanning `scripts/**/*.ps1` will encounter both shim files and canonical files if shims are not tagged, inflating `totalScripts` (358 → 358 + 164 shim files = 522) and confusing `Get-BUScript` | Two options, pick one and document in `P1/README.md`: (a) **Shims are excluded from catalog** via `Build-Catalog.ps1` filter (`Where-Object { $_.FullName -notmatch '/devices/(winget\|proactive-remediations)/' }` after 5.0.0 — shims excluded by old-path regex), or (b) **Shims are catalogued with `deprecated: true` tag** and filtered by default. Recommended: (a) exclusion — cleaner `totalScripts` (358 entries remain canonical). Implementation MUST decide and gate via `tools/Build-Catalog.ps1` tweak (one-line filter). |
| **E9** | **Variants (`remediate_Force_Close.ps1`, `remediate_maintenance_window.ps1`)** | Winget apps offer 3 remediation flavours; consolidation must not lose them | Canonical preserves variants as `Invoke-Winget<App>ForceClose.ps1` and `Invoke-Winget<App>MaintenanceWindow.ps1` alongside `Invoke-Winget<App>.ps1` (standard). Shims at `remediate_Force_Close.ps1` / `remediate_maintenance_window.ps1` forward to the corresponding variant. |
| **E10** | **Bulk Intune update ergonomics** | Operators have 67 script packages to re-upload if they update portal assignments | `P1/README.md` MUST include a Graph bulk-update snippet using `IntuneGraphHelper.psm1` (`Get-IntuneScriptPackage` → `Set-IntuneScriptPackage` with new path), plus a `Invoke-Umbrella.ps1` / `Get-BUScript` one-liner to list old→new paths for scripting. |

---

## 8. Verification — Acceptance Gates

Implementation is **not mergeable** until all checks pass locally (and CI mirrors them).

| Gate | Command (PowerShell 7) | Expected result |
|------|------------------------|-----------------|
| **V1 — Old shim preserves exit 0/1 (healthy path)** | `pwsh -NoProfile -File scripts/endpoints/devices/proactive-remediations/Fix-TeamsCache/detect.ps1; $LASTEXITCODE` (and same for `Check-BatteryHealth/detect.ps1`, `winget/browsers/Firefox/detect.ps1`) on a healthy dev box | `0` with `WARNING: Deprecated: moved to scripts/endpoints/remediation/...` on warning stream. No business-logic output lost. |
| **V2 — Old shim preserves exit 1 (needs remediation)** | Mock or force-condition: e.g., temporarily set `$degradationThreshold = 100` for BatteryHealth or seed a large temp `Teams` cache, then `pwsh -File <shim detect.ps1>; $LASTEXITCODE` | `1` with same warning prefix. Proves `$LASTEXITCODE` forwarding, not swallowed. |
| **V3 — New canonical path works standalone** | `pwsh -NoProfile -File scripts/endpoints/remediation/system/Test-RemediationFixTeamsCache.ps1; $LASTEXITCODE` <br> `pwsh -NoProfile -File scripts/endpoints/remediation/system/Test-RemediationCheckBatteryHealth.ps1; $LASTEXITCODE` <br> `pwsh -File scripts/endpoints/remediation/winget/browsers/Firefox/Test-WingetFirefox.ps1; $LASTEXITCODE` (may be `0` if not installed or no network — valid) | Same `0`/`1` semantics as shim, **no warning**. Exit code matches shim's forwarded code for same machine state. |
| **V4 — PSSA 0 Errors/Warnings** | `Invoke-ScriptAnalyzer -Path scripts/endpoints/remediation -Recurse -Settings .vscode/PSScriptAnalyzerSettings.psd1 \| Where-Object { $_.Severity -in 'Error','Warning' }` <br> Same for `scripts/endpoints/devices/winget` and `scripts/endpoints/devices/proactive-remediations` (shims) | **0 findings.** No `Invoke-Expression`, no missing help, no approved-verb violation. `Write-Warning` is allowed (not `Write-Host`). |
| **V5 — Comment-based help coverage** | `pwsh -NoProfile -File tools/Build-Catalog.ps1; (Get-Content scripts/.catalog/metadata.json \| ConvertFrom-Json).scripts \| Where-Object { -not $_.synopsis } \| Measure-Object` | `0` without synopsis (catalog still 358 canonical entries if shims excluded — see E8). |
| **V6 — Catalog round-trip** | `pwsh -File tools/Build-Catalog.ps1 -Validate` <br> `pwsh -File ./Invoke-Umbrella.ps1 -Search remediation -List` | `-Validate` exits 0 (catalog fresh). `Invoke-Umbrella` lists remediation entries under `endpoints/remediation/...` category (old `devices/winget` / `devices/proactive-remediations` no longer appear as canonical). |
| **V7 — Cross-platform shim path sanity** | `pwsh -File tools/Build-Catalog.ps1` on Linux (CI) + `Test-Path` for every shim's relative target | All shim `Test-Path "$PSScriptRoot/<RELATIVE>"` resolve. No Windows-only `Resolve-Path` assumption. |

> **SYSTEM-context note:** Full SYSTEM verification (`psexec -s pwsh -File ...`) is manual on a Windows Intune test device and listed as a *recommended* post-merge check, not a CI gate (CI runners are not SYSTEM). Logic is already SYSTEM-proven on `main` — shims do not regress it.

---

## 9. Implementation Steps (Ordered, Idempotent)

1. **Create `P1` tree** — `New-Item -ItemType Directory` for `remediation/winget/{browsers,communication,development,media,productivity,remote-access,runtimes,security,utilities,vendor-specific,_templates}`, `remediation/system`, `remediation/network`, `remediation/security` (+ optional `remediation/system/hardware`).
2. **Move & rename** — For each `P2` app folder, `Move-Item` preserving category/App structure, renaming `detect.ps1` → `Test-Winget<App>.ps1`, `remediate.ps1` → `Invoke-Winget<App>.ps1` (variants similarly). For each `P3` folder, map to `system|network|security` per §3.3, rename `detect.ps1` → `Test-Remediation<Name>.ps1`, `remediate.ps1` → `Invoke-Remediation<Name>.ps1` (lowercase folders → PascalCase). Preserve file content byte-for-byte except filename.
3. **Add `P1/README.md`** — Migration guide per §5 (10-row table + timeline + taxonomy note).
4. **Generate shims** — Script `_generate-shims.ps1` (privileged build tool, not shipped) iterates old paths and writes 3-line wrappers with computed `RELATIVE` and `NEW_PATH`. Shims are CRLF+BOM, tiny comment-based help stub.
5. **Patch catalog if needed** — One-line `Build-Catalog.ps1` filter to exclude old shim paths from `totalScripts` (E8), or tag shims as `deprecated`. Keep catalog at 358 canonical entries; decide and document.
6. **Patch `_generate-winget-scripts.ps1`** — Update `$wingetRoot` / `$templatesPath` variable to `remediation/winget/...` (one-line change).
7. **Patch docs consumers** — No doc edits in this spec beyond `P1/README.md`, but `tools/Build-Catalog.ps1` tweak is in-budget if needed. Cross-link `P1/README.md` from `docs/README.md` is owned by `05-docs-site.md` — do not duplicate.
8. **Verify** — Run §8 gates V1–V7 locally; fix PSSA findings before push.

---

## 10. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Operator forgets to update Intune portal and stays on shim path past `6.0.0` | Warning is loud (`Write-Warning` with new path + removal version). `P1/README.md` states timeline. `Invoke-Umbrella.ps1 -Search winget` shows new path only (shims excluded from catalog). |
| Relative path typo breaks shim on case-sensitive Linux CI | Generator validates `Test-Path` per shim; CI V7 fails on broken relative. |
| Dual-tag item (`CertificateExpiry`) discovered under wrong bucket | Document dual-tag resolution in `P1/README.md`; one canonical home + cross-reference. No duplication. |
| `totalScripts` inflation (358 → 522) confuses dashboards | Exclude shim paths from catalog (E8) — keep 358 canonical. |
| Verb-noun debate (`Invoke-` vs `Test-` for Check-*) blocks review | Spec mandates two-file split as primary; single-file `-Mode` allowed only with `Test-` alias. PSSA gate enforces Approved Verbs. |

---

## 11. Acceptance Checklist — Done Means

- [ ] **3 paths** listed in §2 table; implementation touches **only** `scripts/endpoints/remediation/` (new), `scripts/endpoints/devices/winget/` (shims), `scripts/endpoints/devices/proactive-remediations/` (shims). `P1/README.md` counted inside P1.
- [ ] **New hierarchy** exists with **4 subfolders** `winget`, `system`, `network`, `security` (§3.1 diagram verbatim). `winget/` retains 10 category subfolders; `system`/`network`/`security` populated per §3.3 taxonomy.
- [ ] **Shim example** (§4.2) present: `Write-Warning 'Deprecated: moved to scripts/endpoints/remediation/winget/browsers/Firefox/Test-WingetFirefox.ps1 ...'` + `& "$PSScriptRoot/../../../remediation/winget/browsers/Firefox/Test-WingetFirefox.ps1" @args; exit $LASTEXITCODE` (≤ 4 lines, exit code preserved, `@args` forwarded).
- [ ] **Migration table** in `scripts/endpoints/remediation/README.md` contains **≥ 10 rows** old → new, including `Fix-TeamsCache → system`, `Fix-TimeSync → system`, `Check-BatteryHealth → system (hardware sub-namespace)` and 3 winget examples (§5.1 rows 1–10 normative).
- [ ] **Duplicate `detect.ps1`** eliminated in canonical tree — unique names `Test-RemediationFixTeamsCache.ps1` / `Test-RemediationCheckBatteryHealth.ps1` (or `Test-WingetFirefox.ps1`) with Approved Verb `Test-` for detect-side.
- [ ] **SYSTEM context** preserved — canonical scripts retain `Win32_UserProfile` / `Win32_Battery` / `Microsoft.WinGet.Client` patterns; shims add no new SYSTEM assumptions.
- [ ] **Verification gates** V1–V4 pass: old shim still exits `0`/`1`, new path works without warning, **PSSA 0 Errors/Warnings** on all three trees.

---

*End of reorg breaking design spec. Implementation MUST satisfy §11 before merge. Sibling specs own module, CLI, tests, and docs site — do not expand scope.*

