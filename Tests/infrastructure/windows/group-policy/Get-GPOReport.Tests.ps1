#Requires -Modules Pester

Describe "Get-GPOReport" {
    BeforeAll {
        $scriptRelPath = '../../../../scripts/infrastructure/windows/group-policy/Get-GPOReport.ps1'
        $scriptPath = Join-Path $PSScriptRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced. The validated
        # param must be supplied explicitly - dot-sourced param blocks do not read caller
        # variables, and MyDocuments is empty on Linux so the default fails validation.
        . $scriptPath -OutputPath (Join-Path $TestDrive 'pre-dot-output')
        # Local stubs for Windows-only module commands: they do not exist on Linux,
        # and Pester cannot mock a command that does not resolve.
        function Get-ADDomain { }
        function Get-GPO { }
        function Get-GPOReport { }
        function Save-GpoReport { }

        function New-FakeGpo {
            param([string]$Name)
            return [pscustomobject]@{
                Id               = [guid]::NewGuid()
                DisplayName      = $Name
                GpoStatus        = 'AllSettingsEnabled'
                CreationTime     = (Get-Date).AddDays(-100)
                ModificationTime = (Get-Date).AddDays(-5)
                WmiFilter        = $null
                Owner            = 'CONTOSO\Domain Admins'
                Computer         = [pscustomobject]@{ Enabled = $true; DSVersion = 3 }
                User             = [pscustomobject]@{ Enabled = $true; DSVersion = 2 }
            }
        }
        Mock -CommandName Get-ADDomain { [pscustomobject]@{ DNSRoot = 'contoso.com' } }
        Mock -CommandName Get-GPO { @(New-FakeGpo 'Baseline Security'; New-FakeGpo 'Unlinked Policy') }
        # This script requests the XML link report inline; per-GPO file reports go through
        # the Save-GpoReport wrapper, which is mocked separately.
        Mock -CommandName Get-GPOReport { '<GPO><LinksTo><Link SOMETHING="1"/></LinksTo></GPO>' }
        Mock -CommandName Save-GpoReport { }
    }

    Context "Help & Metadata" {
        It "Declares File Name matching the disk filename" {
            Get-Content -Raw $scriptPath | Should -Match 'File Name:\s*Get-GPOReport\.ps1'
        }

        It "Declares Version 1.0.0 and relaunch Date" {
            $helpText = Get-Content -Raw $scriptPath
            $helpText | Should -Match 'Version:\s*1\.0\.0'
            $helpText | Should -Match 'Date:\s*2026-08-23'
        }

        It "Has one .PARAMETER entry per declared parameter, in order" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $paramNames = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $paramMatches = [regex]::Matches(
                (Get-Content -Raw $scriptPath), '(?m)^\.PARAMETER\s+(\S+)')
            $declared = @($paramMatches | ForEach-Object { $_.Groups[1].Value })
            $declared.Count | Should -Be $paramNames.Count
            for ($i = 0; $i -lt $paramNames.Count; $i++) {
                $declared[$i] | Should -Be $paramNames[$i]
            }
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
            $errors.Count | Should -Be 0
        }

        It "Contains no PS7-only syntax without a #Requires -Version 7.0 opt-out" {
            $text = Get-Content -Raw $scriptPath
            if (-not ($text -match '(?m)^\s*#Requires\s+-Version\s+7\.0')) {
                $text | Should -Not -Match '\?\?'
                $text | Should -Not -Match '\|\|'
                $text | Should -Not -Match '&&'
                $text | Should -Not -Match '-Parallel\b'
            }
        }

        It "Is read-only with respect to Active Directory: no mutation cmdlets present" {
            (Get-Content -Raw $scriptPath) | Should -Not -Match '(?i)Remove-Item|New-GPO|Set-GPO|Remove-GPO|New-GPLink'
        }
    }

    Context "Behavior" {
        It "Generates per-GPO reports plus an index and returns 0" {
            $outDir = Join-Path $TestDrive 'gpo-reports'
            $OutputPath = $outDir
            $ReportFormat = 'Both'
            $IncludeUnlinkedGPOs = $false; $IncludeEmptyGPOs = $false; $ExportToCSV = $false

            Main | Should -Be 0
            Join-Path $outDir 'Index.html' | Should -Exist
            Should -Invoke Get-GPOReport -Times 2 -Exactly -Because "one XML link check per GPO"
            Should -Invoke Save-GpoReport -Times 4 -Exactly -Because "2 GPOs x (HTML + XML file report)"
        }
        It "Returns 1 with [-] output when domain discovery fails" {
            Mock -CommandName Get-ADDomain { throw 'domain controller unreachable' }
            $OutputPath = (Join-Path $TestDrive 'gpo-reports-fail')
            $ReportFormat = 'HTML'; $IncludeUnlinkedGPOs = $false; $IncludeEmptyGPOs = $false; $ExportToCSV = $false

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It "Exports a CSV summary when -ExportToCSV is set" {
            $outDir = Join-Path $TestDrive 'gpo-reports-csv'
            $OutputPath = $outDir
            $ReportFormat = 'XML'
            $IncludeUnlinkedGPOs = $false; $IncludeEmptyGPOs = $false; $ExportToCSV = $true

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            @(Get-ChildItem -Path $outDir -Filter 'GPO_Summary_*.csv').Count | Should -Be 1
        }

        It "Warns on unlinked GPOs when link reports show no links" {
            # Override the shared link-report mock: no LinksTo nodes means every GPO is unlinked.
            Mock -CommandName Get-GPOReport { '<GPO><Computer /><User /></GPO>' }
            $outDir = Join-Path $TestDrive 'gpo-reports-unlinked'
            $OutputPath = $outDir
            $ReportFormat = 'HTML'
            $IncludeUnlinkedGPOs = $false; $IncludeEmptyGPOs = $false; $ExportToCSV = $false

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[!\].*unlinked'
        }

        It "Is idempotent: re-running overwrites the index in place without error" {
            $outDir = Join-Path $TestDrive 'gpo-reports-idem'
            $OutputPath = $outDir
            $ReportFormat = 'HTML'; $IncludeUnlinkedGPOs = $false; $IncludeEmptyGPOs = $false; $ExportToCSV = $false

            Main | Should -Be 0
            Main | Should -Be 0
            Join-Path $outDir 'Index.html' | Should -Exist
        }
    }
}
