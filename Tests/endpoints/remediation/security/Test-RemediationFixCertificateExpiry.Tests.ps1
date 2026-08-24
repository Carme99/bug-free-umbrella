#Requires -Modules Pester

Describe 'Test-RemediationFixCertificateExpiry' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/remediation/security/
        # -> repo root is four levels up, then across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/remediation/security/Test-RemediationFixCertificateExpiry.ps1'
        $scriptText = Get-Content $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Windows-only cmdlets do not exist on Linux CI; stub them so Pester can mock.
        Set-Item -Path "Function:global:Get-CimInstance" -Value `
            { throw "Get-CimInstance is not available on this platform" }

        Mock Get-CimInstance { @() }
        Mock Test-Path { $false }
        Mock Get-ChildItem { @() }
        Mock Get-ItemProperty { $null }
        Mock Invoke-RegExe { 0 }
    }

    Context 'Help & Metadata' {
        It 'Declares the five required .NOTES fields with relaunch values' {
            $scriptText | Should -Match 'File Name\s*:\s*Test-RemediationFixCertificateExpiry\.ps1'
            $scriptText | Should -Match 'Author\s*:'
            $scriptText | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
            $scriptText | Should -Match 'Version\s*:\s*1\.0\.0'
            $scriptText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It 'Documents its detect exit-code contract in DESCRIPTION' {
            $scriptText | Should -Match '(?m)^\.DESCRIPTION'
            $scriptText | Should -Match 'Exit codes?: 0 ='
            $scriptText | Should -Match '(?s)Exit codes?: 0 =.+?1 ='
        }

        It 'Has comment-based help with SYNOPSIS and >=2 EXAMPLES' {
            $scriptText | Should -Match '(?m)^\.SYNOPSIS'
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

        It 'Routes reg.exe through an approved-verb wrapper instead of calling it directly' {
            # Native executables must only be invoked via thin wrappers (spec §3).
            $bodyMatches = [regex]::Matches(
                $scriptText, '(?m)^\s*&\s*reg\.exe')
            $bodyMatches.Count | Should -Be 1 -Because 'reg.exe must be called exactly once, inside Invoke-RegExe'
            $scriptText | Should -Match 'function Invoke-RegExe'
        }

        It 'Uses approved verbs only for its functions' {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $functions = $ast.FindAll(
                { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
            foreach ($fn in $functions) {
                if ($fn.Name -eq 'Main') { continue }  # mandated by spec §3
                $verb = ($fn.Name -split '-')[0]
                Get-Verb -Verb $verb | Should -Not -BeNullOrEmpty -Because "'$($fn.Name)' must use an approved verb"
            }
        }
    }

    Context 'Behavior' {
        It 'Returns 0 when no stores or profiles contain certificates (compliant)' {
            Mock Test-Path { $false }
            Mock Get-CimInstance { @() }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match 'No expired or expiring certificates found'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
        }

        It 'Returns 1 and lists expired certificates found in the machine store' {
            Mock Test-Path { param($Path) $Path -eq 'Cert:\LocalMachine\My' }
            Mock Get-ChildItem {
                @([pscustomobject]@{
                        Subject    = 'CN=Old Server Cert'
                        Thumbprint = 'DEADBEEF00000000000000000000000000000000'
                        NotAfter   = (Get-Date).AddDays(-5)
                    })
            }
            Mock Get-CimInstance { @() }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'Expired certificates found:'
            ($out | Out-String) | Should -Match 'CN=Old Server Cert'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Returns 1 and flags certificates expiring within the warning window' {
            Mock Test-Path { param($Path) $Path -eq 'Cert:\CurrentUser\My' }
            Mock Get-ChildItem {
                @([pscustomobject]@{
                        Subject    = 'CN=Almost Gone'
                        Thumbprint = 'CAFEBABE00000000000000000000000000000000'
                        NotAfter   = (Get-Date).AddDays(10)
                    })
            }
            Mock Get-CimInstance { @() }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Out-String) | Should -Match 'Certificates expiring within 30 days'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Skips profiles whose NTUSER.DAT hive cannot be loaded and still returns 0' {
            Mock Test-Path { param($Path) $Path -like '*NTUSER.DAT' }
            Mock Get-CimInstance {
                @([pscustomobject]@{ Special = $false; LocalPath = '/home/alice'; SID = 'S-1-5-21-1234' })
            }
            # Hive load fails (in use / locked): wrapper reports non-zero exit code.
            Mock Invoke-RegExe { 1 }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match 'No expired or expiring certificates found'
            ($out | Out-String) | Should -Match '1 user profile\(s\) were skipped'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            # Only the failed load attempt; no unload of a hive we did not mount.
            Should -Invoke Invoke-RegExe -Times 1 -Exactly
        }

        It 'Unloads a user hive it loaded itself' {
            Mock Test-Path { param($Path) $Path -like '*NTUSER.DAT' }
            Mock Get-CimInstance {
                @([pscustomobject]@{ Special = $false; LocalPath = '/home/jack'; SID = 'S-1-5-5218' })
            }
            Mock Invoke-RegExe { 0 }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            # load + unload through the wrapper seam; reg.exe never called directly.
            Should -Invoke Invoke-RegExe -Times 2 -Exactly
        }

        It 'Returns 1 and writes [-] prefixed output when profile enumeration fails' {
            Mock Get-CimInstance { throw "WMI gone" }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }

    AfterAll {
        # Hygiene: remove platform stubs and restore a FileSystem location so
        # nothing leaks into sibling test containers in the same Pester run.
        foreach ($cmd in @('Get-CimInstance')) {
            $existing = Get-Command $cmd -ErrorAction SilentlyContinue
            if ($existing -and $existing.CommandType -eq 'Function') {
                Remove-Item -LiteralPath "Function:global:$cmd" -Force
            }
        }
        Set-Location $PSScriptRoot
    }
}
