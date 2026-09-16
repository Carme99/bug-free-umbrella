#Requires -Modules Pester

<#
.SYNOPSIS
    Guardrail test asserting every winget detect/remediate script defines the
    `Invoke-WingetWithRetry` helper at most once.

.DESCRIPTION
    A nested second `function Invoke-WingetWithRetry` definition shadows the
    first and, depending on placement, can swallow the actual winget invocation,
    leaving the outer function's `$result` unassigned. Each Intune proactive
    remediation script must be self-contained, so we keep exactly one canonical
    definition per file and forbid duplicates across the whole winget tree.

    The helper's canonical home is `scripts/endpoints/remediation/winget`. The
    deprecated forwarding-shim tree `scripts/endpoints/devices/winget` is scanned
    as well, but only while it still exists, so this guardrail keeps working once
    the shims are removed.
#>

BeforeAll {
    # Canonical tree first - it holds the real implementations.
    $script:canonicalWingetRoot = Join-Path $PSScriptRoot "../../scripts/endpoints/remediation/winget"

    # Deprecated forwarding shims - present only until that tree is removed.
    $script:shimWingetRoot = Join-Path $PSScriptRoot "../../scripts/endpoints/devices/winget"

    $script:wingetRoots = @($script:canonicalWingetRoot, $script:shimWingetRoot) |
        Where-Object { Test-Path -LiteralPath $_ }

    $script:wingetScripts = @(
        foreach ($root in $script:wingetRoots) {
            Get-ChildItem -Path $root -Recurse -Filter *.ps1 -File
        }
    )
}

Describe "Winget Invoke-WingetWithRetry single definition" {
    It "scans the canonical remediation/winget tree" {
        Test-Path -LiteralPath $script:canonicalWingetRoot | Should -BeTrue
        $script:wingetScripts.Count | Should -BeGreaterThan 0
    }

    It "includes every deprecated shim-tree script while that tree still exists" {
        $shimScripts = if (Test-Path -LiteralPath $script:shimWingetRoot) {
            @(Get-ChildItem -Path $script:shimWingetRoot -Recurse -Filter *.ps1 -File)
        } else {
            @()
        }

        $skipped = @($shimScripts | Where-Object { $_.FullName -notin $script:wingetScripts.FullName })
        $skipped | Should -BeNullOrEmpty
    }

    It "defines Invoke-WingetWithRetry at most once per file" {
        $violations = foreach ($file in $script:wingetScripts) {
            $count = @(Get-Content -Path $file.FullName | Where-Object { $_ -match '^\s*function\s+Invoke-WingetWithRetry' }).Count
            if ($count -gt 1) {
                $file.FullName
            }
        }
        $violations | Should -BeNullOrEmpty
    }

    It "keeps a canonical winget helper's ProcessStartInfo execution capturing and returning the result" {
        # Spot-check the canonical pattern is intact in a representative script:
        # the retry function must actually launch winget via ProcessStartInfo,
        # capture stdout into a variable, and return it (success keyed on the
        # child exit code) rather than being shadowed by an empty definition.
        $probe = Join-Path $PSScriptRoot "../../scripts/endpoints/remediation/winget/security/1Password/Test-Winget1Password.ps1"
        $content = Get-Content -Path $probe -Raw
        $content | Should -Match 'ProcessStartInfo'
        $content | Should -Match '\$stdout\s*=\s*\$p\.StandardOutput\.ReadToEnd\(\)'
        $content | Should -Match 'return\s+\$stdout'
    }
}
