#Requires -Modules Pester

Describe 'Test-RemediationCheckWindowsActivationGracePeriod' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Test-RemediationCheckWindowsActivationGracePeriod.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
                Set-Item -Path "Function:global:Get-CimInstance" -Value { throw "Get-CimInstance is not available on this platform" }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Test-RemediationCheckWindowsActivationGracePeriod\.ps1'
            $scriptText | Should -Match 'Author\s*:'
            $scriptText | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
            $scriptText | Should -Match 'Version\s*:\s*1\.0\.0'
            $scriptText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It 'Documents its detect exit-code contract in DESCRIPTION' {
            $scriptText | Should -Match '(?m)^\.DESCRIPTION'
            $scriptText | Should -Match 'Exit codes?: 0 ='
            $scriptText | Should -Match '(?s)Exit codes?: 0 =.+?1 ='
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

        It 'Does not use the PS5.1-only Get-WmiObject cmdlet' {
            $scriptText | Should -Not -Match 'Get-WmiObject'
        }
    }

    Context 'Behavior' {
        It 'Returns 0 when Windows is fully licensed and no grace period applies (compliant)' {
            Mock Get-CimInstance {
                [pscustomobject]@{
                    LicenseStatus        = 1
                    GracePeriodRemaining = 0
                    EvaluationEndDate    = $null
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Windows activation is valid'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 when Windows is in a grace period expiring within 30 days (issue detected)' {
            Mock Get-CimInstance {
                [pscustomobject]@{
                    LicenseStatus        = 2   # OOB grace
                    GracePeriodRemaining = 14400  # 10 days in minutes
                    EvaluationEndDate    = $null
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'Out-of-Box grace period'
            ($out | Out-String) | Should -Match 'Grace period expires in 10 days'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Returns 1 when Windows is unlicensed' {
            Mock Get-CimInstance {
                [pscustomobject]@{
                    LicenseStatus        = 0
                    GracePeriodRemaining = 0
                    EvaluationEndDate    = $null
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'Windows is unlicensed'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Returns 0 when no licensing product can be queried (treated as valid)' {
            Mock Get-CimInstance { $null }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Windows activation is valid'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 and writes [-] prefixed output on upstream failure' {
            Mock Get-CimInstance { throw "CIM gone" }
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
