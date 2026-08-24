#Requires -Modules Pester

Describe "Get-MySQLHealth" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/data/databases/ -> script is two levels up + across.
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/data/databases/Get-MySQLHealth.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        # Mandatory params must be bound explicitly or dot-sourcing would prompt.
        . $scriptPath -Server localhost -Username root

        # Mock ALL externals. The native mysql CLI is reachable ONLY through the
        # Invoke-MySqlCommand wrapper (the mock seam); never mock mysql by name.
        Mock Get-Command { [pscustomobject]@{ Name = 'mysql'; Source = '/usr/bin/mysql' } } `
            -ParameterFilter { $Name -eq 'mysql' }
        Mock Invoke-MySqlCommand { '8.0.36' } -ParameterFilter { $ArgumentList -contains 'SELECT VERSION();' }
        Mock Invoke-MySqlCommand { "Uptime 7200`nThreads_connected 12" } `
            -ParameterFilter { $ArgumentList -contains 'SHOW GLOBAL STATUS;' }
        Mock Invoke-MySqlCommand { @('mysql', 'information_schema', 'appdb') } `
            -ParameterFilter { $ArgumentList -contains 'SHOW DATABASES;' }
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
        It "Returns 0 and reports version, uptime, and database count on a healthy server" {
            $out = Main *>&1
            $text = $out | Out-String
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text | Should -Match '\[\*\] Connecting to MySQL server: localhost:3306'
            $text | Should -Match '\[\+\] MySQL Version: 8\.0\.36'
            $text | Should -Match '\[\+\] Uptime: 2 hours, Connections: 12'
            $text | Should -Match '\[\+\] Found 3 databases'
            Should -Invoke Invoke-MySqlCommand -Times 3 -Exactly -Because 'version, status, and databases queries only'
        }

        It "Queries replication when -CheckReplication is set and warns when not a replica" {
            $CheckReplication = $true
            Mock Invoke-MySqlCommand { $null } -ParameterFilter { $ArgumentList -contains 'SHOW REPLICA STATUS\G' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\!\] Replication not configured or not a replica'
            Should -Invoke Invoke-MySqlCommand -Times 4 -Exactly
        }

        It "Returns 1 and writes [-] prefixed output when the mysql client is missing" {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'mysql' }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
            Should -Invoke Invoke-MySqlCommand -Times 0 -Exactly -Because 'the guard must abort before any query'
        }

        It "Returns 1 and writes [-] prefixed output when the mysql wrapper reports failure" {
            # Same-filter overrides required: a later unfiltered mock loses to earlier filtered ones.
            # Throw so Main's catch block produces the [-] prefixed error output.
            Mock Invoke-MySqlCommand { throw 'mysql exited with code 1' } `
                -ParameterFilter { $ArgumentList -contains 'SELECT VERSION();' }
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
