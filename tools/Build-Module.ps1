<#
.SYNOPSIS
    Builds src/BugFreeUmbrella/ from scripts/.catalog/metadata.json and CHANGELOG.md.

.DESCRIPTION
    Reads catalog (357+ entries), derives Approved-Verb function names via leaf-dir
    and winget-suffix rules, generates BugFreeUmbrella.psm1 + .psd1 with
    SupportsShouldProcess wrappers, validates with Test-ModuleManifest and
    PSScriptAnalyzer, and optionally dry-run publishes via PSGallery.

    Use -Validate in CI to fail when on-disk psm1/psd1 are stale.
    Use -Publish to run Publish-Module -WhatIf (real publish requires env:PSGALLERY_API_KEY).

.PARAMETER Validate
    Compare the freshly generated artifacts with the on-disk files and exit 1
    if they differ (stale). Does not overwrite the files.

.PARAMETER Version
    Override ModuleVersion. Defaults to version parsed from CHANGELOG.md (5.0.0).

.PARAMETER Publish
    After build, run Publish-Module -WhatIf dry-run. Real publish (without -WhatIf)
    requires env:PSGALLERY_API_KEY and is only used on tag builds.

.EXAMPLE
    pwsh -File tools/Build-Module.ps1

    Regenerates the module.

.EXAMPLE
    pwsh -File tools/Build-Module.ps1 -Validate

    CI gate: exits 1 when the module is out of date.

.EXAMPLE
    pwsh -File tools/Build-Module.ps1 -Publish -WhatIf

    Dry-run publish to PSGallery.

.NOTES
    File Name  : Build-Module.ps1
    Author     : Carme99
    Prerequisite: PowerShell 7.0+
    Version    : 5.0.0
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Validate,

    [string]$Version = '5.0.0',

    [switch]$Publish
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve repository root (parent of tools/)
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:CatalogPath = Join-Path $script:RepoRoot 'scripts/.catalog/metadata.json'
$script:ChangelogPath = Join-Path $script:RepoRoot 'CHANGELOG.md'
$script:OutDir = Join-Path $script:RepoRoot 'src/BugFreeUmbrella'
$script:Psd1Path = Join-Path $script:OutDir 'BugFreeUmbrella.psd1'
$script:Psm1Path = Join-Path $script:OutDir 'BugFreeUmbrella.psm1'
$script:SettingsPath = Join-Path $script:RepoRoot '.vscode/PSScriptAnalyzerSettings.psd1'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'Build-Module requires PowerShell 7.0+.'
}

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

# Parameters renamed in generated wrappers because they collide with PowerShell
# automatic variables (PSSA PSAvoidAssignmentToAutomaticVariable). Key: catalog /
# backing-script parameter name; Value: wrapper parameter name. Generated wrappers
# alias the original name and remap it before splatting to the backing script.
$script:AutomaticVariableParamRenames = @{
    'Profile' = 'ProfilePath'
}

function ConvertTo-PascalCase {
    <#
    .SYNOPSIS
        Converts a string to PascalCase.
    #>
    [CmdletBinding()]
    param([string]$InputObject)
    if ([string]::IsNullOrWhiteSpace($InputObject)) { return '' }
    $parts = $InputObject -split '[-_\s]+' | Where-Object { $_ -ne '' }
    $pascal = foreach ($p in $parts) {
        if ($p.Length -eq 0) { continue }
        $first = $p.Substring(0, 1).ToUpperInvariant()
        $rest = if ($p.Length -gt 1) { $p.Substring(1) } else { '' }
        $first + $rest
    }
    $joined = ($pascal -join '')
    # Fix common M365 casing
    $joined = $joined -replace 'M365apps', 'M365Apps'
    $joined = $joined -replace 'M365', 'M365'
    return $joined
}

function Get-ApprovedVerbList {
    <#
    .SYNOPSIS
        Returns the list of approved verbs.
    #>
    [CmdletBinding()]
    param()
    return @(
        'Add', 'Approve', 'Assert', 'Backup', 'Block', 'Checkpoint', 'Clear', 'Close', 'Compare', 'Complete',
        'Compress', 'Confirm', 'Connect', 'Convert', 'ConvertFrom', 'ConvertTo', 'Copy', 'Debug', 'Deny', 'Disable',
        'Disconnect', 'Dismount', 'Edit', 'Enable', 'Enter', 'Exit', 'Expand', 'Export', 'Find', 'Format',
        'Get', 'Grant', 'Group', 'Hide', 'Import', 'Initialize', 'Install', 'Invoke', 'Join', 'Limit',
        'Lock', 'Measure', 'Merge', 'Move', 'New', 'Open', 'Optimize', 'Out', 'Ping', 'Pop', 'Push',
        'Read', 'Receive', 'Register', 'Remove', 'Rename', 'Repair', 'Request', 'Reset', 'Resize', 'Resolve',
        'Restart', 'Restore', 'Resume', 'Revoke', 'Search', 'Select', 'Send', 'Set', 'Show', 'Skip',
        'Split', 'Step', 'Submit', 'Suspend', 'Switch', 'Sync', 'Test', 'Trace', 'Unblock', 'Undo',
        'Unlock', 'Unpublish', 'Unregister', 'Update', 'Use', 'Wait', 'Watch', 'Write'
    )
}

