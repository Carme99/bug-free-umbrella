#Requires -Modules Pester

Describe "Optimize-IISConfiguration" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../../scripts/infrastructure/web/iis/Optimize-IISConfiguration.ps1"
        $scriptText = Get-Content -LiteralPath $scriptPath -Raw

        # Placeholder functions: product modules are not installed offline;
        # Pester Mock requires the command names to be resolvable.
        function Set-WebConfigurationProperty { }
        function Add-WebConfigurationProperty { }
        function Get-IISServerManager { }
        function Get-IISSite { }
        function Set-ItemProperty { }
        function Get-ItemProperty { }

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Mock all external commands (WebAdministration + IISAdministration + registry).
        Mock Set-WebConfigurationProperty { }
        Mock Add-WebConfigurationProperty { }
        Mock Set-ItemProperty { }

        function New-TestServerManager {
            $sm = [pscustomobject]@{
                ApplicationPools = @([pscustomobject]@{
Recycling    = [pscustomobject]@{
                                PeriodicRestart = [pscustomobject]@{ Time = [timespan]::FromHours(8) }
                            }
                    ProcessModel = [pscustomobject]@{ IdleTimeout = [timespan]::FromMinutes(10) }
                    QueueLength  = 1000
                })
            }
            $sm | Add-Member -MemberType ScriptMethod -Name CommitChanges -Value { }
            return $sm
        }
    }

    Context "Help & Metadata" {
        It "Declares the complete header block" {
            $scriptText | Should -Match '(?m)^\.SYNOPSIS'
            $scriptText | Should -Match '(?m)^\.DESCRIPTION'
            $scriptText | Should -Match '(?m)^\.NOTES'
        }

        It "Populates all five .NOTES fields correctly" {
            $scriptText | Should -Match 'File Name\s*:\s*Optimize-IISConfiguration\.ps1'
            $scriptText | Should -Match 'Author\s*:\s*\S'
            $scriptText | Should -Match 'Prerequisite\s*:\s*PowerShell'
            $scriptText | Should -Match 'Version\s*:\s*1\.0\.0'
            $scriptText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Has at least 2 examples with PS C:\> prompts" {
            ([regex]::Matches($scriptText, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($scriptText, [regex]::Escape('PS C:\>'))).Count | Should -BeGreaterOrEqual 2
        }

        It "Documents one .PARAMETER per declared parameter, in order" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
            $declared = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
            $documented = [regex]::Matches($scriptText, '(?m)^\.PARAMETER\s+(\S+)') |
                    ForEach-Object { $_.Groups[1].Value }
            $documented | Should -Be $declared
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                    $scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
            $errors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only operators without a #Requires -Version 7.0 opt-out" {
            if ($scriptText -notmatch '(?m)^#Requires\s+-Version\s+7\.0') {
                $tokens = $null
                $parseErrors = $null
                [System.Management.Automation.Language.Parser]::ParseInput(
                        $scriptText, [ref]$tokens, [ref]$parseErrors) | Out-Null
                $kindType = [System.Management.Automation.Language.TokenKind]
                $ps7Kinds = @('AmpersandAmpersand', 'BarBar', 'QuestionMark', 'QuestionQuestionEquals') |
                    Where-Object { $kindType.GetMember($_) }
                $offenders = @($tokens | Where-Object { $ps7Kinds -contains [string]$_.Kind })
                $offenders | Should -BeNullOrEmpty -Because "PS7-only operators require #Requires opt-out"
            }
        }

        It "Uses the mandatory Main entrypoint and dot-source guard" {
            $guard = "if (`$MyInvocation.InvocationName -ne '.') { exit (Main) }"
            $scriptText.Contains($guard) | Should -BeTrue
        }
    }

    Context "Behavior" {
        It "Applies performance optimizations via mocked config cmdlets and returns 0" {
            Mock Get-IISServerManager { New-TestServerManager }
            $ApplyPerformanceOptimizations = $true

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Set-WebConfigurationProperty -Times 3 -Exactly
            Should -Invoke Get-IISServerManager -Times 1 -Exactly
            ($out | Out-String) | Should -Match '\[\+\]'
        }

        It "Honors -WhatIf: previews without applying any change" {
            Mock Get-IISServerManager { New-TestServerManager }
            $ApplyPerformanceOptimizations = $true

            $out = Main -WhatIf *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Set-WebConfigurationProperty -Times 0 -Exactly
            Should -Invoke Get-IISServerManager -Times 0 -Exactly
            ($out | Out-String) | Should -Match 'No changes applied'
        }

        It "Security hardening adds 4 headers per site and hardens server-level config" {
            Mock Get-IISSite { @([pscustomobject]@{ Name = 'Site1' }) }
            $ApplySecurityHardening = $true

            ($out = Main *>&1) | Out-Null

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Add-WebConfigurationProperty -Times 4 -Exactly
            Should -Invoke Set-WebConfigurationProperty -Times 2 -Exactly
        }

        It "Is idempotent for HTTP/2: already-enabled registry values cause no writes" {
            Mock Get-ItemProperty { [pscustomobject]@{ EnableHttp2Tls = 1; EnableHttp2Cleartext = 1 } }
            $EnableHTTP2 = $true

            ($out = Main *>&1) | Out-Null

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Set-ItemProperty -Times 0 -Exactly
            ($out | Out-String) | Should -Match 'HTTP/2 already enabled'
        }

        It "Writes both HTTP/2 registry values when not yet enabled, returning 0" {
            Mock Get-ItemProperty { $null }
            $EnableHTTP2 = $true

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Set-ItemProperty -Times 2 -Exactly
        }
    }
}
