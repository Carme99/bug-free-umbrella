#Requires -Modules Pester

Describe "Get-PostgreSQLHealth" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/data/databases/ -> script is two levels up + across.
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/data/databases/Get-PostgreSQLHealth.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        # Mandatory params must be bound explicitly or dot-sourcing would prompt.
        . $scriptPath -Server localhost -Username postgres

        # Mock ALL externals. The native psql CLI is reachable ONLY through the
        # Invoke-PsqlCommand wrapper (the mock seam); never mock psql by name.
        Mock Get-Command { [pscustomobject]@{ Name = 'psql'; Source = '/usr/bin/psql' } } `
            -ParameterFilter { $Name -eq 'psql' }
        Mock Read-Host { ConvertTo-SecureString 'test-password' -AsPlainText -Force } `
            -ParameterFilter { $Prompt -eq 'Enter password' }
        Mock Invoke-PsqlCommand { 'PostgreSQL 16.2 (Debian 16.2-1.pgdg120+1)' } `
            -ParameterFilter { $ArgumentList -contains 'SELECT version();' }
        Mock Invoke-PsqlCommand { '15' } `
            -ParameterFilter { $ArgumentList -contains 'SELECT count(*) FROM pg_database;' }
        Mock Invoke-PsqlCommand { '8' } `
            -ParameterFilter { $ArgumentList -contains 'SELECT count(*) FROM pg_stat_activity;' }
        Mock Invoke-PsqlCommand { '0' } -ParameterFilter { ($ArgumentList -join ' ') -match 'query_start' }
    }

    AfterEach {
        Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    }

    Context "Help & Metadata" {
        BeforeAll {
            $raw = Get-Content -Raw $scriptPath
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
            $paramCount = $ast.ParamBlock.Parameters.Count
            $paramHelpCount = ([regex]::Matches($raw, '(?m)^\.PARAMETER')).Count
        }

        It "Declares Version 1.0.0 and relaunch Date 2026-08-23 in .NOTES" {
            $raw | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
            $raw | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
        }

        It "Populates File Name matching the disk filename and an Author" {
            $raw | Should -Match "(?m)^\s*File Name\s*:\s*$(Split-Path $scriptPath -Leaf)"
            $raw | Should -Match '(?m)^\s*Author\s*:'
        }

        It "Has one .PARAMETER entry per declared parameter" {
            $paramHelpCount | Should -Be $paramCount
        }

        It "Has SYNOPSIS, DESCRIPTION, and at least two .EXAMPLE blocks with PS C:\> prompts" {
            $raw | Should -Match '(?m)^\.SYNOPSIS'
            $raw | Should -Match '(?m)^\.DESCRIPTION'
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        BeforeAll {
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errors)
            $raw = Get-Content -Raw $scriptPath
        }

        It "Parses via the PowerShell parser with zero errors" {
            $errors | Should -BeNullOrEmpty
        }

        It "Contains exactly one exit statement: the top-level dot-source guard" {
            $exits = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ExitStatementAst] }, $true)
            $exits.Count | Should -Be 1
            $expectedLastLine = ($raw.TrimEnd() -split "`r`n|`n").Count
            $exits[0].Extent.StartLineNumber | Should -Be $expectedLastLine
            $exits[0].Extent.Text | Should -Match 'Main'
        }

        It "Avoids PS7-only syntax (no #Requires -Version 7.0 opt-out is used)" {
            ($raw -match '\|\||&&|\?\?') | Should -BeFalse
            ($raw -match '-Parallel\b|-AsHashtable\b') | Should -BeFalse
            ($raw -match '(?m)^#Requires\s+-Version\s+7') | Should -BeFalse
        }
    }

    Context "Behavior" {
        It "Returns 0 and reports version, databases, and connections on a healthy server" {
            $out = Main *>&1
            $text = $out | Out-String
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text | Should -Match '\[\*\] Connecting to PostgreSQL: localhost:5432/postgres'
            $text | Should -Match '\[\+\] PostgreSQL Version: PostgreSQL 16\.2'
            $text | Should -Match '\[\+\] Total databases: 15'
            $text | Should -Match '\[\+\] Active connections: 8'
            Should -Invoke Invoke-PsqlCommand -Times 4 -Exactly `
                -Because 'version, db stats, connections, and long-query checks only'
        }

        It "Exports the SecureString password to PGPASSWORD for the psql child process" {
            $null = Main *>&1
            $env:PGPASSWORD | Should -Be 'test-password'
        }

        It "Warns with [!] when long-running queries are detected" {
            Mock Invoke-PsqlCommand { '3' } -ParameterFilter { ($ArgumentList -join ' ') -match 'query_start' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\!\] Warning: 3 long-running queries detected'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 and writes [-] prefixed output when the psql client is missing" {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'psql' }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
            Should -Invoke Invoke-PsqlCommand -Times 0 -Exactly -Because 'the guard must abort before any query'
        }

        It "Returns 1 and writes [-] prefixed output when the psql wrapper reports failure" {
            Mock Invoke-PsqlCommand { throw 'psql exited with code 1' } `
                -ParameterFilter { $ArgumentList -contains 'SELECT version();' }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Is idempotent: repeated healthy runs are read-only and both return 0" {
            $first = (Main *>&1) | Where-Object { $_ -is [int] }
            $second = (Main *>&1) | Where-Object { $_ -is [int] }
            $first | Should -Be 0
            $second | Should -Be 0
        }
    }
}
