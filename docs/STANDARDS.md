# STANDARDS — BugFreeUmbrella Script & Test Contract (v2.0.0)

> Binding contract for every script in `scripts/` and every test in `Tests/`.
> Extends [AGENTS.md](../AGENTS.md); where this file is more specific, this file wins.
> Every rule below is mechanical/checkable. Builders apply it; critics verify it item-by-item.
>
> This document supersedes the v1.0.0 relaunch contract, which is retired as of v2.0.0 and no
> longer shipped; this file is the standard of record from v2.0.0 onward.

---

## 0. Counting convention

One convention, stated once, used everywhere:

```
onDiskScripts = totalScripts + excludedScripts
```

- **`onDiskScripts`** — every non-test `.ps1` under `scripts/`.
- **`totalScripts`** — catalogued scripts; equals `scripts[].Count` in
  `scripts/.catalog/metadata.json`.
- **`excludedScripts`** — files on disk that are deliberately **not** catalogued: the deprecated
  forwarding-shim trees `scripts/endpoints/devices/winget/` and
  `scripts/endpoints/devices/proactive-remediations/`. Every file there forwards to a canonical
  implementation under `scripts/endpoints/remediation/` and is excluded so that the catalog and the
  generated module have exactly one entry per operation.

The three counts and the rule are emitted by `tools/Build-Catalog.ps1` into `metadata.json`
(`totalScripts`, `excludedScripts`, `onDiskScripts`, `excludedPaths`, `countingConvention`), and
`scripts/.catalog/metadata.schema.json` defines them. **No document may assert a script count that
is not one of these three.** Excluded files are still gated by CI (analyzer, syntax, test mirror)
and are still stamped by the standard.

---

## 1. Script Standard

Every `.ps1` under `scripts/` MUST satisfy ALL of:

- **Header block**: exactly the AGENTS.md required-header shape (comment-based help block, then
  `[CmdletBinding()]`, then `param(...)`). All `.NOTES` fields present and populated:
  - `File Name` — actual filename
  - `Author` — existing author preserved; new/anonymous scripts use `Bug-Free Umbrella`
  - `Prerequisite` — `PowerShell 7.0` (or `PowerShell 5.1+` if the script targets 5.1 compat per §4)
  - `Version` — the **standard revision the file conforms to** (currently `2.0.0`)
  - `Date` — the date the file was last stamped against that revision (currently `2026-09-16`)
- **`[CmdletBinding()]`** mandatory on every script and every advanced function.
- **Destructive operations** MUST declare `[CmdletBinding(SupportsShouldProcess)]` and gate mutation
  behind `if ($PSCmdlet.ShouldProcess($target, $action)) { ... }`. This applies to operations that
  change user, device or tenant state.
  **Exempt:** disposing of ephemeral artifacts the script itself created in the same run (a temp
  file it just wrote, a plan file it just produced). Record the exemption in an inline comment.
- **Approved verbs only** for function names (`Get-Verb`). Non-approved verbs are fixed *inside*
  files; filenames stay as-is (§6).
- **Formatting**: 4-space indent (no tabs), max line length 120 columns, no trailing whitespace.
  **Exempt:** a line may exceed 120 columns only when the overflow past column 120 contains no
  whitespace — i.e. it cannot be wrapped without breaking a single unbreakable token such as a URL.
- **Encoding**: UTF-8 **with BOM**; line endings **CRLF**. Verify: first bytes `EF BB BF`; no bare
  `LF` bytes.
- Parameters validated with `[Validate*]` attributes where a domain constraint exists.

### 1.1 Helper interfaces

Scripts that share a helper (for example `scripts/endpoints/intune/IntuneGraphHelper.psm1`) MUST
call it with the parameters the helper actually declares. A call against an advanced function with
an unknown parameter is a terminating binding error, so a mismatch makes the whole script
non-functional and returns exit 1. When a script's help documents a parameter that reaches a
helper, the helper MUST accept it — either implement the pass-through or remove the parameter from
both the script and its help.

## 2. Help Standard

Comment-based help MUST include, at minimum:

| Section | Rule |
|---|---|
| `.SYNOPSIS` | One line, imperative ("Install...", "Check..."), ≤120 chars |
| `.DESCRIPTION` | ≥2 sentences or ≥1 bullet list explaining behaviour + side effects |
| `.PARAMETER X` | One per declared parameter — zero omissions; order matches `param()` order |
| `.EXAMPLE` | **≥2**, each showing a realistic invocation with a `PS C:\>` prompt line |
| `.NOTES` | All five fields per §1 |

- **`Get-Help .\Script.ps1 -Detailed` MUST render completely** — no orphaned sections, no parameter
  listed in help that is not in `param()` (and vice versa).
