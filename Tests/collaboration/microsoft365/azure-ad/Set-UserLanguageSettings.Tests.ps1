#Requires -Modules Pester

Describe "Set-UserLanguageSettings" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/collaboration/microsoft365/azure-ad/ -> repo root is four levels up.
        $scriptPath = Join-Path $PSScriptRoot (
            "../../../../scripts/collaboration/microsoft365/azure-ad/Set-UserLanguageSettings.ps1")

        # Safe: the script's top-level guard skips Main when dot-sourced (#Requires 7.0 satisfied by pwsh CI).
        . $scriptPath

# Function shims: Pester cannot mock commands absent from Linux pwsh, and mock parameter
        # filters are resolved against the shim's signature - so declare the parameters the script uses.
        function Connect-MgGraph { param([array]$Scopes, [switch]$NoWelcome) }
        function Get-MgContext { }
        function Get-MgUser { param([string]$Filter, [switch]$All, [array]$Property, [string]$UserId) }
        function Get-MgUserMailboxSetting { param([string]$UserId) }
        function Update-MgUserMailboxSetting { param([string]$UserId, [hashtable]$BodyParameter) }
        function Update-MgUser { param([string]$UserId, [string]$PreferredLanguage) }

        # Fixture scriptblock variables: Pester mock bodies can read BeforeAll variables but
        # cannot resolve BeforeAll functions.
        $NewTestUser = {
            param([string]$Id = 'u1', [string]$Name = 'Jane Doe', [string]$Upn = 'jane@contoso.com')
            return [pscustomobject]@{
                Id = $Id
                DisplayName = $Name
                UserPrincipalName = $Upn
                Mail = $Upn
            }
        }

        $NewMailboxSettings = {
            param([string]$Locale = 'en-GB', [string]$TimeZoneValue = 'GMT Standard Time')
            return [pscustomobject]@{
                Language = [pscustomobject]@{ Locale = $Locale; DisplayName = 'English (United Kingdom)' }
                TimeZone = $TimeZoneValue
            }
        }

        $compliantMailbox = & $NewMailboxSettings -Locale 'en-GB'
        $nonCompliantMailbox = & $NewMailboxSettings -Locale 'en-US'

        # Mock ALL external commands so nothing leaves the machine (offline Linux pwsh).
        Mock Get-Module { $true } -ParameterFilter { $Name -like '*Microsoft.Graph*' }
        Mock Import-Module { }
        Mock Connect-MgGraph
        Mock Get-MgContext {
            [pscustomobject]@{ Account = 'admin@contoso.com'; Scopes = @('User.ReadWrite.All') }
        }
        Mock Get-MgUser { @(& $NewTestUser) } -ParameterFilter {
            $UserId -eq 'jane@contoso.com' -and $Property -contains 'PreferredLanguage'
        }
        Mock Get-MgUser { @(& $NewTestUser) } -ParameterFilter {
            $UserId -eq 'admin@contoso.com' -and $Property -contains 'PreferredLanguage'
        }
        Mock Get-MgUser { @() } -ParameterFilter { $All -eq $true }
        Mock Get-MgUser { @(& $NewTestUser) } -ParameterFilter {
            $UserId -and $Property -notcontains 'PreferredLanguage'
        }
        Mock Get-MgUserMailboxSetting { $compliantMailbox } -ParameterFilter { $UserId -eq 'u1' }
        Mock Update-MgUserMailboxSetting { }
        Mock Update-MgUser { }
    }

    Context "Help & Metadata" {
        It "Declares all required header fields with relaunch values" {
            $content = Get-Content -Path $scriptPath -Raw
            $content | Should -Match '\.SYNOPSIS'
            $content | Should -Match '\.DESCRIPTION'
            $content | Should -Match '\.NOTES'
            $content | Should -Match 'Version\s*:\s*1\.0\.0'
            $content | Should -Match 'Date\s*:\s*2026-08-23'
            $content | Should -Match 'File Name\s*:\s*Set-UserLanguageSettings\.ps1'
            $content | Should -Match 'Author\s*:\s*\S+'
            $content | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
        }

        It "Starts with #Requires -Version 7.0 on line 1 (ForEach-Object -Parallel opt-out)" {
            $lines = Get-Content -Path $scriptPath
            $lines[0] | Should -Match '^#Requires\s+-Version\s+7\.0'
        }

        It "Has a SYNOPSIS that is imperative and <= 120 characters" {
            $lines = Get-Content -Path $scriptPath
            $idx = [array]::IndexOf(($lines | ForEach-Object { $_.Trim() }), '.SYNOPSIS')
            $synopsis = ($lines[$idx + 1]).Trim()
            $synopsis | Should -Not -BeNullOrEmpty
            $synopsis.Length | Should -BeLessOrEqual 120
        }

        It "Has one .PARAMETER entry per declared script parameter, in order" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $paramNames = $ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }

            $lines = Get-Content -Path $scriptPath
            $helpParamNames = @()
            foreach ($line in $lines) {
                if ($line -match '^\.PARAMETER\s+(\S+)') { $helpParamNames += $Matches[1] }
            }

            $helpParamNames.Count | Should -Be $paramNames.Count
            for ($i = 0; $i -lt $paramNames.Count; $i++) {
                $helpParamNames[$i] | Should -Be $paramNames[$i]
            }
        }

        It "Provides at least two examples showing PS C:\> prompts" {
            $content = Get-Content -Path $scriptPath -Raw
            ($content -split '\.EXAMPLE').Count -ge 3 | Should -BeTrue
            ([regex]::Matches($content, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }

        It "Renders complete help via Get-Help -Detailed" {
            { Get-Help -Path $scriptPath -Detailed -ErrorAction Stop } | Should -Not -Throw
            (Get-Help -Path $scriptPath -ErrorAction Stop).Synopsis | Should -Not -BeNullOrEmpty
        }

        It "Declares SupportsShouldProcess for mutation support" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $cmdletBinding = $ast.ParamBlock.Attributes |
                Where-Object { $_.TypeName.FullName -eq 'CmdletBinding' }
            $cmdletBinding | Should -Not -BeNullOrEmpty
            ($cmdletBinding.NamedArguments | Where-Object { $_.ArgumentName -eq 'SupportsShouldProcess' }) |
                Should -Not -BeNullOrEmpty
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null; $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors | Should -HaveCount 0
        }

        It "Is UTF-8 with BOM and CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
            $raw = [System.Text.Encoding]::UTF8.GetString($bytes)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }
    }

    Context "Behavior" {
        It "Returns 0 in audit mode when the current user is compliant" {
            Mock Get-MgUserMailboxSetting { $compliantMailbox } -ParameterFilter { $UserId -eq 'u1' }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Connected to Microsoft Graph'
            Should -Invoke Update-MgUserMailboxSetting -Times 0 -Exactly
            Should -Invoke Update-MgUser -Times 0 -Exactly
        }

        It "Returns the documented exit code 1 in audit mode when the user is non-compliant" {
            Mock Get-MgUserMailboxSetting { $nonCompliantMailbox } -ParameterFilter { $UserId -eq 'u1' }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match 'Non-Compliant'
        }

        It "Remediates a non-compliant user with -Apply and returns 0" {
            Mock Get-MgUserMailboxSetting { $nonCompliantMailbox } -ParameterFilter { $UserId -eq 'u1' }

            $out = Main -Apply *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match 'Remediated: 1'
            Should -Invoke Update-MgUserMailboxSetting -Times 1 -Exactly -ParameterFilter {
                $UserId -eq 'u1' -and $BodyParameter.TimeZone -eq 'GMT Standard Time'
            }
            Should -Invoke Update-MgUser -Times 1 -Exactly -ParameterFilter {
                $UserId -eq 'u1' -and $PreferredLanguage -eq 'en-GB'
            }
        }

        It "Is idempotent: -Apply on a converged tenant makes no changes and returns 0" {
            Mock Get-MgUserMailboxSetting { $compliantMailbox } -ParameterFilter { $UserId -eq 'u1' }

            $out = Main -Apply *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Update-MgUserMailboxSetting -Times 0 -Exactly
            Should -Invoke Update-MgUser -Times 0 -Exactly
        }

        It "Honors -WhatIf: no settings are written even when non-compliant" {
            Mock Get-MgUserMailboxSetting { $nonCompliantMailbox } -ParameterFilter { $UserId -eq 'u1' }

            $out = Main -Apply -WhatIf *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Update-MgUserMailboxSetting -Times 0 -Exactly
            Should -Invoke Update-MgUser -Times 0 -Exactly
        }

        It "Audits all users with -AllUsers and reports mixed compliance" {
            Mock Get-MgUser {
                @(
                    (& $NewTestUser -Id 'u1' -Name 'Compliant Carl'),
                    (& $NewTestUser -Id 'u2' -Name 'Drifting Dana')
                )
            } -ParameterFilter { $All -eq $true }
            Mock Get-MgUserMailboxSetting { $compliantMailbox } -ParameterFilter { $UserId -eq 'u1' }
            Mock Get-MgUserMailboxSetting { $nonCompliantMailbox } -ParameterFilter { $UserId -eq 'u2' }

            $out = Main -AllUsers *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            $text = $out | Out-String
            $text | Should -Match 'Total Users Processed: 2'
            $text | Should -Match 'Non-Compliant: 1'
        }

        It "Targets a specific user by UPN with -UserPrincipalName" {
            Mock Get-MgUser { @(& $NewTestUser -Id 'u9' -Name 'Paul Upn' -Upn 'paul@contoso.com') } `
                -ParameterFilter { $UserId -eq 'paul@contoso.com' }
            Mock Get-MgUserMailboxSetting { $nonCompliantMailbox } -ParameterFilter { $UserId -eq 'u9' }
            Mock Get-MgUser { @(& $NewTestUser -Id 'u9') } -ParameterFilter { $UserId -eq 'u9' }

            $out = Main -UserPrincipalName 'paul@contoso.com' *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match 'Found user: Paul Upn'
            Should -Invoke Update-MgUserMailboxSetting -Times 0 -Exactly
        }

        It "Returns 1 when the Microsoft Graph Users module is missing" {
            Mock Get-Module { $null } -ParameterFilter { $Name -like '*Microsoft.Graph*' }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 and writes [-] prefixed output when the Graph connection fails" {
            Mock Get-MgContext { $null }
            Mock Connect-MgGraph { throw "sign-in cancelled" }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
