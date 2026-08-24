#Requires -Modules Pester

Describe 'Invoke-RemediationRegionLanguageSettings' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationRegionLanguageSettings.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
        foreach ($cmd in @(
                'Get-WinHomeLocation', 'Set-WinHomeLocation',
                'Set-TimeZone',
                'Get-WinSystemLocale', 'Set-WinSystemLocale',
                'Set-Culture',
                'Get-WinUserLanguageList', 'Set-WinUserLanguageList', 'New-WinUserLanguageList'
            )) {
            Set-Item -Path "Function:global:$cmd" -Value { throw "$cmd is not available on this platform" }
        }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationRegionLanguageSettings\.ps1'
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

        It 'Declares SupportsShouldProcess for its regional mutations' {
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
        It 'Applies every deviant setting and returns 0 on a non-UK device' {
            Mock Get-WinHomeLocation { [pscustomobject]@{ GeoId = 94 } }          # Germany
            Mock Get-TimeZone { [pscustomobject]@{ Id = 'W. Europe Standard Time' } }
            Mock Get-WinSystemLocale { [pscustomobject]@{ Name = 'de-DE' } }
            Mock Get-Culture { [pscustomobject]@{ Name = 'de-DE' } }
            Mock Get-WinUserLanguageList {
                @([pscustomobject]@{ LanguageTag = 'de-DE'; InputMethodTips = [System.Collections.Generic.List[string]]@() })
            }
            Mock New-WinUserLanguageList {
                @([pscustomobject]@{ LanguageTag = 'en-GB'; InputMethodTips = [System.Collections.Generic.List[string]]::new() })
            }
            Mock Set-WinHomeLocation { }
            Mock Set-TimeZone { }
            Mock Set-WinSystemLocale { }
            Mock Set-Culture { }
            Mock Set-WinUserLanguageList { }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Regional settings remediated'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-WinHomeLocation -Times 1 -Exactly
            Should -Invoke Set-TimeZone -Times 1 -Exactly
            Should -Invoke Set-WinSystemLocale -Times 1 -Exactly
            Should -Invoke Set-Culture -Times 1 -Exactly
            Should -Invoke Set-WinUserLanguageList -Times 1 -Exactly
        }

        It 'Is idempotent: compliant device returns 0 with no changes' {
            Mock Get-WinHomeLocation { [pscustomobject]@{ GeoId = 242 } }         # United Kingdom
            Mock Get-TimeZone { [pscustomobject]@{ Id = 'GMT Standard Time' } }
            Mock Get-WinSystemLocale { [pscustomobject]@{ Name = 'en-GB' } }
            Mock Get-Culture { [pscustomobject]@{ Name = 'en-GB' } }
            Mock Get-WinUserLanguageList {
                @([pscustomobject]@{ LanguageTag = 'en-GB'; InputMethodTips = [System.Collections.Generic.List[string]]@() })
            }
            Mock Set-WinHomeLocation { }
            Mock Set-TimeZone { }
            Mock Set-WinSystemLocale { }
            Mock Set-Culture { }
            Mock Set-WinUserLanguageList { }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Already compliant'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-WinHomeLocation -Times 0 -Exactly
            Should -Invoke Set-TimeZone -Times 0 -Exactly
            Should -Invoke Set-WinSystemLocale -Times 0 -Exactly
            Should -Invoke Set-Culture -Times 0 -Exactly
            Should -Invoke Set-WinUserLanguageList -Times 0 -Exactly
        }

        It 'Repairs only the deviant time zone when everything else is compliant' {
            Mock Get-WinHomeLocation { [pscustomobject]@{ GeoId = 242 } }
            Mock Get-TimeZone { [pscustomobject]@{ Id = 'W. Europe Standard Time' } }
            Mock Get-WinSystemLocale { [pscustomobject]@{ Name = 'en-GB' } }
            Mock Get-Culture { [pscustomobject]@{ Name = 'en-GB' } }
            Mock Get-WinUserLanguageList {
                @([pscustomobject]@{ LanguageTag = 'en-GB'; InputMethodTips = [System.Collections.Generic.List[string]]@() })
            }
            Mock Set-TimeZone { }
            Mock Set-WinHomeLocation { }
            Mock Set-WinSystemLocale { }
            Mock Set-Culture { }
            Mock Set-WinUserLanguageList { }

            Main | Should -Be 0
            Should -Invoke Set-TimeZone -Times 1 -Exactly
            Should -Invoke Set-WinHomeLocation -Times 0 -Exactly
            Should -Invoke Set-WinSystemLocale -Times 0 -Exactly
            Should -Invoke Set-Culture -Times 0 -Exactly
            Should -Invoke Set-WinUserLanguageList -Times 0 -Exactly
        }

        It 'Returns 1 and writes [-] prefixed output when a settings read fails' {
            Mock Get-WinHomeLocation { throw "CIM gone" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: no regional mutation is persisted' {
            Mock Get-WinHomeLocation { [pscustomobject]@{ GeoId = 94 } }
            Mock Get-TimeZone { [pscustomobject]@{ Id = 'W. Europe Standard Time' } }
            Mock Get-WinSystemLocale { [pscustomobject]@{ Name = 'de-DE' } }
            Mock Get-Culture { [pscustomobject]@{ Name = 'de-DE' } }
            Mock Get-WinUserLanguageList {
                @([pscustomobject]@{ LanguageTag = 'de-DE'; InputMethodTips = [System.Collections.Generic.List[string]]@() })
            }
            Mock Set-WinHomeLocation { }
            Mock Set-TimeZone { }
            Mock Set-WinSystemLocale { }
            Mock Set-Culture { }
            Mock Set-WinUserLanguageList { }

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Main *>&1 | Out-Null
                Should -Invoke Set-TimeZone -Times 0 -Exactly -Because '-WhatIf must suppress persistence'
                Should -Invoke Set-WinHomeLocation -Times 0 -Exactly
                Should -Invoke Set-WinSystemLocale -Times 0 -Exactly
                Should -Invoke Set-Culture -Times 0 -Exactly
                Should -Invoke Set-WinUserLanguageList -Times 0 -Exactly
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
