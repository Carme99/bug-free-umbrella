#Requires -Modules Pester

Describe 'Invoke-RemediationFixWindowsSearch' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationFixWindowsSearch.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
                Set-Item -Path "Function:global:Get-Service" -Value { throw "Get-Service is not available on this platform" }
                Set-Item -Path "Function:global:Stop-Service" -Value { throw "Stop-Service is not available on this platform" }
                Set-Item -Path "Function:global:Start-Service" -Value { throw "Start-Service is not available on this platform" }
                Set-Item -Path "Function:global:Set-Service" -Value { throw "Set-Service is not available on this platform" }

        # Sleeps are mocked to keep tests fast.
        Mock Start-Sleep { }

        function Invoke-MainWithProgramData {
            # Runs Main with $env:ProgramData redirected into the test drive and
            # restores the previous value afterwards (without calling Remove-Item,
            # which tests may mock/count).
            param([string]$TestProgramData)

            $previousProgramData = $env:ProgramData
            $env:ProgramData = $TestProgramData
            try {
                return (Main *>&1)
            }
            finally {
                $env:ProgramData = $previousProgramData
            }
        }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationFixWindowsSearch\.ps1'
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
        It 'Stops the service, clears the index cache, restarts and returns 0' {
            $searchDataRoot = "$TestDrive/ProgramData/Microsoft/Search/Data"
            New-Item -ItemType Directory -Path $searchDataRoot -Force | Out-Null
            Set-Content -Path "$searchDataRoot/index.edb" -Value 'stale index'

            Mock Get-Service { [pscustomobject]@{ Name = 'WSearch'; Status = 'Running'; StartType = 'Disabled' } }
            Mock Stop-Service { }
            Mock Set-Service { }
            Mock Start-Service { }
            Mock Remove-Item { }
            Mock Test-Path { $true }
            Mock New-Object { throw "COM unavailable on this platform" }

            $out = Invoke-MainWithProgramData "$TestDrive/ProgramData"

            ($out | Out-String) | Should -Match '\[\+\] Windows Search remediation completed successfully'
            Should -Invoke Stop-Service -Times 1
            Should -Invoke Start-Service -Times 1
            Should -Invoke Remove-Item -Times 1
            ($out | Out-String) | Should -Match '\[!\] Could not trigger index rebuild automatically'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Is idempotent: running service with Automatic startup returns 0 untouched' {
            Mock Get-Service { [pscustomobject]@{ Name = 'WSearch'; Status = 'Running'; StartType = 'Automatic' } }
            Mock Stop-Service { }
            Mock Set-Service { }
            Mock Start-Service { }
            Mock Remove-Item { }
            Mock Test-Path { $false }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[\+\] Already healthy'
            Should -Not -Invoke Stop-Service
            Should -Not -Invoke Start-Service
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 and writes [-] prefixed output when WSearch does not exist' {
            Mock Get-Service { $null }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: service is not stopped and index files are kept' {
            $searchDataRoot = "$TestDrive/ProgramData/Microsoft/Search/Data"
            New-Item -ItemType Directory -Path $searchDataRoot -Force | Out-Null
            $indexFile = Join-Path $searchDataRoot 'index.edb'
            Set-Content -Path $indexFile -Value 'keep me'

            Mock Get-Service { [pscustomobject]@{ Name = 'WSearch'; Status = 'Running'; StartType = 'Disabled' } }
            Mock Stop-Service { }
            Mock Set-Service { }
            Mock Start-Service { }
            Mock Remove-Item { }
            Mock Test-Path { $true }
            Mock New-Object { throw "COM unavailable on this platform" }

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Invoke-MainWithProgramData "$TestDrive/ProgramData" | Out-Null

                Test-Path $indexFile | Should -BeTrue -Because '-WhatIf must keep index files'
                Should -Not -Invoke Stop-Service -Because '-WhatIf must not stop the service'
                Should -Not -Invoke Remove-Item -Because '-WhatIf must not delete index files'
                Should -Not -Invoke Start-Service -Because '-WhatIf must not start the service'
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
