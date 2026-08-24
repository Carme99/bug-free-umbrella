#Requires -Modules Pester

Describe "Test-CISBenchmark" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/security/compliance/frameworks/Test-CISBenchmark.ps1"
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        Mock Test-AdministratorElevation { $true }

        $compliantIni = @"
[Unicode]
Unicode=yes
[System Access]
PasswordHistorySize = 24
MaximumPasswordAge = 90
MinimumPasswordAge = 1
MinimumPasswordLength = 14
PasswordComplexity = 1
ClearTextPassword = 0
LockoutDuration = 15
LockoutBadCount = 5
ResetLockoutCount = 15
"@

        Mock Invoke-SeceditExport {
            param([string]$ConfigFile)
            Set-Content -LiteralPath $ConfigFile -Value $compliantIni
            return 0
        }

        Mock Invoke-AuditPolicyQuery {
            [pscustomobject]@{
                Output   = @(
                    "Machine Name,SecPol-Test",
                    "System Audit Policy",
                    "   Credential Validation                     Success and Failure",
                    "   Application Group Management              Success and Failure",
                    "   Process Creation                          Success",
                    "   Account Lockout                           Failure",
                    "   Logoff                                    Success",
                    "   Logon                                     Success and Failure",
                    "   Sensitive Privilege Use                   Success and Failure",
                    "   Security System Extension                 Success"
                )
                ExitCode = 0
            }
        }
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
        It "Returns 0 and is idempotent when every applicable control passes" {
            Main | Should -Be 0
            Should -Invoke Invoke-SeceditExport -Times 1 -Exactly -Scope It

            # Re-run on the already-converged state must still succeed with exit code 0
            Main | Should -Be 0
        }

        It "Returns exit code 1 when a control fails" {
            $nonCompliantIni = $compliantIni -replace 'PasswordHistorySize = 24', 'PasswordHistorySize = 10'
            Mock Invoke-SeceditExport {
                param([string]$ConfigFile)
                Set-Content -LiteralPath $ConfigFile -Value $nonCompliantIni
                return 0
            }

            Main | Should -Be 1
        }

        It "Returns exit code 1 and writes [-] prefixed output when secedit fails" {
            Mock Invoke-SeceditExport { return 1 }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Gates temporary policy file deletion behind ShouldProcess" {
            Mock Remove-Item { }
            # Fail fast AFTER producing the export file so the finally-block cleanup has work to do
            Mock Invoke-SeceditExport {
                param([string]$ConfigFile)
                Set-Content -LiteralPath $ConfigFile -Value $compliantIni
                return 1
            }

            # With -WhatIf the temp file cleanup must NOT run
            Main -WhatIf | Should -Be 1
            Should -Invoke Remove-Item -Times 0 -Exactly -Because "-WhatIf suppresses the temp file delete"

            # Without -WhatIf the temp file cleanup runs exactly once per policy export
            Mock Remove-Item { }
            Main | Should -Be 1
            Should -Invoke Remove-Item -Times 1 -Exactly
        }
    }
}
