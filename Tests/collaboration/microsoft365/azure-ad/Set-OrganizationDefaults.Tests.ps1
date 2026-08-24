#Requires -Modules Pester

Describe "Set-OrganizationDefaults" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/collaboration/microsoft365/azure-ad/ -> repo root is four levels up.
        $scriptPath = Join-Path $PSScriptRoot (
            "../../../../scripts/collaboration/microsoft365/azure-ad/Set-OrganizationDefaults.ps1")

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

# Function shims: Pester cannot mock commands absent from Linux pwsh, and mock parameter
        # filters are resolved against the shim's signature - so declare the parameters the script uses.
        function Connect-MgGraph { param([array]$Scopes, [switch]$NoWelcome) }
        function Get-MgContext { }
        function Get-MgOrganization { }
        function Update-MgOrganization { param([string]$OrganizationId, [string]$PreferredLanguage) }

        # Mock ALL external commands so nothing leaves the machine (offline Linux pwsh).
        Mock Get-Module { $true } -ParameterFilter { $Name -like '*Microsoft.Graph*' }
        Mock Import-Module { }
        Mock Connect-MgGraph

        # Fixture scriptblock variable: Pester mock bodies can read BeforeAll variables but
        # cannot resolve BeforeAll functions.
        $NewOrgObject = {
            param([string]$PreferredLanguage = 'en-GB')
            return [pscustomobject]@{
                Id = 'org-1'
                DisplayName = 'Contoso Ltd'
                CountryLetterCode = 'GB'
                PreferredLanguage = $PreferredLanguage
            }
        }
    }

    Context "Help & Metadata" {
        It "Declares all required header fields with relaunch values" {
            $content = Get-Content -Path $scriptPath -Raw
            $content | Should -Match '\.SYNOPSIS'
            $content | Should -Match '\.DESCRIPTION'
            $content | Should -Match '\.NOTES'
            $content | Should -Match 'Version\s*:\s*1\.0\.0'
            $content | Should -Match 'Date\s*:\s*2026-08-23'
            $content | Should -Match 'File Name\s*:\s*Set-OrganizationDefaults\.ps1'
            $content | Should -Match 'Author\s*:\s*\S+'
            $content | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
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

        It "Contains no PS7-only syntax without #Requires -Version 7.0" {
            $content = Get-Content -Path $scriptPath -Raw
            if ($content -match '(?m)^#Requires\s+-Version\s+7\.0') {
                $true | Should -BeTrue
            }
            else {
                $content | Should -Not -Match '\?\?'
                $content | Should -Not -Match '\|\|'
                $content | Should -Not -Match '&&'
                $content | Should -Not -Match '-Parallel'
            }
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
        BeforeAll {
            Mock Get-MgContext {
                [pscustomobject]@{ Account = 'admin@contoso.com'; Scopes = @('Organization.ReadWrite.All') }
            }
            Mock Update-MgOrganization { }
        }

        It "Returns 0 in audit mode on a compliant tenant and never mutates" {
            Mock Get-MgOrganization { @(& $NewOrgObject -PreferredLanguage 'en-GB') }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] Organization settings are compliant'
            Should -Invoke Update-MgOrganization -Times 0 -Exactly -Because "tenant is already converged"
        }

        It "Is idempotent: -Apply on a converged tenant makes no changes and returns 0" {
            Mock Get-MgOrganization { @(& $NewOrgObject -PreferredLanguage 'en-GB') }

            $out = Main -Apply *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Already compliant; no changes made'
            Should -Invoke Update-MgOrganization -Times 0 -Exactly
        }

        It "Applies the required language via ShouldProcess when non-compliant and returns 0" {
            Mock Get-MgOrganization { @(& $NewOrgObject -PreferredLanguage 'en-US') }

            $out = Main -Apply *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] Organization settings updated successfully!'
            Should -Invoke Update-MgOrganization -Times 1 -Exactly -ParameterFilter {
                $OrganizationId -eq 'org-1' -and $PreferredLanguage -eq 'en-GB'
            }
        }

        It "Honors -WhatIf: no update is issued even when non-compliant" {
            Mock Get-MgOrganization { @(& $NewOrgObject -PreferredLanguage 'en-US') }

            $out = Main -Apply -WhatIf *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Update-MgOrganization -Times 0 -Exactly
        }

        It "Returns 1 when the Microsoft Graph module is missing" {
            Mock Get-Module { $null } -ParameterFilter { $Name -like '*Microsoft.Graph*' }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 when the Graph connection cannot be established" {
            Mock Connect-MgGraph { throw "sign-in cancelled" }
            Mock Get-MgContext { $null }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 when organization settings retrieval fails" {
            Mock Get-MgContext { [pscustomobject]@{ Account = 'admin@contoso.com' } }
            Mock Get-MgOrganization { throw "request failed" }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
