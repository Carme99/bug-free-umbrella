<#
.SYNOPSIS
    Generates scripts/.catalog/metadata.json by scanning all scripts.

.DESCRIPTION
    Scans scripts/**/*.ps1, parses each file with the PowerShell parser,
    extracts comment-based help (.SYNOPSIS / .DESCRIPTION), CmdletBinding
    presence, parameter metadata, exported functions and #Requires modules.
    Derives category from the relative path and tags from synopsis keywords.
    Writes a sorted, pretty-printed JSON catalog to
    scripts/.catalog/metadata.json.

    Use -Validate in CI to fail when the on-disk catalog is stale.
    Use -Verbose for per-file progress.

.PARAMETER Validate
    Compare the freshly generated catalog with the existing metadata.json
    and exit 1 if they differ (stale catalog). Does not overwrite the file.

.PARAMETER OutputPath
    Override output path. Defaults to scripts/.catalog/metadata.json
    relative to the repository root.

.EXAMPLE
    pwsh -File tools/Build-Catalog.ps1

    Regenerates the catalog.

.EXAMPLE
    pwsh -File tools/Build-Catalog.ps1 -Validate

    CI gate: exits 1 when the catalog is out of date.

.EXAMPLE
    pwsh -File tools/Build-Catalog.ps1 -Verbose

    Regenerates with per-file progress output.

.NOTES
    File Name  : Build-Catalog.ps1
    Author     : Carme99
    Prerequisite: PowerShell 7.0+
    Version    : 1.0.0
    Date       : 2026-08-20
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Validate,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve repo root (parent of tools/)
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $script:RepoRoot 'scripts/.catalog/metadata.json'
}

$scriptsRoot = Join-Path $script:RepoRoot 'scripts'

if (-not (Test-Path -LiteralPath $scriptsRoot)) {
    Write-Error "Scripts root not found: $scriptsRoot"
    exit 1
}

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

function Get-SynopsisAndDescription {
    param([string]$Content)

    $synopsis = ''
    $description = ''

    # Extract .SYNOPSIS block
    $synMatch = [regex]::Match(
        $Content,
        '(?im)^\s*\.SYNOPSIS\s*\r?\n(.*?)(?=^\s*\.(DESCRIPTION|PARAMETER|EXAMPLE|NOTES|INPUTS|OUTPUTS|LINK|COMPONENT|ROLE|FUNCTIONALITY|FORWARDHELPTARGETNAME|FORWARDHELPCATEGORY|REMOTEHELPRUNSPACE|EXTERNALHELP)\b|\#\>|\Z)',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if ($synMatch.Success) {
        $synopsis = ($synMatch.Groups[1].Value -replace '\r', '' -split '\n' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }) -join ' '
        $synopsis = $synopsis.Trim()
    }

    # Extract .DESCRIPTION block (first 200 chars for JSON)
    $descMatch = [regex]::Match(
        $Content,
        '(?im)^\s*\.DESCRIPTION\s*\r?\n(.*?)(?=^\s*\.(PARAMETER|EXAMPLE|NOTES|INPUTS|OUTPUTS|LINK|COMPONENT|ROLE|FUNCTIONALITY|FORWARDHELPTARGETNAME|FORWARDHELPCATEGORY|REMOTEHELPRUNSPACE|EXTERNALHELP|SYNOPSIS)\b|\#\>|\Z)',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if ($descMatch.Success) {
        $rawDesc = ($descMatch.Groups[1].Value -replace '\r', '' -split '\n' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }) -join ' '
        $rawDesc = $rawDesc.Trim()
        if ($rawDesc.Length -gt 200) {
            $description = $rawDesc.Substring(0, 200).Trim()
        } else {
            $description = $rawDesc
        }
    }

    # Fallback: if no SYNOPSIS, use first comment line
    if ([string]::IsNullOrWhiteSpace($synopsis)) {
        $firstComment = [regex]::Match($Content, '<#\s*\r?\n\s*(.+)')
        if ($firstComment.Success) {
            $candidate = $firstComment.Groups[1].Value.Trim() -replace '^[\s#]+', ''
            if ($candidate.Length -gt 5 -and $candidate.Length -lt 200) {
                $synopsis = $candidate
            }
        }
    }

    # Final fallback: derive from filename
    if ([string]::IsNullOrWhiteSpace($synopsis)) {
        $synopsis = 'No synopsis available.'
    }

    return @{ Synopsis = $synopsis; Description = $description }
}

function Get-CategoryFromPath {
    param([string]$RelativePath)
    # Category is the directory portion without the filename
    $dir = Split-Path -Parent $RelativePath
    if ([string]::IsNullOrWhiteSpace($dir)) { return 'root' }
    # Normalise to forward slashes
    return ($dir -replace '\\', '/')
}

