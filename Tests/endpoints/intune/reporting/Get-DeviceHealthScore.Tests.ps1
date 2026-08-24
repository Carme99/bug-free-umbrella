#Requires -Modules Pester

Describe "Get-DeviceHealthScore" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/intune/reporting/ -> script is
        # four levels up + across into scripts/.
        $scriptPath = [IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot "../../../../scripts/endpoints/intune/reporting/Get-DeviceHealthScore.ps1"))

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

        $script:healthyDevice = [pscustomobject]@{
            deviceName = 'PC-GOOD'; userPrincipalName = 'good@contoso.com'
            operatingSystem = 'Windows'; osVersion = '10.0.22631'
            complianceState = 'compliant'; isEncrypted = $true
            lastSyncDateTime = (Get-Date).AddDays(-1).ToString('o')
            deviceHealthAttestationState = $null
            serialNumber = 'SN-GOOD'; model = 'Model X'
            managementState = 'managed'
        }
        $script:poorDevice = [pscustomobject]@{
            deviceName = 'PC-BAD'; userPrincipalName = 'bad@contoso.com'
            operatingSystem = 'Windows'; osVersion = ''
            complianceState = 'noncompliant'; isEncrypted = $false
            lastSyncDateTime = (Get-Date).AddDays(-30).ToString('o')
            deviceHealthAttestationState = $null
            serialNumber = 'SN-BAD'; model = 'Model Y'
            managementState = 'retirepending'
        }

        Mock Get-AllIntuneDevices { @($script:healthyDevice, $script:poorDevice) }
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
            $raw | Should -Match 'File Name\s*:\s*Get-DeviceHealthScore\.ps1'
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
        It "Scores devices and writes a sorted CSV report, returning 0" {
            $OutputPath = Join-Path $TestDrive ([guid]::NewGuid().Guid)
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            $Format = 'CSV'

            Main | Should -Be 0
            Should -Invoke Get-AllIntuneDevices -Times 1 -Exactly

            $csvFile = Get-ChildItem -Path $OutputPath -Filter 'DeviceHealthScore-*.csv' | Select-Object -First 1
            $csvFile | Should -Not -BeNullOrEmpty
            $rows = @((Import-Csv -Path $csvFile.FullName))
            $rows.Count | Should -Be 2
            $rows[0].DeviceName | Should -Be 'PC-BAD'    # lowest score first
            $rows[0].HealthScore | Should -Be '0'
            $rows[1].DeviceName | Should -Be 'PC-GOOD'
            $rows[1].HealthScore | Should -Be '85'
        }

        It "Honours -MinHealthScore by excluding low-scoring devices from the report" {
            $OutputPath = Join-Path $TestDrive ([guid]::NewGuid().Guid)
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            $Format = 'CSV'
            $MinHealthScore = 50

            Main | Should -Be 0

            $csvFile = Get-ChildItem -Path $OutputPath -Filter 'DeviceHealthScore-*.csv' | Select-Object -First 1
            $rows = @((Import-Csv -Path $csvFile.FullName))
            $rows.Count | Should -Be 1
            $rows[0].DeviceName | Should -Be 'PC-GOOD'
        }

        It "Renders an HTML report through the helper exporter when Format is HTML" {
            $OutputPath = Join-Path $TestDrive ([guid]::NewGuid().Guid)
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            $Format = 'HTML'
            $MinHealthScore = 0

            Main | Should -Be 0
            Should -Invoke Export-IntuneReportToHTML -Times 1 -Exactly -ParameterFilter {
                $Title -eq 'Device Health Score Report'
            }
        }

        It "Handles an empty device list gracefully (converged/read-only re-run returns 0)" {
            $OutputPath = Join-Path $TestDrive ([guid]::NewGuid().Guid)
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            $Format = 'CSV'
            Mock Get-AllIntuneDevices { @() }

            Main | Should -Be 0
            Should -Invoke Connect-IntuneGraph -Times 1 -Exactly
        }

        It "Returns 1 and writes [-] prefixed output when device retrieval fails" {
            $OutputPath = Join-Path $TestDrive ([guid]::NewGuid().Guid)
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            $Format = 'HTML'
            Mock Get-AllIntuneDevices { throw 'graph unreachable' }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
