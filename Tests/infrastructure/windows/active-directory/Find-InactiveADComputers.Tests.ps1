#Requires -Modules Pester

Describe "Find-InactiveADComputers" {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot "../../../.."

        $scriptDir = Join-Path $repoRoot "scripts/infrastructure/windows/active-directory"

        $scriptPath = Join-Path $scriptDir "Find-InactiveADComputers.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Stub commands that cannot resolve without the ActiveDirectory module installed,
        # then mock them at command-name level.
        function Get-ADDomain { }
        function Get-ADComputer { }
        function Disable-ADAccount { }

        # Mock -CommandName ALL external commands/modules so nothing leaves the machine.
        Mock -CommandName Import-Module { }
        Mock -CommandName Get-ADDomain { [pscustomobject]@{ DNSRoot = 'contoso.com' } }
        Mock -CommandName Disable-ADAccount { }
        Mock -CommandName New-Item { }

        $mockComputer = [pscustomobject]@{
            Name = 'STALE-WS01'
            DNSHostName = 'stale-ws01.contoso.com'
            OperatingSystem = 'Windows 10 Pro'
            OperatingSystemVersion = '10.0 (19045)'
            LastLogonTimeStamp = (Get-Date).AddDays(-120).ToFileTime()
            PasswordLastSet = (Get-Date).AddDays(-120)
            Enabled = $true
            Description = 'Old workstation'
            Created = (Get-Date).AddDays(-400)
            Modified = (Get-Date).AddDays(-120)
            DistinguishedName = 'CN=STALE-WS01,OU=Workstations,DC=contoso,DC=com'
        }
    }

    Context "Help & Metadata" {
        It "Documents every declared parameter, in order" {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declared = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $content = Get-Content -Raw $scriptPath
            $documented = @([regex]::Matches($content, '(?m)^\s*\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value })
            $documented | Should -Be $declared
        }

        It "Has complete .NOTES metadata (File Name, Author, Prerequisite, Version 1.0.0, Date 2026-08-23)" {
            $content = Get-Content -Raw $scriptPath
            $content | Should -Match '\.SYNOPSIS'
            $content | Should -Match '\.DESCRIPTION'
            $content | Should -Match '\.NOTES'
            $content | Should -Match 'File Name\s*:\s*Find-InactiveADComputers\.ps1'
            $content | Should -Match 'Author\s*:\s*\S+'
            $content | Should -Match 'Prerequisite\s*:\s*PowerShell'
            $content | Should -Match 'Version\s*:\s*1\.0\.0'
            $content | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Has at least two examples using PS C:\> prompts" {
            $content = Get-Content -Raw $scriptPath
            $exampleCount = ([regex]::Matches($content, '(?m)^\.EXAMPLE')).Count
            $exampleCount | Should -BeGreaterOrEqual 2
            $promptCount = ([regex]::Matches($content, 'PS C:\\>')).Count
            $promptCount | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero syntax errors" {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only operators without a '#Requires -Version 7.0' opt-in" {
            $content = Get-Content -Raw $scriptPath
            if ($content -notmatch '(?m)^#Requires\s+-Version\s+7') {
                $code = [regex]::Replace($content, '(?ms)^\s*@".*?"@\s*$', '')
                $code = [regex]::Replace($code, "(?ms)^\s*@'.*?'@\s*$", '')
                $code | Should -Not -Match '&&|\|\||\?\?=|\?\?|-Parallel\b'
            }
        }
    }

    Context "Behavior" {
        It "Reports inactive computers and returns 0 on success" {
            Mock -CommandName Get-ADComputer { @($mockComputer) }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Get-ADComputer -Times 1 -Exactly
        }

        It "Returns 1 with [-] output when the ActiveDirectory module is unavailable" {
            Mock -CommandName Import-Module { throw 'ActiveDirectory module missing' }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Disables enabled inactive accounts exactly once when -DisableInactive is set" {
            Mock -CommandName Get-ADComputer { @($mockComputer) }
            $DisableInactive = $true
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Disable-ADAccount -Times 1 -Exactly
        }

        It "Is idempotent: a converged run makes no further changes" {
            Mock -CommandName Get-ADComputer { @() }
            $DisableInactive = $true
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Disable-ADAccount -Times 0 -Exactly -Because "nothing left to disable"
        }

        It "Returns 1 with [-] output when the AD search fails fatally" {
            Mock -CommandName Get-ADComputer { throw 'server unavailable' }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
