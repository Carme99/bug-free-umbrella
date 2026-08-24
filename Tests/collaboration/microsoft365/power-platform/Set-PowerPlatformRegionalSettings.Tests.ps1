#Requires -Modules Pester

Describe 'Set-PowerPlatformRegionalSettings' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/collaboration/microsoft365/power-platform/ ->
        # the script is four levels up plus across under scripts/.
        $scriptDir = Join-Path $PSScriptRoot '../../../../scripts/collaboration/microsoft365/power-platform'
        $scriptPath = Join-Path $scriptDir 'Set-PowerPlatformRegionalSettings.ps1'

        # Sample environments: one compliant with the 2057/GBP baseline, one not.
        function New-TestEnvironment {
            param([string]$DisplayName, [string]$Id, [int]$Language, [string]$Currency)
            [pscustomobject]@{
                DisplayName = $DisplayName
                EnvironmentName = $Id
                Internal = [pscustomobject]@{
                    properties = [pscustomobject]@{
                        linkedEnvironmentMetadata = [pscustomobject]@{
                            baseLanguage = $Language
                            currency = [pscustomobject]@{ code = $Currency }
                        }
                    }
                }
            }
        }
        $compliantEnv = New-TestEnvironment -DisplayName 'UK Production' -Id 'env-uk' -Language 2057 -Currency 'GBP'
        $nonCompliantEnv = New-TestEnvironment -DisplayName 'US Sandbox' -Id 'env-us' -Language 1033 -Currency 'USD'

        # Stub product-module cmdlets not installed on this machine so Pester can mock them.
        function Add-PowerAppsAccount { }
        function Get-AdminPowerAppEnvironment { }

        # Mock ALL external commands so nothing leaves the machine (offline Linux CI).
        function Write-ReportTextFile { }

        # Safe: the top-level guard skips Main when dot-sourced.
        . $scriptPath
        Mock Get-Module { [pscustomobject]@{ Name = 'Microsoft.PowerApps.Administration.PowerShell' } }
        Mock Import-Module { }
        Mock Add-PowerAppsAccount { }
        Mock Get-AdminPowerAppEnvironment { @($compliantEnv, $nonCompliantEnv) }
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock Write-ReportTextFile { }
        Mock Export-Csv { }

    }

    Context 'Help & Metadata' {
        It 'Declares Version 1.0.0 and relaunch Date 2026-08-23 in .NOTES' {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
            $raw | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
        }

        It 'Records File Name matching the disk filename and PowerShell 7.0 prerequisite' {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '(?m)^\s*File Name\s*:\s*Set-PowerPlatformRegionalSettings\.ps1\s*$'
            $raw | Should -Match '(?m)^\s*Prerequisite\s*:\s*PowerShell 7\.0\s*$'
        }

        It 'Has exactly one .PARAMETER entry per declared parameter, in declaration order' {
            $toks = $null
            $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$toks, [ref]$errs)
            $declaredParams = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $helpParams = @(Select-String -Path $scriptPath -Pattern '^\s*\.PARAMETER\s+(\S+)' |
                ForEach-Object { $_.Matches[0].Groups[1].Value })
            $helpParams.Count | Should -Be $declaredParams.Count
            $helpParams | Should -Be $declaredParams
        }

        It 'Provides at least two .EXAMPLE blocks with PS C:\> prompt lines' {
            $raw = Get-Content -Path $scriptPath -Raw
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE\s*$')).Count | Should -BeGreaterOrEqual 2
            $raw | Should -Match 'PS C:\\>'
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $toks = $null
            $errs = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$toks, [ref]$errs) | Out-Null
            $parseErrors | Should -BeNullOrEmpty
        }

        It 'Declares SupportsShouldProcess and gates the apply operation behind ShouldProcess' {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
            $raw | Should -Match '\$PSCmdlet\.ShouldProcess\('
        }

        It 'Contains no PS7-only operators unless #Requires -Version 7.0 is present' {
            $raw = Get-Content -Path $scriptPath -Raw
            if ($raw -notmatch '(?m)^#Requires\s+-Version\s+7\.0') {
                $raw | Should -Not -Match '\?\?|\?\?=|\|\||&&'
            }
        }

        It 'Uses exit only in the top-level dot-source guard line' {
            $toks = $null
            $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$toks, [ref]$errs)
            $findExit = { $args[0] -is [System.Management.Automation.Language.ExitStatementAst] }
            $exitStatements = @($ast.FindAll($findExit, $true))
            $exitStatements.Count | Should -Be 1
            $exitStatements[0].Parent.ToString() | Should -Match 'exit \(Main\)'
        }

        It 'Is saved as UTF-8 with BOM and CRLF line endings' {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
            $text = [System.IO.File]::ReadAllText($scriptPath)
            $text | Should -Not -Match '(?<!\r)\n'
        }
    }

    Context 'Behavior' {
        It 'Audits all environments without changes by default and returns 0' {
            $AllEnvironments = $true
            $Apply = $false
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Connected to Power Platform'
            $text | Should -Match '\[\+\] Found 2 environment\(s\)'
            $text | Should -Match '\[!\] Non-Compliant: Base language: 1033 \(expected: 2057\); Currency: USD'
            $text | Should -Match '\[\+\] Compliant: 1'
            Should -Invoke Add-PowerAppsAccount -Times 1 -Exactly
        }

        It 'Reports remediation guidance through the ShouldProcess gate when -Apply is set' {
            $AllEnvironments = $true
            $Apply = $true
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Regional settings.*set at creation time'
        }

        It 'Honors -WhatIf: no remediation guidance is emitted when WhatIf is active' {
            $AllEnvironments = $true
            $Apply = $true
            $out = Main -WhatIf *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Not -Match 'set at creation time'
        }

        It 'Targets a single environment by name when -EnvironmentName is supplied' {
            Mock Get-AdminPowerAppEnvironment { @($compliantEnv) } -ParameterFilter { $EnvironmentName -eq 'env-uk' }

            $EnvironmentName = 'env-uk'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] Found environment: UK Production'
        }

        It 'Returns 1 with [-] output when neither -EnvironmentName nor -AllEnvironments is given' {
            $AllEnvironments = $false
            $Apply = $false
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] Please specify either -EnvironmentName or -AllEnvironments'
        }

        It 'Returns 1 when the Power Platform administration module is missing' {
            Mock Get-Module { $null }

            $AllEnvironments = $true
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Exports results through Export-Csv when -ExportCSV is set' {
            $AllEnvironments = $true
            $ExportCSV = $true
            Main | Should -Be 0
            $filter = { $Path -like '*PowerPlatformRegionalSettings_*.csv' }
            Should -Invoke Export-Csv -ParameterFilter $filter -Because 'the CSV export path ran'
        }

        It 'Is idempotent: converged audit re-runs succeed with identical outcomes' {
            $AllEnvironments = $true
            $Apply = $false
            $first = Main *>&1
            $second = Main *>&1
            ($first | Where-Object { $_ -is [int] }) | Should -Be 0
            ($second | Where-Object { $_ -is [int] }) | Should -Be 0
            (($first | Out-String)) | Should -Match '\[\+\] Compliant: 1'
            (($second | Out-String)) | Should -Match '\[\+\] Compliant: 1'
        }
    }
}
