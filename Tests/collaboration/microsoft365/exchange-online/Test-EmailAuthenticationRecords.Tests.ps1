#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for scripts/collaboration/microsoft365/exchange-online/Test-EmailAuthenticationRecords.ps1.

.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior using
    fully mocked external cmdlets. Runs offline on Linux pwsh; no network, elevation, or
    installed product modules required. DNS resolution is intercepted at the Invoke-DnsQuery
    wrapper and Exchange Online is intercepted at the Get-DkimSigningConfig stub.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/collaboration/microsoft365/exchange-online
    Runs this test file.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/collaboration/microsoft365/exchange-online -Output Detailed
    Runs this test file with per-test output.

.NOTES
   File Name   : Test-EmailAuthenticationRecords.Tests.ps1
   Author      : Bug-Free Umbrella
   Prerequisite: PowerShell 7.0
   Version     : 2.0.0
   Date        : 2026-09-16
#>

Describe 'Test-EmailAuthenticationRecords' {
    BeforeAll {
        $scriptRelPath = ('../../../../scripts/collaboration/microsoft365/exchange-online/' +
            'Test-EmailAuthenticationRecords.ps1')
        $scriptPath = (Resolve-Path (Join-Path $PSScriptRoot $scriptRelPath)).Path

        # The script's top-level guard skips Main when dot-sourced; -DomainName is supplied so
        # the mandatory parameter does not prompt.
        . $scriptPath -DomainName 'contoso.com'

        # Exchange Online PowerShell is not installed offline: declare the cmdlet as an empty
        # function so Pester can mock it.
        function Get-DkimSigningConfig {
            [CmdletBinding()]
            param([string]$Identity)
        }

        # Invoke-DnsQuery is the script's only path to the native resolver, so mocking it keeps
        # the tests fully offline. The switch keys are '<Type>|<Name>'.
        Mock Invoke-DnsQuery {
            $key = "$Type|$Name"
            switch ($key) {
                'TXT|contoso.com' {
                    return @([pscustomobject]@{
                        Name    = 'contoso.com'
                        Type    = 'TXT'
                        Strings = @('v=spf1 include:spf.protection.outlook.com -all')
                    })
                }
                'MX|contoso.com' {
                    return @([pscustomobject]@{
                        Name         = 'contoso.com'
                        Type         = 'MX'
                        NameExchange = 'contoso-com.mail.protection.outlook.com'
                    })
                }
                'TXT|_dmarc.contoso.com' {
                    return @([pscustomobject]@{
                        Name    = '_dmarc.contoso.com'
                        Type    = 'TXT'
                        Strings = @('v=DMARC1; p=reject; rua=mailto:rua@contoso.com')
                    })
                }
                'CNAME|selector1._domainkey.contoso.com' {
                    return @([pscustomobject]@{
                        Name     = 'selector1._domainkey.contoso.com'
                        Type     = 'CNAME'
                        NameHost = 'selector1-contoso-com._domainkey.contoso.n-v1.dkim.mail.microsoft'
                    })
                }
                'CNAME|selector2._domainkey.contoso.com' {
                    return @([pscustomobject]@{
                        Name     = 'selector2._domainkey.contoso.com'
                        Type     = 'CNAME'
                        NameHost = 'selector2-contoso-com._domainkey.contoso.n-v1.dkim.mail.microsoft'
                    })
                }
                default { return @() }
            }
        }

        Mock Get-DkimSigningConfig {
            [pscustomobject]@{
                Enabled         = $true
                Status          = 'Valid'
                Selector1CNAME  = 'selector1-contoso-com._domainkey.contoso.n-v1.dkim.mail.microsoft'
                Selector2CNAME  = 'selector2-contoso-com._domainkey.contoso.n-v1.dkim.mail.microsoft'
            }
        }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath, [ref]$tokens, [ref]$parseErrors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Test-EmailAuthenticationRecords\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*Bug-Free Umbrella'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Documents every declared parameter, in order' {
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object {
                $_.Name.Extent.Text.TrimStart('$')
            })
            $helpParams = @([regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value })
            $declared | Should -Be @(
                'DomainName', 'DkimSelector', 'ExpectedSpfInclude', 'DmarcPolicy',
                'OutputFormat', 'OutputPath')
            $helpParams | Should -Be $declared
        }

        It 'Provides at least two examples with PS prompts' {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $parseErrors.Count | Should -Be 0
        }

        It 'Uses CmdletBinding, Main function, and dot-source guard' {
            $raw | Should -Match '\[CmdletBinding\('
            $raw | Should -Match '(?m)^function Main \{'
            $raw | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
        }

        It 'Contains no PS7-only operators and no #Requires opt-out' {
            # Token-level scan: the forbidden operator texts are built from code points so this
            # file does not itself contain them.
            $forbidden = @(
                (-join [char[]](0x3F, 0x3F))
                (-join [char[]](0x3F, 0x3F, 0x3D))
                (-join [char[]](0x26, 0x26))
                (-join [char[]](0x7C, 0x7C))
            )
            $declared = @($tokens | ForEach-Object { $_.Text })
            foreach ($operator in $forbidden) {
                $declared | Should -Not -Contain $operator
            }
            $raw | Should -Not -Match '#Requires\s+-Version'
        }

        It 'Is UTF-8 with BOM and CRLF line endings' {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }

        It 'Keeps all lines within 120 columns and free of tabs' {
            ($raw -split "`r`n" | Where-Object { $_.Length -gt 120 }) | Should -BeNullOrEmpty
            $raw | Should -Not -Match "`t"
        }

        It 'Cites Microsoft Learn in its help' {
            $raw | Should -Match 'learn\.microsoft\.com'
        }
    }

    Context 'Behavior' {
        It 'Passes every documented check and returns 0' {
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[\+\] SPF mechanisms: include:spf\.protection\.outlook\.com, -all'
            $text | Should -Match '\[\+\] All email authentication checks passed'
            Should -Invoke Invoke-DnsQuery -Exactly 5
            Should -Invoke Get-DkimSigningConfig -Exactly 1
        }

        It 'Returns 2 when a second SPF record is published' {
            Mock Invoke-DnsQuery {
                if ($Type -eq 'TXT' -and $Name -eq 'contoso.com') {
                    return @(
                        [pscustomobject]@{ Strings = @('v=spf1 include:spf.protection.outlook.com -all') }
                        [pscustomobject]@{ Strings = @('v=spf1 include:spf.protection.outlook.com -all') }
                    )
                }
                return @()
            }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($out | Out-String) | Should -Match 'only one is allowed per domain'
        }

        It 'Returns 2 for a weak DMARC policy and a missing DKIM selector CNAME' {
            Mock Invoke-DnsQuery {
                switch ("$Type|$Name") {
                    'TXT|contoso.com' {
                        return @([pscustomobject]@{
                            Strings = @('v=spf1 include:spf.protection.outlook.com -all')
                        })
                    }
                    'MX|contoso.com' {
                        return @([pscustomobject]@{
                            NameExchange = 'contoso-com.mail.protection.outlook.com'
                        })
                    }
                    'TXT|_dmarc.contoso.com' {
                        return @([pscustomobject]@{
                            Strings = @('v=DMARC1; p=none; rua=mailto:rua@contoso.com')
                        })
                    }
                    'CNAME|selector1._domainkey.contoso.com' {
                        return @([pscustomobject]@{ NameHost = 'selector1-x.dkim.mail.microsoft' })
                    }
                    default { return @() }
                }
            }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            $text = $out | Out-String
            $text | Should -Match 'policy p=none is weaker than the required p=quarantine'
            $text | Should -Match 'no CNAME record is published for selector2'
        }

        It 'Returns 2 when no MX record is published' {
            Mock Invoke-DnsQuery {
                if ($Type -eq 'MX') { return @() }
                if ($Type -eq 'TXT' -and $Name -eq '_dmarc.contoso.com') {
                    return @([pscustomobject]@{ Strings = @('v=DMARC1; p=reject; rua=mailto:r@contoso.com') })
                }
                if ($Type -eq 'TXT') {
                    return @([pscustomobject]@{
                        Strings = @('v=spf1 include:spf.protection.outlook.com -all')
                    })
                }
                return @([pscustomobject]@{ NameHost = 'selectorN-x.dkim.mail.microsoft' })
            }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($out | Out-String) | Should -Match 'MX: no MX record is published for contoso\.com'
        }

        It 'Returns the documented exit code 1 when DNS resolution fails' {
            Mock Invoke-DnsQuery { throw 'DNS server unreachable' }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] Error: DNS server unreachable'
        }

        It 'Warns and still returns 0 when Exchange Online PowerShell is unavailable' {
            Mock Get-Command -ParameterFilter { $Name -eq 'Get-DkimSigningConfig' } { }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Exchange Online PowerShell unavailable'
            Should -Invoke Get-DkimSigningConfig -Exactly 0
        }

        It 'Writes a CSV report when -OutputFormat Csv is used' {
            $csvPath = Join-Path $TestDrive 'email-auth.csv'
            . $scriptPath -DomainName 'contoso.com' -OutputFormat Csv -OutputPath $csvPath
            Main | Should -Be 0
            Test-Path -LiteralPath $csvPath | Should -BeTrue
            (Get-Content -LiteralPath $csvPath -Raw) | Should -Match 'SPF'
        }

        It 'Writes a JSON report whose Domain matches the audit target' {
            $jsonPath = Join-Path $TestDrive 'email-auth.json'
            . $scriptPath -DomainName 'contoso.com' -OutputFormat Json -OutputPath $jsonPath
            Main | Should -Be 0
            $parsed = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
            $parsed.Domain | Should -Be 'contoso.com'
            $parsed.Findings.Count | Should -Be 0
        }
    }
}