function Get-TagsFromSynopsis {
    param([string]$Synopsis)
    $keywords = @(
        'intune', 'azure', 'exchange', 'teams', 'sharepoint', 'onedrive',
        'defender', 'security', 'compliance', 'backup', 'monitoring',
        'active-directory', 'group-policy', 'winget', 'device', 'compliance',
        'health', 'report', 'audit', 'migration', 'database', 'api',
        'docker', 'kubernetes', 'automation', 'network', 'certificate'
    )
    $lower = $Synopsis.ToLowerInvariant()
    $tags = @()
    foreach ($kw in $keywords) {
        if ($lower.Contains($kw)) { $tags += $kw }
    }
    return @($tags | Select-Object -Unique)
}

# -------------------------------------------------------------------------
# Scan
# -------------------------------------------------------------------------

$psFiles = Get-ChildItem -Path $scriptsRoot -Filter '*.ps1' -Recurse -File |
    Where-Object { $_.FullName -notmatch '/devices/(winget|proactive-remediations)/' } |
    Where-Object { $_.Name -notlike '*.Tests.ps1' } |
    Sort-Object FullName

$entries = [System.Collections.Generic.List[object]]::new()
$withoutSynopsis = 0

foreach ($file in $psFiles) {
    $relativePath = [System.IO.Path]::GetRelativePath($script:RepoRoot, $file.FullName) -replace '\\', '/'
    $relativePath = $relativePath -replace '^scripts/', ''
    $rawContent = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8

    # Parse with AST
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$tokens, [ref]$errors
    )

    # Help
    $helpInfo = Get-SynopsisAndDescription -Content $rawContent
    if ($helpInfo.Synopsis -eq 'No synopsis available.') { $withoutSynopsis++ }

    # CmdletBinding
    $hasCmdletBinding = $false
    if ($null -ne $ast) {
        $hasCmdletBinding = $null -ne ($ast.FindAll(
            { param($n) $n -is [System.Management.Automation.Language.AttributeAst] -and $n.TypeName.Name -eq 'CmdletBinding' },
            $true
        ) | Select-Object -First 1)
    }
    # Fallback regex check
    if (-not $hasCmdletBinding) {
        $hasCmdletBinding = $rawContent -match '\[CmdletBinding\s*\(?\]'
    }

    # Parameters
    $paramList = @()
    if ($null -ne $ast -and $null -ne $ast.ParamBlock) {
        foreach ($p in $ast.ParamBlock.Parameters) {
            $pName = $p.Name.VariablePath.UserPath
            $pType = 'object'
            if ($null -ne $p.StaticType -and $p.StaticType.Name -ne 'Object') {
                $pType = $p.StaticType.Name
            } elseif ($p.Attributes) {
                foreach ($attr in $p.Attributes) {
                    $tn = $attr.TypeName.Name
                    if ($tn -and $tn -notin @('Parameter', 'ValidateSet', 'ValidatePattern', 'ValidateRange', 'ValidateNotNullOrEmpty')) {
                        $pType = $tn
                        break
                    }
                }
            }
            $isMandatory = $false
            foreach ($attr in $p.Attributes) {
                if ($attr.TypeName.Name -eq 'Parameter') {
                    foreach ($named in $attr.NamedArguments) {
                        if ($named.ArgumentName -eq 'Mandatory' -and $named.Argument) {
                            $val = $named.Argument.Extent.Text
                            if ($val -match 'true|\$true') { $isMandatory = $true }
                        }
                    }
                }
            }
            $paramList += [ordered]@{
                name      = $pName
                type      = $pType
                mandatory = $isMandatory
            }
        }
    }
    # Also check function param blocks
    if ($paramList.Count -eq 0 -and $null -ne $ast) {
        $funcAsts = $ast.FindAll(
            { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true
        )
        foreach ($f in $funcAsts) {
            if ($null -ne $f.Body.ParamBlock) {
                foreach ($p in $f.Body.ParamBlock.Parameters) {
                    $pName = $p.Name.VariablePath.UserPath
                    $pType = 'object'
                    if ($null -ne $p.StaticType -and $p.StaticType.Name -ne 'Object') {
                        $pType = $p.StaticType.Name
                    }
                    $isMandatory = $false
                    foreach ($attr in $p.Attributes) {
                        if ($attr.TypeName.Name -eq 'Parameter') {
                            foreach ($named in $attr.NamedArguments) {
                                if ($named.ArgumentName -eq 'Mandatory' -and $named.Argument) {
                                    $val = $named.Argument.Extent.Text
                                    if ($val -match 'true|\$true') { $isMandatory = $true }
                                }
                            }
                        }
                    }
                    $paramList += [ordered]@{
                        name      = $pName
                        type      = $pType
                        mandatory = $isMandatory
                    }
                }
            }
        }
    }

    # Functions exported (top-level function definitions)
    $functionsExported = @()
    if ($null -ne $ast) {
        $funcDefs = $ast.FindAll(
            { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true
        )
        foreach ($fd in $funcDefs) {
            $functionsExported += $fd.Name
        }
    }

    # Requires modules
    $requiresModules = @()
    $reqMatches = [regex]::Matches($rawContent, '(?im)^\s*#Requires\s+-Modules?\s+(.+)$')
    foreach ($m in $reqMatches) {
        $modLine = $m.Groups[1].Value.Trim()
        # Split by comma
        $mods = $modLine -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ -ne '' }
        foreach ($mod in $mods) {
            # Handle "ModuleName -Version x" etc — take first token
            $modName = ($mod -split '\s+')[0].Trim()
            if ($modName) { $requiresModules += $modName }
        }
    }
    $requiresModules = @($requiresModules | Select-Object -Unique)

    $category = Get-CategoryFromPath -RelativePath $relativePath
    $tags = Get-TagsFromSynopsis -Synopsis $helpInfo.Synopsis

    $entry = [ordered]@{
        path              = $relativePath
        name              = $file.Name
        category          = $category
        synopsis          = $helpInfo.Synopsis
        description       = $helpInfo.Description
        tags              = @($tags)
        parameters        = @($paramList)
        hasCmdletBinding  = [bool]$hasCmdletBinding
        requiresModules   = @($requiresModules)
        functionsExported = @($functionsExported)
    }

    $entries.Add($entry)

    if ($VerbosePreference -eq 'Continue') {
        Write-Verbose "Scanned: $relativePath"
    }
}

