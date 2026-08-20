<#
.SYNOPSIS
    Queries the bug-free-umbrella script catalog.

.DESCRIPTION
    Filters scripts/.catalog/metadata.json by fuzzy search, category prefix,
    or exact name. Returns ScriptEntry[] for pipeline composition.
    When metadata.json is absent, falls back to a filesystem scan.

.PARAMETER Search
    Case-insensitive fuzzy filter applied to path, synopsis and category.
    Example: -Search intune  -> 35 matches (v4.4.0 catalog).

.PARAMETER Category
    Filter by category prefix or substring (case-insensitive).
    Example: -Category endpoints  or  -Category endpoints/intune.
    Tab-completes to the 8 top-level domains.

.PARAMETER Name
    Exact filename match (case-insensitive, with or without .ps1 extension).
    Example: -Name Fix-TeamsCache  or  -Name Fix-TeamsCache.ps1.
    Tab-completes to 358 script names via metadata.json.

.PARAMETER List
    Alias for "return all" - when no filter is supplied, returns the full
    catalog. Preserved for compatibility with Invoke-Umbrella.ps1 -List.

.EXAMPLE
    Get-BUScript -Search intune -Category endpoints

    Returns ScriptEntry[] where path/synopsis/category contains "intune"
    AND category contains "endpoints" (logical AND of filters).

.EXAMPLE
    Get-BUScript -Name Fix-TeamsCache

    Returns entries whose leaf folder or filename matches Fix-TeamsCache.

.EXAMPLE
    Get-BUScript -Search winget | Where-Object { $_.category -like '*browsers*' }

    Pipeline-friendly - standard PowerShell filtering composes.

.OUTPUTS
    PSCustomObject (ScriptEntry). Zero, one, or many objects - never $null
    when the catalog loads; empty array on no match (so @() wrapping is safe).

.NOTES
    File Name  : Get-BUScript.ps1
    Prerequisite: PowerShell 7.0+
#>

if (-not (Test-Path variable:script:BUCatalogCache)) { $script:BUCatalogCache = $null }
if (-not (Test-Path variable:script:BUCatalogMtime)) { $script:BUCatalogMtime = $null }
if (-not (Test-Path variable:script:BUCatalogPath)) { $script:BUCatalogPath = $null }

