#Requires -Modules Pester

Describe 'Test-RemediationFixBrokenShortcuts' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Test-RemediationFixBrokenShortcuts.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
                Set-Item -Path "Function:global:Get-CimInstance" -Value { throw "Get-CimInstance is not available on this platform" }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Test-RemediationFixBrokenShortcuts\.ps1'
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
            $declaredParams = @($ast.ParamBlock.Parameters)
            $helpParams = ([regex]::Matches($scriptText, '(?m)^\.PARAMETER\b')).Count
            $helpParams | Should -Be $declaredParams.Count
        }

        It 'Is a detection script that never mutates state (no SupportsShouldProcess needed)' {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            ($ast.FindAll(
                { param($node) $node -is [System.Management.Automation.Language.CommandAst] -and
                  $node.GetCommandName() -in @('Remove-Item', 'Set-ItemProperty', 'New-ItemProperty', 'Stop-Process') },
                $true)) | Should -BeNullOrEmpty
            $scriptText | Should -Not -Match '\bSupportsShouldProcess\b'
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

        It 'Does not assign to the reserved $profile automatic variable' {
            $scriptText | Should -Not -Match '\$profile\b'
        }
    }

    Context 'Behavior' {
        It 'Returns 0 when no shortcut locations or user profiles exist (compliant)' {
            Mock Get-CimInstance { $null }
            Mock Test-Path { $false }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] No broken shortcuts found'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 when a shortcut points at a missing target (issue detected)' {
            Mock Get-CimInstance { $null }
            Mock Test-Path {
                param($Path)
                # Scanned folders exist; the missing target does not.
                ($Path -notmatch '\.(exe|dll)$') -or ($Path -eq 'C:\Windows\System32\notepad.exe')
            }
            Mock Get-ChildItem {
                [pscustomobject]@{ FullName = 'C:\Users\alice\Desktop\dead-app.lnk'; Name = 'dead-app.lnk' }
            }
            Mock Get-ShortcutTargetPath { 'C:\Program Files\Missing Vendor\dead-app.exe' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'dead-app\.lnk'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Returns 0 when every scanned shortcut resolves to an existing target (idempotent re-check)' {
            Mock Get-CimInstance { $null }
            Mock Test-Path {
                param($Path)
                ($Path -notmatch '\.(exe|dll)$') -or ($Path -eq 'C:\Windows\System32\notepad.exe')
            }
            Mock Get-ChildItem {
                [pscustomobject]@{ FullName = 'C:\Users\alice\Desktop\notepad.lnk'; Name = 'notepad.lnk' }
            }
            Mock Get-ShortcutTargetPath { 'C:\Windows\System32\notepad.exe' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] No broken shortcuts found'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Enumerates per-user Desktop folders via Win32_UserProfile' {
            # Profile root must resolve on the host running the tests (Join-Path
            # rejects unknown drives on Linux), so use the Pester test drive.
            Mock Get-CimInstance {
                @([pscustomobject]@{ Special = $false; LocalPath = "$TestDrive" })
            }
            Mock Test-Path { $false }
            $out = Main *>&1
            Assert-MockCalled Get-CimInstance -Exactly 1 -Scope It
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
        }

        It 'Returns 1 and writes [-] prefixed output on upstream failure' {
            Mock Get-CimInstance { throw "CIM gone" }
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