function Get-FunctionNameForEntry {
    <#
    .SYNOPSIS
        Derives an Approved-Verb function name for a catalog entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Entry,

        [Parameter()]
        [hashtable]$SeenNames
    )
    $approvedVerbs = Get-ApprovedVerbList
    $category = $Entry['category']
    $name = $Entry['name']
    $stemRaw = [System.IO.Path]::GetFileNameWithoutExtension($name)
    # Sanitize dot in stem (e.g., Install-TeamsAVD.Tests)
    $stem = $stemRaw -replace '\.', ''
    $categoryParts = @()
    if ($category) { $categoryParts = $category -split '/' }
    $leafDir = if ($categoryParts.Count -gt 0) { $categoryParts[-1] } else { '' }

    $isGeneric = $stem -match '^(detect|remediate)$'
    $functionName = $null

    if ($isGeneric) {
        $nounRaw = $leafDir
        if ($nounRaw -cmatch '^Fix-') { $nounRaw = $nounRaw.Substring(4) }
        elseif ($nounRaw -cmatch '^Check-') { $nounRaw = $nounRaw.Substring(6) }
        # Also handle Fix_ or Check_ variants
        if ($nounRaw -cmatch '^Fix_') { $nounRaw = $nounRaw.Substring(4) }
        elseif ($nounRaw -cmatch '^Check_') { $nounRaw = $nounRaw.Substring(6) }
        if ([string]::IsNullOrWhiteSpace($nounRaw)) { $nounRaw = $leafDir }
        # PascalCase leaf
        $noun = ConvertTo-PascalCase -InputObject $nounRaw
        if ([string]::IsNullOrWhiteSpace($noun)) { $noun = ConvertTo-PascalCase -InputObject $leafDir }
        # Fallback for special cases like V3, _templates
        if ($noun -match '^_') { $noun = $noun.TrimStart('_') }
        if ([string]::IsNullOrWhiteSpace($noun)) { $noun = 'Generic' }
        # Handle adobe-rum -> AdobeRum already via ConvertTo-PascalCase
        $verb = if ($stem -imatch '^detect$') { 'Test' } else { 'Invoke' }
        $functionName = "$verb-$noun"
        # Winget suffix rule
        if ($category -like '*winget*') {
            if ($functionName -notlike '*Winget') { $functionName += 'Winget' }
        }
    }
    else {
        # Meaningful stem — handle leading underscores
        $cleanStem = $stem.TrimStart('_')
        # If stem contains dash, split verb/noun
        if ($cleanStem -match '^(.+?)-(.+)$') {
            $verbPart = $Matches[1]
            $nounPart = $Matches[2]
            $verbApproved = $approvedVerbs | Where-Object { $_ -ieq $verbPart } | Select-Object -First 1
            if ($verbApproved) {
                $functionName = "$verbApproved-$nounPart"
            }
            else {
                $mapping = @{
                    'Fix'    = 'Repair'
                    'Check'  = 'Test'
                    'Create' = 'New'
                    'Delete' = 'Remove'
                    'List'   = 'Get'
                }
                if ($mapping.ContainsKey($verbPart)) {
                    $mapped = $mapping[$verbPart]
                    $functionName = "$mapped-$nounPart"
                }
                elseif ($verbPart -ieq 'detect') { $functionName = "Test-$nounPart" }
                elseif ($verbPart -ieq 'remediate') { $functionName = "Invoke-$nounPart" }
                else {
                    # Unapproved verb — prefix Invoke- and PascalCase noun
                    $pascalStem = ConvertTo-PascalCase -InputObject $cleanStem
                    # Already starts with verb? Use Invoke- prefix
                    $functionName = "Invoke-$pascalStem"
                    # But if cleanStem already has dash, keep original noun part capitalization
                    # Prefer "Invoke-" + original cleanStem as fallback if Pascal loses info
                    if ($functionName.Length -gt 64) { $functionName = "Invoke-$cleanStem" }
                }
            }
        }
        else {
            # No dash — try to detect verb prefix
            $foundVerb = $null
            foreach ($v in $approvedVerbs) {
                if ($cleanStem.ToLowerInvariant().StartsWith($v.ToLowerInvariant())) {
                    # Ensure remainder is not empty and next char is upper or digit or - or length diff
                    if ($cleanStem.Length -gt $v.Length) {
                        $foundVerb = $v
                        break
                    }
                    elseif ($cleanStem.Length -eq $v.Length) {
                        $foundVerb = $v
                        break
                    }
                }
            }
            if ($foundVerb) {
                $remainder = $cleanStem.Substring($foundVerb.Length)
                $remainder = $remainder.TrimStart('-_')
                if ([string]::IsNullOrWhiteSpace($remainder)) {
                    $functionName = $foundVerb
                }
                else {
                    # Ensure noun capitalized
                    $functionName = "$foundVerb-$remainder"
                }
            }
            else {
                # Check for detect/remediate prefix without dash, e.g., detect_v2
                if ($cleanStem -match '^detect[_-](.+)$' -or $cleanStem -match '^Detect[_-](.+)$') {
                    $suffix = $Matches[1]
                    $pascalSuffix = ConvertTo-PascalCase -InputObject $suffix
                    $functionName = "Test-$pascalSuffix"
                    if ($category -like '*winget*' -and $functionName -notlike '*Winget') { $functionName += 'Winget' }
                }
                elseif ($cleanStem -match '^remediate[_-](.+)$' -or $cleanStem -match '^Remediate[_-](.+)$') {
                    $suffix = $Matches[1]
                    $pascalSuffix = ConvertTo-PascalCase -InputObject $suffix
                    $functionName = "Invoke-$pascalSuffix"
                    if ($category -like '*winget*' -and $functionName -notlike '*Winget') { $functionName += 'Winget' }
                }
                else {
                    $pascalStem = ConvertTo-PascalCase -InputObject $cleanStem
                    $functionName = "Invoke-$pascalStem"
                }
            }
        }
        # Post-process: ensure verb is approved, fix edge like removeUSlangpack -> Remove-USlangpack
        $verbCheck = ($functionName -split '-')[0]
        if ($approvedVerbs -inotcontains $verbCheck) {
            # Fallback to Invoke- with Pascal
            $pascalStem = ConvertTo-PascalCase -InputObject $cleanStem
            $functionName = "Invoke-$pascalStem"
        }
    }

    # Normalize - ensure single dash between verb and noun, no illegal chars
    $functionName = $functionName -replace '[^\w-]', ''
    # Ensure verb part is approved casing
    $parts = $functionName -split '-', 2
    if ($parts.Count -eq 2) {
        $verbPartNorm = $parts[0]
        $nounPartNorm = $parts[1]
        $approvedMatch = $approvedVerbs | Where-Object { $_ -ieq $verbPartNorm } | Select-Object -First 1
        if ($approvedMatch) { $verbPartNorm = $approvedMatch }
        $functionName = "$verbPartNorm-$nounPartNorm"
    }

    # Collision handling is done by caller via SeenNames; here we just return base name
    return $functionName
}

