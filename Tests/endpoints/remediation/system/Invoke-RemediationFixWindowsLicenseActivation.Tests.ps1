#Requires -Modules Pester

Describe 'Invoke-RemediationFixWindowsLicenseActivation' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationFixWindowsLicenseActivation.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
        # Get-CimInstance gets a typed signature so -ParameterFilter can bind $ClassName.
            function global:Get-CimInstance {
                [CmdletBinding()]
                param(
                    [string]$ClassName,
                    [string]$Filter,
                    [string]$ErrorAction
                )
                throw 'Get-CimInstance is not available on this platform'
            }

        function New-LicenseServiceObject {
            # SoftwareLicensingService stand-in whose RefreshLicenseStatus() is a no-op.
            [pscustomobject]@{} |
                Add-Member -MemberType ScriptMethod -Name RefreshLicenseStatus -Value { } -PassThru
        }
        # slmgr.vbs resolves under %SystemRoot%; Linux CI has no such variable.
        $env:SystemRoot = "$TestDrive/Windows"
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationFixWindowsLicenseActivation\.ps1'
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

        It 'Declares SupportsShouldProcess at script level and inside Main' {
            ([regex]::Matches($scriptText, '\[CmdletBinding\(SupportsShouldProcess\)\]')).Count |
                Should -BeGreaterOrEqual 2
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
        It 'Triggers online activation and refreshes license status when not activated' {
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingProduct' } {
                @([pscustomobject]@{ LicenseStatus = 0; PartialProductKey = 'abc123' })
            }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingService' } {
                New-LicenseServiceObject
            }
            Mock Invoke-CScript { 0 }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[\+\] Successfully triggered Windows activation'
            Should -Invoke Invoke-CScript -Times 1 -ParameterFilter { $args -contains '/ato' }
            Should -Invoke Invoke-CScript -Times 1 -ParameterFilter { $args -contains '/dli' }
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Is idempotent: already-active license returns 0 with no activation attempt' {
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingProduct' } {
                @([pscustomobject]@{ LicenseStatus = 1; PartialProductKey = 'abc123' })
            }
            Mock Invoke-CScript { 0 }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[\+\] Already activated'
            Should -Not -Invoke Invoke-CScript
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 0 with a warning when activation exits non-zero (soft failure)' {
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingProduct' } {
                @([pscustomobject]@{ LicenseStatus = 0 })
            }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingService' } {
                New-LicenseServiceObject
            }
            Mock Invoke-CScript { 1 }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[!\] Activation attempt completed'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 and writes [-] prefixed output on upstream failure' {
            Mock Get-CimInstance { throw "CIM gone" }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: no activation command is invoked' {
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingProduct' } {
                @([pscustomobject]@{ LicenseStatus = 0 })
            }
            Mock Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingService' } {
                New-LicenseServiceObject
            }
            Mock Invoke-CScript { 0 }

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Main *>&1 | Out-Null
                Should -Not -Invoke Invoke-CScript -Because '-WhatIf must suppress activation calls'
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