- Examples MUST be syntactically valid PowerShell if pasted.
- **Help must describe what the code does.** A `.DESCRIPTION` that advertises output the script never
  produces, a parameter whose stated filter direction is the opposite of the implementation, or an
  accepted `ValidateSet` value with no handler, is a defect — not a documentation nit.

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
- `$ErrorActionPreference = 'Stop'` set at top of script body (before `function Main`). Single or
  double quotes are both accepted.
- **`Main` + top-level guard are MANDATORY** on every script. **`exit` MUST appear only in the guard
  line** — never inside `Main`, never at top level unguarded. A stricter guard that also detects
  dot-source-with-arguments (`-not ($MyInvocation.InvocationName -eq '.' -or $MyInvocation.Line -match '^\s*\.\s')`)
  is also conforming.
- **Exit codes**: `exit 0` on success path only; non-zero on failure. Detect/remediate pairs and
  audit scripts MAY use additional documented codes (e.g. `2` = findings present) — document them in
  `.DESCRIPTION` and assert them in the mirrored test. **A run that produced no output, exported no
  items, or targeted no resources MUST NOT return success.**
- **Output prefixes** (via `Write-Host`, colors per AGENTS.md):
  `[+]` success (Green) · `[!]` warning (Yellow) · `[-]` error (Red) · `[*]` info/progress (Cyan).
- `-ErrorAction Stop` on every call whose failure must abort the script.
- **Native executables** (`winget`, `git`, `reg.exe`, …) MUST be called ONLY through thin wrapper
  functions (e.g. `function Invoke-Winget { & winget.exe @args; return $LASTEXITCODE }`). Pester
  cannot mock native commands — wrappers are the mock seam (§5). Check `$LASTEXITCODE` and translate
  non-zero to failure handling.
- **Paging**: a Graph/REST collection MUST be followed through `@odata.nextLink` (or the module's
  `-All`) before it is reported as complete. Silently reporting the first page is a defect.
- **Type normalisation**: values read from a REST response MUST be normalised before comparison
  (e.g. `if ($value -is [string]) { $value = [datetime]::Parse($value) }`). Comparing a raw
  ISO-string to a `[datetime]` does not do what it looks like.
- **Idempotency**: re-running a script on an already-converged system MUST succeed (exit 0) and make
  no further changes. Check-then-act: test state first, act only when needed, report
  `[+] Already ...` style outcome. Destructive ops additionally honor `-WhatIf`.
- **Working directory**: a script MUST NOT write files into the current directory. Default every
  output path to a parameter (`-OutputPath`) whose default is under `$env:TEMP`, so a normal run
  leaves the working tree unchanged. This matters most under .NET APIs, which do not translate
  backslashes the way PowerShell providers do.
- **Errors MUST NOT be swallowed silently.** An empty `catch { }` with no message, or
  `-ErrorAction SilentlyContinue` on a lookup whose failure changes what the script reports, is a
  defect. "Found nothing" and "the query failed" must be distinguishable to the caller.

## 4. Compatibility Standard

- **Primary target: PowerShell 7.0+.**
- Scripts MUST be parse-clean under both 7.x and Windows PowerShell 5.1 semantics unless they opt out.
- **Opt-out mechanism**: `#Requires -Version 7.0` as line 1 (before the help block).
- **Static-checkable rule**: a script WITHOUT `#Requires -Version 7.0` MUST NOT contain:
  - the ternary operator (`? :`), null-coalescing (`??`, `??=`) or pipeline-chain (`&&`, `||`) operators;
  - `ForEach-Object -Parallel` / `-Parallel` cmdlet parameters;
  - `ConvertFrom-Json -AsHashtable`;
  - `try/catch/finally` clean-up forms beyond what 5.1 supports.
- Windows-only cmdlets are allowed syntactically; their absence on Linux is handled by tests via
  mocks (§5), never by requiring Windows to pass CI.
- Encoding/BOM/CRLF rules (§1) apply identically — 5.1 misparses BOM-less UTF-8.

## 5. Test Standard

- **One test file per script**: `Tests/<script's repo-relative path>.Tests.ps1` — mirror the
  directory structure under `Tests/`, replacing `.ps1` with `.Tests.ps1`. NEVER flatten to
  `Tests/detect.Tests.ps1` — dozens of scripts share basenames. Create `Tests/` subdirectories as
  needed. **Directory names under `Tests/` MUST match the case of their script counterparts** —
  case-only collisions (`Tests/Collaboration` vs `Tests/collaboration`) behave differently on
  Windows/macOS than on Linux and are forbidden.
- Repo-level suites with no 1:1 script (`Tests/Catalog.Tests.ps1`, `Tests/Module.Tests.ps1`,
  `Tests/CLI.Tests.ps1`, `Tests/WARP.Tests.ps1`, `Tests/Common/`, `Tests/CI/`,
  `Tests/ProactiveRemediations/`) are permitted alongside the mirror.
