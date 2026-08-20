<#
.SYNOPSIS
    Interactive launcher and discovery tool for bug-free-umbrella scripts.

.DESCRIPTION
    Loads scripts/.catalog/metadata.json and provides search, filter and
    interactive discovery of all 358+ scripts in the repository.

    Supports listing, fuzzy search on path/synopsis/category, category
    prefix filtering, and an interactive picker (Out-GridView when
    available, otherwise a numbered console menu) that previews help and
    offers to invoke the selected script with -WhatIf.

    If metadata.json is missing the tool warns and attempts to generate it
    by invoking tools/Build-Catalog.ps1.

.PARAMETER Search
    Case-insensitive fuzzy filter applied to path, synopsis and category.
    Example: -Search intune

.PARAMETER Category
    Filter by category prefix. Example: -Category endpoints/intune or
    -Category intune (matches any category containing the string).

.PARAMETER List
    Show a table of all scripts (Name, Category, Synopsis truncated to
    80 characters).

.PARAMETER Interactive
    Launch interactive picker. Uses Out-GridView if available, otherwise
    a numbered list with Read-Host selection. After selection, shows
    synopsis, required modules (with availability check), parameter list,
    and offers to invoke with -WhatIf.

.PARAMETER ValidateOnly
    When a script is selected (via -Search / -Category / -Interactive),
    only validate parameters and required modules; do not prompt to invoke.

.EXAMPLE
    pwsh -File ./Invoke-Umbrella.ps1 -List | head

    Lists all scripts in a table.

.EXAMPLE
    pwsh -File ./Invoke-Umbrella.ps1 -Search intune

    Returns scripts matching "intune" in path, synopsis or category.

.EXAMPLE
    pwsh -File ./Invoke-Umbrella.ps1 -Category endpoints/intune -List

    Lists only scripts under endpoints/intune.

.EXAMPLE
    pwsh -File ./Invoke-Umbrella.ps1 -Interactive

    Opens the interactive picker.

.EXAMPLE
    pwsh -File ./Invoke-Umbrella.ps1 -Search azure -ValidateOnly

    Validates matching scripts without prompting to invoke.

.NOTES
    File Name  : Invoke-Umbrella.ps1
    Author     : Carme99
    Prerequisite: PowerShell 7.0+
    Version    : 1.0.0
    Date       : 2026-08-20
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Search,

    [Parameter(Mandatory = $false)]
    [string]$Category,

    [Parameter(Mandatory = $false)]
    [switch]$List,

    [Parameter(Mandatory = $false)]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    $repoRoot = (Get-Location).Path
}

$catalogPath = Join-Path $repoRoot 'scripts/.catalog/metadata.json'
$buildCatalogPath = Join-Path $repoRoot 'tools/Build-Catalog.ps1'