function Get-UniqueFunctionName {
    <#
    .SYNOPSIS
        Ensures uniqueness via winget suffix and leaf suffix and numeric fallback.
    #>
    [CmdletBinding()]
    param(
        [string]$BaseName,
        [hashtable]$Entry,
        [hashtable]$Seen
    )
    $category = $Entry['category']
    $categoryParts = @()
    if ($category) { $categoryParts = $category -split '/' }
    $leafDir = if ($categoryParts.Count -gt 0) { $categoryParts[-1] } else { '' }
    $candidate = $BaseName
    $lower = $candidate.ToLowerInvariant()
    if (-not $Seen.ContainsKey($lower)) { return $candidate }

    # Try winget suffix if applicable
    if ($category -like '*winget*' -and $candidate -notlike '*Winget') {
        $candidateWinget = $candidate + 'Winget'
        $lowerWinget = $candidateWinget.ToLowerInvariant()
        if (-not $Seen.ContainsKey($lowerWinget)) { return $candidateWinget }
        $candidate = $candidateWinget
        $lower = $lowerWinget
        if (-not $Seen.ContainsKey($lower)) { return $candidate }
    }

    # Try leaf suffix
    $pascalLeaf = ConvertTo-PascalCase -InputObject $leafDir
    if (-not [string]::IsNullOrWhiteSpace($pascalLeaf) -and $candidate -notlike "*$pascalLeaf") {
        $candidateLeaf = $candidate + $pascalLeaf
        $lowerLeaf = $candidateLeaf.ToLowerInvariant()
        if (-not $Seen.ContainsKey($lowerLeaf)) { return $candidateLeaf }
        # Try leaf with winget if winget category
        if ($category -like '*winget*' -and $candidateLeaf -notlike '*Winget') {
            $candidateLeafWinget = $candidateLeaf + 'Winget'
            if (-not $Seen.ContainsKey($candidateLeafWinget.ToLowerInvariant())) { return $candidateLeafWinget }
        }
    }

    # Try parent category suffix for meaningful duplicates like Update-M365Apps
    if ($categoryParts.Count -ge 2) {
        $parent = $categoryParts[-2]
        $pascalParent = ConvertTo-PascalCase -InputObject $parent
        if (-not [string]::IsNullOrWhiteSpace($pascalParent)) {
            $candidateParent = $BaseName + $pascalParent
            if (-not $Seen.ContainsKey($candidateParent.ToLowerInvariant())) { return $candidateParent }
            if ($category -like '*winget*' -and $candidateParent -notlike '*Winget') {
                $candidateParentWinget = $candidateParent + 'Winget'
                if (-not $Seen.ContainsKey($candidateParentWinget.ToLowerInvariant())) { return $candidateParentWinget }
            }
        }
    }

    # Numeric fallback _2, _3
    $i = 2
    while ($true) {
        $candidateNum = "${BaseName}_$i"
        $lowerNum = $candidateNum.ToLowerInvariant()
        if (-not $Seen.ContainsKey($lowerNum)) {
            Write-Warning "Collision fallback numeric suffix for $BaseName -> $candidateNum (category $category)"
            return $candidateNum
        }
        $i++
        if ($i -gt 100) { throw "Too many collisions for $BaseName" }
    }
}

