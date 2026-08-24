#Requires -Modules Pester

Describe 'Test-RemediationCheckMicrosoftStoreAppsHealth' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Test-RemediationCheckMicrosoftStoreAppsHealth.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
        # Parameters are declared on the stub so Pester -ParameterFilter blocks
        # can bind the named arguments the script passes.
            Set-Item -Path 'Function:global:Get-AppxPackage' -Value {
                param([string]$Name)
                throw 'Get-AppxPackage is not available on this platform'
            }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Test-RemediationCheckMicrosoftStoreAppsHealth\.ps1'
            $scriptText | Should -Match 'Author\s*:'
            $scriptText | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
            $scriptText | Should -Match 'Version\s*:\s*1\.0\.0'
            $scriptText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It 'Documents its detect exit-code contract in DESCRIPTION' {
            $scriptText | Should -Match '(?m)^\.DESCRIPTION'
            $scriptText | Should -Match 'Exit codes?: 0 ='
            $scriptText | Should -Match '(?s)Exit codes?: 0 =.+?issues detected'
        }

        It 'Has comment-based help with SYNOPSIS and >=2 EXAMPLES' {
            $scriptText | Should -Match '(?m)^\.SYNOPSIS'
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
        It 'Returns 0 when all Store apps are healthy' {
            Mock Get-AppxPackage { [pscustomobject]@{ Name = 'Microsoft.WindowsStore'; Status = 'Ok' } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Microsoft Store apps are healthy'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 when the Microsoft Store app is not installed' {
            Mock Get-AppxPackage { $null }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'Microsoft Store app is not installed'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Returns 1 when AppX packages are in an error state' {
            # Unfiltered call enumerates all packages: two broken ones.
            Mock Get-AppxPackage {
                @(
                    [pscustomobject]@{ Name = 'Microsoft.Broken'; Status = 'Modified' },
                    [pscustomobject]@{ Name = 'Microsoft.Other'; Status = 'Tampered' }
                )
            } -ParameterFilter { -not $Name }
            # Named calls (Store + critical apps) resolve to healthy packages.
            Mock Get-AppxPackage { [pscustomobject]@{ Name = $Name; Status = 'Ok' } } -ParameterFilter { $Name }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match '2 AppX packages with errors'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Returns 1 when a critical app is in an error state' {
            Mock Get-AppxPackage {
                [pscustomobject]@{ Name = 'Microsoft.WindowsStore'; Status = 'Ok' }
            } -ParameterFilter { $Name -eq 'Microsoft.WindowsStore' }
            Mock Get-AppxPackage {
                [pscustomobject]@{ Name = 'Microsoft.WindowsCalculator'; Status = 'Modified' }
            } -ParameterFilter { $Name -eq 'Microsoft.WindowsCalculator' }
            Mock Get-AppxPackage {
                [pscustomobject]@{ Name = $Name; Status = 'Ok' }
            } -ParameterFilter { $Name -eq 'Microsoft.WindowsCamera' -or $Name -eq 'Microsoft.People' }
            Mock Get-AppxPackage { $null } -ParameterFilter { -not $Name }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'Microsoft\.WindowsCalculator is in error state'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Returns 1 and writes [-] prefixed output on upstream failure' {
            Mock Get-AppxPackage { throw "AppX deployment service gone" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
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
