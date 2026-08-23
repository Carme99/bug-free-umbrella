# Module Usage Recipes

Five quick recipes for the `BugFreeUmbrella` module (PowerShell 7+). Import once per session, then drive the 357-script catalog from the command line.

```powershell
Import-Module ./src/BugFreeUmbrella -Force
```

Expected output: none on success — the prompt returns and 360 commands become available (`(Get-Command -Module BugFreeUmbrella).Count` → `360`). Tab completion for `-Category` / `-Name` is registered automatically.

---

## 1. Discover scripts by keyword

```powershell
Get-BUScript -Search intune
```

Expected output: a table of matching catalog entries — **35 matches** today, e.g. `Export-WingetPackageList.ps1`, `New-IntuneWinPackage.ps1`, plus name/category/path columns for each hit.

## 2. Preview a script safely with -WhatIf

```powershell
Get-BUScript -Search winget |
    Select-Object -First 1 |
    Invoke-BUScript -WhatIf
```

Expected output (nothing executes):

```
What if: Performing the operation "Invoke script" on target ".../scripts/endpoints/intune/deployment/Export-WingetPackageList.ps1".
```

## 3. Register tab completion

```powershell
Register-BUCompleter
```

Expected output: none — completers for `Get-BUScript` / `Invoke-BUScript` `-Category`, `-Name`, and `-Search` are re-registered silently; pressing <kbd>Tab</kbd> after `Get-BUScript -Category ` now cycles categories like `endpoints`, `security`.

## 4. Validate module build artifacts

```powershell
pwsh -NoProfile -File ./tools/Build-Module.ps1 -Validate
```

Expected output:

```
[+] Module artifacts are up to date.
    ModuleVersion=5.0.0  Functions=360  GUID=7cc494cc-4523-4630-a69e-12b77001c0f0
[+] Test-ModuleManifest passed
[+] PSScriptAnalyzer passed (0 Errors, 81 Warnings)
[+] Module built: .../src/BugFreeUmbrella  ModuleVersion=5.0.0  Functions=360
```

## 5. Install from the PowerShell Gallery

```powershell
Install-Module BugFreeUmbrella -Scope CurrentUser
Import-Module BugFreeUmbrella
```

Expected output: an untrusted-repository prompt once (`Do you want to install the modules from 'PSGallery'?` → `Y`), then silence on import with all 360 commands available in every new session.

---

See [docs/Getting-Started.md](../../docs/Getting-Started.md) for the full tour and [docs/Script-Catalog.md](../../docs/Script-Catalog.md) for all 357 scripts.