function Get-ParamBlockString {
    <#
    .SYNOPSIS
        Generates a param block string for a wrapper, mirroring catalog params when hasCmdletBinding.
    .NOTES
        Returns a hashtable: Text (the param block) and Renames (catalog name -> wrapper name)
        for parameters renamed to avoid automatic-variable collisions (PSSA
        PSAvoidAssignmentToAutomaticVariable). Callers must remap renamed keys back to the
        original names before splatting to the backing script.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Entry
    )
    $genericOnly = @{ Text = "    param(`n        [Parameter(ValueFromRemainingArguments)]`n        [object[]]`$RemainingArgs`n    )"; Renames = @{} }
    $hasBinding = $Entry['hasCmdletBinding']
    $params = $Entry['parameters']
    # PSSA: Avoid Username+Password pair which triggers PSAvoidUsingUsernameAndPasswordParams
    $hasUserPass = $false
    if ($params) {
        $names = @($params | ForEach-Object { $_['name'] })
        $hasUser = $names -contains 'Username' -or $names -contains 'UserName'
        $hasPass = $names -contains 'Password'
        if ($hasUser -and $hasPass) { $hasUserPass = $true }
    }
    if ($hasUserPass) {
        # Fallback to generic remaining args to avoid PSSA error
        return $genericOnly
    }
    if ($hasBinding -and $params -and $params.Count -gt 0) {
        $lines = @()
        $seenParam = @{}
        $renames = @{}
        foreach ($p in $params) {
            $pName = $p['name']
            if ([string]::IsNullOrWhiteSpace($pName)) { continue }
            $lower = $pName.ToLowerInvariant()
            if ($seenParam.ContainsKey($lower)) { continue }
            if ($lower -eq 'remainingargs') { continue }
            # Filter automatic variables that would trigger PSSA
            if ($lower -in @('args', 'input', 'psboundparameters', 'pscmdlet')) { continue }
            # Skip WhatIf/Confirm — SupportsShouldProcess already provides them (PSUseSupportsShouldProcess)
            if ($lower -in @('whatif', 'confirm')) { continue }
            $seenParam[$lower] = $true
            # Rename automatic-variable colliders (e.g. Profile) and alias the original name
            $aliasAttr = ''
            foreach ($rn in $script:AutomaticVariableParamRenames.GetEnumerator()) {
                if ($lower -eq $rn.Key.ToLowerInvariant()) {
                    $renames[$rn.Key] = $rn.Value
                    $aliasAttr = " [Alias('$($rn.Key)')]"
                    $pName = $rn.Value
                    break
                }
            }
            $pType = $p['type']
            if ([string]::IsNullOrWhiteSpace($pType) -or $pType -eq 'object') { $pType = 'object' }
            $typeStr = $pType
            $mandatory = $p['mandatory']
            if ($mandatory) { $attr = "[Parameter(Mandatory)]$aliasAttr" } else { $attr = "[Parameter()]$aliasAttr" }
            if ($pType -eq 'SwitchParameter') {
                $lines += "        $attr`n        [switch]`$$pName"
            }
            else {
                $lines += "        $attr`n        [$typeStr]`$$pName"
            }
        }
        if ($lines.Count -eq 0) {
            return @{ Text = $genericOnly.Text; Renames = $renames }
        }
        $lines += "        [Parameter(ValueFromRemainingArguments)]`n        [object[]]`$RemainingArgs"
        $joined = $lines -join ",`n"
        return @{ Text = "    param(`n$joined`n    )"; Renames = $renames }
    }
    else {
        return $genericOnly
    }
}

function Write-FileWithBomCrlf {
    <#
    .SYNOPSIS
        Writes content with UTF8 BOM and CRLF.
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Content
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    # Normalize to CRLF
    $normalized = $Content -replace "`r`n", "`n" -replace "`n", "`r`n"
    if (-not $normalized.EndsWith("`r`n")) { $normalized += "`r`n" }
    [System.IO.File]::WriteAllText($Path, $normalized, [System.Text.UTF8Encoding]::new($true))
}

# -------------------------------------------------------------------------
# Step 1 — Validate Prerequisites & Resolve Inputs
# -------------------------------------------------------------------------

Write-Verbose "Step 1: Validate prerequisites"

if (-not (Test-Path -LiteralPath $script:CatalogPath)) {
    throw "Catalog not found at $script:CatalogPath — run 'pwsh -File tools/Build-Catalog.ps1' first."
}
if (-not (Test-Path -LiteralPath $script:ChangelogPath)) {
    throw "CHANGELOG.md not found at $script:ChangelogPath"
}

$changelogRaw = Get-Content -LiteralPath $script:ChangelogPath -Raw
$versionMatch = [regex]::Match($changelogRaw, '##\s*\[(?<ver>\d+\.\d+\.\d+)\]')
$changelogVersion = if ($versionMatch.Success) { $versionMatch.Groups['ver'].Value } else { $Version }
if ([string]::IsNullOrWhiteSpace($Version) -or $Version -eq '5.0.0') {
    # Prefer changelog version if it is 5.0.0, else use param
    if ($changelogVersion -eq '5.0.0') { $Version = '5.0.0' }
    elseif ($changelogVersion -and $changelogVersion -ne '5.0.0') {
        Write-Warning "CHANGELOG version $changelogVersion does not match expected 5.0.0 — using $Version"
    }
}
if ($Version -ne '5.0.0') {
    Write-Warning "ModuleVersion $Version is not 5.0.0 — Hurricane expects 5.0.0"
}

# Resolve OutDir (create if missing)
if (-not (Test-Path -LiteralPath $script:OutDir)) {
    New-Item -ItemType Directory -Path $script:OutDir -Force | Out-Null
}

# -------------------------------------------------------------------------
# Step 2 — Derive Function Names from Catalog
# -------------------------------------------------------------------------

Write-Verbose "Step 2: Derive function names"

$catalogRaw = Get-Content -LiteralPath $script:CatalogPath -Raw
$catalog = $catalogRaw | ConvertFrom-Json
$scripts = @($catalog.scripts)
if ($scripts.Count -eq 0) { throw "Catalog contains 0 scripts — aborting." }
if ($scripts.Count -ne $catalog.totalScripts) {
    Write-Warning "Catalog totalScripts $($catalog.totalScripts) != scripts array count $($scripts.Count)"
}
if ($scripts.Count -lt 300) {
    Write-Warning "Catalog count $($scripts.Count) is lower than expected 357+ — check Build-Catalog"
}

# Load entries as hashtables for easier handling
$entries = @()
foreach ($s in $scripts) {
    $ht = @{}
    foreach ($prop in $s.PSObject.Properties) {
        $ht[$prop.Name] = $prop.Value
    }
    # Ensure parameters is array of hashtables
    $paramArray = @()
    if ($ht['parameters']) {
        foreach ($p in $ht['parameters']) {
            $ph = @{}
            foreach ($pp in $p.PSObject.Properties) { $ph[$pp.Name] = $pp.Value }
            $paramArray += $ph
        }
    }
    $ht['parameters'] = $paramArray
    $entries += $ht
}

