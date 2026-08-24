#Requires -Modules Pester

Describe 'Invoke-RemediationFixStartMenuLayout' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationFixStartMenuLayout.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Baseline mocks; individual tests override the user enumeration.
        Mock Get-Process { $null }
        Mock Stop-Process { }
        Mock Start-Process { }
        Mock Get-ChildItem { @() }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationFixStartMenuLayout\.ps1'
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

        It 'Declares SupportsShouldProcess for its destructive cache removal' {
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
        It 'Removes tile database and clears Start Menu cache for each user, returning 0' {
            $userHome = "$TestDrive/users/alice"
            $tileData = "$userHome/AppData/Local/TileDataLayer"
            $cacheState = "$userHome/AppData/Local/Packages/Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy/LocalState"
            New-Item -ItemType Directory -Path "$tileData/db" -Force | Out-Null
            Set-Content -Path "$tileData/db/corrupt.db" -Value 'corrupt'
            New-Item -ItemType Directory -Path $cacheState -Force | Out-Null
            Set-Content -Path "$cacheState/stale.dat" -Value 'stale'

            Mock Get-ChildItem {
                @([pscustomobject]@{ FullName = $userHome; Name = 'alice'; PSIsContainer = $true })
            }

            Main | Should -Be 0
            Test-Path $tileData | Should -BeFalse -Because 'the corrupted tile database must be removed'
            ([IO.Directory]::GetFileSystemEntries($cacheState)).Count | Should -Be 0 -Because 'the Start Menu cache must be emptied'
            Should -Invoke Start-Process -Times 1 -ParameterFilter { $FilePath -eq 'explorer.exe' }
        }

        It 'Is idempotent: converged system returns 0 and restarts nothing' {
            Mock Get-ChildItem { @() }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Already clean'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Stop-Process -Times 0
            Should -Invoke Start-Process -Times 0
        }

        It 'Returns 1 and writes [-] prefixed output when a removal fails' {
            $userHome = "$TestDrive/users/bob"
            New-Item -ItemType Directory -Path "$userHome/AppData/Local/TileDataLayer" -Force | Out-Null
            Mock Get-ChildItem {
                @([pscustomobject]@{ FullName = $userHome; Name = 'bob'; PSIsContainer = $true })
            }
            Mock Remove-Item { throw "file locked" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: no folders are removed and Explorer is not restarted' {
            $userHome = "$TestDrive/users/carol"
            $tileData = "$userHome/AppData/Local/TileDataLayer"
            New-Item -ItemType Directory -Path $tileData -Force | Out-Null
            Set-Content -Path "$tileData/keep.db" -Value 'keep'

            Mock Get-ChildItem {
                @([pscustomobject]@{ FullName = $userHome; Name = 'carol'; PSIsContainer = $true })
            }

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Main *>&1 | Out-Null
                Test-Path $tileData | Should -BeTrue -Because '-WhatIf must suppress deletion'
                Should -Invoke Start-Process -Times 0
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
