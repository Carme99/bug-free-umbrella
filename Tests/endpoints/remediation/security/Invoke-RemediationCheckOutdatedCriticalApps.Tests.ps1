#Requires -Modules Pester

Describe "Invoke-RemediationCheckOutdatedCriticalApps" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/security/Invoke-RemediationCheckOutdatedCriticalApps.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        # $env:TEMP is unset on Linux pwsh; the script body joins paths against it.
        $env:TEMP = '/tmp'
        . $scriptPath
        $EnableLogging = $false
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Invoke-RemediationCheckOutdatedCriticalApps\.ps1'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
            $raw | Should -Match 'Author:'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
        }

        It "Has SYNOPSIS, DESCRIPTION and at least two EXAMPLES" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
        }

        It "Declares one .PARAMETER per param() parameter" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
            if ($null -eq $ast.ParamBlock) { $declared = @() }
            else { $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.Extent.Text.TrimStart('$') }) }
            $raw = Get-Content -Path $scriptPath -Raw
            $paramHelpMatches = [regex]::Matches($raw, '(?m)^\s*\.PARAMETER\s+(\S+)')
            $documented = @($paramHelpMatches | ForEach-Object { $_.Groups[1].Value })
            @($documented).Count | Should -Be @($declared).Count
            foreach ($p in $declared) { $documented | Should -Contain $p }
        }

        It "Documents every parameter in declaration order" {
            $raw = Get-Content -Path $scriptPath -Raw
            $documented = @([regex]::Matches($raw, '(?m)^\s*\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value })
            $documented[0] | Should -Be 'EnableLogging'
            $documented[1] | Should -Be 'MaxRetries'
            $documented[-2] | Should -Be 'ForceCloseApps'
            $documented[-1] | Should -Be 'TimeoutPerAppMinutes'
        }
    }

    Context "Syntax & Static" {
        BeforeAll {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        }
        It "Parses with zero errors" {
            $errors | Should -BeNullOrEmpty
        }
        It "Contains no PS7-only operators (no #Requires -Version 7.0 opt-out present)" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Not -Match '(?m)&&|\|\||\?\?|\?\?='
            $raw | Should -Not -Match '\$\w+\s*\?\s*[^:]'
        }
        It "Calls winget only through the thin wrapper function" {
            $raw = Get-Content -Path $scriptPath -Raw
            # Every bare winget invocation must be inside a wrapper function body.
            ($raw -split "`n" | Where-Object { $_ -match '&\s*winget' }).Count | Should -Be 2
        }
    }

    Context "Behavior" {
        It "Returns 0 when no outdated applications are found" {
            Mock Invoke-Winget {
                [PSCustomObject]@{ Output = @(''); ExitCode = 0 }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'No outdated applications found'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Invoke-Winget -Exactly 1 -Scope It
        }

        It "Updates an outdated priority application and returns 0" {
            Mock Invoke-Winget {
                [PSCustomObject]@{
                    Output = @(
                        '',
                        'Name              Id               Version      Available',
                        '----------------  ---------------  -----------  ---------',
                        '  Google Chrome    Google.Chrome    131.0.1      132.0.2',
                        '  1 upgrades available',
                        ''
                    )
                    ExitCode = 0
                }
            }
            function Start-Job { }
            function Wait-Job { }
            function Receive-Job { }
            function Remove-Job { }
            Mock Get-Process { $null }
            Mock Start-Job { [pscustomobject]@{ Id = [guid]::NewGuid() } }
            Mock Wait-Job { $true }
            Mock Receive-Job { 'Successfully installed' }
            Mock Remove-Job { }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match 'Successfully Updated: 1'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Start-Job -Exactly 1 -Scope It
        }

        It "Retries failed updates up to MaxRetries and returns 1 when all attempts fail" {
            Mock Invoke-Winget {
                [PSCustomObject]@{
                    Output = @(
                        '  Google Chrome    Google.Chrome    131.0.1      132.0.2',
                        ''
                    )
                    ExitCode = 0
                }
            }
            function Start-Job { }
            function Wait-Job { }
            function Receive-Job { }
            function Remove-Job { }
            Mock Get-Process { $null }
            Mock Start-Job { [pscustomobject]@{ Id = [guid]::NewGuid() } }
            Mock Wait-Job { $true }
            Mock Receive-Job { 'Installation failed with error 0x80070005' }
            Mock Remove-Job { }
            function Start-Sleep { }
            Mock Start-Sleep { }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Out-String) | Should -Match 'Failed: 1'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            Should -Invoke Start-Job -Exactly 3 -Scope It
            Should -Invoke Start-Sleep -Exactly 2 -Scope It
        }

        It "Returns 0 when the winget inventory fails (no outdated apps to act on)" {
            Mock Invoke-Winget {
                [PSCustomObject]@{ Output = @('winget: command not found'); ExitCode = 9009 }
            }
            $out = Main *>&1
            ($out | Out-String) | Should -Match 'No outdated applications found'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }
    }
}