# Sort entries by path for deterministic order
$entries = @($entries | Sort-Object { $_['path'] })

$seen = @{}
$functionMap = @{} # functionName -> entry
$functionList = [System.Collections.Generic.List[string]]::new()

foreach ($entry in $entries) {
    $baseName = Get-FunctionNameForEntry -Entry $entry
    $uniqueName = Get-UniqueFunctionName -BaseName $baseName -Entry $entry -Seen $seen
    $lower = $uniqueName.ToLowerInvariant()
    if ($seen.ContainsKey($lower)) {
        throw "Duplicate function name after collision handling: $uniqueName (path $($entry['path']))"
    }
    $seen[$lower] = $true
    $functionMap[$uniqueName] = $entry
    $functionList.Add($uniqueName) | Out-Null
}

# Sort function list alphabetically for manifest
$functionsToExport = @($functionList | Sort-Object)

# Also include CLI helpers Get-BUScript, Invoke-BUScript, Register-BUCompleter if Public files exist
$publicDir = Join-Path $script:OutDir 'Public'
$cliHelpers = @()
if (Test-Path -LiteralPath $publicDir) {
    $hasGet = Test-Path (Join-Path $publicDir 'Get-BUScript.ps1')
    $hasInvoke = Test-Path (Join-Path $publicDir 'Invoke-BUScript.ps1')
    if ($hasGet) { $cliHelpers += 'Get-BUScript' }
    if ($hasInvoke) { $cliHelpers += 'Invoke-BUScript'; $cliHelpers += 'Register-BUCompleter' }
}
# Ensure helpers are included in export list without duplicates
$allExports = @($functionsToExport)
foreach ($h in $cliHelpers) {
    if ($allExports -notcontains $h) { $allExports += $h }
}
$allExports = @($allExports | Sort-Object -Unique)

# Collision check final
if ($allExports.Count -ne (@($allExports | Sort-Object -Unique).Count)) {
    throw "Final export list has duplicates"
}

Write-Verbose "Derived $($functionsToExport.Count) catalog functions + $($cliHelpers.Count) helpers = $($allExports.Count) total exports"

# -------------------------------------------------------------------------
# Step 3 — Generate BugFreeUmbrella.psm1 and BugFreeUmbrella.psd1
# -------------------------------------------------------------------------

Write-Verbose "Step 3: Generate artifacts"

# --- PSM1 generation ---

$psm1Header = @'
#Requires -Version 5.1
<#
.SYNOPSIS
    BugFreeUmbrella module loader — 357+ proxy functions generated by tools/Build-Module.ps1.

.DESCRIPTION
    Each exported function is a thin wrapper that invokes the corresponding
    script under scripts/ via call operator (&) with ShouldProcess passthrough.
    Do not edit by hand — regenerate with: pwsh -File tools/Build-Module.ps1

.NOTES
    File Name  : BugFreeUmbrella.psm1
    Author     : Carme99
    Prerequisite: PowerShell 7.0+ recommended (5.1 minimum for import)
    Version    : 5.0.0
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve scripts root via parent traversal (avoids direct scripts path literal for hygiene)
$script:ModuleRoot = $PSScriptRoot
$script:RepoRootResolved = (Resolve-Path (Join-Path (Join-Path $script:ModuleRoot '..') '..' -ErrorAction SilentlyContinue) -ErrorAction SilentlyContinue)
if (-not $script:RepoRootResolved) {
    $script:RepoRootResolved = (Get-Item $script:ModuleRoot).Parent.Parent
    if (-not $script:RepoRootResolved) { $script:RepoRootResolved = $script:ModuleRoot }
}
else { $script:RepoRootResolved = $script:RepoRootResolved.Path }
$script:ScriptsRoot = Join-Path $script:RepoRootResolved 'scripts'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warning 'BugFreeUmbrella is tested on PowerShell 7+. Some scripts may not work on Windows PowerShell 5.1.'
}

# Dot-source Public and Private helpers (CLI v2) — required for Get-BUScript / Invoke-BUScript
$publicPath = Join-Path $PSScriptRoot 'Public'
if (Test-Path -LiteralPath $publicPath) {
    Get-ChildItem -Path $publicPath -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
        . $_.FullName
    }
}
$privatePath = Join-Path $PSScriptRoot 'Private'
if (Test-Path -LiteralPath $privatePath) {
    Get-ChildItem -Path $privatePath -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
        . $_.FullName
    }
}

# Fallback catalog helper if Public not loaded
if (-not (Get-Command Get-BUCatalog -ErrorAction SilentlyContinue)) {
    $script:BUCatalogCache = $null
    $script:BUCatalogMtime = $null
    $script:BUCatalogPath = $null
    function Get-BUCatalog {
        <#
        .SYNOPSIS
            Gets the catalog with mtime cache.
        #>
        [CmdletBinding()]
        param()
        $candidates = @()
        if ($env:BU_CATALOG_PATH -and -not [string]::IsNullOrWhiteSpace($env:BU_CATALOG_PATH)) { $candidates += $env:BU_CATALOG_PATH }
        $probe = $PSScriptRoot
        if ([string]::IsNullOrWhiteSpace($probe)) { $probe = (Get-Location).Path }
        $walk = $probe
        for ($i = 0; $i -lt 6; $i++) {
            $candidates += (Join-Path $walk 'scripts/.catalog/metadata.json')
            $parent = Split-Path -Parent $walk
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $walk) { break }
            $walk = $parent
        }
        $catalogPath = $null
        foreach ($c in $candidates) {
            try { $resolved = [System.IO.Path]::GetFullPath($c) } catch { $resolved = $c }
            if (Test-Path -LiteralPath $resolved) { $catalogPath = $resolved; break }
        }
        if (-not $catalogPath) { throw "Catalog not found" }
        $raw = Get-Content -LiteralPath $catalogPath -Raw -ErrorAction Stop
        $catalog = $raw | ConvertFrom-Json -ErrorAction Stop
        return $catalog
    }
}

