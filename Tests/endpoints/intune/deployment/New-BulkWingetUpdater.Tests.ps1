#Requires -Modules Pester

Describe "New-BulkWingetUpdater" {
    BeforeAll {
        # Mirrored layout: walk up ../../../../ levels from this test folder to the repository root.
        $repoRoot = (Get-Item (Join-Path $PSScriptRoot "../../../../")).FullName
        $scriptPath = Join-Path $repoRoot "scripts/endpoints/intune/deployment/New-BulkWingetUpdater.ps1"

        # Mandatory Single-set parameters must be bound for dot-sourcing to avoid interactive prompts.
        # Tests override the script-scope variables per behavior case.
        . $scriptPath -AppName 'Probe App' -WingetID 'Probe.Id' -ProcessName 'probe'
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$') | Should -BeTrue
            ($raw -match '(?m)^\s*Date\s*:\s*2026-08-23\s*$') | Should -BeTrue
        }

        It "Declares File Name matching the on-disk filename" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match "(?m)^\s*File Name\s*:\s*New-BulkWingetUpdater\.ps1\s*$") | Should -BeTrue
        }

        It "Documents one .PARAMETER per declared parameter in order" {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $paramNames = @($ast.ParamBlock.Parameters.Name) -replace '^\$', ''
            $paramNames.Count | Should -Be 7
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

        It "Declares CmdletBinding with SupportsShouldProcess, Main, dot-source guard, and guarded exit" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match '\[CmdletBinding\(.+SupportsShouldProcess\)') | Should -BeTrue
            ($raw -match '(?m)^function Main \{') | Should -BeTrue
            ($raw -match [regex]::Escape('if ($MyInvocation.InvocationName -ne '.')')) | Should -BeTrue
            ([regex]::Matches($raw, '\bexit\s*\(')).Count | Should -Be 1
        }
    }

    Context "Behavior" {
        It "Generates detect and remediate scripts for a single app and returns 0" {
            $AppName = 'Google Chrome'
            $WingetID = 'Google.Chrome'
            $ProcessName = 'chrome'
            $OutputPath = Join-Path $TestDrive 'single'
            $ForceUpdate = $false
            $GenerateBatch = $false

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $appFolder = Join-Path $OutputPath 'Google Chrome'
            Test-Path (Join-Path $appFolder 'detect.ps1') | Should -BeTrue
            Test-Path (Join-Path $appFolder 'remediate.ps1') | Should -BeTrue
            $detectContent = Get-Content (Join-Path $appFolder 'detect.ps1') -Raw
            ($detectContent -match '\.SYNOPSIS') | Should -BeTrue
            ($detectContent -match 'Google\.Chrome') | Should -BeTrue
        }

        It "Is idempotent: re-running on an existing output folder still succeeds and keeps both scripts" {
            $AppName = 'Google Chrome'
            $WingetID = 'Google.Chrome'
            $ProcessName = 'chrome'
            $OutputPath = Join-Path $TestDrive 'rerun'
            $ForceUpdate = $false
            $GenerateBatch = $false

            ($out1 = Main *>&1) | Out-Null
            ($out2 = Main *>&1) | Out-Null

            ($out2 | Where-Object { $_ -is [int] }) | Should -Be 0
            $appFolder = Join-Path $OutputPath 'Google Chrome'
            Test-Path (Join-Path $appFolder 'detect.ps1') | Should -BeTrue
            Test-Path (Join-Path $appFolder 'remediate.ps1') | Should -BeTrue
        }

        It "Honors -WhatIf: no folders or files are written" {
            $AppName = 'Google Chrome'
            $WingetID = 'Google.Chrome'
            $ProcessName = 'chrome'
            $OutputPath = Join-Path $TestDrive 'whatif'
            $WhatIfPreference = $true

            try {
                $out = Main *>&1
                ($out | Where-Object { $_ -is [int] }) | Should -Be 0
                Test-Path $OutputPath | Should -BeFalse
            }
            finally {
                $WhatIfPreference = $false
            }
        }

        It "Generates scripts for every CSV row in batch mode and returns 0" {
            $csvPath = Join-Path $TestDrive 'apps.csv'
            @'
AppName,WingetID,ProcessName
7-Zip,7zip.7zip,7zFM
VLC media player,VideoLAN.VLC,vlc
'@ | Set-Content -Path $csvPath -NoNewline

            $GenerateBatch = $true
            $CSVPath = $csvPath
            $OutputPath = Join-Path $TestDrive 'batch'

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Test-Path (Join-Path $OutputPath '7-Zip/remediate.ps1') | Should -BeTrue
            Test-Path (Join-Path $OutputPath 'VLC media player/detect.ps1') | Should -BeTrue
        }

        It "Returns 1 with [-] prefixed output when the batch CSV is missing" {
            $GenerateBatch = $true
            $CSVPath = Join-Path $TestDrive 'does-not-exist.csv'
            $OutputPath = Join-Path $TestDrive 'batch-fail'

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
