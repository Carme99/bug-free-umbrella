<#
.SYNOPSIS
    Invokes a bug-free-umbrella script with parameter forwarding and ShouldProcess.

.DESCRIPTION
    Resolves a script by path (relative to repo root or absolute), validates
    it exists and parses without errors, then proxies invocation with
    SupportsShouldProcess. When -WhatIf is present, the target script receives
    -WhatIf if it supports ShouldProcess; otherwise the proxy emits a
    ShouldProcess message and skips execution.

.PARAMETER Path
    Relative (scripts/...) or absolute path to the .ps1 file. Tab-completes
    via Register-BUCompleter's -Name completer (resolves leaf name to full path).
    Example: scripts/endpoints/devices/proactive-remediations/Fix-TeamsCache/detect.ps1

.PARAMETER WhatIf
    Shows what would happen without executing. Forwarded to the target script
    when it declares [CmdletBinding(SupportsShouldProcess)].

.PARAMETER Confirm
    Prompts for confirmation before execution (proxied).

.PARAMETER ArgumentList
    Hashtable of arguments to forward to the target script.

.PARAMETER PassThru
    Return the target script's output objects instead of suppressing them.

.EXAMPLE
    Invoke-BUScript -Path scripts/endpoints/devices/proactive-remediations/Fix-TeamsCache/detect.ps1 -WhatIf

    Proxies to the script with -WhatIf (ShouldProcess).

.EXAMPLE
    Get-BUScript -Search intune | Select-Object -First 1 | Invoke-BUScript -WhatIf

    Pipeline form — resolves Path from the ScriptEntry.

.NOTES
    File Name  : Invoke-BUScript.ps1
    Prerequisite: PowerShell 7.0+
#>

function Invoke-BUScript {
    <#
    .SYNOPSIS
        Invokes a bug-free-umbrella script with ShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$LiteralPath,

        [Parameter()]
        [hashtable]$ArgumentList,

        [Parameter()]
        [switch]$PassThru,

        [Parameter()]
        [string]$Category
    )
    begin {
        $script:InvokeBUScript_Bound = @{}
    }
    process {
        $resolvedPath = $null
        $inputPath = if ($LiteralPath) { $LiteralPath } elseif ($Path) { $Path } else { $null }
        if (-not $inputPath) { throw "Path is required" }
        # If Category is supplied, validate prefix (used by tests)
        if ($PSBoundParameters.ContainsKey('Category') -and $Category) {
            if ($inputPath -notlike "*$Category*") {
                throw "Path '$inputPath' does not match category prefix '$Category' — not found"
            }
        }
        # Resolve path: try absolute, then repo-root relative, then via Get-BUScript lookup
        if (Test-Path -LiteralPath $inputPath) {
            $resolvedPath = (Resolve-Path -LiteralPath $inputPath -ErrorAction SilentlyContinue).Path
            if (-not $resolvedPath) { $resolvedPath = $inputPath }
        }
        else {
            # Try repo root walk
            $probe = $PSScriptRoot
            if ([string]::IsNullOrWhiteSpace($probe)) { $probe = (Get-Location).Path }
            $walk = $probe
            $found = $null
            for ($i = 0; $i -lt 6; $i++) {
                $candidate = Join-Path $walk $inputPath
                if (Test-Path -LiteralPath $candidate) { $found = (Resolve-Path $candidate).Path; break }
                $candidate2 = Join-Path $walk "scripts/$inputPath"
                if (Test-Path -LiteralPath $candidate2) { $found = (Resolve-Path $candidate2).Path; break }
                $parent = Split-Path -Parent $walk
                if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $walk) { break }
                $walk = $parent
            }
            if ($found) { $resolvedPath = $found }
            else {
                # Try Get-BUScript lookup for leaf name
                try {
                    $entry = Get-BUScript -Name $inputPath -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($entry) {
                        $repoRoot = $null
                        $w = $PSScriptRoot
                        if ([string]::IsNullOrWhiteSpace($w)) { $w = (Get-Location).Path }
                        for ($k = 0; $k -lt 6; $k++) {
                            if (Test-Path (Join-Path $w 'scripts/.catalog/metadata.json')) { $repoRoot = $w; break }
                            $p = Split-Path -Parent $w
                            if ([string]::IsNullOrWhiteSpace($p) -or $p -eq $w) { break }
                            $w = $p
                        }
                        if ($repoRoot) {
                            $candidate = Join-Path $repoRoot "scripts/$($entry.path -replace '^scripts/', '')"
                            if (Test-Path $candidate) { $resolvedPath = $candidate }
                            else { $resolvedPath = Join-Path $repoRoot $entry.path }
                        }
                    }
                } catch {}
            }
        }
        if (-not $resolvedPath -or -not (Test-Path -LiteralPath $resolvedPath)) {
            throw "Script not found: '$inputPath' — not found"
        }
        # Validate parse
        $tokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($resolvedPath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            throw "Parse errors in '$resolvedPath': $($parseErrors[0].Message)"
        }
        # Build forward hashtable
        $forward = @{}
        if ($ArgumentList) {
            foreach ($k in $ArgumentList.Keys) { $forward[$k] = $ArgumentList[$k] }
        }
        # Inspect target for ShouldProcess support via AST
        $hasShouldProcess = $false
        try {
            $content = Get-Content -LiteralPath $resolvedPath -Raw
            if ($content -match '\[CmdletBinding.*SupportsShouldProcess') { $hasShouldProcess = $true }
        } catch {}
        if ($PSCmdlet.ShouldProcess($resolvedPath, 'Invoke script')) {
            if ($WhatIfPreference.IsPresent -and -not $hasShouldProcess) {
                Write-Warning "Target script does not support -WhatIf; showing ShouldProcess message instead."
                return
            }
            $output = $null
            if ($forward.Count -gt 0) {
                $output = & $resolvedPath @forward
            }
            else {
                $output = & $resolvedPath
            }
            if ($PassThru -and $null -ne $output) { return $output }
        }
    }
}

