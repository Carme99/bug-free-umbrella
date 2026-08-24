#Requires -Modules Pester

Describe 'Invoke-RemediationFixPrintSpooler' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationFixPrintSpooler.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
                Set-Item -Path "Function:global:Get-Service" -Value { throw "Get-Service is not available on this platform" }
                Set-Item -Path "Function:global:Stop-Service" -Value { throw "Stop-Service is not available on this platform" }
                Set-Item -Path "Function:global:Start-Service" -Value { throw "Start-Service is not available on this platform" }
                Set-Item -Path "Function:global:Set-Service" -Value { throw "Set-Service is not available on this platform" }
        # Contain the run: the spool directory resolves under the Pester test drive.
        $env:SystemRoot = "$TestDrive/windows"

        # Baseline service mocks; individual tests override Get-Service state.
        Mock Stop-Service { }
        Mock Start-Service { }
        Mock Set-Service { }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationFixPrintSpooler\.ps1'
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

        It 'Declares SupportsShouldProcess for its destructive spool cleanup' {
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
        It 'Clears stuck print jobs and starts the Spooler, returning 0' {
            $winSpool = "$TestDrive/windows/System32/spool/PRINTERS"
            New-Item -ItemType Directory -Path $winSpool -Force | Out-Null
            $staleJob = Join-Path $winSpool 'FOO00001.shd'
            Set-Content -Path $staleJob -Value 'stuck job'
            Set-Content -Path (Join-Path $winSpool 'readme.txt') -Value 'keep me'

            $script:svcCalls = 0
            Mock Get-Service {
                $script:svcCalls++
                if ($script:svcCalls -ge 2) {
                    [pscustomobject]@{ Name = 'Spooler'; Status = 'Running'; StartType = 'Automatic' }
                }
                else {
                    [pscustomobject]@{ Name = 'Spooler'; Status = 'Stopped'; StartType = 'Automatic' }
                }
            }

            Main | Should -Be 0
            Test-Path $staleJob | Should -BeFalse -Because 'the stuck print job must be deleted'
            Test-Path (Join-Path $winSpool 'readme.txt') | Should -BeTrue -Because 'only *.shd/*.spl are removed'
            Should -Invoke Start-Service -Times 1
        }

        It 'Is idempotent: running service with clean spool returns 0 unchanged' {
            $winSpool = "$TestDrive/windows/System32/spool/PRINTERS"
            New-Item -ItemType Directory -Path $winSpool -Force | Out-Null

            Mock Get-Service {
                [pscustomobject]@{ Name = 'Spooler'; Status = 'Running'; StartType = 'Automatic' }
            }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Already healthy'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Stop-Service -Times 0
            Should -Invoke Start-Service -Times 0
            Should -Invoke Set-Service -Times 0
        }

        It 'Returns 1 and writes [-] prefixed output when the Spooler service is missing' {
            Mock Get-Service { $null }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: no files are deleted and no service action runs' {
            $winSpool = "$TestDrive/windows/System32/spool/PRINTERS"
            New-Item -ItemType Directory -Path $winSpool -Force | Out-Null
            $staleJob = Join-Path $winSpool 'BAR00002.spl'
            Set-Content -Path $staleJob -Value 'keep me'

            Mock Get-Service {
                [pscustomobject]@{ Name = 'Spooler'; Status = 'Running'; StartType = 'Automatic' }
            }

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Main *>&1 | Out-Null
                Test-Path $staleJob | Should -BeTrue -Because '-WhatIf must suppress deletion'
                Should -Invoke Stop-Service -Times 0
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
