#Requires -Modules Pester

Describe "Test-RemediationFixSMBv1Protocol" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/network/Test-RemediationFixSMBv1Protocol.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Stub Windows-only cmdlets so Pester can mock them on Linux pwsh.
        function Get-WindowsOptionalFeature { }
        function Get-SmbServerConfiguration { }
        function Get-ItemProperty { }
        Mock Get-ItemProperty { }

        # Default mock: SMBv1 fully disabled everywhere (converged system).
        Mock Get-WindowsOptionalFeature { [pscustomobject]@{ FeatureName = 'SMB1Protocol'; State = 'Disabled' } }
        Mock Get-SmbServerConfiguration { [pscustomobject]@{ EnableSMB1Protocol = $false } }
        Mock Test-Path { $false } -ParameterFilter { $Path -like '*LanmanServer*' }
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationFixSMBv1Protocol\.ps1'
            $raw | Should -Match 'Author:'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
        }

        It "Has SYNOPSIS, DESCRIPTION and at least two EXAMPLES" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
        }

        It "Declares one .PARAMETER per param() parameter" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
            if ($null -eq $ast.ParamBlock) { $declared = @() }
            else { $declared = @($ast.ParamBlock.Parameters.Name.VariableText) }
            $raw = Get-Content -Path $scriptPath -Raw
            $paramHelpMatches = [regex]::Matches($raw, '(?m)^\s*\.PARAMETER\s+(\S+)')
            $documented = @($paramHelpMatches | ForEach-Object { $_.Groups[1].Value })
            @($documented).Count | Should -Be @($declared).Count
            foreach ($p in $declared) { $documented | Should -Contain $p }
        }
    }

    Context "Syntax & Static" {
        BeforeAll {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        }
        It "Parses with zero errors" {
            $errors | Should -BeNullOrEmpty
        }
        It "Contains no PS7-only operators (no #Requires -Version 7.0 opt-out present)" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Not -Match '(?m)&&|\|\||\?\?|\?\?='
            $raw | Should -Not -Match '\$\w+\s*\?\s*[^:]'
        }
    }

    Context "Behavior" {
        It "Returns 0 with [+] output when SMBv1 is disabled everywhere" {
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*LanmanServer*' }
            Mock Get-ItemProperty { [pscustomobject]@{ SMB1 = 0 } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Returns 1 with [!] output when the SMB1Protocol feature is Enabled" {
            Mock Get-WindowsOptionalFeature { [pscustomobject]@{ FeatureName = 'SMB1Protocol'; State = 'Enabled' } }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\]'
            $text | Should -Match 'security risk'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 when only the SMB server configuration enables SMBv1" {
            Mock Get-SmbServerConfiguration { [pscustomobject]@{ EnableSMB1Protocol = $true } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'SMB server configuration'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 when only the registry backup value enables SMBv1" {
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*LanmanServer*' }
            Mock Get-ItemProperty { [pscustomobject]@{ SMB1 = 1 } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'registry'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Treats a missing registry key as compliant" {
            Mock Test-Path { $false } -ParameterFilter { $Path -like '*LanmanServer*' }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Get-ItemProperty -Times 0 -Exactly -Because "registry key is absent"
        }

        It "Returns 1 and writes [-] prefixed output when feature enumeration fails" {
            Mock Get-WindowsOptionalFeature { throw 'DISM unavailable' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
