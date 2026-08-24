#Requires -Modules Pester

Describe "Get-LocalAdminAudit" {
    BeforeAll {
        $scriptName = "Get-LocalAdminAudit.ps1"
        $scriptPath = Join-Path $PSScriptRoot "../../../../scripts/security/compliance/frameworks/$scriptName"
        . $scriptPath

        # Microsoft.PowerShell.LocalAccounts cmdlets are absent on Linux; declare function
        # seams first so Pester has local commands to mock. SecurityIdentifier construction
        # is also unsupported on Linux, so SIDs are plain Value-bearing stand-ins.
        function Get-LocalGroup { $null }
        function Get-LocalGroupMember { $null }
        function Get-LocalUser { $null }

        function New-TestGroupMember {
            param(
                [string]$Name = 'DESKTOP-01\admin_user',
                [string]$Sid = 'S-1-5-21-1004336348-1177238915-682003330-1120',
                [string]$ObjectClass = 'User',
                [string]$PrincipalSource = 'Local'
            )
            [pscustomobject]@{
                Name            = $Name
                SID             = [pscustomobject]@{ Value = $Sid }
                ObjectClass     = $ObjectClass
                PrincipalSource = $PrincipalSource
            }
        }

        Mock Get-LocalGroup { [pscustomobject]@{ Name = 'Administrators' } }
        Mock Get-LocalGroupMember { @() }
        # Default local user: enabled, recently used, password expires -> low risk.
        Mock Get-LocalUser {
            [pscustomobject]@{
                Enabled              = $true
                PasswordNeverExpires = $false
                LastLogon            = (Get-Date).AddHours(-2)
                PasswordLastSet      = (Get-Date).AddDays(-30)
            }
        }

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
        $raw = Get-Content -LiteralPath $scriptPath -Raw
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

        It "Contains no RunAsAdministrator requirement that would break dot-sourcing offline" {
            $raw | Should -Not -Match '#Requires\s+-RunAsAdministrator'
        }
    }

    Context "Behavior" {
        It "Returns 0 for a healthy local administrator account" {
            Mock Get-LocalGroupMember { @(New-TestGroupMember) }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Get-LocalGroupMember -Exactly 1
            Should -Invoke Get-LocalUser -Exactly 1
        }

        It "Returns 1 for an enabled built-in Administrator account that was never used" {
            Mock Get-LocalGroupMember {
                @(
                    New-TestGroupMember `
                        -Sid 'S-1-5-21-1004336348-1177238915-682003330-500' `
                        -Name 'DESKTOP-01\Administrator'
                )
            }
            Mock Get-LocalUser {
                [pscustomobject]@{
                    Enabled              = $true
                    PasswordNeverExpires = $false
                    LastLogon            = $null
                    PasswordLastSet      = (Get-Date).AddDays(-90)
                }
            }

            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match 'Built-in Administrator'
        }

        It "Classifies a domain-group member without querying local users" {
            Mock Get-LocalGroupMember {
                @(
                    New-TestGroupMember -Name 'CONTOSO\Domain Admins' -ObjectClass 'Group' `
                        -PrincipalSource 'ActiveDirectory'
                )
            }

            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match 'Domain Account'
            Should -Invoke Get-LocalUser -Times 0
        }

        It "Returns 1 and writes [-] output when the Administrators group cannot be read" {
            Mock Get-LocalGroup { throw 'The group name could not be found.' }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Out-String) | Should -Match 'Failed to retrieve Administrators group'
        }
    }
}
