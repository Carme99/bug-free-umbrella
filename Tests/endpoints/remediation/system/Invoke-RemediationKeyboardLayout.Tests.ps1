#Requires -Modules Pester

Describe 'Invoke-RemediationKeyboardLayout' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationKeyboardLayout.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
                Set-Item -Path "Function:global:Get-WinUserLanguageList" -Value { throw "Get-WinUserLanguageList is not available on this platform" }
                Set-Item -Path "Function:global:Set-WinUserLanguageList" -Value { throw "Set-WinUserLanguageList is not available on this platform" }
                Set-Item -Path "Function:global:New-WinUserLanguageList" -Value { throw "New-WinUserLanguageList is not available on this platform" }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationKeyboardLayout\.ps1'
            $scriptText | Should -Match 'Author\s*:'
            $scriptText | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
            $scriptText | Should -Match 'Version\s*:\s*1\.0\.0'
            $scriptText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It 'Has comment-based help with SYNOPSIS, DESCRIPTION and >=2 EXAMPLES' {
            $scriptText | Should -Match '(?m)^\.SYNOPSIS'
            $scriptText | Should -Match '(?m)^\.DESCRIPTION'
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

        It 'Declares SupportsShouldProcess for its language-list mutation' {
            $scriptText | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
            $scriptText | Should -Match '\$PSCmdlet\.ShouldProcess\('
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
    }

    Context 'Behavior' {
        It 'Adds en-GB, applies UK tips and returns 0 when en-GB is missing' {
            Mock Get-WinUserLanguageList {
                @([pscustomobject]@{ LanguageTag = 'de-DE'; InputMethodTips = [System.Collections.Generic.List[string]]@('0407:00000407') })
            }
            Mock New-WinUserLanguageList {
                @([pscustomobject]@{ LanguageTag = 'en-GB'; InputMethodTips = [System.Collections.Generic.List[string]]::new() })
            }
            Mock Set-WinUserLanguageList { }

            Main | Should -Be 0
            Should -Invoke Set-WinUserLanguageList -Times 1 -Exactly
            Should -Invoke New-WinUserLanguageList -Times 1 -Exactly
        }

        It 'Is idempotent: converged profile returns 0 with no changes' {
            Mock Get-WinUserLanguageList {
                @(
                    [pscustomobject]@{
                        LanguageTag     = 'en-GB'
                        InputMethodTips = [System.Collections.Generic.List[string]]@('0809:00000809', '0809:00000452')
                    },
                    [pscustomobject]@{ LanguageTag = 'de-DE'; InputMethodTips = [System.Collections.Generic.List[string]]@('0407:00000407') }
                )
            }
            Mock Set-WinUserLanguageList { }
            Mock New-WinUserLanguageList { }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Already configured'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-WinUserLanguageList -Times 0 -Exactly -Because 'the profile is already converged'
            Should -Invoke New-WinUserLanguageList -Times 0 -Exactly
        }

        It 'Repairs input method tips when en-GB is present but misconfigured' {
            Mock Get-WinUserLanguageList {
                @(
                    [pscustomobject]@{
                        LanguageTag     = 'en-GB'
                        InputMethodTips = [System.Collections.Generic.List[string]]@('0409:00000409')
                    },
                    [pscustomobject]@{ LanguageTag = 'fr-FR'; InputMethodTips = [System.Collections.Generic.List[string]]@('040c:0000040c') }
                )
            }
            Mock Set-WinUserLanguageList { }
            Mock New-WinUserLanguageList { }

            Main | Should -Be 0
            Should -Invoke Set-WinUserLanguageList -Times 1 -Exactly
            Should -Invoke New-WinUserLanguageList -Times 0 -Exactly
        }

        It 'Returns 1 and writes [-] prefixed output when the language list cannot be read' {
            Mock Get-WinUserLanguageList { throw "language list gone" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: no language-list change is persisted' {
            Mock Get-WinUserLanguageList {
                @([pscustomobject]@{ LanguageTag = 'de-DE'; InputMethodTips = [System.Collections.Generic.List[string]]@('0407:00000407') })
            }
            Mock New-WinUserLanguageList {
                @([pscustomobject]@{ LanguageTag = 'en-GB'; InputMethodTips = [System.Collections.Generic.List[string]]::new() })
            }
            Mock Set-WinUserLanguageList { }

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Main *>&1 | Out-Null
                Should -Invoke Set-WinUserLanguageList -Times 0 -Exactly -Because '-WhatIf must suppress persistence'
            }
            finally {
                $WhatIfPreference = $false
            }
        }
    }

    AfterAll {
        # Hygiene: remove platform stubs and restore a FileSystem location so
        # nothing leaks into sibling test containers in the same Pester run.
        foreach ($cmd in @(
                'Add-AppxPackage', 'Clear-RecycleBin', 'Get-AppxPackage', 'Get-CimInstance',
                'Get-MpComputerStatus', 'Get-PhysicalDisk', 'Get-Service', 'Get-StorageReliabilityCounter',
                'Get-Volume', 'Get-WinEvent', 'Get-WinUserLanguageList', 'Get-WindowsPackage',
                'New-WinUserLanguageList', 'Optimize-Volume', 'Remove-CimInstance', 'Remove-WindowsPackage',
                'Restart-Service', 'Set-Service', 'Set-WinUserLanguageList', 'Start-Service', 'Stop-Service'
            )) {
            $existing = Get-Command $cmd -ErrorAction SilentlyContinue
            if ($existing -and $existing.CommandType -eq 'Function') {
                Remove-Item -LiteralPath "Function:global:$cmd" -Force
            }
        }
        Set-Location $PSScriptRoot
    }
}
