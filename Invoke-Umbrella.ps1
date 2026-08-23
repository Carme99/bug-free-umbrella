<#
.SYNOPSIS
    Interactive launcher and discovery tool for bug-free-umbrella scripts.

.DESCRIPTION
    Loads scripts/.catalog/metadata.json and provides search, filter and
    interactive discovery of all 358+ scripts. Supports fuzzy search on
    path/synopsis/category, category prefix filtering, exact-name lookup
    (-Name), direct invocation (-Invoke with ShouldProcess), bulk export
    (-Export), and a cross-platform picker tier: Out-GridView -> fzf
    --multi --preview -> numbered list. If metadata.json is missing, tries
    tools/Build-Catalog.ps1.

.PARAMETER Search
    Case-insensitive fuzzy filter applied to path, synopsis and category.
    Example: -Search intune

.PARAMETER Category
    Filter by category prefix. Example: -Category endpoints/intune or
    -Category intune (matches any category containing the string).

.PARAMETER Name
    Exact filename or leaf-folder match (case-insensitive, .ps1 optional).
    Example: -Name Fix-TeamsCache. With -Category disambiguates duplicates.

.PARAMETER Invoke
    When filtered set is single script, invoke it via Invoke-BUScript with
    ShouldProcess forwarding. Honors -WhatIf. Multiple matches -> error.

.PARAMETER Export
    Copy matched script file(s) to destination. Directory if path exists as
    dir, ends with / or \, or multiple matches. Single match may be file
    path. Creates parent dirs. Respects -WhatIf via ShouldProcess.

.PARAMETER List
    Show a table of all scripts (Name, Category, Synopsis truncated to
    80 characters).

.PARAMETER Interactive
    Launch interactive picker. Uses Out-GridView if available, otherwise
    fzf --multi --preview on Linux/macOS, otherwise numbered list.

.PARAMETER ValidateOnly
    Only validate parameters and required modules; do not prompt to invoke.

.EXAMPLE
    pwsh -File ./Invoke-Umbrella.ps1 -List

.EXAMPLE
    pwsh -File ./Invoke-Umbrella.ps1 -Search intune

.EXAMPLE
    pwsh -File ./Invoke-Umbrella.ps1 -Name Fix-TeamsCache -List

.EXAMPLE
    pwsh -File ./Invoke-Umbrella.ps1 -Invoke -Name Fix-TeamsCache -WhatIf

.EXAMPLE
    pwsh -File ./Invoke-Umbrella.ps1 -Export /tmp/bu-export -Search intune

.NOTES
    File Name  : Invoke-Umbrella.ps1
    Author     : Carme99
    Prerequisite: PowerShell 7.0+
    Version    : 1.0.0
#>

[CmdletBinding(DefaultParameterSetName = 'Default', SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [string]$Search,
    [Parameter()]
    [string]$Category,
    [Parameter(ParameterSetName = 'Name')]
    [string]$Name,
    [Parameter()]
    [switch]$Invoke,
    [Parameter()]
    [string]$Export,
    [Parameter()]
    [switch]$List,
    [Parameter()]
    [switch]$Interactive,
    [Parameter()]
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($repoRoot)) { $repoRoot = (Get-Location).Path }
$catalogPath = Join-Path $repoRoot 'scripts/.catalog/metadata.json'
$buildCatalogPath = Join-Path $repoRoot 'tools/Build-Catalog.ps1'

# Dev-mode: dot-source Public/*.ps1 so launcher shares module implementation
$cliPublic = Join-Path $repoRoot 'src/BugFreeUmbrella/Public'
if (Test-Path -LiteralPath $cliPublic) {
    Get-ChildItem -Path $cliPublic -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
        try { . $_.FullName } catch { Write-Verbose "dot-source $($_.Name) failed: $($_.Exception.Message)" }
    }
}

