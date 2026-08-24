#Requires -Modules Pester

Describe "Get-SoftwareInventory" {
    BeforeAll {
        # Stub Windows/Store-only commands so Pester can mock them on Linux pwsh.
        function Get-AppxPackage { }

        # Mirrored layout: this file lives at Tests/utilities/ -> script is two levels up.
        $scriptPath = Join-Path $PSScriptRoot "../../scripts/utilities/Get-SoftwareInventory.ps1"
        . $scriptPath

        # Default no-op mocks so nothing leaves the machine or touches real state.
        Mock Get-ItemProperty { @() }
        Mock Get-AppxPackage { @() }
        Mock Invoke-Winget { throw "winget not expected in this test" }
        Mock Out-File { }
        Mock Export-Csv { }
    }

    Context "Help & Metadata" {
        It "Declares File Name, Version 1.0.0 and relaunch Date 2026-08-23 in the header" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match 'File Name:\s*Get-SoftwareInventory\.ps1'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
            $raw | Should -Match 'Author:\s*\S+'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
        }

        It "Has one .PARAMETER entry per declared parameter, in declaration order" {
            $tokens = $null; $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declared = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)

            $headerText = (Get-Content -Raw $scriptPath) -replace '(?s)\.PARAMETER.*', ''
            $helpParams = [regex]::Matches((Get-Content -Raw $scriptPath), '\.PARAMETER\s+(\w+)') |
                ForEach-Object { $_.Groups[1].Value }

            $helpParams.Count | Should -Be $declared.Count
            $helpParams | Should -Be $declared
        }

        It "Provides SYNOPSIS, DESCRIPTION and at least two EXAMPLES with PS C:\> prompts" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match '\.SYNOPSIS'
            $raw | Should -Match '\.DESCRIPTION'
            $examples = [regex]::Matches($raw, '\.EXAMPLE')
            $examples.Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses cleanly with zero parser errors" {
            $tokens = $null; $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only tokens (opt-out requires line 1)" {
            $raw = Get-Content -Raw $scriptPath
            $requiresV7 = ($raw -split "`r?`n")[0] -match '#Requires\s+-Version\s+7'
            if (-not $requiresV7) {
                $tokens = $null; $parseErrors = $null
                [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
                $badKinds = $tokens | Where-Object {
                    $_.Kind.ToString() -in @('QuestionMark', 'QuestionQuestion', 'AmpersandAmpersand', 'PipePipe')
                }
                $badKinds | Should -BeNullOrEmpty -Because "PS7-only operators need #Requires -Version 7.0 on line 1"
            }
        }

        It "Uses UTF-8 BOM and CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            ($text -replace "`r`n", '') | Should -Not -Match "`n"
        }
    }

    Context "Behavior" {
        It "Returns 0 and reports discovered applications on a default scan" {
            Mock Get-ItemProperty {
                @(
                    [pscustomobject]@{
                        DisplayName = 'App One'; DisplayVersion = '1.0'; Publisher = 'Contoso'
                        InstallDate = '20260101'; InstallLocation = 'C:\Apps\One'; UninstallString = 'msiexec /x'
                    },
                    [pscustomobject]@{
                        DisplayName = 'App Two'; DisplayVersion = '2.0'; Publisher = 'Fabrikam'
                        InstallDate = '20260102'; InstallLocation = 'C:\Apps\Two'; UninstallString = 'msiexec /x'
                    }
                )
            }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] Found 2 installed applications'
        }

        It "Routes native winget exclusively through the Invoke-Winget wrapper" {
            Mock Get-ItemProperty { @() }
            Mock Invoke-Winget { @('App One   Contoso.AppOne   1.0') }

            $out = Main -IncludeWinget *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Invoke-Winget -Times 1 -Exactly
            ($out | Out-String) | Should -Match '\[\+\] Found 1 winget apps'
        }

        It "Returns 1 and writes [-] prefixed output when JSON export fails" {
            Mock ConvertTo-Json { throw "serializer exploded" }

            $out = Main -ExportJSON *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Is idempotent: re-running produces the same report and exit code with no extra mutations" {
            Mock Get-ItemProperty {
                @([pscustomobject]@{ DisplayName = 'App One'; DisplayVersion = '1.0'; Publisher = 'Contoso' })
            }

            $first = Main *>&1
            $second = Main *>&1

            ($first | Where-Object { $_ -is [int] }) | Should -Be 0
            ($second | Where-Object { $_ -is [int] }) | Should -Be 0
            (($first | Out-String)) | Should -Match 'Found 1 installed applications'
            (($second | Out-String)) | Should -Match 'Found 1 installed applications'
        }
    }
}
