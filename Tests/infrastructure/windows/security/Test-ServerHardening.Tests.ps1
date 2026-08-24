#Requires -Modules Pester

Describe "Test-ServerHardening" {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../../../..')
        $scriptPath = Join-Path $repoRoot 'scripts/infrastructure/windows/security/Test-ServerHardening.ps1'
        . $scriptPath
        $helpText = Get-Content -Raw $scriptPath
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)

        # Stub Windows-only commands absent on Linux so Pester can attach mocks.
        $stubCmds = @(
            'Get-SmbServerConfiguration', 'Get-MpComputerStatus', 'Get-CimInstance',
            'Get-LocalUser', 'Get-Service'
        )
        foreach ($stub in $stubCmds) {
            if (-not (Get-Command $stub -ErrorAction SilentlyContinue)) {
                Invoke-Expression "function $stub { }"
            }
        }


        # All-pass baseline mocks (Windows-only surface, mocked offline)
        Mock -CommandName Get-SmbServerConfiguration {
            [PSCustomObject]@{
                EnableSMB1Protocol = $false
                EncryptData = $true
                RequireSecuritySignature = $true
            }
        }
        Mock -CommandName Get-ItemProperty {
            [PSCustomObject]@{
                EnableScriptBlockLogging = 1
                EnableTranscripting = 1
                RunAsPPL = 1
                UserAuthentication = 1
                MinEncryptionLevel = 4
            }
        }
        Mock -CommandName Get-MpComputerStatus {
            [PSCustomObject]@{
                AntivirusEnabled = $true
                RealTimeProtectionEnabled = $true
                AntivirusSignatureLastUpdated = (Get-Date)
            }
        }
        Mock -CommandName Get-CimInstance { [PSCustomObject]@{ SecurityServicesRunning = @(1) } }
        Mock -CommandName Invoke-Secedit { 0 }
        Mock -CommandName Get-Content { @("MinimumPasswordLength = 14", "LockoutBadCount = 10") }
        Mock -CommandName Get-Service { $null }
        Mock -CommandName Get-LocalUser { [PSCustomObject]@{ Enabled = $false } }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date" {
            $helpText | Should -Match 'Version\s*:\s*1\.0\.0'
            $helpText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Declares matching File Name, Author and Prerequisite" {
            $helpText | Should -Match ('File Name\s*:\s*' + [regex]::Escape('Test-ServerHardening.ps1'))
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
        It "Returns 0 and reports success when all controls pass" {
            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            $text | Should -Match '\[\+\] Hardening check completed'
        }

        It "Returns 1 with [-] output when a control fails" {
            Mock -CommandName Get-SmbServerConfiguration {
                [PSCustomObject]@{
                    EnableSMB1Protocol = $true   # SMBv1 enabled -> failed control
                    EncryptData = $true
                    RequireSecuritySignature = $true
                }
            }

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 1
            $text | Should -Match '\[-\]'
        }

        It "Is idempotent: repeated read-only runs succeed identically" {
            (Main) | Should -Be 0
            (Main) | Should -Be 0
        }

        It "Queries every hardening category through mocked externals" {
            $null = Main
            Should -Invoke Get-SmbServerConfiguration -Times 1 -Exactly
            Should -Invoke Invoke-Secedit -Times 1 -Exactly
            Should -Invoke Get-MpComputerStatus -Times 1 -Exactly
        }
    }
}
