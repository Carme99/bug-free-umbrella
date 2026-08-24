#Requires -Modules Pester

Describe "Get-SecurityBaseline" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/security/compliance/frameworks/Get-SecurityBaseline.ps1"

        # Stub Windows-only cmdlets so Pester can attach mocks on Linux.
        function Get-NetFirewallProfile { }
        function Get-MpComputerStatus { }
        function Get-WindowsOptionalFeature { }
        function Get-SmbServerConfiguration { }
        function Get-LocalUser { }

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
        $rawText = Get-Content -LiteralPath $scriptPath -Raw

        # Route the temporary secedit export into the test drive.
        $script:oldTemp = $env:TEMP
        $env:TEMP = "$TestDrive"

        # Compliant secedit export content written by the Invoke-SecEdit mock.
        Mock Invoke-SecEdit {
            foreach ($arg in $args) {
                if ($arg -like '*.cfg') {
                    # -WhatIf:$false keeps the mock's file write out of the caller's -WhatIf scope.
                    Set-Content -LiteralPath $arg -Encoding UTF8 -WhatIf:$false -Value @(
                        '[Unicode]'
                        'Unicode=yes'
                        '[System Access]'
                        'MinimumPasswordLength = 14'
                        'PasswordComplexity = 1'
                        'MaximumPasswordAge = 60'
                        'MinimumPasswordAge = 1'
                        'PasswordHistorySize = 24'
                    )
                }
            }
            return 0
        }

        Mock Invoke-NetAccounts {
            @(
                'The command completed successfully.'
                ''
                'Lockout threshold:           10 invalid logon attempts'
                'Lockout duration:            30 minutes'
            )
        }

        Mock Invoke-AuditPol {
            @(
                'Logon/Logoff',
                '  Logon                          Success and Failure',
                'Account Logon                  Success and Failure',
                'Account Management             Success and Failure',
                'Policy Change                  Success and Failure',
                'Privilege Use                  Success and Failure'
            )
        }

        Mock Get-NetFirewallProfile {
            @(
                [pscustomobject]@{ Name = 'Domain'; Enabled = $true },
                [pscustomobject]@{ Name = 'Private'; Enabled = $true },
                [pscustomobject]@{ Name = 'Public'; Enabled = $true }
            )
        }

        Mock Get-ItemProperty {
            [pscustomobject]@{
                EnableLUA = 1
                ConsentPromptBehaviorAdmin = 5
                fDenyTSConnections = 1
                UserAuthentication = 1
            }
        }

        Mock Get-MpComputerStatus {
            [pscustomobject]@{
                AntivirusEnabled = $true
                RealTimeProtectionEnabled = $true
                AntivirusSignatureLastUpdated = (Get-Date).AddDays(-1)
            }
        }

        Mock Get-WindowsOptionalFeature { [pscustomobject]@{ FeatureName = 'SMB1Protocol'; State = 'Disabled' } }
        Mock Get-SmbServerConfiguration { [pscustomobject]@{ EnableSMB1Protocol = $false; EncryptData = $true } }
        Mock Get-LocalUser {
            @(
                [pscustomobject]@{
                    Name = 'Administrator'
                    Enabled = $false
                    SID = [pscustomobject]@{ Value = 'S-1-5-21-1004336348-1177238915-682003330-500' }
                },
                [pscustomobject]@{
                    Name = 'Guest'
                    Enabled = $false
                    SID = [pscustomobject]@{ Value = 'S-1-5-21-1004336348-1177238915-682003330-501' }
                }
            )
        }
        Mock Test-Path { $true }
        Mock Remove-Item { }
    }

    AfterAll {
        if ($null -ne $script:oldTemp) {
            $env:TEMP = $script:oldTemp
        }
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

        It "Routes native executables through wrapper functions only" {
            $rawText | Should -Match '(?m)function Invoke-SecEdit\b'
            $rawText | Should -Match '(?m)function Invoke-NetAccounts\b'
            $rawText | Should -Match '(?m)function Invoke-AuditPol\b'
            # Outside the wrapper definitions, no native exe may be called directly.
            $bodyOnly = $rawText -split '\n' |
                Where-Object { $_ -notmatch '& (secedit|net|auditpol)\.exe @args' }
            (($bodyOnly -join "`n") -match '&\s*(secedit|net|auditpol)\.exe') | Should -BeFalse
        }
    }

    Context "Behavior" {
        It "Passes all nine check categories against a compliant system and returns 0" {
            $exitCode = Main
            $exitCode | Should -Be 0
            Should -Invoke Invoke-SecEdit -Times 1 -Exactly
            Should -Invoke Invoke-NetAccounts -Times 1 -Exactly
            Should -Invoke Invoke-AuditPol -Times 1 -Exactly
        }

        It "Is idempotent: repeated runs still return 0 and re-run the read-only checks" {
            Main | Should -Be 0
            Main | Should -Be 0
            Should -Invoke Get-MpComputerStatus -Times 2 -Exactly
        }

        It "Cleans up the temporary secpol export file on every run" {
            $null = Main *>&1
            Should -Invoke Remove-Item -Times 1 -Exactly
        }

        It "Honors -WhatIf and does not delete the temporary policy file" {
            $exitCode = Main -WhatIf
            $exitCode | Should -Be 0
            Should -Invoke Remove-Item -Times 0 -Exactly
        }

        It "Returns 1 when a check category fails (secedit unavailable)" {
            Mock Invoke-SecEdit { throw "secedit.exe exited with code 1" }

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out -join "`n") | Should -Match '\[-\]'
        }
    }
}