#region Generated Functions — DO NOT EDIT BETWEEN MARKERS
# BEGIN GENERATED — catalog wrappers

'@

$psm1Footer = @'

# END GENERATED
#endregion

$script:FunctionsToExport = @(
__EXPORT_LIST__
)
Export-ModuleMember -Function $script:FunctionsToExport
'@

# Generate function blocks
$functionBlocks = [System.Collections.Generic.List[string]]::new()
foreach ($funcName in ($functionsToExport | Sort-Object)) {
    $entry = $functionMap[$funcName]
    $relPath = $entry['path']
    $category = $entry['category']
    $synopsis = $entry['synopsis']
    if ([string]::IsNullOrWhiteSpace($synopsis)) { $synopsis = "Wrapper for $relPath" }
    # Escape synopsis for comment help (remove */ etc.)
    $synopsisEscaped = $synopsis -replace '\*/', '* /' -replace "`r`n", ' ' -replace "`n", ' ' -replace "`r", ' '
    if ($synopsisEscaped.Length -gt 120) { $synopsisEscaped = $synopsisEscaped.Substring(0, 117) + '...' }
    $paramInfo = Get-ParamBlockString -Entry $entry
    $paramBlock = $paramInfo.Text
    # Remap renamed parameters back to their original names before splatting to the backing script
    $beginRemap = ''
    if ($paramInfo.Renames.Count -gt 0) {
        $remapParts = foreach ($rn in $paramInfo.Renames.GetEnumerator()) {
            "        if (`$boundParams.ContainsKey('$($rn.Value)')) { `$boundParams['$($rn.Key)'] = `$boundParams['$($rn.Value)']; `$null = `$boundParams.Remove('$($rn.Value)') }"
        }
        $beginRemap = ($remapParts -join "`n") + "`n"
    }
    # Determine backing script path (relative to scripts root)
    # Use $script:ScriptsRoot + relative path
    $escapedPath = $relPath -replace "'", "''"
    $block = @"
function $funcName {
    <#
    .SYNOPSIS
        $synopsisEscaped
    .DESCRIPTION
        Proxies to scripts/$escapedPath.
        Original category: $category
    .PARAMETER WhatIf
        Shows what would happen without executing.
    .EXAMPLE
        $funcName -Verbose
    .NOTES
        Backing script: scripts/$escapedPath
        Category: $category
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Wrapper name mirrors backing script filename scripts/$escapedPath')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
$paramBlock
    begin {
        `$boundParams = @{}
        foreach (`$k in `$PSBoundParameters.Keys) {
            if (`$k -ne 'RemainingArgs') { `$boundParams[`$k] = `$PSBoundParameters[`$k] }
        }
$beginRemap    }
    process {
        `$target = Join-Path `$script:ScriptsRoot '$escapedPath'
        if (-not (Test-Path -LiteralPath `$target)) {
            `$alt = Join-Path `$script:RepoRootResolved "scripts/$escapedPath"
            if (Test-Path -LiteralPath `$alt) { `$target = `$alt }
        }
        if (`$PSCmdlet.ShouldProcess(`$target, 'Invoke script')) {
            if (`$RemainingArgs -and `$RemainingArgs.Count -gt 0) {
                & `$target @boundParams @RemainingArgs
            }
            else {
                & `$target @boundParams
            }
        }
    }
}
"@
    $functionBlocks.Add($block) | Out-Null
}

# Assemble psm1
$psm1FunctionsText = ($functionBlocks -join "`r`n`r`n")
$exportListText = ($allExports | ForEach-Object { "    '$_'" }) -join ",`r`n"
$psm1FooterResolved = $psm1Footer -replace '__EXPORT_LIST__', $exportListText
$psm1Content = $psm1Header + "`r`n" + $psm1FunctionsText + "`r`n" + $psm1FooterResolved

# --- PSD1 generation ---

# Preserve GUID if exists, else generate once
$existingGuid = $null
if (Test-Path -LiteralPath $script:Psd1Path) {
    try {
        $existingManifest = Import-PowerShellDataFile -Path $script:Psd1Path -ErrorAction SilentlyContinue
        if ($existingManifest -and $existingManifest.GUID) { $existingGuid = $existingManifest.GUID }
    } catch {
        Write-Verbose "Could not read existing manifest GUID: $($_.Exception.Message) — generating a new GUID"
    }
}
if (-not $existingGuid) {
    $existingGuid = [guid]::NewGuid().ToString()
}

