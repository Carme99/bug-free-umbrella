#Requires -Modules Pester

Describe 'Invoke-RemediationFixDiskSpace' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationFixDiskSpace.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
                Set-Item -Path "Function:global:Clear-RecycleBin" -Value { throw "Clear-RecycleBin is not available on this platform" }
                Set-Item -Path "Function:global:Stop-Service" -Value { throw "Stop-Service is not available on this platform" }
                Set-Item -Path "Function:global:Start-Service" -Value { throw "Start-Service is not available on this platform" }

        # Contain the run: %SystemRoot% resolves to the Pester test drive.
        $env:SystemRoot = "$TestDrive/Windows"
        New-Item -ItemType Directory -Path "$TestDrive/Windows/Temp" -Force | Out-Null
        New-Item -ItemType Directory -Path "$TestDrive/Windows/SoftwareDistribution/Download" -Force | Out-Null

        Mock Clear-RecycleBin { }
        Mock Stop-Service { }
        Mock Start-Service { }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationFixDiskSpace\.ps1'
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
        It 'Deletes stale temp files and Windows Update cache content and returns 0' {
            $staleTemp = Join-Path $env:SystemRoot 'Temp/junk.log'
            Set-Content -Path $staleTemp -Value 'stale'
            (Get-Item $staleTemp).LastWriteTime = (Get-Date).AddDays(-30)
            Set-Content -Path (Join-Path $env:SystemRoot 'SoftwareDistribution/Download/payload.cab') -Value ('x' * 10MB)

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Cleaned'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Test-Path $staleTemp | Should -BeFalse -Because 'the stale temp file must be deleted'
            Should -Invoke Clear-RecycleBin -Times 1 -Exactly
        }

        It 'Is idempotent: converged system returns 0 with no changes' {
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Already clean'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 and writes [-] prefixed output when deletion fails' {
            Set-Content -Path (Join-Path $env:SystemRoot 'Temp/locked.log') -Value 'locked'
            (Get-Item (Join-Path $env:SystemRoot 'Temp/locked.log')).LastWriteTime = (Get-Date).AddDays(-30)
            Mock Remove-Item { throw "file locked" }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: no files are deleted and no bin is emptied' {
            $staleTemp = Join-Path $env:SystemRoot 'Temp/old.txt'
            Set-Content -Path $staleTemp -Value 'keep me'
            (Get-Item $staleTemp).LastWriteTime = (Get-Date).AddDays(-14)

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Main *>&1 | Out-Null
                Test-Path $staleTemp | Should -BeTrue -Because '-WhatIf must suppress deletion'
                Test-Path (Join-Path $env:SystemRoot 'SoftwareDistribution/Download') | Should -BeTrue
                Should -Invoke Clear-RecycleBin -Times 0 -Exactly -Scope It -Because '-WhatIf must suppress the recycle bin purge'
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
