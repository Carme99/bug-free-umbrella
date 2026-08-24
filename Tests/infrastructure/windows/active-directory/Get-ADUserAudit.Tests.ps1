#Requires -Modules Pester

Describe "Get-ADUserAudit" {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot "../../../.."

        $scriptDir = Join-Path $repoRoot "scripts/infrastructure/windows/active-directory"

        $scriptPath = Join-Path $scriptDir "Get-ADUserAudit.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Stub commands that cannot resolve without the ActiveDirectory module installed,
        # then mock them at command-name level.
        function Get-ADDomain { }
        function Get-ADUser { }
        function Get-ADGroup { }
        function Get-ADGroupMember { }

        # Mock -CommandName ALL external commands/modules so nothing leaves the machine.
        Mock -CommandName Import-Module { }
        Mock -CommandName Get-ADDomain { [pscustomobject]@{ DNSRoot = 'contoso.com' } }

        $oldDate = (Get-Date).AddDays(-200)
        $recentDate = (Get-Date).AddDays(-5)

        $inactiveUser = [pscustomobject]@{
            ObjectClass = 'user'
            SamAccountName = 'a.stale'
            DisplayName = 'A Stale'
            LastLogonDate = $oldDate
            Enabled = $true
            Created = $oldDate
            Department = 'Sales'
            Title = 'Representative'
            PasswordNeverExpires = $false
            PasswordLastSet = $oldDate
            LockedOut = $false
            AccountLockoutTime = $null
            BadPwdCount = 0
            AccountExpirationDate = $null
            Modified = $oldDate
        }
        $freshUser = [pscustomobject]@{
            ObjectClass = 'user'
            SamAccountName = 'b.fresh'
            DisplayName = 'B Fresh'
            LastLogonDate = (Get-Date)
            Enabled = $true
            Created = $recentDate
            Department = 'IT'
            Title = 'Developer'
            PasswordNeverExpires = $true
            PasswordLastSet = $recentDate
            LockedOut = $false
            AccountLockoutTime = $null
            BadPwdCount = 0
            AccountExpirationDate = $null
            Modified = $recentDate
        }

        # Directory query (-Filter) returns the user set; identity lookup (privileged path) returns fresh user.
        Mock -CommandName Get-ADUser {
            if ($Filter) { @($inactiveUser, $freshUser) } else { $freshUser }
        }
        Mock -CommandName Get-ADGroup { [pscustomobject]@{ Name = 'Domain Admins' } }
        Mock -CommandName Get-ADGroupMember {
            @([pscustomobject]@{ objectClass = 'user'; SamAccountName = 'domadmin1' })
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

        It "Has complete .NOTES metadata with preserved author, Version 1.0.0, Date 2026-08-23" {
            $content = Get-Content -Raw $scriptPath
            $content | Should -Match '\.SYNOPSIS'
            $content | Should -Match '\.DESCRIPTION'
            $content | Should -Match '\.NOTES'
            $content | Should -Match 'File Name\s*:\s*Get-ADUserAudit\.ps1'
            $content | Should -Match 'Author\s*:\s*Server Management Team'
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
        It "Audits users, exports CSVs for non-empty categories, and returns 0 on success" {
            $OutputPath = Join-Path $TestDrive 'useraudit-out'
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            $ExportToCSV = $true
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            # InactiveAccounts + PasswordNeverExpires + RecentlyCreated are non-empty in mock data.
            @(Get-ChildItem -Path $OutputPath -Filter '*.csv').Count | Should -Be 3
            @(Get-ChildItem -Path $OutputPath -Filter '*.html').Count | Should -Be 1
        }

        It "Flags inactive and never-expiring accounts found in AD" {
            $OutputPath = Join-Path $TestDrive 'useraudit-flags'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match 'Inactive Accounts \(>90 days\): 1'
            $text | Should -Match 'Password Never Expires: 1'
        }

        It "Returns 1 with [-] output when the ActiveDirectory module is unavailable" {
            Mock -CommandName Import-Module { throw 'ActiveDirectory module missing' }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 with [-] output when the AD user query fails fatally" {
            Mock -CommandName Get-ADUser { throw 'domain unreachable' }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 for an unsafe OutputPath containing '..' traversal" {
            $OutputPath = '/tmp/reports/../..'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
