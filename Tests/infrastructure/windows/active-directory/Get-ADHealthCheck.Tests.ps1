#Requires -Modules Pester

Describe "Get-ADHealthCheck" {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot "../../../.."

        $scriptDir = Join-Path $repoRoot "scripts/infrastructure/windows/active-directory"

        $scriptPath = Join-Path $scriptDir "Get-ADHealthCheck.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Stub commands that cannot resolve without the ActiveDirectory module installed,
        # then mock them at command-name level.
        function Get-ADDomain { }
        function Get-ADForest { }
        function Get-ADDomainController { }
        function Get-ADReplicationPartnerMetadata { }
        function Get-Service { }
        function Get-WinEvent { }

        # Mock -CommandName ALL external commands/modules so nothing leaves the machine.
        Mock -CommandName Import-Module { }
        Mock -CommandName New-Item { }
        Mock -CommandName Get-ADDomain {
            [pscustomobject]@{
                DNSRoot = 'contoso.com'
                DomainMode = 'Windows2016Domain'
                PDCEmulator = 'dc01.contoso.com'
                RIDMaster = 'dc01.contoso.com'
                InfrastructureMaster = 'dc01.contoso.com'
            }
        }
        Mock -CommandName Get-ADForest {
            [pscustomobject]@{
                Name = 'contoso.com'
                ForestMode = 'Windows2016Forest'
                SchemaMaster = 'dc01.contoso.com'
                DomainNamingMaster = 'dc01.contoso.com'
            }
        }

        $mockDc = [pscustomobject]@{
            Name = 'DC01'
            HostName = 'dc01.contoso.com'
            Site = 'Default-First-Site-Name'
            IPv4Address = '10.0.0.11'
            OperatingSystem = 'Windows Server 2022 Datacenter'
            IsGlobalCatalog = $true
            IsReadOnly = $false
            Enabled = $true
        }
        Mock -CommandName Get-ADDomainController { @($mockDc) }
        Mock -CommandName Test-Connection { $true }
        Mock -CommandName Test-LDAPConnection { $true }   # thin ADSI wrapper is the mock seam
        Mock -CommandName Test-Path { $true }
        Mock -CommandName Get-Service { [pscustomobject]@{ Name = 'NTDS'; Status = 'Running' } }
        Mock -CommandName Invoke-Command { (Get-Date) }
        Mock -CommandName Get-WinEvent { @() }
        Mock -CommandName Get-ADReplicationPartnerMetadata { @() }
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
            $content | Should -Match 'File Name\s*:\s*Get-ADHealthCheck\.ps1'
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
        It "Runs a full health check and returns 0 on success" {
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Test-Connection -Times 1 -Exactly
            Should -Invoke Get-Service -Times 4 -Exactly -Because "four core services are checked per DC"
        }

        It "Returns 1 with [-] output when the ActiveDirectory module is unavailable" {
            Mock -CommandName Import-Module { throw 'ActiveDirectory module missing' }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Records a critical issue and stays exit-0 when a DC service is stopped" {
            Mock -CommandName Get-Service { [pscustomobject]@{ Name = 'kdc'; Status = 'Stopped' } }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $script:report.HealthStatus | Should -Be 'Critical'
            $issues = $script:report.Issues | Out-String
            $issues | Should -Match 'kdc service is Stopped'
        }

        It "Returns 0 but reports issues when SYSVOL is inaccessible" {
            Mock -CommandName Test-Path { $false }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $sysvolIssues = @($script:report.Issues | Where-Object { $_ -match 'SYSVOL not accessible' })
            $sysvolIssues.Count | Should -BeGreaterOrEqual 1
        }
    }
}
