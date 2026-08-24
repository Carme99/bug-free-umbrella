#Requires -Modules Pester

Describe "Get-OpenPortScan" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/security/compliance/frameworks/Get-OpenPortScan.ps1"

        # Stub Windows-only cmdlets so Pester can attach mocks on Linux.
        function Get-NetTCPConnection { }
        function Get-NetUDPEndpoint { }

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
        $rawText = Get-Content -LiteralPath $scriptPath -Raw

        # Mock external commands so nothing touches the host network stack.
        Mock Get-NetTCPConnection { @() }
        Mock Get-NetUDPEndpoint { @() }
        Mock Get-Process { $null }
    }

    Context "Help & Metadata" {
        It "Declares required NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $rawText | Should -Match '(?m)^\.NOTES\r?$'
            $rawText | Should -Match 'Version\s*:\s*1\.0\.0'
            $rawText | Should -Match 'Date\s*:\s*2026-08-23'
            $rawText | Should -Match 'Prerequisite\s*:\s*PowerShell'
            $rawText | Should -Match 'Author\s*:\s*\S'
        }

        It "Matches the disk filename in File Name" {
            $fileName = Split-Path $scriptPath -Leaf
            $rawText | Should -Match ("File Name\s*:\s*" + [regex]::Escape($fileName))
        }

        It "Documents one .PARAMETER block per declared parameter" {
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errors)
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $helped = [regex]::Matches($rawText, '(?m)^\.PARAMETER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value }

            $declared.Count | Should -BeGreaterThan 0
            $helped.Count | Should -Be $declared.Count
            foreach ($name in $declared) {
                $helped | Should -Contain $name
            }
        }

        It "Provides at least two EXAMPLES with PS C:\> prompts" {
            $promptCount = ([regex]::Matches($rawText, 'PS C:\\>')).Count
            $promptCount | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero syntax errors" {
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$null, [ref]$parseErrors)
            @($parseErrors).Count | Should -Be 0
        }

        It "Contains no PS7-only operators without a 7.0 opt-out" {
            ($rawText -match '#Requires -Version 7\.0') | Should -BeFalse
            ($rawText -match '\?\?|\?\?=|&&|\|\|') | Should -BeFalse
        }

        It "Wraps the body in Main behind a dot-source guard" {
            $rawText | Should -Match '(?m)function Main\b'
            $rawText | Should -Match 'exit \(Main\)'
            ($rawText -match [regex]::Escape('InvocationName -ne')) | Should -BeTrue
        }
    }

    Context "Behavior" {
        It "Detects a high-risk listening port, flags recommendations, and returns documented code 1" {
            Mock Get-NetTCPConnection {
                @(
                    [pscustomobject]@{
                        LocalAddress = '0.0.0.0'
                        LocalPort = 3389
                        OwningProcess = 4242
                        State = 'Listen'
                    },
                    [pscustomobject]@{
                        LocalAddress = '127.0.0.1'
                        LocalPort = 5357
                        OwningProcess = 991
                        State = 'Listen'
                    }
                )
            }

            $out = Main *>&1
            $exitCode = $out | Where-Object { $_ -is [int] }
            $exitCode | Should -Be 1
            ($out -join "`n") | Should -Match 'High-risk ports detected'
            Should -Invoke Get-Process -Times 2 -Exactly
        }

        It "Is idempotent-safe: a converged low-risk system returns 0" {
            Mock Get-NetTCPConnection {
                @(
                    [pscustomobject]@{
                        LocalAddress = '127.0.0.1'
                        LocalPort = 5357
                        OwningProcess = 991
                        State = 'Listen'
                    }
                )
            }

            Main | Should -Be 0
            Main | Should -Be 0
        }

        It "Returns 1 and writes [-]-prefixed output when the port scan fails" {
            Mock Get-NetTCPConnection { throw "socket enumeration unavailable" }

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out -join "`n") | Should -Match '\[-\]'
        }

        It "Includes UDP endpoints only when -IncludeUDP is supplied" {
            Mock Get-NetTCPConnection { @() }
            Mock Get-NetUDPEndpoint {
                @(
                    [pscustomobject]@{ LocalAddress = '0.0.0.0'; LocalPort = 137; OwningProcess = 1234 }
                )
            }

            $null = Main -IncludeUDP *>&1
            Should -Invoke Get-NetUDPEndpoint -Times 1 -Exactly
        }
    }
}
