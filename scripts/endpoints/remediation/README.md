# Remediation — Canonical Endpoint Scripts (5.0 Hurricane)

> **New in 5.0.0** — `scripts/endpoints/remediation/` is the single canonical hierarchy for all Intune Proactive Remediation and winget-managed app update scripts. Legacy paths under `scripts/endpoints/devices/winget/` and `scripts/endpoints/devices/proactive-remediations/` are retained as deprecation shims through `5.x` and will be removed in `6.0.0`.

## Why

The previous layout used `detect.ps1` × 51 (plus ~35 winget `detect.ps1`) filename collisions, fragmented search (`Get-BUScript -Name detect.ps1` ambiguous), and mixed verb semantics. The new hierarchy consolidates into 4 top-level folders, uses globally-unique `Test-`/`Invoke-` Verb-Noun filenames (Approved Verbs), and preserves SYSTEM-context handling (`Win32_UserProfile`, `Win32_Battery`, `Microsoft.WinGet.Client`).

## Deprecation Timeline

| Version | Change |
|---------|--------|
| **5.0.0** | Shims added at old paths. Each shim emits `Write-Warning 'Deprecated: moved to scripts/endpoints/remediation/... — shim will be removed in 6.0.0.'` and forwards `exit $LASTEXITCODE`. |
| **5.x** | Shims continue to work with warning. Update Intune script packages to canonical paths at next edit. |
| **6.0.0** | Shims removed. Only `scripts/endpoints/remediation/` remains. |

## Intune Update Steps

**Portal (4 steps):**
1. **Devices** → **Scripts and remediations** → **Create / Edit** script package.
2. Replace **Detection script** upload with the new `Test-*.ps1` from `scripts/endpoints/remediation/...`.
3. Replace **Remediation script** upload with the new `Invoke-*.ps1` from the same folder.
4. **Save** and re-assign to groups.

**Bulk via Graph (PowerShell):**

```powershell
Import-Module ./scripts/endpoints/intune/IntuneGraphHelper.psm1 -Force
Connect-IntuneGraph
# List old → new mapping (see table below)
Get-BUScript -Search remediation | Format-Table Name, Category
# For each package, update via Graph (pseudo-code)
# Get-IntuneScriptPackage | Where-Object { $_.DetectionScript -match 'devices/winget' } | ForEach-Object {
#     Set-IntuneScriptPackage -Id $_.Id -DetectionScript (Get-Content 'scripts/endpoints/remediation/winget/.../Test-*.ps1' -Raw)
# }
```

**Local discovery:**

```powershell
pwsh -File ./Invoke-Umbrella.ps1 -Search remediation -List
pwsh -File ./Invoke-Umbrella.ps1 -Category endpoints/remediation -List
```

## Migration Table (15 Rows)

