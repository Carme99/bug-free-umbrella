#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/infrastructure/windows/cluster/Test-FailoverClusterHealth.ps1.
.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behaviour of the
    failover cluster health audit using fully mocked FailoverClusters cmdlets. Runs offline on
    Linux pwsh; no network, elevation, or installed product modules required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/infrastructure/windows/cluster/Test-FailoverClusterHealth.Tests.ps1
    Runs this test file.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/infrastructure/windows/cluster/Test-FailoverClusterHealth.Tests.ps1 `
        -Output Detailed
    Runs this test file with per-test output.
.NOTES
    File Name   : Test-FailoverClusterHealth.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Test-FailoverClusterHealth' {
    BeforeAll {
        $relativePath = '../../../../scripts/infrastructure/windows/cluster/Test-FailoverClusterHealth.ps1'
        $scriptPath = Join-Path $PSScriptRoot $relativePath

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC section 3).
        . $scriptPath

        # The FailoverClusters module is not installed offline: declare its cmdlets as empty
        # advanced functions with their real parameter sets, then Mock each one.
        function Get-ClusterNode {
            [CmdletBinding()]
            param(
                [Parameter()][string[]]$Name,
                [Parameter()][object]$InputObject,
                [Parameter()][string]$Cluster
            )
        }

        function Get-ClusterQuorum {
            [CmdletBinding()]
            param(
                [Parameter()][string]$Cluster,
                [Parameter()][object]$InputObject
            )
        }

        function Get-ClusterResource {
            [CmdletBinding()]
            param(
                [Parameter()][string[]]$Name,
                [Parameter()][guid]$VMId,
                [Parameter()][object]$InputObject,
                [Parameter()][string]$Cluster
            )
        }

        function Get-ClusterSharedVolume {
            [CmdletBinding()]
            param(
                [Parameter()][string[]]$Name,
                [Parameter()][object]$InputObject,
                [Parameter()][string]$Cluster
            )
        }

        function Test-Cluster {
            [CmdletBinding()]
            param(
                [Parameter()][object[]]$Node,
                [Parameter()][object[]]$Disk,
                [Parameter()][object[]]$Pool,
                [Parameter()][string]$ReportName,
                [Parameter()][switch]$List,
                [Parameter()][object[]]$Include,
                [Parameter()][object[]]$Ignore,
                [Parameter()][switch]$Force,
                [Parameter()][object]$InputObject,
                [Parameter()][string]$Cluster,
                [Parameter()][switch]$WhatIf,
                [Parameter()][switch]$Confirm
            )
        }

        Mock Import-Module { }

        # Default inventory: a two node cluster with a disk witness, one online resource and one
        # online Cluster Shared Volume.
        Mock Get-ClusterNode {
            @(
                [pscustomobject]@{ Name = 'CLU1'; State = 'Up'; NodeWeight = 1 }
                [pscustomobject]@{ Name = 'CLU2'; State = 'Up'; NodeWeight = 1 }
            )
        }

        Mock Get-ClusterQuorum {
            [pscustomobject]@{
                QuorumType     = 'NodeAndDiskMajority'
                QuorumResource = [pscustomobject]@{ Name = 'Cluster Disk Witness'; State = 'Online' }
            }
        }

        Mock Get-ClusterResource {
            @(
                [pscustomobject]@{
                    Name         = 'Cluster IP Address'
                    State        = 'Online'
                    ResourceType = 'IP Address'
                    OwnerNode    = 'CLU1'
                }
            )
        }

        Mock Get-ClusterSharedVolume {
            @(
                [pscustomobject]@{ Name = 'Cluster Disk 3'; State = 'Online'; OwnerNode = 'CLU1' }
            )
        }

        Mock Test-Cluster {
            @(
                [pscustomobject]@{ Name = 'Validate Cluster Network Configuration'; Status = 'Passed' }
            )
        }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens,
            [ref]$errors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Test-FailoverClusterHealth\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            foreach ($name in @('ClusterName', 'IncludeClusterValidation', 'OutputFormat',
                    'OutputPath')) {
                $raw | Should -Match "(?m)\.PARAMETER\s+$name"
            }
        }

        It 'Provides at least two examples with PS prompts' {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, '(?m)^\s*PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }

        It 'Documents the exit codes and cites Microsoft Learn' {
            $raw | Should -Match 'Exit codes: 0 = healthy'
            $raw | Should -Match '2 = findings present'
            $raw | Should -Match '1 = error'
            $raw | Should -Match 'learn\.microsoft\.com/powershell/module/failoverclusters/'
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $errors.Count | Should -Be 0
        }

        It 'Uses CmdletBinding, Main function, and dot-source guard' {
            $raw | Should -Match '\[CmdletBinding\('
            $raw | Should -Match '(?m)function Main\b'
            $raw | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
        }

        It 'Contains no PS7-only operators and no #Requires opt-out' {
            ($raw -match '\?\?') | Should -BeFalse
            ($raw -match '\|\|') | Should -BeFalse
            ($raw -match '&&') | Should -BeFalse
            ($raw -match '#Requires\s+-Version') | Should -BeFalse
        }

        It 'Is UTF-8 with BOM and CRLF line endings' {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }

        It 'Guards the module import inside Main and exits 1 with a [-] line' {
            $raw | Should -Match 'Import-Module FailoverClusters -ErrorAction Stop'
            $raw | Should -Match 'Get-Command Get-ClusterNode -ErrorAction SilentlyContinue'
        }
    }

    Context 'Behavior' {
        It 'Reports a healthy cluster and exits 0' {
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Found 2 node\(s\)'
            $text | Should -Match "\[\+\] Quorum is NodeAndDiskMajority across 2 node\(s\)"
            $text | Should -Match 'Quorum witness: Cluster Disk Witness'
            $text | Should -Match 'Findings: 0'
            $text | Should -Match "\[\+\] Failover cluster .* passed every check\."
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-ClusterNode -Times 1 -Exactly
            Should -Invoke Get-ClusterQuorum -Times 1 -Exactly
            Should -Invoke Get-ClusterSharedVolume -Times 1 -Exactly
        }

        It 'Flags a node that is not Up and exits 2' {
            Mock Get-ClusterNode {
                @(
                    [pscustomobject]@{ Name = 'CLU1'; State = 'Up'; NodeWeight = 1 }
                    [pscustomobject]@{ Name = 'CLU2'; State = 'Down'; NodeWeight = 1 }
                )
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match "\[!\] Node 'CLU2' is Down"
            $text | Should -Match 'Node state Down'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Flags a NodeMajority quorum on an even node count and exits 2' {
            Mock Get-ClusterQuorum {
                [pscustomobject]@{
                    QuorumType     = 'NodeMajority'
                    QuorumResource = [pscustomobject]@{ Name = 'Cluster Disk Witness' }
                }
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[!\] Quorum is NodeMajority with an even node count \(2\)'
            $text | Should -Match 'NodeMajority quorum on an even node count'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Accepts a NodeMajority quorum on an odd node count' {
            Mock Get-ClusterQuorum {
                [pscustomobject]@{
                    QuorumType     = 'NodeMajority'
                    QuorumResource = $null
                }
            }
            Mock Get-ClusterNode {
                @(
                    [pscustomobject]@{ Name = 'CLU1'; State = 'Up'; NodeWeight = 1 }
                    [pscustomobject]@{ Name = 'CLU2'; State = 'Up'; NodeWeight = 1 }
                    [pscustomobject]@{ Name = 'CLU3'; State = 'Up'; NodeWeight = 1 }
                )
            }
            $out = Main *>&1
            $text = $out | Out-String
            ($text -match 'even node count') | Should -BeFalse
            $text | Should -Match 'Quorum witness: <none>'
            $text | Should -Match 'Findings: 0'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
        }

        It 'Flags a failed resource and exits 2' {
            Mock Get-ClusterResource {
                @(
                    [pscustomobject]@{
                        Name         = 'Cluster Disk 4'
                        State        = 'Failed'
                        ResourceType = 'Physical Disk'
                        OwnerNode    = 'CLU2'
                    }
                )
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match "\[!\] Resource 'Cluster Disk 4' is Failed"
            $text | Should -Match 'Resources: 1 \(1 failed\)'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Reports a non-Online resource without treating it as a finding' {
            Mock Get-ClusterResource {
                @(
                    [pscustomobject]@{
                        Name         = 'Cluster Disk 5'
                        State        = 'Offline'
                        ResourceType = 'Physical Disk'
                        OwnerNode    = 'CLU1'
                    }
                )
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match 'Resource state Offline'
            $text | Should -Match 'Findings: 0'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-ClusterResource -Times 1 -Exactly
        }

        It 'Flags a failed Cluster Shared Volume and exits 2' {
            Mock Get-ClusterSharedVolume {
                @(
                    [pscustomobject]@{ Name = 'Cluster Disk 7'; State = 'Failed'; OwnerNode = 'CLU2' }
                )
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match "\[!\] Cluster Shared Volume 'Cluster Disk 7' is Failed"
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Does not run Test-Cluster unless -IncludeClusterValidation is set' {
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Test-Cluster -Times 0 -Exactly `
                -Because 'cluster validation is opt-in'
        }

        It 'Flags a failing validation result when -IncludeClusterValidation is set' {
            $IncludeClusterValidation = $true
            Mock Test-Cluster {
                @(
                    [pscustomobject]@{
                        Name   = 'Validate Cluster Network Configuration'
                        Status = 'Failed'
                    }
                )
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match "\[!\] Validation 'Validate Cluster Network Configuration' reported Failed"
            $text | Should -Match 'Validation reported Failed'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            Should -Invoke Test-Cluster -Times 1 -Exactly `
                -ParameterFilter { $Include -contains 'Inventory' -and $Force }
        }

        It 'Reports a passing validation result without changing the exit code' {
            $IncludeClusterValidation = $true
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match 'Validation reported Passed'
            $text | Should -Match 'Findings: 0'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
        }

        It 'Exits 1 with a [-] line when the FailoverClusters module cannot be imported' {
            Mock Import-Module { throw 'module not found' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\] Error: module not found'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-ClusterNode -Times 0 -Exactly
        }

        It 'Returns 1 for an unsafe -OutputPath without querying the cluster' {
            $OutputPath = '../escape'
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\] Unsafe OutputPath'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-ClusterNode -Times 0 -Exactly
        }

        It 'Writes a JSON report under -OutputPath and leaves the working directory alone' {
            $OutputFormat = 'Json'
            $OutputPath = $TestDrive
            $workingDirectory = (Get-Location).Path
            $out = Main *>&1
            $text = $out | Out-String
            $files = @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.json')
            $files.Count | Should -Be 1
            $text | Should -Match '\[\+\] JSON report written:'
            $report = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
            $report.Findings | Should -Be 0
            $report.QuorumType | Should -Be 'NodeAndDiskMajority'
            $report.Witness | Should -Be 'Cluster Disk Witness'
            @($report.Nodes).Count | Should -Be 2
            @($report.SharedVolumes).Count | Should -Be 1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            (Get-Location).Path | Should -Be $workingDirectory
        }

        It 'Writes a CSV report with one row per check under -OutputPath' {
            $OutputFormat = 'Csv'
            $OutputPath = $TestDrive
            $out = Main *>&1
            $files = @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.csv')
            $files.Count | Should -Be 1
            $rows = @(Import-Csv -LiteralPath $files[0].FullName)
            $rows.Count | Should -BeGreaterOrEqual 6
            @($rows | Where-Object { $_.Status -ne 'Pass' }).Count | Should -Be 0
            @($rows | Where-Object { $_.Category -eq 'Quorum' }).Count | Should -Be 1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
        }

        It 'Is idempotent: repeated runs return the same exit code' {
            $firstRun = (Main *>&1 | Where-Object { $_ -is [int] })
            $secondRun = (Main *>&1 | Where-Object { $_ -is [int] })
            $firstRun | Should -Be 0
            $secondRun | Should -Be 0
        }
    }
}
