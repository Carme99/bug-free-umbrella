# RELAUNCH-SPEC — v1.0.0 Relaunch Standards Contract

> Binding contract for every script in `scripts/` and every test in `Tests/`.
> Extends [AGENTS.md](../AGENTS.md); where this file is more specific, this file wins.
> Every rule below is mechanical/checkable. Builders apply it; critics verify it item-by-item.

---

## 1. Script Standard

Every `.ps1` under `scripts/` MUST satisfy ALL of:

- **Header block**: exactly the AGENTS.md required-header shape (comment-based help block, then `[CmdletBinding()]`, then `param(...)`). All `.NOTES` fields present and populated:
  - `File Name` : actual filename
  - `Author`    : existing author preserved; new/anonymous scripts use `Bug-Free Umbrella`
  - `Prerequisite`: `PowerShell 7.0` (or `PowerShell 5.1+` if the script targets 5.1 compat per §4)
  - `Version`   : `1.0.0` — no exceptions during relaunch
  - `Date`      : `2026-08-23` — relaunch date on all touched scripts
- **`[CmdletBinding()]`** mandatory on every script and every advanced function (`function` without it is a violation unless it is a trivial private helper inside a script).
- **Destructive operations** (delete, overwrite, stop service, uninstall, config change) MUST declare `[CmdletBinding(SupportsShouldProcess)]` and gate mutation behind `if ($PSCmdlet.ShouldProcess($target, $action)) { ... }`. A destructive op without a `ShouldProcess` guard fails review.
- **Approved verbs only** for function names (`Get-Verb`). Non-approved verbs are fixed *inside* files; filenames stay as-is (§6).
- **Formatting**: 4-space indent (no tabs), max line length 120 columns, no trailing whitespace.
- **Encoding**: UTF-8 **with BOM**; line endings **CRLF**. Verify: first bytes `EF BB BF`; no bare `LF` bytes.
- Parameters validated with `[Validate*]` attributes where a domain constraint exists (`[ValidateNotNullOrEmpty()]`, `[ValidateSet()]`, ranges).

## 2. Help Standard

Comment-based help MUST include, at minimum:

| Section | Rule |
|---|---|
| `.SYNOPSIS` | One line, imperative ("Install...", "Check..."), ≤120 chars |
| `.DESCRIPTION` | ≥2 sentences or ≥1 bullet list explaining behavior + side effects |
| `.PARAMETER X` | One per declared parameter — zero omissions; order matches `param()` order |
| `.EXAMPLE` | **≥2**, each showing a realistic invocation with a `PS C:\>` prompt line |
| `.NOTES` | All five fields per §1 |

- **`Get-Help .\Script.ps1 -Detailed` MUST render completely** — no orphaned sections, no parameter listed in help that isn't in `param()` (and vice versa). This is a critic check run verbatim.
- Examples MUST be syntactically valid PowerShell if pasted (parameter names correct, mandatory params supplied).

## 3. Behavior Standard

Every executable script wraps its body in a `Main` function and runs it ONLY on direct invocation:

```powershell
$ErrorActionPreference = 'Stop'

function Main {
    try {
        Write-Host "[*] Starting..." -ForegroundColor Cyan

        # validate inputs early: throw before doing work
        if (-not $RequiredParam) { throw "Parameter -RequiredParam is required" }

        $result = Invoke-Something -ErrorAction Stop   # critical calls carry explicit -ErrorAction Stop

        Write-Host "[+] Done" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
```

Rules:
- `$ErrorActionPreference = 'Stop'` set at top of script body (before `function Main`).
- **`Main` + top-level guard are MANDATORY** on every script. `exit` MUST appear only in the guard line — never inside `Main`, never at top level unguarded. This makes dot-sourcing safe (no runner termination) and lets tests call `Main` directly and assert its return value (§5).

- **Exit codes**: `exit 0` on success path only; `exit 1` on any failure. Detect/remediate pairs: detect scripts MAY use additional documented codes (e.g. `exit 1` = non-compliant) — document them in `.DESCRIPTION` and tests assert the documented code.
- **Output prefixes** (via `Write-Host`, colors per AGENTS.md):
  - `[+]` success (Green) · `[!]` warning (Yellow) · `[-]` error (Red) · `[*]` info/progress (Cyan)