| # | Old path (shim) | New canonical path | Type |
|---|-----------------|--------------------|------|
| 1 | `scripts/endpoints/devices/winget/browsers/Firefox/detect.ps1` | `scripts/endpoints/remediation/winget/browsers/Firefox/Test-WingetFirefox.ps1` | Winget · detect → Test- |
| 2 | `scripts/endpoints/devices/winget/browsers/Firefox/remediate.ps1` | `scripts/endpoints/remediation/winget/browsers/Firefox/Invoke-WingetFirefox.ps1` | Winget · remediate → Invoke- |
| 3 | `scripts/endpoints/devices/winget/browsers/GoogleChrome/detect.ps1` | `scripts/endpoints/remediation/winget/browsers/GoogleChrome/Test-WingetGoogleChrome.ps1` | Winget · detect |
| 4 | `scripts/endpoints/devices/winget/communication/Slack/detect.ps1` | `scripts/endpoints/remediation/winget/communication/Slack/Test-WingetSlack.ps1` | Winget · detect |
| 5 | `scripts/endpoints/devices/winget/development/VisualStudioCode/detect.ps1` | `scripts/endpoints/remediation/winget/development/VisualStudioCode/Test-WingetVisualStudioCode.ps1` | Winget · detect |
| 6 | `scripts/endpoints/devices/proactive-remediations/Fix-TeamsCache/detect.ps1` | `scripts/endpoints/remediation/system/Test-RemediationFixTeamsCache.ps1` | System · Fix-TeamsCache → system |
| 7 | `scripts/endpoints/devices/proactive-remediations/Fix-TeamsCache/remediate.ps1` | `scripts/endpoints/remediation/system/Invoke-RemediationFixTeamsCache.ps1` | System · remediate |
| 8 | `scripts/endpoints/devices/proactive-remediations/Fix-TimeSync/detect.ps1` | `scripts/endpoints/remediation/system/Test-RemediationFixTimeSync.ps1` | System · Fix-TimeSync → system |
| 9 | `scripts/endpoints/devices/proactive-remediations/Check-BatteryHealth/detect.ps1` | `scripts/endpoints/remediation/system/Test-RemediationCheckBatteryHealth.ps1` | System · Check-BatteryHealth → system |
| 10 | `scripts/endpoints/devices/proactive-remediations/Check-BatteryHealth/remediate.ps1` | `scripts/endpoints/remediation/system/Invoke-RemediationCheckBatteryHealth.ps1` | System · remediate |
| 11 | `scripts/endpoints/devices/proactive-remediations/Fix-DNSCache/detect.ps1` | `scripts/endpoints/remediation/network/Test-RemediationFixDNSCache.ps1` | Network |
| 12 | `scripts/endpoints/devices/proactive-remediations/Fix-NetworkAdapterPowerManagement/detect.ps1` | `scripts/endpoints/remediation/network/Test-RemediationFixNetworkAdapterPowerManagement.ps1` | Network |
| 13 | `scripts/endpoints/devices/proactive-remediations/Check-SecurityBaseline/detect.ps1` | `scripts/endpoints/remediation/security/Test-RemediationCheckSecurityBaseline.ps1` | Security |
| 14 | `scripts/endpoints/devices/proactive-remediations/Fix-SMBv1Protocol/detect.ps1` | `scripts/endpoints/remediation/network/Test-RemediationFixSMBv1Protocol.ps1` | Network (security-motivated) |
| 15 | `scripts/endpoints/devices/proactive-remediations/region-language-settings/detect.ps1` | `scripts/endpoints/remediation/system/Test-RemediationRegionLanguageSettings.ps1` | System · lowercase → PascalCase |

> **Path prefix note:** `scripts/endpoints/devices/proactive-remediations/...` and the abbreviated `scripts/endpoints/proactive-remediations/...` in assignment text are aliased — the full repo-relative path always starts with `scripts/endpoints/devices/`. Lowercase legacy folders (`keyboard-layout`, `language-pack-audit`, `region-language-settings`) map to PascalCase (`KeyboardLayout`, `LanguagePackAudit`, `RegionLanguageSettings`) under `system/`.

Additional winget examples (category-preserving):

| Old | New |
|-----|-----|
| `scripts/endpoints/devices/winget/communication/Discord/detect.ps1` | `scripts/endpoints/remediation/winget/communication/Discord/Test-WingetDiscord.ps1` |
| `scripts/endpoints/devices/winget/utilities/SevenZip/detect.ps1` | `scripts/endpoints/remediation/winget/utilities/SevenZip/Test-WingetSevenZip.ps1` |
| `scripts/endpoints/devices/winget/runtimes/EdgeWebView2/detect.ps1` | `scripts/endpoints/remediation/winget/runtimes/EdgeWebView2/Test-WingetEdgeWebView2.ps1` |

## Taxonomy — `system` vs `network` vs `security`

Scripts from `proactive-remediations/` are bucketed by primary tag (original 7 groups):

- **`system`** (≈39): `Fix-TeamsCache`, `Fix-TimeSync`, `Fix-DiskSpace`, `Fix-TempFiles`, `Fix-StaleProfiles`, `Fix-EventLogSize`, `Fix-EdgeCacheSize`, `Check-DiskHealth`, `Fix-StartMenuLayout`, `Check-PageFileConfiguration`, `Check-MemoryDiagnostics`, `Fix-WindowsUpdateStuck`, `Fix-WindowsUpdateRebootPending`, `Fix-WindowsStoreLicensing`, `Fix-WindowsSearch`, `Fix-WindowsPerformanceRecorder`, `Fix-TaskSchedulerCorruption`, `Check-MicrosoftStoreAppsHealth`, `Fix-SystemFileCorruption`, `Fix-OutdatedDrivers`, `Fix-PrintSpooler`, `Fix-WindowsLicenseActivation`, `Check-WindowsActivationGracePeriod`, `Check-BatteryHealth`, `Check-DeviceUptime`, `Check-UnexpectedReboots`, `Check-SystemStabilityIndex`, `Check-BootPerformance`, `Check-ServiceFailures`, `Check-SystemEventErrors`, `Check-HardwareErrors`, `Check-ApplicationCrashes`, `Fix-BrokenShortcuts`, `Fix-OneDriveKnownFolderMove`, `Fix-TempFiles`, `keyboard-layout` → `KeyboardLayout`, etc. Flat files directly under `system/`.

