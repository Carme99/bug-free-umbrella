#Requires -Modules Pester

Describe "Test-SecurityFeatures" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/security/compliance/frameworks/Test-SecurityFeatures.ps1"
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        Mock Test-AdministratorElevation { $true }

        # Stub Windows-only cmdlets so Pester can mock them on Linux
        function Get-Tpm { }
        function Confirm-SecureBootUEFI { }
        function Get-BitLockerVolume { }
        function Get-MpComputerStatus { }
        function Get-NetFirewallProfile { }
        function Get-ProcessMitigation { }
        function Get-CimInstance { }
        function Get-ItemProperty { }
        function Get-Service { }

        # Fully compliant machine: every check reports Enabled
        Mock Get-Tpm {
            [pscustomobject]@{ TpmPresent = $true; TpmReady = $true; ManufacturerVersion = '2.0' }
        }
        Mock Confirm-SecureBootUEFI { $true }
        Mock Get-CimInstance {
            param([string]$ClassName, [string]$Namespace)
            if ($ClassName -eq 'Win32_DeviceGuard') {
                [pscustomobject]@{
                    VirtualizationBasedSecurityStatus = 2
                    SecurityServicesRunning   = @(1)
                    SecurityServicesConfigured = @(1)
                }
            }
            else {
                [pscustomobject]@{ DataExecutionPrevention_SupportPolicy = 3 }
            }
        }
        Mock Get-BitLockerVolume {
            @([pscustomobject]@{
                VolumeType = 'OperatingSystem'; ProtectionStatus = 'On'; MountPoint = 'C:'
                EncryptionPercentage = 100; EncryptionMethod = 'XtsAes256'
            })
        }
        Mock Get-MpComputerStatus {
            [pscustomobject]@{
                AntivirusEnabled = $true; RealTimeProtectionEnabled = $true
                BehaviorMonitorEnabled = $true; IoavProtectionEnabled = $true
            }
        }
        Mock Get-NetFirewallProfile {
            @(
                [pscustomobject]@{ Name = 'Domain'; Enabled = $true },
                [pscustomobject]@{ Name = 'Private'; Enabled = $true },
                [pscustomobject]@{ Name = 'Public'; Enabled = $true }
            )
        }
        Mock Get-ProcessMitigation { [pscustomobject]@{ Enablement = 1 } }
        Mock Get-Service { [pscustomobject]@{ Name = 'wuauserv'; Status = 'Running' } }
        Mock Get-ItemProperty { [pscustomobject]@{ PEFirmwareType = 2 } }
    }

    Context "Help & Metadata" {
        It "Has the required header fields" {
            $raw | Should -Match '(?m)^\.SYNOPSIS'
            $raw | Should -Match '(?m)^\.DESCRIPTION'
            $raw | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
            $raw | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
        }

        It "Has a File Name field matching the disk filename" {
            $fileName = Split-Path $scriptPath -Leaf
            $escaped = [regex]::Escape($fileName)
            $raw | Should -Match "(?m)^\s*File Name\s*:\s*$escaped\s*$"
        }

        It "Declares one .PARAMETER block per declared parameter, in order" {
            $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errs)
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $documented = @([regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })

            $documented.Count | Should -Be $declared.Count
            for ($i = 0; $i -lt $declared.Count; $i++) {
                $documented[$i] | Should -Be $declared[$i]
            }
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $errs = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errs) | Out-Null
            $errs | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only operator tokens" {
            $tokens = $null
            $errs = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errs) | Out-Null
            $ps7Only = @($tokens | Where-Object { $_.Text -in @('&&', '||', '??', '??=') })
            $ps7Only | Should -BeNullOrEmpty
        }

        It "Declares SupportsShouldProcess (destructive-capable compliance scanner)" {
            $raw | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
        }
    }

    Context "Behavior" {
        It "Returns 0 and is idempotent when every security feature is enabled" {
            Main | Should -Be 0
            Main | Should -Be 0   # converged re-run still exits 0
        }

        It "Returns exit code 1 when Secure Boot is disabled" {
            Mock Confirm-SecureBootUEFI { $false }

            Main | Should -Be 1
        }

        It "Prints actionable recommendations for disabled features with -ShowRecommendations" {
            Mock Confirm-SecureBootUEFI { $false }

            $out = (Main -ShowRecommendations *>&1 | Out-String)
            $out | Should -Match 'Enable Secure Boot in UEFI firmware settings'
        }
    }
}