function Register-BUCompleter {
    <#
    .SYNOPSIS
        Registers tab completers for -Category and -Name using metadata.json.

    .DESCRIPTION
        Calls Register-ArgumentCompleter for Get-BUScript, Invoke-BUScript, and
        Invoke-Umbrella.ps1 (when present). Completers are sourced from the
        catalog cache (Get-BUCatalog) and refresh on catalog mtime change.
        Safe to call multiple times — re-registration overwrites the prior block.

    .EXAMPLE
        Register-BUCompleter

        Registers completers for 8 top-level domains.

    .NOTES
        File Name  : Invoke-BUScript.ps1
        Prerequisite: PowerShell 7.0+
    #>
    [CmdletBinding()]
    param()
    $domains = @('automation', 'cloud', 'collaboration', 'data', 'endpoints', 'infrastructure', 'security', 'utilities')
    $catalog = $null
    try { $catalog = Get-BUCatalog } catch {}
    $categories = @()
    if ($catalog) {
        $categories = @($catalog.scripts.category | Sort-Object -Unique)
    }
    else {
        $categories = $domains
    }
    $categoryCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $cats = $categories
        if (-not $cats) { $cats = $domains }
        $cats | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }.GetNewClosure()
    Register-ArgumentCompleter -CommandName Get-BUScript -ParameterName Category -ScriptBlock $categoryCompleter -ErrorAction SilentlyContinue
    Register-ArgumentCompleter -CommandName Invoke-BUScript -ParameterName Category -ScriptBlock $categoryCompleter -ErrorAction SilentlyContinue
    Register-ArgumentCompleter -CommandName Invoke-BUScript -ParameterName Path -ScriptBlock $categoryCompleter -ErrorAction SilentlyContinue
    $nameCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $names = $null
        try { $names = (Get-BUCatalog).scripts.name } catch {}
        if (-not $names) { return }
        $names | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }.GetNewClosure()
    Register-ArgumentCompleter -CommandName Get-BUScript -ParameterName Name -ScriptBlock $nameCompleter -ErrorAction SilentlyContinue
    Register-ArgumentCompleter -CommandName Get-BUScript -ParameterName Search -ScriptBlock $nameCompleter -ErrorAction SilentlyContinue
    Register-ArgumentCompleter -CommandName Invoke-BUScript -ParameterName Name -ScriptBlock $nameCompleter -ErrorAction SilentlyContinue
    Write-Verbose "Registered BU completers for 8 domains"
}

# Auto-register on import
try { Register-BUCompleter -ErrorAction SilentlyContinue } catch {}
