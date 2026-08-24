#Requires -Modules Pester

Describe "Get-ExchangeServerHealth" {
    BeforeAll {
        # Mirrored layout: mirrored at Tests/collaboration/email/exchange-server/ -> repo root is four levels up.
        $scriptPath = Join-Path $PSScriptRoot (
            "../../../../scripts/collaboration/email/exchange-server/Get-ExchangeServerHealth.ps1")

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Function shims: Pester cannot mock commands absent from Linux pwsh, and mock parameter
        # filters are resolved against the shim's signature - so declare the parameters the script uses.
        function Add-PSSnapin { param([string]$Name) }
        function Get-ExchangeServer { }
        function Get-Service { param([string]$ComputerName) }
        function Get-MailboxDatabase { param([switch]$Status) }
        function Get-Queue { }

        # Mock ALL external commands so nothing leaves the machine (offline Linux pwsh).
        Mock Add-PSSnapin { }
        Mock Get-ExchangeServer {
            @(
                [pscustomobject]@{ Name = 'EX01'; ServerRole = 'Mailbox' },
                [pscustomobject]@{ Name = 'EDGE01'; ServerRole = 'Edge' }
            )
        }
        Mock Get-Service { @() }
        Mock Get-MailboxDatabase { @() }
        Mock Get-Queue { @() }
    }

    Context "Help & Metadata" {
        It "Declares all required header fields with relaunch values" {
            $content = Get-Content -Path $scriptPath -Raw
            $content | Should -Match '\.SYNOPSIS'
            $content | Should -Match '\.DESCRIPTION'
            $content | Should -Match '\.NOTES'
            $content | Should -Match 'Version\s*:\s*1\.0\.0'
            $content | Should -Match 'Date\s*:\s*2026-08-23'
            $content | Should -Match 'File Name\s*:\s*Get-ExchangeServerHealth\.ps1'
            $content | Should -Match 'Author\s*:\s*\S+'
            $content | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
        }

        It "Has a SYNOPSIS that is imperative and <= 120 characters" {
            $lines = Get-Content -Path $scriptPath
            $idx = [array]::IndexOf(($lines | ForEach-Object { $_.Trim() }), '.SYNOPSIS')
            $synopsis = ($lines[$idx + 1]).Trim()
            $synopsis | Should -Not -BeNullOrEmpty
            $synopsis.Length | Should -BeLessOrEqual 120
        }

        It "Has one .PARAMETER entry per declared script parameter, in order" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $paramNames = $ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }

            $lines = Get-Content -Path $scriptPath
            $helpParamNames = @()
            foreach ($line in $lines) {
                if ($line -match '^\.PARAMETER\s+(\S+)') { $helpParamNames += $Matches[1] }
            }

            $helpParamNames.Count | Should -Be $paramNames.Count
            for ($i = 0; $i -lt $paramNames.Count; $i++) {
                $helpParamNames[$i] | Should -Be $paramNames[$i]
            }
        }

        It "Provides at least two examples showing PS C:\> prompts" {
            $content = Get-Content -Path $scriptPath -Raw
            ($content -split '\.EXAMPLE').Count -ge 3 | Should -BeTrue
            ([regex]::Matches($content, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }

        It "Renders complete help via Get-Help -Detailed" {
            { Get-Help -Path $scriptPath -Detailed -ErrorAction Stop } | Should -Not -Throw
            (Get-Help -Path $scriptPath -ErrorAction Stop).Synopsis | Should -Not -BeNullOrEmpty
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null; $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors | Should -HaveCount 0
        }

        It "Contains no PS7-only syntax without #Requires -Version 7.0" {
            $content = Get-Content -Path $scriptPath -Raw
            if ($content -match '(?m)^#Requires\s+-Version\s+7\.0') {
                $true | Should -BeTrue
            }
            else {
                $content | Should -Not -Match '\?\?'
                $content | Should -Not -Match '\|\|'
                $content | Should -Not -Match '&&'
                $content | Should -Not -Match '-Parallel'
            }
        }

        It "Is UTF-8 with BOM and CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
            $raw = [System.Text.Encoding]::UTF8.GetString($bytes)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }
    }

    Context "Behavior" {
        It "Returns 0 on a healthy baseline and only contacts non-Edge servers" {
            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Get-Service -Times 1 -Exactly -ParameterFilter { $ComputerName -eq 'EX01' }
            Should -Invoke Get-Service -Times 0 -Exactly -ParameterFilter { $ComputerName -eq 'EDGE01' }
        }

        It "Warns with [!] when Exchange services are stopped" {
            Mock Get-Service {
                @([pscustomobject]@{ DisplayName = 'Microsoft Exchange Information Store'; Status = 'Stopped' })
            }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[!\]'
        }

        It "Reports database mount status with -CheckDatabaseHealth" {
            Mock Get-MailboxDatabase {
                @(
                    [pscustomobject]@{ Name = 'DB01'; Mounted = $true },
                    [pscustomobject]@{ Name = 'DB02'; Mounted = $false }
                )
            }

            $out = Main -CheckDatabaseHealth *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match 'DB01: Mounted'
            $text | Should -Match 'DB02: Dismounted'
        }

        It "Reports queue totals with -CheckMailQueues" {
            Mock Get-Queue {
                @(
                    [pscustomobject]@{ MessageCount = 150 },
                    [pscustomobject]@{ MessageCount = 50 }
                )
            }

            $out = Main -CheckMailQueues *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Total messages in queues: 200'
        }

        It "Returns 1 and writes [-] prefixed output when the snap-in is unavailable" {
            Mock Add-PSSnapin { throw "snap-in not available" }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 and writes [-] prefixed output when server enumeration fails" {
            Mock Get-ExchangeServer { throw "RPC unavailable" }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
