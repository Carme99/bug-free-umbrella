#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for scripts/endpoints/intune/configuration/Get-SettingsCatalogPolicyReport.ps1.

.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior using
    fully mocked external cmdlets. Runs offline on Linux pwsh; no network, elevation, or
    installed product modules required. Microsoft Graph is intercepted at the
    Get-MgDeviceManagementConfigurationPolicy stub.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/endpoints/intune/configuration
    Runs this test file.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/endpoints/intune/configuration -Output Detailed
    Runs this test file with per-test output.

.NOTES
   File Name   : Get-SettingsCatalogPolicyReport.Tests.ps1
   Author      : Bug-Free Umbrella
   Prerequisite: PowerShell 7.0
   Version     : 2.0.0
   Date        : 2026-09-16
#>

Describe 'Get-SettingsCatalogPolicyReport' {
    BeforeAll {
        $scriptRelPath = ('../../../../scripts/endpoints/intune/configuration/' +
            'Get-SettingsCatalogPolicyReport.ps1')
        $scriptPath = (Resolve-Path (Join-Path $PSScriptRoot $scriptRelPath)).Path

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Microsoft.Graph.DeviceManagement is not installed offline: declare the cmdlet as an
        # empty function with the parameter surface the script uses, then mock it.
        function Get-MgDeviceManagementConfigurationPolicy {
            [CmdletBinding()]
            param(
                [switch]$All,
                [string[]]$ExpandProperty,
                [string]$Filter
            )
        }

        $windowsPolicy = [pscustomobject]@{
            name              = 'Baseline - Windows'
            platforms         = 'windows10'
            technologies      = 'mdm'
            settingCount      = 12
            roleScopeTagIds   = @('0')
            isAssigned        = $true
            templateReference = [pscustomobject]@{ templateFamily = 'baseline' }
            assignments       = @([pscustomobject]@{
                    target = [pscustomobject]@{
                        '@odata.type'                               = '#microsoft.graph.allDevicesAssignmentTarget'
                        deviceAndAppManagementAssignmentFilterId   = 'filter-1'
                        deviceAndAppManagementAssignmentFilterType = 'include'
                    }
                })
            settingStatuses   = @([pscustomobject]@{ state = 'compliant'; deviceCount = 40 })
        }

        $iosPolicy = [pscustomobject]@{
            name              = 'iOS Security - Passcode'
            platforms         = 'iOS'
            technologies      = 'mdm'
            settingCount      = 4
            roleScopeTagIds   = @('7')
            isAssigned        = $true
            templateReference = $null
            assignments       = @([pscustomobject]@{
                    target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget' }
                })
            settingStatuses   = @([pscustomobject]@{ state = 'compliant'; deviceCount = 5 })
        }

        $brokenMacPolicy = [pscustomobject]@{
            name              = 'Unassigned macOS policy'
            platforms         = 'macOS'
            technologies      = 'mdm'
            settingCount      = 0
            roleScopeTagIds   = @()
            isAssigned        = $false
            templateReference = $null
            assignments       = @()
            settingStatuses   = @(
                [pscustomobject]@{ state = 'conflict'; deviceCount = 3 }
                [pscustomobject]@{ state = 'error'; deviceCount = 1 }
            )
        }

        Mock Get-MgDeviceManagementConfigurationPolicy {
            @($windowsPolicy, $iosPolicy, $brokenMacPolicy)
        }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath, [ref]$tokens, [ref]$parseErrors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Get-SettingsCatalogPolicyReport\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*Bug-Free Umbrella'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Documents every declared parameter, in order' {
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object {
                $_.Name.Extent.Text.TrimStart('$')
            })
            $helpParams = @([regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value })
            $declared | Should -Be @(
                'PolicyName', 'Platform', 'NonCompliantOnly', 'OutputFormat', 'OutputPath')
            $helpParams | Should -Be $declared
        }

        It 'Provides at least two examples with PS prompts' {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $parseErrors.Count | Should -Be 0
        }

        It 'Uses CmdletBinding, Main function, and dot-source guard' {
            $raw | Should -Match '\[CmdletBinding\('
            $raw | Should -Match '(?m)^function Main \{'
            $raw | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
        }

        It 'Contains no PS7-only operators and no #Requires opt-out' {
            # Token-level scan: the forbidden operator texts are built from code points so this
            # file does not itself contain them.
            $forbidden = @(
                (-join [char[]](0x3F, 0x3F))
                (-join [char[]](0x3F, 0x3F, 0x3D))
                (-join [char[]](0x26, 0x26))
                (-join [char[]](0x7C, 0x7C))
            )
            $declared = @($tokens | ForEach-Object { $_.Text })
            foreach ($operator in $forbidden) {
                $declared | Should -Not -Contain $operator
            }
            $raw | Should -Not -Match '#Requires\s+-Version'
        }

        It 'Is UTF-8 with BOM and CRLF line endings' {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }

        It 'Keeps all lines within 120 columns and free of tabs' {
            ($raw -split "`r`n" | Where-Object { $_.Length -gt 120 }) | Should -BeNullOrEmpty
            $raw | Should -Not -Match "`t"
        }

        It 'Cites Microsoft Learn in its help' {
            $raw | Should -Match 'learn\.microsoft\.com'
        }
    }

    Context 'Behavior' {
        It 'Reports every matching policy and returns 2 when a policy has findings' {
            . $scriptPath
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            $text = $out | Out-String
            $text | Should -Match 'Policies matched\s+:\s+3'
            $text | Should -Match 'Policies with zero settings: 1'
            $text | Should -Match 'Policies assigned to nobody: 1'
            $text | Should -Match 'Devices in conflict\s+:\s+3'
            $text | Should -Match 'Unassigned macOS policy: zero settings; assigned to nobody'
            Should -Invoke Get-MgDeviceManagementConfigurationPolicy -Exactly 1
            Should -Invoke Get-MgDeviceManagementConfigurationPolicy `
                -ParameterFilter { $All } -Exactly 1
        }

        It 'Returns 0 and reports a clean tenant' {
            Mock Get-MgDeviceManagementConfigurationPolicy { @($windowsPolicy, $iosPolicy) }
            . $scriptPath
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match 'Policies matched\s+:\s+2'
            $text | Should -Match '\[\+\] All settings catalog policies are clean'
        }

        It 'Filters rows but keeps every summary count under -NonCompliantOnly' {
            . $scriptPath -NonCompliantOnly
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            $text = $out | Out-String
            $text | Should -Match 'Policies matched\s+:\s+3'
            $text | Should -Match 'NonCompliantOnly selects 1 of 3 policies'
            $text | Should -Match 'Unassigned macOS policy \[macOS\]'
            $text | Should -Not -Match 'Baseline - Windows \[windows10\]'
        }

        It 'Narrows the report to one platform' {
            . $scriptPath -Platform Windows
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Policies matched\s+:\s+1'
        }

        It 'Narrows the report with a wildcard name filter' {
            . $scriptPath -PolicyName 'iOS*'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Policies matched\s+:\s+1'
        }

        It 'Returns 1 with [-] output when the Graph cmdlet is unavailable' {
            Mock Get-Command `
                -ParameterFilter { $Name -eq 'Get-MgDeviceManagementConfigurationPolicy' } { }
            . $scriptPath
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[\-\] Error: Get-MgDeviceManagementConfigurationPolicy'
            Should -Invoke Get-MgDeviceManagementConfigurationPolicy -Exactly 0
        }

        It 'Returns the documented exit code 1 when Graph throws' {
            Mock Get-MgDeviceManagementConfigurationPolicy { throw 'graph unavailable' }
            . $scriptPath
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[\-\] Error: graph unavailable'
        }

        It 'Writes the assignment filters and scope tags to a CSV report' {
            $csvPath = Join-Path $TestDrive 'settings-catalog.csv'
            . $scriptPath -OutputFormat Csv -OutputPath $csvPath
            Main | Should -Be 2
            Test-Path -LiteralPath $csvPath | Should -BeTrue
            $csv = Get-Content -LiteralPath $csvPath -Raw
            $csv | Should -Match 'filter-1 \(include\)'
            $csv | Should -Match 'Baseline - Windows'
        }

        It 'Writes a JSON report whose summary counts match the console output' {
            $jsonPath = Join-Path $TestDrive 'settings-catalog.json'
            . $scriptPath -OutputFormat Json -OutputPath $jsonPath -NonCompliantOnly
            Main | Should -Be 2
            $parsed = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
            $parsed.Summary.Matched | Should -Be 3
            $parsed.Summary.ConflictDevices | Should -Be 3
            $parsed.Summary.ErrorDevices | Should -Be 1
            $parsed.Policies.Count | Should -Be 1
        }
    }
}
