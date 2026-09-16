#Requires -Modules Pester

Describe "Get-DeviceGroupMembership" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/intune/reporting/ -> script is
        # four levels up + across into scripts/.
        $scriptPath = [IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot "../../../../scripts/endpoints/intune/reporting/Get-DeviceGroupMembership.ps1"))

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Stub helper-module commands (the module import itself is mocked) so Pester can attach mocks.
        # Each stub is advanced and mirrors the helper's real parameter set, so a parameter the
        # helper does not declare fails binding instead of being silently swallowed.
        function Connect-IntuneGraph {
            [CmdletBinding()]
            param([string[]]$Scopes, [string]$TenantId)
        }
        function Disconnect-IntuneGraph {
            [CmdletBinding()]
            param()
        }
        function Get-AllIntuneDevices {
            [CmdletBinding()]
            param()
        }
        function Invoke-MgGraphRequest {
            [CmdletBinding()]
            param([string]$Uri, [string]$Method)
        }
        function Export-IntuneReportToHTML {
            [CmdletBinding()]
            param([object[]]$Data, [string]$Title, [string]$FilePath, [string]$Description)
        }
        function Export-IntuneReportToCSV {
            [CmdletBinding()]
            param([object[]]$Data, [string]$Title, [string]$FilePath)
        }

        # Mock the helper module import and every Graph entry point so nothing leaves the machine.
        Mock Import-Module { }
        Mock Connect-IntuneGraph { $true }
        Mock Disconnect-IntuneGraph { }
        Mock Export-IntuneReportToHTML { }
        Mock Export-IntuneReportToCSV { }

        # Default Graph payload: device PC01 is a member of one assigned group.
        Mock Invoke-MgGraphRequest {
            param($Uri)
            if ($Uri -match '/devices\?') {
                return @{ value = @([pscustomobject]@{ id = 'dev-1'; displayName = 'PC01' }) }
            }
            if ($Uri -match '/devices/dev-1/memberOf') {
                return @{ value = @([pscustomobject]@{
                    '@odata.type' = '#microsoft.graph.group'; id = 'grp-1'
                }) }
            }
            if ($Uri -match '/groups/grp-1') {
                return [pscustomobject]@{
                    id = 'grp-1'; displayName = 'Group One'; membershipRule = $null; description = 'Test group'
                }
            }
            return @{ value = @() }
        }
    }

    Context "Help & Metadata" {
        BeforeAll {
            $raw = Get-Content -Raw -LiteralPath $scriptPath
            $bytes = [IO.File]::ReadAllBytes($scriptPath)

            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declaredParams = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $documentedParams = [regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value }
        }

        It "Declares the complete .NOTES header (File Name, Author, Prerequisite, Version, Date)" {
            $raw | Should -Match '(?m)^\.NOTES'
            $raw | Should -Match 'File Name\s*:\s*Get-DeviceGroupMembership\.ps1'
            $raw | Should -Match 'Author\s*:\s*\S+'
            $raw | Should -Match 'Prerequisite\s*:\s*PowerShell'
            $raw | Should -Match 'Version\s*:\s*2\.0\.0'
            $raw | Should -Match 'Date\s*:\s*2026-09-16'
        }

        It "Documents exactly one .PARAMETER per declared parameter, in declaration order" {
            $documentedParams.Count | Should -Be $declaredParams.Count
            for ($i = 0; $i -lt $declaredParams.Count; $i++) {
                $documentedParams[$i] | Should -Be $declaredParams[$i]
            }
        }

        It "Provides at least two .EXAMPLE blocks with PS C:\> prompt lines" {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            $raw | Should -Match 'PS C:\\>'
        }

        It "Is saved as UTF-8 with BOM" {
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
        }
    }

    Context "Syntax & Static" {
        It "Parses via the PowerShell parser with zero errors" {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            @($parseErrors).Count | Should -Be 0
        }

        It "Contains no PS7-only operators (no #Requires -Version 7.0 opt-out present)" {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $ps7OnlyKinds = @('QuestionMark', 'QuestionMarkQuestionMark', 'AmpersandAmpersand', 'PipePipe')
            $offending = @($tokens | Where-Object { $_.Kind -in $ps7OnlyKinds })
            $offending | Should -BeNullOrEmpty -Because "PS7-only operators require the 7.0 opt-out"
        }

        It "Uses only approved verbs for its functions" {
            $functionNames = (Get-Content -Raw -LiteralPath $scriptPath) |
                Select-String -Pattern '(?m)^\s*function\s+([A-Za-z]+-[A-Za-z]+)' -AllMatches |
                ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value }
            foreach ($name in $functionNames) {
                $verb = ($name -split '-')[0]
                Get-Verb -Verb $verb | Should -Not -BeNullOrEmpty -Because "$name must use an approved verb"
            }
        }

        It "Wraps the body in Main and keeps exit in the dot-source guard only" {
            $exitLines = @((Get-Content -LiteralPath $scriptPath) | Where-Object { $_ -match '\bexit\b' })
            @($exitLines).Count | Should -Be 1
            $exitLines[0] | Should -Match '\$MyInvocation\.InvocationName'
            Get-Content -Raw -LiteralPath $scriptPath | Should -Match 'function Main'
        }
    }

    Context "Behavior" {
        It "Audits a device's group memberships and exports both HTML and CSV reports (returns 0)" {
            $DeviceName = 'PC01'

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Contain 0
            ($out | Out-String) | Should -Match '\[\+\].*Found device: PC01'
            Should -Invoke Invoke-MgGraphRequest -Times 3 -Exactly
            Should -Invoke Export-IntuneReportToHTML -Times 1 -Exactly
            Should -Invoke Export-IntuneReportToCSV -Times 1 -Exactly
        }

        It "Skips non-group memberOf entries (administrative units) and still reports the group" {
            $DeviceName = 'PC02'
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match '/devices\?') {
                    return @{ value = @([pscustomobject]@{ id = 'dev-2'; displayName = 'PC02' }) }
                }
                if ($Uri -match '/devices/dev-2/memberOf') {
                    return @{ value = @(
                        [pscustomobject]@{
                            '@odata.type' = '#microsoft.graph.administrativeUnit'
                            id = 'au-1'; displayName = 'Admin Unit One'
                        }
                        [pscustomobject]@{
                            '@odata.type' = '#microsoft.graph.group'
                            id = 'grp-2'; displayName = 'Group Two'
                        }
                    ) }
                }
                if ($Uri -match '/groups/grp-2') {
                    return [pscustomobject]@{
                        id = 'grp-2'; displayName = 'Group Two'; membershipRule = 'dynamic rule'
                        description = 'Second group'
                    }
                }
                return @{ value = @() }
            }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\].*Found 1 group memberships'
            # Device lookup + memberOf + exactly one group detail: the administrative unit is
            # never dereferenced through /groups/{id}.
            Should -Invoke Invoke-MgGraphRequest -Times 3 -Exactly
        }

        It "Returns 1 with [-] output when the device is not found in Azure AD" {
            $DeviceName = 'GHOST-PC'
            Mock Invoke-MgGraphRequest { param($Uri) return @{ value = @() } }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\].*not found in Azure AD'
            Should -Invoke Export-IntuneReportToHTML -Times 0 -Exactly
        }

        It "Returns 1 without querying Graph when run with no mode selected" {
            Mock Connect-IntuneGraph { $true }   # fresh mocks reset call history

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\].*Please specify'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
        }

        It "Returns 1 with [-] output when the Graph connection fails" {
            Mock Connect-IntuneGraph { $false }

            $DeviceName = 'PC01'
            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\].*Failed to connect'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
        }

        It "Is idempotent for read-only reporting: repeated runs succeed against the same data" {
            $ShowAllMappings = $true
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -match '/groups$') {
                    return @{
                        value = @([pscustomobject]@{
                            id = 'grp-1'; displayName = 'Group One'; membershipRule = $null; description = 'd'
                        })
                    }
                }
                if ($Uri -match '/members\?') {
                    return @{
                        value = @([pscustomobject]@{
                            '@odata.type' = '#microsoft.graph.device'
                            id = 'dev-9'; displayName = 'PC09'; deviceId = 'dev-9'
                        })
                    }
                }
                return @{ value = @() }
            }

            Main | Should -Be 0
            Main | Should -Be 0   # second identical run: still succeeds, nothing mutated
            Should -Invoke Export-IntuneReportToHTML -Times 2 -Exactly
        }

        It "Returns 1 and writes [-] prefixed output when an upstream Graph call throws" {
            $GroupName = 'Windows 10 Devices'
            Mock Invoke-MgGraphRequest { throw 'graph unreachable' }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
