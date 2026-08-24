#Requires -Modules Pester

Describe "Get-ServiceAccountAudit" {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot "../../../.."

        $scriptDir = Join-Path $repoRoot "scripts/infrastructure/windows/active-directory"

        $scriptPath = Join-Path $scriptDir "Get-ServiceAccountAudit.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Stub commands that cannot resolve without the ActiveDirectory module installed,
        # then mock them at command-name level.
        function Get-ADDomain { }
        function Get-ADUser { }
        function Get-ADPrincipalGroupMembership { }
        function Get-ADServiceAccount { }

        # Mock -CommandName ALL external commands/modules so nothing leaves the machine.
        Mock -CommandName Import-Module { }
        Mock -CommandName Get-ADDomain { [pscustomobject]@{ DNSRoot = 'contoso.com' } }

        $svcAccount = [pscustomobject]@{
            SamAccountName = 'svc_sql'
            Name = 'svc_sql'
            DisplayName = 'SQL Service'
            Description = 'SQL service account'
            Enabled = $true
            Created = (Get-Date).AddDays(-800)
            LastLogonDate = $null
            PasswordNeverExpires = $true
            PasswordNotRequired = $false
            PasswordLastSet = (Get-Date).AddDays(-500)
            ServicePrincipalNames = @('MSSQLSvc/sql01.contoso.com:1433')
            TrustedForDelegation = $true
            TrustedToAuthForDelegation = $false
        }

        Mock -CommandName Get-ADUser { @($svcAccount) }
        Mock -CommandName Get-ADPrincipalGroupMembership {
            @([pscustomobject]@{ Name = 'Domain Admins' }, [pscustomobject]@{ Name = 'Domain Users' })
        }
        Mock -CommandName Get-ADServiceAccount { @() }
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
            $content | Should -Match 'File Name\s*:\s*Get-ServiceAccountAudit\.ps1'
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
        It "Audits the service account, checks its group memberships, and returns 0" {
            $OutputPath = Join-Path $TestDrive 'svcaudit-basic'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Get-ADPrincipalGroupMembership -Times 1 -Exactly
        }

        It "Flags privileged membership and security issues for svc accounts" {
            $OutputPath = Join-Path $TestDrive 'svcaudit-flags'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match 'Privileged Service Accounts: 1'
            $text | Should -Match 'Accounts with Security Issues: 1'
        }

        It "Reports Kerberos delegation when -CheckKerberosDelegation is set" {
            $OutputPath = Join-Path $TestDrive 'svcaudit-delegation'
            $CheckKerberosDelegation = $true
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'delegation enabled'
        }

        It "Exports one CSV per non-empty category when -ExportToCSV is set" {
            $OutputPath = Join-Path $TestDrive 'svcaudit-csv'
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            $ExportToCSV = $true
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            # StandardServiceAccounts + AccountsWithSPNs + PrivilegedServiceAccounts + SecurityIssues
            @(Get-ChildItem -Path $OutputPath -Filter '*.csv').Count | Should -Be 4
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
    }
}
