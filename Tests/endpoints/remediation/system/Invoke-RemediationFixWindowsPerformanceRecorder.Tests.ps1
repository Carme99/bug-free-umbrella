#Requires -Modules Pester

Describe 'Invoke-RemediationFixWindowsPerformanceRecorder' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationFixWindowsPerformanceRecorder.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # No Windows-only cmdlets are used: logman.exe is reached only through the
        # Get-WprSessionName / Stop-WprSession wrapper seams, which are mocked below.
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationFixWindowsPerformanceRecorder\.ps1'
            $scriptText | Should -Match 'Author\s*:'
            $scriptText | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
            $scriptText | Should -Match 'Version\s*:\s*1\.0\.0'
            $scriptText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It 'Has comment-based help with SYNOPSIS, DESCRIPTION and >=2 EXAMPLES' {
            $scriptText | Should -Match '(?m)^\.SYNOPSIS'
            $scriptText | Should -Match '(?m)^\.DESCRIPTION'
            ([regex]::Matches($scriptText, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
        }

        It 'Has one .PARAMETER entry per declared parameter' {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declaredParams = @($ast.ParamBlock.Parameters)
            $helpParams = ([regex]::Matches($scriptText, '(?m)^\.PARAMETER\b')).Count
            $helpParams | Should -Be $declaredParams.Count
        }

        It 'Declares SupportsShouldProcess at script level and inside Main' {
            ([regex]::Matches($scriptText, '\[CmdletBinding\(SupportsShouldProcess\)\]')).Count |
                Should -BeGreaterOrEqual 2
            $scriptText | Should -Match '\$PSCmdlet\.ShouldProcess\('
        }

        It 'Is wrapped in Main with a single top-level dot-source guard exit' {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $exitStatements = $ast.FindAll(
                { param($node) $node -is [System.Management.Automation.Language.ExitStatementAst] }, $true)
            $exitStatements | Should -HaveCount 1
            $exitStatements[0].Extent.Text.Trim() | Should -Be 'exit (Main)'
            $scriptText | Should -Match ([regex]::Escape('if ($MyInvocation.InvocationName -ne ''.'') { exit (Main) }'))
        }
    }

    Context 'Syntax & Static' {
        It 'Parses without errors' {
            $tokens = $null
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
        }

        It 'Uses no PS7-only operators without #Requires -Version 7.0' {
            $scriptText | Should -Not -Match '(?m)^#Requires -Version'
            $scriptText | Should -Not -Match '\|\||&&|\?\?'
        }
    }

    Context 'Behavior' {
        It 'Stops stuck WPR sessions and returns 0' {
            Mock Get-WprSessionName { @('WPR_initiated_DiagTrack') }
            Mock Stop-WprSession { 0 }
            Mock Get-Process { $null }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[\+\] Stopped WPR session: WPR_initiated_DiagTrack'
            Should -Invoke Stop-WprSession -Times 1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Warns but keeps going when a session stop fails, and still returns 0' {
            Mock Get-WprSessionName { @('WPR_initiated_A', 'WPR_initiated_B') }
            Mock Stop-WprSession -ParameterFilter { $Name -eq 'WPR_initiated_A' } { 1 }
            Mock Stop-WprSession -ParameterFilter { $Name -eq 'WPR_initiated_B' } { 0 }
            Mock Get-Process { $null }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[!\] Could not stop WPR session WPR_initiated_A'
            ($out | Out-String) | Should -Match '\[\+\] Stopped WPR session: WPR_initiated_B'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Is idempotent: converged system returns 0 with no changes' {
            Mock Get-WprSessionName { @() }
            Mock Get-Process { $null }
            Mock Stop-WprSession { 0 }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[\+\] Already clean'
            Should -Not -Invoke Stop-WprSession
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 and writes [-] prefixed output when session enumeration fails' {
            Mock Get-WprSessionName { throw "logman gone" }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: no session or process is stopped' {
            Mock Get-WprSessionName { @('WPR_initiated_Stuck') }
            Mock Stop-WprSession { 0 }
            Mock Get-Process { [pscustomobject]@{ Name = 'wpr' } }
            Mock Stop-Process { }

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Main *>&1 | Out-Null
                Should -Not -Invoke Stop-WprSession -Because '-WhatIf must suppress stopping sessions'
                Should -Not -Invoke Stop-Process -Because '-WhatIf must suppress killing wpr.exe'
            }
            finally {
                $WhatIfPreference = $false
            }
        }
    }

    AfterAll {
        # Hygiene: remove platform stubs and restore a FileSystem location so
        # nothing leaks into sibling test containers in the same Pester run.
        foreach ($cmd in @(
                'Add-AppxPackage', 'Clear-RecycleBin', 'Get-AppxPackage', 'Get-CimInstance',
                'Get-MpComputerStatus', 'Get-PhysicalDisk', 'Get-Service', 'Get-StorageReliabilityCounter',
                'Get-Volume', 'Get-WinEvent', 'Get-WinUserLanguageList', 'Get-WindowsPackage',
                'New-WinUserLanguageList', 'Optimize-Volume', 'Remove-CimInstance', 'Remove-WindowsPackage',
                'Restart-Service', 'Set-Service', 'Set-WinUserLanguageList', 'Start-Service', 'Stop-Service'
            )) {
            $existing = Get-Command $cmd -ErrorAction SilentlyContinue
            if ($existing -and $existing.CommandType -eq 'Function') {
                Remove-Item -LiteralPath "Function:global:$cmd" -Force
            }
        }
        Set-Location $PSScriptRoot
    }
}
