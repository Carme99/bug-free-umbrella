#Requires -Modules Pester

Describe "Get-SQLServerHealth" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/data/databases/ -> script is two levels up + across.
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/data/databases/Get-SQLServerHealth.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        # All parameters are optional, so no binding is required here.
        . $scriptPath

        # Mock the SQL seam: Invoke-SqlQuery is a top-level script function, so Pester
        # can intercept every query. Keep writes off $HOME by stubbing the report dir.
        Mock Invoke-SqlQuery {
            [pscustomobject]@{
                ServerName    = 'SQL01'
                Version       = '15.0.4298.2'
                ProductLevel  = 'CU12'
                Edition       = 'Developer Edition (64-bit)'
                EngineEdition = 3
            }
        } -ParameterFilter { $Query -match 'SERVERPROPERTY' }
        Mock Invoke-SqlQuery {
            @([pscustomobject]@{
                    DatabaseName = 'AppDB'; Status = 'ONLINE'; RecoveryModel = 'FULL'
                    CompatLevel = 150; SizeMB = 1024.5
                })
        } -ParameterFilter { $Query -match 'state_desc' }
        Mock Invoke-SqlQuery {
            @([pscustomobject]@{ 'Database Name' = 'master'; 'Log Size (MB)' = 201.5; 'Log Space Used (%)' = 45.25 })
        } -ParameterFilter { $Query -match 'LOGSPACE' }
        Mock Invoke-SqlQuery { @() } -ParameterFilter { $Query -match 'sysjobhistory' }
        Mock Test-Path { $false }
        Mock New-Item { [pscustomobject]@{ FullName = '/fake/Reports' } }
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
        It "Returns 0 and reports a healthy server with zero issues" {
            $out = Main *>&1
            $text = $out | Out-String
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text | Should -Match '\[\+\] SQL Server: SQL01'
            $text | Should -Match '\[Pass\] AppDB: ONLINE \(1024\.5 MB\)'
            $text | Should -Match '\[Pass\] master: Log 45\.25% used'
            $text | Should -Match '\[\+\] No failed jobs in the last 7 days'
            $text | Should -Match '\[\+\] Health check completed!'
            Should -Invoke Invoke-SqlQuery -Times 4 -Exactly `
                -Because 'version, db status, log space, and job queries only'
        }

        It "Returns 1 when a database is OFFLINE (documented failure exit code)" {
            Mock Invoke-SqlQuery {
                @([pscustomobject]@{
                        DatabaseName = 'BrokenDB'; Status = 'OFFLINE'; RecoveryModel = 'FULL'
                        CompatLevel = 150; SizeMB = 10
                    })
            } -ParameterFilter { $Query -match 'state_desc' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[Fail\] BrokenDB: OFFLINE'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Validates backup age when -CheckBackups is set and fails on stale backups" {
            $CheckBackups = $true
            Mock Invoke-SqlQuery {
                @([pscustomobject]@{
                    DatabaseName        = 'AppDB'
                    LastFullBackup      = (Get-Date).AddDays(-30)
                    LastDiffBackup      = [DBNull]::Value
                    LastLogBackup       = [DBNull]::Value
                    DaysSinceFullBackup = 30
                })
            } -ParameterFilter { $Query -match 'backupset' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[Fail\] AppDB: Last backup 30 days ago'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            Should -Invoke Invoke-SqlQuery -Times 5 -Exactly -Because 'the backup query runs only with -CheckBackups'
        }

        It "Returns 1 and writes [-] prefixed output when queries fail" {
            Mock Invoke-SqlQuery { throw 'connection refused' } -ParameterFilter { $Query -match 'SERVERPROPERTY' }
            Mock Invoke-SqlQuery { throw 'connection refused' } -ParameterFilter { $Query -match 'state_desc' }
            Mock Invoke-SqlQuery { throw 'connection refused' } -ParameterFilter { $Query -match 'LOGSPACE' }
            Mock Invoke-SqlQuery { throw 'connection refused' } -ParameterFilter { $Query -match 'sysjobhistory' }
            $out = Main *>&1
            $text = $out | Out-String
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            $text | Should -Match '\[-\]'
            $text | Should -Match 'connection refused'
        }

        It "Is idempotent: repeated healthy runs succeed and both return 0" {
            $first = (Main *>&1) | Where-Object { $_ -is [int] }
            $second = (Main *>&1) | Where-Object { $_ -is [int] }
            $first | Should -Be 0
            $second | Should -Be 0
        }
    }
}
