#Requires -Modules Pester

Describe "_generate-winget-scripts.ps1" {
    BeforeAll {
        # Mirrored layout: walk up 4 levels from this test folder to the repository root.
        $repoRoot = (Get-Item (Join-Path $PSScriptRoot "../../../../")).FullName
        $scriptPath = Join-Path $repoRoot "scripts/endpoints/devices/winget/_generate-winget-scripts.ps1"

        # Safe: the top-level guard skips Main when dot-sourced (docs/RELAUNCH-SPEC.md section 3).
        . $scriptPath

        # Keep everything in memory: templates come from a filtered mock, writes are captured
        # into a reference-type list so mock bodies and tests share the same instance.
        $writtenFiles = [System.Collections.Generic.List[object]]::new()
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock Get-Content -ParameterFilter { $Path -like '*_templates*' } {
            '# WINGETID' + "`r`n" + '$NotifyUserBeforeClose = $false' + "`r`n" + '$UserNotificationSeconds = 0'
        }
        Mock Set-Content {
            $writtenFiles.Add(@($Path, $Value))
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
            ($raw -match "(?m)^\s*File Name\s*:\s*_generate-winget-scripts\.ps1\s*$") | Should -BeTrue
        }

        It "Documents every declared parameter in declaration order (none declared)" {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $raw = Get-Content -Path $scriptPath -Raw
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $documented = @([regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
            $declared.Count | Should -Be 0
            $documented.Count | Should -Be 0
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

        It "Gates file creation behind SupportsShouldProcess" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match '\[CmdletBinding\(SupportsShouldProcess\)\]') | Should -BeTrue
            ([regex]::Matches($raw, '\$PSCmdlet\.ShouldProcess')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Behavior" {
        It "Generates a detect/remediate pair for every configured application (2 writes per app)" {
            Mock Write-Host { }
            $writtenFiles.Clear()

            Main | Should -Be 0

            Should -Invoke Set-Content -Times (2 * $AppDefinitions.Count) -Exactly
        }

        It "Substitutes the winget id and enables notification for force-close apps" {
            Mock Write-Host { }
            $writtenFiles.Clear()

            New-WingetScriptPair -WingetId 'Discord.Discord' -Category 'communication' `
                -FolderName 'Discord' -ForceClose $true -NotifySeconds 60 | Out-Null

            (@($writtenFiles | Where-Object { $_[0] -like '*Discord*' })).Count | Should -Be 2
            $detectValue = @($writtenFiles | Where-Object { $_[0] -like '*detect.ps1' })[-1][1]
            $remediateValue = @($writtenFiles | Where-Object { $_[0] -like '*remediate.ps1' })[-1][1]
            $detectValue | Should -Match 'Discord\.Discord'
            $remediateValue | Should -Match 'Discord\.Discord'
            $remediateValue | Should -Match '\$NotifyUserBeforeClose = \$true'
            $remediateValue | Should -Match '\$UserNotificationSeconds = 60'
        }

        It "Leaves standard apps on the silent template (no forced notification)" {
            Mock Write-Host { }
            $writtenFiles.Clear()

            New-WingetScriptPair -WingetId 'Box.Box' -Category 'cloud-storage' `
                -FolderName 'Box' -ForceClose $false -NotifySeconds 0 | Out-Null

            $remediateValue = @($writtenFiles | Where-Object { $_[0] -like '*remediate.ps1' })[-1][1]
            $remediateValue | Should -Match '\$NotifyUserBeforeClose = \$false'
            $remediateValue | Should -Match 'Box\.Box'
        }

        It "Returns 1 with [-] output when any app generation fails" {
            Mock Write-Host { param($Object) $Object }
            # Point templates at a missing folder; It-level mocks cannot override the
            # BeforeAll mock of the same command in Pester 5.
            $TemplatePath = '/tmp/bfu-nonexistent-templates'

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Honors -WhatIf: no directories or files are written" {
            Mock Write-Host { }
            $writtenFiles.Clear()

            Main -WhatIf | Should -Be 0

            Should -Invoke Set-Content -Times 0 -Exactly
            Should -Invoke New-Item -Times 0 -Exactly
        }
    }
}
