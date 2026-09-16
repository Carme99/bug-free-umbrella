#Requires -Version 7.0
<#
.SYNOPSIS
    Re-stamps the script and test standard revision recorded in every .NOTES block.

.DESCRIPTION
    The repository standard (`docs/STANDARDS.md`) states that the `.NOTES` `Version`
    field records the revision of the *standard* a file conforms to, and `Date` records
    the date it was last stamped. A release that changes the standard therefore re-stamps
    every script and every mirrored test in one pass, including the assertion literals
    inside the Pester suites that verify those fields.

    This tool performs that pass deterministically. It rewrites:
      - `Version : <FromVersion>` and `Date : <FromDate>` lines in `.NOTES` blocks, and
      - the escaped assertion literals `Version\s*:\s*<FromVersion>` and
        `Date\s*:\s*<FromDate>` used by mirrored tests.
    Files are rewritten in place preserving UTF-8 BOM and CRLF line endings.

    Run with -WhatIf to list the files that would change without writing anything.

.PARAMETER FromVersion
    The standard revision to replace. Defaults to `1.0.0`.

.PARAMETER ToVersion
    The standard revision to stamp. Defaults to `2.0.0`.

.PARAMETER FromDate
    The stamp date to replace. Defaults to `2026-08-23`.

.PARAMETER ToDate
    The stamp date to write. Defaults to `2026-09-16`.

.PARAMETER Path
    Repository root to operate on. Defaults to the parent of this tool's directory.

.PARAMETER PassThru
    Emit one object per rewritten file.

.EXAMPLE
    PS C:\> .\Update-StandardVersion.ps1 -WhatIf
    Lists every script and test still stamped with the 1.0.0 standard revision.

.EXAMPLE
    PS C:\> .\Update-StandardVersion.ps1 -FromVersion 2.0.0 -ToVersion 3.0.0 -ToDate 2027-01-15
    Re-stamps the collection for the next standard revision.

.EXAMPLE
    PS C:\> .\Update-StandardVersion.ps1 -PassThru | Measure-Object
    Reports how many files were rewritten.

.NOTES
    File Name   : Update-StandardVersion.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$FromVersion = '1.0.0',

    [string]$ToVersion = '2.0.0',

    [string]$FromDate = '2026-08-23',

    [string]$ToDate = '2026-09-16',

    [string]$Path,

    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

function Main {
    try {
        $root = $Path
        if ([string]::IsNullOrWhiteSpace($root)) {
            $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        }

        if (-not (Test-Path -LiteralPath $root)) {
            throw "Repository root not found: $root"
        }

        $utf8Bom = [System.Text.UTF8Encoding]::new($true)

        # Line-shaped patterns: the whole line is nothing but the .NOTES field, so
        # incidental "Version"/"Date" text elsewhere in a file is never touched.
        $versionLine = [regex]::new(
            '(?m)^(\s*Version\s*:\s*)' + [regex]::Escape($FromVersion) + '(\s*)$')
        $dateLine = [regex]::new(
            '(?m)^(\s*Date\s*:\s*)' + [regex]::Escape($FromDate) + '(\s*)$')

        # Test suites assert the fields as escaped regex literals; those strings must
        # move with the stamp or every suite fails.
        $versionLiteral = 'Version\s*:\s*' + [regex]::Escape($FromVersion)
        $versionLiteralNew = 'Version\s*:\s*' + [regex]::Escape($ToVersion)
        $dateLiteral = 'Date\s*:\s*' + [regex]::Escape($FromDate)
        $dateLiteralNew = 'Date\s*:\s*' + [regex]::Escape($ToDate)

        $targets = @(
            Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Recurse -Filter '*.ps1' -File
            Get-ChildItem -LiteralPath (Join-Path $root 'Tests') -Recurse -Filter '*.ps1' -File
        )

        Write-Host "[*] Scanning $($targets.Count) PowerShell file(s) under $root..." -ForegroundColor Cyan

        $matched = 0
        $changed = 0
        foreach ($file in $targets) {
            $text = [IO.File]::ReadAllText($file.FullName)

            $updated = $versionLine.Replace($text, ('${1}' + $ToVersion + '${2}'))
            $updated = $dateLine.Replace($updated, ('${1}' + $ToDate + '${2}'))
            $updated = $updated.Replace($versionLiteral, $versionLiteralNew)
            $updated = $updated.Replace($dateLiteral, $dateLiteralNew)

            if ($updated -ceq $text) { continue }

            $matched++

            $relative = [IO.Path]::GetRelativePath($root, $file.FullName)
            if ($PSCmdlet.ShouldProcess($relative, "stamp standard $ToVersion / $ToDate")) {
                [IO.File]::WriteAllText($file.FullName, $updated, $utf8Bom)
                $changed++
                Write-Host "[+] Stamped $relative" -ForegroundColor Green
                if ($PassThru) {
                    [pscustomobject]@{ Path = $relative; Version = $ToVersion; Date = $ToDate }
                }
            }
        }

        $summary = "[+] Complete: $matched file(s) matched the old stamp, " +
            "$changed written for standard $ToVersion / $ToDate"
        Write-Host $summary -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
