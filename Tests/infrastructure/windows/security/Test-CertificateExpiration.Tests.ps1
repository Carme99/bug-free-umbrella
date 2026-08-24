#Requires -Modules Pester

Describe "Test-CertificateExpiration" {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../../../..')
        $scriptPath = Join-Path $repoRoot 'scripts/infrastructure/windows/security/Test-CertificateExpiration.ps1'
        . $scriptPath
        $helpText = Get-Content -Raw $scriptPath
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)

        function New-MockCertificate {
            param([int]$ExpiresInDays = 90)
            [PSCustomObject]@{
                Subject = 'CN=test.local'
                Issuer = 'CN=Test CA'
                FriendlyName = 'Test Cert'
                Thumbprint = 'ABCD1234'
                NotBefore = (Get-Date).AddDays(-365)
                NotAfter = (Get-Date).AddDays($ExpiresInDays)
                DnsNameList = @()
                SerialNumber = 'SER1'
                HasPrivateKey = $true
            }
        }

        Mock -CommandName Test-Path { $true }
        Mock -CommandName Get-ChildItem { @(New-MockCertificate -ExpiresInDays 90) }
        Mock -CommandName Out-File { }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date" {
            $helpText | Should -Match 'Version\s*:\s*1\.0\.0'
            $helpText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Declares matching File Name, Author and Prerequisite" {
            $helpText | Should -Match ('File Name\s*:\s*' + [regex]::Escape('Test-CertificateExpiration.ps1'))
            $helpText | Should -Match 'Author\s*:\s*\S+'
            $helpText | Should -Match 'Prerequisite\s*:\s*PowerShell'
        }

        It "Has one .PARAMETER entry per declared parameter, in order" {
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $documented = @([regex]::Matches($helpText, '(?m)^\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value })
            $documented | Should -Be $declared
        }

        It "Has SYNOPSIS, DESCRIPTION and at least two PS C:\> examples" {
            $helpText | Should -Match '(?m)^\.SYNOPSIS'
            $helpText | Should -Match '(?m)^\.DESCRIPTION'
            ([regex]::Matches($helpText, '(?m)^    PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It "Contains no PS7-only syntax without a #Requires -Version 7.0 opt-in" {
            if ($helpText -notmatch '(?m)^#Requires\s+-Version\s+7') {
                $helpText | Should -Not -Match '(\?\?=)|(\?\?)|&&|(\|\|)'
            }
        }
    }

    Context "Behavior" {
        It "Returns 0 with [+] output for healthy certificates" {
            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            $text | Should -Match '\[\+\] Healthy: 3'
            $text | Should -Match '\[HEALTHY\]'
            $text | Should -Match '\[\+\] Certificate expiration check completed'
        }

        It "Flags soon-expiring certificates as critical with [!] summary output" {
            # inside CriticalDays default of 7
            Mock -CommandName Get-ChildItem { @(New-MockCertificate -ExpiresInDays 3) }

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            $text | Should -Match '\[CRITICAL\]'
            $text | Should -Match '\[!\] Critical \(expires in 7 days\): 3'
        }

        It "Is idempotent: repeated read-only scans succeed identically" {
            (Main) | Should -Be 0
            (Main) | Should -Be 0
        }

        It "Returns 1 with [-] output when the report directory cannot be validated" {
            Mock -CommandName Test-Path { throw "access denied" } `
                -ParameterFilter { $LiteralPath -and $LiteralPath -like '*Reports*' }

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 1
            $text | Should -Match '\[-\] Error'
        }
    }
}
