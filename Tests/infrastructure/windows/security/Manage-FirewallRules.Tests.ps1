#Requires -Modules Pester

Describe "Manage-FirewallRules" {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../../../..')
        $scriptPath = Join-Path $repoRoot 'scripts/infrastructure/windows/security/Manage-FirewallRules.ps1'
        . $scriptPath -Action 'Audit'
        $helpText = Get-Content -Raw $scriptPath
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)

        # Stub Windows-only commands absent on Linux so Pester can attach mocks.
        $firewallCmds = @(
            'Get-NetFirewallRule', 'Get-NetFirewallPortFilter', 'Get-NetFirewallAddressFilter',
            'Get-NetFirewallApplicationFilter', 'Enable-NetFirewallRule',
            'Disable-NetFirewallRule', 'Remove-NetFirewallRule'
        )
        foreach ($stub in $firewallCmds) {
            if (-not (Get-Command $stub -ErrorAction SilentlyContinue)) {
                Invoke-Expression "function $stub { }"
            }
        }


        function New-MockFirewallRule {
            param([bool]$Enabled = $true)
            [PSCustomObject]@{
                Name = 'Mock-Rule-1'
                DisplayName = 'Test Inbound Rule'
                Enabled = $Enabled
                Direction = 'Inbound'
                Action = 'Allow'
                Profile = 'Any'
                Description = 'Mocked rule'
            }
        }

        Mock -CommandName Test-Path { $true }
        Mock -CommandName Get-NetFirewallRule { @(New-MockFirewallRule -Enabled $true) }
        Mock -CommandName Get-NetFirewallPortFilter {
            [PSCustomObject]@{ Protocol = 'TCP'; LocalPort = @('Any'); RemotePort = @('Any') }
        }
        Mock -CommandName Get-NetFirewallAddressFilter {
            [PSCustomObject]@{ LocalAddress = @('Any'); RemoteAddress = @('Any') }
        }
        Mock -CommandName Get-NetFirewallApplicationFilter { [PSCustomObject]@{ Program = 'Any'; Service = 'Any' } }
        Mock -CommandName Enable-NetFirewallRule { }
        Mock -CommandName Disable-NetFirewallRule { }
        Mock -CommandName Remove-NetFirewallRule { }
        Mock -CommandName Invoke-Netsh { 0 }
        Mock -CommandName Export-Csv { }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date" {
            $helpText | Should -Match 'Version\s*:\s*1\.0\.0'
            $helpText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Declares matching File Name, Author and Prerequisite" {
            $helpText | Should -Match ('File Name\s*:\s*' + [regex]::Escape('Manage-FirewallRules.ps1'))
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

        It "Declares SupportsShouldProcess for mutating actions" {
            $ast.ParamBlock.Attributes.NamedArguments.ArgumentName | Should -Contain 'SupportsShouldProcess'
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
        It "Disables an enabled rule via ShouldProcess gate and returns 0" {
            $Action = 'Disable'

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            Should -Invoke Disable-NetFirewallRule -Times 1 -Exactly
            $text | Should -Match '\[\+\] Disabled: Test Inbound Rule'
        }

        It "Is idempotent: disabling an already-disabled rule makes no change" {
            $Action = 'Disable'
            $ShowDisabled = $true   # disabled rules are filtered out by default
            Mock -CommandName Get-NetFirewallRule { @(New-MockFirewallRule -Enabled $false) }

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            Should -Invoke Disable-NetFirewallRule -Times 0 -Exactly -Because "rule is already in the requested state"
            $text | Should -Match '\[\*\] Already disabled'
        }

        It "Returns 1 with [-] output when rule retrieval fails" {
            $Action = 'Audit'
            Mock -CommandName Get-NetFirewallRule { throw "firewall service unreachable" }

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 1
            $text | Should -Match '\[-\] Error'
        }

        It "Audits without mutation on the Audit action" {
            $Action = 'Audit'

            $null = Main
            Should -Invoke Disable-NetFirewallRule -Times 0
            Should -Invoke Enable-NetFirewallRule -Times 0
            Should -Invoke Remove-NetFirewallRule -Times 0
        }

        It "Routes netsh export through the wrapper and fails loudly on non-zero exit" {
            $Action = 'Export'
            Mock -CommandName Invoke-Netsh { 1 }

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 1
            $text | Should -Match 'netsh advfirewall export failed'
        }
    }
}
