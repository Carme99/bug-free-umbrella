#Requires -Modules Pester

Describe "Export-WingetPackageList" {
    BeforeAll {
        # Mirrored layout: walk up ../../../../ levels from this test folder to the repository root.
        $repoRoot = (Get-Item (Join-Path $PSScriptRoot "../../../../")).FullName
        $scriptPath = Join-Path $repoRoot "scripts/endpoints/intune/deployment/Export-WingetPackageList.ps1"

        # Safe: the top-level guard skips Main when dot-sourced (docs/RELAUNCH-SPEC.md section 3).
        . $scriptPath

        # Realistic `winget list` output: header + separator are skipped, then package rows.
        # The '< available' column marks pending updates; msstore source is filtered by default.
        $wingetListOutput = @'
Name                        Id                   Version       Available      Source
---------------------------------------------------------------------------------
Chrome                      Google.Chrome        120.0.6099    < 121.0.6148   winget
7-Zip                       7zip.7zip            23.01                        winget
News                        Microsoft.News       1.0           < 2.0          msstore
'@

        function New-PackageMocks {
            $script:Packages = @()   # reset state accumulated by earlier Main calls
            Mock Get-WingetPath { 'C:\Program Files\WindowsApps\fake\winget.exe' }
            Mock Invoke-WingetList { param([string]$WingetExe) $wingetListOutput }
        }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$') | Should -BeTrue
            ($raw -match '(?m)^\s*Date\s*:\s*2026-08-23\s*$') | Should -BeTrue
        }

        It "Declares File Name matching the on-disk filename" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match "(?m)^\s*File Name\s*:\s*Export-WingetPackageList\.ps1\s*$") | Should -BeTrue
        }

        It "Documents one .PARAMETER per declared parameter in order" {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $paramNames = @($ast.ParamBlock.Parameters.Name) -replace '^\$', ''
            $paramNames.Count | Should -Be 4
            $raw = Get-Content -Path $scriptPath -Raw
            $documented = @([regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\w+)') | ForEach-Object { $_.Groups[1].Value })
            $documented | Should -Be $paramNames
        }

        It "Provides at least two examples" {
            $raw = Get-Content -Path $scriptPath -Raw
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Is UTF-8 BOM encoded with CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            (@($bytes[0], $bytes[1], $bytes[2])) | Should -Be @(0xEF, 0xBB, 0xBF)
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            $bareLfLines = @(($text -split "`n") | Where-Object { $_ -and ($_ -notmatch "`r$") })
            $bareLfLines.Count | Should -Be 0
        }

        It "Contains no PS7-only operators without an opt-out pragma" {
            $raw = Get-Content -Path $scriptPath -Raw
            foreach ($pattern in '&&', '\|\|', '\?\?') {
                ($raw -match $pattern) | Should -BeFalse
            }
        }

        It "Declares CmdletBinding, a Main function, a dot-source guard, and exit only in the guard line" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match '\[CmdletBinding\(') | Should -BeTrue
            ($raw -match '(?m)^function Main \{') | Should -BeTrue
            ($raw -match [regex]::Escape('if ($MyInvocation.InvocationName -ne '.')')) | Should -BeTrue
            ([regex]::Matches($raw, '\bexit\s*\(')).Count | Should -Be 1
        }

        It "Routes native winget.exe only through the Invoke-WingetList wrapper" {
            Mock Get-WingetPath { 'C:\fake\winget.exe' }
            Mock Invoke-WingetList { param([string]$WingetExe) $wingetListOutput }
            $out = Main *>&1
            Should -Invoke Invoke-WingetList -Times 1 -Exactly
            ($out | Out-String) | Should -Not -Match '&\s*\$WingetExe'
        }
    }

    Context "Behavior" {
        It "Enumerates packages via the winget wrapper and returns 0 in Console format" {
            New-PackageMocks
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] Found 2 packages'
            Should -Invoke Invoke-WingetList -Times 1 -Exactly -ParameterFilter {
                $WingetExe -like '*winget.exe'
            }
        }

        It "Exports JSON excluding msstore apps when -OutputPath is given" {
            New-PackageMocks
            $ExportFormat = 'JSON'
            $OutputPath = Join-Path $TestDrive 'packages.json'

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Test-Path $OutputPath | Should -BeTrue
            $exported = Get-Content $OutputPath -Raw | ConvertFrom-Json
            @($exported).Count | Should -Be 2   # msstore row filtered without -IncludeSystemApps
            ($exported.ID) | Should -Contain 'Google.Chrome'
            ($exported | Where-Object ID -eq 'Google.Chrome').UpdateAvailable | Should -BeTrue
            ($exported | Where-Object ID -eq '7zip.7zip').UpdateAvailable | Should -BeFalse
        }

        It "Includes system apps when -IncludeSystemApps is set" {
            New-PackageMocks
            $IncludeSystemApps = $true
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] Found 3 packages'
        }

        It "Writes a CSV export honoring ShouldProcess file writes" {
            New-PackageMocks
            $ExportFormat = 'CSV'
            $OutputPath = Join-Path $TestDrive 'packages.csv'

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Test-Path $OutputPath | Should -BeTrue
            @(Import-Csv $OutputPath).Count | Should -Be 2
        }

        It "Converges safely when winget is absent: returns 0 with a warning and no export" {
            $script:Packages = @()   # reset state accumulated by earlier Main calls
            Mock Get-WingetPath { $null }
            Mock Invoke-WingetList { throw 'must not be called' }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[!\]'
            Should -Invoke Invoke-WingetList -Times 0 -Exactly -Because 'winget is absent'
        }

        It "Returns 1 with [-] prefixed output when the winget call fails" {
            Mock Get-WingetPath { 'C:\fake\winget.exe' }
            Mock Invoke-WingetList { throw 'winget exploded' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