function Import-CatalogData {
    if (-not (Test-Path -LiteralPath $catalogPath)) {
        Write-Host "[!] Catalog not found at $catalogPath" -ForegroundColor Yellow
        if (Test-Path -LiteralPath $buildCatalogPath) {
            Write-Host "[*] Attempting to generate catalog..." -ForegroundColor Cyan
            try {
                & $buildCatalogPath
            } catch {
                Write-Host "[-] Failed to generate catalog: $($_.Exception.Message)" -ForegroundColor Red
                exit 1
            }
        } else {
            Write-Host "[-] Build-Catalog.ps1 not found at $buildCatalogPath" -ForegroundColor Red
            exit 1
        }
        if (-not (Test-Path -LiteralPath $catalogPath)) {
            Write-Host '[-] Catalog still missing after generation attempt.' -ForegroundColor Red
            exit 1
        }
    }

    try {
        $raw = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8
        $data = $raw | ConvertFrom-Json
        return $data
    } catch {
        Write-Host "[-] Failed to load catalog: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

function Show-ScriptTable {
    param($Scripts)

    $table = $Scripts | ForEach-Object {
        $syn = $_.synopsis
        if ($null -ne $syn -and $syn.Length -gt 80) {
            $syn = $syn.Substring(0, 77) + '...'
        }
        [PSCustomObject]@{
            Name     = $_.name
            Category = $_.category
            Synopsis = $syn
            Path     = $_.path
        }
    }

    if ($table.Count -eq 0) {
        Write-Host '[!] No scripts matched.' -ForegroundColor Yellow
        return
    }

    $table | Format-Table -AutoSize | Out-String -Width 4096 | Write-Host
}

function Show-ScriptDetail {
    param($Script)

    Write-Host '' -ForegroundColor White
    Write-Host ("=== {0} ===" -f $Script.name) -ForegroundColor Cyan
    Write-Host ("Path    : {0}" -f $Script.path) -ForegroundColor White
    Write-Host ("Category: {0}" -f $Script.category) -ForegroundColor White
    Write-Host ("Synopsis: {0}" -f $Script.synopsis) -ForegroundColor White
    if ($Script.description) {
        Write-Host ("Description: {0}" -f $Script.description) -ForegroundColor White
    }
    if ($Script.tags -and $Script.tags.Count -gt 0) {
        Write-Host ("Tags    : {0}" -f ($Script.tags -join ', ')) -ForegroundColor White
    }
    Write-Host ("CmdletBinding: {0}" -f $Script.hasCmdletBinding) -ForegroundColor White

    # Required modules availability
    if ($Script.requiresModules -and $Script.requiresModules.Count -gt 0) {
        Write-Host 'Required Modules:' -ForegroundColor Cyan
        foreach ($mod in $Script.requiresModules) {
            $available = Get-Module -ListAvailable -Name $mod -ErrorAction SilentlyContinue
            if ($available) {
                Write-Host ("  [+] {0} (available)" -f $mod) -ForegroundColor Green
            } else {
                Write-Host ("  [-] {0} (not installed)" -f $mod) -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host 'Required Modules: none' -ForegroundColor DarkGray
    }

    # Parameters
    if ($Script.parameters -and $Script.parameters.Count -gt 0) {
        Write-Host 'Parameters:' -ForegroundColor Cyan
        foreach ($p in $Script.parameters) {
            $mand = if ($p.mandatory) { 'mandatory' } else { 'optional' }
            Write-Host ("  - {0} [{1}] ({2})" -f $p.name, $p.type, $mand) -ForegroundColor White
        }
    } else {
        Write-Host 'Parameters: none' -ForegroundColor DarkGray
    }

    # Try Get-Help preview if file exists
    $fullPath = Join-Path $repoRoot ("scripts/" + $Script.path)
    # Script.path no longer has scripts/ prefix, so join with scripts/
    if (-not (Test-Path -LiteralPath $fullPath)) {
        # Try without prefix handling
        $fullPath = Join-Path $repoRoot $Script.path
    }
    if (Test-Path -LiteralPath $fullPath) {
        try {
            $helpText = Get-Help -Name $fullPath -ErrorAction SilentlyContinue | Out-String
            if ($helpText -and $helpText.Trim().Length -gt 0) {
                Write-Host '' -ForegroundColor White
                Write-Host '--- Get-Help preview ---' -ForegroundColor DarkCyan
                # Truncate to 30 lines
                $lines = $helpText -split "`n" | Select-Object -First 30
                $lines | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
            }
        } catch {
            Write-Verbose "Get-Help failed: $($_.Exception.Message)"
        }
    }
}

# -------------------------------------------------------------------------
# Main
# -------------------------------------------------------------------------

$catalog = Import-CatalogData
$allScripts = @($catalog.scripts)

Write-Host ("[*] Loaded catalog: {0} scripts (v{1}, {2})" -f $catalog.totalScripts, $catalog.version, $catalog.generated) -ForegroundColor DarkGray

# Apply filters
$filtered = $allScripts

if ($Search) {
    $searchLower = $Search.ToLowerInvariant()
    $filtered = $filtered | Where-Object {
        $_.path.ToLowerInvariant().Contains($searchLower) -or
        $_.synopsis.ToLowerInvariant().Contains($searchLower) -or
        $_.category.ToLowerInvariant().Contains($searchLower)
    }
    Write-Host ("[*] Search '{0}' matched {1} script(s)." -f $Search, @($filtered).Count) -ForegroundColor Cyan
}

if ($Category) {
    $catLower = $Category.ToLowerInvariant()
    $filtered = $filtered | Where-Object {
        $_.category.ToLowerInvariant().StartsWith($catLower) -or
        $_.category.ToLowerInvariant().Contains($catLower)
    }
    Write-Host ("[*] Category '{0}' matched {1} script(s)." -f $Category, @($filtered).Count) -ForegroundColor Cyan
}

if ($Interactive) {
    if (@($filtered).Count -eq 0) {
        Write-Host '[!] No scripts to pick from.' -ForegroundColor Yellow
        exit 0
    }

    $selected = $null

    # Try Out-GridView if available
    $hasGridView = $null -ne (Get-Command -Name Out-GridView -ErrorAction SilentlyContinue)
    if ($hasGridView) {
        try {
            $gridData = $filtered | ForEach-Object {
                $syn = $_.synopsis
                if ($syn.Length -gt 80) { $syn = $syn.Substring(0, 77) + '...' }
                [PSCustomObject]@{
                    Name     = $_.name
                    Category = $_.category
                    Synopsis = $syn
                    Path     = $_.path
                    _raw     = $_
                }
            }
            $picked = $gridData | Out-GridView -Title 'Select a script (Invoke-Umbrella)' -PassThru
            if ($picked) {
                # Handle single or multiple selection - take first
                $firstPicked = @($picked)[0]
                $selected = $firstPicked._raw
                if (-not $selected) {
                    # Fallback: match by path
                    $selected = $filtered | Where-Object { $_.path -eq $firstPicked.Path } | Select-Object -First 1
                }
            }
        } catch {
            Write-Host "[!] Out-GridView failed: $($_.Exception.Message) - falling back to console." -ForegroundColor Yellow
            $hasGridView = $false
        }
    }

    if (-not $selected) {
        if (-not $hasGridView) {
            # Console numbered list
            Write-Host '' -ForegroundColor White
            Write-Host 'Select a script:' -ForegroundColor Cyan
            $idx = 1
            foreach ($s in $filtered) {
                $syn = $s.synopsis
                if ($syn.Length -gt 70) { $syn = $syn.Substring(0, 67) + '...' }
                Write-Host ("  [{0}] {1} ({2}) - {3}" -f $idx, $s.name, $s.category, $syn) -ForegroundColor White
                $idx++
            }
            $choice = Read-Host 'Enter number (or press Enter to cancel)'
            if ([string]::IsNullOrWhiteSpace($choice)) {
                Write-Host '[*] Cancelled.' -ForegroundColor DarkGray
                exit 0
            }
            $num = 0
            if ([int]::TryParse($choice, [ref]$num) -and $num -ge 1 -and $num -le $filtered.Count) {
                $selected = @($filtered)[$num - 1]
            } else {
                Write-Host '[-] Invalid selection.' -ForegroundColor Red
                exit 1
            }
        } else {
            # Grid view was available but user cancelled
            Write-Host '[*] No selection made.' -ForegroundColor DarkGray
            exit 0
        }
    }

    if ($selected) {
        Show-ScriptDetail -Script $selected

        if ($ValidateOnly) {
            Write-Host '' -ForegroundColor White
            Write-Host '[*] ValidateOnly: skipping invoke prompt.' -ForegroundColor Cyan
            exit 0
        }

        Write-Host '' -ForegroundColor White
        $answer = Read-Host 'Invoke this script with -WhatIf? (y/N)'
        if ($answer -match '^[Yy]') {
            $fullPath = Join-Path $repoRoot ("scripts/" + $selected.path)
            if (-not (Test-Path -LiteralPath $fullPath)) {
                $fullPath = Join-Path $repoRoot $selected.path
            }
            if (Test-Path -LiteralPath $fullPath) {
                Write-Host ("[*] Invoking: {0} -WhatIf" -f $fullPath) -ForegroundColor Cyan
                try {
                    & $fullPath -WhatIf 2>&1 | Write-Host -ForegroundColor White
                } catch {
                    Write-Host "[-] Invoke failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "[-] Script file not found: $fullPath" -ForegroundColor Red
            }
        } else {
            Write-Host '[*] Skipped invoke.' -ForegroundColor DarkGray
        }
    }
    exit 0
}

# Non-interactive output
if ($List -or (-not $Search -and -not $Category)) {
    # Default to list when no filter and no explicit flag? Spec says -List triggers table.
    # If no filter and no flag at all, show table as well for discoverability.
    Show-ScriptTable -Scripts $filtered
} else {
    # Filtered but not -List: still show table of filtered results
    Show-ScriptTable -Scripts $filtered
}

if ($ValidateOnly -and @($filtered).Count -gt 0) {
    Write-Host '' -ForegroundColor White
    Write-Host '[*] ValidateOnly: details for matched scripts:' -ForegroundColor Cyan
    foreach ($s in $filtered) {
        Show-ScriptDetail -Script $s
    }
}