- `-ErrorAction Stop` on every call whose failure must abort the script (module cmdlets, `Invoke-RestMethod`, wrapper functions, file writes).
- **Native executables** (`winget`, `git`, `reg.exe`, ...) MUST be called ONLY through thin wrapper functions (e.g. `function Invoke-Winget { & winget.exe @args; return $LASTEXITCODE }`). Pester cannot mock native commands — wrappers are the mock seam (§5). Check the wrapper's `$LASTEXITCODE` and translate non-zero to failure handling.
- **Idempotency**: re-running a script on an already-converged system MUST succeed (exit 0) and make no further changes. Check-then-act pattern: test state first, act only when needed, report `[+] Already ...` style outcome. Destructive ops additionally honor `-WhatIf`.

## 4. Compatibility Standard

- **Primary target: PowerShell 7.0+.**
- Scripts MUST be parse-clean under both 7.x and Windows PowerShell 5.1 semantics unless they opt out.
- **Opt-out mechanism**: `#Requires -Version 7.0` as line 1 (before the help block). If present, the script may freely use PS7-only features and 5.1 checks skip it.
- **Static-checkable rule** (critics verify by regex/token scan of the AST): a script WITHOUT `#Requires -Version 7.0` MUST NOT contain any of:
  - Ternary operator: `? :` expression form — token kind `QuestionMark` followed by non-pattern-match usage
  - Null-coalescing operators: `??`, `??=`
  - Pipeline chain operators: `&&`, `||`
  - `ForEach-Object -Parallel` / `ForEach -Parallel`
  - PS7-only cmdlet parameters: e.g. `-Parallel`, `-AsHashtable` on `ConvertFrom-Json`
  - Clean-up blocks in `try/catch/finally` beyond what 5.1 supports
- Windows-only cmdlets (`Get-WmiObject`, registry providers, etc.) are allowed syntactically; their absence on Linux is handled by tests via mocks (§5), never by requiring Windows to pass CI.
- Encoding/BOM/CRLF rules (§1) apply identically — 5.1 misparses BOM-less UTF-8.

## 5. Test Standard

- **One test file per script**: `Tests/<script's repo-relative path>.Tests.ps1` — mirror the script's directory structure under `Tests/`, replacing `.ps1` with `.Tests.ps1` (`scripts/endpoints/devices/autopatch/V3/detect.ps1` → `Tests/endpoints/devices/autopatch/V3/detect.Tests.ps1`). NEVER flatten to `Tests/detect.Tests.ps1` — dozens of scripts share basenames like `detect.ps1`/`remediate.ps1`; flattening collides. Create `Tests/` subdirectories as needed.
- **Pester 5 syntax ONLY**: `Describe`/`Context`/`It`; ALL setup inside `BeforeAll { }` (no Pester 4 `BeforeEach`/script-scope variables); `#Requires -Modules Pester` at top.
- Structure per AGENTS.md Test Structure, extended:
  - `Context "Help & Metadata"` — header fields present, Version is `1.0.0`, Date is `2026-08-23`, `.PARAMETER` count matches param count
  - `Context "Syntax & Static"` — parses via `[System.Management.Automation.Language.Parser]::ParseFile`, no PS7-only tokens unless `#Requires -Version 7.0`
  - `Context "Behavior"` — **≥1 behavioral test per script**: execute the script's logic against MOCKED externals and assert observable outcomes (exit code, output prefix, file/service state via mock)
- **Mocking rules (hard requirements)**:
  - Mock ALL external commands/modules: `Mock Get-Command`, `Mock Invoke-RestMethod`, `Mock Connect-MgGraph`, `Mock Az.*`, `Mock Get-Service`, etc. — inside `BeforeAll`.
  - Pester CANNOT mock native executables (`winget.exe`, `git`, ...). Per §3, scripts route native calls through wrapper functions; tests Mock the WRAPPERS (e.g. `Mock Invoke-Winget { 0 }`). A test that tries `Mock winget` is invalid, and a script calling a native exe without a wrapper fails review.
  - Tests MUST NOT require network access, admin elevation, Azure/M365 connectivity, or installed product modules at runtime. Module-dependent scripts load the real module's surface via `InModuleScope` or mock at the command-name level; if a module cannot even be loaded offline, mock its entry points and assert the script's guard logic instead.
  - Tests MUST pass offline on Linux `pwsh` — that is the CI environment.
