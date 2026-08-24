#Requires -Modules Pester

Describe "Compare-ConfigurationDrift.ps1" {
    BeforeAll {
        $scriptFile = Join-Path $PSScriptRoot `
            "../../../../scripts/endpoints/intune/maintenance/Compare-ConfigurationDrift.ps1"
        $rawBytes = [System.IO.File]::ReadAllBytes($scriptFile)
        $rawText = [System.IO.File]::ReadAllText($scriptFile)

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptFile, [ref]$tokens, [ref]$parseErrors)

        # Placeholder definitions so Pester can Mock commands without the module installed.
        function Invoke-MgGraphRequest { param([string]$Uri, [string]$Method) }
        function Connect-IntuneGraph { }

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptFile
        # Mock every external surface at command-name level (offline).
        # Single steerable mock: tests set $script:testDeviceConfigs to control the
        # snapshot payload (Pester resolves the first defined mock, so avoid re-mocking).
        $script:testDeviceConfigs = @(
            [pscustomobject]@{
                id = 'dc1'; displayName = 'DC One'; description = ''
                createdDateTime = '2026-01-01T00:00:00Z'
                lastModifiedDateTime = '2026-08-24T00:00:00Z'
                '@odata.type' = '#microsoft.graph.windows10GeneralConfiguration'
            }
        )
        Mock Invoke-MgGraphRequest {
            if ($Uri -like "*deviceConfigurations") {
                @{ value = $script:testDeviceConfigs }
            }
            else { @{ value = @() } }
        }
        Mock Connect-IntuneGraph { }
    }

    Context "Help & Metadata" {
        It "Starts with a UTF-8 BOM" {
            ($rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF) | Should -BeTrue
        }

        It "Has all five required .NOTES fields with relaunch values" {
            $rawText | Should -Match '\.NOTES'
            $rawText | Should -Match 'File Name:\s*Compare-ConfigurationDrift\.ps1'
            $rawText | Should -Match 'Author:\s*\S+'
            $rawText | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
            $rawText | Should -Match 'Version:\s*1\.0\.0'
            $rawText | Should -Match 'Date:\s*2026-08-23'
        }

        It "Has one .PARAMETER entry per declared parameter" {
            $paramCount = $ast.ParamBlock.Parameters.Count
            $helpParams = ([regex]::Matches($rawText, '(?m)^\.PARAMETER')).Count
            $paramCount | Should -Be 4
            $helpParams | Should -Be $paramCount
        }

        It "Has at least two examples with PS C:\> prompts" {
            ([regex]::Matches($rawText, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($rawText, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $parseErrors | Should -HaveCount 0
        }

        It "Contains no PS7-only operators" {
            $codeWithoutStrings = [regex]::Replace($rawText, '"[^"]*"|''[^'']*''|#[^\r\n]*', '')
            $codeWithoutStrings | Should -Not -Match '&&'
            $codeWithoutStrings | Should -Not -Match '\|\|'
            $codeWithoutStrings | Should -Not -Match '\?\?'
        }

        It "Defines a Main function" {
            $mainFn = $ast.Find({ param($a)
                $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Main'
            }, $false)
            $mainFn | Should -Not -BeNullOrEmpty
        }

        It "Has the dot-source guard and exit ONLY in the guard line" {
            @( $rawText -split "`r?`n" | Where-Object { $_ -cmatch '(^|[^\w])exit[ (\r\n]' } ).Count | Should -Be 1
            $guardLine = "if (`$MyInvocation.InvocationName -ne '.') { exit (Main) }"
            ($rawText -split "`r?`n") | Should -Contain $guardLine
        }
    }

    Context "Behavior" {
        It "Creates a baseline snapshot file and returns 0 with -CreateBaseline" {
            $outDir = Join-Path $TestDrive "baseline-out"
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null

            $CreateBaseline = $true
            $OutputPath = $outDir
            Main | Should -Be 0

            $baselineFiles = @(Get-ChildItem -Path $outDir -Filter "intune-baseline-*.json")
            $baselineFiles.Count | Should -Be 1
            $baselineContent = Get-Content $baselineFiles[0].FullName -Raw | ConvertFrom-Json
            $baselineContent.DeviceConfigurations | Should -Not -BeNullOrEmpty
        }

        It "Detects modified configuration against a baseline and writes a drift report" {
            $outDir = Join-Path $TestDrive "drift-out"
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null


            $baseline = @{
                CapturedDate = '2026-01-01 00:00:00'
                DeviceConfigurations = @(
                    @{ id = 'dc1'; displayName = 'DC One'; lastModifiedDateTime = '2026-01-01T00:00:00Z' }
                )
                CompliancePolicies = @()
                ConfigurationPolicies = @()
                Applications = @()
            }
            $baselineFile = Join-Path $outDir "baseline.json"
            $baseline | ConvertTo-Json -Depth 5 | Out-File -FilePath $baselineFile -Encoding UTF8

            $CreateBaseline = $false
            $BaselinePath = $baselineFile
            $OutputPath = $outDir
            Main | Should -Be 0

            $reportFiles = @(Get-ChildItem -Path $outDir -Filter "drift-report-*.json")
            $reportFiles.Count | Should -Be 1
            $report = Get-Content $reportFiles[0].FullName -Raw | ConvertFrom-Json
            $report.TotalChanges | Should -Be 1
            $report.Modified.DeviceConfigurations.Count | Should -Be 1
        }

        It "Is idempotent: identical baseline reports zero changes and still exits 0" {
            $outDir = Join-Path $TestDrive "converged-out"
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null

            # Step 1: capture a baseline from the current (mocked) tenant snapshot.
            $script:testDeviceConfigs = @(
                [pscustomobject]@{
                    id = 'dc1'; displayName = 'DC One'; description = ''
                    createdDateTime = '2026-01-01T00:00:00Z'
                    lastModifiedDateTime = '2026-08-24T00:00:00Z'
                    '@odata.type' = '#microsoft.graph.windows10GeneralConfiguration'
                }
            )
            $CreateBaseline = $true
            $OutputPath = $outDir
            Main | Should -Be 0

            # Step 2: compare against a freshly captured identical snapshot.
            $baselineFile = @(Get-ChildItem -Path $outDir -Filter "intune-baseline-*.json")[0].FullName
            $CreateBaseline = $false
            $BaselinePath = $baselineFile

            Main | Should -Be 0
            $reportFiles = @(Get-ChildItem -Path $outDir -Filter "drift-report-*.json")
            ($reportFiles.Count) | Should -BeGreaterOrEqual 1
            $latest = $reportFiles | Sort-Object Name | Select-Object -Last 1
            (Get-Content $latest.FullName -Raw | ConvertFrom-Json).TotalChanges | Should -Be 0
        }

        It "Returns 1 with [-] output when BaselinePath is missing and not creating a baseline" {
            $CreateBaseline = $false
            $BaselinePath = $null
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [-] output when the baseline file does not exist" {
            $CreateBaseline = $false
            $BaselinePath = Join-Path $TestDrive "does-not-exist.json"
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
