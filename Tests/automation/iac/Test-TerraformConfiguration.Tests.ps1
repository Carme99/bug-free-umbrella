#Requires -Modules Pester

Describe "Test-TerraformConfiguration" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/automation/iac/ -> script is two levels up.
        $scriptPath = [IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot "../../../scripts/automation/iac/Test-TerraformConfiguration.ps1"))

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        # Mandatory parameters need a value at dot-source time; tests override via scope below.
        . $scriptPath -ConfigPath (Join-Path $TestDrive 'placeholder')

        # Run offline against throwaway paths; never touch user directories.
        $OutputFormat = 'Console'
        $OutputPath = Join-Path $TestDrive 'reports'
        $IncludePlan = $false
        $IncludeSecurityScan = $false
        $ConfigPath = Join-Path $TestDrive 'tf-config'
        New-Item -ItemType Directory -Path $ConfigPath -Force | Out-Null

        # Native exes are only invoked through wrapper functions; mock the wrappers,
        # never terraform/tfsec themselves (Pester cannot mock native commands).
        Mock Invoke-TerraformCli {
            param($ArgumentList)
            switch ($ArgumentList[0]) {
                'version' { [pscustomobject]@{ ExitCode = 0; Output = @('Terraform v1.9.8') } }
                'init' { [pscustomobject]@{ ExitCode = 0; Output = @('Terraform has been successfully initialized!') } }
                'fmt' { [pscustomobject]@{ ExitCode = 0; Output = @() } }
                'validate' {
                    [pscustomobject]@{
                        ExitCode = 0
                        Output = (@{ valid = $true; diagnostics = @() } | ConvertTo-Json -Compress)
                    }
                }
                default { [pscustomobject]@{ ExitCode = 0; Output = @() } }
            }
        }
        Mock Invoke-TfsecCli {
            [pscustomobject]@{ ExitCode = 0; Output = (@{ results = @() } | ConvertTo-Json -Compress) }
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
            $raw | Should -Match 'File Name\s*:\s*Test-TerraformConfiguration\.ps1'
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

        It "Wraps the body in Main and keeps exit in the dot-source guard only" {
            $exitLines = @((Get-Content -LiteralPath $scriptPath) | Where-Object { $_ -match '\bexit\b' })
            @($exitLines).Count | Should -Be 1
            $exitLines[0] | Should -Match '\$MyInvocation\.InvocationName'
            Get-Content -Raw -LiteralPath $scriptPath | Should -Match 'function Main'
        }
    }

    Context "Behavior" {
        It "Runs init/fmt/validate via the CLI wrappers and returns 0 on a clean config" {
            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Contain 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Invoke-TerraformCli -Times 4 -Exactly -Because "version + init + fmt + validate"
            Should -Invoke Invoke-TfsecCli -Times 0 -Exactly
        }

        It "Is idempotent: a second identical run also returns 0 with the same probe count" {
            Mock Invoke-TerraformCli {
                param($ArgumentList)
                switch ($ArgumentList[0]) {
                    'version' { [pscustomobject]@{ ExitCode = 0; Output = @('Terraform v1.9.8') } }
                    'init' { [pscustomobject]@{ ExitCode = 0; Output = @('ok') } }
                    'fmt' { [pscustomobject]@{ ExitCode = 0; Output = @() } }
                    'validate' {
                        $payload = @{ valid = $true; diagnostics = @() } | ConvertTo-Json -Compress
                        [pscustomobject]@{ ExitCode = 0; Output = $payload }
                    }
                    default { [pscustomobject]@{ ExitCode = 0; Output = @() } }
                }
            }   # fresh mock: resets call history

            Main | Should -Be 0
            Main | Should -Be 0
            Should -Invoke Invoke-TerraformCli -Times 8 -Exactly -Because "two runs x four probes"
        }

        It "Returns 1 and writes [-] prefixed output when the Terraform CLI is missing" {
            Mock Invoke-TerraformCli { [pscustomobject]@{ ExitCode = 127; Output = @('terraform: not found') } }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 and writes [-] output when the configuration path does not exist" {
            $missingConfig = Join-Path $TestDrive 'does-not-exist'
            $out = & { $ConfigPath = $missingConfig; Main }*>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It "Reports validation failure diagnostics but still completes with return code 0" {
            Mock Invoke-TerraformCli {
                param($ArgumentList)
                switch ($ArgumentList[0]) {
                    'version' { [pscustomobject]@{ ExitCode = 0; Output = @('Terraform v1.9.8') } }
                    'init' { [pscustomobject]@{ ExitCode = 0; Output = @('ok') } }
                    'fmt' { [pscustomobject]@{ ExitCode = 1; Output = @('main.tf') } }
                    'validate' {
                        $payload = @{
                            valid = $true
                            diagnostics = @()
                        } | ConvertTo-Json -Compress
                        [pscustomobject]@{ ExitCode = 0; Output = $payload }
                    }
                    default { [pscustomobject]@{ ExitCode = 0; Output = @() } }
                }
            }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Contain 0
            ($out | Out-String) | Should -Match '\[!\] Some files need formatting'
        }

        It "Rejects an unsafe OutputPath with return code 1 before touching the filesystem" {
            $unsafePath = "$TestDrive/../evil-reports"
            $out = & { $OutputPath = $unsafePath; Main }*>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\].*Unsafe OutputPath'
        }
    }
}
