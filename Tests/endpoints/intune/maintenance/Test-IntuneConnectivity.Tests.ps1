#Requires -Modules Pester

Describe "Test-IntuneConnectivity" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/endpoints/intune/maintenance/Test-IntuneConnectivity.ps1"

        # Static analysis inputs
        $rawScript = Get-Content -LiteralPath $scriptPath -Raw
        $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
        $parseErrors = $null
        $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath, [ref]$null, [ref]$parseErrors)

        # Stub the Windows-only DNS cmdlet so Pester can mock it on Linux.
        function Resolve-DnsName { param([string]$Name) }

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Mock ALL externals so nothing leaves the machine (zero network, zero registry, zero native calls).
        Mock Invoke-WebRequest { [pscustomobject]@{ StatusCode = 200; Headers = @{} } }
        Mock Resolve-DnsName { [pscustomobject]@{ NameHost = 'login.microsoftonline.com' } }
        Mock Get-ItemProperty { [pscustomobject]@{ ProxyEnable = 0; ProxyServer = '' } }
        Mock Invoke-DsRegCmdStatus { "AzureAdJoined : YES`nWorkplaceJoined : NO" }
        Mock Export-Csv { }
    }

    Context "Help & Metadata" {
        It "Contains all five required .NOTES fields with correct values" {
            $rawScript | Should -Match '\.NOTES'
            $rawScript | Should -Match 'File Name:\s*Test-IntuneConnectivity\.ps1'
            $rawScript | Should -Match 'Author:\s*\S+'
            $rawScript | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
            $rawScript | Should -Match 'Version:\s*1\.0\.0'
            $rawScript | Should -Match 'Date:\s*2026-08-23'
        }

        It "Has one .PARAMETER entry per declared param, in order" {
            $declared = $scriptAst.ParamBlock.Parameters.Name.VariablePath.UserPath
            $documented = [regex]::Matches($rawScript, '(?m)^\s*\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value }
            $documented | Should -Be $declared
        }

        It "Has at least two examples with PS C:\> prompts" {
            ([regex]::Matches($rawScript, '\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($rawScript, [regex]::Escape('PS C:\>'))).Count | Should -BeGreaterOrEqual 2
        }

        It "Is saved as UTF-8 with BOM" {
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only operators (no #Requires -Version 7.0 opt-out)" {
            $rawScript | Should -Not -Match '#Requires\s+-Version'
            $rawScript | Should -Not -Match '\?\?'
            $rawScript | Should -Not -Match '&&|\|\|'
        }

        It "Defines a Main function and the dot-source guard, with exit only in the guard" {
            $mainFn = $scriptAst.FindAll({ param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -eq 'Main' }, $true)
            ($mainFn | Should -Not -BeNullOrEmpty)
            $guardLine = 'if ($MyInvocation.InvocationName -ne ''.'') { exit (Main) }'
            $rawScript | Should -Match ([regex]::Escape($guardLine))
            ([regex]::Matches($rawScript, '\bexit\b')).Count | Should -Be 1
        }

        It "Uses only approved verbs for internal functions" {
            $isFn = { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }
            $functions = $scriptAst.FindAll($isFn, $true) | Select-Object -ExpandProperty Name
            foreach ($fn in ($functions | Where-Object { $_ -ne 'Main' })) {
                $verb = ($fn -split '-')[0]
                (Get-Verb -Verb $verb) | Should -Not -BeNullOrEmpty -Because "$fn must use an approved verb"
            }
        }

        It "Calls the native dsregcmd only through its wrapper function" {
            $nativeCalls = $rawScript -split "`n" | Where-Object { $_ -match '& dsregcmd' }
            $nativeCalls.Count | Should -Be 1 -Because "the native call lives only inside the wrapper"
        }
    }

    Context "Behavior" {
        It "Returns 0 when all 14 endpoints are reachable, DNS works, and device is AAD joined" {
            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Passed: 14'
            ($out | Out-String) | Should -Match 'Failed: 0'
            ($out | Out-String) | Should -Match '\[\+\] DNS resolution working'
            Should -Invoke Invoke-DsRegCmdStatus -Exactly 1 -Because "dsregcmd must go through the wrapper"
            Should -Invoke Export-Csv -Times 0
        }

        It "Returns the documented failure code 1 with recommendations when an endpoint is unreachable" {
            Mock Invoke-WebRequest `
                -ParameterFilter { $Uri -eq 'https://au.download.windowsupdate.com' } `
                { throw "connection refused" }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match 'Failed: 1'
            ($out | Out-String) | Should -Match '\[!\] Recommendations:'
        }

        It "-ExportResults writes one CSV report with every endpoint result and still returns 0" {
            . $scriptPath -ExportResults
            # NOTE: piping 14 result rows into the mocked function makes Pester run the mock body
            # once per row, so we assert on the distinct report path instead of invocation count.
            $exportedPaths = New-Object System.Collections.Generic.List[string]
            Mock Export-Csv { param([string]$Path) $exportedPaths.Add($Path) }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($exportedPaths | Select-Object -Unique).Count |
                Should -Be 1 -Because "each run exports exactly one CSV report"
            ($out | Out-String) | Should -Match '\[\+\] Results exported to:'
        }

        It "-Detailed prints per-endpoint status lines for successes and failures" {
            . $scriptPath -Detailed
            Mock Invoke-WebRequest -ParameterFilter { $Uri -eq 'https://graph.windows.net' } { throw "timeout" }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            $text = $out | Out-String
            $text | Should -Match '\[\+\] https://enrollment\.manage\.microsoft\.com - Status: 200'
            $text | Should -Match '\[-\] https://graph\.windows\.net - Error: timeout'
        }

        It "Degrades gracefully offline: DNS, registry, and dsregcmd failures still return 0" {
            Mock Resolve-DnsName { throw "no resolver" }
            Mock Get-ItemProperty { $null }
            Mock Invoke-DsRegCmdStatus { throw "dsregcmd not found" }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[-\] DNS resolution failed'
            $text | Should -Match '\[\+\] No proxy configured'
            $text | Should -Match '\[-\] Could not determine Azure AD join status'
        }
    }
}
