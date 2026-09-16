#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for scripts/security/defender/Get-DefenderAsrRuleAudit.ps1.

.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior using fully
    mocked Microsoft Graph cmdlets. Runs offline on Linux pwsh; no network, elevation, or
    installed product modules required.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/security/defender/Get-DefenderAsrRuleAudit.Tests.ps1
    Runs this test file.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/security/defender -Output Detailed
    Runs this test file with per-test output.

.NOTES
    File Name   : Get-DefenderAsrRuleAudit.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-DefenderAsrRuleAudit' {
    BeforeAll {
        $scriptRelPath = ('../../../scripts/security/defender/Get-DefenderAsrRuleAudit.ps1')
        $scriptPath = (Resolve-Path (Join-Path $PSScriptRoot $scriptRelPath)).Path

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Microsoft Graph is not installed offline: declare each cmdlet the script calls as an
        # advanced function carrying its real parameter set, then mock it.
        function Connect-MgGraph {
            [CmdletBinding()]
            param(
                [string[]]$Scopes,
                [switch]$NoWelcome
            )
        }

        function Invoke-MgGraphRequest {
            [CmdletBinding()]
            param(
                [string]$Method,
                [string]$Uri,
                [string]$OutputType,
                [hashtable]$Headers,
                [object]$Body
            )
        }

        # The three standard protection rules Microsoft recommends in Block mode.
        $driverRuleGuid = '56a863a9-875e-4185-98a7-b882c64b5ce5'
        $lsassRuleGuid = '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2'
        $wmiRuleGuid = 'e6db77e5-3df2-4cf1-b95a-636979351e5b'
        $recommendedGuidList = @($driverRuleGuid, $lsassRuleGuid, $wmiRuleGuid)

        $defaultMachines = @(
            [pscustomobject]@{
                id             = 'pc01-device-id'
                computerDnsName = 'PC01.contoso.com'
                healthStatus   = 'Active'
            }
            [pscustomobject]@{
                id             = 'srv01-device-id'
                computerDnsName = 'SRV01.contoso.com'
                healthStatus   = 'Active'
            }
        )

        # PC01 reports a Block rule, an Off rule and a NotApplicable rule; SRV01 reports nothing.
        $defaultAssessments = @(
            [pscustomobject]@{
                DeviceId        = 'pc01-device-id'
                DeviceName      = 'PC01.contoso.com'
                ConfigurationId = '56A863A9-875E-4185-98A7-B882C64B5CE5'
                IsApplicable    = $true
                IsCompliant     = $true
            }
            [pscustomobject]@{
                DeviceId        = 'pc01-device-id'
                DeviceName      = 'PC01.contoso.com'
                ConfigurationId = '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2'
                IsApplicable    = $true
                IsCompliant     = $false
            }
            [pscustomobject]@{
                DeviceId        = 'pc01-device-id'
                DeviceName      = 'PC01.contoso.com'
                ConfigurationId = 'e6db77e5-3df2-4cf1-b95a-636979351e5b'
                IsApplicable    = $false
                IsCompliant     = $false
            }
        )

        $compliantAssessments = @(
            foreach ($guid in @($driverRuleGuid, $lsassRuleGuid, $wmiRuleGuid)) {
                [pscustomobject]@{
                    DeviceId        = 'pc01-device-id'
                    DeviceName      = 'PC01.contoso.com'
                    ConfigurationId = $guid
                    IsApplicable    = $true
                    IsCompliant     = $true
                }
                [pscustomobject]@{
                    DeviceId        = 'srv01-device-id'
                    DeviceName      = 'SRV01.contoso.com'
                    ConfigurationId = $guid
                    IsApplicable    = $true
                    IsCompliant     = $true
                }
            }
        )

        Mock Connect-MgGraph { }
        Mock Invoke-MgGraphRequest {
            param($Uri)
            if ($Uri -like '*SecureConfigurationsAssessmentByMachine*') {
                return [pscustomobject]@{ value = $defaultAssessments }
            }
            if ($Uri -like '*/api/machines?$top=*') {
                return [pscustomobject]@{ value = $defaultMachines }
            }
            return [pscustomobject]@{ value = @() }
        }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath, [ref]$tokens, [ref]$parseErrors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Get-DefenderAsrRuleAudit\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*Bug-Free Umbrella'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Documents every declared parameter, in order' {
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object {
                    $_.Name.Extent.Text.TrimStart('$')
                })
            $helpParams = @([regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value })
            $declared | Should -Be @('MachineName', 'OutputFormat', 'OutputPath')
            $helpParams | Should -Be $declared
        }

        It 'Declares the documented format set and the * default for -MachineName' {
            $raw | Should -Match "ValidateSet\('Table', 'Json', 'Csv'\)"
            $raw | Should -Match "(?m)\[string\]\`$MachineName = '\*'"
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

        It 'Uses CmdletBinding, Main function, and dot-source guard' {
            $raw | Should -Match '\[CmdletBinding\('
            $raw | Should -Match '(?m)^function Main \{'
            $raw | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
        }

        It 'Contains no PS7-only operators and no #Requires opt-out' {
            # Token-level scan: the forbidden operator texts are built from code points so this
            # file does not itself contain them.
            $forbidden = @(
                (-join [char[]](0x3F, 0x3F))
                (-join [char[]](0x3F, 0x3F, 0x3D))
                (-join [char[]](0x26, 0x26))
                (-join [char[]](0x7C, 0x7C))
            )
            $declaredTokens = @($tokens | ForEach-Object { $_.Text })
            foreach ($operator in $forbidden) {
                $declaredTokens | Should -Not -Contain $operator
            }
            $raw | Should -Not -Match '#Requires\s+-Version'
        }

        It 'Is UTF-8 with BOM and CRLF line endings' {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }

        It 'Keeps all lines within 120 columns and free of tabs' {
            ($raw -split "`r`n" | Where-Object { $_.Length -gt 120 }) | Should -BeNullOrEmpty
            $raw | Should -Not -Match "`t"
        }

        It 'Carries the documented ASR rule GUIDs from the rules reference' {
            foreach ($guid in @('56a863a9-875e-4185-98a7-b882c64b5ce5',
                    '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2',
                    'e6db77e5-3df2-4cf1-b95a-636979351e5b',
                    'c1db55ab-c21a-4637-bb3f-a12568109d35')) {
                $raw | Should -Match ([regex]::Escape($guid))
            }
        }

        It 'Cites the Microsoft Learn pages for the ASR rules it audits' {
            $raw | Should -Match ('learn\.microsoft\.com/defender-endpoint/' +
                'attack-surface-reduction-rules-reference')
            $raw | Should -Match ('learn\.microsoft\.com/defender-endpoint/' +
                'attack-surface-reduction-rules-overview')
            $raw | Should -Match ('learn\.microsoft\.com/defender-endpoint/' +
                'enable-attack-surface-reduction')
        }
    }

    Context 'Behavior' {
        It 'Reports the recommended-rule gaps and machines without Block rules, returning 2' {
            . $scriptPath
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            $text = $out | Out-String
            $text | Should -Match 'Devices audited\s+:\s+2'
            $text | Should -Match 'ASR rules evaluated\s+:\s+19'
            $text | Should -Match 'Rules in Block mode\s+:\s+1'
            $text | Should -Match 'Rules off\s+:\s+1'
            $text | Should -Match 'Rules not configured\s+:\s+35'
            $text | Should -Match 'Rules not applicable\s+:\s+1'
            $text | Should -Match ('PC01\.contoso\.com health=Active Block=1 NotApplicable=1 ' +
                'NotConfigured=16 Off=1')
            $text | Should -Match ('\[!\] PC01\.contoso\.com: Block credential stealing from the ' +
                'Windows local security authority subsystem is Off \(Microsoft recommends Block\)')
            $text | Should -Match '\[!\] SRV01\.contoso\.com: no ASR rule is in Block mode'
            $text | Should -Not -Match ('PC01\.contoso\.com: Block persistence through WMI ' +
                'event subscription')
            $text | Should -Match '\[!\] ASR rule findings: 5'
            Should -Invoke Connect-MgGraph -Exactly 1
            Should -Invoke Invoke-MgGraphRequest -ParameterFilter {
                $Uri -like '*/api/machines?$top=*' } -Exactly 1
            Should -Invoke Invoke-MgGraphRequest -ParameterFilter {
                $Uri -like '*SecureConfigurationsAssessmentByMachine*' } -Exactly 1
        }

        It 'Narrows the audit to devices matching the -MachineName wildcard' {
            . $scriptPath -MachineName 'PC*'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            $text = $out | Out-String
            $text | Should -Match 'Devices audited\s+:\s+1'
            $text | Should -Match 'PC01\.contoso\.com'
            $text | Should -Not -Match 'SRV01'
            $text | Should -Match '\[!\] ASR rule findings: 1'
        }

        It 'Returns 0 and reports compliance when the standard protection rules are blocked' {
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -like '*SecureConfigurationsAssessmentByMachine*') {
                    return [pscustomobject]@{ value = $compliantAssessments }
                }
                return [pscustomobject]@{ value = $defaultMachines }
            }
            . $scriptPath
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match 'Rules in Block mode\s+:\s+6'
            $text | Should -Match 'Rules not configured\s+:\s+32'
            $text | Should -Match '\[\+\] ASR rule posture is compliant'
        }

        It 'Reports a device whose rules are not configured and counts every rule state' {
            . $scriptPath -MachineName 'SRV01*'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            $text = $out | Out-String
            $text | Should -Match 'SRV01\.contoso\.com health=Active NotConfigured=19'
            $text | Should -Match ('\[!\] SRV01\.contoso\.com: Block abuse of exploited ' +
                'vulnerable signed drivers is NotConfigured \(Microsoft recommends Block\)')
            $text | Should -Match '\[!\] ASR rule findings: 4'
        }

        It 'Follows @odata.nextLink when the assessment export is paginated' {
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -like '*SecureConfigurationsAssessmentByMachine*' -and
                    $Uri -notlike '*$skip=200000*') {
                    return [pscustomobject]@{
                        value             = @($defaultAssessments[0], $defaultAssessments[1])
                        '@odata.nextLink' = ('https://api.security.microsoft.com/api/machines/' +
                            'SecureConfigurationsAssessmentByMachine?$skip=200000')
                    }
                }
                if ($Uri -like '*$skip=200000*') {
                    return [pscustomobject]@{
                        value = @(
                            [pscustomobject]@{
                                DeviceId        = 'srv01-device-id'
                                DeviceName      = 'SRV01.contoso.com'
                                ConfigurationId = $recommendedGuidList[0]
                                IsApplicable    = $true
                                IsCompliant     = $true
                            }
                            [pscustomobject]@{
                                DeviceId        = 'srv01-device-id'
                                DeviceName      = 'SRV01.contoso.com'
                                ConfigurationId = $recommendedGuidList[1]
                                IsApplicable    = $true
                                IsCompliant     = $true
                            }
                            [pscustomobject]@{
                                DeviceId        = 'srv01-device-id'
                                DeviceName      = 'SRV01.contoso.com'
                                ConfigurationId = $recommendedGuidList[2]
                                IsApplicable    = $true
                                IsCompliant     = $true
                            }
                        )
                    }
                }
                return [pscustomobject]@{ value = $defaultMachines }
            }
            . $scriptPath
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            $text = $out | Out-String
            $text | Should -Match 'Devices audited\s+:\s+2'
            $text | Should -Match 'Rules in Block mode\s+:\s+4'
            $text | Should -Match '\[!\] ASR rule findings: 2'
            Should -Invoke Invoke-MgGraphRequest -ParameterFilter {
                $Uri -like '*$skip=200000*' } -Exactly 1
        }

        It 'Writes a CSV report and leaves the working directory unchanged' {
            $csvPath = Join-Path ([IO.Path]::GetTempPath()) `
                ('defender-asr-audit-{0}.csv' -f [guid]::NewGuid().ToString('N'))
            $workingDirectory = (Get-Location).Path
            try {
                . $scriptPath -OutputFormat Csv -OutputPath $csvPath
                Main | Should -Be 2
                Test-Path -LiteralPath $csvPath | Should -BeTrue
                (Get-Location).Path | Should -Be $workingDirectory
                $csv = Get-Content -LiteralPath $csvPath -Raw
                $csv | Should -Match 'PC01\.contoso\.com'
                $csv | Should -Match 'SRV01\.contoso\.com'
            }
            finally {
                Remove-Item -LiteralPath $csvPath -ErrorAction SilentlyContinue
            }
        }

        It 'Writes a JSON report whose device summary matches the console counts' {
            $jsonPath = Join-Path ([IO.Path]::GetTempPath()) `
                ('defender-asr-audit-{0}.json' -f [guid]::NewGuid().ToString('N'))
            try {
                . $scriptPath -OutputFormat Json -OutputPath $jsonPath
                Main | Should -Be 2
                $parsed = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
                $parsed.Summary.DevicesAudited | Should -Be 2
                $parsed.Summary.Findings | Should -Be 5
                $parsed.Devices[0].Device | Should -Be 'PC01.contoso.com'
                $parsed.Devices[0].Block | Should -Be 1
                $parsed.Devices[1].NotConfigured | Should -Be 19
                $parsed.Findings.Count | Should -Be 5
            }
            finally {
                Remove-Item -LiteralPath $jsonPath -ErrorAction SilentlyContinue
            }
        }

        It 'Returns 1 with [-] output when the Graph module is not available' {
            Mock Get-Command -ParameterFilter { $Name -eq 'Connect-MgGraph' } { }
            . $scriptPath
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[\-\] Error: Microsoft\.Graph\.Authentication'
            Should -Invoke Invoke-MgGraphRequest -Exactly 0
        }

        It 'Returns the documented exit code 1 when the assessment call throws' {
            Mock Invoke-MgGraphRequest { throw 'Forbidden' }
            . $scriptPath
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[\-\] Error: Forbidden'
        }
    }
}
