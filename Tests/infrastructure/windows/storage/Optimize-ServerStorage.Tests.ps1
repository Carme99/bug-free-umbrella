#Requires -Modules Pester

Describe "Optimize-ServerStorage" {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../../../..')
        $scriptPath = Join-Path $repoRoot 'scripts/infrastructure/windows/storage/Optimize-ServerStorage.ps1'
        . $scriptPath
        $helpText = Get-Content -Raw $scriptPath
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)

        # Stub Windows-only commands absent on Linux so Pester can attach mocks.
        foreach ($stub in @('Clear-RecycleBin', 'Get-Service', 'Stop-Service', 'Start-Service')) {
            if (-not (Get-Command $stub -ErrorAction SilentlyContinue)) {
                Invoke-Expression "function $stub { }"
            }
        }
        # Shadow Get-Volume and Get-ChildItem unconditionally: absent on Linux /
        # provider dynamic parameters break Pester's mock proxies.
        function Get-Volume { }
        function Get-ChildItem { }



        Mock -CommandName Test-Path { $true }
        Mock -CommandName Get-ChildItem { @() }   # no user profiles, no files to clean anywhere
        Mock -CommandName Get-Volume {
            @([PSCustomObject]@{
                DriveLetter = 'C'
                Size = 100GB
                SizeRemaining = 40GB
            })
        }
        Mock -CommandName Remove-Item { }
        Mock -CommandName Stop-Service { }
        Mock -CommandName Start-Service { }
        Mock -CommandName Clear-RecycleBin { }
        Mock -CommandName Get-Service { $null }
        Mock -CommandName Import-Module { }
        Mock -CommandName Invoke-Dism { 0 }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date" {
            $helpText | Should -Match 'Version\s*:\s*1\.0\.0'
            $helpText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Declares matching File Name, Author and Prerequisite" {
            $helpText | Should -Match ('File Name\s*:\s*' + [regex]::Escape('Optimize-ServerStorage.ps1'))
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

        It "Declares SupportsShouldProcess for destructive cleanup operations" {
            $ast.ParamBlock.Attributes.NamedArguments.ArgumentName | Should -Contain 'SupportsShouldProcess'
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

        It "Routes Dism.exe through the Invoke-Dism wrapper only" {
            # Native exe references must live inside the wrapper function (mock seam).
            $dismLines = @([regex]::Matches($helpText, '(?m)^(?!\s*#).*Dism\.exe.*$') | ForEach-Object { $_.Value })
            $dismLines.Count | Should -Be 1 -Because "Dism.exe must be invoked exactly once, inside Invoke-Dism"
            $dismLines[0] | Should -Match '& Dism\.exe @args'
        }
    }

    Context "Behavior" {
        It "Returns 0 with [+]-prefixed completion output when there is nothing to clean" {
            $out = Main *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            $text | Should -Match '\[\*\] Already clean'
            $text | Should -Match '\[\+\] Storage optimization completed'
        }

        It "Is idempotent: converged system makes zero deletions and still exits 0" {
            (Main) | Should -Be 0
            Should -Invoke Remove-Item -Times 0 -Exactly -Because "converged system has nothing left to remove"
        }

        It "Honors -WhatIf: no files are deleted and WHATIF output is shown" {
            $out = Main -WhatIf *>&1
            $text = $out | Out-String
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            Should -Invoke Remove-Item -Times 0 -Exactly
            $text | Should -Match 'WHATIF'
        }

        It "Returns 1 with [-] output when volume enumeration fails" {
            Mock -CommandName Get-Volume { throw "storage subsystem unavailable" }

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] })[-1] | Should -Be 1
            (($out | Out-String)) | Should -Match '\[-\] Error'
        }
    }
}
