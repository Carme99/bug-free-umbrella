#Requires -Modules Pester

Describe "Monitor-AzureDevOpsPipelines" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/automation/cicd/Monitor-AzureDevOpsPipelines.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (spec section 3).
        . $scriptPath -Organization 'testorg' -Project 'ProjOne'

        $helpText = Get-Content -Raw $scriptPath

        # Isolated output directory; no real report ever leaves the test sandbox.
        $OutputPath = Join-Path $TestDrive 'reports'
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

        # Deterministic PAT so Main passes its credential guard offline.
        $env:AZURE_DEVOPS_PAT = 'pester-pat'

        # Recent runs fixture: one succeeded, one failed -> 50% success rate.
        # PSCustomObject mirrors real Invoke-RestMethod output (hashtables would
        # make .Count return the number of keys instead of the element count).
        $mockRuns = @(
            [pscustomobject]@{
                id           = 1
                createdDate  = (Get-Date).AddHours(-2).ToString('o')
                state        = 'completed'
                result       = 'succeeded'
                finishedDate = (Get-Date).AddMinutes(-90).ToString('o')
                _links       = @{ web = @{ href = 'https://dev.azure.com/testorg/run/1' } }
            }
            [pscustomobject]@{
                id           = 2
                createdDate  = (Get-Date).AddHours(-1).ToString('o')
                state        = 'completed'
                result       = 'failed'
                finishedDate = (Get-Date).AddMinutes(-30).ToString('o')
                _links       = @{ web = @{ href = 'https://dev.azure.com/testorg/run/2' } }
            }
        )

        # Mock every REST surface: nothing leaves the machine.
        Mock Invoke-RestMethod {
            if ($Uri -match '/_apis/pipelines\?') {
                return @{ value = @([pscustomobject]@{ id = 101; name = 'build-api'; folder = '\' }) }
            }
            if ($Uri -match '/runs\?api-version=') { return @{ value = $mockRuns } }
            if ($Uri -match '/distributedtask/pools') { return @{ value = @() } }
            if ($Uri -match 'vsrm\.dev\.azure\.com') { return @{ value = @() } }
            throw "Unexpected URI in test: $Uri"
        }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date 2026-08-23 in NOTES" {
            $helpText | Should -Match 'Version:\s*1\.0\.0'
            $helpText | Should -Match 'Date:\s*2026-08-23'
        }

        It "Names the disk file and preserves the original author in NOTES" {
            $helpText | Should -Match 'File Name:\s*Monitor-AzureDevOpsPipelines\.ps1'
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
        It "Analyzes pipelines via mocked REST calls and returns 0 with an HTML report" {
            $rc = Main *>&1 | Where-Object { $_ -is [int] }
            $rc | Should -Be 0

            # One pipelines-list call + one runs call for the single project.
            Should -Invoke Invoke-RestMethod -Times 2 -Exactly

            $report = Get-ChildItem $OutputPath -Filter 'AzureDevOps-Pipeline-Health-*.html' | Select-Object -First 1
            $report | Should -Not -BeNullOrEmpty
        }

        It "Returns 0 when a pipeline has no recent runs (nothing to analyze)" {
            Mock Invoke-RestMethod {
                if ($Uri -match '/_apis/pipelines\?') {
                    return @{ value = @([pscustomobject]@{ id = 202; name = 'idle-pipeline'; folder = '\' }) }
                }
                if ($Uri -match '/runs\?api-version=') { return @{ value = @() } }
                throw "Unexpected URI in test: $Uri"
            }
            Main | Should -Be 0
        }

        It "Returns 1 and writes [-] prefixed output when the PAT is missing" {
            $savedPat = $env:AZURE_DEVOPS_PAT
            $env:AZURE_DEVOPS_PAT = ''
            try {
                $out = Main *>&1
                ($out | Where-Object { $_ -is [int] }) | Should -Be 1
                ($out | Out-String) | Should -Match '\[-\]'
            }
            finally {
                $env:AZURE_DEVOPS_PAT = $savedPat
            }
        }
    }
}
