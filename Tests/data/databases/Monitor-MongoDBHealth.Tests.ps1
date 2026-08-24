#Requires -Modules Pester

Describe "Monitor-MongoDBHealth" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/data/databases/ -> script is two levels up + across.
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/data/databases/Monitor-MongoDBHealth.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        # All parameters are optional, so no binding is required here.
        . $scriptPath
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

        It "Populates File Name matching the disk filename and preserves the original Author" {
            $raw | Should -Match "(?m)^\s*File Name\s*:\s*$(Split-Path $scriptPath -Leaf)"
            $raw | Should -Match '(?m)^\s*Author\s*:\s*IT Operations'
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
        It "Writes a template JSON into OutputPath and returns 0 without touching MongoDB" {
            $OutputPath = Join-Path $TestDrive 'mongo-out'
            $out = Main *>&1
            $text = $out | Out-String
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text | Should -Match '\[\*\] Monitoring MongoDB: localhost:27017'
            $text | Should -Match '\[\+\] Template JSON saved'
            $jsonFiles = Get-ChildItem $OutputPath -Filter *.json
            $jsonFiles.Count | Should -Be 1
            ($jsonFiles[0] | Get-Content -Raw | ConvertFrom-Json).Server | Should -Be 'localhost'
        }

        It "Builds an authenticated connection string when -Credential is supplied" {
            $OutputPath = Join-Path $TestDrive 'mongo-cred'
            $Credential = [pscredential]::new('admin', (ConvertTo-SecureString 's3cret' -AsPlainText -Force))
            $out = Main *>&1
            $text = $out | Out-String
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text | Should -Not -Match 's3cret' -Because 'the password must never be echoed to output'
            (Get-ChildItem $OutputPath -Filter *.json).Count | Should -Be 1
        }

        It "Returns 1 and writes [-] prefixed output on unsafe '..' traversal in OutputPath" {
            $OutputPath = Join-Path $TestDrive '../escape'
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Is idempotent: repeated runs succeed and produce a fresh timestamped report each time" {
            $OutputPath = Join-Path $TestDrive 'mongo-rerun'
            $first = (Main *>&1) | Where-Object { $_ -is [int] }
            $second = (Main *>&1) | Where-Object { $_ -is [int] }
            $first | Should -Be 0
            $second | Should -Be 0
            (Get-ChildItem $OutputPath -Filter *.json).Count | Should -Be 2
        }
    }
}