- **Worked example** — canonical dot-source + Main + mocking pattern (adapt per script):

```powershell
#Requires -Modules Pester

Describe "Test-RemediationFixTempFiles" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/system/ -> script is two levels up + across.
        $scriptPath = Join-Path $PSScriptRoot "../../scripts/endpoints/system/Test-RemediationFixTempFiles.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (§3).
        . $scriptPath

        # Mock external commands so nothing leaves the machine.
        # Native exes are mocked via their wrapper functions, never by name.
        Mock Remove-Item { }
    }

    Context "Behavior" {
        It "Cleans temp files and returns 0 on success" {
            Mock Get-ChildItem { @([pscustomobject]@{ FullName = "/tmp/junk.log"; Length = 500MB }) }
            Main | Should -Be 0
            Should -Invoke Remove-Item -Times 1 -Exactly
        }

        It "Is idempotent: converged system returns 0 with no changes" {
            Mock Get-ChildItem { @() }   # nothing left to clean
            Main | Should -Be 0
            Should -Invoke Remove-Item -Times 0 -Exactly -Because "nothing left to clean"
        }

        It "Returns 1 and writes [-] prefixed output on upstream failure" {
            Mock Get-ChildItem { throw "disk gone" }
            $out = Main *>&1                       # capture all streams: Write-Host + return value
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
```

## 6. Naming & Migration Rules

- **NO renames of script files or paths. Ever.** Docs, catalog entries, badges, and Intune Proactive Remediations references depend on current names/locations.
- Verb/noun fixes happen **inside** files: rename functions, fix help titles, correct `.NOTES File Name` only if it currently mismatches the actual filename.
- New files only via explicit instruction from Main; builders do not invent scripts.
- Deleted/deprecated content: mark deprecated in `.SYNOPSIS` ("DEPRECATED: use X") rather than removing the file.
- `_templates/` directories follow the same standards except where template placeholders make rules inapplicable (e.g. examples) — note deviations inline in the template.

## 7. Definition of Done — Per-Script Checklist

Critics verify EVERY box independently. A script is done only when all boxes pass:

1. ☐ Header block matches §1 exactly; `Version: 1.0.0`, `Date: 2026-08-23`, `File Name` matches disk filename.
2. ☐ `[CmdletBinding()]` present; `SupportsShouldProcess` + `ShouldProcess` guard on all destructive ops.
3. ☐ All function verbs approved (`Get-Verb`).
4. ☐ Formatting: 4-space indent, ≤120 cols, no trailing whitespace.
5. ☐ UTF-8 BOM present; CRLF endings.
6. ☐ Help complete per §2: SYNOPSIS, DESCRIPTION, one PARAMETER per param, ≥2 EXAMPLES, NOTES; `Get-Help -Detailed` renders fully.
7. ☐ `$ErrorActionPreference = 'Stop'` + AGENTS.md try/catch inside `Main`; `Main` + top-level dot-source guard present; `exit` only in the guard line (§3).
8. ☐ Output uses `[+]`/`[!]`/`[-]`/`[*]` prefixes with correct colors.
9. ☐ Critical calls carry `-ErrorAction Stop`; native exes invoked ONLY via wrapper functions with `$LASTEXITCODE` checked.
10. ☐ Idempotent: safe to re-run, converged runs exit 0 with no changes.
11. ☐ No PS7-only syntax without `#Requires -Version 7.0` on line 1 (§4 static rule passes).
12. ☐ `Tests/<mirrored relative path>/<ScriptName>.Tests.ps1` exists per §5, Pester 5 syntax, all setup in `BeforeAll`.
13. ☐ ≥1 behavioral test asserting observable behavior via mocked externals; zero network/admin/module-install requirements.
14. ☐ Test passes: `pwsh -NoProfile -Command "Invoke-Pester -Path ./Tests/<mirrored relative path>/<ScriptName>.Tests.ps1"` → green, offline, on Linux.
15. ☐ Filename/path unchanged (§6).
16. ☐ `Invoke-ScriptAnalyzer -Path <script>` returns zero errors (warnings need justification comment).
