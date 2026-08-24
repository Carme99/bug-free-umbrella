#Requires -Modules Pester

Describe "Get-SecurityEventAudit" {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../../../..')
        $scriptPath = Join-Path $repoRoot 'scripts/infrastructure/windows/security/Get-SecurityEventAudit.ps1'
        . $scriptPath
        $helpText = Get-Content -Raw $scriptPath
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)

        # Stub Windows-only commands absent on Linux so Pester can attach mocks.
        foreach ($stub in @('Get-WinEvent')) {
            if (-not (Get-Command $stub -ErrorAction SilentlyContinue)) {
                Invoke-Expression "function $stub { }"
            }
        }


        # Default: no events found anywhere (offline, no event log access)
        Mock -CommandName Get-WinEvent { @() }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date" {
            $helpText | Should -Match 'Version\s*:\s*1\.0\.0'
            $helpText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Declares matching File Name, Author and Prerequisite" {
            $helpText | Should -Match ('File Name\s*:\s*' + [regex]::Escape('Get-SecurityEventAudit.ps1'))
            $helpText | Should -Match 'Author\s*:\s*\S+'
            $helpText | Should -Match 'Prerequisite\s*:\s*PowerShell'
        }

        It "Has one .PARAMETER entry per declared parameter, in order" {
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $documented = @([regex]::Matches($helpText, '(?m)^\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value })
            $documented | Should -Be $declared
        }

        It "Has SYNOPSIS, DESCRIPTION and at least two PS C:\> examples" {
            $helpText | Should -Match '(?m)^\.SYNOPSIS'
            $helpText | Should -Match '(?m)^\.DESCRIPTION'
            ([regex]::Matches($helpText, '(?m)^    PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It "Contains no PS7-only syntax without a #Requires -Version 7.0 opt-in" {
            if ($helpText -notmatch '(?m)^#Requires\s+-Version\s+7') {
                $helpText | Should -Not -Match '(\?\?=)|(\?\?)|&&|(\|\|)'
            }
        }
    }

    Context "Behavior" {
        It "Returns 0 with [+] output when no security events are found" {
            Mock -CommandName Get-WinEvent { @() }

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            $text | Should -Match '\[\+\] Audit completed'
            Should -Invoke Get-WinEvent -Times 6 -Exactly -Because "All mode queries six categories"
        }

        It "Returns 1 with [!] threshold-violation output when events exceed the threshold" {
            $fakeEvents = @(
                [PSCustomObject]@{
                    Id = 4625
                    TimeCreated = (Get-Date)
                    MachineName = 'SRV01'
                    Message = 'An account failed to log on'
                    Properties = @(1, 2, 3, 4, 5, 'attacker')
                }
            )
            Mock -CommandName Get-WinEvent { $fakeEvents }
            $Threshold = 0   # any single event trips the alert

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 1
            $text | Should -Match '\[!\]'
            $text | Should -Match 'threshold violations detected'
        }

        It "Is idempotent: repeated read-only audits succeed identically" {
            Mock -CommandName Get-WinEvent { @() }
            (Main) | Should -Be 0
            (Main) | Should -Be 0
        }
    }
}
