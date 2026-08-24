#Requires -Modules Pester

Describe "Get-LargeFilesReport" {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../../../..')
        $scriptPath = Join-Path $repoRoot 'scripts/infrastructure/windows/storage/Get-LargeFilesReport.ps1'
        . $scriptPath
        $helpText = Get-Content -Raw $scriptPath
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)

        # Stub Windows-only commands absent on Linux so Pester can attach mocks.
        foreach ($stub in @('Get-Volume')) {
            if (-not (Get-Command $stub -ErrorAction SilentlyContinue)) {
                Invoke-Expression "function $stub { }"
            }
        }
        # Shadow Get-ChildItem unconditionally: its provider dynamic parameters
        # (-File/-Directory) are rejected by Pester's mock proxy functions.
        function Get-ChildItem { }



        function New-MockLargeFile {
            param([string]$FullName = 'C:\Data\big.vhd')
            $name = Split-Path $FullName -Leaf
            [PSCustomObject]@{
                FullName = $FullName
                DirectoryName = Split-Path $FullName -Parent
                Name = $name
                Extension = [System.IO.Path]::GetExtension($name)
                Length = 500MB
                CreationTime = (Get-Date).AddDays(-30)
                LastWriteTime = (Get-Date).AddDays(-10)
                LastAccessTime = (Get-Date)
            }
        }

        Mock -CommandName Test-Path { $false }
        Mock -CommandName Test-Path { $true } -ParameterFilter { $LiteralPath }
        Mock -CommandName Out-File { }
        Mock -CommandName Get-Volume {
            @([PSCustomObject]@{ DriveLetter = 'C'; DriveType = 'Fixed' })
        }
        Mock -CommandName Get-ChildItem { @(New-MockLargeFile) }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date" {
            $helpText | Should -Match 'Version\s*:\s*1\.0\.0'
            $helpText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Declares matching File Name, Author and Prerequisite" {
            $helpText | Should -Match ('File Name\s*:\s*' + [regex]::Escape('Get-LargeFilesReport.ps1'))
            $helpText | Should -Match 'Author\s*:\s*\S+'
            $helpText | Should -Match 'Prerequisite\s*:\s*PowerShell'
        }

        It "Has one .PARAMETER entry per declared parameter, in order" {
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $documented = @([regex]::Matches($helpText, '(?m)^\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value })
            $documented | Should -Be $declared
        }

        It "Has SYNOPSIS, DESCRIPTION and at least two PS C:\> examples" {
            $helpText | Should -Match '(?m)^\.SYNOPSIS'
            $helpText | Should -Match '(?m)^\.DESCRIPTION'
            ([regex]::Matches($helpText, '(?m)^    PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It "Contains no PS7-only syntax without a #Requires -Version 7.0 opt-in" {
            if ($helpText -notmatch '(?m)^#Requires\s+-Version\s+7') {
                $helpText | Should -Not -Match '(\?\?=)|(\?\?)|&&|(\|\|)'
            }
        }

        It "Uses only approved verbs for its functions" {
            $fns = $ast.FindAll(
                { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] },
                $true) |
                Where-Object { $_.Name -like '*-*' }
            foreach ($fn in $fns) {
                $verb = ($fn.Name -split '-')[0]
                Get-Verb -Verb $verb | Should -Not -BeNullOrEmpty -Because "'$($fn.Name)' must use an approved verb"
            }
        }
    }

    Context "Behavior" {
        It "Returns 0 with [+]-prefixed success output after finding a large file" {
            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            $text | Should -Match '\[\+\] Found 1 files larger than 100 MB'
            $text | Should -Match '\[\+\] Large files scan completed'
        }

        It "Excludes files under excluded paths from the report" {
            Mock -CommandName Get-ChildItem { @(New-MockLargeFile -FullName 'C:\Windows\WinSxS\huge.dll') }

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            $text | Should -Match 'Found 0 files larger than 100 MB'
        }

        It "Is idempotent: repeated read-only scans succeed identically" {
            $r1 = Main *>&1
            $r2 = Main *>&1
            ($r1 | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            ($r2 | Where-Object { $_ -is [int] })[-1] | Should -Be 0
        }

        It "Returns 1 with [-] output when volume enumeration fails" {
            Mock -CommandName Get-Volume { throw "storage subsystem unavailable" }

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 1
            $text | Should -Match '\[-\] Error'
        }
    }
}