function Import-CatalogData {
    if (-not (Test-Path -LiteralPath $catalogPath)) {
        Write-Host "[!] Catalog not found at $catalogPath" -ForegroundColor Yellow
        if (Test-Path -LiteralPath $buildCatalogPath) {
            Write-Host "[*] Attempting to generate catalog..." -ForegroundColor Cyan
            try { & $buildCatalogPath } catch {
                Write-Host "[-] Failed to generate catalog: $($_.Exception.Message)" -ForegroundColor Red; exit 1
            }
        } else { Write-Host "[-] Build-Catalog.ps1 not found at $buildCatalogPath" -ForegroundColor Red; exit 1 }
        if (-not (Test-Path -LiteralPath $catalogPath)) { Write-Host '[-] Catalog still missing after generation.' -ForegroundColor Red; exit 1 }
    }
    try { $raw = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8; $raw | ConvertFrom-Json } catch {
        Write-Host "[-] Failed to load catalog: $($_.Exception.Message)" -ForegroundColor Red; exit 1
    }
}

function Show-ScriptTable {
    param($Scripts)
    $table = $Scripts | ForEach-Object {
        $syn = $_.synopsis; if ($null -ne $syn -and $syn.Length -gt 80) { $syn = $syn.Substring(0, 77) + '...' }
        [PSCustomObject]@{ Name = $_.name; Category = $_.category; Synopsis = $syn; Path = $_.path }
    }
    if (@($table).Count -eq 0) { Write-Host '[!] No scripts matched.' -ForegroundColor Yellow; return }
    $table | Format-Table -AutoSize | Out-String -Width 4096 | Write-Host
}

function Show-ScriptDetail {
    param($Script)
    Write-Host '' -ForegroundColor White
    Write-Host ("=== {0} ===" -f $Script.name) -ForegroundColor Cyan
    Write-Host ("Path    : {0}" -f $Script.path) -ForegroundColor White
    Write-Host ("Category: {0}" -f $Script.category) -ForegroundColor White
    Write-Host ("Synopsis: {0}" -f $Script.synopsis) -ForegroundColor White
    if ($Script.description) { Write-Host ("Description: {0}" -f $Script.description) -ForegroundColor White }
    if ($Script.tags -and $Script.tags.Count -gt 0) { Write-Host ("Tags    : {0}" -f ($Script.tags -join ', ')) -ForegroundColor White }
    Write-Host ("CmdletBinding: {0}" -f $Script.hasCmdletBinding) -ForegroundColor White
    if ($Script.requiresModules -and $Script.requiresModules.Count -gt 0) {
        Write-Host 'Required Modules:' -ForegroundColor Cyan
        foreach ($mod in $Script.requiresModules) {
            $a = Get-Module -ListAvailable -Name $mod -ErrorAction SilentlyContinue
            if ($a) { Write-Host ("  [+] {0} (available)" -f $mod) -ForegroundColor Green } else { Write-Host ("  [-] {0} (not installed)" -f $mod) -ForegroundColor Yellow }
        }
    } else { Write-Host 'Required Modules: none' -ForegroundColor DarkGray }
    if ($Script.parameters -and $Script.parameters.Count -gt 0) {
        Write-Host 'Parameters:' -ForegroundColor Cyan
        foreach ($p in $Script.parameters) {
            $mand = if ($p.mandatory) { 'mandatory' } else { 'optional' }
            Write-Host ("  - {0} [{1}] ({2})" -f $p.name, $p.type, $mand) -ForegroundColor White
        }
    } else { Write-Host 'Parameters: none' -ForegroundColor DarkGray }
    $fullPath = Join-Path $repoRoot ("scripts/" + $Script.path)
    if (-not (Test-Path -LiteralPath $fullPath)) { $fullPath = Join-Path $repoRoot $Script.path }
    if (Test-Path -LiteralPath $fullPath) {
        try {
            $helpText = Get-Help -Name $fullPath -ErrorAction SilentlyContinue | Out-String
            if ($helpText -and $helpText.Trim().Length -gt 0) {
                Write-Host '' -ForegroundColor White
                Write-Host '--- Get-Help preview ---' -ForegroundColor DarkCyan
                ($helpText -split "`n" | Select-Object -First 30) | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
            }
        } catch { Write-Verbose "Get-Help failed: $($_.Exception.Message)" }
    }
}

