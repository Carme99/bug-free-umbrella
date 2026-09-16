#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for scripts/endpoints/intune/autopilot/Test-AutopilotHardwareHashCsv.ps1.

.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior. Every
    behaviour test drives the script against a real CSV fixture written into the Pester test
    drive, so the Import-Csv / Export-Csv path is exercised for real. Runs offline on Linux
    pwsh; no network, elevation, or installed product modules required.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/endpoints/intune/autopilot
    Runs this test file.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/endpoints/intune/autopilot -Output Detailed
    Runs this test file with per-test output.

.NOTES
   File Name   : Test-AutopilotHardwareHashCsv.Tests.ps1
   Author      : Bug-Free Umbrella
   Prerequisite: PowerShell 7.0
   Version     : 2.0.0
   Date        : 2026-09-16
#>

Describe 'Test-AutopilotHardwareHashCsv' {
    BeforeAll {
        $scriptRelPath = ('../../../../scripts/endpoints/intune/autopilot/' +
            'Test-AutopilotHardwareHashCsv.ps1')
        $scriptPath = (Resolve-Path (Join-Path $PSScriptRoot $scriptRelPath)).Path

        # Writes an ANSI fixture (no BOM) and returns its path. -Preamble prepends raw bytes so
        # the Unicode byte-order-mark rule can be tested.
        function New-CsvFixture {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)][string]$Name,
                [Parameter(Mandatory = $true)][string]$Content,
                [byte[]]$Preamble
            )

            $path = Join-Path $TestDrive $Name
            $bytes = [Text.Encoding]::ASCII.GetBytes($Content)
            if ($null -ne $Preamble) { $bytes = $Preamble + $bytes }
            [IO.File]::WriteAllBytes($path, $bytes)

            return $path
        }

        $header = 'Device Serial Number,Windows Product ID,Hardware Hash,Group Tag,Assigned User'
        $longGroupTag = 'T' * 70

        $validCsv = New-CsvFixture -Name 'valid.csv' -Content ($header + "`r`n" +
            'SER-001,00456-12345-67890-AAOEM,HASHAAA111,Kiosk,' + "`r`n" +
            'SER-002,00456-12345-67890-AAOEM,HASHBBB222,,' + "`r`n")

        $duplicateHashCsv = New-CsvFixture -Name 'duplicate-hash.csv' -Content ($header + "`r`n" +
            'SER-010,00456-1,HASHSAME000,Kiosk,' + "`r`n" +
            'SER-011,00456-1,HASHSAME000,Kiosk,' + "`r`n")

        $missingHashCsv = New-CsvFixture -Name 'missing-hash.csv' -Content ($header + "`r`n" +
            'SER-020,00456-1,,Kiosk,' + "`r`n")

        $badCaseCsv = New-CsvFixture -Name 'bad-case.csv' -Content (
            'Device Serial Number,Windows Product ID,hardware hash,Group Tag,Assigned User' +
            "`r`n" + 'SER-030,00456-1,HASHCCC333,Kiosk,' + "`r`n")

        $quotedCsv = New-CsvFixture -Name 'quoted.csv' -Content ($header + "`r`n" +
            '"SER-040",00456-1,HASHDDD444,Kiosk,' + "`r`n")

        $extraColumnCsv = New-CsvFixture -Name 'extra-column.csv' -Content (
            $header + ',Notes' + "`r`n" + 'SER-050,00456-1,HASHEEE555,Kiosk,,note' + "`r`n")

        $missingColumnCsv = New-CsvFixture -Name 'missing-column.csv' -Content (
            'Device Serial Number,Windows Product ID,Hardware Hash' + "`r`n" +
            'SER-060,00456-1,HASHFFF666' + "`r`n")

        $bomCsv = New-CsvFixture -Name 'bom.csv' -Preamble ([byte[]](0xEF, 0xBB, 0xBF)) -Content (
            $header + "`r`n" + 'SER-070,00456-1,HASHGGG777,Kiosk,' + "`r`n")

        $longGroupTagCsv = New-CsvFixture -Name 'long-group-tag.csv' -Content (
            $header + "`r`n" + 'SER-080,00456-1,HASHHHH888,' + $longGroupTag + ',' + "`r`n")

        $badUserCsv = New-CsvFixture -Name 'bad-user.csv' -Content ($header + "`r`n" +
            'SER-090,00456-1,HASHIII999,Kiosk,not-a-upn' + "`r`n")

        # Safe: the script's top-level guard skips Main when dot-sourced. -CsvPath is supplied
        # so the mandatory parameter does not prompt.
        . $scriptPath -CsvPath $validCsv

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath, [ref]$tokens, [ref]$parseErrors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Test-AutopilotHardwareHashCsv\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*Bug-Free Umbrella'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Documents every declared parameter, in order' {
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object {
                $_.Name.Extent.Text.TrimStart('$')
            })
            $helpParams = @([regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value })
            $declared | Should -Be @('CsvPath', 'MaxBatchSize', 'OutputPath')
            $helpParams | Should -Be $declared
        }

        It 'Provides at least two examples with PS prompts' {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $parseErrors.Count | Should -Be 0
        }

        It 'Uses CmdletBinding, Main function, and dot-source guard' {
            $raw | Should -Match '\[CmdletBinding\('
            $raw | Should -Match '(?m)^function Main \{'
            $raw | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
        }

        It 'Contains no PS7-only operators and no #Requires opt-out' {
            # Token-level scan: the forbidden operator texts are built from code points so this
            # file does not itself contain them.
            $forbidden = @(
                (-join [char[]](0x3F, 0x3F))
                (-join [char[]](0x3F, 0x3F, 0x3D))
                (-join [char[]](0x26, 0x26))
                (-join [char[]](0x7C, 0x7C))
            )
            $declared = @($tokens | ForEach-Object { $_.Text })
            foreach ($operator in $forbidden) {
                $declared | Should -Not -Contain $operator
            }
            $raw | Should -Not -Match '#Requires\s+-Version'
        }

        It 'Is UTF-8 with BOM and CRLF line endings' {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }

        It 'Keeps all lines within 120 columns and free of tabs' {
            ($raw -split "`r`n" | Where-Object { $_.Length -gt 120 }) | Should -BeNullOrEmpty
            $raw | Should -Not -Match "`t"
        }

        It 'Cites Microsoft Learn in its help' {
            $raw | Should -Match 'learn\.microsoft\.com'
        }
    }

    Context 'Behavior' {
        It 'Returns 0 and writes a clean reconciliation CSV for a valid file' {
            $outCsv = Join-Path $TestDrive 'recon-valid.csv'
            . $scriptPath -CsvPath $validCsv -OutputPath $outCsv
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] CSV is valid for Autopilot manual import'
            $written = @(Import-Csv -LiteralPath $outCsv)
            $written.Count | Should -Be 2
            $written[0].Verdict | Should -Be 'Ready'
            $written[0].PredictedError | Should -Be ''
        }

        It 'Writes to temp by default and leaves the working directory unchanged' {
            $defaultCsv = Join-Path ([IO.Path]::GetTempPath()) 'AutopilotHardwareHashReconciliation.csv'
            Remove-Item -LiteralPath $defaultCsv -ErrorAction SilentlyContinue
            $cwd = (Get-Location).Path
            $before = @(Get-ChildItem -Force -Path $cwd | Select-Object -ExpandProperty Name)

            . $scriptPath -CsvPath $validCsv
            $out = Main *>&1

            $after = @(Get-ChildItem -Force -Path $cwd | Select-Object -ExpandProperty Name)
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Reconciliation CSV written to'
            Test-Path -LiteralPath $defaultCsv -PathType Leaf | Should -BeTrue
            @(Import-Csv -LiteralPath $defaultCsv).Count | Should -Be 2
            Test-Path -LiteralPath (Join-Path $cwd 'AutopilotHardwareHashReconciliation.csv') |
                Should -BeFalse
            ($after -join ';') | Should -Be ($before -join ';')
        }

        It 'Predicts ZtdDeviceDuplicated for a repeated hardware hash' {
            $outCsv = Join-Path $TestDrive 'recon-duplicate.csv'
            . $scriptPath -CsvPath $duplicateHashCsv -OutputPath $outCsv
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($out | Out-String) | Should -Match 'ZtdDeviceDuplicated'
            $written = @(Import-Csv -LiteralPath $outCsv)
            $written[0].Verdict | Should -Be 'Ready'
            $written[1].PredictedError | Should -Be 'ZtdDeviceDuplicated'
            $written[1].Verdict | Should -Be 'Review'
        }

        It 'Predicts InvalidZtdHardwareHash when the hardware hash is empty' {
            $outCsv = Join-Path $TestDrive 'recon-missing-hash.csv'
            . $scriptPath -CsvPath $missingHashCsv -OutputPath $outCsv
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($out | Out-String) | Should -Match 'InvalidZtdHardwareHash'
            (@(Import-Csv -LiteralPath $outCsv))[0].PredictedError |
                Should -Be 'InvalidZtdHardwareHash'
        }

        It 'Fails the case-sensitive header rule and skips row analysis' {
            $outCsv = Join-Path $TestDrive 'recon-bad-case.csv'
            . $scriptPath -CsvPath $badCaseCsv -OutputPath $outCsv
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            $text = $out | Out-String
            $text | Should -Match 'headers are case-sensitive'
            $text | Should -Match '\[!\] Header mismatch; row analysis skipped'
        }

        It 'Rejects a file that contains quotation marks' {
            $outCsv = Join-Path $TestDrive 'recon-quoted.csv'
            . $scriptPath -CsvPath $quotedCsv -OutputPath $outCsv
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($out | Out-String) | Should -Match 'quotation marks are not allowed'
        }

        It 'Rejects a Unicode byte-order mark because only ANSI is allowed' {
            $outCsv = Join-Path $TestDrive 'recon-bom.csv'
            . $scriptPath -CsvPath $bomCsv -OutputPath $outCsv
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($out | Out-String) | Should -Match 'only ANSI text is allowed'
        }

        It 'Rejects extra columns and missing columns' {
            $extraOut = Join-Path $TestDrive 'recon-extra.csv'
            . $scriptPath -CsvPath $extraColumnCsv -OutputPath $extraOut
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($out | Out-String) | Should -Match 'extra columns are not allowed: Notes'

            $missingOut = Join-Path $TestDrive 'recon-missing-column.csv'
            . $scriptPath -CsvPath $missingColumnCsv -OutputPath $missingOut
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($out | Out-String) | Should -Match "the 'Group Tag' column is missing"
        }

        It 'Flags an over-long group tag and a non-UPN assigned user per row' {
            $tagOut = Join-Path $TestDrive 'recon-long-tag.csv'
            . $scriptPath -CsvPath $longGroupTagCsv -OutputPath $tagOut
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($out | Out-String) | Should -Match 'group tag exceeds 64 characters'

            $userOut = Join-Path $TestDrive 'recon-bad-user.csv'
            . $scriptPath -CsvPath $badUserCsv -OutputPath $userOut
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($out | Out-String) | Should -Match 'assigned user is not a user principal name'
        }

        It 'Flags a file that exceeds the configured batch size' {
            $outCsv = Join-Path $TestDrive 'recon-batch.csv'
            . $scriptPath -CsvPath $validCsv -MaxBatchSize 1 -OutputPath $outCsv
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
            ($out | Out-String) | Should -Match 'exceed the configured batch limit of 1'
        }

        It 'Returns the documented exit code 1 when the CSV is missing' {
            $missingPath = Join-Path $TestDrive 'does-not-exist.csv'
            $outCsv = Join-Path $TestDrive 'recon-missing-file.csv'
            . $scriptPath -CsvPath $missingPath -OutputPath $outCsv
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[\-\] Error: Hardware hash CSV not found'
        }

        It 'Returns 1 when the path is a directory rather than a file' {
            $outCsv = Join-Path $TestDrive 'recon-directory.csv'
            . $scriptPath -CsvPath $TestDrive -OutputPath $outCsv
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[\-\]'
        }
    }
}
