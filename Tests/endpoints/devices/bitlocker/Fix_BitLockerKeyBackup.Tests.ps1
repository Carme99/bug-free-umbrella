#Requires -Modules Pester

Describe 'endpoints/bitlocker/Fix_BitLockerKeyBackup' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/devices/bitlocker/Fix_BitLockerKeyBackup.ps1'

        # Safe: the script top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Platform stubs so Pester can mock Windows-only cmdlets absent on Linux pwsh.
        if (-not (Get-Command 'Get-BitLockerVolume' -ErrorAction SilentlyContinue)) {
            function Get-BitLockerVolume { throw 'placeholder: Get-BitLockerVolume unavailable on this platform' }
        }
        if (-not (Get-Command 'BackupToAAD-BitLockerKeyProtector' -ErrorAction SilentlyContinue)) {
            function BackupToAAD-BitLockerKeyProtector { throw 'placeholder: BackupToAAD-BitLockerKeyProtector unavailable on this platform' }
        }

        # One operating-system volume with a TPM protector plus a RecoveryPassword protector.
        $fixVolume = [pscustomobject]@{
            VolumeType = 'Operating System'
            MountPoint = 'C:'
            VolumeStatus = 'Used'
            EncryptionPercentage = 100
            KeyProtector = @(
                [pscustomobject]@{ KeyProtectorType = 'Tpm'; KeyProtectorID = 'kp-tpm' },
                [pscustomobject]@{ KeyProtectorType = 'RecoveryPassword'; KeyProtectorID = 'kp-rp' }
            )
        }
        Mock Get-BitLockerVolume { @($fixVolume) }
Mock BackupToAAD-BitLockerKeyProtector { }
    }

    Context 'Help & Metadata' {
        It 'Declares Version 1.0.0 and the relaunch date' {
            $rawText = Get-Content -Path $scriptPath -Raw
            $rawText | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
            $rawText | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
        }

        It 'Records the actual disk file name in .NOTES' {
            $rawText = Get-Content -Path $scriptPath -Raw
            $rawText | Should -Match "(?m)^\s*File Name\s*:\s*Fix_BitLockerKeyBackup.ps1\s*$"
        }

        It 'Documents every declared parameter' {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $paramNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $scriptHelpOnly = ((Get-Content -Path $scriptPath -Raw) -split '(?m)^\s*(?:function|#region)\s')[0]
            $helpNames = @([regex]::Matches($scriptHelpOnly, '(?m)^\s*\.PARAMETER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
            $paramNames.Count | Should -Be $helpNames.Count
            foreach ($p in $paramNames) { $helpNames | Should -Contain $p }
        }
    }

    Context 'Syntax & Static' {
        It 'Parses without parser errors' {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors | Should -BeNullOrEmpty
        }

        It 'Uses UTF-8 BOM and CRLF line endings' {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be @(0xEF, 0xBB, 0xBF)
            $rawText = [System.Text.Encoding]::UTF8.GetString($bytes)
            ($rawText -replace '\r\n', '') | Should -Not -Match '\n'
        }

        It 'Keeps lines within 120 columns without tabs or trailing whitespace' {
            $lines = Get-Content -Path $scriptPath
            ($lines | Where-Object { $_.Length -gt 120 -and $_ -notmatch '^\s*https?://\S+\s*$' }) | Should -BeNullOrEmpty
            ($lines | Where-Object { $_ -match '\t' }) | Should -BeNullOrEmpty
            ($lines | Where-Object { $_ -match '\s+$' }) | Should -BeNullOrEmpty
        }

        It 'Avoids PS7-only syntax without #Requires -Version 7.0' {
            $rawText = Get-Content -Path $scriptPath -Raw
            if ($rawText -notmatch '(?m)^\s*#\s*Requires\s+-Version\s+7\.0') {
                $rawText | Should -Not -Match '\?\?'
                $rawText | Should -Not -Match '&&'
                $rawText | Should -Not -Match '\|\|'
                $rawText | Should -Not -Match '\?\s*[^:\r\n]+\s*:'
            }
        }

        It 'Exits only via the dot-source guard' {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $exitTokens = @($tokens | Where-Object { $_.Kind -eq [System.Management.Automation.Language.TokenKind]::Exit })
            $exitTokens.Count | Should -Be 1
            (Get-Content -Path $scriptPath -Raw) | Should -Match ([regex]::Escape('if ($MyInvocation.InvocationName -ne ''.'') { exit (Main) }'))
        }

    }

    Context 'Behavior' {
        It 'Backs up every recovery password protector and returns 0' {
            Main | Should -Be 0
            Should -Invoke BackupToAAD-BitLockerKeyProtector -Exactly 1
        }

        It 'Returns 1 and writes [-] prefixed output when escrow fails' {
            Mock BackupToAAD-BitLockerKeyProtector { throw 'escrow rejected' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Honors -WhatIf: previews escrow without backing anything up' {
            Main -WhatIf | Should -Be 0
            Should -Invoke BackupToAAD-BitLockerKeyProtector -Exactly 0
        }
    }
}
