# Naming Conventions

This document outlines the naming standards for the winget-updates folder structure.

## Folder Naming

### Standard: PascalCase

All folder names use **PascalCase** (no spaces, each word capitalized).

**Benefits:**
- Script-friendly (no escaping required)
- Consistent and predictable
- Easy to parse programmatically
- Clean and professional appearance

### Examples

| Application Name | Folder Name |
|-----------------|-------------|
| Google Chrome | `GoogleChrome` |
| Adobe Reader 32-bit | `AdobeReader32bit` |
| Microsoft Teams | `MicrosoftTeams` |
| Visual Studio Code | `VisualStudioCode` |
| C++ 2008 Redistributable | `Cpp2008Redist` |
| Edge WebView2 | `EdgeWebView2` |
| 7-Zip | `SevenZip` |
| Notepad++ | `NotepadPlusPlus` |
| Oh My Posh | `OhMyPosh` |

### Special Cases

**Numbers:**
- Leading numbers: Spell out (7-Zip → `SevenZip`)
- Trailing numbers: Keep as-is (`PowerShell7`, `AdobeReader32bit`)

**Special Characters:**
- `++` → `PlusPlus` (Notepad++ → `NotepadPlusPlus`)
- `-` → Remove or spell out (`C++` → `Cpp`)
- Spaces → Remove (combine words)

**Abbreviations:**
- Keep well-known abbreviations: `SSMS`, `CLI`, `OBS`, `VLC`
- Use full words when unclear: `VisualStudioCode` not `VSCode`

**Architecture/Variants:**
- Append architecture: `AdobeReader32bit`, `AdobeReader64bit`
- Append variant: `TeamViewerFull`, `TeamViewerHost`
- For x86/x64: `-x86`, `-x64` (e.g., `Cpp2013Redist-x86`)

## Category Naming

Category folders use **lowercase with hyphens** to distinguish them from app folders:

- `browsers/`
- `development/`
- `media/`
- `productivity/`
- `remote-access/`
- `runtimes/`
- `utilities/`
- `vendor-specific/`

## File Naming

PowerShell scripts use **lowercase with underscores**:

**Standard files:**
- `detect.ps1` - Detection script (always V3 template)
- `remediate.ps1` - Primary remediation script

**Variant files:**
- `remediate_force_close.ps1` - Force close variant
- `remediate_maintenance.ps1` - Maintenance window variant

**Documentation:**
- `README.md` - App-specific notes or instructions

## Template Naming

Template files in `_templates/` folder:

- `detect_v3.ps1` - V3 detection template
- `remediate_v3_standard.ps1` - Standard remediation template
- `remediate_v3_force_close.ps1` - Force close template
- `remediate_v3_maintenance_window.ps1` - Maintenance window template
- `detect_v1_legacy.ps1` - Legacy V1 template (reference only)
- `remediate_v1_legacy.ps1` - Legacy V1 template (reference only)

## Version Handling

**Don't use version subfolders** (V1, V2, V3).

- Use git for version history
- Keep only current/recommended version in main branch
- Old versions can be accessed via git history

**Example - DON'T:**
```
GoogleChrome/
├── V1/
├── V2/
└── V3/
```

**Example - DO:**
```
GoogleChrome/
├── detect.ps1
└── remediate.ps1
```

## Architecture Handling

For architecture-specific applications, use **separate folders** with architecture suffix:

**Option 1: Separate Folders (Recommended)**
```
AdobeReader32bit/
├── detect.ps1
└── remediate.ps1

AdobeReader64bit/
├── detect.ps1
└── remediate.ps1
```

**Option 2: Subfolders (Only if scripts share significant code)**
```
Cpp2013Redist-x86/
├── detect.ps1
└── remediate.ps1

Cpp2013Redist-x64/
├── detect.ps1
└── remediate.ps1
```

## Quick Reference

### Naming Checklist

When adding a new app:

- [ ] Folder name in PascalCase
- [ ] No spaces in folder name
- [ ] Numbers handled correctly (spell out leading, keep trailing)
- [ ] Special characters converted appropriately
- [ ] Scripts named `detect.ps1` and `remediate.ps1`
- [ ] Scripts use V3 template
- [ ] App placed in correct category folder
- [ ] Architecture suffix added if needed
- [ ] No version subfolders (V1/V2/V3)

### Example Structure

```
winget-updates/
├── _templates/
├── browsers/
│   └── GoogleChrome/
│       ├── detect.ps1
│       └── remediate.ps1
├── development/
│   └── Git/
│       ├── detect.ps1
│       └── remediate.ps1
├── productivity/
│   ├── AdobeReader32bit/
│   │   ├── detect.ps1
│   │   └── remediate.ps1
│   └── MicrosoftTeams/
│       ├── detect.ps1
│       ├── remediate.ps1
│       └── remediate_force_close.ps1
└── runtimes/
    ├── Cpp2013Redist-x86/
    │   ├── detect.ps1
    │   └── remediate.ps1
    └── Cpp2013Redist-x64/
        ├── detect.ps1
        └── remediate.ps1
```
