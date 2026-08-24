#Requires -Modules Pester

Describe "Test-BicepTemplates" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/automation/iac/ -> script is two levels up.
        $scriptPath = [IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot "../../../scripts/automation/iac/Test-BicepTemplates.ps1"))
        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        # Mandatory parameters need a value at dot-source time; tests override via scope below.
        . $scriptPath -TemplatePath (Join-Path $TestDrive 'placeholder')

        # Run offline against throwaway paths; never touch user directories.
        $OutputFormat = 'Console'
        $OutputPath = Join-Path $TestDrive 'reports'

        # Native exes are only invoked through wrapper functions; mock the wrappers, never bicep/az.
        Mock Invoke-BicepCli {
            [pscustomobject]@{ ExitCode = 0; Output = @('Bicep CLI version 0.26.54') }
        }
        Mock Invoke-AzCli {
            [pscustomobject]@{ ExitCode = 0; Output = @('Resource and property changes are indicated with this symbol') }
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
            $raw | Should -Match 'File Name\s*:\s*Test-BicepTemplates\.ps1'
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
        It "Validates a discovered template and returns 0 with [+]/[*] prefixed output" {
            Mock Test-Path { $true }
            Mock Get-ChildItem {
                @([pscustomobject]@{ Name = 'main.bicep'; FullName = '/repo/templates/main.bicep' })
            }
            Mock Get-Content {
                "param location string`nresource web 'Microsoft.Web/sites' {`n  tags: { env = 'test' }`n}"
            }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Contain 0
            ($out | Out-String) | Should -Match '\[\+\]'
            ($out | Out-String) | Should -Match '\[\*\]'
            Should -Invoke Invoke-BicepCli -Times 3 -Exactly -Because "--version probe plus build and lint per template"
        }

        It "Is idempotent: a second identical run also returns 0" {
            Mock Test-Path { $true }
            Mock Get-ChildItem {
                @([pscustomobject]@{ Name = 'main.bicep'; FullName = '/repo/templates/main.bicep' })
            }
            Mock Get-Content { "param location string`nresource web 'x' {`n  tags: {}`n}" }

            Main | Should -Be 0
            Main | Should -Be 0
        }

        It "Returns 1 and writes [-] prefixed output when the template path does not exist" {
            Mock Test-Path { $false }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 and writes [-] output when the Bicep CLI probe fails" {
            Mock Test-Path { $true }
            Mock Invoke-BicepCli { [pscustomobject]@{ ExitCode = 9003; Output = @('bicep: command not found') } }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
            Should -Invoke Invoke-AzCli -Times 0 -Exactly
        }

        It "Surfaces lint findings as [!] warnings while still completing successfully" {
            Mock Test-Path { $true }
            Mock Get-ChildItem {
                @([pscustomobject]@{ Name = 'main.bicep'; FullName = '/repo/templates/main.bicep' })
            }
            Mock Get-Content { "param location string`nresource web 'x' {`n  tags: {}`n}" }
            Mock Invoke-BicepCli {
                param($ArgumentList)
                if ($ArgumentList[0] -eq 'lint') {
                    [pscustomobject]@{ ExitCode = 0; Output = @('WARNING: use a recent API version') }
                }
                else {
                    [pscustomobject]@{ ExitCode = 0; Output = @('Bicep CLI version 0.26.54') }
                }
            }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Contain 0
            ($out | Out-String) | Should -Match '\[!\] Lint:'
        }
    }
}
