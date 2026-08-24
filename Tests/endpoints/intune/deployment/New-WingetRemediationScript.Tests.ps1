#Requires -Modules Pester

Describe "New-WingetRemediationScript" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/intune/deployment/ -> script sits four levels up + across.
        $relative = "../../../../scripts/endpoints/intune/deployment/New-WingetRemediationScript.ps1"
        $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $relative))
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Mock the folder-open shell-out so nothing leaves the machine.
        Mock Start-Process { }
    }

    Context "Help & Metadata" {
        It "Contains all required .NOTES metadata fields" {
            $start = $raw.IndexOf('<#')
            $end = $raw.IndexOf('#>')
            $help = $raw.Substring($start, $end - $start)

            $help | Should -Match 'File Name\s*:\s*New-WingetRemediationScript\.ps1'
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
            $mainFn = @($scriptAst.FindAll(
                { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                  $args[0].Name -eq 'Main' },
                $true))
            $mainFn.Count | Should -Be 1

            # The generated payload here-strings contain 'exit' as string content; the parsed
            # script itself must have exactly one ExitStatement (the dot-source guard).
            $exits = @($scriptAst.FindAll(
                { $args[0] -is [System.Management.Automation.Language.ExitStatementAst] },
                $true))
            $exits.Count | Should -Be 1

            $lastLine = (Get-Content -LiteralPath $scriptPath | Where-Object { $_.Trim() })[-1]
            $lastLine | Should -Match 'InvocationName'
        }
    }

    Context "Behavior" {
        It "Generates detect and remediate scripts and returns 0" {
            $PackageId = "Google.Chrome"
            $OutputFolder = Join-Path $TestDrive "remediation-out"

            $out = (Main *>&1)

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Join-Path $OutputFolder "detect.ps1" | Should -Exist
            Join-Path $OutputFolder "remediate.ps1" | Should -Exist
            Get-Content (Join-Path $OutputFolder "detect.ps1") -Raw | Should -Match 'Google\.Chrome'
            Get-Content (Join-Path $OutputFolder "remediate.ps1") -Raw | Should -Match '--silent'
        }

        It "Includes README when -IncludeReadme is set" {
            $PackageId = "Mozilla.Firefox"
            $AppDisplayName = "Firefox Browser"
            $OutputFolder = Join-Path $TestDrive "remediation-readme"
            $IncludeReadme = $true

            (Main *>&1 | Where-Object { $_ -is [int] }) | Should -Be 0
            Join-Path $OutputFolder "README.md" | Should -Exist
        }

        It "Derives display name from PackageId when omitted" {
            $PackageId = "7zip.7zip"
            $OutputFolder = Join-Path $TestDrive "remediation-derived"

            $out = (Main *>&1)

            ($out | Out-String) | Should -Match '7zip 7zip'
        }

        It "Is idempotent: regenerating over existing files succeeds" {
            $PackageId = "Microsoft.Edge"
            $OutputFolder = Join-Path $TestDrive "remediation-rerun"

            (Main *>&1 | Where-Object { $_ -is [int] }) | Should -Be 0
            (Main *>&1 | Where-Object { $_ -is [int] }) | Should -Be 0
            Join-Path $OutputFolder "remediate.ps1" | Should -Exist
        }

        It "Honors -WhatIf: writes no files and returns 0" {
            $PackageId = "WhatIf.Package"
            $OutputFolder = Join-Path $TestDrive "remediation-whatif"

            $out = (Main -WhatIf *>&1)

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Test-Path $OutputFolder | Should -BeFalse
        }

        It "Returns 1 with [-] output when output folder is unwritable (existing file)" {
            $PackageId = "Broken.Package"
            $blocked = Join-Path $TestDrive "blocked.txt"
            Set-Content -LiteralPath $blocked -Value "not a folder"
            $OutputFolder = $blocked

            $out = (Main *>&1)

            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
