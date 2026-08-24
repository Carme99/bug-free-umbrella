#Requires -Modules Pester

Describe 'Invoke-RemediationCheckServiceFailures' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/system/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/system/Invoke-RemediationCheckServiceFailures.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
        # The stubs declare their parameters so -ParameterFilter can route by service name.
            Set-Item -Path 'Function:global:Get-Service' -Value {
                [CmdletBinding()]
                param([string]$Name)
                throw 'Get-Service is not available on this platform'
            }
            Set-Item -Path 'Function:global:Start-Service' -Value {
                [CmdletBinding()]
                param([string]$Name)
                throw 'Start-Service is not available on this platform'
            }

        # Default: every critical service is running (converged system).
        Mock Get-Service { [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' } }
        Mock Start-Service { }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Invoke-RemediationCheckServiceFailures\.ps1'
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

        It 'Declares SupportsShouldProcess for its service start mutation' {
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
        It 'Starts a stopped critical service and returns 0' {
            Mock Get-Service {
                [pscustomobject]@{ Status = 'Stopped'; StartType = 'Manual' }
            } -ParameterFilter { $Name -eq 'BITS' }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Successfully started BITS'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Start-Service -Times 1 -Exactly
        }

        It 'Is idempotent: all services running returns 0 with no mutation' {
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\] Already compliant: all critical services are running'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Start-Service -Times 0 -Exactly -Because 'nothing is stopped'
        }

        It 'Skips disabled services and logs a failed start without failing the run' {
            Mock Get-Service {
                [pscustomobject]@{ Status = 'Stopped'; StartType = 'Manual' }
            }
            Mock Get-Service {
                [pscustomobject]@{ Status = 'Stopped'; StartType = 'Disabled' }
            } -ParameterFilter { $Name -eq 'wuauserv' }
            Mock Start-Service { throw "service did not start" }

            $out = Main *>&1
            ($out | Out-String) | Should -Not -Match 'Attempting to start wuauserv'
            ($out | Out-String) | Should -Match '\[\*\] Attempting to start BITS'
            ($out | Out-String) | Should -Match '\[!\] Failed to start BITS'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 and writes [-] prefixed output when service enumeration fails' {
            Mock Get-Service { throw "service database gone" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Honours -WhatIf: no service is started' {
            Mock Get-Service {
                [pscustomobject]@{ Status = 'Stopped'; StartType = 'Manual' }
            } -ParameterFilter { $Name -eq 'BITS' }

            # Main is an advanced function carrying SupportsShouldProcess.
            $WhatIfPreference = $true
            try {
                Main *>&1 | Out-Null
                Should -Invoke Start-Service -Times 0 -Exactly -Because '-WhatIf must suppress the start'
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
