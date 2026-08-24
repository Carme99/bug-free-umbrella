#Requires -Modules Pester

Describe "Get-WingetUpdateCompliance" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/intune/reporting/Get-WingetUpdateCompliance.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # External commands mocked by name (works offline without the Graph SDK).
        function Get-MgContext { }
        function Connect-MgGraph { }
        function Get-MgDeviceManagementManagedDevice { @() }

        Mock Import-Module { }
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $fileName = Split-Path $scriptPath -Leaf
            $raw | Should -Match ("File Name:\s*" + [regex]::Escape($fileName))
            $raw | Should -Match 'Author:\s*\S'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
        }

        It "Has SYNOPSIS, DESCRIPTION and at least two EXAMPLES" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Synopsis.Length | Should -BeLessOrEqual 120
            $help.Description | Should -Not -BeNullOrEmpty
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
        }

        It "Declares one .PARAMETER per param() parameter" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
            $declared = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $documented = @((Get-Help $scriptPath).Parameters.Parameter.Name)
            $declared.Count | Should -Be $documented.Count
            foreach ($p in $declared) { $documented | Should -Contain $p }
        }
    }

    Context "Syntax & Static" {
        BeforeAll {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        }
        It "Parses with zero errors" {
            $errors | Should -BeNullOrEmpty
        }
        It "Contains no PS7-only operators (no #Requires -Version 7.0 opt-out present)" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Not -Match '(?m)&&|\|\||\?\?|\?\?='
            $raw | Should -Not -Match '\$\w+\s*\?\s*[^:]'
        }
    }

    Context "Behavior" {
        It "Connects to Graph, builds the sample report and returns 0" {
            Mock Get-MgContext { $null }
            Mock Connect-MgGraph { }
            Mock Get-MgDeviceManagementManagedDevice { @() }

            $ExportHTML = $false
            $ExportCSV = $false

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            $text | Should -Match '\[\+\]'
            $text | Should -Match 'SAMPLE DATA'
            Should -Invoke Connect-MgGraph -Exactly 1
            Should -Invoke Import-Module -Exactly 2
        }

        It "Skips Connect-MgGraph when an existing Graph context is present" {
            Mock Get-MgContext { [pscustomobject]@{ TenantId = '11111111-1111-1111-1111-111111111111' } }
            Mock Connect-MgGraph { }
            Mock Get-MgDeviceManagementManagedDevice { @() }

            $ExportHTML = $false
            $ExportCSV = $false

            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Connect-MgGraph -Exactly 0
        }

        It "Applies the application filter to the sample data" {
            Mock Get-MgContext { $null }
            Mock Connect-MgGraph { }
            Mock Get-MgDeviceManagementManagedDevice { @() }

            $ApplicationFilter = '*Chrome*'
            $ExportHTML = $false
            $ExportCSV = $false

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match 'Total Applications: 1'
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
        }

        It "Exports an HTML report when -ExportHTML is set" {
            Mock Get-MgContext { $null }
            Mock Connect-MgGraph { }
            Mock Get-MgDeviceManagementManagedDevice { @() }
            Mock Out-File { }

            $ExportHTML = $true
            $ExportCSV = $false

            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Out-File -Exactly 1
        }

        It "Exports a CSV report when -ExportCSV is set" {
            Mock Get-MgContext { $null }
            Mock Connect-MgGraph { }
            Mock Get-MgDeviceManagementManagedDevice { @() }
            Mock Export-Csv { }

            $ExportHTML = $false
            $ExportCSV = $true

            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Export-Csv
        }

        It "Returns 1 and writes [-] prefixed output when Graph connection fails" {
            Mock Get-MgContext { $null }
            Mock Connect-MgGraph { throw "Authentication failed" }
            Mock Get-MgDeviceManagementManagedDevice { @() }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