function Test-TargetSupportsShouldProcess {
    param([string]$ResolvedPath)
    try {
        $ci = Get-Command -Name $ResolvedPath -ErrorAction Stop
        if ($ci.Parameters.ContainsKey('WhatIf')) { return $true }
    } catch { Write-Verbose "Get-Command probe failed: $($_.Exception.Message)" }
    try {
        $errs = $null; $toks = $null; $ast = [System.Management.Automation.Language.Parser]::ParseFile($ResolvedPath, [ref]$toks, [ref]$errs)
        if ($null -ne $ast.ParamBlock.Attributes) {
            foreach ($attr in $ast.ParamBlock.Attributes) {
                if ($attr.TypeName.Name -eq 'CmdletBinding') {
                    foreach ($named in $attr.NamedArguments) { if ($named.ArgumentName -eq 'SupportsShouldProcess') { return $true } }
                }
            }
        }
        if ($ast.Extent.Text -match '\$PSCmdlet\.ShouldProcess') { return $true }
    } catch { Write-Verbose "AST probe failed: $($_.Exception.Message)" }
    return $false
}

# Completer wiring (best-effort)
try {
    $catComp = {
        param($cn, $pn, $word, $ast, $fake)
        try {
            $cat = $null; if (Get-Command Get-BUCatalog -ErrorAction SilentlyContinue) { $cat = Get-BUCatalog } elseif (Get-Command Import-CatalogData -ErrorAction SilentlyContinue) { $cat = Import-CatalogData }
            if (-not $cat -or -not $cat.scripts) { return }
            $doms = @($cat.scripts | ForEach-Object { ($_.category -split '/')[0] } | Sort-Object -Unique)
            if ($doms.Count -eq 0) { $doms = @('automation', 'cloud', 'collaboration', 'data', 'endpoints', 'infrastructure', 'security', 'utilities') }
            $pref = if ($null -ne $word) { $word.ToLowerInvariant() } else { '' }
            $doms | Where-Object { $_.ToLowerInvariant().Contains($pref) } | ForEach-Object {
                $cnt = @($cat.scripts | Where-Object { $_.category -like "$_/*" -or $_.category -eq $_ }).Count
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "$_ - $cnt scripts")
            }
        } catch { Write-Verbose "cat completer: $($_.Exception.Message)" }
    }
    $nameComp = {
        param($cn, $pn, $word, $ast, $fake)
        try {
            $cat = $null; if (Get-Command Get-BUCatalog -ErrorAction SilentlyContinue) { $cat = Get-BUCatalog } elseif (Get-Command Import-CatalogData -ErrorAction SilentlyContinue) { $cat = Import-CatalogData }
            if (-not $cat -or -not $cat.scripts) { return }
            $pref = if ($null -ne $word) { $word.ToLowerInvariant() } else { '' }
            $cands = $cat.scripts | Where-Object { $_.name.ToLowerInvariant().Contains($pref) -or ($_.name -replace '\.ps1$', '').ToLowerInvariant().Contains($pref) -or $_.path.ToLowerInvariant().Contains($pref) } | Sort-Object name | Select-Object -First 200
            foreach ($e in $cands) {
                $tt = "$($e.name) ($($e.category)) - $($e.synopsis)"; if ($tt.Length -gt 90) { $tt = $tt.Substring(0, 87) + '...' }
                [System.Management.Automation.CompletionResult]::new($e.name, $e.name, 'ParameterValue', $tt)
            }
        } catch { Write-Verbose "name completer: $($_.Exception.Message)" }
    }
    Register-ArgumentCompleter -CommandName 'Invoke-Umbrella.ps1' -ParameterName Category -ScriptBlock $catComp -ErrorAction SilentlyContinue
    Register-ArgumentCompleter -CommandName 'Invoke-Umbrella.ps1' -ParameterName Name -ScriptBlock $nameComp -ErrorAction SilentlyContinue
} catch { Write-Verbose "completer wiring: $($_.Exception.Message)" }

