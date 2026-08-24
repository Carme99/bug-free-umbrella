#Requires -Modules Pester

Describe "Test-RemediationFixWindowsUpdateRebootPending" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptPath = Join-Path $repoRoot `
            'scripts/endpoints/remediation/system/Test-RemediationFixWindowsUpdateRebootPending.ps1'

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationFixWindowsUpdateRebootPending\.ps1'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
            $raw | Should -Match 'Author:'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
        }

        It "Has SYNOPSIS, DESCRIPTION and at least two EXAMPLES" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
        }

        It "Declares one .PARAMETER per param() parameter" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
            if ($null -eq $ast.ParamBlock) {
                $declared = @()
            }
            else {
                $declared = @($ast.ParamBlock.Parameters.Name.VariableText)
            }
            $raw = Get-Content -Path $scriptPath -Raw
            $documented = @([regex]::Matches($raw, '(?m)^\s*\.PARAMETER\s+(\S+)') |
                    ForEach-Object { $_.Groups[1].Value })
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
        It "Returns 0 when no reboot-pending indicators are present" {
            Mock Get-ItemProperty { $null }
            function Get-WmiObject { }
            Mock Get-WmiObject { throw "unexpected WMI call" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Get-WmiObject -Times 0 -Exactly -Because "no reboot-pending state exists"
        }

        It "Returns 1 and lists issues when a reboot-pending indicator is present" {
            Mock Get-ItemProperty { [pscustomobject]@{ PSChildName = 'RebootPending' } }
            function Get-WmiObject { }
            $fakeOs = [pscustomobject]@{ LastBootUpTime = '20200101000000.000000+000' }
            $fakeOs | Add-Member -MemberType ScriptMethod -Name ConvertToDateTime -Value { [datetime]'2020-01-01' }
            Mock Get-WmiObject { $fakeOs }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'Component-Based Servicing'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Adds an uptime issue when reboot pending for more than 7 days" {
            Mock Get-ItemProperty { $null } -ParameterFilter { $Name -eq 'PendingFileRenameOperations' }
            Mock Get-ItemProperty { [pscustomobject]@{ PSChildName = 'RebootPending' } }
            function Get-WmiObject { }
            $fakeOs = [pscustomobject]@{ LastBootUpTime = 'x' }
            $fakeOs | Add-Member -MemberType ScriptMethod -Name ConvertToDateTime -Value { (Get-Date).AddDays(-30) }
            Mock Get-WmiObject { $fakeOs }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'not been rebooted in \d+ days'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [-] prefixed output when the WMI query fails" {
            Mock Get-ItemProperty { [pscustomobject]@{ PSChildName = 'RebootPending' } }
            function Get-WmiObject { }
            Mock Get-WmiObject { throw "WMI unavailable" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