- **Pester 5 syntax ONLY**: `Describe`/`Context`/`It`; ALL setup inside `BeforeAll { }`;
  `#Requires -Modules Pester` at top.
- Structure: `Context "Help & Metadata"`, `Context "Syntax & Static"`, `Context "Behavior"` with
  **≥1 behavioural test per script** against mocked externals.
- **Mocking rules (hard requirements)**:
  - Mock ALL external commands/modules inside `BeforeAll`.
  - Pester CANNOT mock native executables; tests Mock the script's wrapper functions (§3).
  - Tests MUST NOT require network, admin elevation, tenant connectivity, or installed product
    modules. Declare product cmdlets as empty stub functions, then `Mock` them.
  - **Stubs MUST be advanced functions** (`[CmdletBinding()]`) with the **real parameter set** of
    whatever they stand in for. A simple (non-advanced) function accepts arbitrary extra named
    parameters, so a stub written to match a call site instead of the real interface will pass while
    the script cannot run. This is the single most common way a green suite hides a broken script.
  - Tests MUST pass offline on Linux `pwsh` — that is the CI environment.
  - Tests MUST NOT create files in the repository working directory; use the test's temp directory.
- **A test that cannot fail is a defect.** Asserting only that a file exists, or asserting `$true`,
  is not coverage. Assert observable behaviour: exit codes, `[+]/[!]/[-]` output, cmdlet invocation
  counts, and at least one failure path.

## 6. Naming & Migration Rules

- **NO renames of script files or paths. Ever.** Docs, catalog entries, badges and Intune Proactive
  Remediations references depend on current names/locations.
- Verb/noun fixes happen **inside** files. Correct `.NOTES File Name` only if it mismatches disk.
- Deleted/deprecated content: mark deprecated in `.SYNOPSIS` (`DEPRECATED: use X`) and add one
  `.DESCRIPTION` sentence saying why the replacement is authoritative — rather than removing the file.
- `_templates/` directories follow the same standards except where template placeholders make a rule
  inapplicable; note deviations inline.

## 7. Definition of Done — Per-Script Checklist

Critics verify EVERY box independently. A script is done only when all boxes pass:

1. ☐ Header block matches §1; `Version` = current standard revision, `Date` = stamp date,
   `File Name` matches the disk filename.
2. ☐ `[CmdletBinding()]` present; `SupportsShouldProcess` + `ShouldProcess` on every destructive op
   (with the §1 ephemeral-artifact exemption commented when used).
3. ☐ All function verbs approved (`Get-Verb`).
4. ☐ Formatting: 4-space indent, ≤120 columns (unbreakable-token exemption only), no trailing whitespace.
5. ☐ UTF-8 BOM present; CRLF endings.
6. ☐ Help complete per §2 and truthful about output, parameters and accepted values.
7. ☐ `$ErrorActionPreference = 'Stop'` + try/catch inside `Main`; `Main` + dot-source guard present;
   `exit` only in the guard line.
8. ☐ Output uses `[+]/[!]/[-]/[*]` prefixes with correct colors.
9. ☐ Critical calls carry `-ErrorAction Stop`; native exes via wrapper functions with
   `$LASTEXITCODE` checked; REST collections paged; REST values type-normalised before comparison.
10. ☐ Idempotent: converged runs exit 0 with no changes; no success exit when nothing was produced.
11. ☐ No PS7-only syntax without `#Requires -Version 7.0` on line 1.
12. ☐ No file written into the working directory.
13. ☐ `Tests/<mirrored relative path>/<ScriptName>.Tests.ps1` exists per §5, Pester 5, setup in `BeforeAll`.
14. ☐ ≥1 behavioural test that can fail, with mocked externals and no network/admin/module needs.
15. ☐ Filename/path unchanged (§6).
16. ☐ `Invoke-ScriptAnalyzer -Path <script>` returns zero errors under
    `.vscode/PSScriptAnalyzerSettings.psd1`.

## 8. Enforcement

CI (`.github/workflows/validate-powershell.yml`) gates every pull request on:

| Gate | Rule enforced |
|---|---|
| PSScriptAnalyzer | zero Error-severity findings under `.vscode/PSScriptAnalyzerSettings.psd1` |
| Comment-based help | `.SYNOPSIS` present in every script |
| Syntax | `Parser::ParseFile` reports zero errors for every script |
| Pester | zero failing tests, run on the pinned Pester version |
| Test mirror | every `scripts/**/*.ps1` has a mirrored `Tests/**.Tests.ps1` |
| Freshness | `tools/Build-Catalog.ps1 -Validate`, `tools/Build-Docs.ps1 -Validate`, `tools/Build-Module.ps1 -Validate` |
| Module | the generated module imports and every generated wrapper resolves to a real script file |

Re-stamping the collection for a new standard revision is done with
`pwsh -File tools/Update-StandardVersion.ps1` (supports `-WhatIf`), never by hand.
