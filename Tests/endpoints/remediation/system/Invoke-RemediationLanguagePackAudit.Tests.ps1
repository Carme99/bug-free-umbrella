#Requires -Modules Pester

Describe 'Invoke-RemediationLanguagePackAudit' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationLanguagePackAudit.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
                Set-Item -Path "Function:global:Get-WindowsPackage" -Value { throw "Get-WindowsPackage is not available on this platform" }
                Set-Item -Path "Function:global:Remove-WindowsPackage" -Value { throw "Remove-WindowsPackage is not available on this platform" }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationLanguagePackAudit\.ps1'
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

        It 'Declares SupportsShouldProcess for its destructive package removal' {
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
        BeforeAll {
            # Elevation probe is always mocked; the real one needs Windows.
            Mock Test-ElevatedPrivilege { $true }

            # Recording mock: Pester's Should -Invoke filters cannot see bound
            # parameters of function-backed stubs, so record calls explicitly.
            $script:removedPackages = [System.Collections.Generic.List[string]]::new()
            Mock Remove-WindowsPackage {
                param($PackageName)
                $script:removedPackages.Add($PackageName) | Out-Null
            }

            Mock Get-WindowsPackage {
                @(
                    [pscustomobject]@{ PackageName = 'Microsoft-Windows-Client-LanguagePack-Package~31bf3856ad364e35~amd64~de-DE~10.0.19041.1' },
                    [pscustomobject]@{ PackageName = 'Microsoft-Windows-Client-LanguagePack-Package~31bf3856ad364e35~amd64~en-GB~10.0.19041.1' },
                    [pscustomobject]@{ PackageName = 'Microsoft-Windows-LanguageFeatures-Basic-en-us-Package~31bf3856ad364e35~amd64~~10.0.19041.1' }
                )
            }
        }

        It 'Removes only disallowed language packs and returns 0' {
            $script:removedPackages.Clear()
            Main | Should -Be 0
            ($script:removedPackages -join ',') | Should -Match '~de-DE~'
            ($script:removedPackages -join ',') | Should -Not -Match '~en-GB~'
            ($script:removedPackages -join ',') | Should -Not -Match '~en-US~'
        }

        It 'Is idempotent: compliant device returns 0 with no removals' {
            Mock Get-WindowsPackage {
                @(
                    [pscustomobject]@{ PackageName = 'Microsoft-Windows-Client-LanguagePack-Package~31bf3856ad364e35~amd64~en-GB~10.0.19041.1' },
                    [pscustomobject]@{ PackageName = 'Microsoft-Windows-Client-LanguagePack-Package~31bf3856ad364e35~amd64~en-US~10.0.19041.1' }
                )
            }

            $script:removedPackages.Clear()
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Already compliant'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $script:removedPackages | Should -BeNullOrEmpty -Because 'nothing is left to remove'
        }

        It 'Returns 1 and writes [-] prefixed output when not elevated' {
            Mock Test-ElevatedPrivilege { $false }
            $script:removedPackages.Clear()
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            $script:removedPackages | Should -BeNullOrEmpty
        }

        It 'Returns 1 and writes [-] prefixed output when package enumeration fails' {
            Mock Get-WindowsPackage { throw "DISM gone" }
            $script:removedPackages.Clear()
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: no package is removed' {
            $script:removedPackages.Clear()

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Main *>&1 | Out-Null
                $script:removedPackages | Should -BeNullOrEmpty -Because '-WhatIf must suppress removal'
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
