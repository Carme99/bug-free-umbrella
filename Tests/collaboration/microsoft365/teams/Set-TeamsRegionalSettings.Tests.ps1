#Requires -Modules Pester

Describe "Set-TeamsRegionalSettings.ps1" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/collaboration/microsoft365/teams/ -> four levels up to repo root.
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/collaboration/microsoft365/teams/Set-TeamsRegionalSettings.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Stub + mock external module surface so nothing leaves the machine.
        # MicrosoftTeams is not installed offline: declare stubs so Pester can attach mocks.
        function Connect-MicrosoftTeams { }
        function Get-CsOnlineUser { }
        function Set-CsTeamsMeetingPolicy { }
        Mock Get-Module { [pscustomobject]@{ Name = 'MicrosoftTeams' } }
        Mock Get-CsOnlineUser { [pscustomobject]@{ UserPrincipalName = 'owner@contoso.com' } }
        Mock Connect-MicrosoftTeams { }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date 2026-08-23" {
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            $raw | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
            $raw | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
        }

        It "Declares File Name matching the actual filename and PowerShell 7.0 prerequisite" {
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            $fileName = Split-Path $scriptPath -Leaf
            $raw | Should -Match ([regex]::Escape("File Name  : $fileName"))
            $raw | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
        }

        It "Has an imperative .SYNOPSIS of at most 120 characters" {
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            $match = [regex]::Match($raw, '(?ms)\.SYNOPSIS\r?\n(.*?)\r?\n\.')
            $match.Success | Should -BeTrue
            $synopsis = (($match.Groups[1].Value -split "\r?\n") | ForEach-Object { $_.Trim() }) -join ' '
            $synopsis | Should -Not -BeNullOrEmpty
            $synopsis.Length | Should -BeLessOrEqual 120
        }

        It "Documents exactly one .PARAMETER block per declared parameter, in order" {
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            $helpParams = [regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value }

            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declaredParams = $ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }

            $helpParams.Count | Should -Be $declaredParams.Count
            $helpParams | Should -Be $declaredParams
        }

        It "Provides at least two .EXAMPLE blocks with PS C:\> prompts" {
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero syntax errors" {
            $tokens = $null
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Uses no PS7-only operators unless #Requires -Version 7.0 is line 1" {
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            $firstLine = ($raw -split "\r?\n")[0]
            $allowsPs7OnlySyntax = $firstLine -match '#Requires\s+-Version\s+7'

            if (-not $allowsPs7OnlySyntax) {
                $badKinds = @('AndAnd', 'OrOr', 'QuestionMark', 'QuestionQuestion', 'QuestionQuestionEquals')
                $tokens = $null
                $parseErrors = $null
                $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
                $offenders = @($tokens | Where-Object { $badKinds -contains $_.Kind.ToString() })
                $offenders | Should -BeNullOrEmpty -Because "PS7-only operators require #Requires -Version 7.0"
                $raw | Should -Not -Match '\-Parallel'
            }
        }

        It "Is saved as UTF-8 with BOM and CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            $raw | Should -Not -Match "(?<!\r)\n"
        }

        It "Keeps every line at or below 120 columns without trailing whitespace" {
            $lines = [System.IO.File]::ReadAllLines($scriptPath)
            $tooLong = @($lines | Where-Object { $_.Length -gt 120 })
            $tooLong | Should -BeNullOrEmpty
            $trailing = @($lines | Where-Object { $_ -match '[ \t]+$' })
            $trailing | Should -BeNullOrEmpty
        }

        It "Contains exit only in the top-level dot-source guard line" {
            $lines = [System.IO.File]::ReadAllLines($scriptPath)
            $exitLines = @($lines | Where-Object { $_ -cmatch '(?<!\w)exit(?!\w)' })
            $exitLines.Count | Should -Be 1
            $exitLines[0] | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\)'
        }
    }

    Context "Behavior" {
        It "Returns 1 with [-] prefixed output when the MicrosoftTeams module is missing" {
            Mock Get-Module { $null }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 0 and reports the existing connection without reconnecting" {
            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[\+\] Connected to Microsoft Teams'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Connect-MicrosoftTeams -Times 0 -Exactly -Because "a session already exists"
        }

        It "Connects interactively when the connectivity probe fails and still returns 0" {
            Mock Get-CsOnlineUser { throw "No connection" }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[\+\] Connected to Microsoft Teams'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Connect-MicrosoftTeams -Times 1 -Exactly
        }

        It "Returns 1 when connecting fails" {
            Mock Get-CsOnlineUser { throw "No connection" }
            Mock Connect-MicrosoftTeams { throw "Interactive sign-in cancelled" }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Makes no configuration changes: no Teams policy cmdlets are invoked" {
            Mock Set-CsTeamsMeetingPolicy { }

            $out = Main *>&1

            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-CsTeamsMeetingPolicy -Times 0 -Exactly
        }
    }
}
