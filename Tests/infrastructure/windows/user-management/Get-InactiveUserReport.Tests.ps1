#Requires -Modules Pester

Describe "Get-InactiveUserReport" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/infrastructure/windows/user-management/Get-InactiveUserReport.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Windows-only cmdlets are absent on Linux CI - define no-op stubs
        # so Pester has an existing command to attach each Mock to.
        foreach ($cmd in @('Get-ADUser', 'Get-ADGroup')) {
            if (-not (Get-Command -Name $cmd -ErrorAction SilentlyContinue)) {
                . ([scriptblock]::Create("function script:$cmd { }"))
            }
        }

        # Mock platform/external seams so nothing leaves the machine.
        Mock -CommandName Test-Path { $true }
        Mock -CommandName New-Item { }
        Mock -CommandName Out-File { }
        Mock -CommandName Export-Csv { }
        Mock -CommandName Get-ADGroup {
            param($Identity, $Properties)
            [pscustomobject]@{
                Name = "Administrators"
                SID = [pscustomobject]@{ Value = "S-1-5-32-544" }
            }
        }

        function New-FakeUser([string]$Name, [bool]$Enabled, $LastLogon, $MemberOf) {
            return [pscustomobject]@{
                SamAccountName = $Name
                Name = $Name
                Enabled = $Enabled
                LastLogonDate = $LastLogon
                PasswordLastSet = (Get-Date).AddDays(-30)
                Created = (Get-Date).AddYears(-2)
                MemberOf = $MemberOf
                Description = ""
                DistinguishedName = "CN=$Name,DC=contoso,DC=com"
            }
        }
    }

    Context "Help & Metadata" {
        It "Declares the required header fields with relaunch values" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            $text | Should -Match '\.SYNOPSIS'
            $text | Should -Match '\.DESCRIPTION'
            $text | Should -Match 'File Name:\s*Get-InactiveUserReport\.ps1'
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
        It "Returns 0 when no privileged accounts are inactive" {
            $u1 = New-FakeUser "stale.user" $true ((Get-Date).AddDays(-200)) $null
            $u2 = New-FakeUser "active.user" $true ((Get-Date).AddDays(-1)) $null
            Mock -CommandName Get-ADUser { @($u1, $u2) }

            $out = Main -DaysInactive 90 *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] Report completed'
        }

        It "Returns the documented code 1 when a privileged account is inactive" {
            Mock -CommandName Get-ADUser {
                @(
                    New-FakeUser "old.admin" $true ((Get-Date).AddDays(-400)) @("CN=Administrators,DC=contoso,DC=com")
                )
            }

            $out = Main -DaysInactive 90 *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match 'Privileged Accounts: 1'
            Should -Invoke Get-ADGroup -Times 1 -Exactly
        }

        It "Returns 1 with [-] output when Active Directory queries fail" {
            Mock -CommandName Get-ADUser { throw "Server unavailable" }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