function Get-BUCatalog {
    <#
    .SYNOPSIS
        Gets the catalog with mtime cache.
    #>
    [CmdletBinding()]
    param()
    if ($null -ne $script:BUCatalogCache -and $null -ne $script:BUCatalogPath -and (Test-Path -LiteralPath $script:BUCatalogPath)) {
        try {
            $currentMtime = (Get-Item -LiteralPath $script:BUCatalogPath -ErrorAction SilentlyContinue).LastWriteTimeUtc
            if ($null -ne $currentMtime -and $null -ne $script:BUCatalogMtime -and $currentMtime -eq $script:BUCatalogMtime) {
                Write-Verbose "[Get-BUCatalog] cache hit: $($script:BUCatalogCache.totalScripts) scripts"
                return $script:BUCatalogCache
            }
        }
        catch { Write-Verbose "[Get-BUCatalog] mtime check failed: $($_.Exception.Message)" }
    }
    $candidates = @()
    if ($env:BU_CATALOG_PATH -and -not [string]::IsNullOrWhiteSpace($env:BU_CATALOG_PATH)) { $candidates += $env:BU_CATALOG_PATH }
    if ($PSScriptRoot) {
        $candidates += (Join-Path $PSScriptRoot '../../scripts/.catalog/metadata.json')
        $candidates += (Join-Path $PSScriptRoot '../scripts/.catalog/metadata.json')
    }
    $probe = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($probe)) { $probe = (Get-Location).Path }
    $walk = $probe
    for ($i = 0; $i -lt 6; $i++) {
        $candidates += (Join-Path $walk 'scripts/.catalog/metadata.json')
        $parent = Split-Path -Parent $walk
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $walk) { break }
        $walk = $parent
    }
    if ($PSScriptRoot) { $candidates += (Join-Path $PSScriptRoot 'scripts/.catalog/metadata.json') }
    $catalogPath = $null
    foreach ($c in $candidates) {
        try { $resolved = [System.IO.Path]::GetFullPath($c) } catch { $resolved = $c }
        if (Test-Path -LiteralPath $resolved) { $catalogPath = $resolved; break }
    }
    if (-not $catalogPath) {
        Write-Verbose "[Get-BUCatalog] catalog not found; attempting filesystem fallback"
        $scriptsRoot = $null
        $walk2 = $probe
        for ($j = 0; $j -lt 6; $j++) {
            $testRoot = Join-Path $walk2 'scripts'
            if (Test-Path -LiteralPath $testRoot) { $scriptsRoot = $testRoot; break }
            $p2 = Split-Path -Parent $walk2
            if ([string]::IsNullOrWhiteSpace($p2) -or $p2 -eq $walk2) { break }
            $walk2 = $p2
        }
        if (-not $scriptsRoot) { throw "Catalog not found at $catalogPath and no scripts folder found" }
        $files = Get-ChildItem -Path $scriptsRoot -Filter '*.ps1' -Recurse -File | Sort-Object FullName
        $entries = foreach ($f in $files) {
            [PSCustomObject]@{
                path              = $f.FullName.Replace($scriptsRoot, 'scripts').Replace('\', '/')
                name              = $f.Name
                category          = ($f.DirectoryName.Replace($scriptsRoot, '').Trim('/\') -replace '\\', '/')
                synopsis          = 'No synopsis available.'
                description       = ''
                tags              = @()
                parameters        = @()
                hasCmdletBinding  = $false
                requiresModules   = @()
                functionsExported = @()
            }
        }
        $catalog = [PSCustomObject]@{
            version      = '1.0.0'
            generated    = (Get-Date).ToString('o')
            totalScripts = @($entries).Count
            scripts      = @($entries)
        }
        $script:BUCatalogCache = $catalog
        $script:BUCatalogMtime = (Get-Date).ToUniversalTime()
        $script:BUCatalogPath = $catalogPath
        return $catalog
    }
    $raw = Get-Content -LiteralPath $catalogPath -Raw -ErrorAction Stop
    $catalog = $raw | ConvertFrom-Json -ErrorAction Stop
    try { $mtime = (Get-Item -LiteralPath $catalogPath).LastWriteTimeUtc } catch { $mtime = (Get-Date).ToUniversalTime() }
    $catalog | Add-Member -NotePropertyName '_mtime' -NotePropertyValue $mtime -Force -ErrorAction SilentlyContinue
    $script:BUCatalogCache = $catalog
    $script:BUCatalogMtime = $mtime
    $script:BUCatalogPath = $catalogPath
    return $catalog
}

function Get-BUScript {
    <#
    .SYNOPSIS
        Queries the bug-free-umbrella script catalog.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(ParameterSetName = 'Filter', Position = 0)]
        [string]$Search,

        [Parameter(ParameterSetName = 'Filter')]
        [Parameter(ParameterSetName = 'Name')]
        [string]$Category,

        [Parameter(ParameterSetName = 'Name', Mandatory)]
        [string]$Name,

        [Parameter()]
        [switch]$List,

        [Parameter()]
        [switch]$Interactive
    )
    $catalog = Get-BUCatalog
    $filtered = @($catalog.scripts)
    if ($PSBoundParameters.ContainsKey('Name') -and $Name) {
        $n = $Name.Trim()
        if ($n -like '*.ps1') { $n = $n.Substring(0, $n.Length - 4) }
        $filtered = @($filtered | Where-Object {
            $_.name -ieq "$n.ps1" -or $_.name -ieq $n -or $_.name -like "$n*" -or ($_.path -split '/')[-2] -ieq $n -or $_.path -like "*$n*"
        })
        # If Name matched leaf folder like Fix-TeamsCache, also try leaf dir
        if (@($filtered).Count -eq 0) {
            $filtered = @($catalog.scripts | Where-Object { $_.category -like "*$n*" -or $_.path -like "*$n*" })
        }
    }
    if ($PSBoundParameters.ContainsKey('Search') -and $Search) {
        $s = $Search.ToLowerInvariant()
        $filtered = @($filtered | Where-Object {
            $_.path.ToLowerInvariant().Contains($s) -or
            $_.synopsis.ToLowerInvariant().Contains($s) -or
            $_.category.ToLowerInvariant().Contains($s)
        })
    }
    if ($PSBoundParameters.ContainsKey('Category') -and $Category) {
        $c = $Category.ToLowerInvariant()
        $filtered = @($filtered | Where-Object { $_.category.ToLowerInvariant().Contains($c) })
    }
    if ($Interactive) {
        $hasGrid = Get-Command Out-GridView -ErrorAction SilentlyContinue
        if (-not $hasGrid) {
            $i = 0
            foreach ($entry in $filtered) {
                $i++
                Write-Host ("[{0}] {1} - {2}" -f $i, $entry.path, $entry.synopsis)
            }
            if ($i -eq 0) { return @() }
            $choice = Read-Host "Select [1-$i] or press Enter to cancel"
            if ([string]::IsNullOrWhiteSpace($choice)) { return @() }
            $idx = 0
            if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $filtered.Count) {
                return @($filtered[$idx - 1])
            }
            return @()
        }
        else {
            try {
                $selected = $filtered | Out-GridView -Title 'Select script(s)' -PassThru -ErrorAction Stop
                if (-not $selected) { return @() }
                return @($selected)
            }
            catch {
                Write-Verbose "Out-GridView failed, returning filtered list without prompt: $($_.Exception.Message)"
                return @($filtered)
            }
        }
    }
    Write-Verbose "[Get-BUScript] catalog v$($catalog.version) total=$($catalog.totalScripts) filtered=$($filtered.Count)"
    return @($filtered)
}
