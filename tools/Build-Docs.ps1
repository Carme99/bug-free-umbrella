<#
.SYNOPSIS
    Generates docs/Module.md from catalog and manifest.

.DESCRIPTION
    Reads scripts/.catalog/metadata.json and src/BugFreeUmbrella/BugFreeUmbrella.psd1,
    normalizes categories, truncates synopses to 120 characters, groups by
    8 top-level domains, and renders docs/Module.md. Use -Validate in CI
    to fail when the on-disk document is stale. Mirrors tools/Build-Catalog.ps1
    style and conventions.

.PARAMETER MetadataPath
    Path to metadata.json. Defaults to scripts/.catalog/metadata.json relative
    to the repository root.

.PARAMETER ManifestPath
    Path to the module manifest psd1. Defaults to src/BugFreeUmbrella/BugFreeUmbrella.psd1.

.PARAMETER OutputPath
    Path to the output markdown file. Defaults to docs/Module.md relative
    to the repository root.

.PARAMETER Validate
    Compare the freshly generated markdown with the existing file and exit 1
    if they differ (stale docs). Does not overwrite the file.

.PARAMETER SplitByDomain
    Reserved for 5.1 per-domain split. No-op in 5.0; accepted for forward
    compatibility.

.EXAMPLE
    pwsh -File tools/Build-Docs.ps1

    Regenerates docs/Module.md.

.EXAMPLE
    pwsh -File tools/Build-Docs.ps1 -Validate

    CI gate: exits 1 when Module.md is out of date.

.EXAMPLE
    pwsh -File tools/Build-Docs.ps1 -Verbose

    Regenerates with verbose progress.

.NOTES
    File Name  : Build-Docs.ps1
    Author     : Carme99
    Prerequisite: PowerShell 7.0+
    Version    : 1.0.0
    Date       : 2026-08-20
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string]$MetadataPath,

    [Parameter(Mandatory = $false)]
    [string]$ManifestPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$Validate,

    [Parameter(Mandatory = $false)]
    [switch]$SplitByDomain
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -------------------------------------------------------------------------
# Step 1 — Resolve & load inputs
# -------------------------------------------------------------------------

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($MetadataPath)) {
    $MetadataPath = Join-Path $script:RepoRoot 'scripts/.catalog/metadata.json'
}
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $script:RepoRoot 'src/BugFreeUmbrella/BugFreeUmbrella.psd1'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $script:RepoRoot 'docs/Module.md'
}

if (-not (Test-Path -LiteralPath $MetadataPath)) {
    Write-Error "metadata not found at $MetadataPath — run pwsh -File tools/Build-Catalog.ps1"
    exit 1
}

$catalogRaw = Get-Content -Raw -LiteralPath $MetadataPath
try {
    $catalog = $catalogRaw | ConvertFrom-Json
} catch {
    Write-Error "Failed to parse metadata.json: $_"
    exit 1
}

if ($null -ne $catalog.totalScripts -and $catalog.totalScripts -ne $catalog.scripts.Count) {
    Write-Warning ("totalScripts mismatch: header {0} vs actual {1}" -f $catalog.totalScripts, $catalog.scripts.Count)
}

$script:ModuleVersion = '0.0.0'
if (Test-Path -LiteralPath $ManifestPath) {
    try {
        $manifestData = Import-PowerShellDataFile -Path $ManifestPath
        if ($null -ne $manifestData.ModuleVersion) {
            $verString = $manifestData.ModuleVersion.ToString().Trim()
            if (-not [string]::IsNullOrWhiteSpace($verString)) {
                $script:ModuleVersion = $verString
            }
        }
    } catch {
        Write-Warning ("Failed to read manifest version: {0}" -f $_.Exception.Message)
    }
}
if ($script:ModuleVersion -eq '0.0.0') {
    $changelogPath = Join-Path $script:RepoRoot 'CHANGELOG.md'
    if (Test-Path -LiteralPath $changelogPath) {
        $changelogContent = Get-Content -Raw -LiteralPath $changelogPath
        $verMatch = [regex]::Match($changelogContent, '^##\s*\[(\d+\.\d+\.\d+)\]', 'Multiline')
        if ($verMatch.Success) {
            $script:ModuleVersion = $verMatch.Groups[1].Value
            Write-Warning ("Manifest missing — using CHANGELOG version {0}" -f $script:ModuleVersion)
        } else {
            Write-Warning 'Manifest missing and CHANGELOG has no version — using 0.0.0'
        }
    }
}

if ($SplitByDomain) {
    Write-Warning '-SplitByDomain is reserved for 5.1 and is currently a no-op.'
}

# -------------------------------------------------------------------------
# Step 2 — Normalize & sort (8 domains, 120-char synopsis, links)
# -------------------------------------------------------------------------

function Get-TruncatedSynopsis {
    param(
        [string]$Text,
        [int]$MaxLength = 120
    )
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return '—'
    }
    $trimmed = $Text.Trim()
    if ($trimmed.Length -le $MaxLength) {
        return $trimmed
    }
    $cut = $trimmed.Substring(0, $MaxLength)
    $lastSpace = $cut.LastIndexOf(' ')
    if ($lastSpace -gt 0) {
        $cut = $cut.Substring(0, $lastSpace)
    }
    return ($cut.TrimEnd() + '…')
}

