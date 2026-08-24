#Requires -Modules Pester

Describe "Invoke-RemediationFixBitLockerNotEscrowedKeys" {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/security/Invoke-RemediationFixBitLockerNotEscrowedKeys.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Invoke-RemediationFixBitLockerNotEscrowedKeys\.ps1'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
            $raw | Should -Match 'Author:'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
        }

        It "Has SYNOPSIS, DESCRIPTION and at least two EXAMPLES" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
        }

        It "Declares one .PARAMETER per param() parameter" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
            if ($null -eq $ast.ParamBlock) { $declared = @() }
            else { $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.Extent.Text.TrimStart('$') }) }
            $raw = Get-Content -Path $scriptPath -Raw
            $paramHelpMatches = [regex]::Matches($raw, '(?m)^\s*\.PARAMETER\s+(\S+)')
            $documented = @($paramHelpMatches | ForEach-Object { $_.Groups[1].Value })
            @($documented).Count | Should -Be @($declared).Count
            foreach ($p in $declared) { $documented | Should -Contain $p }
        }
    }

    Context "Syntax & Static" {
        BeforeAll {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        }
        It "Parses with zero errors" {
            $errors | Should -BeNullOrEmpty
        }
        It "Contains no PS7-only operators and no emoji" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Not -Match '(?m)&&|\|\||\?\?|\?\?='
            $raw | Should -Not -Match '\$\w+\s*\?\s*[^:]'
            $raw | Should -Not -Match '[\u2705\u274C\u26A0]'
            $raw | Should -Not -Match '[\uD83C-\uDBFF][\uDC00-\uDFFF]'
        }
        It "Uses SupportsShouldProcess for its mutating operations" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
            $raw | Should -Match '\$PSCmdlet\.ShouldProcess\('
        }
    }

    Context "Behavior" {
        BeforeAll {

        # Stub externals so Pester Mock can bind them offline.
        function Get-BitLockerVolume { }
        function Add-BitLockerKeyProtector { }
        function BackupToAAD-BitLockerKeyProtector { }
        }

        It "Adds a missing protector, escrows it and returns 0 with [+]-prefixed output" {
            Mock Get-Module { [pscustomobject]@{ Name = 'BitLocker' } }
            Mock Get-BitLockerVolume {
                @([pscustomobject]@{
                    MountPoint = 'C:'
                    VolumeStatus = 'FullyEncrypted'
                    KeyProtector = @()
                })
            }
            Mock Add-BitLockerKeyProtector {
                [pscustomobject]@{ KeyProtectorId = '{11111111-1111-1111-1111-111111111111}' }
            }
            Mock BackupToAAD-BitLockerKeyProtector { }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[\+\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Add-BitLockerKeyProtector -Exactly 1 -Scope It
            Should -Invoke BackupToAAD-BitLockerKeyProtector -Exactly 1 -Scope It
        }

        It "Escrows an existing recovery password without adding a new protector" {
            Mock Get-Module { [pscustomobject]@{ Name = 'BitLocker' } }
            Mock Get-BitLockerVolume {
                @([pscustomobject]@{
                    MountPoint = 'C:'
                    VolumeStatus = 'FullyEncrypted'
                    KeyProtector = @([pscustomobject]@{
                        KeyProtectorType = 'RecoveryPassword'
                        KeyProtectorId = '{22222222-2222-2222-2222-222222222222}'
                    })
                })
            }
            Mock Add-BitLockerKeyProtector { }
            Mock BackupToAAD-BitLockerKeyProtector { }

            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Add-BitLockerKeyProtector -Exactly 0 -Scope It
            Should -Invoke BackupToAAD-BitLockerKeyProtector -Exactly 1 -Scope It
        }

        It "Returns 1 with [-] output when escrow fails" {
            Mock Get-Module { [pscustomobject]@{ Name = 'BitLocker' } }
            Mock Get-BitLockerVolume {
                @([pscustomobject]@{
                    MountPoint = 'C:'
                    VolumeStatus = 'FullyEncrypted'
                    KeyProtector = @([pscustomobject]@{
                        KeyProtectorType = 'RecoveryPassword'
                        KeyProtectorId = '{33333333-3333-3333-3333-333333333333}'
                    })
                })
            }
            Mock Add-BitLockerKeyProtector { }
            Mock BackupToAAD-BitLockerKeyProtector { throw 'AAD unreachable' }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 when the BitLocker module is unavailable" {
            Mock Get-Module { @() }
            Mock Get-BitLockerVolume { }
            Mock Add-BitLockerKeyProtector { }
            Mock BackupToAAD-BitLockerKeyProtector { }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[!\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Is idempotent: no volumes returns 0 without mutations" {
            Mock Get-Module { [pscustomobject]@{ Name = 'BitLocker' } }
            Mock Get-BitLockerVolume { @() }
            Mock Add-BitLockerKeyProtector { }
            Mock BackupToAAD-BitLockerKeyProtector { }

            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Add-BitLockerKeyProtector -Exactly 0 -Scope It
            Should -Invoke BackupToAAD-BitLockerKeyProtector -Exactly 0 -Scope It
        }
    }
}
