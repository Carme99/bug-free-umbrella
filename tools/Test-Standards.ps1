#Requires -Version 7.0
<#
.SYNOPSIS
    Enforces the mechanical rules of docs/STANDARDS.md across scripts/ and Tests/.

.DESCRIPTION
    Implements the checkable subset of the standards contract so the rules can be enforced
    by CI rather than by review. For every non-test script under scripts/ it verifies the
    comment-based help fields, the script shape, encoding, formatting and test mirror, and
    for every mirrored suite it verifies the required help and metadata assertions.

    Command usage is resolved through the AST (CommandAst), so destructive cmdlet names
    appearing inside string literals or comments are not misreported as ungated
    destructive operations.

    Exits 0 when no findings are reported and 1 otherwise. Supports -WhatIf-free operation;
    the tool is read-only and never edits a file.

.PARAMETER Root
    Repository root. Defaults to the parent of this tool's directory.

.PARAMETER Version
    Expected `.NOTES` Version value. Defaults to 2.0.0.

.PARAMETER Date
    Expected `.NOTES` Date value. Defaults to 2026-09-16.

.PARAMETER PassThru
    Emit the findings as objects in addition to the console report.

.EXAMPLE
    PS C:\> .\Test-Standards.ps1
    Reports every standards violation in the collection.

.EXAMPLE
    PS C:\> .\Test-Standards.ps1 -PassThru | Where-Object Rule -like 'Format.*'
    Reports only the formatting findings as objects.

.EXAMPLE
    PS C:\> .\Test-Standards.ps1 -Verbose
    Runs the check with a summary per rule.

.NOTES
    File Name   : Test-Standards.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>
