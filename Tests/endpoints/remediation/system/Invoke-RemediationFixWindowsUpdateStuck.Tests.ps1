#Requires -Modules Pester

Describe 'Invoke-RemediationFixWindowsUpdateStuck' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationFixWindowsUpdateStuck.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # No Windows-only cmdlets are used: Get-Service / Stop-Service / Rename-Item /
        # Start-Service all exist on Linux pwsh and are mocked per test.
        # Cache paths resolve under %SystemRoot%; Linux CI has no such variable.
        $env:SystemRoot = "$TestDrive/Windows"

    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationFixWindowsUpdateStuck\.ps1'
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
        It 'Removes the marker, stops services, renames caches and returns 0' {
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*WUStuckFirstSeen' }
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*SoftwareDistribution' }
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*catroot2' }
            Mock Remove-Item { }
            Mock Stop-Service { }
            Mock Rename-Item { }
            Mock Start-Service { }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[\+\] Windows Update reset complete'
            Should -Invoke Remove-Item -Times 1
            Should -Invoke Stop-Service -Times 1
            Should -Invoke Rename-Item -Times 2
            Should -Invoke Rename-Item -ParameterFilter { $NewName -eq 'SoftwareDistribution.old' } -Times 1
            Should -Invoke Rename-Item -ParameterFilter { $NewName -eq 'catroot2.old' } -Times 1
            Should -Invoke Start-Service -Times 1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Is idempotent: no marker and no unrenamed cache folders returns 0 untouched' {
            Mock Test-Path { $false }
            Mock Remove-Item { }
            Mock Stop-Service { }
            Mock Rename-Item { }
            Mock Start-Service { }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[\+\] Already reset: no stuck Windows Update state found'
            Should -Not -Invoke Remove-Item
            Should -Not -Invoke Stop-Service
            Should -Not -Invoke Rename-Item
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 and writes [-] prefixed output when services cannot be stopped' {
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*WUStuckFirstSeen' }
            Mock Test-Path { $false } -ParameterFilter { $Path -like '*SoftwareDistribution' }
            Mock Test-Path { $false } -ParameterFilter { $Path -like '*catroot2' }
            Mock Stop-Service { throw "service will not stop" }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: marker key is kept and cache folders are not renamed' {
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*WUStuckFirstSeen' }
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*SoftwareDistribution' }
            Mock Test-Path { $false } -ParameterFilter { $Path -like '*catroot2' }
            Mock Remove-Item { }
            Mock Stop-Service { }
            Mock Rename-Item { }
            Mock Start-Service { }

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Main *>&1 | Out-Null
                Should -Not -Invoke Remove-Item -Because '-WhatIf must keep the first-seen marker key'
                Should -Not -Invoke Stop-Service -Because '-WhatIf must not stop services'
                Should -Not -Invoke Rename-Item -Because '-WhatIf must not rename cache folders'
                Should -Not -Invoke Start-Service
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
