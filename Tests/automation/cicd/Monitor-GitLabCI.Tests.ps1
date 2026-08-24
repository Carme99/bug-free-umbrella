#Requires -Modules Pester

Describe "Monitor-GitLabCI" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/automation/cicd/Monitor-GitLabCI.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (spec section 3).
        . $scriptPath -GitLabUrl 'https://gitlab.example.test' -ProjectId 'grp/proj'

        $helpText = Get-Content -Raw $scriptPath

        # Isolated output directory; no real report ever leaves the test sandbox.
        $OutputPath = Join-Path $TestDrive 'reports'
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

        # Deterministic token so Main passes its credential guard offline.
        $PrivateToken = 'pester-token'

        # Pipelines fixture: one success, one failure on main -> 50% success rate.
        # PSCustomObject mirrors real Invoke-RestMethod output (hashtables would
        # make .Count return the number of keys instead of the element count).
        $mockPipelines = @(
            [pscustomobject]@{
                id         = 900
                ref        = 'main'
                status     = 'success'
                duration   = 300
                sha        = 'abcdef1234567890'
                created_at = (Get-Date).AddHours(-4).ToString('o')
                web_url    = 'https://gitlab.example.test/grp/proj/-/pipelines/900'
            }
            [pscustomobject]@{
                id         = 901
                ref        = 'main'
                status     = 'failed'
                duration   = 120
                sha        = '12345678abcdef90'
                created_at = (Get-Date).AddHours(-2).ToString('o')
                web_url    = 'https://gitlab.example.test/grp/proj/-/pipelines/901'
            }
        )

        # Mock every REST surface: nothing leaves the machine.
        Mock Invoke-RestMethod {
            if ($Uri -match '/projects/grp%2Fproj$') {
                return [pscustomobject]@{ id = 42; name = 'proj'; path_with_namespace = 'grp/proj' }
            }
            if ($Uri -match '/pipelines\?') { return $mockPipelines }
            if ($Uri -match '/deployments\?') { return @() }
            if ($Uri -match '/runners/all') { return @() }
            throw "Unexpected URI in test: $Uri"
        }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date 2026-08-23 in NOTES" {
            $helpText | Should -Match 'Version:\s*1\.0\.0'
            $helpText | Should -Match 'Date:\s*2026-08-23'
        }

        It "Names the disk file and preserves the original author in NOTES" {
            $helpText | Should -Match 'File Name:\s*Monitor-GitLabCI\.ps1'
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
        It "Analyzes pipelines via mocked REST calls and returns 0 with a JSON report" {
            $OutputFormat = 'JSON'
            $rc = Main *>&1 | Where-Object { $_ -is [int] }
            $rc | Should -Be 0

            # One project-lookup call + one pipelines call for the single project.
            Should -Invoke Invoke-RestMethod -Times 2 -Exactly

            $report = Get-ChildItem $OutputPath -Filter 'GitLab-Pipelines-*.json' | Select-Object -First 1
            $report | Should -Not -BeNullOrEmpty
            $parsed = Get-Content -Raw $report.FullName | ConvertFrom-Json
            $parsed.Summary.TotalPipelines | Should -Be 1
            $parsed.Pipelines[0].SuccessRate | Should -Be 50
            $parsed.Pipelines[0].Status | Should -Be 'Critical'
        }

        It "Returns 0 when the project has no recent pipelines (nothing to analyze)" {
            Mock Invoke-RestMethod {
                if ($Uri -match '/projects/grp%2Fproj$') {
                    return [pscustomobject]@{ id = 42; name = 'proj'; path_with_namespace = 'grp/proj' }
                }
                if ($Uri -match '/pipelines\?') { return @() }
                throw "Unexpected URI in test: $Uri"
            }
            Main | Should -Be 0
        }

        It "Returns 1 and writes [-] prefixed output when the token is missing" {
            $PrivateToken = ''
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
