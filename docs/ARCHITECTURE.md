# Bug-Free Umbrella — Architecture

> How the repository is organized, built, and shipped. 566 PowerShell scripts on disk — 381 catalogued across 8 technology domains plus 185 deprecated forwarding shims excluded from the catalog.

**Applies to:** v2.0.0 "Coverage & Correctness" · **Last verified:** 2026-09-16

---

## 1. Overview

Bug-Free Umbrella is a collection of **566 PowerShell scripts on disk** for enterprise IT management — **381 catalogued** in `scripts/.catalog/metadata.json` plus **185 deprecated forwarding shims** excluded from the catalog (`onDiskScripts = totalScripts + excludedScripts`): endpoint management (Intune/Winget), server administration, security compliance, M365, cloud (Azure/AWS), databases, and CI/CD automation.

- **PowerShell:** developed on PowerShell 7 (5.1-compatible where noted)
- **Style:** enforced by PSScriptAnalyzer + a CI gate (see [§3 CI/CD](#3-cicd-pipeline))
- **Docs:** in-repo, under `docs/` (this page is part of the docs tree)
- **License:** Apache 2.0

## 2. Repository Layout

```text
bug-free-umbrella/
├── scripts/                  # 566 scripts on disk (381 catalogued), organized by domain
│   ├── automation/           #   CI/CD pipelines, Infrastructure as Code
│   ├── cloud/                #   Azure (incl. AVD), AWS, containers
│   ├── collaboration/        #   M365, Exchange, Teams, SharePoint
│   ├── data/                 #   Databases, APIs
│   ├── endpoints/            #   Intune, Winget, proactive remediations, device health
│   ├── infrastructure/       #   Windows servers, AD, network, virtualization, IIS
│   ├── security/             #   Compliance frameworks, hardening, monitoring
│   ├── utilities/            #   General-purpose toolbox
│   └── .catalog/             #   Machine-readable script metadata + compatibility matrix
├── docs/                     # All documentation (this tree) — single source of truth
├── examples/                 # End-to-end workflow examples (onboarding, incident response, …)
├── Tests/                    # Pester 5 suites, mirroring scripts/ 1:1
├── templates/                # Script templates (e.g. Intune app detection)
└── .github/                  # Issue/PR templates, workflows, CODEOWNERS
```

```mermaid
flowchart LR
    subgraph SCRIPTS[scripts/ — 8 domains]
        A[automation<br/>CI/CD · IaC]
        C[cloud<br/>Azure · AWS · containers]
        L[collaboration<br/>M365 · Exchange · Teams]
        D[data<br/>Databases · APIs]
        E[endpoints<br/>Intune · Winget · Remediations]
        I[infrastructure<br/>Windows · AD · Network · IIS]
        S[security<br/>Compliance · Hardening]
        U[utilities]
    end
    CAT[.catalog<br/>metadata + compatibility] -. indexes .-> SCRIPTS
    MOD[Module<br/>BugFreeUmbrella.psd1 + .psm1] -. exports .-> SCRIPTS
    DOC[docs/ · Architecture · Catalog · Guides] -. documents .-> SCRIPTS
    TST[Tests/ — mirrors scripts/ 1:1] -. validates .-> SCRIPTS
```

## 3. CI/CD Pipeline

Every push/PR runs **four jobs** in `validate-powershell.yml` — `analyze` (PSScriptAnalyzer), `syntax-check` (Language.Parser), `test` (Pester + per-script test mirror + module smoke) and `summary` (the aggregate merge gate); supporting workflows keep the repo tidy and docs healthy.

```mermaid
flowchart TD
    PUSH[Push / Pull Request] --> CO[Checkout]
    CO --> PSSA[analyze<br/>PSScriptAnalyzer · curated settings]
    CO --> SYN[syntax-check<br/>Language.Parser]
    CO --> PESTER[test<br/>Pester + test mirror + module smoke]
    PSSA -->|Error findings| FAIL[❌ Fail]
    PSSA -->|Warnings only| OK1[✅ Pass]
    SYN -->|Parse errors| FAIL
    SYN -->|Clean| OK1
    PESTER -->|Failed tests| FAIL
    PESTER -->|Passed| OK1
    OK1 --> SUM[summary<br/>aggregate merge gate]
    SUM --> MERGE[Merge to main]
    MERGE --> LABELER[issue-labeler<br/>auto-labels new issues<br/>resilient fallback]
    MERGE --> STALE[stale<br/>closes inactive issues/PRs]
    PUSH -.->|PRs touching *.md / weekly| LINK[markdown-link-check<br/>lychee]
```

| Workflow | Trigger | Role |
|---|---|---|
| `validate-powershell.yml` | PRs + pushes to main | **Gating:** PSSA (fails on Error) + syntax check + **Pester tests** (fails on test failures; coverage informational) |
| `issue-labeler.yml` | Issue open/edit | Auto-applies 36 technology/type/priority labels (28 technology + 6 issue type + 2 priority; resilient: bulk → per-label fallback → auto-create missing) |
| `markdown-link-check.yml` | PRs touching `*.md`, push to main (`*.md`), weekly, manual | Checks markdown links via lychee (`fail: false` — warns on broken links, tolerates 429) |
| `stale.yml` | Daily | Marks/closes inactive issues (60d) and PRs (30d) |

> **Note:** Pester tests run both locally (`Invoke-Pester` via `Tests/Pester.Config.psd1`) and in CI (`test` job in `validate-powershell.yml`). Coverage is enabled but not gating — low coverage does not fail the pipeline.
## 4. Release Process

Releases are CHANGELOG-driven — the version lives only in `CHANGELOG.md`. (Pre-relaunch releases used weather-themed codenames; that scheme is retired.)

```mermaid
flowchart LR
    F[Feature branch] -->|PR| M[Merge to main]
    M --> R[Release PR:<br/>chore: release vX.Y.Z<br/>CHANGELOG bump + rename]
    R --> RT[Tag vX.Y.Z]
    RT --> REL[GitHub Release]
```

Releases follow [Semantic Versioning](https://semver.org). The pre-relaunch weather-codename scheme (Drizzle/Shower/Thunderstorm/Hurricane/Rainbow) is retired; see the CHANGELOG for historical mapping.

## 5. Script Conventions

Every script follows a strict contract (enforced by PSScriptAnalyzer settings + CI):

- **Header:** comment-based help (`.SYNOPSIS` presence is CI-gated) — `Get-Help .\Script.ps1 -Detailed` must work
- **Functions:** `[CmdletBinding()]`, approved verbs (`Get-Verb`), `SupportsShouldProcess` + `-WhatIf` for state-changing scripts
- **Errors:** `$ErrorActionPreference = 'Stop'`, `try/catch` with `Write-Host "[-] ..."` (red) / `"[+]"` (green) / `"[!]"` (yellow) / `"[*]"` (cyan) messaging
- **Exit codes:** `0` success, `1` failure
- **Formatting:** 4-space indent, CRLF + UTF-8 BOM, ≤120 chars/line, no trailing whitespace
- **Credentials:** never hardcoded — env vars, Key Vault, or secure prompts

```mermaid
flowchart LR
    HELP[Comment-based help] --> PARAM[[CmdletBinding + validation]]
    PARAM --> FLOW{try / catch}
    FLOW -->|success| OK["Write-Host [+] · exit 0"]
    FLOW -->|error| ERR["Write-Host [-] · exit 1"]
```

## 6. Testing

- **Pester 5.5.0+**, config in `Tests/Pester.Config.psd1`
- One suite per script, mirrored 1:1: `scripts/X/Y/Z.ps1` → `Tests/X/Y/Z.Tests.ps1`, gated by the `test` job's mirror check. Never flatten to `Tests/<Name>.Tests.ps1` — basenames like `detect.ps1` collide.
- Run locally: `Invoke-Pester -Configuration (New-PesterConfiguration -Hashtable (Import-PowerShellDataFile ./Tests/Pester.Config.psd1))`

## 7. Documentation Architecture

Docs live **in the repository** — no external wiki (retired 2026-08-08). Benefits: versioned with code, PR-reviewable, link-checked by review, impossible to silently drift.

`docs/Module.md` is auto-generated from the manifest + catalog (see `tools/Build-Docs.ps1`)
and is the PSGallery-facing reference. It is **not** currently validated in CI — issue #285
tracks wiring `Build-Docs.ps1 -Validate` into the pipeline.

Module loads 357 generated wrapper functions (+3 helpers = 360 exported commands) via Build-Module, version from CHANGELOG, PSSA 0

```mermaid
flowchart LR
    HUB[docs/README.md<br/>entry point + map]
    HUB --> GS[Getting Started]
    HUB --> CAT[Script Catalog]
    HUB --> ARCH[This page]
    GS --> FAQ[FAQ] & TRO[ Troubleshooting]
    CAT --> DOMAIN[Category guides<br/>Intune · Server · Security · M365 · Cloud · Data]
    DOMAIN --> SCRIPTS2[scripts/ tree]
```
- **`docs/README.md`** — entry point, documentation map, by-domain index
- **`docs/Script-Catalog.md`** — full index of all scripts with paths
- **Category guides** — one page per domain (Intune, Server Management, Security, M365, Cloud…)
- **`docs/ARCHITECTURE.md`** — this page
- **Per-category `README.md` files** under `scripts/` — directory-level docs next to the code they describe

## 8. Community Files

| File | Purpose |
|---|---|
| [CONTRIBUTING.md](../CONTRIBUTING.md) | How to contribute (issues, PRs, coding standards) |
| [GOVERNANCE.md](../GOVERNANCE.md) | Project governance, solo-maintainer model |
| [SECURITY.md](../SECURITY.md) | Vulnerability reporting policy |
| [SUPPORT.md](../SUPPORT.md) | Getting help, response-time expectations |
| [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) | Community standards |
| [WARP.md](../WARP.md) | Working practices for AI-assisted contributors |
| [CHANGELOG.md](../CHANGELOG.md) | Full version history with codenames |
