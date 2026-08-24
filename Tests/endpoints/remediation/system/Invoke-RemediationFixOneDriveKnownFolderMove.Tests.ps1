#Requires -Modules Pester

Describe 'Invoke-RemediationFixOneDriveKnownFolderMove' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationFixOneDriveKnownFolderMove.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets are absent on Linux CI. Pester cannot mock a
        # command it cannot resolve, so define SCRIPT-SCOPED tolerant stand-ins
        # here (never global functions — those persist across the whole
        # Pester session and bleed into sibling test files). Script-scoped
        # functions die with this file's session scope.
        function Get-CimInstance {
            [CmdletBinding()]
            param([string]$ClassName)
            throw "Get-CimInstance is not available on this platform"
        }

        # The registry-only -Type dynamic parameter of Set-ItemProperty does
        # not exist off-Windows; the stand-in accepts it so the Pester mock
        # proxy can bind the script's -Type argument.
        function Set-ItemProperty {
            [CmdletBinding()]
            param(
                [Parameter(Position = 0)]
                [string]$Path,
                [Parameter(Position = 1)]
                [string]$Name,
                [Parameter(Position = 2)]
                $Value,
                [string]$Type
            )
        }

        # Keep the run fast; mutations below are mocked per test.
        Mock Start-Sleep { }
        Mock Start-Process { }
        Mock Stop-Process { }
        Mock New-Item { }
        Mock Get-CimInstance { throw "Get-CimInstance is not available on this platform" }
        Mock Set-ItemProperty { }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationFixOneDriveKnownFolderMove\.ps1'
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

        It 'Declares SupportsShouldProcess for its registry and process mutations' {
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
        It 'Starts OneDrive and sets the KFM registry values for the current user' {
            Mock Get-Process { $null }
            Mock Get-CimInstance {
                [pscustomobject]@{ UserName = 'CONTOSO\alice' }
            }
            Mock Resolve-UserSid { 'S-1-5-21-1001' }
            Mock Test-Path { $false }  # OneDrive.exe absent from the default path, key missing
            Mock Get-ItemProperty { $null }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Configured OneDrive KFM registry settings'
            ($out | Out-String) | Should -Match '\[\+\] Started OneDrive application'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-ItemProperty -Times 2 -Exactly -Scope It
        }

        It 'Is idempotent: already-configured system returns 0 with no changes' {
            Mock Get-Process { @([pscustomobject]@{ Name = 'OneDrive' }) }
            Mock Get-CimInstance {
                [pscustomobject]@{ UserName = 'CONTOSO\alice' }
            }
            Mock Resolve-UserSid { 'S-1-5-21-1002' }
            Mock Test-Path { $true }
            Mock Get-ItemProperty {
                [pscustomobject]@{ KFMSilentOptIn = '1'; KFMSilentOptInWithNotification = 1 }
            }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Already configured'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-ItemProperty -Times 0 -Exactly -Scope It
            Should -Invoke Stop-Process -Times 0 -Exactly -Scope It
            Should -Invoke Start-Process -Times 0 -Exactly -Scope It
        }

        It 'Returns 1 and writes [-] prefixed output when computer system lookup fails' {
            Mock Get-Process { $null }
            Mock Get-CimInstance { throw "CIM gone" }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: no processes are started/stopped and no values are set' {
            Mock Get-Process { $null }
            Mock Get-CimInstance {
                [pscustomobject]@{ UserName = 'CONTOSO\alice' }
            }
            Mock Resolve-UserSid { 'S-1-5-21-1003' }
            Mock Test-Path { $true }
            Mock Get-ItemProperty { $null }

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Main *>&1 | Out-Null
                Should -Invoke Set-ItemProperty -Times 0 -Exactly -Scope It -Because '-WhatIf must suppress registry writes'
                Should -Invoke New-Item -Times 0 -Exactly -Scope It
                Should -Invoke Stop-Process -Times 0 -Exactly -Scope It
                Should -Invoke Start-Process -Times 0 -Exactly -Scope It -Because '-WhatIf must suppress starting OneDrive'
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
