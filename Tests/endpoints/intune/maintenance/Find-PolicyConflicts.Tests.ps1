#Requires -Modules Pester

Describe "Find-PolicyConflicts" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/endpoints/intune/maintenance/Find-PolicyConflicts.ps1"

        # Static analysis inputs
        $rawScript = Get-Content -LiteralPath $scriptPath -Raw
        $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
        $parseErrors = $null

        function Connect-IntuneGraph { param([string[]]$Scopes) $true }
        function Disconnect-IntuneGraph { }
        function Export-IntuneReportToHTML { param($Data, $Title, $FilePath) }
        function Export-IntuneReportToCSV { param($Data, $Title, $FilePath) }
        function Invoke-MgGraphRequest { param([string]$Uri) }

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
        $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath, [ref]$null, [ref]$parseErrors)

        # Mock ALL externals so nothing leaves the machine.
        Mock Import-Module { }
        Mock Connect-IntuneGraph { $true }
        Mock Disconnect-IntuneGraph { }
        Mock Export-IntuneReportToHTML { }
        Mock Export-IntuneReportToCSV { }
        Mock Test-Path { $true }

        # Shared Graph fixtures: two configuration profiles of the SAME type assigned to the SAME group.
        $configProfileA = [pscustomobject]@{
            id                   = 'cfg-1'
            displayName          = 'Wi-Fi Policy'
            '@odata.type'        = '#microsoft.graph.windowsWifiConfiguration'
            createdDateTime      = [datetime]'2025-01-01'
            lastModifiedDateTime = [datetime]'2025-01-02'
        }
        $configProfileB = [pscustomobject]@{
            id                   = 'cfg-2'
            displayName          = 'VPN Policy'
            '@odata.type'        = '#microsoft.graph.windowsWifiConfiguration'
            createdDateTime      = [datetime]'2025-02-01'
            lastModifiedDateTime = [datetime]'2025-02-02'
        }
        $assignmentFixture = @{
            value = @(
                @{ target = @{
                        groupId       = '11111111-1111-1111-1111-111111111111'
                        '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                    }
                }
            )
        }
    }

    Context "Help & Metadata" {
        It "Contains all five required .NOTES fields with correct values" {
            $rawScript | Should -Match '\.NOTES'
            $rawScript | Should -Match 'File Name:\s*Find-PolicyConflicts\.ps1'
            $rawScript | Should -Match 'Author:\s*\S+'
            $rawScript | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
            $rawScript | Should -Match 'Version:\s*1\.0\.0'
            $rawScript | Should -Match 'Date:\s*2026-08-23'
        }

        It "Has one .PARAMETER entry per declared param, in order" {
            $declared = $scriptAst.ParamBlock.Parameters.Name.VariablePath.UserPath
            $documented = [regex]::Matches($rawScript, '(?m)^\s*\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value }
            $documented | Should -Be $declared
        }

        It "Has at least two examples with PS C:\> prompts" {
            ([regex]::Matches($rawScript, '\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($rawScript, [regex]::Escape('PS C:\>'))).Count | Should -BeGreaterOrEqual 2
        }

        It "Is saved as UTF-8 with BOM" {
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only operators (no #Requires -Version 7.0 opt-out)" {
            $rawScript | Should -Not -Match '#Requires\s+-Version'
            $rawScript | Should -Not -Match '\?\?'
            $rawScript | Should -Not -Match '&&|\|\|'
        }

        It "Defines a Main function and the dot-source guard, with exit only in the guard" {
            $guardLine = 'if ($MyInvocation.InvocationName -ne ''.'') { exit (Main) }'
            $rawScript | Should -Match ([regex]::Escape($guardLine))
            ([regex]::Matches($rawScript, '\bexit\b')).Count | Should -Be 1
        }

        It "Uses only approved verbs for internal functions" {
            $isFn = { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }
            $functions = $scriptAst.FindAll($isFn, $true) | Select-Object -ExpandProperty Name
            foreach ($fn in ($functions | Where-Object { $_ -ne 'Main' })) {
                $verb = ($fn -split '-')[0]
                (Get-Verb -Verb $verb) | Should -Not -BeNullOrEmpty -Because "$fn must use an approved verb"
            }
        }
    }

    Context "Behavior" {
        It "Returns 0, detects same-type conflicts on a shared target, and exports an HTML report" {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like "*deviceConfigurations" } {
                @{ value = @($configProfileA, $configProfileB) }
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like "*deviceConfigurations/*/assignments" } {
                $assignmentFixture
            }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'CONFLICT ANALYSIS SUMMARY'
            ($out | Out-String) | Should -Match 'Same Type Overlap'
            Should -Invoke Export-IntuneReportToHTML -Exactly 1 -Because "default ExportFormat is HTML"
            Should -Invoke Export-IntuneReportToCSV -Times 0
            Should -Invoke Disconnect-IntuneGraph -Exactly 1
        }

        It "Is idempotent on a converged tenant: no conflicts means no report and return 0" {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like "*deviceConfigurations" } {
                @{ value = @($configProfileA) }
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like "*assignments" } {
                $assignmentFixture
            }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] No policy conflicts detected!'
            Should -Invoke Export-IntuneReportToHTML -Times 0
            Should -Invoke Export-IntuneReportToCSV -Times 0
        }

        It "Handles a tenant with zero policies gracefully and returns 0" {
            Mock Invoke-MgGraphRequest { @{ value = @() } }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[!\] No policies found to analyze\.'
        }

        It "Returns 1 with [-] output when Graph connection fails" {
            Mock Connect-IntuneGraph { $false }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 with [-] output and disconnects when an upstream Graph call throws" {
            Mock Invoke-MgGraphRequest { throw "tenant unreachable" }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] Error:'
            Should -Invoke Disconnect-IntuneGraph -Exactly 1 -Because "finally must always disconnect"
        }
    }
}
