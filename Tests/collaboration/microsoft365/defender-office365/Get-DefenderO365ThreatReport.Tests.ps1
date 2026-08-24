#Requires -Modules Pester

Describe 'Get-DefenderO365ThreatReport' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/collaboration/microsoft365/defender-office365/ ->
        # the script is four levels up plus across under scripts/.
        $scriptDir = Join-Path $PSScriptRoot '../../../../scripts/collaboration/microsoft365/defender-office365'
        $scriptPath = Join-Path $scriptDir 'Get-DefenderO365ThreatReport.ps1'

        # Stub product-module cmdlets not installed on this machine so Pester can mock them.
        function Get-OrganizationConfig { }
        function Get-MailDetailATPReport { }
        function Get-SafeLinksDetailReport { }

        # Mock ALL external commands so nothing leaves the machine (offline Linux CI).
        function Write-ReportTextFile { }

        # Safe: the script's top-level guard skips Main when dot-sourced (spec section 3).
        . $scriptPath
        Mock Get-Module { [pscustomobject]@{ Name = 'ExchangeOnlineManagement'; Version = [version]'3.4.0' } }
        Mock Get-OrganizationConfig { [pscustomobject]@{ Name = 'contoso.onmicrosoft.com' } }
        Mock Get-MailDetailATPReport { @() }
        Mock Get-SafeLinksDetailReport { @() }
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock Write-ReportTextFile { }
        Mock Export-Csv { }

    }

    Context 'Help & Metadata' {
        It 'Declares Version 1.0.0 and relaunch Date 2026-08-23 in .NOTES' {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
            $raw | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
        }

        It 'Records File Name matching the disk filename and PowerShell 7.0 prerequisite' {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '(?m)^\s*File Name\s*:\s*Get-DefenderO365ThreatReport\.ps1\s*$'
            $raw | Should -Match '(?m)^\s*Prerequisite\s*:\s*PowerShell 7\.0\s*$'
        }

        It 'Has exactly one .PARAMETER entry per declared parameter, in declaration order' {
            $toks = $null
            $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$toks, [ref]$errs)
            $declaredParams = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $helpParams = @(Select-String -Path $scriptPath -Pattern '^\s*\.PARAMETER\s+(\S+)' |
                ForEach-Object { $_.Matches[0].Groups[1].Value })
            $helpParams.Count | Should -Be $declaredParams.Count
            $helpParams | Should -Be $declaredParams
        }

        It 'Provides at least two .EXAMPLE blocks with PS C:\> prompt lines' {
            $raw = Get-Content -Path $scriptPath -Raw
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE\s*$')).Count | Should -BeGreaterOrEqual 2
            $raw | Should -Match 'PS C:\\>'
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $toks = $null
            $errs = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$toks, [ref]$errs) | Out-Null
            $parseErrors | Should -BeNullOrEmpty
        }

        It 'Contains no PS7-only operators unless #Requires -Version 7.0 is present' {
            $raw = Get-Content -Path $scriptPath -Raw
            if ($raw -notmatch '(?m)^#Requires\s+-Version\s+7\.0') {
                $raw | Should -Not -Match '\?\?|\?\?=|\|\||&&'
            }
        }

        It 'Uses exit only in the top-level dot-source guard line' {
            $toks = $null
            $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$toks, [ref]$errs)
            $findExit = { $args[0] -is [System.Management.Automation.Language.ExitStatementAst] }
            $exitStatements = @($ast.FindAll($findExit, $true))
            $exitStatements.Count | Should -Be 1
            $exitStatements[0].Parent.ToString() | Should -Match 'exit \(Main\)'
        }

        It 'Is saved as UTF-8 with BOM and CRLF line endings' {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
            $text = [System.IO.File]::ReadAllText($scriptPath)
            $text | Should -Not -Match '(?<!\r)\n'
        }
    }

    Context 'Behavior' {
        It 'Returns 0 and prints prefixed summary counts when detections exist' {
            Mock Get-MailDetailATPReport {
                @(
                    [pscustomobject]@{
                        VerdictSource = 'Phish'; RecipientAddress = 'victim@contoso.com'
                        SenderAddress = 'phish@evil.com'; Subject = 'Urgent wire transfer'
                        Date = (Get-Date '2026-08-20'); Direction = 'Inbound'; Action = 'Delivered'; FileName = $null
                    }
                    [pscustomobject]@{
                        VerdictSource = 'Malware'; RecipientAddress = 'victim@contoso.com'
                        SenderAddress = 'worm@evil.com'; Subject = 'Invoice'
                        Date = (Get-Date '2026-08-21'); Direction = 'Inbound'; Action = 'Removed'; FileName = 'evil.exe'
                    }
                )
            }

            $OutputFormat = 'Console'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[\*\] Analyzing Defender for Office 365 threats \(Last 7 days\)'
            $text | Should -Match 'Total Threats Detected: 2'
            $text | Should -Match 'Phishing: 1'
            $text | Should -Match 'Malware: 1'
            Should -Invoke Get-MailDetailATPReport -Times 4 -Exactly
        }

        It 'Ranks targeted users with risk levels when -IncludeUserRiskAnalysis is set' {
            Mock Get-MailDetailATPReport {
                @(
                    [pscustomobject]@{
                        VerdictSource = 'Phish'; RecipientAddress = 'victim@contoso.com'
                        SenderAddress = 'phish@evil.com'; Subject = 'Hi'
                        Date = (Get-Date '2026-08-20'); Direction = 'Inbound'; Action = 'Delivered'; FileName = $null
                    }
                )
            }

            $IncludeUserRiskAnalysis = $true
            $OutputFormat = 'Console'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'victim@contoso\.com: 1 threats \[Low Risk\]'
        }

        It 'Writes the HTML report through Out-File when OutputFormat is HTML' {
            Mock Get-SafeLinksDetailReport {
                @([pscustomobject]@{
                    RecipientAddress = 'victim@contoso.com'; Url = 'https://evil.example/click'
                    Action = 'Blocked'; Date = (Get-Date '2026-08-21'); IsClickedThrough = $false
                })
            }

            $OutputFormat = 'HTML'
            Main | Should -Be 0
            $filter = { $Path -like '*Defender-O365-Threats-*.html' }
            Should -Invoke Write-ReportTextFile -Times 1 -Exactly -ParameterFilter $filter
        }

        It 'Exports threat detections through Export-Csv when OutputFormat is CSV' {
            Mock Get-MailDetailATPReport {
                @([pscustomobject]@{
                    VerdictSource = 'Phish'; RecipientAddress = 'victim@contoso.com'
                    SenderAddress = 'phish@evil.com'; Subject = 'Hi'
                    Date = (Get-Date '2026-08-20'); Direction = 'Inbound'; Action = 'Delivered'; FileName = $null
                })
            }

            $OutputFormat = 'CSV'
            Main | Should -Be 0
            $filter = { $Path -like '*Defender-Threats-*.csv' }
            Should -Invoke Export-Csv -ParameterFilter $filter
        }

        It 'Returns 1 and writes [-] prefixed output when not connected to Exchange Online' {
            Mock Get-OrganizationConfig { throw 'Cannot access organization configuration' }

            $OutputFormat = 'Console'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] Error'
        }

        It 'Returns 1 when the ExchangeOnlineManagement module is missing' {
            Mock Get-Module { $null }

            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Tolerates upstream retrieval warnings and still completes with exit 0' {
            Mock Get-MailDetailATPReport { throw 'transient service error' }

            $OutputFormat = 'Console'
            Main | Should -Be 0
        }

        It 'Is idempotent: repeated runs against unchanged data both return 0' {
            $OutputFormat = 'Console'
            Main | Should -Be 0
            Main | Should -Be 0
        }
    }
}