# -------------------------------------------------------------------------
# Main
# -------------------------------------------------------------------------
$catalog = Import-CatalogData
$allScripts = @($catalog.scripts)
Write-Host ("[*] Loaded catalog: {0} scripts (v{1}, {2})" -f $catalog.totalScripts, $catalog.version, $catalog.generated) -ForegroundColor DarkGray

# Unified filtering - prefer Get-BUScript when available, else inline
$useGBS = $null -ne (Get-Command Get-BUScript -ErrorAction SilentlyContinue)
if ($useGBS -and (-not [string]::IsNullOrWhiteSpace($Name) -or -not [string]::IsNullOrWhiteSpace($Search) -or -not [string]::IsNullOrWhiteSpace($Category))) {
    $gp = @{}; if (-not [string]::IsNullOrWhiteSpace($Name)) { $gp['Name'] = $Name }
    if (-not [string]::IsNullOrWhiteSpace($Search)) { $gp['Search'] = $Search }
    if (-not [string]::IsNullOrWhiteSpace($Category)) { $gp['Category'] = $Category }
    if ($List) { $gp['List'] = $true }
    try {
        $filtered = @(Get-BUScript @gp)
        if ($Search) { Write-Host ("[*] Search '{0}' matched {1} script(s)." -f $Search, @($filtered).Count) -ForegroundColor Cyan }
        if ($Category) { Write-Host ("[*] Category '{0}' matched {1} script(s)." -f $Category, @($filtered).Count) -ForegroundColor Cyan }
        if ($Name) {
            Write-Host ("[*] Name '{0}' matched {1} script(s)." -f $Name, @($filtered).Count) -ForegroundColor Cyan
            if (@($filtered).Count -eq 0) { Write-Warning "No script named '$Name' found."; exit 1 }
        }
    } catch { Write-Host "[-] Get-BUScript filter failed: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
} else {
    $filtered = $allScripts
    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $nl = $Name.ToLowerInvariant().Trim(); $nExt = if ($nl.EndsWith('.ps1')) { $nl } else { "$nl.ps1" }; $nNoExt = $nl -replace '\.ps1$', ''
        $filtered = $filtered | Where-Object {
            $nL = $_.name.ToLowerInvariant(); $leaf = ''
            try { $leaf = (Split-Path $_.path -Parent -ErrorAction SilentlyContinue | Split-Path -Leaf -ErrorAction SilentlyContinue); if ($null -eq $leaf) { $leaf = '' } } catch { $leaf = '' }
            ($nL -eq $nExt) -or ($nL -eq $nl) -or ($leaf.ToLowerInvariant() -eq $nNoExt) -or ($leaf.ToLowerInvariant() -eq $nl)
        }
        Write-Host ("[*] Name '{0}' matched {1} script(s)." -f $Name, @($filtered).Count) -ForegroundColor Cyan
        if (@($filtered).Count -eq 0) { Write-Warning "No script named '$Name' found."; exit 1 }
        if (-not [string]::IsNullOrWhiteSpace($Category)) {
            $cl = $Category.ToLowerInvariant()
            $filtered = $filtered | Where-Object { $_.category.ToLowerInvariant().StartsWith($cl) -or $_.category.ToLowerInvariant().Contains($cl) }
            Write-Host ("[*] Category '{0}' matched {1} script(s)." -f $Category, @($filtered).Count) -ForegroundColor Cyan
        }
    } else {
        if ($Search) {
            $sl = $Search.ToLowerInvariant()
            $filtered = $filtered | Where-Object { $_.path.ToLowerInvariant().Contains($sl) -or $_.synopsis.ToLowerInvariant().Contains($sl) -or $_.category.ToLowerInvariant().Contains($sl) }
            Write-Host ("[*] Search '{0}' matched {1} script(s)." -f $Search, @($filtered).Count) -ForegroundColor Cyan
        }
        if ($Category) {
            $cl = $Category.ToLowerInvariant()
            $filtered = $filtered | Where-Object { $_.category.ToLowerInvariant().StartsWith($cl) -or $_.category.ToLowerInvariant().Contains($cl) }
            Write-Host ("[*] Category '{0}' matched {1} script(s)." -f $Category, @($filtered).Count) -ForegroundColor Cyan
        }
    }
}

