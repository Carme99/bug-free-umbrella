#Requires -Modules Pester

Describe "detect.ps1 (SCCM)" {
    BeforeAll {
        # Mirrored layout: walk up 4 levels from this test folder to the repository root.
        $repoRoot = (Get-Item (Join-Path $PSScriptRoot "../../../../")).FullName
        $scriptPath = Join-Path $repoRoot "scripts/endpoints/devices/sccm/detect.ps1"

        # Safe: the top-level guard skips Main when dot-sourced (docs/RELAUNCH-SPEC.md section 3).
        . $scriptPath

        # Get-Service is unavailable/unmockable directly on Linux pwsh; stub it so Pester
        # has a command surface to mock (docs/RELAUNCH-SPEC.md section 5).
        function Get-Service {
            # Full parameter signature so Pester can bind -Name for ParameterFilters.
            [CmdletBinding()]
            param([string]$Name)
            $null
        }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$') | Should -BeTrue
            ($raw -match '(?m)^\s*Date\s*:\s*2026-08-23\s*$') | Should -BeTrue
        }

        It "Declares File Name matching the on-disk filename" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match "(?m)^\s*File Name\s*:\s*detect\.ps1\s*$") | Should -BeTrue
        }

        It "Documents every declared parameter in declaration order (none declared)" {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $documented = @([regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
            $declared.Count | Should -Be 0
            $documented.Count | Should -Be 0
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
            ([regex]::Matches($raw, '(?m)\bexit\s*\(')).Count | Should -Be 1
        }
    }

    Context "Behavior" {
        It "Returns 0 when the CcmExec service is running" {
            Mock Write-Host { }
            Mock Get-Service { [pscustomobject]@{ Name = 'CcmExec'; Status = 'Running' } }
            Mock Test-Path { throw 'fallback must not run' }
            Main | Should -Be 0
            Should -Invoke Get-Service -Times 1 -Exactly -ParameterFilter { $Name -eq 'CcmExec' }
        }

        It "Falls back to the client data folder when the service is absent" {
            Mock Write-Host { }
            Mock Get-Service { $null }
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*CCM\ServiceData*' }
            Main | Should -Be 0
            Should -Invoke Test-Path -Times 1 -Exactly -ParameterFilter { $Path -like '*CCM\ServiceData*' }
        }

        It "Is idempotent on a converged device: returns 1 only as a documented detection result, changing nothing" {
            Mock Write-Host { }
            Mock Get-Service { $null }
            Mock Test-Path { $false }
            Main | Should -Be 1
        }

        It "Returns 1 with [-] prefixed output when detection throws" {
            Mock Write-Host { param($Object) $Object }
            Mock Get-Service { throw 'WMI broken' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
