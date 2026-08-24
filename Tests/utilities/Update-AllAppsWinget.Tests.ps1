#Requires -Modules Pester

Describe "Update-AllAppsWinget" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/utilities/ -> script is two levels up + across.
        $scriptPath = Join-Path $PSScriptRoot "../../scripts/utilities/Update-AllAppsWinget.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets absent on Linux: declare stubs so Pester can mock them.
        # Justification (PSScriptAnalyzer): $Path documents the real parameter; the stub body is intentionally empty.
        function Add-AppxPackage { param([Parameter(Mandatory = $true)][string]$Path) }

        # Neutralize filesystem logging so nothing leaves the machine.
        Mock Add-Content { }
        Mock New-Item { }
        Mock Test-Path { $true }
        Mock Start-Sleep { }

        # Windows-only identity checks: force the happy path by default.
        Mock Test-IsAdministrator { $true }
        Mock Test-RunningAsSystem { $true }

        # Default mocks so every test can assert on external invocations.
        Mock Invoke-WingetWithRetry { throw "Invoke-WingetWithRetry must not be called in this test" }
        Mock Invoke-WebRequest { }
        Mock Add-AppxPackage { }
    }

    Context "Help & Metadata" {
        BeforeAll {
            $script:help = Get-Help $scriptPath -Full
            $tokens = $null
            $parseErrors = $null
            $script:ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $script:text = Get-Content -Raw $scriptPath
        }

        It "Declares all five .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $script:text | Should -Match 'File Name\s*:\s*Update-AllAppsWinget\.ps1'
            $script:text | Should -Match 'Author\s*:\s*\S+'
            $script:text | Should -Match 'Prerequisite\s*:\s*\S+'
            $script:text | Should -Match 'Version\s*:\s*1\.0\.0'
            $script:text | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Documents exactly one .PARAMETER per declared parameter, in order" {
            $declared = @($script:ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $documented = @(
                $script:help.Parameters.Parameter |
                    Where-Object { $_.Name -notin @('WhatIf', 'Confirm') } |
                    ForEach-Object { $_.Name }
            )
            $documented | Should -Be $declared
        }

        It "Has at least two .EXAMPLE blocks, each with a PS C:\> prompt line" {
            ([regex]::Matches($script:text, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            # Get-Help strips prompt lines from Example.Code, so assert on the raw header text.
            ([regex]::Matches($script:text, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }

        It "Renders Get-Help -Detailed completely (synopsis and description populated)" {
            $script:help.Synopsis | Should -Not -BeNullOrEmpty
            ($script:help.Description.Text -join " ") | Should -Not -BeNullOrEmpty
        }
    }

    Context "Syntax & Static" {
        It "Parses cleanly via the PowerShell parser (no syntax errors)" {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Uses no PS7-only tokens while lacking #Requires -Version 7.0" {
            $text = Get-Content -Raw $scriptPath
            $hasRequires = $text -match '(?m)^#Requires\s+-Version\s+7'
            if (-not $hasRequires) {
                $text | Should -Not -Match '\?\?'
                $text | Should -Not -Match '\|\|'
                $text | Should -Not -Match '&&'
                $text | Should -Not -Match '-AsHashtable'
                $text | Should -Not -Match '-Parallel\b'
            }
        }

        It "Contains exactly one exit statement, in the top-level dot-source guard" {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            # 'exit' parses as a language keyword, not a CommandAst, so scan tokens.
            @($tokens | Where-Object { $_.Kind -eq 'Exit' -and $_.Text -eq 'exit' }).Count | Should -Be 1
            $guardLine = [regex]::Escape('if ($MyInvocation.InvocationName -ne ''.'') { exit (Main) }')
            (Get-Content -Raw $scriptPath) | Should -Match $guardLine
        }

        It "Invokes winget.exe only through the thin wrapper seam checking LASTEXITCODE" {
            $text = Get-Content -Raw $scriptPath
            $wrappers = @($script:ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -eq 'Invoke-Winget'
                }, $true))
            $wrappers.Count | Should -Be 1
            $wrapperBody = $wrappers[0].Extent.Text
            $ampersandCall = [regex]::Escape('& $Path')
            $wrapperBody | Should -Match $ampersandCall
            $wrapperBody | Should -Match '\$LASTEXITCODE'
            # Outside the wrapper, no native winget invocation remains.
            ($text.Replace($wrapperBody, '')) | Should -Not -Match '&\s*\$?\w*[Ww]inget'
        }
    }

    Context "Behavior" {
        It "Is idempotent on a converged system: returns 0 and never runs the upgrade pass" {
            Mock Test-WingetConfiguration { $true }
            # winget list --upgrade-available reports nothing to do.
            Mock Invoke-WingetWithRetry { @() }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            # source update + one list check; no upgrade call because zero updates were found.
            Should -Invoke Invoke-WingetWithRetry -Times 2 -Exactly
            Should -Invoke Invoke-WingetWithRetry -ParameterFilter { $Arguments -like 'upgrade*' } -Times 0 -Exactly `
                -Because "nothing was pending so no system mutation may occur"
            ($out | Out-String) | Should -Match '\[\+\]'
        }

        It "Returns 1 with [-] output when not running as Administrator or SYSTEM" {
            Mock Test-IsAdministrator { $false }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[\-\]'
            Should -Invoke Invoke-WingetWithRetry -Times 0 -Exactly
        }

        It "Returns 1 without installing dependencies when winget is unconfigured and dependency check skipped" {
            # Justification (PSScriptAnalyzer): $SkipDependencyCheck is consumed dynamically by Main via script scope.
            $SkipDependencyCheck = $true
            # Unresolved C:\ WindowsApps path yields no winget on Linux CI -> unconfigured.
            Mock Get-WingetPath { $null }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly -Because "dependency install must be skipped"
            Should -Invoke Add-AppxPackage -Times 0 -Exactly
        }

        It "Runs the full upgrade through the wrapper when updates exist, then returns 0" {
            Mock Test-WingetConfiguration { $true }
            $script:listCalls = 0
            Mock Invoke-WingetWithRetry {
                param([string]$Arguments)
                if ($Arguments -like 'list *') {
                    $script:listCalls++
                    if ($script:listCalls -eq 1) {
                        # One line matching the upgradeable-row pattern: name id current available.
                        return @('Microsoft Edge MSEdge 120.0.10 121.0.20')
                    }
                    return @()
                }
                return @()
            }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Invoke-WingetWithRetry -Times 4 -Exactly
            Should -Invoke Invoke-WingetWithRetry -ParameterFilter { $Arguments -like 'upgrade*' } `
                -Times 1 -Exactly
            Should -Invoke Invoke-WingetWithRetry -ParameterFilter { $Arguments -like 'source update*' } `
                -Times 1 -Exactly
            ($out | Out-String) | Should -Match '\[\+\]'
        }

        It "Returns 1 and writes [-] output when winget operations fail after retries" {
            Mock Test-WingetConfiguration { $true }
            Mock Invoke-WingetWithRetry { throw "Winget command failed after 3 attempts" }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[\-\]'
        }
    }
}