# Export
if (-not [string]::IsNullOrWhiteSpace($Export)) {
    if (@($filtered).Count -eq 0) { Write-Host '[!] No scripts to export.' -ForegroundColor Yellow; exit 0 }
    $isDir = $false
    if ((Test-Path -LiteralPath $Export) -and (Get-Item -LiteralPath $Export -ErrorAction SilentlyContinue).PSIsContainer) { $isDir = $true }
    elseif ($Export.EndsWith('/') -or $Export.EndsWith('\') -or @($filtered).Count -gt 1) { $isDir = $true }
    if (-not $isDir -and @($filtered).Count -gt 1) { Write-Error "-Export file path requires a single match; $($filtered.Count) matched."; exit 1 }
    $exported = 0
    foreach ($entry in $filtered) {
        $src = Join-Path $repoRoot ("scripts/" + $entry.path); if (-not (Test-Path -LiteralPath $src)) { $src = Join-Path $repoRoot $entry.path }
        if (-not (Test-Path -LiteralPath $src)) { Write-Warning "Source not found, skipping: $($entry.path)"; continue }
        if ($isDir) {
            $dd = $Export.TrimEnd('/\')
            if (-not (Test-Path -LiteralPath $dd)) { if ($PSCmdlet.ShouldProcess($dd, 'Create export directory')) { New-Item -ItemType Directory -Path $dd -Force | Out-Null } }
            $dst = Join-Path $dd (Split-Path $entry.path -Leaf)
            if (Test-Path -LiteralPath $dst) {
                $baseLeaf = [System.IO.Path]::GetFileNameWithoutExtension($dst)
                $extLeaf = [System.IO.Path]::GetExtension($dst)
                $parentLeaf = Split-Path $entry.category -Leaf
                if ([string]::IsNullOrWhiteSpace($parentLeaf)) { $parentLeaf = 'script' }
                $uniqueName = "${parentLeaf}_${baseLeaf}${extLeaf}"
                $dst = Join-Path $dd $uniqueName
                $suffix = 1
                while (Test-Path -LiteralPath $dst) {
                    $uniqueName = "${parentLeaf}_${baseLeaf}_$suffix${extLeaf}"
                    $dst = Join-Path $dd $uniqueName
                    $suffix++
                }
            }
        } else {
            $dst = $Export; $pd = Split-Path -Parent $dst
            if (-not [string]::IsNullOrWhiteSpace($pd) -and -not (Test-Path -LiteralPath $pd)) { if ($PSCmdlet.ShouldProcess($pd, 'Create export parent directory')) { New-Item -ItemType Directory -Path $pd -Force | Out-Null } }
        }
        try {
            if ($PSCmdlet.ShouldProcess($dst, "Copy $($entry.path)")) { Copy-Item -LiteralPath $src -Destination $dst -Force; $exported++; Write-Verbose "Exported $($entry.path) -> $dst" }
            else { Write-Host "[WhatIf] Would copy $($entry.path) -> $dst" -ForegroundColor DarkGray; $exported++ }
        } catch { Write-Error "Export failed for $($entry.path): $($_.Exception.Message)"; exit 1 }
    }
    Write-Host ("[+] Exported {0} script(s) to {1}" -f $exported, $Export) -ForegroundColor Green; exit 0
}

# Invoke single
if ($Invoke) {
    if (@($filtered).Count -eq 0) { Write-Host '[!] No scripts to invoke.' -ForegroundColor Yellow; exit 1 }
    if (@($filtered).Count -gt 1) { Write-Error "-Invoke requires a single match; use -Name or narrow -Search/-Category (matched $($filtered.Count))."; exit 1 }
    $tgt = @($filtered)[0]; $fp = Join-Path $repoRoot ("scripts/" + $tgt.path); if (-not (Test-Path -LiteralPath $fp)) { $fp = Join-Path $repoRoot $tgt.path }
    if (-not (Test-Path -LiteralPath $fp)) { Write-Host "[-] Script file not found: $fp" -ForegroundColor Red; exit 1 }
    $hasIBS = Get-Command Invoke-BUScript -ErrorAction SilentlyContinue
    if ($hasIBS) {
        try { if ($WhatIfPreference.IsPresent -or $PSBoundParameters.ContainsKey('WhatIf')) { Invoke-BUScript -Path $fp -WhatIf } else { Invoke-BUScript -Path $fp } } catch { Write-Host "[-] Invoke failed: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
    } else {
        $sup = Test-TargetSupportsShouldProcess -ResolvedPath $fp
        if ($PSCmdlet.ShouldProcess($fp, 'Invoke script')) {
            $isW = $WhatIfPreference.IsPresent -or $PSBoundParameters.ContainsKey('WhatIf')
            if ($isW) {
                if ($sup) { Write-Host ("[*] Invoking: {0} -WhatIf" -f $fp) -ForegroundColor Cyan; try { & $fp -WhatIf 2>&1 | Write-Host -ForegroundColor White } catch { Write-Host "[-] Invoke failed: $($_.Exception.Message)" -ForegroundColor Red } }
                else { Write-Warning "Target script does not support -WhatIf; showing ShouldProcess message instead." }
            } else { Write-Host ("[*] Invoking: {0}" -f $fp) -ForegroundColor Cyan; try { & $fp 2>&1 | Write-Host -ForegroundColor White } catch { Write-Host "[-] Invoke failed: $($_.Exception.Message)" -ForegroundColor Red } }
        }
    }
    exit 0
}

# Interactive
if ($Interactive) {
    $isCI = $env:CI -eq 'true' -or $Host.Name -eq 'ServerRemoteHost' -or [Console]::IsInputRedirected
    if ($isCI) { Write-Warning 'Interactive mode requires a console; use -Search/-Category/-Name instead.'; exit 1 }
    if (@($filtered).Count -eq 0) { Write-Host '[!] No scripts to pick from.' -ForegroundColor Yellow; exit 0 }
    $selected = $null
    $hasGridView = $null -ne (Get-Command -Name Out-GridView -ErrorAction SilentlyContinue)
    if ($hasGridView) {
        try {
            $gridData = $filtered | ForEach-Object {
                $syn = $_.synopsis; if ($syn.Length -gt 80) { $syn = $syn.Substring(0, 77) + '...' }
                [PSCustomObject]@{ Name = $_.name; Category = $_.category; Synopsis = $syn; Path = $_.path; _raw = $_ }
            }
            $picked = $gridData | Out-GridView -Title 'Select a script (Invoke-Umbrella)' -PassThru
            if ($picked) { $fp2 = @($picked)[0]; $selected = $fp2._raw; if (-not $selected) { $selected = $filtered | Where-Object { $_.path -eq $fp2.Path } | Select-Object -First 1 } }
        } catch { Write-Host "[!] Out-GridView failed: $($_.Exception.Message) - falling back to console." -ForegroundColor Yellow; $hasGridView = $false }
    }
    if (-not $selected) {
        $hasFzf = $false
        if ((-not $hasGridView) -and ($IsLinux -or $IsMacOS)) { $hasFzf = $null -ne (Get-Command -Name fzf -ErrorAction SilentlyContinue) }
        if ($hasFzf) {
            try {
                $fzfInput = $filtered | ForEach-Object { $syn = $_.synopsis; if ($syn.Length -gt 60) { $syn = $syn.Substring(0, 57) + '...' }; "{0}`t{1}`t{2}`t{3}" -f $_.name, $_.category, $syn, $_.path }
                $selLine = $fzfInput | fzf --ansi --multi --delimiter "`t" --with-nth 1,2,3 --preview 'echo {4}' --preview-window down:3:wrap 2>$null
                $fzfExit = $LASTEXITCODE
                if ($fzfExit -eq 130 -or [string]::IsNullOrWhiteSpace($selLine)) { Write-Host '[*] Cancelled (fzf).' -ForegroundColor DarkGray; exit 0 }
                $sp = (@($selLine)[0] -split "`t")[3]
                if ($sp) { $selected = $filtered | Where-Object { $_.path -eq $sp } | Select-Object -First 1 }
                if (-not $selected) { $selected = $filtered | Where-Object { $_.name -eq ((@($selLine)[0] -split "`t")[0]) } | Select-Object -First 1 }
            } catch { Write-Host "[!] fzf failed: $($_.Exception.Message) - falling back to console." -ForegroundColor Yellow; $hasFzf = $false; $selected = $null }
        }
        if (-not $selected -and -not $hasFzf) {
            if (-not $hasGridView) {
                Write-Host '' -ForegroundColor White; Write-Host 'Select a script:' -ForegroundColor Cyan; $idx = 1
                foreach ($s in $filtered) { $syn = $s.synopsis; if ($syn.Length -gt 70) { $syn = $syn.Substring(0, 67) + '...' }; Write-Host ("  [{0}] {1} ({2}) - {3}" -f $idx, $s.name, $s.category, $syn) -ForegroundColor White; $idx++ }
                $choice = Read-Host 'Enter number (or press Enter to cancel)'
                if ([string]::IsNullOrWhiteSpace($choice)) { Write-Host '[*] Cancelled.' -ForegroundColor DarkGray; exit 0 }
                $num = 0
                if ([int]::TryParse($choice, [ref]$num) -and $num -ge 1 -and $num -le $filtered.Count) { $selected = @($filtered)[$num - 1] } else { Write-Host '[-] Invalid selection.' -ForegroundColor Red; exit 1 }
            } else { Write-Host '[*] No selection made.' -ForegroundColor DarkGray; exit 0 }
        } elseif (-not $selected -and $hasFzf) { Write-Host '[*] No selection made (fzf).' -ForegroundColor DarkGray; exit 0 }
    }
    if ($selected) {
        Show-ScriptDetail -Script $selected
        if ($ValidateOnly) { Write-Host '' -ForegroundColor White; Write-Host '[*] ValidateOnly: skipping invoke prompt.' -ForegroundColor Cyan; exit 0 }
        Write-Host '' -ForegroundColor White; $ans = Read-Host 'Invoke this script with -WhatIf? (y/N)'
        if ($ans -match '^[Yy]') {
            $fullPath = Join-Path $repoRoot ("scripts/" + $selected.path); if (-not (Test-Path -LiteralPath $fullPath)) { $fullPath = Join-Path $repoRoot $selected.path }
            if (Test-Path -LiteralPath $fullPath) {
                $hasIBS2 = Get-Command Invoke-BUScript -ErrorAction SilentlyContinue
                if ($hasIBS2) { try { Invoke-BUScript -Path $fullPath -WhatIf } catch { Write-Host "[-] Invoke failed: $($_.Exception.Message)" -ForegroundColor Red } }
                else { $sup2 = Test-TargetSupportsShouldProcess -ResolvedPath $fullPath; if ($sup2) { Write-Host ("[*] Invoking: {0} -WhatIf" -f $fullPath) -ForegroundColor Cyan; try { & $fullPath -WhatIf 2>&1 | Write-Host -ForegroundColor White } catch { Write-Host "[-] Invoke failed: $($_.Exception.Message)" -ForegroundColor Red } } else { Write-Host ("[*] Invoking: {0}" -f $fullPath) -ForegroundColor Cyan; try { & $fullPath 2>&1 | Write-Host -ForegroundColor White } catch { Write-Host "[-] Invoke failed: $($_.Exception.Message)" -ForegroundColor Red } } }
            } else { Write-Host "[-] Script file not found: $fullPath" -ForegroundColor Red }
        } else { Write-Host '[*] Skipped invoke.' -ForegroundColor DarkGray }
    }
    exit 0
}

# Non-interactive output
if ($List -or (-not $Search -and -not $Category -and [string]::IsNullOrWhiteSpace($Name))) { Show-ScriptTable -Scripts $filtered } else { Show-ScriptTable -Scripts $filtered }
if ($ValidateOnly -and @($filtered).Count -gt 0) {
    Write-Host '' -ForegroundColor White; Write-Host '[*] ValidateOnly: details for matched scripts:' -ForegroundColor Cyan
    foreach ($s in $filtered) { Show-ScriptDetail -Script $s }
}
