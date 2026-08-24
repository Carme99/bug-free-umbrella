#Requires -Modules Pester

Describe "Get-MDEDeviceHealth" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/security/compliance/defender-endpoint/Get-MDEDeviceHealth.ps1"
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Prove no network ever leaves the machine: any Invoke-RestMethod call is a test failure.
        Mock Invoke-RestMethod { throw "Network access attempted during test" }
    }

    Context "Help & Metadata" {
        It "Has the required header fields" {
            $raw | Should -Match '(?m)^\.SYNOPSIS'
            $raw | Should -Match '(?m)^\.DESCRIPTION'
            $raw | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
            $raw | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
        }

        It "Has a File Name field matching the disk filename" {
            $fileName = Split-Path $scriptPath -Leaf
            $escaped = [regex]::Escape($fileName)
            $raw | Should -Match "(?m)^\s*File Name\s*:\s*$escaped\s*$"
        }

        It "Declares one .PARAMETER block per declared parameter, in order" {
            $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errs)
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $documented = @([regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })

            $documented.Count | Should -Be $declared.Count
            for ($i = 0; $i -lt $declared.Count; $i++) {
                $documented[$i] | Should -Be $declared[$i]
            }
        }

        It "Does NOT declare TenantId as mandatory (dot-sourcing must stay safe)" {
            $raw | Should -Not -Match '\[Parameter\(Mandatory\s*=\s*\$true\)\][\s\S]{0,120}\[string\]\$TenantId'
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $errs = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errs) | Out-Null
            $errs | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only operator tokens" {
            $tokens = $null
            $errs = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errs) | Out-Null
            $ps7Only = @($tokens | Where-Object { $_.Text -in @('&&', '||', '??', '??=') })
            $ps7Only | Should -BeNullOrEmpty
        }

        It "Declares SupportsShouldProcess (destructive-capable compliance scanner)" {
            $raw | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
        }
    }

    Context "Behavior" {
        It "Returns exit code 1 and writes [-] output when -TenantId is missing" {
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Out-String) | Should -Match '-TenantId is required'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Writes a JSON report under OutputPath and never touches the network" {
            $reportDir = Join-Path $TestDrive 'mde-json'

            Main -TenantId '00000000-1111-2222-3333-444444444444' `
                -OutputFormat JSON -OutputPath $reportDir | Should -Be 0

            @(Get-ChildItem -LiteralPath $reportDir -Filter '*.json').Count | Should -Be 1
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly -Because "the framework template makes no API calls"
        }

        It "Writes an HTML report under OutputPath without any network access" {
            $reportDir = Join-Path $TestDrive 'mde-html'

            Main -TenantId '00000000-1111-2222-3333-444444444444' `
                -OutputFormat HTML -OutputPath $reportDir | Should -Be 0

            @(Get-ChildItem -LiteralPath $reportDir -Filter '*.html').Count | Should -Be 1
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly -Because "the framework template makes no API calls"
        }
    }
}
