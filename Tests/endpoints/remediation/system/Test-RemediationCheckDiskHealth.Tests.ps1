#Requires -Modules Pester

Describe 'Test-RemediationCheckDiskHealth' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Test-RemediationCheckDiskHealth.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
                Set-Item -Path "Function:global:Get-PhysicalDisk" -Value { throw "Get-PhysicalDisk is not available on this platform" }
                Set-Item -Path "Function:global:Get-StorageReliabilityCounter" -Value { throw "Get-StorageReliabilityCounter is not available on this platform" }
                Set-Item -Path "Function:global:Get-Volume" -Value { throw "Get-Volume is not available on this platform" }

        Mock Get-PhysicalDisk { @() }
        Mock Get-StorageReliabilityCounter { $null }
        Mock Get-Volume { @() }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Test-RemediationCheckDiskHealth\.ps1'
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
        It 'Returns 0 when all disks are healthy with ample free space (compliant)' {
            Mock Get-PhysicalDisk {
                @([pscustomobject]@{
                    FriendlyName      = 'Samsung SSD'
                    HealthStatus      = 'Healthy'
                    OperationalStatus = 'OK'
                    MediaType         = 'SSD'
                })
            }
            Mock Get-StorageReliabilityCounter {
                [pscustomobject]@{ ReadErrorsTotal = 0; WriteErrorsTotal = 0 }
            }
            Mock Get-Volume {
                @([pscustomobject]@{ DriveLetter = 'C'; DriveType = 'Fixed'; Size = 500GB; SizeRemaining = 250GB })
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match 'All disks are healthy'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Get-StorageReliabilityCounter -Times 1 -Exactly
        }

        It 'Returns 1 when a disk reports warnings and read errors (non-compliant)' {
            Mock Get-PhysicalDisk {
                @(
                    [pscustomobject]@{
                        FriendlyName      = 'Failing HDD'
                        HealthStatus      = 'Warning'
                        OperationalStatus = 'OK'
                        MediaType         = 'HDD'
                    },
                    [pscustomobject]@{
                        FriendlyName      = 'Degraded SSD'
                        HealthStatus      = 'Healthy'
                        OperationalStatus = 'Degraded'
                        MediaType         = 'SSD'
                    }
                )
            }
            Mock Get-StorageReliabilityCounter {
                [pscustomobject]@{ ReadErrorsTotal = 42; WriteErrorsTotal = 0 }
            }
            Mock Get-Volume {
                @([pscustomobject]@{ DriveLetter = 'C'; DriveType = 'Fixed'; Size = 500GB; SizeRemaining = 250GB })
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'Health status is Warning'
            ($out | Out-String) | Should -Match 'Operational status is Degraded'
            ($out | Out-String) | Should -Match '42 read errors detected'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Returns 1 when a fixed volume is critically low on space (non-compliant)' {
            Mock Get-Volume {
                @([pscustomobject]@{ DriveLetter = 'C'; DriveType = 'Fixed'; Size = 500GB; SizeRemaining = 10GB })
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'Critically low disk space'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Returns 1 and writes [-] prefixed output on upstream failure' {
            Mock Get-PhysicalDisk { throw "storage stack gone" }
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
