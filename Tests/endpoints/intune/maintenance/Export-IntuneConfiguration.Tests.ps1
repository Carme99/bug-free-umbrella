#Requires -Modules Pester

Describe "Export-IntuneConfiguration.ps1" {
    BeforeAll {
        $scriptFile = Join-Path $PSScriptRoot `
            "../../../../scripts/endpoints/intune/maintenance/Export-IntuneConfiguration.ps1"
        $rawBytes = [System.IO.File]::ReadAllBytes($scriptFile)
        $rawText = [System.IO.File]::ReadAllText($scriptFile)

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptFile, [ref]$tokens, [ref]$parseErrors)

        # Placeholder definitions so Pester can Mock Graph cmdlets without the module installed.
        function Connect-MgGraph { }
        function Get-MgContext { }
        function Invoke-MgGraphRequest { param([string]$Uri, [string]$Method) }
        function Compress-Archive { }

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptFile

        # Mock every external surface at command-name level (offline).
        Mock Get-MgContext { [pscustomobject]@{ TenantId = 'tenant-1' } }
        Mock Connect-MgGraph { }
        Mock Compress-Archive { }

        function New-MockPolicy {
            param([string]$Id, [string]$Name)
            [pscustomobject]@{
                id = $Id
                displayName = $Name
                description = 'mock policy'
            }
        }
    }

    Context "Help & Metadata" {
        It "Starts with a UTF-8 BOM" {
            ($rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF) | Should -BeTrue
        }

        It "Has all five required .NOTES fields with relaunch values" {
            $rawText | Should -Match '\.NOTES'
            $rawText | Should -Match 'File Name:\s*Export-IntuneConfiguration\.ps1'
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
        It "Exports device configurations as JSON files and returns 0" {
            Mock Invoke-MgGraphRequest {
                @{ value = @(
                    New-MockPolicy -Id 'pol-1' -Name 'BitLocker Policy'
                    New-MockPolicy -Id 'pol-2' -Name 'Firewall Policy'
                ) }
            }

            $outDir = Join-Path $TestDrive "export-deviceconfig"
            $ConfigTypes = @('DeviceConfig')
            $OutputPath = $outDir

            Main | Should -Be 0

            $policyFiles = @(Get-ChildItem -Path (Join-Path $outDir "DeviceConfigurations") -Filter "*.json")
            $policyFiles.Count | Should -Be 2
            Test-Path (Join-Path $outDir "export-summary.json") | Should -BeTrue
        }

        It "Is idempotent: re-running the export over existing output still returns 0 with fresh files" {
            Mock Invoke-MgGraphRequest {
                @{ value = @(
                    New-MockPolicy -Id 'pol-1' -Name 'Compliance Baseline'
                ) }
            }

            $outDir = Join-Path $TestDrive "export-repeat"
            $ConfigTypes = @('Compliance')
            $OutputPath = $outDir

            Main | Should -Be 0
            Main | Should -Be 0

            $summary = Get-Content (Join-Path $outDir "export-summary.json") -Raw | ConvertFrom-Json
            $summary.ItemsExported | Should -Be 1
        }

        It "Returns 1 with [-] output when Graph authentication fails" {
            Mock Get-MgContext { }
            Mock Connect-MgGraph { throw "interactive login cancelled" }

            $outDir = Join-Path $TestDrive "export-authfail"
            $ConfigTypes = @('DeviceConfig')
            $OutputPath = $outDir

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
