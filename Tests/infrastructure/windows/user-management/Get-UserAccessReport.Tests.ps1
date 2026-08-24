#Requires -Modules Pester

Describe "Get-UserAccessReport" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/infrastructure/windows/user-management/Get-UserAccessReport.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Windows-only cmdlets are absent on Linux CI - define no-op stubs
        # so Pester has an existing command to attach each Mock to.
        foreach ($cmd in @('Get-ADDomain', 'Get-ADUser', 'Get-ADPrincipalGroupMembership')) {
            if (-not (Get-Command -Name $cmd -ErrorAction SilentlyContinue)) {
                . ([scriptblock]::Create("function script:$cmd { }"))
            }
        }

        # Report files are written for real under Pester's TestDrive sandbox
        # (mocking Out-File breaks on its typed -Encoding parameter).
        Mock -CommandName Write-Progress { }
        Mock -CommandName Get-ADDomain { [pscustomobject]@{ DNSRoot = "contoso.com" } }
        Mock -CommandName Get-ADPrincipalGroupMembership {
            @(
                [pscustomobject]@{ Name = "Domain Users" },
                [pscustomobject]@{ Name = "Domain Admins" }
            )
        }

        function New-FakeAdUser([string]$Name) {
            return [pscustomobject]@{
                SamAccountName = $Name
                DisplayName = $Name
                EmailAddress = "$Name@contoso.com"
                Department = "IT"
                Title = "Engineer"
                Enabled = $true
                Created = (Get-Date).AddYears(-1)
                LastLogonDate = (Get-Date).AddDays(-2)
            }
        }
    }

    Context "Help & Metadata" {
        It "Declares the required header fields with relaunch values" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            $text | Should -Match '\.SYNOPSIS'
            $text | Should -Match '\.DESCRIPTION'
            $text | Should -Match 'File Name:\s*Get-UserAccessReport\.ps1'
            $text | Should -Match 'Version:\s*1\.0\.0'
            $text | Should -Match 'Date:\s*2026-08-23'
            $text | Should -Match 'Prerequisite:\s*PowerShell'
            $text | Should -Match 'Author:\s*Server Management Team'
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
        It "Audits all users, writes the HTML report, and returns 0" {
            Mock -CommandName Get-ADUser {
                param($Filter, $Properties)
                @(New-FakeAdUser "jdoe")
            }
            $outDir = Join-Path $TestDrive "reports"
            $out = Main -OutputPath $outDir *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'HTML report saved to:'
            @(Get-ChildItem $outDir -Filter '*.html').Count | Should -Be 1
            @(Get-ChildItem $outDir -Filter '*.csv').Count | Should -Be 0 -Because "-ExportToCSV was not supplied"
        }

        It "Exports CSV when -ExportToCSV is supplied" {
            Mock -CommandName Get-ADUser {
                param($Filter, $Properties)
                @(New-FakeAdUser "jdoe")
            }
            $outDir = Join-Path $TestDrive "csv"
            $out = Main -OutputPath $outDir -ExportToCSV *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            @(Get-ChildItem $outDir -Filter '*.csv').Count | Should -Be 1
        }

        It "Returns 1 with [-] output when Active Directory queries fail" {
            Mock -CommandName Get-ADDomain { throw "Server unavailable" }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
