#Requires -Modules Pester

Describe "Get-AppInstallationStatus" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/intune/reporting/;
        # the script sits under <repo root>/scripts/endpoints/intune/reporting/.
        $repoRoot = Join-Path $PSScriptRoot "../../../.."
        $scriptPath = Join-Path $repoRoot "scripts/endpoints/intune/reporting/Get-AppInstallationStatus.ps1"

        # --- Mock all externals so nothing leaves the machine (offline, no Graph tenant) ---
        # IntuneGraphHelper.psm1 / Microsoft.Graph surfaces are mocked at command-name level.
        # Pester requires the command to exist before Mock, so declare minimal stubs first
        # (the real Import-Module is mocked below and never runs).
        function Connect-IntuneGraph { param([string[]]$Scopes) $true }
        function Disconnect-IntuneGraph { }
        function Export-IntuneReportToHTML { param($Data, $Title, $FilePath) return $FilePath }
        function Export-IntuneReportToCSV { param($Data, $Title, $FilePath) return $FilePath }
        function Invoke-MgGraphRequest { param([string]$Uri) throw "Invoke-MgGraphRequest not mocked for URI: $Uri" }
        Mock Import-Module { }

        Mock Test-Path { $true }
        Mock New-Item { }
        Mock Connect-IntuneGraph { $true }
        Mock Disconnect-IntuneGraph { }
        Mock Export-IntuneReportToHTML { return "/tmp/fake.html" }
        Mock Export-IntuneReportToCSV { return "/tmp/fake.csv" }

        $statusData = @(
            [pscustomobject]@{
                deviceName = 'PC-01'; userName = 'user1@contoso.com'; installState = 'installed'
                lastSyncDateTime = [datetime]'2026-08-20 10:00:00'; osVersion = '10.0.19045'; osDescription = 'Windows'
                errorCode = $null; installStateDetail = $null
            },
            [pscustomobject]@{
                deviceName = 'PC-02'; userName = 'user2@contoso.com'; installState = 'failed'
                lastSyncDateTime = [datetime]'2026-08-19 08:30:00'; osVersion = '10.0.19045'; osDescription = 'Windows'
                errorCode = [long]2147483655; installStateDetail = 'noOp'
            },
            [pscustomobject]@{
                deviceName = 'PC-03'; userName = 'user3@contoso.com'; installState = 'pendingInstall'
                lastSyncDateTime = $null; osVersion = '11.0.22621'; osDescription = 'Windows'
                errorCode = $null; installStateDetail = $null
            }
        )

        function script:Get-FakeGraphApp {
            [pscustomobject]@{
                id = 'app-123'; displayName = 'Test App'; publisher = 'Contoso'
                '@odata.type' = '#microsoft.graph.win32LobApp'
            }
        }

        Mock Invoke-MgGraphRequest {
            param($Uri)
            # Order matters: most specific URIs first
            switch -Wildcard ($Uri) {
                '*deviceStatuses*' {
                    [pscustomobject]@{ value = $statusData }
                }
                '*mobileApps/app-123' {
                    Get-FakeGraphApp
                }
                '*mobileApps' {
                    [pscustomobject]@{ value = @(Get-FakeGraphApp) }
                }
                default {
                    throw "Unexpected Graph URI in test: $Uri"
                }
            }
        }
    }

    Context "Help & Metadata" {
        It "Is UTF-8 with BOM and CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            $hasUtf8Bom = ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            ($bytes.Length -gt 3 -and $hasUtf8Bom) | Should -BeTrue
            $raw = [System.IO.File]::ReadAllText($scriptPath)
            $raw.Contains("`n") | Should -BeTrue
            ($raw -split "`n" | Where-Object { $_ -notmatch "`r$" }) | Should -BeNullOrEmpty
        }

        It "Has required header fields: File Name, Author, Prerequisite, Version 1.0.0, Date 2026-08-23" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match '\.NOTES'
            $raw | Should -Match 'File Name\s*:\s*Get-AppInstallationStatus\.ps1'
            $raw | Should -Match 'Author\s*:'
            $raw | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match 'Version\s*:\s*1\.0\.0'
            $raw | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Has complete help: SYNOPSIS, DESCRIPTION, >=2 EXAMPLES with PS C:\> prompts" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match '\.SYNOPSIS'
            $raw | Should -Match '\.DESCRIPTION'
            $examples = [regex]::Matches($raw, '(?m)^\.EXAMPLE')
            $examples.Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>') | Measure-Object).Count | Should -BeGreaterOrEqual 2
        }

        It "Has one .PARAMETER per declared param, in param() order" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $declaredParams = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $paramMatches = [regex]::Matches((Get-Content -Raw $scriptPath), '(?m)^\.PARAMETER\s+(\S+)')
            $helpParams = @($paramMatches | ForEach-Object { $_.Groups[1].Value })
            $helpParams.Count | Should -Be ($declaredParams.Count)
            $helpParams | Should -Be $declaredParams
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
            $errors.Count | Should -Be 0
        }

        It "Contains no PS7-only operators (&&, ||, ??, ternary, -Parallel)" {
            $raw = Get-Content -Raw $scriptPath
            $codeOnly = ($raw -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
            $codeOnly | Should -Not -Match '&&'
            $codeOnly | Should -Not -Match '\|\|'
            $codeOnly | Should -Not -Match '\?\?'
            $codeOnly | Should -Not -Match '-Parallel'
        }

        It "Defines Main, sets ErrorActionPreference Stop, guards dot-source, exits only in guard line" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $isMainFn = { param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Main'
            }
            $mainFns = @($ast.FindAll($isMainFn, $true))
            $mainFns.Count | Should -BeGreaterOrEqual 1

            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match "\`$ErrorActionPreference\s*=\s*'Stop'"

            $lines = Get-Content $scriptPath
            $exitLines = @($lines | Where-Object { $_ -match '(^|[^\w-])exit([^\w-]|$)' })
            $exitLines.Count | Should -Be 1
            $exitLines[0] | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\)'
        }
    }

    Context "Behavior" {
        It "Returns 0 and exports both HTML and CSV reports for a known AppId" {
            . $scriptPath -AppId 'app-123'

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text | Should -Match '\[\*\]'
            $text | Should -Match '\[\+\]'
            $text | Should -Match 'INSTALLATION SUMMARY'
            Should -Invoke Export-IntuneReportToHTML -Times 1 -Exactly
            Should -Invoke Export-IntuneReportToCSV -Times 1 -Exactly
            Should -Invoke Disconnect-IntuneGraph -Times 1 -Exactly
        }

        It "Applies -ShowFailuresOnly filter to exported report data" {
            . $scriptPath -AppId 'app-123' -ShowFailuresOnly

            ($out = Main *>&1 | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Export-IntuneReportToCSV -ParameterFilter {
                $Data.Count -eq 1 -and $Data[0].InstallState -eq 'Failed' -and $Data[0].DeviceName -eq 'PC-02'
            }
        }

        It "Is converged-safe: no installation data returns 0 without exporting reports" {
            Mock Invoke-MgGraphRequest {
                param($Uri)
                switch -Wildcard ($Uri) {
                    '*deviceStatuses*' { [pscustomobject]@{ value = @() } }
                    '*mobileApps/app-123' { Get-FakeGraphApp }
                    default { throw "Unexpected Graph URI in test: $Uri" }
                }
            }

            . $scriptPath -AppId 'app-123'
            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text | Should -Match '\[!\]'
            $text | Should -Match 'No installation data'
            Should -Invoke Export-IntuneReportToHTML -Times 0 -Exactly
            Should -Invoke Export-IntuneReportToCSV -Times 0 -Exactly
        }

        It "Returns 1 with [-] prefixed output when the app cannot be found" {
            Mock Invoke-MgGraphRequest { param($Uri) $null }

            . $scriptPath -AppId 'does-not-exist'
            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            $text | Should -Match '\[-\]'
            $text | Should -Match 'not found'
        }

        It "Returns 1 with [-] prefixed output when Graph requests fail" {
            Mock Invoke-MgGraphRequest { throw "graph unavailable" }

            . $scriptPath -AppId 'app-123'
            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            $text | Should -Match '\[-\]'
            $text | Should -Match 'graph unavailable'
        }

        It "Returns 1 with [-] output when Graph connection fails" {
            Mock Connect-IntuneGraph { $false }

            . $scriptPath -AppId 'app-123'
            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            $text | Should -Match '\[-\]'
            $text | Should -Match 'Failed to connect'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
        }
    }
}
