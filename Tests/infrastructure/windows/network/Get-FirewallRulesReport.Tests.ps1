#Requires -Modules Pester

Describe "Get-FirewallRulesReport" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            ""../../../../scripts/infrastructure/windows/network/Get-FirewallRulesReport.ps1""

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Stub Windows-only commands so Pester can attach mocks on Linux.
        function Get-NetFirewallRule { }
        function Get-NetFirewallPortFilter { }
        function Get-NetFirewallApplicationFilter { }
        function Get-NetFirewallServiceFilter { }
        function Get-NetFirewallAddressFilter { }
        function Get-NetFirewallProfile { }

        # Mock ALL externals so nothing touches the machine or network.
        Mock Test-AdminPrivilege { $true }
        Mock Write-Progress { }
        Mock Get-NetFirewallRule {
            @(
                [pscustomobject]@{
                    DisplayName = 'Allow HTTP'; Name = 'allow-http'; Enabled = 'True'
                    Direction = 'Inbound'; Action = 'Allow'; Profile = 'Domain, Private, Public'
                    Description = 'HTTP'; Group = 'Web'; EdgeTraversalPolicy = 'False'
                },
                [pscustomobject]@{
                    DisplayName = 'Block Legacy SMB'; Name = 'block-smb'; Enabled = 'False'
                    Direction = 'Outbound'; Action = 'Block'; Profile = 'Any'
                    Description = ''; Group = ''; EdgeTraversalPolicy = 'False'
                }
            )
        }
        Mock Get-NetFirewallPortFilter {
            [pscustomobject]@{ LocalPort = @('80'); RemotePort = @('Any'); Protocol = 'TCP' }
        }
        Mock Get-NetFirewallApplicationFilter {
            [pscustomobject]@{ Program = 'Any' }
        }
        Mock Get-NetFirewallServiceFilter {
            [pscustomobject]@{ Service = 'Any' }
        }
        Mock Get-NetFirewallAddressFilter {
            [pscustomobject]@{ LocalAddress = @('Any'); RemoteAddress = @('Any') }
        }
        Mock Get-NetFirewallProfile {
            @([pscustomobject]@{
                Name = 'Domain'; Enabled = $true; DefaultInboundAction = 'Block'
                DefaultOutboundAction = 'Allow'; AllowInboundRules = $true
                AllowLocalFirewallRules = $true; AllowLocalIPsecRules = $true
                NotifyOnListen = $true; EnableStealthModeForIPsec = $false
                LogFileName = 'firewall.log'; LogMaxSizeKilobytes = 16384
                LogAllowed = 'False'; LogBlocked = 'True'; LogIgnored = 'True'
            })
        }
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock Out-File { }
        Mock Export-Csv { }

        $scriptText = Get-Content -Raw $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0" {
            $scriptText | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
        }

        It "Declares relaunch Date 2026-08-23" {
            $scriptText | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
        }

        It "Declares File Name matching the disk filename" {
            $expected = Split-Path -Leaf $scriptPath
            $scriptText | Should -Match "(?m)^\s*File Name\s*:\s*$([regex]::Escape($expected))\s*$"
        }

        It "Declares an Author and Prerequisite" {
            $scriptText | Should -Match '(?m)^\s*Author\s*:\s*\S'
            $scriptText | Should -Match '(?m)^\s*Prerequisite\s*:\s*PowerShell'
        }

        It "Has at least two EXAMPLE blocks with PS C:\> prompts" {
            ([regex]::Matches($scriptText, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($scriptText, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }

        It "Has one .PARAMETER per declared parameter, in order" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($scriptText, [ref]$tokens, [ref]$errors)
            $declared = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $documented = @([regex]::Matches($scriptText, '(?m)^\.PARAMETER\s+(\w+)') |
                ForEach-Object { $_.Groups[1].Value })
            $documented.Count | Should -Be $declared.Count
            for ($i = 0; $i -lt $declared.Count; $i++) {
                $documented[$i] | Should -Be $declared[$i]
            }
        }
    }

    Context "Syntax & Static" {
        It "Parses cleanly via the PowerShell parser" {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
            $errors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only syntax (no #Requires -Version 7.0 present)" {
            $scriptText | Should -Not -Match '#Requires\s+-Version\s+7'
            $scriptText | Should -Not -Match '\?\?'
            $scriptText | Should -Not -Match '&&'
            $scriptText | Should -Not -Match '\|\|'
            $scriptText | Should -Not -Match '-Parallel\b'
        }

        It "Wraps execution in Main and exits only via the top-level guard" {
            $scriptText | Should -Match '(?m)^function Main \{'
            $guardLine = [regex]::Escape("if (`$MyInvocation.InvocationName -ne '.') { exit (Main) }")
            $scriptText | Should -Match $guardLine
            ([regex]::Matches($scriptText, '\bexit\b')).Count | Should -Be 1
        }

        It "Uses UTF-8 BOM and CRLF line endings" {
            $raw = [System.IO.File]::ReadAllBytes($scriptPath)
            ($raw[0], $raw[1], $raw[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            [System.Text.Encoding]::UTF8.GetString($raw) | Should -Not -Match "(?<!`r)`n"
        }
    }

    Context "Behavior" {
        It "Documents mocked rules with correct summary statistics and returns 0" {
            $Enabled = 'All'

            $out = Main *>&1
            $rc = $out | Where-Object { $_ -is [int] } | Select-Object -First 1
            $rc | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            $script:report.Summary.TotalRules | Should -Be 2
            $script:report.Summary.InboundRules | Should -Be 1
            $script:report.Summary.OutboundRules | Should -Be 1
            $script:report.Summary.AllowRules | Should -Be 1
            $script:report.Summary.BlockRules | Should -Be 1
            $script:report.Summary.EnabledRules | Should -Be 1
            $script:report.Summary.DisabledRules | Should -Be 1
            Should -Invoke Get-NetFirewallPortFilter -Times 2 -Exactly
        }

        It "Applies the enabled-only filter by default (idempotent re-run)" {
            (Main *>&1 | Where-Object { $_ -is [int] }) | Should -Contain 0
            # Default filter is Enabled='Enabled': only the enabled rule is documented.
            $script:report.Summary.TotalRules | Should -Be 1
        }

        It "Returns 1 with [-] output when administrator privileges are missing" {
            Mock Test-AdminPrivilege { $false }
            $out = Main *>&1
            $rc = $out | Where-Object { $_ -is [int] } | Select-Object -First 1
            $rc | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
            Should -Invoke Get-NetFirewallRule -Times 0 -Exactly
        }
    }
}
