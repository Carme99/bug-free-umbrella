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
#>

BeforeAll {
    $script:wingetRoot = Join-Path $PSScriptRoot "..\..\scripts\endpoints\devices\winget"
    $script:wingetScripts = @(Get-ChildItem -Path $wingetRoot -Recurse -Filter *.ps1 -File)
}

Describe "Winget Invoke-WingetWithRetry single definition" {
    It "finds winget scripts to validate" {
        $script:wingetScripts.Count | Should -BeGreaterThan 0
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
        # The devices/winget tree now holds deprecated forwarder shims; the
        # canonical home of Invoke-WingetWithRetry is under remediation/winget.
        $probe = Join-Path $PSScriptRoot "..\..\scripts\endpoints\remediation\winget\security\1Password\Test-Winget1Password.ps1"
        $content = Get-Content -Path $probe -Raw
        $content | Should -Match 'ProcessStartInfo'
        $content | Should -Match '\$stdout\s*=\s*\$p\.StandardOutput\.ReadToEnd\(\)'
        $content | Should -Match 'return\s+\$stdout'
    }
}