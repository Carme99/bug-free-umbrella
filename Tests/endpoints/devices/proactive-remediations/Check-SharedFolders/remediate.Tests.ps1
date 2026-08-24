#Requires -Modules Pester

Describe "Check-SharedFolders/remediate.ps1 (deprecated shim)" {
    BeforeAll {
        # Mirrored layout: this test dir mirrors the script dir; repo root is five levels up.
        $here = Get-Item $PSScriptRoot
        $repoRoot = $here.Parent.Parent.Parent.Parent.Parent.FullName
        $prDir = 'scripts/endpoints/devices/proactive-remediations/Check-SharedFolders'
        $scriptPath = Join-Path $repoRoot (Join-Path $prDir 'remediate.ps1')
        $canonicalRepoPath =
            'scripts/endpoints/remediation/network/Invoke-RemediationCheckSharedFolders.ps1'

        # Safe: the top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        . $scriptPath

        # Mock seam: all forwarding goes through Invoke-ForwardedScript; never through the real canonical script.
        Mock Invoke-ForwardedScript { 0 }
    }

    Context "Help & Metadata" {
        It "Declares required header fields matching the disk filename" {
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            $fileName = Split-Path $scriptPath -Leaf
            $raw | Should -Match ("File Name\s*:\s*" + [regex]::Escape($fileName))
            $raw | Should -Match 'Version\s*:\s*1\.0\.0'
            $raw | Should -Match 'Date\s*:\s*2026-08-23'
            $raw | Should -Match 'Author\s*:'
            $raw | Should -Match 'Prerequisite\s*:'
        }

        It "Marks deprecation, declares no undeclared parameters, and ships >=2 examples" {
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            $paramHelpCount = ($raw | Select-String '(?m)^\.PARAMETER\b' -AllMatches).Matches.Count
            $paramHelpCount | Should -Be 0 # shim declares no parameters
            ($raw | Select-String '(?m)^\.EXAMPLE' -AllMatches).Matches.Count | Should -BeGreaterOrEqual 2
            ($raw | Select-String 'DEPRECATED' -AllMatches).Matches.Count | Should -BeGreaterThan 0
        }

        It "Renders Get-Help -Detailed completely" {
            $help = Get-Help -Detailed $scriptPath
            $help.Synopsis | Should -Match 'DEPRECATED'
            $help.Examples.Example.Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses without errors" {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $null = $ast
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Uses no PS7-only operators without opting out via #Requires" {
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            $optsOut = $raw -match '(?m)^#Requires\s+-Version\s+7'
            if (-not $optsOut) {
                $raw | Should -Not -Match '\?\?|\|\||&&'
            }
        }
    }

    Context "Behavior" {
        It "Warns about deprecation and forwards to the canonical script" {
            $script:forwardedTo = $null
            Mock Invoke-ForwardedScript { param($Path) $script:forwardedTo = $Path; 0 }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'Deprecated'
            $script:forwardedTo | Should -Not -BeNullOrEmpty
            (Split-Path $script:forwardedTo -Leaf) | Should -Be (Split-Path $canonicalRepoPath -Leaf)
            Should -Invoke Invoke-ForwardedScript -Times 1 -Exactly
        }

        It "Returns the canonical exit code verbatim, preserving detect/remediate semantics" {
            Mock Invoke-ForwardedScript { 1 }
            Main | Should -Be 1
        }

        It "Is safe to re-run converged: dot-sourcing executes nothing (guard skips Main)" {
            Mock Invoke-ForwardedScript { throw 'Main must not run when dot-sourcing' }
            { . $scriptPath } | Should -Not -Throw
        }

        It "Returns 1 with [-] prefixed output when forwarding fails" {
            Mock Invoke-ForwardedScript { throw 'canonical script not found' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
