#Requires -Modules Pester

Describe "Get-AzureADGuestAudit" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/collaboration/microsoft365/azure-ad/ -> repo root is four levels up.
        $scriptPath = Join-Path $PSScriptRoot (
            "../../../../scripts/collaboration/microsoft365/azure-ad/Get-AzureADGuestAudit.ps1")

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

# Function shims: Pester cannot mock commands absent from Linux pwsh, and mock parameter
        # filters are resolved against the shim's signature - so declare the parameters the script uses.
        function Connect-MgGraph { param([array]$Scopes, [switch]$NoWelcome) }
        function Disconnect-MgGraph { }
        function Get-MgUser { param([string]$Filter, [switch]$All, [array]$Property, [string]$UserId) }
        function Get-MgRoleManagementDirectoryRoleAssignment { param([string]$Filter, [switch]$All) }
        function Get-MgRoleManagementDirectoryRoleDefinition { param([string]$UnifiedRoleDefinitionId) }

        # Fixture scriptblock variables: Pester mock bodies can read BeforeAll variables but
        # cannot resolve BeforeAll functions.
        $NewGuestUser = {
            param(
                [string]$Name = 'Guest User',
                [string]$Upn = 'guest_example.com#EXT#@contoso.onmicrosoft.com',
                [string]$Mail = 'guest@example.com',
                [Nullable[datetime]]$LastSignIn = (Get-Date).AddDays(-1),
                [bool]$Enabled = $true
            )
            return [pscustomobject]@{
                Id = $Name
                DisplayName = $Name
                UserPrincipalName = $Upn
                Mail = $Mail
                UserType = 'Guest'
                CreatedDateTime = (Get-Date).AddDays(-400)
                SignInActivity = if ($null -ne $LastSignIn) {
                    [pscustomobject]@{ LastSignInDateTime = $LastSignIn }
                }
                else { $null }
                AccountEnabled = $Enabled
            }
        }
        # Mock ALL external commands so nothing leaves the machine (offline Linux pwsh).
        Mock Connect-MgGraph
        Mock Disconnect-MgGraph
        Mock Get-MgUser { @() }
        Mock Get-MgRoleManagementDirectoryRoleAssignment { @() }
        Mock Get-MgRoleManagementDirectoryRoleDefinition { $null }
    }

    Context "Help & Metadata" {
        It "Declares all required header fields with relaunch values" {
            $content = Get-Content -Path $scriptPath -Raw
            $content | Should -Match '\.SYNOPSIS'
            $content | Should -Match '\.DESCRIPTION'
            $content | Should -Match '\.NOTES'
            $content | Should -Match 'Version\s*:\s*1\.0\.0'
            $content | Should -Match 'Date\s*:\s*2026-08-23'
            $content | Should -Match 'File Name\s*:\s*Get-AzureADGuestAudit\.ps1'
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
        It "Returns 0 with zero guests on an empty tenant" {
            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Found 0 guest user\(s\)'
            Should -Invoke Connect-MgGraph -Times 1 -Exactly
        }

        It "Flags guests inactive beyond the threshold and counts them in the summary" {
            Mock Get-MgUser { @(& $NewGuestUser -Name 'Stale Guest' -LastSignIn (Get-Date).AddDays(-200)) }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Inactive Guests \(> 90 days\): 1'
        }

        It "Counts never-signed-in guests as inactive without throwing" {
            Mock Get-MgUser { @(& $NewGuestUser -Name 'Fresh Guest' -LastSignIn $null) }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Never Signed In: 1'
        }

        It "Returns the documented exit code 1 when privileged guests are found" {
            Mock Get-MgUser { @(& $NewGuestUser -Name 'Admin Guest') }
            Mock Get-MgRoleManagementDirectoryRoleAssignment {
                @([pscustomobject]@{ RoleDefinitionId = 'role-123' })
            }
            Mock Get-MgRoleManagementDirectoryRoleDefinition {
                [pscustomobject]@{ DisplayName = 'Global Reader' }
            }

            $out = Main -CheckPrivilegedGuests *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            $text = $out | Out-String
            $text | Should -Match 'Privileged Guests \(CRITICAL\): 1'
            Should -Invoke Get-MgRoleManagementDirectoryRoleAssignment -Times 1 -Exactly
            Should -Invoke Get-MgRoleManagementDirectoryRoleDefinition -Times 1 -Exactly
        }

        It "Returns 1 and writes [-] prefixed output when the Graph connection fails" {
            Mock Connect-MgGraph { throw "sign-in cancelled" }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 and writes [-] prefixed output when guest retrieval fails" {
            Mock Get-MgUser { throw "Insufficient privileges" }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Performs no mutations: repeated audits only read from Graph" {
            Mock Get-MgUser { @((& $NewGuestUser -Name 'Guest A'), (& $NewGuestUser -Name 'Guest B')) }

            Main | Should -Be 0
            Main | Should -Be 0

            Should -Invoke Get-MgUser -Times 2 -Exactly
            Should -Invoke Disconnect-MgGraph -Times 2 -Exactly
        }
    }
}