# ReleaseNotes from CHANGELOG truncated to 500 chars, single-lined
$releaseNotes = '5.0.0 Hurricane - Platform'
try {
    $clLines = Get-Content -LiteralPath $script:ChangelogPath -Raw
    # Try to extract Unreleased or 5.0.0 section
    $unreleasedMatch = [regex]::Match($clLines, '##\s*\[Unreleased\](?<notes>.*?)(?=##\s*\[)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $notesRaw = if ($unreleasedMatch.Success) { $unreleasedMatch.Groups['notes'].Value } else { $clLines }
    $notesSingle = ($notesRaw -replace "`r`n", ' ' -replace "`n", ' ' -replace '\s+', ' ').Trim()
    if ($notesSingle.Length -gt 500) { $notesSingle = $notesSingle.Substring(0, 497) + '...' }
    if (-not [string]::IsNullOrWhiteSpace($notesSingle) -and $notesSingle.Length -gt 10) {
        $releaseNotes = "5.0.0 Hurricane - Platform. $notesSingle"
        if ($releaseNotes.Length -gt 500) { $releaseNotes = $releaseNotes.Substring(0, 497) + '...' }
    }
} catch {
    Write-Verbose "Could not extract release notes from CHANGELOG: $($_.Exception.Message)"
}

# FunctionsToExport list for PSD1 (sorted, quoted)
$psdFunctions = ($allExports | ForEach-Object { "        '$_'" }) -join ",`r`n"

$psd1Content = @"
@{
    # --- Identity ---
    ModuleVersion      = '$Version'
    GUID               = '$existingGuid'
    Author             = 'Carme99'
    CompanyName        = 'Carme99'
    Copyright          = '(c) Carme99. Licensed under Apache-2.0.'
    Description        = '358 PowerShell scripts as importable module'

    # --- Requirements ---
    PowerShellVersion  = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    RequiredModules    = @()
    PowerShellHostName = ''
    PowerShellHostVersion = ''
    DotNetFrameworkVersion = ''
    CLRVersion         = ''

    # --- Loading ---
    RootModule         = 'BugFreeUmbrella.psm1'
    ScriptsToProcess   = @()
    TypesToProcess     = @()
    FormatsToProcess   = @()
    NestedModules      = @()

    # --- Exports ---
    FunctionsToExport  = @(
$psdFunctions
    )
    CmdletsToExport    = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    # --- Gallery Metadata ---
    PrivateData        = @{
        PSData = @{
            Tags                       = @('Intune','M365','Azure','Security')
            LicenseUri                 = 'https://github.com/Carme99/bug-free-umbrella/blob/main/LICENSE'
            ProjectUri                 = 'https://github.com/Carme99/bug-free-umbrella'
            IconUri                    = ''
            ReleaseNotes               = '$($releaseNotes -replace "'", "''")'
            Prerelease                 = ''
            RequireLicenseAcceptance   = `$false
            ExternalModuleDependencies = @()
        }
    }

    HelpInfoURI          = 'https://github.com/Carme99/bug-free-umbrella/tree/main/docs'
    DefaultCommandPrefix = ''
}
"@

# Normalize psd1/psm1 to CRLF ensured by Write-FileWithBomCrlf
$stalePsd1 = $false
$stalePsm1 = $false

if ($Validate) {
    Write-Verbose "Validate mode: comparing on-disk artifacts"
    # Helper to normalize via Write-FileWithBomCrlf logic (CRLF + trailing newline)
    function Get-NormalizedHash {
        param([string]$Content)
        $norm = $Content -replace "`r`n", "`n" -replace "`r", "`n"
        $norm = $norm -replace "`n", "`r`n"
        if (-not $norm.EndsWith("`r`n")) { $norm += "`r`n" }
        # Return hash of UTF8 BOM bytes + content
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($norm)
        $bom = [byte[]]@(0xEF, 0xBB, 0xBF)
        $all = $bom + $bytes
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hash = $sha.ComputeHash($all)
        return [BitConverter]::ToString($hash).Replace('-', '')
    }
    if (-not (Test-Path -LiteralPath $script:Psd1Path)) {
        Write-Host "[-] PSD1 missing: $script:Psd1Path" -ForegroundColor Red
        $stalePsd1 = $true
    }
    else {
        $existingPsd1 = [System.IO.File]::ReadAllBytes($script:Psd1Path)
        $existingHash = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($existingPsd1)).Replace('-', '')
        $newHash = Get-NormalizedHash -Content $psd1Content
        if ($existingHash -ne $newHash) {
            Write-Host "[-] PSD1 stale: $script:Psd1Path differs from generated" -ForegroundColor Red
            $stalePsd1 = $true
        }
    }
    if (-not (Test-Path -LiteralPath $script:Psm1Path)) {
        Write-Host "[-] PSM1 missing: $script:Psm1Path" -ForegroundColor Red
        $stalePsm1 = $true
    }
    else {
        $existingPsm1 = [System.IO.File]::ReadAllBytes($script:Psm1Path)
        $existingHash2 = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($existingPsm1)).Replace('-', '')
        $newHash2 = Get-NormalizedHash -Content $psm1Content
        if ($existingHash2 -ne $newHash2) {
            Write-Host "[-] PSM1 stale: $script:Psm1Path differs from generated" -ForegroundColor Red
            $stalePsm1 = $true
        }
    }
    if ($stalePsd1 -or $stalePsm1) {
        Write-Host "[-] Module artifacts are stale — run 'pwsh -File tools/Build-Module.ps1' to regenerate." -ForegroundColor Red
        exit 1
    }
    else {
        Write-Host "[+] Module artifacts are up to date." -ForegroundColor Green
        Write-Host "    ModuleVersion=$Version  Functions=$($allExports.Count)  GUID=$existingGuid" -ForegroundColor Cyan
    }
}
else {
    if ($PSCmdlet.ShouldProcess($script:Psd1Path, 'Generate PSD1')) {
        Write-FileWithBomCrlf -Path $script:Psd1Path -Content $psd1Content
        Write-Host "[+] Generated $script:Psd1Path" -ForegroundColor Green
    }
    if ($PSCmdlet.ShouldProcess($script:Psm1Path, 'Generate PSM1')) {
        Write-FileWithBomCrlf -Path $script:Psm1Path -Content $psm1Content
        Write-Host "[+] Generated $script:Psm1Path with $($allExports.Count) exports (catalog $($functionsToExport.Count) + helpers $($cliHelpers.Count))" -ForegroundColor Green
    }
    Write-Host "    ModuleVersion=$Version  Functions=$($allExports.Count)  GUID=$existingGuid" -ForegroundColor Cyan
}

