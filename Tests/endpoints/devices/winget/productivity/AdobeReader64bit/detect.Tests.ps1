#Requires -Modules Pester

Describe "detect.ps1" {
    BeforeAll {
        # Mirrored layout: walk up ../../../../../../ levels from this test folder to the repository root.
        $repoRoot = (Get-Item (Join-Path $PSScriptRoot "../../../../../../")).FullName
        $scriptPath = Join-Path $repoRoot "scripts/endpoints/devices/winget/productivity/AdobeReader64bit/detect.ps1"

        # Safe: the top-level guard skips Main when dot-sourced (docs/RELAUNCH-SPEC.md section 3).
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$') | Should -BeTrue
            ($raw -match '(?m)^\s*Date\s*:\s*2026-08-23\s*$') | Should -BeTrue
        }

        It "Declares File Name matching the on-disk filename with no orphaned parameters documented" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match "(?m)^\s*File Name\s*:\s*detect\.ps1\s*$") | Should -BeTrue
            ($raw -match '\.PARAMETER') | Should -BeFalse  # param() is intentionally empty
        }

        It "Provides at least two examples" {
            $raw = Get-Content -Path $scriptPath -Raw
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Is UTF-8 BOM encoded with CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            (@($bytes[0], $bytes[1], $bytes[2])) | Should -Be @(0xEF, 0xBB, 0xBF)
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            $bareLfLines = @(($text -split "`n") | Where-Object { $_ -and ($_ -notmatch "`r$") })
            $bareLfLines.Count | Should -Be 0
        }

        It "Contains no PS7-only operators without an opt-out pragma" {
            $raw = Get-Content -Path $scriptPath -Raw
            foreach ($pattern in '&&', '\|\|', '\?\?') {
                ($raw -match $pattern) | Should -BeFalse
            }
        }

        It "Declares CmdletBinding, a Main function, a dot-source guard, and exit only in the guard line" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match '\[CmdletBinding\(\)\]') | Should -BeTrue
            ($raw -match '(?m)^function Main \{') | Should -BeTrue
            ($raw -match [regex]::Escape('if ($MyInvocation.InvocationName -ne '.')')) | Should -BeTrue
            ([regex]::Matches($raw, '\bexit\s*\(')).Count | Should -Be 1
        }
    }

    Context "Behavior" {
        It "Forwards to the canonical script and preserves its exit code" {
            Mock Write-Host { }
            Mock Write-Warning { }
            Mock Invoke-CanonicalScript { 7 }
            Main | Should -Be 7
            Should -Invoke Invoke-CanonicalScript -Times 1 -Exactly -ParameterFilter {
                $Path -like '*Test-WingetAdobeReader64bit.ps1'
            }
        }

        It "Returns 0 when the canonical script reports success (repeatable forward)" {
            Mock Write-Host { }
            Mock Write-Warning { }
            Mock Invoke-CanonicalScript { 0 }
            Main | Should -Be 0
            Should -Invoke Invoke-CanonicalScript -Times 1 -Exactly
        }

        It "Warns that the script is deprecated" {
            Mock Write-Host { }
            Mock Write-Warning { }
            Mock Invoke-CanonicalScript { 0 }
            Main | Out-Null
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -match 'Deprecated' }
        }

        It "Returns 1 with [-] prefixed output when forwarding fails" {
            # Pass console output through so the [-] prefix can be asserted.
            Mock Write-Host { param($Object) $Object }
            Mock Write-Warning { }
            Mock Invoke-CanonicalScript { throw 'canonical script failed' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
