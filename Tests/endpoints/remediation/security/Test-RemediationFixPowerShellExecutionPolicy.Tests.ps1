#Requires -Modules Pester

Describe 'Test-RemediationFixPowerShellExecutionPolicy' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/security/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/security/Test-RemediationFixPowerShellExecutionPolicy.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Build a Get-ExecutionPolicy -List style result. Precedence order per
        # MS Learn: MachinePolicy, UserPolicy, LocalMachine, CurrentUser, Process.
        function New-PolicyList {
            param(
                [string]$MachinePolicy = 'Undefined',
                [string]$UserPolicy = 'Undefined',
                [string]$LocalMachine = 'Undefined',
                [string]$CurrentUser = 'Undefined',
                [string]$ProcessScope = 'Undefined'
            )
            @(
                [pscustomobject]@{ Scope = 'MachinePolicy'; ExecutionPolicy = $MachinePolicy },
                [pscustomobject]@{ Scope = 'UserPolicy'; ExecutionPolicy = $UserPolicy },
                [pscustomobject]@{ Scope = 'LocalMachine'; ExecutionPolicy = $LocalMachine },
                [pscustomobject]@{ Scope = 'CurrentUser'; ExecutionPolicy = $CurrentUser },
                [pscustomobject]@{ Scope = 'Process'; ExecutionPolicy = $ProcessScope }
            )
        }

        Mock Get-ExecutionPolicy { New-PolicyList -LocalMachine 'RemoteSigned' }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Test-RemediationFixPowerShellExecutionPolicy\.ps1'
            $scriptText | Should -Match 'Author\s*:'
            $scriptText | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
            $scriptText | Should -Match 'Version\s*:\s*1\.0\.0'
            $scriptText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It 'Documents its detect exit-code contract in DESCRIPTION' {
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
            $declaredParams = @($ast.ParamBlock.Parameters)
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
    }

    Context 'Behavior' {
        It 'Returns 0 when the effective policy is RemoteSigned (compliant)' {
            Mock Get-ExecutionPolicy { New-PolicyList -LocalMachine 'RemoteSigned' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match 'properly configured: RemoteSigned'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 and flags an overly permissive effective policy' {
            Mock Get-ExecutionPolicy { New-PolicyList -LocalMachine 'Unrestricted' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match "Effective execution policy is 'Unrestricted'"
            ($out | Out-String) | Should -Match 'too permissive'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Excludes the Process scope from the effective-policy calculation' {
            # Process is Bypass/Unrestricted because Intune runs scripts with
            # -ExecutionPolicy Bypass; it must not influence the verdict.
            Mock Get-ExecutionPolicy { New-PolicyList -LocalMachine 'Bypass' -ProcessScope 'Unrestricted' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match "Effective execution policy is 'Bypass'"
            ($out | Out-String) | Should -Not -Match 'Unrestricted'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Returns 1 and flags an overly restrictive effective policy' {
            Mock Get-ExecutionPolicy { New-PolicyList -MachinePolicy 'AllSigned' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match "Effective execution policy is 'AllSigned'"
            ($out | Out-String) | Should -Match 'too restrictive'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Returns 1 and writes [-] prefixed output when policy enumeration fails' {
            Mock Get-ExecutionPolicy { throw "policy store gone" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }

    AfterAll {
        # Hygiene: restore a FileSystem location so nothing leaks into sibling
        # test containers in the same Pester run.
        Set-Location $PSScriptRoot
    }
}
