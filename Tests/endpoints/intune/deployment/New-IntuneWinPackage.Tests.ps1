#Requires -Modules Pester

Describe "New-IntuneWinPackage" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/intune/deployment/ -> script sits four levels up + across.
        $relative = "../../../../scripts/endpoints/intune/deployment/New-IntuneWinPackage.ps1"
        $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $relative))
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Offline fixtures: real temp files so Test-Path/Get-ChildItem checks behave naturally.
        $testRoot = Join-Path $TestDrive "intunewin"
        $sourceDir = Join-Path $testRoot "source"
        New-Item -ItemType Directory -Path (Join-Path $sourceDir "App1") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sourceDir "App1" "setup.exe") -Value "fake installer"
        Set-Content -LiteralPath (Join-Path $sourceDir "App1" "install.msi") -Value "fake installer"
        $toolFile = Join-Path $testRoot "IntuneWinAppUtil.exe"
        Set-Content -LiteralPath $toolFile -Value "fake tool"

        # Mock externals: the native prep tool is only reached via its wrapper; Start-Process
        # is mocked so the folder-open shell-out never runs.
        Mock Invoke-ContentPrepTool { return 0 }
        Mock Start-Process { }
    }

    Context "Help & Metadata" {
        It "Contains all required .NOTES metadata fields" {
            $start = $raw.IndexOf('<#')
            $end = $raw.IndexOf('#>')
            $help = $raw.Substring($start, $end - $start)

            $help | Should -Match 'File Name\s*:\s*New-IntuneWinPackage\.ps1'
            $help | Should -Match 'Author\s*:'
            $help | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
            $help | Should -Match 'Version\s*:\s*1\.0\.0'
            $help | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Declares a .PARAMETER entry for every param() variable" {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $paramNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })

            $start = $raw.IndexOf('<#')
            $end = $raw.IndexOf('#>')
            $help = $raw.Substring($start, $end - $start)

            $helpParams = @([regex]::Matches($help, '(?m)^\s*\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value })
            $helpParams.Count | Should -Be $paramNames.Count
            foreach ($name in $paramNames) {
                $helpParams | Should -Contain $name
            }
        }

        It "Is saved as UTF-8 with BOM" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            (($bytes[0..2] | ForEach-Object { $_.ToString('X2') }) -join '') | Should -Be 'EFBBBF'
        }
    }

    Context "Syntax & Static" {
        BeforeAll {
            $tokens = $null
            $parseErrors = $null
            $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
        }

        It "Parses with zero errors" {
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Avoids PS7-only syntax without a 7.0 requirement" {
            $raw | Should -Not -Match '#Requires\s+-Version\s+7\.0'
            $raw | Should -Not -Match '\|\||&&|\?\?'
        }

        It "Defines a Main function with exit only in the dot-source guard line" {
            $mainFn = $scriptAst.FindAll(
                { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                  $args[0].Name -eq 'Main' },
                $true)
            $mainFn | Should -Not -BeNullOrEmpty

            $exits = @($scriptAst.FindAll(
                { $args[0] -is [System.Management.Automation.Language.ExitStatementAst] },
                $true))
            $exits.Count | Should -Be 1
            $lastLine = (Get-Content -LiteralPath $scriptPath | Where-Object { $_.Trim() })[-1]
            $lastLine | Should -Match 'InvocationName'
        }
    }

    Context "Behavior" {
        It "Converts a single installer and returns 0 on success" {
            $SetupFile = Join-Path $sourceDir "App1" "setup.exe"
            $OutputFolder = Join-Path $testRoot "out-single"
            $ContentPrepToolPath = $toolFile

            $out = (Main *>&1)

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Invoke-ContentPrepTool -Times 1 -Exactly -ParameterFilter { $SetupFileName -eq 'setup.exe' }
        }

        It "Is idempotent: re-running on the same inputs succeeds again" {
            $SetupFile = Join-Path $sourceDir "App1" "setup.exe"
            $OutputFolder = Join-Path $testRoot "out-rerun"
            $ContentPrepToolPath = $toolFile

            (Main | Where-Object { $_ -is [int] }) | Should -Be 0
            (Main | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Invoke-ContentPrepTool -Times 2 -Exactly `
                -ParameterFilter { $DestinationFolder -like '*out-rerun*' }
        }

        It "Batch converts all installers under -SourceFolder" {
            $SourceFolder = $sourceDir
            $OutputFolder = Join-Path $testRoot "out-batch"
            $ContentPrepToolPath = $toolFile

            $out = (Main *>&1)

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Invoke-ContentPrepTool -Times 2 -Exactly `
                -ParameterFilter { $DestinationFolder -like '*out-batch*' }
        }

        It "Honors -WhatIf: skips package generation and returns 0" {
            $SetupFile = Join-Path $sourceDir "App1" "setup.exe"
            $OutputFolder = Join-Path $testRoot "out-whatif"
            $ContentPrepToolPath = $toolFile

            $out = (Main -WhatIf *>&1)

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Invoke-ContentPrepTool -Times 0 -Exactly `
                -ParameterFilter { $DestinationFolder -like '*out-whatif*' }
            Test-Path -LiteralPath (Join-Path $testRoot "out-whatif") | Should -BeFalse
        }

        It "Returns 1 with [-] output when neither source nor setup file is given" {
            $SetupFile = $null
            $SourceFolder = $null
            $OutputFolder = Join-Path $testRoot "out-empty"
            $ContentPrepToolPath = $toolFile

            $out = (Main *>&1)

            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It "Returns 1 with [-] output when the setup file does not exist" {
            $SetupFile = Join-Path $testRoot "missing\setup.exe"
            $OutputFolder = Join-Path $testRoot "out-missing"
            $ContentPrepToolPath = $toolFile

            $out = (Main *>&1)

            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