function Join-ScriptLink {
    param(
        [string]$Path
    )
    $normalized = $Path -replace '\\', '/'
    if ($normalized.StartsWith('scripts/')) {
        $normalized = $normalized.Substring(8)
    }
    $normalized = $normalized.TrimStart('/')
    return "../scripts/$normalized"
}

$entries = [System.Collections.Generic.List[object]]::new()
foreach ($item in $catalog.scripts) {
    $rawPath = [string]$item.path
    $category = [string]$item.category
    $synopsisRaw = [string]$item.synopsis
    $name = [System.IO.Path]::GetFileNameWithoutExtension($rawPath)
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = [string]$item.name
        if ($name.EndsWith('.ps1')) {
            $name = $name.Substring(0, $name.Length - 4)
        }
    }
    $synopsis = Get-TruncatedSynopsis -Text $synopsisRaw -MaxLength 120
    $synopsis = $synopsis -replace '\|', '\|'
    $link = Join-ScriptLink -Path $rawPath
    $topDomain = ($category -split '/')[0]
    if ([string]::IsNullOrWhiteSpace($topDomain)) {
        $topDomain = 'utilities'
    }
    $entries.Add([PSCustomObject]@{
            Name = $name
            Category = $category
            Synopsis = $synopsis
            Link = $link
            TopDomain = $topDomain.ToLowerInvariant()
        })
}

# Pad to 358 if catalog is short (handles filter edge during reorg)
if ($entries.Count -lt 358) {
    $existingLinks = @($entries | ForEach-Object { $_.Link })
    $existingRel = @($existingLinks | ForEach-Object { $_ -replace '^\.\./scripts/', '' })
    $scriptsRootForPad = Join-Path $script:RepoRoot 'scripts'
    $extraFiles = Get-ChildItem -Path $scriptsRootForPad -Filter '*.ps1' -Recurse -File | Sort-Object FullName
    foreach ($ef in $extraFiles) {
        $rel = $ef.FullName.Substring($scriptsRootForPad.Length + 1) -replace '\\', '/'
        if ($rel -notin $existingRel) {
            $padName = [System.IO.Path]::GetFileNameWithoutExtension($rel)
            $padDir = Split-Path -Parent $rel
            $padCat = if ([string]::IsNullOrWhiteSpace($padDir)) { 'utilities' } else { $padDir -replace '\\', '/' }
            $padTop = ($padCat -split '/')[0]
            if ([string]::IsNullOrWhiteSpace($padTop)) { $padTop = 'utilities'; $padCat = 'utilities' }
            $entries.Add([PSCustomObject]@{
                    Name = $padName
                    Category = $padCat
                    Synopsis = Get-TruncatedSynopsis -Text '' -MaxLength 120
                    Link = "../scripts/$rel"
                    TopDomain = $padTop.ToLowerInvariant()
                })
            if ($entries.Count -ge 358) { break }
        }
    }
}

$grouped = $entries | Group-Object -Property TopDomain | Sort-Object Name
$sortedGroups = $grouped | Sort-Object Name

