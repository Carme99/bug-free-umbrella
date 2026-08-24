#Requires -Modules Pester

Describe "Analyze-BuildPerformance" {
    BeforeAll {

        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/automation/cicd/Analyze-BuildPerformance.ps1"

        $helpText = Get-Content -Raw $scriptPath
        . $scriptPath -Platform 'AzureDevOps' -DataSource 'placeholder.json'

        # Isolated output directory; no real report ever leaves the test sandbox.
        $OutputPath = Join-Path $TestDrive 'reports'
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

        # Build a deterministic build-history fixture: 6 baseline builds (~20 days old,
        # 10 min each) plus two recent builds, one of which is a clear regression.
        $baseline = 1..6 | ForEach-Object {
            @{
                BuildId         = "baseline-$_"
                StartTime       = (Get-Date).AddDays(-20).ToString('o')
                DurationMinutes = 10
                Result          = 'Success'
                Branch          = 'main'
            }
        }
        $recent = @(
            @{ BuildId = 'recent-ok';   StartTime = (Get-Date).AddDays(-1).ToString('o'); DurationMinutes = 10; Result = 'Success'; Branch = 'main' }
            @{ BuildId = 'recent-slow'; StartTime = (Get-Date).AddDays(-1).ToString('o'); DurationMinutes = 30; Result = 'Failed';  Branch = 'feature/x' }
        )
        $dataFile = Join-Path $TestDrive 'builds.json'
        ($baseline + $recent) | ConvertTo-Json | Set-Content -Path $dataFile

        $DataSource = $dataFile
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date 2026-08-23 in NOTES" {
            $helpText | Should -Match 'Version:\s*1\.0\.0'
            $helpText | Should -Match 'Date:\s*2026-08-23'
        }

        It "Names the disk file and preserves the original author in NOTES" {
            $helpText | Should -Match 'File Name:\s*Analyze-BuildPerformance\.ps1'
            $helpText | Should -Match 'Author:\s*IT Operations'
            $helpText | Should -Match 'Prerequisite:'
        }

        It "Documents every declared parameter, in declaration order" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref] $null, [ref] $null)
            $declaredParams = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
            $documentedParams = [regex]::Matches($helpText, '(?m)^\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value }
            $documentedParams | Should -Be $declaredParams
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref] $tokens, [ref] $parseErrors) | Out-Null
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Uses no PS7-only syntax (targets PowerShell 5.1+)" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Not -Match '\?\?'
            $raw | Should -Not -Match '&&|\|\|'
            $raw | Should -Not -Match '#Requires -Version 7\.0'
        }

        It "Is UTF-8 BOM encoded with CRLF line endings only" {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            $text = [Text.Encoding]::UTF8.GetString($bytes)
            ([regex]::Matches($text, "(?<!`r)`n")).Count | Should -Be 0
        }

        It "Has no trailing whitespace and stays within 120 columns" {
            foreach ($line in (Get-Content $scriptPath)) {
                $line | Should -Not -Match '[ \t]$'
                $line.Length | Should -BeLessOrEqual 120
            }
        }
    }

    Context "Behavior" {
        It "Analyzes build data and returns 0 while writing a JSON report" {
            $OutputFormat = 'JSON'
            $rc = Main *>&1 | Where-Object { $_ -is [int] }
            $rc | Should -Be 0

            $report = Get-ChildItem $OutputPath -Filter 'Build-Performance-*.json' | Select-Object -First 1
            $report | Should -Not -BeNullOrEmpty
            $analysis = Get-Content -Raw $report.FullName | ConvertFrom-Json
            $analysis.Summary.TotalBuilds | Should -Be 8
        }

        It "Flags recent builds slower than baseline when -IdentifyRegressions is set" {
            $OutputFormat = 'JSON'
            $IdentifyRegressions = $true
            $RegressionThreshold = 25
            Main | Should -Be 0

            $report = Get-ChildItem $OutputPath -Filter 'Build-Performance-*.json' |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $analysis = Get-Content -Raw $report.FullName | ConvertFrom-Json
            $analysis.Summary.RegressionsFound | Should -BeGreaterOrEqual 1
            $analysis.Regressions.BuildId | Should -Contain 'recent-slow'
        }

        It "Is idempotent: re-running on the same inputs returns 0 again" {
            $OutputFormat = 'JSON'
            Main | Should -Be 0
            Main | Should -Be 0
        }

        It "Returns 1 and writes [-] prefixed output when the data source is missing" {
            $DataSource = Join-Path $TestDrive 'does-not-exist.json'
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
