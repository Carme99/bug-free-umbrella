#Requires -Modules Pester

Describe "Get-AutopilotDeploymentReport" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/intune/reporting/ ->
        # the script is four levels up plus across under scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/intune/reporting/Get-AutopilotDeploymentReport.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Stub product-module cmdlets not installed on this machine so Pester can mock them.
        function Connect-MgGraph { }
        function Get-MgContext { }
        function Get-MgDeviceManagementManagedDevice { }

        # Safe: the top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Mock ALL external commands so nothing leaves the machine (offline Linux CI).
        Mock Get-Module { [pscustomobject]@{ Name = 'Microsoft.Graph' } } -ParameterFilter {
            $ListAvailable -and $Name -in @('Microsoft.Graph.Authentication', 'Microsoft.Graph.DeviceManagement')
        }
        Mock Get-MgContext { [pscustomobject]@{ Account = 'admin@contoso.com' } }
        Mock Connect-MgGraph { }
        Mock Get-MgDeviceManagementManagedDevice {
            @(
                [pscustomobject]@{
                    DeviceName        = 'LTW1010013'
                    SerialNumber      = 'SN001'
                    EnrolledDateTime  = (Get-Date).AddDays(-1)
                    ComplianceState   = 'compliant'
                    OSVersion         = '10.0.26100'
                    UserPrincipalName = 'alice@contoso.com'
                    LastSyncDateTime  = (Get-Date).AddHours(-2)
                },
                [pscustomobject]@{
                    DeviceName        = 'LTW1010334'
                    SerialNumber      = 'SN002'
                    EnrolledDateTime  = (Get-Date).AddDays(-2)
                    ComplianceState   = 'noncompliant'
                    OSVersion         = '10.0.22631'
                    UserPrincipalName = 'bob@contoso.com'
                    LastSyncDateTime  = (Get-Date).AddHours(-5)
                },
                [pscustomobject]@{
                    DeviceName        = 'LTW1010999'
                    SerialNumber      = 'SN003'
                    EnrolledDateTime  = (Get-Date).AddDays(-400)   # outside lookback window
                    ComplianceState   = 'compliant'
                    OSVersion         = '10.0.19045'
                    UserPrincipalName = 'carol@contoso.com'
                    LastSyncDateTime  = (Get-Date).AddDays(-399)
                }
            )
        }
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '(?m)^\s*File Name\s*:\s*Get-AutopilotDeploymentReport\.ps1\s*$'
            $raw | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
            $raw | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
            $raw | Should -Match '(?m)^\s*Prerequisite\s*:\s*PowerShell 7\.0\s*$'
        }

        It "Has SYNOPSIS, DESCRIPTION and at least two EXAMPLES with PS C:\> prompts" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
            (Get-Content -Path $scriptPath -Raw) | Should -Match 'PS C:\\>'
        }

        It "Declares one .PARAMETER per param() parameter, in declaration order" {
            $toks = $null
            $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$toks, [ref]$errs)
            $declaredParams = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $documentedParams = @(Select-String -Path $scriptPath -Pattern '^\s*\.PARAMETER\s+(\S+)' |
                ForEach-Object { $_.Matches[0].Groups[1].Value })
            $documentedParams.Count | Should -Be $declaredParams.Count
            $documentedParams | Should -Be $declaredParams
        }
    }

    Context "Syntax & Static" {
        BeforeAll {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        }
        It "Parses with zero errors" {
            $errors | Should -BeNullOrEmpty
        }
        It "Contains no PS7-only operators (no #Requires -Version 7.0 opt-out present)" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Not -Match '(?m)&&|\|\||\?\?|\?\??='
        }
        It "Uses exit only in the top-level dot-source guard line" {
            $findExit = { $args[0] -is [System.Management.Automation.Language.ExitStatementAst] }
            $exitStatements = @($ast.FindAll($findExit, $true))
            $exitStatements.Count | Should -Be 1
            $exitStatements[0].Parent.ToString() | Should -Match 'exit \(Main\)'
        }
        It "Is saved as UTF-8 with BOM and CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
            [System.IO.File]::ReadAllText($scriptPath) | Should -Not -Match '(?<!\r)\n'
        }
    }

    Context "Behavior" {
        It "Returns 0 and summarizes deployments with [+]/[-]/[!] prefixes; devices outside lookback excluded" {
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[\*\] Autopilot Deployment Report'
            $text | Should -Match '\[\+\] Connected successfully'
            $text | Should -Match '\[\+\] Found 2 deployments'
            $text | Should -Match 'Total Deployments: 2'
            $text | Should -Match '\[\+\] Compliant: 1'
            $text | Should -Match '\[-\] NonCompliant: 1'
            $text | Should -Match '\[!\] Unknown: 0'
        }

        It "Reuses an existing Graph session without reconnecting when Get-MgContext returns one" {
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Connect-MgGraph -Times 0 -Exactly `
                -Because 'an existing Graph context means no reconnect is needed'
        }

        It "Connects when no existing session exists and reports success" {
            Mock Get-MgContext { $null }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] Connected successfully'
            Should -Invoke Connect-MgGraph -Times 1 -Exactly
        }

        It "Filters to only compliant devices when -Status Compliant is set" {
            $Status = 'Compliant'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Found 1 deployments'
            $text | Should -Match '\[\+\] Compliant: 1'
            $text | Should -Match '\[-\] NonCompliant: 0'
        }

        It "Returns 1 and writes [-] output when the device query fails" {
            Mock Get-MgDeviceManagementManagedDevice { throw 'tenant unreachable' }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] Error querying devices: tenant unreachable'
        }

        It "Returns 1 when a required Microsoft.Graph module is missing" {
            Mock Get-Module { $null } -ParameterFilter {
                $ListAvailable -and $Name -in @('Microsoft.Graph.Authentication', 'Microsoft.Graph.DeviceManagement')
            }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] .* module not found!'
        }

        It "Exports a CSV report when -ExportCSV is set" {
            $ExportCSV = $true
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] CSV report:'
        }

        It "Is idempotent: repeated read-only runs both return 0" {
            (Main *>&1) | Where-Object { $_ -is [int] } | Should -Be 0
            (Main *>&1) | Where-Object { $_ -is [int] } | Should -Be 0
        }
    }
}
