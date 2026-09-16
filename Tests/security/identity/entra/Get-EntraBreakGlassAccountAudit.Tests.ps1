#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/security/identity/entra/Get-EntraBreakGlassAccountAudit.ps1.

.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior of the
    emergency access account auditor using fully mocked Microsoft Graph cmdlets. Runs offline on
    Linux pwsh; no network, elevation, or installed product modules required.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/security/identity/entra/Get-EntraBreakGlassAccountAudit.Tests.ps1
    Runs this test file.

.EXAMPLE
    PS C:\> $testFile = './Tests/security/identity/entra/Get-EntraBreakGlassAccountAudit.Tests.ps1'
    PS C:\> Invoke-Pester -Path $testFile -Output Detailed
    Runs this test file with per-test output.

.NOTES
    File Name   : Get-EntraBreakGlassAccountAudit.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-EntraBreakGlassAccountAudit' {
    BeforeAll {
        $relativeScript = '../../../../scripts/security/identity/entra/Get-EntraBreakGlassAccountAudit.ps1'
        $scriptPath = Join-Path $PSScriptRoot $relativeScript
        $scriptName = Split-Path $scriptPath -Leaf
        $raw = [IO.File]::ReadAllText($scriptPath)
        $workingDirectory = (Get-Location).Path
        $tempRoot = [IO.Path]::GetTempPath()

        # Safe: the script's top-level guard skips Main when dot-sourced (spec section 3).
        . $scriptPath

        # The product module is not installed offline: declare its cmdlets as advanced-function
        # stubs carrying the real parameter sets, then mock them.
        function Import-Module {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true, Position = 0)][string[]]$Name
            )
        }

        function Connect-MgGraph {
            [CmdletBinding()]
            param(
                [Parameter()][string]$TenantId,
                [Parameter()][string[]]$Scopes,
                [Parameter()][switch]$NoWelcome
            )
        }

        function Invoke-MgGraphRequest {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)][string]$Method,
                [Parameter(Mandatory = $true)][string]$Uri,
                [Parameter()][hashtable]$Body,
                [Parameter()][string]$OutputType
            )
        }

        function New-GraphPage {
            [CmdletBinding()]
            param(
                [Parameter()][object[]]$Value,
                [Parameter()][string]$NextLink
            )

            $page = @{ value = @($Value) }
            if (-not [string]::IsNullOrWhiteSpace($NextLink)) { $page['@odata.nextLink'] = $NextLink }
            return $page
        }

        function New-DirectoryRole {
            [CmdletBinding()]
            param(
                [Parameter()][string]$Id = 'role-ga',
                [Parameter()][string]$DisplayName = 'Global Administrator'
            )

            return @{
                id             = $Id
                displayName    = $DisplayName
                roleTemplateId = '62e90394-69f5-4237-9190-012177145e10'
            }
        }

        function New-AdminUser {
            [CmdletBinding()]
            param(
                [Parameter()][string]$Id = 'admin-1',
                [Parameter()][string]$DisplayName = 'Break Glass One',
                [Parameter()][string]$UserPrincipalName = 'breakglass1@contoso.onmicrosoft.com',
                [Parameter()][string]$UserType = 'Member',
                [Parameter()][object]$OnPremisesSyncEnabled = $null
            )

            return @{
                id                    = $Id
                displayName           = $DisplayName
                userPrincipalName     = $UserPrincipalName
                userType              = $UserType
                onPremisesSyncEnabled = $OnPremisesSyncEnabled
            }
        }

        function New-ConditionalAccessPolicy {
            [CmdletBinding()]
            param(
                [Parameter()][string]$State = 'enabled',
                [Parameter()][string[]]$ExcludeUsers = @(),
                [Parameter()][string[]]$ExcludeGroups = @(),
                [Parameter()][string[]]$ExcludeRoles = @()
            )

            return @{
                id         = 'policy-1'
                displayName = 'CA001: Require MFA'
                state      = $State
                conditions = @{
                    users = @{
                        includeUsers  = @('All')
                        excludeUsers  = @($ExcludeUsers)
                        excludeGroups = @($ExcludeGroups)
                        excludeRoles  = @($ExcludeRoles)
                    }
                }
            }
        }

        Mock Import-Module { }
        Mock Connect-MgGraph { }
        Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -eq 'https://graph.microsoft.com/v1.0/directoryRoles' } {
            New-GraphPage -Value @( (New-DirectoryRole) )
        }
        Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/directoryRoles/*/members' } {
            New-GraphPage -Value @( (New-AdminUser) )
        }
        Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*onPremisesSyncEnabled*' } {
            New-GraphPage -Value @( (New-AdminUser) )
        }
        Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/identity/conditionalAccess/policies*' } {
            New-GraphPage -Value @( (New-ConditionalAccessPolicy -ExcludeUsers @('admin-1')) )
        }
        Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/authentication/passwordMethods' } {
            New-GraphPage -Value @( @{ id = '28c10230-6103-485e-b985-444c60001490' } )
        }
        Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/transitiveMemberOf/*' } {
            New-GraphPage -Value @()
        }

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath, [ref]$tokens, [ref]$parseErrors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match "(?m)^\s*File Name\s*:\s*$([regex]::Escape($scriptName))\s*$"
            $raw | Should -Match '(?m)^\s*Author\s*:\s*\S+'
            $raw | Should -Match '(?m)^\s*Prerequisite\s*:\s*PowerShell 7\.0\s*$'
            $raw | Should -Match '(?m)^\s*Version\s*:\s*2\.0\.0\s*$'
            $raw | Should -Match '(?m)^\s*Date\s*:\s*2026-09-16\s*$'
        }

        It 'Has one .PARAMETER entry per declared parameter' {
            $parameters = @(
                'TenantId',
                'ExpectedAccountCount',
                'OutputFormat',
                'OutputPath'
            )
            foreach ($name in $parameters) {
                $raw | Should -Match "(?m)^\.PARAMETER\s+$name\s*$"
            }
        }

        It 'Provides at least two examples with PS prompts' {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $parseErrors.Count | Should -Be 0
        }

        It 'Uses CmdletBinding, Main, and the dot-source guard' {
            $raw | Should -Match '\[CmdletBinding\('
            $raw | Should -Match '(?m)^function Main\b'
            $raw | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
        }

        It 'Contains no PS7-only operators and no #Requires opt-out' {
            ($raw -match '\?\?') | Should -BeFalse
            ($raw -match '\|\|') | Should -BeFalse
            ($raw -match '&&') | Should -BeFalse
            ($raw -match '#Requires\s+-Version') | Should -BeFalse
        }

        It 'Is UTF-8 with BOM and CRLF line endings' {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }

        It 'Cites Microsoft Learn in its help' {
            $raw | Should -Match 'learn\.microsoft\.com'
        }
    }

    Context 'Behavior' {
        It 'Connects to the supplied tenant with the documented Microsoft Graph scope' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/authentication/passwordMethods' } {
                New-GraphPage -Value @( @{ id = 'pwd-1' } )
            }
            $TenantId = 'contoso.onmicrosoft.com'
            $ExpectedAccountCount = 1
            $OutputFormat = 'Table'
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter {
                $TenantId -eq 'contoso.onmicrosoft.com' -and
                $Scopes -contains 'UserAuthenticationMethod.Read.All'
            }
        }

        It 'Meets the baseline and returns 0 with two excluded cloud-only accounts' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/directoryRoles/*/members' } {
                New-GraphPage -Value @( (New-AdminUser -Id 'admin-1'), (New-AdminUser -Id 'admin-2') )
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*onPremisesSyncEnabled*' } {
                New-GraphPage -Value @( (New-AdminUser -Id 'admin-1'), (New-AdminUser -Id 'admin-2') )
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/identity/conditionalAccess/policies*' } {
                New-GraphPage -Value @( (New-ConditionalAccessPolicy -ExcludeUsers @('admin-1', 'admin-2')) )
            }
            $TenantId = ''
            $ExpectedAccountCount = 2
            $OutputFormat = 'Table'
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($Out | Out-String) | Should -Match 'cloud-only members: 2'
            ($Out | Out-String) | Should -Match '\[\+\] Emergency access account baseline met'
            (Get-Location).Path | Should -Be $workingDirectory
        }

        It 'Returns 2 and reports GA-COUNT-LOW when fewer accounts exist than expected' {
            $ExpectedAccountCount = 2
            $OutputFormat = 'Table'
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($Out | Out-String) | Should -Match 'GA-COUNT-LOW'
            ($Out | Out-String) | Should -Match 'cloud-only members: 1'
        }

        It 'Flags guest and synchronized Global Administrators' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/directoryRoles/*/members' } {
                New-GraphPage -Value @( (New-AdminUser -Id 'admin-1'), (New-AdminUser -Id 'admin-2') )
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*onPremisesSyncEnabled*' } {
                $guest = New-AdminUser -Id 'admin-1' -UserType 'Guest'
                $synced = New-AdminUser -Id 'admin-2' -OnPremisesSyncEnabled $true
                New-GraphPage -Value @($guest, $synced)
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/identity/conditionalAccess/policies*' } {
                New-GraphPage -Value @( (New-ConditionalAccessPolicy -ExcludeUsers @('admin-1', 'admin-2')) )
            }
            $ExpectedAccountCount = 2
            $OutputFormat = 'Table'
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($Out | Out-String) | Should -Match 'GA-GUEST'
            ($Out | Out-String) | Should -Match 'GA-SYNCED-FROM-ONPREM'
        }

        It 'Flags Global Administrators that no enabled policy excludes' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/identity/conditionalAccess/policies*' } {
                New-GraphPage -Value @( (New-ConditionalAccessPolicy) )
            }
            $ExpectedAccountCount = 2
            $OutputFormat = 'Table'
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($Out | Out-String) | Should -Match 'GA-NOT-CA-EXCLUDED'
        }

        It 'Accepts a group-based Conditional Access exclusion' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/directoryRoles/*/members' } {
                New-GraphPage -Value @( (New-AdminUser -Id 'admin-1'), (New-AdminUser -Id 'admin-2') )
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*onPremisesSyncEnabled*' } {
                New-GraphPage -Value @( (New-AdminUser -Id 'admin-1'), (New-AdminUser -Id 'admin-2') )
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/identity/conditionalAccess/policies*' } {
                New-GraphPage -Value @( (New-ConditionalAccessPolicy -ExcludeGroups @('group-breakglass')) )
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/transitiveMemberOf/*' } {
                New-GraphPage -Value @( @{ id = 'group-breakglass' } )
            }
            $ExpectedAccountCount = 2
            $OutputFormat = 'Table'
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($Out | Out-String) | Should -Not -Match 'GA-NOT-CA-EXCLUDED'
        }

        It 'Flags an account with no password credential' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/authentication/passwordMethods' } {
                New-GraphPage -Value @()
            }
            $ExpectedAccountCount = 1
            $OutputFormat = 'Table'
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($Out | Out-String) | Should -Match 'GA-NO-PASSWORD-CREDENTIAL'
        }

        It 'Writes a JSON report under $env:TEMP without touching the working directory' {
            $reportPath = Join-Path $tempRoot 'bfu-breakglass-audit-report.json'
            if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath -Force }
            $ExpectedAccountCount = 2
            $OutputFormat = 'Json'
            $OutputPath = $reportPath
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 2
            Test-Path -LiteralPath $reportPath | Should -BeTrue
            (Get-Content -LiteralPath $reportPath -Raw) | Should -Match 'CloudOnlyAdminCount'
            (Get-Location).Path | Should -Be $workingDirectory
        }

        It 'Returns 1 and writes [-] output when Microsoft Graph fails' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -eq 'https://graph.microsoft.com/v1.0/directoryRoles' } {
                throw 'Graph request failed'
            }
            $ExpectedAccountCount = 2
            $OutputFormat = 'Table'
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($Out | Out-String) | Should -Match '\[-\]'
            ($Out | Out-String) | Should -Match 'Graph request failed'
        }
    }
}
