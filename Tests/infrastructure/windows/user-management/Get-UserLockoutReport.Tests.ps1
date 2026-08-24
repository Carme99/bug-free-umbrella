#Requires -Modules Pester

Describe "Get-UserLockoutReport" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/infrastructure/windows/user-management/Get-UserLockoutReport.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Windows-only cmdlets are absent on Linux CI - define no-op stubs
        # so Pester has an existing command to attach each Mock to.
        foreach ($cmd in @('Get-ADDomainController', 'Get-WinEvent')) {
            if (-not (Get-Command -Name $cmd -ErrorAction SilentlyContinue)) {
                . ([scriptblock]::Create("function script:$cmd { }"))
            }
        }

        # Mock platform/external seams so nothing leaves the machine.
        Mock -CommandName Test-Path { $true }
        Mock -CommandName New-Item { }
        Mock -CommandName Out-File { }
        Mock -CommandName Export-Csv { }
        Mock -CommandName Get-ADDomainController {
            @([pscustomobject]@{ HostName = "DC01.contoso.com" })
        }

        class FakeSecurityEvent {
            [int]$Id
            [datetime]$TimeCreated
            hidden [string]$XmlPayload

            FakeSecurityEvent([int]$id, [datetime]$time, [string]$xml) {
                $this.Id = $id
                $this.TimeCreated = $time
                $this.XmlPayload = $xml
            }

            [string] ToXml() {
                return $this.XmlPayload
            }
        }
    }

    Context "Help & Metadata" {
        It "Declares the required header fields with relaunch values" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            $text | Should -Match '\.SYNOPSIS'
            $text | Should -Match '\.DESCRIPTION'
            $text | Should -Match 'File Name:\s*Get-UserLockoutReport\.ps1'
            $text | Should -Match 'Version:\s*1\.0\.0'
            $text | Should -Match 'Date:\s*2026-08-23'
            $text | Should -Match 'Prerequisite:\s*PowerShell'
            $text | Should -Match 'Author:\s*\S'
        }

        It "Documents exactly the declared parameters in order" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            $helpParams = [regex]::Matches($text, '(?m)^\.PARAMETER\s+(\w+)') | ForEach-Object { $_.Groups[1].Value }
            $tokens = $null; $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declared = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
            $helpParams | Should -Be $declared
        }

        It "Provides at least two examples with PS C:\> prompts" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            ([regex]::Matches($text, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($text, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses cleanly" {
            $tokens = $null; $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only syntax without #Requires -Version 7.0" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            if ($text -notmatch '(?m)^#Requires\s+-Version\s+7') {
                $text | Should -Not -Match '\?\?'
                $text | Should -Not -Match '\|\|'
                $text | Should -Not -Match '&&'
                $text | Should -Not -Match '-Parallel'
            }
        }

        It "Uses no tabs, max 120 columns and no trailing whitespace" {
            $lines = Get-Content -LiteralPath $scriptPath
            $bad = @($lines | Where-Object { $_ -match '`t' -or $_ -match '\s$' -or $_.Length -gt 120 })
            $bad | Should -BeNullOrEmpty
        }
    }

    Context "Behavior" {
        It "Returns 0 when no lockout events exist on the domain controllers" {
            Mock -CommandName Get-WinEvent { $null }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Total Lockouts: 0'
        }

        It "Returns the documented code 1 when a lockout event is found and parsed" {
            $lockoutXml = @'
<Event>
  <EventData>
    <Data Name="TargetUserName">jdoe</Data>
    <Data Name="TargetDomainName">CONTOSO</Data>
    <Data Name="Caller Computer Name">WS01.contoso.com</Data>
  </EventData>
</Event>
'@
            Mock -CommandName Get-WinEvent {
                @([FakeSecurityEvent]::new(4740, (Get-Date).AddMinutes(-30), $lockoutXml))
            }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match 'Total Lockouts: 1'
        }

        It "Returns 1 with [-] output when domain controller enumeration fails" {
            Mock -CommandName Get-ADDomainController { throw "Domain not available" }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
