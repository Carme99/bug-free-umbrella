#Requires -Modules Pester

Describe 'Invoke-RemediationFixEdgeCacheSize' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationFixEdgeCacheSize.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
                Set-Item -Path "Function:global:Get-CimInstance" -Value { throw "Get-CimInstance is not available on this platform" }

        # Keep the run fast and side-effect free.
        Mock Start-Sleep { }
        Mock Stop-Process { }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationFixEdgeCacheSize\.ps1'
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

        It 'Declares SupportsShouldProcess for its destructive cleanup' {
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
        It 'Stops Edge, clears the enumerated user cache folders and returns 0' {
            $cacheDir = "$TestDrive/users/alice/AppData/Local/Microsoft/Edge/User Data/Default/Cache"
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            Set-Content -Path (Join-Path $cacheDir 'entry.dat') -Value ('x' * 1MB)

            Mock Get-Process { @([pscustomobject]@{ Name = 'msedge' }) }
            Mock Get-CimInstance {
                @([pscustomobject]@{ Special = $false; LocalPath = "$TestDrive/users/alice" })
            }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Cleared \d'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Stop-Process -Times 1 -Exactly -Scope It
            (Get-ChildItem $cacheDir | Measure-Object).Count | Should -Be 0 -Because 'the cache folder must be emptied'
        }

        It 'Is idempotent: converged system returns 0 with no changes' {
            Mock Get-Process { $null }
            Mock Get-CimInstance {
                @([pscustomobject]@{ Special = $false; LocalPath = "$TestDrive/users/bob" })
            }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Already clean'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 and writes [-] prefixed output when profile enumeration fails' {
            Mock Get-Process { $null }
            Mock Get-CimInstance { throw "WMI gone" }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: Edge keeps running and no cache is deleted' {
            $cacheDir = "$TestDrive/users/carol/AppData/Local/Microsoft/Edge/User Data/Default/Cache"
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            Set-Content -Path (Join-Path $cacheDir 'keepme.dat') -Value 'keep me'

            Mock Get-Process { @([pscustomobject]@{ Name = 'msedge' }) }
            Mock Get-CimInstance {
                @([pscustomobject]@{ Special = $false; LocalPath = "$TestDrive/users/carol" })
            }

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Main *>&1 | Out-Null
                Test-Path (Join-Path $cacheDir 'keepme.dat') | Should -BeTrue -Because '-WhatIf must suppress deletion'
                Should -Invoke Stop-Process -Times 0 -Exactly -Scope It -Because '-WhatIf must suppress stopping Edge'
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
