#Requires -Modules Pester

Describe "Optimize-WsusServer" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/infrastructure/windows/system/Optimize-WsusServer.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Windows-only cmdlets are absent on Linux CI - define no-op stubs
        # so Pester has an existing command to attach each Mock to.
        foreach ($cmd in @('Get-WsusClassification', 'Set-WsusClassification')) {
            if (-not (Get-Command -Name $cmd -ErrorAction SilentlyContinue)) {
                . ([scriptblock]::Create("function script:$cmd { }"))
            }
        }

        # Mock platform/external seams so nothing leaves the machine.
        # No WSUS/SQL/IIS modules are installed in CI - everything is mocked at command level.
        Mock -CommandName Test-AdminPrivilege { $true }
        # Keep Write-Log from creating log dirs; config load falls back to defaults.
        Mock -CommandName Test-Path { $true }
        Mock -CommandName Add-Content { }
        Mock -CommandName New-Item { }
        Mock -CommandName Get-Content { throw "no config file in test environment" } -ParameterFilter {
            $Path -like "*wsus-config*"
        }
        Mock -CommandName Get-WsusClassification {
            @(
                [pscustomobject]@{ Classification = [pscustomobject]@{ Title = "Drivers" } },
                [pscustomobject]@{ Classification = [pscustomobject]@{ Title = "Security Updates" } }
            )
        }
        Mock -CommandName Set-WsusClassification { }
    }

    Context "Help & Metadata" {
        It "Declares the required header fields with relaunch values" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            $text | Should -Match '\.SYNOPSIS'
            $text | Should -Match '\.DESCRIPTION'
            $text | Should -Match 'File Name:\s*Optimize-WsusServer\.ps1'
            $text | Should -Match 'Version:\s*1\.0\.0'
            $text | Should -Match 'Date:\s*2026-08-23'
            $text | Should -Match 'Prerequisite:\s*PowerShell 5\.1\+'
            $text | Should -Match 'Author:\s*\S'
        }

        It "Documents exactly the declared parameters in order" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            $helpParams = [regex]::Matches($text, '(?m)^\.PARAMETER\s+(\w+)') | ForEach-Object { $_.Groups[1].Value }
            $tokens = $null; $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declared = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
            $helpParams | Should -Be $declared
        }

        It "Provides at least two examples with PS C:\> prompts" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            ([regex]::Matches($text, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($text, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses cleanly" {
            $tokens = $null; $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only syntax without #Requires -Version 7.0" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            if ($text -notmatch '(?m)^#Requires\s+-Version\s+7') {
                $text | Should -Not -Match '\?\?'
                $text | Should -Not -Match '\|\|'
                $text | Should -Not -Match '&&'
                $text | Should -Not -Match '-Parallel'
            }
        }

        It "Uses no tabs, max 120 columns and no trailing whitespace" {
            $lines = Get-Content -LiteralPath $scriptPath
            $bad = @($lines | Where-Object { $_ -match '`t' -or $_ -match '\s$' -or $_.Length -gt 120 })
            $bad | Should -BeNullOrEmpty
        }
    }

    Context "Behavior" {
        It "Disables driver synchronization and returns 0 using defaults when config is missing" {
            $out = Main -DisableDrivers *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\].*Driver synchronization disabled'
            Should -Invoke Set-WsusClassification -Times 1 -Exactly -Because "only the Drivers classification matches"
        }

        It "Is idempotent-safe: -WhatIf mutates nothing and exits 0" {
            $out = Main -DisableDrivers -WhatIf *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Set-WsusClassification -Times 0 -Exactly -Because "-WhatIf must not change classifications"
        }

        It "Returns 1 with [-] output when the WSUS server cannot be reached" {
            Mock -CommandName Get-WsusServerInstance { throw "Cannot connect to WSUS" }

            $out = Main -OptimizeServer *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
