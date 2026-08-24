#Requires -Modules Pester

Describe "Remove-USLanguagePack" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/infrastructure/windows/system/Remove-USLanguagePack.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Windows-only cmdlets are absent on Linux CI - define no-op stubs
        # so Pester has an existing command to attach each Mock to.
        foreach ($cmd in @('Get-WinSystemLocale', 'Get-WinUserLanguageList', 'Set-WinUserLanguageList',
                'Install-Language', 'Get-WindowsCapability', 'Remove-WindowsCapability',
                'Checkpoint-Computer', 'Enable-ComputerRestore', 'Restart-Computer')) {
            if (-not (Get-Command -Name $cmd -ErrorAction SilentlyContinue)) {
                . ([scriptblock]::Create("function script:$cmd { }"))
            }
        }

        # Mock platform/external seams so nothing leaves the machine.
        Mock -CommandName Test-AdminPrivilege { $true }
        Mock -CommandName Get-Culture { [pscustomobject]@{ Name = "en-GB" } }
        Mock -CommandName Get-WinSystemLocale { [pscustomobject]@{ Name = "en-GB" } }
        Mock -CommandName Set-WinUserLanguageList { }
        Mock -CommandName Install-Language { }
        Mock -CommandName Invoke-DismCapture {
            param($ArgumentList)
            if ($ArgumentList -contains '/Get-Intl') {
                return [pscustomobject]@{ ExitCode = 0; Output = "Installed language: en-US" }
            }
            return [pscustomobject]@{ ExitCode = 0; Output = "The operation completed successfully." }
        }
        Mock -CommandName Invoke-LpkSetup { 0 }
        Mock -CommandName Get-WindowsCapability { @() }
        Mock -CommandName Remove-WindowsCapability { }
        Mock -CommandName Test-Path { $false }
        Mock -CommandName Get-ItemProperty { $null }
        Mock -CommandName Set-ItemProperty { }
        Mock -CommandName Remove-Item { }
        Mock -CommandName Out-File { }
        Mock -CommandName Start-Sleep { }

        function New-FakeLanguage([string]$Tag) {
            $obj = [pscustomobject]@{ LanguageTag = $Tag }
            $tips = [System.Collections.Generic.List[string]]@("0409:00000409", "0809:00000809")
            $obj | Add-Member -NotePropertyName InputMethodTips -NotePropertyValue $tips
            return $obj
        }
    }

    Context "Help & Metadata" {
        It "Declares the required header fields with relaunch values" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            $text | Should -Match '\.SYNOPSIS'
            $text | Should -Match '\.DESCRIPTION'
            $text | Should -Match 'File Name:\s*Remove-USLanguagePack\.ps1'
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
        It "Is idempotent: en-US already absent exits 0 with no changes" {
            Mock -CommandName Get-WinUserLanguageList { @(New-FakeLanguage "en-GB") }

            $out = Main -Force *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'nothing to remove'
            Should -Invoke Set-WinUserLanguageList -Times 0 -Exactly -Because "en-US was never installed"
            Should -Invoke Invoke-DismCapture -Times 0 -Exactly
        }

        It "Removes en-US when both en-GB and en-US are installed, returns 0" {
            $script:listCalls = 0
            Mock -CommandName Get-WinUserLanguageList {
                $script:listCalls++
                if ($script:listCalls -le 2) { return @(New-FakeLanguage "en-US"; New-FakeLanguage "en-GB") }
                return @(New-FakeLanguage "en-GB")
            }

            $out = Main -Force *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Set-WinUserLanguageList -Times 2 -Exactly
            Should -Invoke Invoke-DismCapture -Times 2 -Exactly
        }

        It "Returns 1 with [-] output when en-GB is missing and -Force is set" {
            Mock -CommandName Get-WinUserLanguageList { @(New-FakeLanguage "en-US") }

            $out = Main -Force *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
