#Requires -Modules Pester

Describe "Get-DiskReport" {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../../../..')
        $scriptPath = Join-Path $repoRoot 'scripts/infrastructure/windows/storage/Get-DiskReport.ps1'
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



        Mock -CommandName Test-Path { $false }
        Mock -CommandName Test-Path { $true } -ParameterFilter { $LiteralPath }
        Mock -CommandName Get-ChildItem { @() }
        Mock -CommandName Out-File { }
        Mock -CommandName Get-Volume {
            @([PSCustomObject]@{
                DriveLetter = 'C'
                FileSystem = 'NTFS'
                Size = 100GB
                SizeRemaining = 40GB
            })
        }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date" {
            $helpText | Should -Match 'Version\s*:\s*1\.0\.0'
            $helpText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Declares matching File Name, Author and Prerequisite" {
            $helpText | Should -Match ('File Name\s*:\s*' + [regex]::Escape('Get-DiskReport.ps1'))
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
    }

    Context "Behavior" {
        It "Returns 0 and reports volume usage with no cleanup opportunities" {
            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            $text | Should -Match '\[\+\] No significant cleanup opportunities found'
            $text | Should -Match '(?s)\[\+\].*Disk analysis completed'
        }

        It "Surfaces a cleanup suggestion when a large temp folder exists" {
            Mock -CommandName Test-Path { $true } -ParameterFilter { $Path -eq 'C:\Windows\Temp' }
            Mock -CommandName Get-ChildItem {
                @([PSCustomObject]@{
                    FullName = 'C:\Windows\Temp\junk.tmp'; Length = 200MB
                    LastWriteTime = (Get-Date)
                })
            }

            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            $text | Should -Match 'Windows Temp Files'
        }

        It "Is idempotent: repeated read-only analyses succeed identically" {
            (Main) | Should -Be 0
            (Main) | Should -Be 0
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
