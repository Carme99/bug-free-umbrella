#Requires -Modules Pester

Describe 'Test-RemediationCheckDeviceHealthScore' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Test-RemediationCheckDeviceHealthScore.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
                Set-Item -Path "Function:global:Get-WinEvent" -Value { throw "Get-WinEvent is not available on this platform" }
                Set-Item -Path "Function:global:Get-CimInstance" -Value { throw "Get-CimInstance is not available on this platform" }
                Set-Item -Path "Function:global:Get-MpComputerStatus" -Value { throw "Get-MpComputerStatus is not available on this platform" }

        # No Defender module on Linux CI -> AV checks are skipped deterministically.
        Mock Get-WinEvent { $null }
        Mock Get-CimInstance { $null }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Test-RemediationCheckDeviceHealthScore\.ps1'
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
    }

    Context 'Behavior' {
        It 'Returns 0 with a perfect score on a healthy device (compliant)' {
            Mock Get-CimInstance {
                param($ClassName)
                if ($ClassName -eq 'Win32_OperatingSystem') {
                    [pscustomobject]@{ LastBootUpTime = (Get-Date).AddDays(-2) }
                }
                else {
                    $null   # no SMART failure predictions
                }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match 'Score: 100 / 100'
            ($out | Out-String) | Should -Match 'Status: EXCELLENT'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Get-CimInstance -Times 2 -Exactly   # OS uptime + disk SMART query
        }

        It 'Deducts points for uptime, crashes and slow boot but stays above threshold' {
            Mock Get-CimInstance {
                param($ClassName)
                if ($ClassName -eq 'Win32_OperatingSystem') {
                    [pscustomobject]@{ LastBootUpTime = (Get-Date).AddDays(-60) }
                }
                else {
                    $null   # no SMART failure predictions
                }
            }
            Mock Get-WinEvent {
                param($FilterHashtable)
                if ($FilterHashtable['ID'] -eq 100) {
                    # Latest boot took 200 seconds -> boot score drops below 100.
                    @([pscustomobject]@{ Properties = @([pscustomobject]@{ Value = 200000 }) })
                }
                else {
                    1..5 | ForEach-Object { [pscustomobject]@{ Properties = @() } }
                }
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match 'Excessive uptime'
            $text | Should -Match 'Very slow boot: 200 seconds'
            $text | Should -Match 'Issues Detected \(\d+\)'
            $text | Should -Match 'Health Report JSON'
            # Weighted deductions keep the score above the 70 threshold.
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 and writes [-] prefixed output when data collection fails' {
            Mock Get-WinEvent { throw "event log gone" }
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
