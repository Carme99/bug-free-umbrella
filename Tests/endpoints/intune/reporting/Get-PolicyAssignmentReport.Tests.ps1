#Requires -Modules Pester

Describe "Get-PolicyAssignmentReport" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/intune/reporting/ -> script is
        # four levels up + across into scripts/.
        $scriptPath = [IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot "../../../../scripts/endpoints/intune/reporting/Get-PolicyAssignmentReport.ps1"))

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Stub helper-module commands (the module import itself is mocked) so Pester can attach mocks.
        function Connect-IntuneGraph { param([string]$TenantId, [string[]]$Scopes) }
        function Disconnect-IntuneGraph { }
        function Invoke-MgGraphRequest { param([string]$Uri, [string]$Method) }
        function Get-AllIntuneDevices { }
        function Export-IntuneReportToHTML { param($Data, [string]$Title, [string]$Description, [string]$FilePath) }
        function Export-IntuneReportToCSV { param($Data, [string]$Title, [string]$FilePath) }

        # Mock the helper module import and every Graph entry point so nothing leaves the machine.
        Mock Import-Module { }
        Mock Connect-IntuneGraph { }
        Mock Export-IntuneReportToHTML { }

        # Graph payload: two device configuration policies sharing one group target (a conflict),
        # one Settings Catalog profile assigned to all devices; no compliance or app protection.
        Mock Invoke-MgGraphRequest {
            param($Uri)
            if ($Uri -match 'deviceConfigurations/[^/]+/assignments') {
                return @{ value = @([pscustomobject]@{
                    intent = 'apply'
                    target = [pscustomobject]@{
                        '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'grp-a'
                    }
                }) }
            }
            if ($Uri -match '/deviceConfigurations$') {
                return @{ value = @(
                    [pscustomobject]@{
                        id = 'cfg-1'; displayName = 'Win Config A'
                        createdDateTime = [datetime]'2026-01-01Z'; lastModifiedDateTime = [datetime]'2026-01-02Z'
                    }
                    [pscustomobject]@{
                        id = 'cfg-2'; displayName = 'Win Config B'
                        createdDateTime = [datetime]'2026-01-01Z'; lastModifiedDateTime = [datetime]'2026-01-02Z'
                    }
                ) }
            }
            if ($Uri -match 'configurationPolicies/[^/]+/assignments') {
                return @{ value = @([pscustomobject]@{
                    target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' }
                }) }
            }
            if ($Uri -match '/configurationPolicies$') {
                return @{ value = @([pscustomobject]@{
                    id = 'sc-1'; name = 'SettingsCatalog1'
                    createdDateTime = [datetime]'2026-01-01Z'; lastModifiedDateTime = [datetime]'2026-01-02Z'
                }) }
            }
            return @{ value = @() }   # compliance policies, app protection, anything else
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
            $raw | Should -Match 'File Name\s*:\s*Get-PolicyAssignmentReport\.ps1'
            $raw | Should -Match 'Author\s*:\s*\S+'
            $raw | Should -Match 'Prerequisite\s*:\s*PowerShell'
            $raw | Should -Match 'Version\s*:\s*1\.0\.0'
            $raw | Should -Match 'Date\s*:\s*2026-08-23'
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
        It "Collects assignments across policy types and writes a CSV report (returns 0)" {
            $OutputPath = Join-Path $TestDrive ([guid]::NewGuid().Guid)
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            $Format = 'CSV'

            Main | Should -Be 0

            $csvFile = Get-ChildItem -Path $OutputPath -Filter 'PolicyAssignmentReport-*.csv' | Select-Object -First 1
            $csvFile | Should -Not -BeNullOrEmpty
            $rows = @((Import-Csv -Path $csvFile.FullName))
            $rows.Count | Should -Be 3   # 2 config + 1 settings catalog
            ($rows | Where-Object { $_.PolicyType -eq 'Device Configuration' }).Count | Should -Be 2
            ($rows | Where-Object { $_.AssignmentTarget -eq 'All Devices' }).Count | Should -Be 1
        }

        It "Flags potential conflicts when one group receives multiple policies of the same type" {
            $OutputPath = Join-Path $TestDrive ([guid]::NewGuid().Guid)
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            $Format = 'HTML'

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Contain 0
            ($out | Out-String) | Should -Match '\[\!\].*potential policy conflicts'
            Should -Invoke Export-IntuneReportToHTML -Times 1 -Exactly -ParameterFilter {
                $Title -eq 'Intune Policy Assignment Report'
            }
        }

        It "Is idempotent for read-only reporting: repeated runs succeed against the same data" {
            $OutputPath = Join-Path $TestDrive ([guid]::NewGuid().Guid)
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            $Format = 'HTML'

            Main | Should -Be 0
            Main | Should -Be 0   # second identical run: still succeeds, nothing mutated
        }

        It "Returns 1 and writes [-] prefixed output when a Graph query fails" {
            $OutputPath = Join-Path $TestDrive ([guid]::NewGuid().Guid)
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            $Format = 'CSV'
            Mock Invoke-MgGraphRequest { throw 'graph unreachable' }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