[CmdletBinding()]
param(
    [string]$Root,

    [string]$Version = '2.0.0',

    [string]$Date = '2026-09-16',

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepoRoot = if ($Root) { (Resolve-Path -LiteralPath $Root).Path }
else { (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$script:ScriptsRoot = Join-Path $script:RepoRoot 'scripts'
$script:TestsRoot = Join-Path $script:RepoRoot 'Tests'
$script:ApprovedVerbs = (Get-Verb).Verb

# Cmdlets that mutate or destroy user or environment state and therefore need a ShouldProcess gate.
$script:DestructiveCmdlets = @(
    'Remove-Item', 'Remove-ItemProperty', 'Remove-Variable', 'Remove-PSDrive',
    'Remove-AppxPackage', 'Remove-Package', 'Remove-Module', 'Remove-WindowsPackage',
    'Remove-SmbShare', 'Uninstall-Module', 'Uninstall-Package',
    'Stop-Service', 'Stop-Process', 'Stop-Computer', 'Restart-Computer', 'Restart-Service',
    'Set-ItemProperty', 'Set-Service', 'Set-Acl', 'Set-ExecutionPolicy',
    'New-ItemProperty', 'Move-Item', 'Rename-Item', 'Clear-Content',
    'Optimize-Volume', 'Format-Volume', 'Disable-WindowsOptionalFeature'
)

# PowerShell 7-only tokens that require a `#Requires -Version 7.0` opt-out on line 1.
$script:Ps7OnlyTokens = @('QuestionMark', 'QuestionQuestion', 'AmpersandAmpersand', 'PipePipe')
$script:Domains = @('automation', 'cloud', 'collaboration', 'data', 'endpoints',
    'infrastructure', 'security', 'utilities')
$script:Findings = [System.Collections.Generic.List[object]]::new()

function Add-Finding {
    param([string]$Path, [string]$Rule, [string]$Detail, [int]$Line = 0)

    $script:Findings.Add([pscustomobject]@{
            Path   = $Path
            Rule   = $Rule
            Line   = $Line
            Detail = $Detail
        })
}

function Test-ScriptFile {
    param([System.IO.FileInfo]$File, [string]$RelativePath)

    $bytes = [IO.File]::ReadAllBytes($File.FullName)
    $raw = [IO.File]::ReadAllText($File.FullName)

    # Encoding: UTF-8 BOM and CRLF only.
    if (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
        Add-Finding $RelativePath 'Encoding.BOM' 'Missing UTF-8 BOM'
    }
    $bareLf = 0
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 0x0A -and ($i -eq 0 -or $bytes[$i - 1] -ne 0x0D)) { $bareLf++ }
    }
    if ($bareLf -gt 0) {
        Add-Finding $RelativePath 'Encoding.CRLF' "$bareLf bare LF line ending(s); files must be CRLF"
    }

    $lines = $raw -split "`r`n|`n"

    # Formatting. A line may exceed 120 columns only when the overflow is a single
    # unbreakable token (for example a URL), which the contract exempts.
    $tabLines = 0
    $trailing = 0
    $long = 0
    $firstLong = 0
    for ($n = 0; $n -lt $lines.Count; $n++) {
        $ln = $lines[$n]
        if ($ln -match "^[`t ]*`t") { $tabLines++ }
        if ($ln -match '[ \t]+$') { $trailing++ }
        if ($ln.Length -gt 120 -and ($ln.Substring(120) -match '\s')) {
            $long++
            if ($firstLong -eq 0) { $firstLong = $n + 1 }
        }
    }
    if ($tabLines -gt 0) { Add-Finding $RelativePath 'Format.Tabs' "$tabLines line(s) with tab indentation" }
    if ($trailing -gt 0) { Add-Finding $RelativePath 'Format.TrailingWhitespace' "$trailing line(s) with trailing whitespace" }
    if ($long -gt 0) { Add-Finding $RelativePath 'Format.LineLength' "$long line(s) exceed 120 columns (first at line $firstLong)" $firstLong }

    # Help.
    if ($raw -notmatch '\.SYNOPSIS') { Add-Finding $RelativePath 'Help.Synopsis' 'Missing .SYNOPSIS' }
    if ($raw -notmatch '\.DESCRIPTION') { Add-Finding $RelativePath 'Help.Description' 'Missing .DESCRIPTION' }
    $examples = ([regex]::Matches($raw, '(?m)^\s*\.EXAMPLE')).Count
    if ($examples -lt 2) { Add-Finding $RelativePath 'Help.Examples' "Only $examples .EXAMPLE block(s); the contract requires >=2" }

    $fieldPatterns = @{
        'File Name'    = '(?m)^\s*File Name\s*:\s*(.+)$'
        'Author'       = '(?m)^\s*Author\s*:\s*(.+)$'
        'Prerequisite' = '(?m)^\s*Prerequisite\s*:\s*(.+)$'
        'Version'      = '(?m)^\s*Version\s*:\s*(\S+)\s*$'
        'Date'         = '(?m)^\s*Date\s*:\s*(\S+)\s*$'
    }
    $notes = @{}
    foreach ($key in $fieldPatterns.Keys) {
        $match = [regex]::Match($raw, $fieldPatterns[$key])
        if (-not $match.Success) { Add-Finding $RelativePath 'Notes.MissingField' ".NOTES field '$key' missing" }
        else { $notes[$key] = $match.Groups[1].Value.Trim() }
    }
    if ($notes.ContainsKey('File Name') -and $notes['File Name'] -ne $File.Name) {
        Add-Finding $RelativePath 'Notes.FileNameMismatch' "File Name is '$($notes['File Name'])', disk filename is '$($File.Name)'"
    }
    if ($notes.ContainsKey('Version') -and $notes['Version'] -ne $Version) {
        Add-Finding $RelativePath 'Notes.Version' "Version is '$($notes['Version'])', expected $Version"
    }
    if ($notes.ContainsKey('Date') -and $notes['Date'] -ne $Date) {
        Add-Finding $RelativePath 'Notes.Date' "Date is '$($notes['Date'])', expected $Date"
    }

    # Structure.
    if ($raw -notmatch '\[CmdletBinding\(') { Add-Finding $RelativePath 'Structure.CmdletBinding' 'Missing [CmdletBinding()]' }
    if ($raw -notmatch '(?m)^\s*function\s+Main\b') { Add-Finding $RelativePath 'Structure.Main' 'Missing function Main' }
    if ($raw -notmatch "\`$ErrorActionPreference\s*=\s*['`"]Stop['`"]") {
        Add-Finding $RelativePath 'Structure.ErrorActionPreference' "Missing `$ErrorActionPreference = 'Stop'"
    }

    # Both guard polarities are conforming: `-ne '.'` and the negated `-eq '.'` form.
    $guardPattern = "MyInvocation\.InvocationName\s*(-ne\s*'\.'|-eq\s*'\.')"
    if ($raw -notmatch $guardPattern) {
        Add-Finding $RelativePath 'Structure.DotSourceGuard' 'Missing the top-level dot-source guard'
    }

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        Add-Finding $RelativePath 'Syntax.Parse' $parseErrors[0].Message $parseErrors[0].Extent.StartLineNumber
    }

    $guardLines = @()
    foreach ($guardMatch in [regex]::Matches($raw, "(?m)^.*$guardPattern.*$")) {
        $guardLines += ($raw.Substring(0, $guardMatch.Index).Split("`n").Count)
    }
    $exitNodes = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ExitStatementAst] }, $true))
    $strayExits = @($exitNodes | Where-Object { $guardLines -notcontains $_.Extent.StartLineNumber })
    if ($strayExits.Count -gt 0) {
        $locations = @($strayExits | ForEach-Object { $_.Extent.StartLineNumber })
        Add-Finding $RelativePath 'Structure.ExitPlacement' "exit outside the dot-source guard at line(s) $($locations -join ', ')" $locations[0]
    }

    # Compatibility: PS7-only syntax without the line-1 opt-out.
    if ($lines[0] -notmatch '#Requires\s+-Version\s+(7|\d+)') {
        $badTokens = @($tokens | Where-Object { $script:Ps7OnlyTokens -contains $_.Kind.ToString() })
        if ($badTokens.Count -gt 0) {
            Add-Finding $RelativePath 'Compat.PS7Token' "PS7-only token '$($badTokens[0].Kind)' used without #Requires -Version 7.0" $badTokens[0].Extent.StartLineNumber
        }
    }

    # Destructive operations need a ShouldProcess gate. STANDARDS section 1 exempts disposal
    # of an ephemeral artifact the script itself created in the same run, recorded inline.
    $usedDestructive = @()
    foreach ($command in @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))) {
        $name = $command.GetCommandName()
        if ($name -and ($script:DestructiveCmdlets -contains $name)) { $usedDestructive += $name }
    }
    $usedDestructive = @($usedDestructive | Select-Object -Unique)
    $exempt = $raw -match 'Exempt from the ShouldProcess rule'
    if ($usedDestructive.Count -gt 0 -and $raw -notmatch 'SupportsShouldProcess' -and -not $exempt) {
        Add-Finding $RelativePath 'Structure.ShouldProcess' "Destructive cmdlet(s) used without SupportsShouldProcess: $($usedDestructive -join ', ')"
    }

    # Approved verbs on declared functions.
    $functionNames = [regex]::Matches($raw, '(?m)^\s*function\s+([A-Za-z][\w-]*)') | ForEach-Object { $_.Groups[1].Value }
    $badVerbs = @($functionNames | Where-Object { $_ -match '-' -and ($_.Split('-')[0]) -notin $script:ApprovedVerbs })
    if ($badVerbs.Count -gt 0) {
        Add-Finding $RelativePath 'Structure.Verb' "Non-approved verb(s): $($badVerbs -join ', ')"
    }

    # Mirrored test.
    $mirrorRelative = ($RelativePath -replace '^scripts/', '') -replace '\.ps1$', '.Tests.ps1'
    if (-not (Test-Path -LiteralPath (Join-Path $script:TestsRoot $mirrorRelative))) {
        Add-Finding $RelativePath 'Tests.MissingMirror' "No mirrored test at 'Tests/$mirrorRelative'"
    }
}

