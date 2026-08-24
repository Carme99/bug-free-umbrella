#Requires -Modules Pester

Describe "remediate.ps1 (SCCM)" {
    BeforeAll {
        # Mirrored layout: walk up 4 levels from this test folder to the repository root.
        $repoRoot = (Get-Item (Join-Path $PSScriptRoot "../../../../")).FullName
        $scriptPath = Join-Path $repoRoot "scripts/endpoints/devices/sccm/remediate.ps1"

        # Safe: the top-level guard skips Main when dot-sourced (docs/RELAUNCH-SPEC.md section 3).
        . $scriptPath

        # Deterministic install location for the mocked Test-Path calls.
        $env:windir = 'C:\Windows'

        # Join-Path validates drive names on Linux, so source trees use a Unix-style path;
        # only the (never-resolved-on-disk) windir location stays Windows-shaped.
        $sourceRoot = '/tmp/bfu-sccm-source'
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$') | Should -BeTrue
            ($raw -match '(?m)^\s*Date\s*:\s*2026-08-23\s*$') | Should -BeTrue
        }

        It "Declares File Name matching the on-disk filename" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match "(?m)^\s*File Name\s*:\s*remediate\.ps1\s*$") | Should -BeTrue
        }

        It "Documents every declared parameter in declaration order" {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $raw = Get-Content -Path $scriptPath -Raw
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $documented = @([regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
            $documented | Should -Be $declared
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

        It "Gates the destructive installation behind SupportsShouldProcess" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match '\[CmdletBinding\(SupportsShouldProcess\)\]') | Should -BeTrue
            ($raw -match '\$PSCmdlet\.ShouldProcess') | Should -BeTrue
        }
    }

    Context "Behavior" {
        It "Is idempotent: already-installed client returns 0 and never installs" {
            Mock Write-Host { }
            Mock Test-Path { $true }
            Mock Invoke-CcmSetup { throw 'must not install when already present' }
            Main | Should -Be 0
            Should -Invoke Invoke-CcmSetup -Times 0 -Exactly
        }

        It "Returns 1 with [-] output when the client is missing and no SourcePath is supplied" {
            Mock Write-Host { param($Object) $Object }
            Mock Test-Path { $false }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 when the supplied SourcePath does not exist" {
            Mock Write-Host { }
            Mock Test-Path { $false } -ParameterFilter { $Path -eq 'C:\Nope' }
            Main -SourcePath 'C:\Nope' | Should -Be 1
        }

        It "Installs from a valid source tree and returns 0 on ccmsetup success (exit code 0)" {
            Mock Write-Host { }
            $installState = @{ Installed = $false }
            Mock Test-Path {
                if ($Path -eq 'C:\Windows\ccmsetup\ccmsetup.exe') { return $installState.Installed }
                return $true
            }
            Mock Invoke-CcmSetup {
                $installState.Installed = $true
                [pscustomobject]@{ ExitCode = 0; StandardOutput = 'ccmsetup ok'; StandardError = '' }
            }

            Main -SourcePath $sourceRoot | Should -Be 0

            Should -Invoke Invoke-CcmSetup -Times 1 -Exactly -ParameterFilter {
                $FilePath -like '*sccm-source/ccmsetup.exe' -and $ArgumentList -eq "/Source:$sourceRoot"
            }
        }

        It "Treats ccmsetup exit code 7 (reboot required) as success" {
            Mock Write-Host { }
            $installState = @{ Installed = $false }
            Mock Test-Path {
                if ($Path -eq 'C:\Windows\ccmsetup\ccmsetup.exe') { return $installState.Installed }
                return $true
            }
            Mock Invoke-CcmSetup {
                $installState.Installed = $true
                [pscustomobject]@{ ExitCode = 7; StandardOutput = ''; StandardError = '' }
            }

            Main -SourcePath $sourceRoot -ManagementPoint 'MP.contoso.com' | Should -Be 0

            Should -Invoke Invoke-CcmSetup -Times 1 -Exactly -ParameterFilter {
                $ArgumentList -eq "/Source:$sourceRoot /MP:MP.contoso.com"
            }
        }

        It "Returns 1 with [-] output when ccmsetup fails" {
            Mock Write-Host { param($Object) $Object }
            Mock Test-Path {
                if ($Path -eq 'C:\Windows\ccmsetup\ccmsetup.exe') { return $false }
                return $true
            }
            Mock Invoke-CcmSetup {
                [pscustomobject]@{ ExitCode = 3; StandardOutput = ''; StandardError = 'fatal' }
            }

            $out = Main -SourcePath 'C:\SCCM' *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Honors -WhatIf: no process is started and the script still succeeds" {
            Mock Write-Host { }
            Mock Test-Path {
                if ($Path -eq 'C:\Windows\ccmsetup\ccmsetup.exe') { return $false }
                return $true
            }
            Mock Invoke-CcmSetup { throw 'WhatIf must prevent execution' }

            Main -SourcePath $sourceRoot -WhatIf | Should -Be 0
            Should -Invoke Invoke-CcmSetup -Times 0 -Exactly
        }
    }
}
