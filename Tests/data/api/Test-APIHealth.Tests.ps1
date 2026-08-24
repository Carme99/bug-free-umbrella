#Requires -Modules Pester

Describe "Test-APIHealth" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/data/api/ -> script is two levels up.
        $scriptPath = [IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot "../../../scripts/data/api/Test-APIHealth.ps1"))
        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Run offline against throwaway paths; never touch user directories.
        $OutputFormat = 'Console'
        $OutputPath = Join-Path $TestDrive 'reports'
        $RunContinuous = $false
        $IntervalSeconds = 60
        $Method = 'GET'

        # All HTTP traffic goes through Invoke-WebRequest; mock it so nothing leaves the machine.
        Mock Invoke-WebRequest {
            [pscustomobject]@{ StatusCode = 200; Headers = @{} }
        }
    }

    Context "Help & Metadata" {
        BeforeAll {
            $raw = Get-Content -Raw -LiteralPath $scriptPath
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
            $raw | Should -Match 'File Name\s*:\s*Test-APIHealth\.ps1'
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
            @($functionNames).Count | Should -BeGreaterOrEqual 2
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
        It "Probes a single endpoint and returns 0 with [+]/[*] prefixed output" {
            $EndpointsFile = $null
            $SingleEndpoint = 'http://api.example.com/health'
            $ExpectedStatusCode = 200
            $MaxResponseTime = 2000

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Contain 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly
        }

        It "Tests every endpoint from an EndpointsFile and returns 0" {
            Mock Invoke-WebRequest {
                [pscustomobject]@{ StatusCode = 200; Headers = @{} }
            }   # fresh mock: resets call history

            $SingleEndpoint = $null
            $endpointsFile = Join-Path $TestDrive 'endpoints.json'
            @'
[
  { "Name": "Catalog", "Url": "http://api.example.com/catalog", "Method": "GET", "ExpectedStatusCode": 200 },
  { "Name": "Orders", "Url": "http://api.example.com/orders", "Method": "GET", "ExpectedStatusCode": 200 }
]
'@ | Set-Content -Path $endpointsFile -Encoding UTF8
            $EndpointsFile = $endpointsFile

            Main | Should -Be 0
            Should -Invoke Invoke-WebRequest -Times 2 -Exactly
        }

        It "Returns 1 and writes [-] prefixed output when no endpoint source is given" {
            Mock Invoke-WebRequest {
                [pscustomobject]@{ StatusCode = 200; Headers = @{} }
            }   # fresh mock: resets call history

            $EndpointsFile = $null
            $SingleEndpoint = $null

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It "Reports a status-code mismatch as a failed endpoint but still completes with 0" {
            $EndpointsFile = $null
            $SingleEndpoint = 'http://api.example.com/health'
            $ExpectedStatusCode = 200
            $MaxResponseTime = 2000
            Mock Invoke-WebRequest {
                [pscustomobject]@{ StatusCode = 500; Headers = @{} }
            }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Contain 0
            ($out | Out-String) | Should -Match '\[-\] Failed:.*Status code mismatch'
        }

        It "Returns 1 and writes [-] output when the endpoints file is missing" {
            $SingleEndpoint = $null
            $EndpointsFile = Join-Path $TestDrive 'nope.json'

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\].*not found'
        }
    }
}
