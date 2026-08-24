#Requires -Modules Pester

Describe 'Test-RemediationFixBitLockerNotEscrowedKeys' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/security/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/security/Test-RemediationFixBitLockerNotEscrowedKeys.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only commands do not exist on Linux CI; stub them globally so
        # Pester can mock them by name.
        Set-Item -Path "Function:global:Get-BitLockerVolume" -Value `
            { throw "Get-BitLockerVolume is not available on this platform" }

        Mock Get-Module { $null }
        Mock Get-BitLockerVolume { $null }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Test-RemediationFixBitLockerNotEscrowedKeys\.ps1'
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
    }

    Context 'Behavior' {
        It 'Returns 0 without touching BitLocker when the module is unavailable' {
            Mock Get-Module { $null }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Get-BitLockerVolume -Times 0 -Exactly -Because 'the check cannot run without the module'
        }

        It 'Returns 0 when every encrypted volume has a recovery password protector (compliant)' {
            Mock Get-Module { [pscustomobject]@{ Name = 'BitLocker' } }
            Mock Get-BitLockerVolume {
                @(
                    [pscustomobject]@{
                        MountPoint   = 'C:'
                        VolumeStatus = 'FullyEncrypted'
                        KeyProtector = @([pscustomobject]@{ KeyProtectorType = 'RecoveryPassword' })
                    },
                    [pscustomobject]@{
                        MountPoint   = 'D:'
                        VolumeStatus = 'FullyDecrypted'
                        KeyProtector = @()
                    }
                )
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match 'All BitLocker volumes have a recovery password protector'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 and lists volumes missing a recovery password protector (non-compliant)' {
            Mock Get-Module { [pscustomobject]@{ Name = 'BitLocker' } }
            Mock Get-BitLockerVolume {
                @(
                    [pscustomobject]@{
                        MountPoint   = 'C:'
                        VolumeStatus = 'FullyEncrypted'
                        KeyProtector = @([pscustomobject]@{ KeyProtectorType = 'Tpm' })
                    },
                    [pscustomobject]@{
                        MountPoint   = 'D:'
                        VolumeStatus = 'EncryptionInProgress'
                        KeyProtector = @(
                            [pscustomobject]@{ KeyProtectorType = 'RecoveryPassword' },
                            [pscustomobject]@{ KeyProtectorType = 'Tpm' }
                        )
                    }
                )
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'C: - No recovery password protector'
            ($out | Out-String) | Should -Not -Match 'D: - No recovery password protector'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Returns 1 and writes [-] prefixed output when volume enumeration fails' {
            Mock Get-Module { [pscustomobject]@{ Name = 'BitLocker' } }
            Mock Get-BitLockerVolume { throw "TPM gone" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }

    AfterAll {
        # Hygiene: remove platform stubs and restore a FileSystem location so
        # nothing leaks into sibling test containers in the same Pester run.
        foreach ($cmd in @('Get-BitLockerVolume')) {
            $existing = Get-Command $cmd -ErrorAction SilentlyContinue
            if ($existing -and $existing.CommandType -eq 'Function') {
                Remove-Item -LiteralPath "Function:global:$cmd" -Force
            }
        }
        Set-Location $PSScriptRoot
    }
}
