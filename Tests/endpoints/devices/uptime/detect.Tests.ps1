#Requires -Modules Pester

Describe "detect.ps1 (uptime)" {
    BeforeAll {
        # Mirrored layout: walk up 4 levels from this test folder to the repository root.
        $repoRoot = (Get-Item (Join-Path $PSScriptRoot "../../../../")).FullName
        $scriptPath = Join-Path $repoRoot "scripts/endpoints/devices/uptime/detect.ps1"

        # Safe: the top-level guard skips Main when dot-sourced (docs/RELAUNCH-SPEC.md section 3).
        . $scriptPath

        # Get-ComputerInfo is Windows-bound; stub it so Pester has a command surface to
        # mock (docs/RELAUNCH-SPEC.md section 5).
        function Get-ComputerInfo {
            [CmdletBinding()]
            param()
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
            $raw = Get-Content -Path $scriptPath -Raw
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
        It "Returns 1 with [!] output when the device has not been restarted for 4+ days" {
            Mock Write-Host { param($Object) $Object }
            Mock Get-ComputerInfo { [pscustomobject]@{ OsUptime = [timespan]::FromDays(6) } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 0 when the device was restarted within the last 4 days" {
            Mock Write-Host { }
            Mock Get-ComputerInfo { [pscustomobject]@{ OsUptime = [timespan]::FromDays(2) } }
            Main | Should -Be 0
        }

        It "Treats exactly 3 days of uptime as compliant (boundary)" {
            Mock Write-Host { }
            Mock Get-ComputerInfo { [pscustomobject]@{ OsUptime = [timespan]::FromDays(3) } }
            Main | Should -Be 0
        }

        It "Defaults to compliant (exit 0) when uptime cannot be determined" {
            Mock Write-Host { param($Object) $Object }
            Mock Get-ComputerInfo { throw 'WMI unavailable' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }
    }
}
