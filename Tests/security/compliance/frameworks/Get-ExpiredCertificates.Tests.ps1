#Requires -Modules Pester

Describe "Get-ExpiredCertificates" {
    BeforeAll {
        $scriptName = "Get-ExpiredCertificates.ps1"
        $scriptPath = Join-Path $PSScriptRoot "../../../../scripts/security/compliance/frameworks/$scriptName"
        . $scriptPath

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        # Build an in-memory certificate stand-in; NotAfter drives all classification logic.
        function New-TestCert {
            param(
                [string]$Subject = 'CN=test.contoso.local',
                [int]$ExpiresInDays = 365,
                [switch]$SelfSigned
            )
            $issuer = if ($SelfSigned) { $Subject } else { 'CN=Contoso Issuing CA' }
            $notAfter = (Get-Date).AddDays($ExpiresInDays)
            [pscustomobject]@{
                Subject       = $Subject
                Issuer        = $issuer
                Thumbprint    = ([guid]::NewGuid().ToString('N').ToUpper())
                FriendlyName  = ''
                NotBefore     = $notAfter.AddYears(-1)
                NotAfter      = $notAfter
                HasPrivateKey = $false
            }
        }

        Mock Get-Item { [pscustomobject]@{ Name = 'store' } }
        # Script scans 6 stores per location (LocalMachine by default) -> 6 calls.
        Mock Get-ChildItem { @() }
    }

    Context "Help & Metadata" {
        It "Declares a File Name matching the disk filename" {
            $raw | Should -Match ([regex]::Escape("File Name   : $scriptName"))
        }

        It "Pins Version 1.0.0 and relaunch Date 2026-08-23" {
            $raw | Should -Match 'Version\s*:\s*1\.0\.0'
            $raw | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Documents every declared parameter in declaration order" {
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $documented = @([regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
            $documented | Should -Be $declared
        }

        It "Provides at least two EXAMPLES with PS C:\> prompts" {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE\s*$')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Avoids PS7-only operators (targets 5.1-compatible syntax)" {
            $offenders = @($raw -split "`n" | Where-Object { $_ -match '\?\?|\?\?=|&&|\|\|' })
            $offenders | Should -BeNullOrEmpty
        }

        It "Wraps execution in Main with a dot-source guard and exit only in the guard line" {
            $raw | Should -Match 'function Main \{'
            ($raw -split "`n" | Where-Object { $_ -match '(?m)^\s*exit\b' }).Count | Should -Be 1
        }
    }

    Context "Behavior" {
        It "Returns 1 and flags an expired certificate found in a scanned store" {
            Mock Get-ChildItem { @(New-TestCert -Subject 'CN=oldcert.contoso.local' -ExpiresInDays (-10)) }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match 'Expired'
        }

        It "Returns 0 when all certificates are valid and far from expiry" {
            Mock Get-ChildItem { @(New-TestCert -Subject 'CN=goodcert.contoso.local' -ExpiresInDays 400) }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match 'No expired or expiring certificates found'
            Should -Invoke Get-ChildItem -Exactly 6 -Scope It -Because "LocalMachine has 6 stores to scan"
        }

        It "Flags a self-signed certificate expiring soon as an issue" {
            Mock Get-ChildItem { @(New-TestCert -Subject 'CN=selfsigned.contoso.local' -ExpiresInDays 5 -SelfSigned) }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match 'Self-signed'
        }

        It "Is idempotent: repeated scans against unchanged stores return the same result" {
            Mock Get-ChildItem { @() }
            Main | Should -Be 0
            Main | Should -Be 0
        }
    }
}
