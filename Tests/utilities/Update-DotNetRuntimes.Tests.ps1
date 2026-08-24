#Requires -Modules Pester

Describe "Update-DotNetRuntimes" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/utilities/ -> repo root is two levels up.
        $scriptPath = Join-Path $PSScriptRoot "../../scripts/utilities/Update-DotNetRuntimes.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Default mocks: nothing leaves the machine, nothing mutates the system.
        # Native exes are mocked via their wrapper functions, never by name.
        Mock Test-Admin { $true }
        Mock Initialize-NetworkSecurityProtocol { }
        Mock Get-ReleasesIndex { [PSCustomObject]@{ 'releases-index' = @() } }
        Mock Get-SystemStatus {
            [PSCustomObject]@{
                ComputerName    = 'CI'
                IsAdmin         = $true
                HasDotnetX64    = $false
                HasDotnetX86    = $false
                HasUninstallTool = $false
                IisInstalled    = $false
                AncmInstalled   = $false
                IisSiteCount    = 0
                AspNetGroups    = @()
                DesktopGroups   = @()
                TotalDiskUsage  = 0
                ReclaimableDisk = 0
                EolChannels     = @()
            }
        }
        Mock Save-FileWithRetry { }
        Mock Install-Exe { }
        Mock Invoke-TrackedProcess { [PSCustomObject]@{ ExitCode = 0; TimedOut = $false } }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0, relaunch Date, File Name, and Prerequisite in NOTES" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match 'Version\s*:\s*1\.0\.0'
            $raw | Should -Match 'Date\s*:\s*2026-08-23'
            $raw | Should -Match 'File Name\s*:\s*Update-DotNetRuntimes\.ps1'
            $raw | Should -Match 'Prerequisite\s*:\s*PowerShell'
        }

        It "Has an imperative one-line SYNOPSIS within 120 characters" {
            $raw = Get-Content -Raw $scriptPath
            $synopsis = ([regex]::Match($raw, '(?m)^\.SYNOPSIS\r?\n\s*(.+)$')).Groups[1].Value.Trim()
            $synopsis | Should -Not -BeNullOrEmpty
            $synopsis.Length | Should -BeLessOrEqual 120
            $synopsis | Should -Match '^[A-Z]'
        }

        It "Declares exactly one .PARAMETER block per declared parameter, in order" {
            $raw = Get-Content -Raw $scriptPath
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$errors)
            $declared = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $helpParams = [regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)')
            $helpParams.Count | Should -Be $declared.Count
            for ($i = 0; $i -lt $declared.Count; $i++) {
                $helpParams[$i].Groups[1].Value | Should -Be $declared[$i]
            }
        }

        It "Contains at least two EXAMPLE blocks with PS C:\> prompt lines" {
            $raw = Get-Content -Raw $scriptPath
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE\b')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses cleanly via the PowerShell parser" {
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$null, [ref]$errors) | Out-Null
            $errors.Count | Should -Be 0
        }

        It "Uses no PS7-only syntax (no #Requires -Version 7.0 opt-out present)" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Not -Match '(?m)^#Requires\s+-Version\s+7\.0'
            foreach ($token in @('&&', '||', '??', '-Parallel', '-AsHashtable')) {
                ($raw -join '') | Should -Not -Match ([regex]::Escape($token))
            }
        }

        It "Is saved as UTF-8 with BOM and CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            $text | Should -Not -Match "(?<!`r)`n"
        }
    }

    Context "Behavior" {
        It "Returns 1 and writes [-] prefixed output when not running elevated" {
            Mock Test-Admin { $false }
            $NonInteractive = $true
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Plans only with PlanOnly: returns 0 and never downloads or installs" {
            $NonInteractive = $true
            $PlanOnly = $true
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Save-FileWithRetry -Times 0 -Exactly
            Should -Invoke Install-Exe -Times 0 -Exactly
            Should -Invoke Invoke-TrackedProcess -Times 0 -Exactly
            ($out | Out-String) | Should -Match '\[\*\]'
        }

        It "Is idempotent on a converged system: returns 0 with no changes attempted" {
            $NonInteractive = $true
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Save-FileWithRetry -Times 0 -Exactly -Because "no updates are pending"
            Should -Invoke Install-Exe -Times 0 -Exactly -Because "no updates are pending"
            Should -Invoke Invoke-TrackedProcess -Times 0 -Exactly
            ($out | Out-String) | Should -Match '\[\+\] Automated maintenance completed'
        }

        It "Returns 1 and writes [-] prefixed output when release index lookup fails" {
            Mock Get-ReleasesIndex { throw "offline: release index unreachable" }
            $NonInteractive = $true
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Out-String) | Should -Match 'offline'
        }
    }
}
