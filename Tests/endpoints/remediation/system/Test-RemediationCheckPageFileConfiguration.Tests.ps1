#Requires -Modules Pester

Describe 'Test-RemediationCheckPageFileConfiguration' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Test-RemediationCheckPageFileConfiguration.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
        # Parameters are declared on the stub so Pester -ParameterFilter blocks
        # can bind the named arguments the script passes.
            Set-Item -Path 'Function:global:Get-CimInstance' -Value {
                param([string]$ClassName)
                throw 'Get-CimInstance is not available on this platform'
            }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Test-RemediationCheckPageFileConfiguration\.ps1'
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

        It 'Documents its declared MinRatio parameter' {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            @($ast.ParamBlock.Parameters).Name.VariablePath.UserPath | Should -Be 'MinRatio'
            $scriptText | Should -Match '(?m)^\.PARAMETER\s+MinRatio'
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
        BeforeAll {
            Mock Get-CimInstance { $null } -ParameterFilter { $ClassName -eq 'Win32_PageFileSetting' }
            Mock Get-CimInstance {
                [pscustomobject]@{ AutomaticManagedPagefile = $true; TotalPhysicalMemory = 8GB }
            } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
        }

        It 'Returns 0 when the page file is system-managed (compliant)' {
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Page file is properly configured'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 0 for a custom page file at or above the MinRatio floor' {
            Mock Get-CimInstance {
                @([pscustomobject]@{ InitialSize = 8192; MaximumSize = 16384 })
            } -ParameterFilter { $ClassName -eq 'Win32_PageFileSetting' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Page file is properly configured'
            ($out | Out-String) | Should -Match 'Custom page file configured \(initial 8192 MB'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 when a custom page file initial size is below the floor' {
            Mock Get-CimInstance {
                @([pscustomobject]@{ InitialSize = 512; MaximumSize = 1024 })
            } -ParameterFilter { $ClassName -eq 'Win32_PageFileSetting' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'initial size \(512 MB\) is below the configured minimum'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Returns 1 when the page file is disabled entirely' {
            Mock Get-CimInstance { $null } -ParameterFilter { $ClassName -eq 'Win32_PageFileSetting' }
            Mock Get-CimInstance {
                [pscustomobject]@{ AutomaticManagedPagefile = $false; TotalPhysicalMemory = 8GB }
            } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'Page file is disabled \(not recommended\)'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Returns 1 and writes [-] prefixed output on upstream failure' {
            Mock Get-CimInstance { throw "WMI service gone" } -ParameterFilter { $ClassName -eq 'Win32_PageFileSetting' }
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
