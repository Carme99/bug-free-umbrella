#Requires -Modules Pester

Describe "Find-GPOConflicts" {
    BeforeAll {
        $scriptRelPath = '../../../../scripts/infrastructure/windows/group-policy/Find-GPOConflicts.ps1'
        $scriptPath = Join-Path $PSScriptRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Local stubs for ActiveDirectory/GroupPolicy module commands: they do not exist
        # on Linux, and Pester cannot mock a command that does not resolve.
        function Get-ADDomain { }
        function Get-GPO { }
        function Get-GPOReport { }
        function Get-GPPermissions { }
        function Get-ADOrganizationalUnit { }
        function Get-GPInheritance { }

        function New-FakeGpo {
            param([string]$Name)
            return [pscustomobject]@{
                Id               = [guid]::NewGuid()
                DisplayName      = $Name
                GpoStatus        = 'AllSettingsEnabled'
                WmiFilter        = $null
                Computer         = [pscustomobject]@{ Enabled = $true; DSVersion = 3 }
                User             = [pscustomobject]@{ Enabled = $true; DSVersion = 2 }
            }
        }

        $gpoXmlNoLoopback = '<GPO><Computer><ExtensionData Name="Registry"/></Computer><LinksTo></LinksTo></GPO>'

        # Mock -CommandName ALL external commands/modules so nothing touches a real domain.
        Mock -CommandName Get-ADDomain { [pscustomobject]@{ DNSRoot = 'contoso.com' } }
        Mock -CommandName Get-GPO { @(New-FakeGpo 'Baseline Security'; New-FakeGpo 'Drive Maps') }
        Mock -CommandName Get-GPOReport { $gpoXmlNoLoopback }
        Mock -CommandName Get-GPPermissions {
            @([pscustomobject]@{
                    Trustee   = [pscustomobject]@{ Name = 'Authenticated Users' }
                    Permission = 'GpoApply'
                    Denied    = $false
                })
        }
        Mock -CommandName Get-ADOrganizationalUnit { @() }
        Mock -CommandName Get-GPInheritance { [pscustomobject]@{ GpoLinks = @() } }
    }

    Context "Help & Metadata" {
        It "Declares File Name matching the disk filename" {
            Get-Content -Raw $scriptPath | Should -Match 'File Name:\s*Find-GPOConflicts\.ps1'
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

        It "Is read-only: contains no Remove-Item or other destructive mutation calls" {
            (Get-Content -Raw $scriptPath) | Should -Not -Match '(?i)Remove-Item|Stop-Service|Set-GPO|Remove-GPO'
        }
    }

    Context "Behavior" {
        It "Analyzes a clean domain, exports reports, and returns 0" {
            $outDir = Join-Path $TestDrive 'conflicts-clean'
            $Scope = 'Domain'; $TargetOU = $null
            $OutputPath = $outDir
            $IncludeInheritance = $false; $CheckDuplicateSettings = $false

            Main | Should -Be 0
            (Join-Path $outDir 'GPOConflictsReport.html') | Should -Exist
            @(Get-ChildItem -Path $outDir -Filter 'GPOConflicts_*.csv').Count | Should -Be 1
        }

        It "Flags duplicate GPO names as High severity findings" {
            Mock -CommandName Get-GPO { @(New-FakeGpo 'Same Name'; New-FakeGpo 'Same Name') }
            $outDir = Join-Path $TestDrive 'conflicts-dupes'
            $Scope = 'Domain'; $OutputPath = $outDir; $TargetOU = $null
            $IncludeInheritance = $false; $CheckDuplicateSettings = $false

            Main | Should -Be 0
            $csv = (Get-ChildItem -Path $outDir -Filter 'GPOConflicts_*.csv' | Select-Object -First 1)
            $csv | Should -Not -BeNullOrEmpty
            (Get-Content -Raw $csv.FullName) | Should -Match 'Duplicate GPO Names'
        }

        It "Returns 1 with [-] output when domain discovery fails" {
            Mock -CommandName Get-ADDomain { throw 'domain controller unreachable' }
            $Scope = 'Domain'; $OutputPath = (Join-Path $TestDrive 'conflicts-fail'); $TargetOU = $null
            $IncludeInheritance = $false; $CheckDuplicateSettings = $false

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
