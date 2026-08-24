#Requires -Modules Pester

Describe 'Invoke-RemediationFixTeamsCache' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationFixTeamsCache.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
                Set-Item -Path "Function:global:Get-CimInstance" -Value { throw "Get-CimInstance is not available on this platform" }

        Mock Get-Process { $null }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationFixTeamsCache\.ps1'
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

        It 'Declares SupportsShouldProcess for its destructive cache deletion' {
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
        It 'Clears Teams cache folders and old logs per user profile and returns 0' {
            $teamsDir = "$TestDrive/users/alice/AppData/Roaming/Microsoft/Teams"
            New-Item -ItemType Directory -Path "$teamsDir/Cache" -Force | Out-Null
            Set-Content -Path "$teamsDir/Cache/junk.bin" -Value 'stale cache'
            New-Item -ItemType Directory -Path "$teamsDir/logs" -Force | Out-Null
            $oldLog = "$teamsDir/logs/old.log"
            Set-Content -Path $oldLog -Value 'old log'
            (Get-Item $oldLog).LastWriteTime = (Get-Date).AddDays(-14)
            Set-Content -Path "$teamsDir/logs/new.log" -Value 'recent log'

            Mock Get-CimInstance {
                @([pscustomobject]@{ Special = $false; LocalPath = "$TestDrive/users/alice" })
            }

            Main | Should -Be 0
            Test-Path "$teamsDir/Cache/junk.bin" | Should -BeFalse -Because 'the stale cache must be cleared'
            Test-Path $oldLog | Should -BeFalse -Because 'logs older than 7 days must be deleted'
            Test-Path "$teamsDir/logs/new.log" | Should -BeTrue -Because 'recent logs are preserved'
        }

        It 'Is idempotent: converged system returns 0 with no changes' {
            Mock Get-CimInstance {
                @([pscustomobject]@{ Special = $false; LocalPath = "$TestDrive/users/bob" })
            }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Already clean'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 and writes [-] prefixed output when profile enumeration fails' {
            Mock Get-CimInstance { throw "WMI gone" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: no cache files or logs are deleted' {
            $teamsDir = "$TestDrive/users/carol/AppData/Roaming/Microsoft/Teams"
            New-Item -ItemType Directory -Path "$teamsDir/GPUCache" -Force | Out-Null
            $cacheFile = "$teamsDir/GPUCache/keep.bin"
            Set-Content -Path $cacheFile -Value 'keep me'

            Mock Get-CimInstance {
                @([pscustomobject]@{ Special = $false; LocalPath = "$TestDrive/users/carol" })
            }

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Main *>&1 | Out-Null
                Test-Path $cacheFile | Should -BeTrue -Because '-WhatIf must suppress deletion'
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
