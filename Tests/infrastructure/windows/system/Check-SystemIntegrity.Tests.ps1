#Requires -Modules Pester

Describe "Check-SystemIntegrity" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/infrastructure/windows/system/Check-SystemIntegrity.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Windows-only cmdlets are absent on Linux CI - define no-op stubs
        # so Pester has an existing command to attach each Mock to.
        foreach ($cmd in @('Get-CimInstance', 'Get-Volume', 'Get-WinEvent')) {
            if (-not (Get-Command -Name $cmd -ErrorAction SilentlyContinue)) {
                . ([scriptblock]::Create("function script:$cmd { }"))
            }
        }

        # Mock platform/external seams so nothing leaves the machine.
        Mock -CommandName Test-AdminPrivilege { $true }
        Mock -CommandName Get-CimInstance {
            [pscustomobject]@{ Caption = "Microsoft Windows Server 2022"; Version = "10.0.20348" }
        }
        Mock -CommandName Start-Sleep { }
        Mock -CommandName Invoke-Sfc { [pscustomobject]@{ ExitCode = 0; Output = "" } }
        Mock -CommandName Invoke-Dism {
            [pscustomobject]@{ ExitCode = 0; Output = "No component store corruption detected." }
        }
        Mock -CommandName Invoke-Fsutil { [pscustomobject]@{ ExitCode = 0; Output = "Volume - Dirty Bit NOT Set" } }
        Mock -CommandName Get-Volume { @([pscustomobject]@{ DriveLetter = "C"; FileSystem = "NTFS" }) }
        Mock -CommandName Get-WinEvent { @() }
        Mock -CommandName Test-Path { $false }
        Mock -CommandName Out-File { }
        Mock -CommandName New-Item { }
    }

    Context "Help & Metadata" {
        It "Declares the required header fields with relaunch values" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            $text | Should -Match '\.SYNOPSIS'
            $text | Should -Match '\.DESCRIPTION'
            $text | Should -Match 'File Name:\s*Check-SystemIntegrity\.ps1'
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

        It "Uses 4-space indent, max 120 columns and no trailing whitespace" {
            $lines = Get-Content -LiteralPath $scriptPath
            $bad = @($lines | Where-Object { $_ -match '`t' -or $_ -match '\s$' -or $_.Length -gt 120 })
            $bad | Should -BeNullOrEmpty
        }
    }

    Context "Behavior" {
        It "Completes a quick scan and returns 0 using native wrappers" {
            $out = Main -QuickScan *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Invoke-Sfc -Times 1 -Exactly
            Should -Invoke Invoke-Dism -Times 1 -Exactly
        }

        It "Is idempotent-safe: -WhatIf triggers no mutations and exits 0" {
            $out = Main -AutoRepair -GenerateReport -WhatIf *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Out-File -Times 0 -Exactly -Because "-WhatIf must not write reports"
            Should -Invoke New-Item -Times 0 -Exactly -Because "-WhatIf must not create directories"
        }

        It "Returns 1 with [-] prefixed error output when privileges are missing" {
            Mock -CommandName Test-AdminPrivilege { $false }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
