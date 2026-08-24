#Requires -Modules Pester

Describe 'Invoke-RemediationCheckMicrosoftStoreAppsHealth' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationCheckMicrosoftStoreAppsHealth.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
        # The stub declares the parameters the script passes so Pester ParameterFilters bind.
                Set-Item -Path "Function:global:Get-AppxPackage" -Value { param($Name) throw "Get-AppxPackage is not available on this platform" }
                Set-Item -Path "Function:global:Add-AppxPackage" -Value { param($Name) throw "Add-AppxPackage is not available on this platform" }

        Mock Invoke-WsReset { 0 }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationCheckMicrosoftStoreAppsHealth\.ps1'
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

        It 'Declares SupportsShouldProcess for its package re-registration' {
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
        It 'Re-registers error packages, resets the cache and returns 0' {
            Mock Get-AppxPackage {
                @(
                    [pscustomobject]@{ Name = 'Contoso.App'; Status = 'Modified'; InstallLocation = 'C:\Apps\Contoso' },
                    [pscustomobject]@{ Name = 'Healthy.App'; Status = 'Ok'; InstallLocation = 'C:\Apps\Healthy' }
                )
            }
            Mock Get-AppxPackage {
                [pscustomobject]@{ Name = 'Microsoft.WindowsStore'; Status = 'Ok'; InstallLocation = 'C:\Apps\Store' }
            } -ParameterFilter { $Name -eq 'Microsoft.WindowsStore' }
            Mock Add-AppxPackage { }
            Mock Invoke-WsReset { 0 }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Store apps remediation completed:'
            ($out | Out-String) | Should -Match 'Re-registered Contoso.App'
            ($out | Out-String) | Should -Match 'Reset Windows Store cache'
            Should -Invoke Add-AppxPackage -Times 1 -Exactly
            Should -Invoke Invoke-WsReset -Times 1 -Exactly
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 0 without mutation when all packages are healthy (idempotent)' {
            Mock Get-AppxPackage {
                [pscustomobject]@{ Name = 'Healthy.App'; Status = 'Ok'; InstallLocation = 'C:\Apps\Healthy' }
            }
            Mock Add-AppxPackage { }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Already healthy'
            Should -Invoke Add-AppxPackage -Times 0 -Exactly
            Should -Invoke Invoke-WsReset -Times 0 -Exactly
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Performs no mutation under -WhatIf and still returns 0' {
            Mock Get-AppxPackage {
                @(
                    [pscustomobject]@{ Name = 'Contoso.App'; Status = 'Modified'; InstallLocation = 'C:\Apps\Contoso' },
                    [pscustomobject]@{ Name = 'Microsoft.WindowsStore'; Status = 'Modified'; InstallLocation = 'C:\Apps\Store' }
                )
            }
            Mock Add-AppxPackage { }
            $WhatIfPreference = $true
            try {
                $out = Main *>&1
                $out | Where-Object { $_ -is [int] } | Should -Be 0
                Should -Invoke Add-AppxPackage -Times 0 -Exactly
                Should -Invoke Invoke-WsReset -Times 0 -Exactly
            }
            finally {
                $WhatIfPreference = $false
            }
        }

        It 'Returns 1 and writes [-] prefixed output when re-registration fails' {
            Mock Get-AppxPackage {
                [pscustomobject]@{ Name = 'Broken.App'; Status = 'Modified'; InstallLocation = 'C:\Apps\Broken' }
            }
            Mock Add-AppxPackage { throw 'registration failed' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
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