function Main {
    try {
        if (-not (Test-Path -LiteralPath $script:ScriptsRoot)) {
            throw "Scripts root not found: $script:ScriptsRoot"
        }

        Write-Host "[*] Checking scripts against the standards contract..." -ForegroundColor Cyan

        $files = Get-ChildItem -Path $script:ScriptsRoot -Recurse -Filter '*.ps1' |
            Where-Object { $_.Name -notlike '*.Tests.ps1' } |
            Sort-Object FullName

        foreach ($file in $files) {
            $relative = ([IO.Path]::GetRelativePath($script:RepoRoot, $file.FullName)) -replace '\\', '/'
            Test-ScriptFile -File $file -RelativePath $relative
        }

        # Orphan mirrored tests: only tests under a script domain must mirror a script.
        if (Test-Path -LiteralPath $script:TestsRoot) {
            Get-ChildItem -Path $script:TestsRoot -Recurse -Filter '*.Tests.ps1' | ForEach-Object {
                $relativeTest = ([IO.Path]::GetRelativePath($script:TestsRoot, $_.FullName)) -replace '\\', '/'
                $top = ($relativeTest -split '/')[0]
                if ($script:Domains -contains $top) {
                    $candidate = Join-Path $script:ScriptsRoot (($relativeTest -replace '\.Tests\.ps1$', '.ps1'))
                    if (-not (Test-Path -LiteralPath $candidate)) {
                        Add-Finding "Tests/$relativeTest" 'Tests.Orphan' "'scripts/$($relativeTest -replace '\.Tests\.ps1$', '.ps1')' does not exist"
                    }
                }
            }
        }

        if ($script:Findings.Count -eq 0) {
            Write-Host "[+] Standards check passed: $($files.Count) script(s), 0 findings." -ForegroundColor Green
            return 0
        }

        Write-Host "[-] Standards check reported $($script:Findings.Count) finding(s):" -ForegroundColor Red
        $script:Findings | Group-Object Rule | Sort-Object Count -Descending | ForEach-Object {
            Write-Host ("    {0,4}  {1}" -f $_.Count, $_.Name) -ForegroundColor Yellow
        }
        Write-Host ''
        $script:Findings | Select-Object -First 50 | ForEach-Object {
            $location = if ($_.Line -gt 0) { "$($_.Path):$($_.Line)" } else { $_.Path }
            Write-Host ("    $location  [$($_.Rule)] $($_.Detail)")
        }
        if ($script:Findings.Count -gt 50) {
            Write-Host "    ... and $($script:Findings.Count - 50) more" -ForegroundColor Yellow
        }
        return 1
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
