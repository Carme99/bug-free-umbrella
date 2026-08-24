#Requires -Modules Pester

Describe "Test-RemediationFixWindowsUpdateStuck" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptPath = Join-Path $repoRoot `
            'scripts/endpoints/remediation/system/Test-RemediationFixWindowsUpdateStuck.ps1'

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Cross-file isolation hygiene: sibling test files stub/mock
        # Windows-only registry cmdlets with narrowed parameter sets (e.g. a
        # `function global:Set-ItemProperty` without -Force). Pester leaves
        # those mock aliases/functions installed for the whole session, so
        # Main's first-seen marker write (-Force) fails to bind and lands in
        # Main's catch block. Strip any non-cmdlet shadow so the real cmdlet
        # metadata - and therefore Pester's mock signatures - is intact.
        foreach ($name in 'New-Item', 'Set-ItemProperty', 'Remove-Item') {
            while ((Get-Command $name -ErrorAction SilentlyContinue) -and
                   (Get-Command $name).CommandType -ne 'Cmdlet') {
                Remove-Item -Path "$((Get-Command $name).CommandType):$name" -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationFixWindowsUpdateStuck\.ps1'
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
        It "Gates marker mutations behind ShouldProcess (SupportsShouldProcess declared)" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'SupportsShouldProcess'
            $raw | Should -Match 'ShouldProcess\('
        }
    }

    Context "Behavior" {
        It "Is healthy: running service with no pending updates clears a stale marker and returns 0" {
            function Get-Service { }
            Mock Get-Service { [pscustomobject]@{ Name = 'wuauserv'; Status = 'Running' } }
            Mock Get-PendingUpdateCount { 0 }
            Mock Test-Path { $true }
            Mock Remove-Item { }
            Mock New-Item { }
            Mock Set-ItemProperty { }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Remove-Item -Times 1 -Exactly -Because "stale marker should be cleared"
            Should -Invoke Set-ItemProperty -Times 0 -Exactly
        }

        It "Records first observation of pending updates without flagging (returns 0)" {
            function Get-Service { }
            Mock Get-Service { [pscustomobject]@{ Name = 'wuauserv'; Status = 'Running' } }
            Mock Get-PendingUpdateCount { 3 }
            Mock Test-Path { $false }
            Mock New-Item { }
            Mock Set-ItemProperty { }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'first observation'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke New-Item -Times 1 -Exactly
            Should -Invoke Set-ItemProperty -Times 1 -Exactly
        }

        It "Flags pending updates stuck for more than 7 days (returns 1)" {
            function Get-Service { }
            Mock Get-Service { [pscustomobject]@{ Name = 'wuauserv'; Status = 'Running' } }
            Mock Get-PendingUpdateCount { 2 }
            Mock Test-Path { $true }
            Mock Get-ItemProperty { [pscustomobject]@{ FirstSeen = '2020-01-01T00:00:00.0000000+00:00' } }
            Mock Set-ItemProperty { }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Does not flag recent pending updates inside the 7-day window (returns 0)" {
            function Get-Service { }
            Mock Get-Service { [pscustomobject]@{ Name = 'wuauserv'; Status = 'Running' } }
            Mock Get-PendingUpdateCount { 2 }
            Mock Test-Path { $true }
            Mock Get-ItemProperty { [pscustomobject]@{ FirstSeen = (Get-Date).AddDays(-2).ToString('o') } }
            Mock Set-ItemProperty { }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'not yet stuck'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It "Resets an unparseable marker and re-observes without flagging (returns 0)" {
            function Get-Service { }
            Mock Get-Service { [pscustomobject]@{ Name = 'wuauserv'; Status = 'Running' } }
            Mock Get-PendingUpdateCount { 1 }
            Mock Test-Path { $true }
            Mock Get-ItemProperty { [pscustomobject]@{ FirstSeen = 'not-a-date' } }
            Mock Set-ItemProperty { }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'marker reset'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-ItemProperty -Times 1 -Exactly
        }

        It "Returns 1 when the Windows Update service is missing" {
            function Get-Service { }
            Mock Get-Service { $null }
            Mock Get-PendingUpdateCount { throw "should not be reached" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 when the update search fails" {
            function Get-Service { }
            Mock Get-Service { [pscustomobject]@{ Name = 'wuauserv'; Status = 'Running' } }
            Mock Get-PendingUpdateCount { throw "COM blew up" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'Could not query updates'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Supports -WhatIf: no marker mutations occur" {
            function Get-Service { }
            Mock Get-Service { [pscustomobject]@{ Name = 'wuauserv'; Status = 'Running' } }
            Mock Get-PendingUpdateCount { 3 }
            Mock Test-Path { $false }
            Mock New-Item { }
            Mock Set-ItemProperty { }
            $out = Main -WhatIf *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke New-Item -Times 0 -Exactly -Because "WhatIf must suppress mutations"
            Should -Invoke Set-ItemProperty -Times 0 -Exactly -Because "WhatIf must suppress mutations"
        }
    }
}
