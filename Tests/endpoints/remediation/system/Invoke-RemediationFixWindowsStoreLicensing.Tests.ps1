#Requires -Modules Pester

Describe 'Invoke-RemediationFixWindowsStoreLicensing' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationFixWindowsStoreLicensing.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
                Set-Item -Path "Function:global:Get-Service" -Value { throw "Get-Service is not available on this platform" }
                Set-Item -Path "Function:global:Stop-Service" -Value { throw "Stop-Service is not available on this platform" }
                Set-Item -Path "Function:global:Start-Service" -Value { throw "Start-Service is not available on this platform" }
                Set-Item -Path "Function:global:Get-AppxPackage" -Value { throw "Get-AppxPackage is not available on this platform" }
                Set-Item -Path "Function:global:Add-AppxPackage" -Value { throw "Add-AppxPackage is not available on this platform" }

        # Sleeps are mocked to keep tests fast.
        Mock Start-Sleep { }
        # tokens.dat resolves under %ProgramData%; Linux CI has no such variable.
        $env:ProgramData = "$TestDrive/ProgramData"
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationFixWindowsStoreLicensing\.ps1'
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
        It 'Stops ClipSVC, deletes tokens.dat, restarts ClipSVC and re-registers Store' {
            Mock Get-Service { [pscustomobject]@{ Name = 'ClipSVC'; Status = 'Running' } }
            Mock Test-Path { $true }
            Mock Stop-Service { }
            Mock Remove-Item { }
            Mock Start-Service { }
            Mock Get-AppxPackage { [pscustomobject]@{ Name = 'Microsoft.WindowsStore'; InstallLocation = 'C:\Store' } }
            Mock Add-AppxPackage { }
            Mock Invoke-Wsreset { 0 }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[\+\] Windows Store licensing remediation completed'
            Should -Invoke Stop-Service -Times 1
            Should -Invoke Remove-Item -Times 1
            Should -Invoke Start-Service -Times 1
            Should -Invoke Add-AppxPackage -Times 1
            Should -Invoke Invoke-Wsreset -Times 1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Is idempotent: missing token cache returns 0 with no changes' {
            Mock Get-Service { [pscustomobject]@{ Name = 'ClipSVC'; Status = 'Running' } }
            Mock Test-Path { $false }
            Mock Stop-Service { }
            Mock Remove-Item { }
            Mock Invoke-Wsreset { 0 }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[\+\] Already clean'
            Should -Not -Invoke Stop-Service
            Should -Not -Invoke Remove-Item
            Should -Not -Invoke Invoke-Wsreset
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 and writes [-] prefixed output when ClipSVC cannot be stopped' {
            Mock Get-Service { [pscustomobject]@{ Name = 'ClipSVC'; Status = 'Running' } }
            Mock Test-Path { $true }
            Mock Stop-Service { throw "access denied" }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: ClipSVC stays up and tokens.dat is kept' {
            Mock Get-Service { [pscustomobject]@{ Name = 'ClipSVC'; Status = 'Running' } }
            Mock Test-Path { $true }
            Mock Stop-Service { }
            Mock Remove-Item { }
            Mock Start-Service { }
            Mock Get-AppxPackage { [pscustomobject]@{ Name = 'Microsoft.WindowsStore'; InstallLocation = 'C:\Store' } }
            Mock Add-AppxPackage { }
            Mock Invoke-Wsreset { 0 }

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Main *>&1 | Out-Null
                Should -Not -Invoke Stop-Service -Because '-WhatIf must not stop ClipSVC'
                Should -Not -Invoke Remove-Item -Because '-WhatIf must keep tokens.dat'
                Should -Not -Invoke Start-Service
                Should -Not -Invoke Invoke-Wsreset -Because '-WhatIf must not reset the Store cache'
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