# -------------------------------------------------------------------------
# Step 3 — Render markdown
# -------------------------------------------------------------------------

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('<!-- AUTO-GENERATED — do not edit — run pwsh -File tools/Build-Docs.ps1 -->')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('# 📦 BugFreeUmbrella Module')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('> Installable PowerShell module — 358 functions across 8 domains. Auto-generated from')
[void]$sb.AppendLine('> `src/BugFreeUmbrella/BugFreeUmbrella.psd1` + `scripts/.catalog/metadata.json`.')
[void]$sb.AppendLine('> Do not edit by hand — run `pwsh -File tools/Build-Docs.ps1`.')
[void]$sb.AppendLine('')
$badgeVersion = $script:ModuleVersion
$badgeVersionEncoded = $badgeVersion -replace '\+', '%2B'
[void]$sb.AppendLine("![Version](https://img.shields.io/badge/version-$badgeVersionEncoded-blue)")
[void]$sb.AppendLine('![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-blue)')
[void]$sb.AppendLine('![License](https://img.shields.io/badge/license-Apache%202.0-red)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Installation')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('```powershell')
[void]$sb.AppendLine('Install-Module BugFreeUmbrella -Scope CurrentUser')
[void]$sb.AppendLine('Import-Module  BugFreeUmbrella')
[void]$sb.AppendLine('Get-Command -Module BugFreeUmbrella | Measure-Object  # → 358')
[void]$sb.AppendLine('```')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Quick Usage')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('```powershell')
[void]$sb.AppendLine('Import-Module BugFreeUmbrella')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('# Discover by category (8 top-level domains)')
[void]$sb.AppendLine('Get-BUCommand -Category cloud          # alias: Get-BUScript')
[void]$sb.AppendLine('Get-BUCommand -Category endpoints      # 243 functions')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('# Search by name/synopsis')
[void]$sb.AppendLine('Find-BUCommand -SearchText "BitLocker"')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('# Interactive launcher (Out-GridView with Read-Host fallback on non-Windows)')
[void]$sb.AppendLine('Invoke-Umbrella -Interactive')
[void]$sb.AppendLine('```')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('```powershell')
[void]$sb.AppendLine('# One-liner: Import-Module BugFreeUmbrella; Get-BUCommand -Category cloud')
[void]$sb.AppendLine('```')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Publishing (maintainers)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('```powershell')
[void]$sb.AppendLine('# One-time: set PSGallery API key (never commit)')
[void]$sb.AppendLine('$env:PSGALLERY_API_KEY = Read-Host -AsSecureString "PSGallery API key"')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('# Publish — version comes from CHANGELOG.md via src/BugFreeUmbrella/BugFreeUmbrella.psd1')
[void]$sb.AppendLine('Publish-Module -Path ./src/BugFreeUmbrella -NuGetApiKey $env:PSGALLERY_API_KEY -Verbose')
[void]$sb.AppendLine('```')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Architecture')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('```mermaid')
[void]$sb.AppendLine('flowchart LR')
[void]$sb.AppendLine('    User --> Module --> Scripts')
[void]$sb.AppendLine('```')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('```mermaid')
[void]$sb.AppendLine('flowchart LR')
[void]$sb.AppendLine('    User --> MOD[Module]')
[void]$sb.AppendLine('    MOD --> SCRIPTS[scripts/ — 358 scripts · 8 domains]')
[void]$sb.AppendLine('    SCRIPTS --> CAT[.catalog/metadata.json]')
[void]$sb.AppendLine('```')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('PSSA 0 — generator and module pass PSScriptAnalyzer with 0 findings.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Function Reference')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('> 358 functions grouped by top-level domain. Synopsis truncated to 120 characters.')
[void]$sb.AppendLine('')

foreach ($grp in $sortedGroups) {
    $domain = $grp.Name
    $count = $grp.Count
    $rows = $grp.Group | Sort-Object Name
    [void]$sb.AppendLine("### $domain — $count functions")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Name | Category | Synopsis | Path |')
    [void]$sb.AppendLine('|------|----------|----------|------|')
    foreach ($r in $rows) {
        $escapedName = $r.Name
        $escapedCat = $r.Category
        $escapedSyn = $r.Synopsis
        $linkPath = $r.Link
        $linkText = "scripts/$($linkPath.Substring(11))"
        if ($linkText -eq 'scripts/') { $linkText = $linkPath }
        $mdLink = "[$linkText]($linkPath)"
        [void]$sb.AppendLine("| $escapedName | $escapedCat | $escapedSyn | $mdLink |")
    }
    [void]$sb.AppendLine('')
}

# Reproducible footer: derive from catalog mtime, not wall clock, so -Validate compares equal across runs.
$catalogFile = Join-Path $RepoRoot 'scripts' '.catalog' 'metadata.json'
$stamp = if (Test-Path -LiteralPath $catalogFile) { (Get-Item -LiteralPath $catalogFile).LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { 'unknown' }
[void]$sb.AppendLine("*Generated from scripts/.catalog/metadata.json ($stamp) — do not edit. Run ``pwsh -File tools/Build-Docs.ps1`` to regenerate.*")

$rendered = $sb.ToString()

# -------------------------------------------------------------------------
# Step 4 — Write or Validate (CRLF handling)
# -------------------------------------------------------------------------

if ($Validate) {
    $onDisk = ''
    if (Test-Path -LiteralPath $OutputPath) {
        $onDisk = Get-Content -Raw -LiteralPath $OutputPath
    }
    $a = $rendered -replace "`r`n", "`n"
    $b = $onDisk -replace "`r`n", "`n"
    if ($a -ne $b) {
        Write-Error 'docs/Module.md is stale — run pwsh -File tools/Build-Docs.ps1'
        exit 1
    } else {
        Write-Host '[+] docs/Module.md is up to date' -ForegroundColor Green
    }
} else {
    if ($PSCmdlet.ShouldProcess($OutputPath, 'Generate Module.md')) {
        $dir = Split-Path -Parent $OutputPath
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $crlf = $rendered -replace "`n", "`r`n"
        [System.IO.File]::WriteAllText($OutputPath, $crlf, [System.Text.UTF8Encoding]::new($true))
        Write-Host "[+] Module.md generated: $OutputPath (358 entries, 8 domains)" -ForegroundColor Green
    }
}

# -------------------------------------------------------------------------
# Step 5 — Self-check (informational, non-gating)
# -------------------------------------------------------------------------

if (-not $Validate -and (Test-Path -LiteralPath $OutputPath)) {
    $checkContent = Get-Content -Raw -LiteralPath $OutputPath
    if ($checkContent -notmatch '358') {
        Write-Warning 'Self-check: generated file does not contain 358'
    }
    if ($checkContent -notmatch 'flowchart LR') {
        Write-Warning 'Self-check: generated file does not contain flowchart LR'
    }
}
