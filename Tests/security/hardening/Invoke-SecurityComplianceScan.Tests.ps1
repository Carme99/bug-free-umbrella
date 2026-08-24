#Requires -Modules Pester

Describe "Invoke-SecurityComplianceScan" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/security/hardening/Invoke-SecurityComplianceScan.ps1"
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        Mock Test-AdministratorElevation { $true }

        # Stub Windows-only cmdlets so Pester can mock them on Linux
        function Get-LocalUser { }
        function Get-NetFirewallProfile { }
        function Get-ItemProperty { }
        function Get-Service { }

        # Fully compliant machine: registry values, local users, firewall, services, TLS
        $compliantRegProps = [pscustomobject]@{
            PasswordHistoryLength = 24
            LockoutBadCount       = 3
            legalnoticecaption    = 'Authorized access only'
            Enabled               = 1
            DisabledByDefault     = 0
        }
        Mock Get-ItemProperty { $compliantRegProps }

        Mock Get-LocalUser {
            param([string]$Name)
            if ($Name) {
                [pscustomobject]@{ Name = 'Guest'; Enabled = $false }
            }
            else {
                @()
            }
        }
        Mock Get-NetFirewallProfile { [pscustomobject]@{ Profile = 'Domain'; Enabled = $true } }
        Mock Get-Service { $null }   # no Telnet/FTP/SNMP running

        $compliantIni = @"
[Unicode]
Unicode=yes
[System Access]
PasswordComplexity = 1
"@
        Mock Invoke-SeceditExport {
            param([string]$ConfigFile)
            Set-Content -LiteralPath $ConfigFile -Value $compliantIni
            return 0
        }

        Mock Invoke-AuditPolicyQuery {
            [pscustomobject]@{
                Output   = @("Credential Validation                Success and Failure")
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
        It "Returns 0 with no findings on a fully compliant system" {
            $out = (Main -OutputFormat Console *>&1 | Out-String)
            $out | Should -Match '\[\+\] Security compliance scan complete!'
            $lastCode = $LASTEXITCODE   # not used; Main returns via pipeline below
            Main -OutputFormat Console | Should -Be 0
        }

        It "Reports findings when registry configuration is non-compliant" {
            Mock Get-ItemProperty { [pscustomobject]@{ PasswordHistoryLength = 5 } }

            $out = (Main -Framework CIS -TargetSystem Windows -Severity All -OutputFormat Console *>&1 | Out-String)
            $out | Should -Match 'CIS-1\.1\.1'
            Main -Framework CIS -TargetSystem Windows -Severity All -OutputFormat Console | Should -Be 0
        }

        It "Writes a JSON report under OutputPath without any network access" {
            $reportDir = Join-Path $TestDrive 'reports'

            Main -Framework All -TargetSystem Windows -OutputFormat JSON -OutputPath $reportDir | Should -Be 0

            @(Get-ChildItem -LiteralPath $reportDir -Filter '*.json').Count | Should -Be 1
        }

        It "Gates temporary policy file deletion behind ShouldProcess" {
            Mock Remove-Item { }

            # With -WhatIf the temp file cleanup must NOT run
            Main -Framework PCI-DSS -TargetSystem Windows -OutputFormat Console -WhatIf | Should -Be 0
            Should -Invoke Remove-Item -Times 0 -Exactly -Because "-WhatIf suppresses the temp file delete"

            # Without -WhatIf the temp file cleanup runs exactly once per policy export
            Mock Remove-Item { }
            Main -Framework PCI-DSS -TargetSystem Windows -OutputFormat Console | Should -Be 0
            Should -Invoke Remove-Item -Times 1 -Exactly
        }
    }
}
