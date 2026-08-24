#Requires -Modules Pester

Describe 'Invoke-RemediationFixTimeSync' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationFixTimeSync.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
                Set-Item -Path "Function:global:Get-CimInstance" -Value { throw "Get-CimInstance is not available on this platform" }
                Set-Item -Path "Function:global:Get-Service" -Value { throw "Get-Service is not available on this platform" }
                Set-Item -Path "Function:global:Set-Service" -Value { throw "Set-Service is not available on this platform" }
                Set-Item -Path "Function:global:Start-Service" -Value { throw "Start-Service is not available on this platform" }
                Set-Item -Path "Function:global:Restart-Service" -Value { throw "Restart-Service is not available on this platform" }

        # Baseline: converged service state and healthy w32tm responses.
        Mock Set-Service { }
        Mock Start-Service { }
        Mock Restart-Service { }
        Mock Invoke-W32tm { 0 }
        Mock Get-Service {
            [pscustomobject]@{ Name = 'W32Time'; Status = 'Running'; StartType = 'Automatic' }
        }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationFixTimeSync\.ps1'
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

        It 'Declares SupportsShouldProcess for its mutating configuration changes' {
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
        It 'Configures manual NTP for a workgroup device and returns 0' {
            Mock Get-CimInstance { [pscustomobject]@{ PartOfDomain = $false; DomainRole = 0 } }
            Mock Get-Service {
                [pscustomobject]@{ Name = 'W32Time'; Status = 'Stopped'; StartType = 'Manual' }
            }
            $script:w32Args = @()
            Mock Invoke-W32tm { $script:w32Args += ,@($args); 0 }

            Main | Should -Be 0
            Should -Invoke Set-Service -Times 1
            Should -Invoke Start-Service -Times 1
            $flatArgs = @($script:w32Args | ForEach-Object { $_ })
            $flatArgs | Should -Contain '/manualpeerlist:time.windows.com'
        }

        It 'Uses NT5DS without manual NTP or /reliable for a domain member (idempotent)' {
            Mock Get-CimInstance { [pscustomobject]@{ PartOfDomain = $true; DomainRole = 3 } }
            $script:w32Args = @()
            Mock Invoke-W32tm { $script:w32Args += ,@($args); 0 }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-Service -Times 0
            Should -Invoke Start-Service -Times 0
            $flatArgs = @($script:w32Args | ForEach-Object { $_ })
            $flatArgs | Should -Contain '/syncfromflags:domhier'
            $flatArgs | Should -Not -Contain '/manualpeerlist:time.windows.com'
            $flatArgs | Should -Not -Contain '/reliable:yes'
        }

        It 'Adds /reliable:yes for a domain controller' {
            Mock Get-CimInstance { [pscustomobject]@{ PartOfDomain = $true; DomainRole = 4 } }
            $script:w32Args = @()
            Mock Invoke-W32tm { $script:w32Args += ,@($args); 0 }

            Main | Should -Be 0
            $flatArgs = @($script:w32Args | ForEach-Object { $_ })
            $flatArgs | Should -Contain '/reliable:yes'
        }

        It 'Returns 1 and writes [-] prefixed output when role detection fails' {
            Mock Get-CimInstance { throw "CIM gone" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: no service or w32tm changes are made' {
            Mock Get-CimInstance { [pscustomobject]@{ PartOfDomain = $false; DomainRole = 0 } }
            Mock Get-Service {
                [pscustomobject]@{ Name = 'W32Time'; Status = 'Stopped'; StartType = 'Manual' }
            }

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Main *>&1 | Out-Null
                Should -Invoke Invoke-W32tm -Times 0 -Because '-WhatIf must suppress configuration'
                Should -Invoke Set-Service -Times 0
                Should -Invoke Start-Service -Times 0
                Should -Invoke Restart-Service -Times 0
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
