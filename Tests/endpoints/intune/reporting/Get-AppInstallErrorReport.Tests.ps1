#Requires -Modules Pester

Describe "Get-AppInstallErrorReport" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/intune/reporting/ ->
        # the script is four levels up plus across under scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/intune/reporting/Get-AppInstallErrorReport.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Stub product-module cmdlets not installed on this machine so Pester can mock them.
        function Connect-MgGraph { }
        function Invoke-MgGraphRequest { }

        # Safe: the top-level guard skips Main when dot-sourced.
        . $scriptPath

        $failureStatus = {
            [pscustomobject]@{
                value = @(
                    [pscustomobject]@{
                        installState      = 'failed'
                        deviceName        = 'LTW1010013'
                        userPrincipalName = 'alice@contoso.com'
                        errorCode         = 0x80073CF3
                        lastSyncDateTime  = (Get-Date).AddHours(-2)
                    }
                )
            }
        }

        # Mock ALL external commands so nothing leaves the machine (offline Linux CI).
        Mock Get-Module { [pscustomobject]@{ Name = 'Microsoft.Graph.Authentication' } } -ParameterFilter {
            $ListAvailable -and $Name -eq 'Microsoft.Graph.Authentication'
        }
        Mock Connect-MgGraph { }
        Mock Invoke-MgGraphRequest {
            param($Uri)
            if ($Uri -like '*mobileApps') {
                [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{ id = 'app-1'; displayName = 'Microsoft Edge' },
                        [pscustomobject]@{ id = 'app-2'; displayName = '7-Zip' }
                    )
                }
            }
            else { & $failureStatus }
        }
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '(?m)^\s*File Name\s*:\s*Get-AppInstallErrorReport\.ps1\s*$'
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
        It "Returns 0 and reports failure counts with [*]/[!] prefixes when failures exist" {
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[\*\] App Installation Error Report'
            $text | Should -Match '\[\*\] Connecting to Microsoft Graph'
            $text | Should -Match '\[!\] Found 2 failures'
            $text | Should -Match '\[!\] Total Failures: 2'
            Should -Invoke Connect-MgGraph -Times 1 -Exactly
        }

        It "Filters by -AppName so only matching apps are queried" {
            $AppName = 'Edge'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly `
                -Because 'one mobileApps list + one deviceStatuses call for the matching app'
        }

        It "Exports an HTML report when -ExportHTML is set" {
            $ExportHTML = $true
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] HTML report:'
        }

        It "Returns 1 and writes [-] prefixed output when the Graph query fails" {
            Mock Invoke-MgGraphRequest { throw 'network unreachable' }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] Error: network unreachable'
        }

        It "Returns 1 when the Microsoft.Graph.Authentication module is missing" {
            Mock Get-Module { $null } -ParameterFilter {
                $ListAvailable -and $Name -eq 'Microsoft.Graph.Authentication'
            }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] Microsoft\.Graph\.Authentication module not found!'
        }

        It "Is idempotent: repeated read-only runs both return 0" {
            (Main *>&1) | Where-Object { $_ -is [int] } | Should -Be 0
            (Main *>&1) | Where-Object { $_ -is [int] } | Should -Be 0
        }
    }
}
