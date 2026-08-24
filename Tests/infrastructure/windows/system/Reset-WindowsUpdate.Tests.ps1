#Requires -Modules Pester

Describe "Reset-WindowsUpdate" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/infrastructure/windows/system/Reset-WindowsUpdate.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Windows-only cmdlets are absent on Linux CI - define no-op stubs
        # so Pester has an existing command to attach each Mock to.
        foreach ($cmd in @('Get-CimInstance', 'Stop-Service', 'Start-Service')) {
            if (-not (Get-Command -Name $cmd -ErrorAction SilentlyContinue)) {
                . ([scriptblock]::Create("function script:$cmd { }"))
            }
        }

        # Mock platform/external seams so nothing leaves the machine.
        Mock -CommandName Test-AdminPrivilege { $true }
        Mock -CommandName Get-CimInstance { [pscustomobject]@{ Caption = "Microsoft Windows Server 2022" } }
        Mock -CommandName Stop-Service { }
        Mock -CommandName Start-Service { }
        Mock -CommandName Test-Path { $true }
        Mock -CommandName Remove-Item { }
        Mock -CommandName Invoke-DismRepair { 0 }
        Mock -CommandName Invoke-SfcScan { 0 }
        Mock -CommandName Invoke-RegSvr32 { 0 }
        Mock -CommandName New-Object { throw "COM unavailable in test environment" }
    }

    Context "Help & Metadata" {
        It "Declares the required header fields with relaunch values" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            $text | Should -Match '\.SYNOPSIS'
            $text | Should -Match '\.DESCRIPTION'
            $text | Should -Match 'File Name:\s*Reset-WindowsUpdate\.ps1'
            $text | Should -Match 'Version:\s*1\.0\.0'
            $text | Should -Match 'Date:\s*2026-08-23'
            $text | Should -Match 'Prerequisite:\s*PowerShell'
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
        It "Runs the legacy reset path and returns 0 when native wrappers succeed" {
            $out = Main -LegacyReset *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Invoke-RegSvr32 -Times 36 -Exactly
            Should -Invoke Invoke-DismRepair -Times 0 -Exactly
            Should -Invoke Remove-Item -Times 1
        }

        It "Is idempotent-safe: -WhatIf performs no mutations and exits 0" {
            $out = Main -FullReset -WhatIf *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Remove-Item -Times 0 -Exactly -Because "-WhatIf must not delete anything"
            Should -Invoke Stop-Service -Times 0 -Exactly -Because "-WhatIf must not stop services"
            Should -Invoke Invoke-DismRepair -Times 0 -Exactly -Because "-WhatIf must not run DISM"
        }

        It "Returns 1 with [-] prefixed error output when privileges are missing" {
            Mock -CommandName Test-AdminPrivilege { $false }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