- **`network`** (4): `Fix-DNSCache`, `Fix-NetworkAdapterPowerManagement`, `Fix-SMBv1Protocol`, `Check-SharedFolders` → `network/`. `Fix-DNSCache` is network-primary despite legacy System Services listing.

- **`security`** (8): `Check-SecurityBaseline`, `Fix-BitLockerNotEscrowedKeys`, `Check-DefenderHealthStatus`, `Check-TPMStatus`, `Check-LocalAdminAccounts`, `Fix-PowerShellExecutionPolicy`, `Fix-CertificateExpiry`, `Check-OutdatedCriticalApps` → `security/`. `Fix-SMBv1Protocol` is security-motivated but network-implemented — canonical is `network/` with cross-reference here. `Fix-CertificateExpiry` is trust/compliance — canonical `security/`.

> **Hardware sub-namespace (optional):** `system/hardware/` could host `Check-BatteryHealth`, `Check-DiskHealth`, etc., without violating the 4-folder contract. Not required for 5.0.0; if introduced, shims will point to the sub-namespace and `tools/Build-Catalog.ps1` will treat `remediation/system/hardware` as `endpoints/remediation/system/hardware`.

- `winget/` retains its 10 category subfolders and per-app leaf folders, so Intune operators and `_generate-winget-scripts.ps1` keep the same mental model with a one-line path-variable change. `_templates/` moved to `remediation/winget/_templates/`.

## PSScriptAnalyzer & SYSTEM Notes

- All new `.ps1` files (canonical + shims) are 4-space, **CRLF + BOM**, with comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.NOTES` with `Exit 0/1` contract). `Invoke-ScriptAnalyzer -Path scripts/endpoints/remediation -Recurse -Settings .vscode/PSScriptAnalyzerSettings.psd1` reports **0 Error/Warning**.
- Shims are PSSA-clean (`Write-Warning` is allowed; no `Invoke-Expression`, no hardcoded secrets). They do not re-implement logic — pure forwarders.
- **SYSTEM context preserved:** canonical scripts retain existing SYSTEM patterns — `Get-CimInstance Win32_UserProfile` (Teams cache, 20-profile cap), `Get-CimInstance Win32_Battery` + `powercfg /batteryreport` (BatteryHealth), `Microsoft.WinGet.Client` module preference over `winget.exe` CLI (unsupported in SYSTEM per [learn.microsoft.com](https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting)). Shims add no new SYSTEM assumptions.
- **Exit-code preservation:** shims use `& "$PSScriptRoot/<RELATIVE>" @args` immediately followed by `exit $LASTEXITCODE` with no intervening `Write-*`. Canonical detection scripts end with `exit 0`/`exit 1`; remediation scripts return `0` on success, `1` on failure for Intune retry.

## Layout

```
scripts/endpoints/remediation/
├── README.md
├── winget/
│   ├── _templates/
│   ├── browsers/Firefox/Test-WingetFirefox.ps1
│   ├── browsers/Firefox/Invoke-WingetFirefox.ps1
│   ├── communication/Slack/Test-WingetSlack.ps1
│   └── ...
├── system/
│   ├── Test-RemediationFixTeamsCache.ps1
│   ├── Invoke-RemediationFixTeamsCache.ps1
│   ├── Test-RemediationCheckBatteryHealth.ps1
│   └── ...
├── network/
│   ├── Test-RemediationFixDNSCache.ps1
│   └── ...
└── security/
    ├── Test-RemediationCheckTPMStatus.ps1
    └── ...
```