# Sort by path
$sortedEntries = $entries | Sort-Object { $_['path'] }

$catalog = [ordered]@{
    '$schema'     = 'https://raw.githubusercontent.com/Carme99/bug-free-umbrella/main/scripts/.catalog/metadata.schema.json'
    version       = '1.0.0'
    generated     = (Get-Date).ToString('o')
    totalScripts  = $sortedEntries.Count
    scripts       = @($sortedEntries)
}

$json = ($catalog | ConvertTo-Json -Depth 6) -replace "`r`n", "`n"

# -------------------------------------------------------------------------
# Validate mode
# -------------------------------------------------------------------------

if ($Validate) {
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        Write-Host '[-] Catalog missing: run tools/Build-Catalog.ps1 to generate it.' -ForegroundColor Red
        exit 1
    }
    $existing = Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8
    # Normalise: compare canonical JSON (re-parse and re-serialize to ignore whitespace)
    # For Validate we compare totalScripts and the scripts array structurally;
    # generated timestamp is ignored.
    try {
        $existingObj = $existing | ConvertFrom-Json
        $freshObj = $json | ConvertFrom-Json
    } catch {
        Write-Host '[-] Existing catalog is not valid JSON.' -ForegroundColor Red
        exit 1
    }

    $stale = $false
    if ($existingObj.totalScripts -ne $freshObj.totalScripts) {
        $stale = $true
    } else {
        $existingJson = ($existingObj.scripts | ConvertTo-Json -Depth 6 -Compress)
        $freshJson = ($freshObj.scripts | ConvertTo-Json -Depth 6 -Compress)
        if ($existingJson -ne $freshJson) {
            $stale = $true
        }
    }

    if ($stale) {
        Write-Host '[-] Catalog is stale: run tools/Build-Catalog.ps1 to regenerate.' -ForegroundColor Red
        Write-Host ("    Expected totalScripts={0}, found {1}" -f $freshObj.totalScripts, $existingObj.totalScripts) -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host '[+] Catalog is up to date.' -ForegroundColor Green
        Write-Host ("    totalScripts={0}" -f $freshObj.totalScripts) -ForegroundColor Cyan
        exit 0
    }
}

# -------------------------------------------------------------------------
# Write
# -------------------------------------------------------------------------

$outDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

# Byte-deterministic across platforms: UTF-8 without BOM, LF newlines only
# (ConvertTo-Json/[Environment]::NewLine would emit CRLF on Windows).
[System.IO.File]::WriteAllText($OutputPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))

Write-Host "[+] Catalog generated: $OutputPath" -ForegroundColor Green
Write-Host ("    totalScripts={0}  withoutSynopsis={1}" -f $sortedEntries.Count, $withoutSynopsis) -ForegroundColor Cyan
if ($withoutSynopsis -gt 0) {
    $pct = [math]::Round((($sortedEntries.Count - $withoutSynopsis) / $sortedEntries.Count) * 100, 1)
    Write-Host ("    synopsis coverage: {0}% ({1}/{2})" -f $pct, ($sortedEntries.Count - $withoutSynopsis), $sortedEntries.Count) -ForegroundColor Cyan
}
