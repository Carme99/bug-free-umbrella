#Requires -Modules Pester

Describe 'Invoke-RemediationCheckApplicationCrashes' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationCheckApplicationCrashes.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Deterministic device name on Linux CI where COMPUTERNAME is unset.
        Set-Item -Path 'Env:COMPUTERNAME' -Value 'TESTBOX'
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationCheckApplicationCrashes\.ps1'
            $scriptText | Should -Match 'Author\s*:'
            $scriptText | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
            $scriptText | Should -Match 'Version\s*:\s*1\.0\.0'
            $scriptText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It 'Documents its exit-code contract in DESCRIPTION' {
            $scriptText | Should -Match '(?m)^\.DESCRIPTION'
            $scriptText | Should -Match 'Exit codes?: 0 ='
            $scriptText | Should -Match '(?s)Exit codes?: 0 =.+?1 ='
        }

        It 'Has comment-based help with SYNOPSIS and >=2 EXAMPLES' {
            $scriptText | Should -Match '(?m)^\.SYNOPSIS'
            ([regex]::Matches($scriptText, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
        }

        It 'Has one .PARAMETER entry per declared parameter' {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declaredParams = @()
            if ($ast.ParamBlock) { $declaredParams = @($ast.ParamBlock.Parameters) }
            $helpParams = ([regex]::Matches($scriptText, '(?m)^\.PARAMETER\b')).Count
            $helpParams | Should -Be $declaredParams.Count
        }

        It 'Is wrapped in Main with a single top-level dot-source guard exit' {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $exitStatements = $ast.FindAll(
                { param($node) $node -is [System.Management.Automation.Language.ExitStatementAst] }, $true)
            $exitStatements | Should -HaveCount 1
            $exitStatements[0].Extent.Text.Trim() | Should -Be 'exit (Main)'
            $scriptText | Should -Match ([regex]::Escape('if ($MyInvocation.InvocationName -ne ''.'') { exit (Main) }'))
        }
    }

    Context 'Syntax & Static' {
        It 'Parses without errors' {
            $tokens = $null
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
        }

        It 'Uses no PS7-only operators without #Requires -Version 7.0' {
            $scriptText | Should -Not -Match '(?m)^#Requires -Version'
            $scriptText | Should -Not -Match '\|\||&&|\?\?'
        }

        It 'Uses approved verbs only for its functions' {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $functions = $ast.FindAll(
                { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
            foreach ($fn in $functions) {
                if ($fn.Name -eq 'Main') { continue }  # mandated by spec §3
                $verb = ($fn.Name -split '-')[0]
                Get-Verb -Verb $verb | Should -Not -BeNullOrEmpty -Because "'$($fn.Name)' must use an approved verb"
            }
        }

        It 'Makes no system changes beyond console output' {
            # Idempotency/static guarantee: the script body must not invoke any
            # mutating command; it is pure Write-Host guidance.
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $commands = $ast.FindAll(
                { param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() } | Select-Object -Unique
            @($commands | Where-Object { $_ -ne 'Main' }) | Should -Be 'Write-Host'
        }
    }

    Context 'Behavior' {
        It 'Returns 0 and prints the troubleshooting playbook' {
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\*\]'
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match 'Troubleshooting steps:'
            ($out | Out-String) | Should -Match 'Review crash dumps'
            ($out | Out-String) | Should -Match 'Device flagged for application stability review'
            ($out | Out-String) | Should -Match 'Device: TESTBOX'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Is idempotent: a second run succeeds identically' {
            $first = Main *>&1
            $second = Main *>&1
            ($second | Where-Object { $_ -is [int] }) | Should -Be 0
            (($second | Out-String)) | Should -Be (($first | Out-String))
        }

        It 'Exits 0 when executed directly through the dot-source guard' {
            $null = & $scriptPath
            $LASTEXITCODE | Should -Be 0
        }
    }

    AfterAll {
        # Hygiene: restore a FileSystem location so nothing leaks into sibling
        # test containers in the same Pester run.
        Set-Location $PSScriptRoot
    }
}
