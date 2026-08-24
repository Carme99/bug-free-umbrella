#Requires -Modules Pester

Describe 'Invoke-RemediationCheckPageFileConfiguration' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationCheckPageFileConfiguration.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
        # The stubs declare their parameters so -ParameterFilter can route by ClassName.
            Set-Item -Path 'Function:global:Get-CimInstance' -Value {
                [CmdletBinding()]
                param([string]$ClassName)
                throw 'Get-CimInstance is not available on this platform'
            }
            Set-Item -Path 'Function:global:Set-CimInstance' -Value {
                [CmdletBinding()]
                param([object]$CimInstance)
                throw 'Set-CimInstance is not available on this platform'
            }

        Mock Set-CimInstance { }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationCheckPageFileConfiguration\.ps1'
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

        It 'Declares SupportsShouldProcess for its page file mutation' {
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
        It 'Enables the system-managed page file when completely disabled and returns 0' {
            Mock Get-CimInstance {
                [pscustomobject]@{ Name = 'PC01'; AutomaticManagedPagefile = $false }
            } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
            Mock Get-CimInstance { $null } -ParameterFilter { $ClassName -eq 'Win32_PageFileSetting' }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Enabled system-managed page file'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-CimInstance -Times 1 -Exactly
        }

        It 'Preserves a custom page file configuration and returns 0 without mutation' {
            Mock Get-CimInstance {
                [pscustomobject]@{ Name = 'PC01'; AutomaticManagedPagefile = $false }
            } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
            Mock Get-CimInstance {
                @([pscustomobject]@{ Name = 'C:\pagefile.sys'; InitialSize = 4096; MaximumSize = 8192 })
            } -ParameterFilter { $ClassName -eq 'Win32_PageFileSetting' }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\] NOTICE: Custom page file configurations are not automatically changed'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-CimInstance -Times 0 -Exactly -Because 'custom configurations must be preserved'
        }

        It 'Is idempotent: already system-managed page file returns 0 with no changes' {
            Mock Get-CimInstance {
                [pscustomobject]@{ Name = 'PC01'; AutomaticManagedPagefile = $true }
            } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
            Mock Get-CimInstance { $null } -ParameterFilter { $ClassName -eq 'Win32_PageFileSetting' }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Already configured: page file is system-managed'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-CimInstance -Times 0 -Exactly
        }

        It 'Returns 1 and writes [-] prefixed output when the CIM query fails' {
            Mock Get-CimInstance { throw "WMI gone" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: the page file configuration is not modified' {
            Mock Get-CimInstance {
                [pscustomobject]@{ Name = 'PC01'; AutomaticManagedPagefile = $false }
            } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
            Mock Get-CimInstance { $null } -ParameterFilter { $ClassName -eq 'Win32_PageFileSetting' }

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Main *>&1 | Out-Null
                Should -Invoke Set-CimInstance -Times 0 -Exactly -Because '-WhatIf must suppress the mutation'
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
