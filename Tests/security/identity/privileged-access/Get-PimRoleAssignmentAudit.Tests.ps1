#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/security/identity/privileged-access/Get-PimRoleAssignmentAudit.ps1.

.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior of the PIM
    role assignment auditor using fully mocked Microsoft Graph cmdlets. Runs offline on Linux
    pwsh; no network, elevation, or installed product modules required.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/security/identity/privileged-access/Get-PimRoleAssignmentAudit.Tests.ps1
    Runs this test file.

.EXAMPLE
    PS C:\> $testFile = './Tests/security/identity/privileged-access/Get-PimRoleAssignmentAudit.Tests.ps1'
    PS C:\> Invoke-Pester -Path $testFile -Output Detailed
    Runs this test file with per-test output.

.NOTES
    File Name   : Get-PimRoleAssignmentAudit.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-PimRoleAssignmentAudit' {
    BeforeAll {
        $relativeScript = '../../../../scripts/security/identity/privileged-access/Get-PimRoleAssignmentAudit.ps1'
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

        function New-RoleDefinition {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)][string]$Id,
                [Parameter()][string]$DisplayName = 'Role'
            )

            return @{ id = $Id; displayName = $DisplayName; isBuiltIn = $true }
        }

        function New-RoleAssignmentInstance {
            [CmdletBinding()]
            param(
                [Parameter()][string]$PrincipalId = 'user-1',
                [Parameter()][string]$RoleDefinitionId = 'role-ga',
                [Parameter()][string]$AssignmentType = 'Assigned',
                [Parameter()][string]$StartDateTime = '2026-01-05T00:00:00Z',
                [Parameter()][string]$EndDateTime = ''
            )

            return @{
                id               = 'instance-' + $PrincipalId + '-' + $RoleDefinitionId
                principalId      = $PrincipalId
                roleDefinitionId = $RoleDefinitionId
                assignmentType   = $AssignmentType
                memberType       = 'Direct'
                startDateTime    = $StartDateTime
                endDateTime      = $EndDateTime
            }
        }

        function New-DirectoryUser {
            [CmdletBinding()]
            param(
                [Parameter()][string]$Id = 'user-1',
                [Parameter()][string]$DisplayName = 'Privileged User',
                [Parameter()][string]$UserType = 'Member',
                [Parameter()][string]$UserPrincipalName = 'privuser@contoso.onmicrosoft.com'
            )

            return @{
                id                = $Id
                displayName       = $DisplayName
                userType          = $UserType
                userPrincipalName = $UserPrincipalName
            }
        }

        function New-DirectoryGroup {
            [CmdletBinding()]
            param(
                [Parameter()][string]$Id = 'group-1',
                [Parameter()][string]$DisplayName = 'Privileged Access Group'
            )

            return @{ id = $Id; displayName = $DisplayName }
        }

        Mock Import-Module { }
        Mock Connect-MgGraph { }
        Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*roleManagement/directory/roleDefinitions*' } {
            New-GraphPage -Value @( (New-RoleDefinition -Id 'role-ga' -DisplayName 'Global Administrator') )
        }
        Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' } {
            New-GraphPage -Value @()
        }
        Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*roleEligibilityScheduleInstances*' } {
            New-GraphPage -Value @()
        }
        Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/users*' } {
            New-GraphPage -Value @( (New-DirectoryUser) )
        }
        Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/groups*' } {
            New-GraphPage -Value @( (New-DirectoryGroup) )
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
                'RoleFilter',
                'IncludeGroups',
                'StaleDays',
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
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' } {
                New-GraphPage -Value @()
            }
            $TenantId = 'contoso.onmicrosoft.com'
            $RoleFilter = 'Privileged'
            $IncludeGroups = $false
            $StaleDays = 90
            $OutputFormat = 'Table'
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter {
                $TenantId -eq 'contoso.onmicrosoft.com' -and
                $Scopes -contains 'RoleManagement.Read.Directory'
            }
        }

        It 'Returns 0 when the tenant has no assignments in scope' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' } {
                New-GraphPage -Value @()
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*roleEligibilityScheduleInstances*' } {
                New-GraphPage -Value @()
            }
            $TenantId = ''
            $RoleFilter = 'Privileged'
            $IncludeGroups = $false
            $StaleDays = 90
            $OutputFormat = 'Table'
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($Out | Out-String) | Should -Match '\[\+\]'
            ($Out | Out-String) | Should -Match 'audited: 0'
            (Get-Location).Path | Should -Be $workingDirectory
        }

        It 'Classifies a permanent privileged assignment and returns 2' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' } {
                New-GraphPage -Value @( (New-RoleAssignmentInstance -AssignmentType 'Assigned') )
            }
            $RoleFilter = 'Privileged'
            $IncludeGroups = $false
            $StaleDays = 90
            $OutputFormat = 'Table'
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($Out | Out-String) | Should -Match 'PERMANENT-ACTIVE'
            ($Out | Out-String) | Should -Match 'permanent-active: 1'
        }

        It 'Classifies time-bound assignments and flags never-activated eligibilities' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' } {
                New-GraphPage -Value @( (New-RoleAssignmentInstance -EndDateTime '2026-12-31T00:00:00Z') )
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*roleEligibilityScheduleInstances*' } {
                New-GraphPage -Value @( (New-RoleAssignmentInstance -StartDateTime '2020-01-01T00:00:00Z') )
            }
            $RoleFilter = 'Privileged'
            $IncludeGroups = $false
            $StaleDays = 90
            $OutputFormat = 'Table'
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($Out | Out-String) | Should -Match 'time-bound active: 1'
            ($Out | Out-String) | Should -Match 'ELIGIBLE-NEVER-ACTIVATED'
            ($Out | Out-String) | Should -Not -Match '\[!\] PERMANENT-ACTIVE'
        }

        It 'Flags guest principals holding a privileged assignment' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/users*' } {
                New-GraphPage -Value @( (New-DirectoryUser -Id 'user-1' -UserType 'Guest') )
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' } {
                New-GraphPage -Value @( (New-RoleAssignmentInstance -EndDateTime '2026-12-31T00:00:00Z') )
            }
            $RoleFilter = 'Privileged'
            $IncludeGroups = $false
            $StaleDays = 90
            $OutputFormat = 'Table'
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($Out | Out-String) | Should -Match 'GUEST-ROLE-HOLDER'
        }

        It 'Excludes group-held assignments unless -IncludeGroups is supplied' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/users*' } {
                New-GraphPage -Value @()
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*/groups*' } {
                New-GraphPage -Value @( (New-DirectoryGroup -Id 'group-1') )
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' } {
                New-GraphPage -Value @(
                    (New-RoleAssignmentInstance -PrincipalId 'group-1' -EndDateTime '2026-12-31T00:00:00Z')
                )
            }
            $RoleFilter = 'Privileged'
            $StaleDays = 90
            $OutputFormat = 'Table'

            $IncludeGroups = $false
            $Out = Main *>&1
            ($Out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($Out | Out-String) | Should -Match 'excluded; rerun with -IncludeGroups'
            ($Out | Out-String) | Should -Match 'audited: 0'

            $IncludeGroups = $true
            $Out = Main *>&1
            ($Out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($Out | Out-String) | Should -Match 'audited: 1'
        }

        It 'Audits only the role selected by -RoleFilter' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*roleManagement/directory/roleDefinitions*' } {
                $definitions = @(
                    (New-RoleDefinition -Id 'role-ga' -DisplayName 'Global Administrator')
                    (New-RoleDefinition -Id 'role-aa' -DisplayName 'Application Administrator')
                )
                New-GraphPage -Value $definitions
            }
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' } {
                New-GraphPage -Value @( (New-RoleAssignmentInstance -RoleDefinitionId 'role-aa') )
            }
            $IncludeGroups = $false
            $StaleDays = 90
            $OutputFormat = 'Table'

            $RoleFilter = 'Privileged'
            $Out = Main *>&1
            ($Out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($Out | Out-String) | Should -Match 'audited: 1'

            $RoleFilter = 'Global Administrator'
            $Out = Main *>&1
            ($Out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($Out | Out-String) | Should -Match 'audited: 0'
        }

        It 'Writes a JSON report under $env:TEMP without touching the working directory' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' } {
                New-GraphPage -Value @( (New-RoleAssignmentInstance -AssignmentType 'Assigned') )
            }
            $reportPath = Join-Path $tempRoot 'bfu-pim-audit-report.json'
            if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath -Force }
            $RoleFilter = 'Privileged'
            $IncludeGroups = $false
            $StaleDays = 90
            $OutputFormat = 'Json'
            $OutputPath = $reportPath
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 2
            Test-Path -LiteralPath $reportPath | Should -BeTrue
            (Get-Content -LiteralPath $reportPath -Raw) | Should -Match 'PermanentActiveCount'
            (Get-Location).Path | Should -Be $workingDirectory
        }

        It 'Returns 1 and writes [-] output when Microsoft Graph fails' {
            Mock Invoke-MgGraphRequest -ParameterFilter { $Uri -like '*roleManagement/directory/roleDefinitions*' } {
                throw 'Graph request failed'
            }
            $RoleFilter = 'Privileged'
            $IncludeGroups = $false
            $StaleDays = 90
            $OutputFormat = 'Table'
            $Out = Main *>&1

            ($Out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($Out | Out-String) | Should -Match '\[-\]'
            ($Out | Out-String) | Should -Match 'Graph request failed'
        }
    }
}
