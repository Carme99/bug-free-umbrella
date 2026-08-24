#Requires -Modules Pester

Describe 'Get-PowerPlatformGovernance' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/collaboration/microsoft365/power-platform/ ->
        # the script is four levels up plus across under scripts/.
        $scriptDir = Join-Path $PSScriptRoot '../../../../scripts/collaboration/microsoft365/power-platform'
        $scriptPath = Join-Path $scriptDir 'Get-PowerPlatformGovernance.ps1'

        # Sample tenant data
        $testEnvironments = @(
            [pscustomobject]@{
                DisplayName = 'Production'; EnvironmentName = 'env-prod'; Location = 'unitedstates'
                EnvironmentType = 'Production'; CreatedTime = (Get-Date '2025-01-01')
                IsDefault = $false; SecurityGroupId = $null
            }
            [pscustomobject]@{
                DisplayName = 'Default'; EnvironmentName = 'env-default'; Location = 'unitedstates'
                EnvironmentType = 'Default'; CreatedTime = (Get-Date '2024-01-01')
                IsDefault = $true; SecurityGroupId = $null
            }
        )
        $orphanedApp = [pscustomobject]@{
            DisplayName = 'Orphan Tracker'; AppName = 'app-orphan-1'
            Owner = [pscustomobject]@{ displayName = $null; email = $null }
            EnvironmentName = 'env-prod'; CreatedTime = (Get-Date '2025-02-01')
            LastModifiedTime = (Get-Date '2025-06-01'); IsFeaturedApp = $false
            IsHeroApp = $false; BypassConsent = $false
        }

        # Stub product-module cmdlets not installed on this machine so Pester can mock them.
        function Get-AdminPowerAppEnvironment { }
        function Get-AdminPowerAppEnvironmentCapacity { }
        function Get-AdminPowerApp { }
        function Get-AdminPowerAppConnection { }
        function Get-AdminFlow { }
        function Get-AdminDlpPolicy { }

        # Mock ALL external commands so nothing leaves the machine (offline Linux CI).
        function Write-ReportTextFile { }

        # Safe: the top-level guard skips Main when dot-sourced. TenantId is mandatory,
        # so bind it explicitly during dot-sourcing.
        . $scriptPath -TenantId '00000000-0000-0000-0000-000000000000'
        Mock Get-Module { [pscustomobject]@{ Name = 'Microsoft.PowerApps.Administration.PowerShell' } }
        Mock Get-AdminPowerAppEnvironment { $testEnvironments }
        Mock Get-AdminPowerAppEnvironmentCapacity {
            [pscustomobject]@{
                DatabaseCapacity = [pscustomobject]@{ Capacity = [pscustomobject]@{ Allocated = 10; Available = 40 } }
            }
        }
        Mock Get-AdminPowerApp { @($orphanedApp) }
        Mock Get-AdminPowerAppConnection { @() }
        Mock Get-AdminFlow { @() }
        Mock Get-AdminDlpPolicy { @() }
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
            $raw | Should -Match '(?m)^\s*File Name\s*:\s*Get-PowerPlatformGovernance\.ps1\s*$'
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
        It 'Returns 0 and reports environment counts in console output' {
            $OutputFormat = 'Console'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[\*\] Analyzing Power Platform governance for tenant:'
            $text | Should -Match '\[\+\] Found 2 environments'
            Should -Invoke Get-AdminPowerAppEnvironmentCapacity -Times 2 -Exactly
        }

        It 'Flags orphaned apps whose owner email is gone when -IncludeAppDetails is set' {
            $IncludeAppDetails = $true
            $OutputFormat = 'Console'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Found 1 Power Apps'
            $text | Should -Match 'Orphaned Resources: 1'
            $text | Should -Match '\[Power App\] Orphan Tracker - Owner not found or deleted'
            Should -Invoke Get-AdminPowerApp -Times 1 -Exactly
        }

        It 'Collects flows and orphan detection when -IncludeFlowDetails is set' {
            Mock Get-AdminFlow {
                @([pscustomobject]@{
                    DisplayName = 'Nightly Sync'; FlowName = 'flow-1'
                    CreatedBy = [pscustomobject]@{ displayName = 'Dana'; email = 'dana@contoso.com' }
                    EnvironmentName = 'env-prod'; Enabled = $true
                    CreatedTime = (Get-Date '2025-03-01'); LastModifiedTime = (Get-Date '2025-07-01')
                    Properties = [pscustomobject]@{
                        definitionSummary = [pscustomobject]@{
                            triggers = @([pscustomobject]@{ type = 'Recurrence' })
                        }
                    }
                })
            }

            $IncludeFlowDetails = $true
            $OutputFormat = 'Console'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] Found 1 Power Automate flows'
            Should -Invoke Get-AdminFlow -Times 1 -Exactly
        }

        It 'Writes the HTML report through Out-File by default' {
            $OutputFormat = 'HTML'
            Main | Should -Be 0
            $filter = { $Path -like '*PowerPlatform-Governance-*.html' }
            Should -Invoke Write-ReportTextFile -Times 1 -Exactly -ParameterFilter $filter
        }

        It 'Exports app inventory through Export-Csv when OutputFormat is CSV' {
            $IncludeAppDetails = $true
            $OutputFormat = 'CSV'
            Main | Should -Be 0
            Should -Invoke Export-Csv -Times 1 -Exactly -ParameterFilter { $Path -like '*PowerPlatform-Apps-*.csv' }
        }

        It 'Returns 1 and writes [-] prefixed output when tenant retrieval fails' {
            Mock Get-AdminPowerAppEnvironment { throw 'authentication expired' }

            $OutputFormat = 'Console'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] Error'
        }

        It 'Is idempotent: repeated runs against unchanged tenant data both return 0' {
            $OutputFormat = 'Console'
            Main | Should -Be 0
            Main | Should -Be 0
        }
    }
}