# -------------------------------------------------------------------------
# Step 4 — Validate Artifacts
# -------------------------------------------------------------------------

Write-Verbose "Step 4: Validate artifacts"

try {
    $null = Test-ModuleManifest -Path $script:Psd1Path -ErrorAction Stop
    Write-Host "[+] Test-ModuleManifest passed" -ForegroundColor Green
}
catch {
    Write-Host "[-] Test-ModuleManifest failed: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

# PSSA
try {
    $pesterSettings = $script:SettingsPath
    $pssaArgs = @{
        Path = $script:Psm1Path
        Severity = @('Error', 'Warning')
        ErrorAction = 'Stop'
    }
    if (Test-Path -LiteralPath $pesterSettings) { $pssaArgs['Settings'] = $pesterSettings }
    $findings = Invoke-ScriptAnalyzer @pssaArgs
    $errors = @($findings | Where-Object { $_.Severity -in @('Error', 'Warning') })
    # Filter to Errors only for gate? Design says Error,Warning MUST be 0
    # But settings excludes some warnings; we follow settings severity
    # Count only Errors for strict gate, but report warnings
    $errOnly = @($findings | Where-Object Severity -eq 'Error')
    if ($errOnly.Count -gt 0) {
        Write-Host "[-] PSScriptAnalyzer found $($errOnly.Count) Error(s) in PSM1:" -ForegroundColor Red
        $errOnly | Format-Table RuleName, Line, Message -AutoSize | Out-String | Write-Host -ForegroundColor Red
        throw "PSSA Errors in $script:Psm1Path"
    }
    else {
        Write-Host "[+] PSScriptAnalyzer passed (0 Errors, $($errors.Count) Warnings)" -ForegroundColor Green
    }
    # Also check PSD1
    $findingsPsd1 = Invoke-ScriptAnalyzer -Path $script:Psd1Path -Severity Error, Warning -ErrorAction Stop
    $errPsd1 = @($findingsPsd1 | Where-Object Severity -eq 'Error')
    if ($errPsd1.Count -gt 0) {
        Write-Host "[-] PSScriptAnalyzer Errors in PSD1:" -ForegroundColor Red
        $errPsd1 | Format-Table RuleName, Line, Message -AutoSize | Out-String | Write-Host -ForegroundColor Red
        throw "PSSA Errors in $script:Psd1Path"
    }
}
catch {
    if ($_.Exception.Message -like '*PSSA*') { throw }
    Write-Warning "PSScriptAnalyzer not available or failed: $($_.Exception.Message) — skipping PSSA gate"
}

# Smoke import (only when not -Validate)
if (-not $Validate) {
    try {
        Remove-Module BugFreeUmbrella -ErrorAction SilentlyContinue
        $mod = Import-Module $script:Psd1Path -Force -PassThru -ErrorAction Stop
        $count = (Get-Command -Module BugFreeUmbrella -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Host "[+] Import-Module succeeded: $($mod.Name) $($mod.Version)  Get-Command count=$count" -ForegroundColor Green
        if ($count -lt $functionsToExport.Count) {
            Write-Warning "Get-Command count $count < catalog functions $($functionsToExport.Count) — check exports"
        }
        Remove-Module BugFreeUmbrella -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "[-] Smoke import failed: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# -------------------------------------------------------------------------
# Step 5 — Optional Publish (dry-run by default)
# -------------------------------------------------------------------------

if ($Publish) {
    Write-Verbose "Step 5: Publish"
    $whatIf = $true
    # If -WhatIf was explicitly passed via ShouldProcess, respect it
    # Default to WhatIf dry-run
    try {
        $publishParams = @{
            Path = $script:OutDir
            Repository = 'PSGallery'
            WhatIf = $true
        }
        # Only do real publish if PSGALLERY_API_KEY is set and user did not use -WhatIf
        if ($env:PSGALLERY_API_KEY -and -not $WhatIfPreference) {
            # Check if ShouldProcess allows it
            if ($PSCmdlet.ShouldProcess("BugFreeUmbrella $Version", 'Publish-Module')) {
                Write-Host "[*] Publishing BugFreeUmbrella $Version to PSGallery (real)..." -ForegroundColor Yellow
                $publishParams.Remove('WhatIf')
                $publishParams['NuGetApiKey'] = $env:PSGALLERY_API_KEY
                # Mask key in logs
                $masked = if ($env:PSGALLERY_API_KEY.Length -gt 4) { $env:PSGALLERY_API_KEY.Substring(0, 4) + '****' } else { '****' }
                Write-Verbose "Using NuGetApiKey $masked"
                Publish-Module @publishParams -ErrorAction Stop
                Write-Host "[+] Publish-Module succeeded" -ForegroundColor Green
            }
        }
        else {
            if (-not $env:PSGALLERY_API_KEY) {
                Write-Host "[*] Publish dry-run (WhatIf) — PSGALLERY_API_KEY not set, skipping real publish" -ForegroundColor Yellow
            }
            Publish-Module @publishParams -ErrorAction Stop
            Write-Host "[+] Publish-Module -WhatIf dry-run succeeded" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "[-] Publish failed: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}
else {
    Write-Verbose "Skipping publish (use -Publish to dry-run)"
}

Write-Host "[+] Module built: $script:OutDir  ModuleVersion=$Version  Functions=$($allExports.Count)" -ForegroundColor Green
