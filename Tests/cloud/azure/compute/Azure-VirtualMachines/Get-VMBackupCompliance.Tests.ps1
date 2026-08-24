<#
.SYNOPSIS
    Pester 5 tests for scripts/cloud/azure/compute/Azure-VirtualMachines/Get-VMBackupCompliance.ps1.

.DESCRIPTION
    Offline Pester coverage: help/metadata conformance, syntax/static checks, and behavior of
    Main against fully mocked Az Recovery Services / Az Compute cmdlets. No network, admin
    rights, or modules beyond Pester are required.

.NOTES
    File Name   : Get-VMBackupCompliance.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

#Requires -Modules Pester

Describe "Get-VMBackupCompliance" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../../../scripts/cloud/azure/compute/Azure-VirtualMachines/Get-VMBackupCompliance.ps1"
        $scriptContent = Get-Content -Path $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        . $scriptPath

        # Az cmdlets are absent offline; Pester needs a stub before it can mock by name.
        function Get-AzContext { }
        function Get-AzSubscription { }
        function Set-AzContext { }
        function Get-AzVM { }
        function Get-AzRecoveryServicesVault { }
        function Get-AzRecoveryServicesBackupContainer { }
        function Get-AzRecoveryServicesBackupItem { }
        function Get-AzRecoveryServicesBackupJob { }

        $script:outDir = Join-Path ([System.IO.Path]::GetTempPath()) "bfu-pester-backup-$PID"
        New-Item -ItemType Directory -Path $script:outDir -Force | Out-Null

        Mock Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'Az.RecoveryServices' } { [pscustomobject]@{ Name = 'Az.RecoveryServices' } }
        Mock Import-Module { }
        Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-test' } } }
        Mock Get-AzSubscription { @([pscustomobject]@{ Name = 'sub-test'; Id = '00000000-0000-0000-0000-000000000000' }) }
        Mock Set-AzContext { }

        $script:vm = [pscustomobject]@{
            Name              = 'vm-a'
            ResourceGroupName = 'rg1'
            Location          = 'westeurope'
            Statuses          = @([pscustomobject]@{ Code = 'PowerState/running'; DisplayStatus = 'VM running' })
        }
        Mock Get-AzVM { @($script:vm) }

        $script:vault = [pscustomobject]@{
            Name = 'vault-a'
            Id   = '/subscriptions/s/resourceGroups/rg1/providers/Microsoft.RecoveryServices/vaults/vault-a'
        }
        Mock Get-AzRecoveryServicesVault { @($script:vault) }
        Mock Get-AzRecoveryServicesBackupContainer {
            [pscustomobject]@{ FriendlyName = 'vm-a'; ContainerType = 'AzureVM' }
        }
        Mock Get-AzRecoveryServicesBackupItem {
            [pscustomobject]@{
                ProtectionPolicyName = 'DailyPolicy'
                LastBackupTime       = (Get-Date).AddHours(-6)
            }
        }
        Mock Get-AzRecoveryServicesBackupJob { @() }
    }

    Context "Help & Metadata" {
        It "Declares all five required .NOTES fields with relaunch values" {
            $scriptContent | Should -Match '\.NOTES'
            $scriptContent | Should -Match 'File Name\s*:\s*Get-VMBackupCompliance\.ps1'
            $scriptContent | Should -Match 'Author\s*:\s*\S+'
            $scriptContent | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
            $scriptContent | Should -Match 'Version\s*:\s*1\.0\.0'
            $scriptContent | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Documents one .PARAMETER per declared parameter" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $paramNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $paramNames | Should -Not -BeNullOrEmpty
            foreach ($p in $paramNames) {
                $scriptContent | Should -Match "\.PARAMETER\s+$([regex]::Escape($p))"
            }
            ([regex]::Matches($scriptContent, '(?m)^\.PARAMETER').Count) | Should -Be $paramNames.Count
        }

        It "Provides at least two examples with prompt lines using the real filename" {
            ([regex]::Matches($scriptContent, '(?m)^\.EXAMPLE').Count) | Should -BeGreaterOrEqual 2
            ($scriptContent -split '\.EXAMPLE')[1] | Should -Match 'PS C:\\>\s+\.\\Get-VMBackupCompliance\.ps1'
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero syntax errors" {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
            $errors | Should -HaveCount 0
        }

        It "Wraps execution in Main behind the dot-source guard with exit only in the guard line" {
            $scriptContent | Should -Match 'function Main\b'
            $guardPattern = [regex]::Escape("if (`$MyInvocation.InvocationName -ne '.') { exit (Main @PSBoundParameters) }")
            $scriptContent | Should -Match $guardPattern
            @($scriptContent | Select-String '(?m)^\s*exit\b' | Where-Object { $_.Line -notmatch '@PSBoundParameters' }) | Should -BeNullOrEmpty
        }

        It "Uses no PS7-only operators and no tabs or trailing whitespace" {
            $scriptContent | Should -Not -Match '\?\?'
            $scriptContent | Should -Not -Match "`t"
            @($scriptContent | Select-String '(?m)[ \t]+\r?$') | Should -BeNullOrEmpty
        }
    }

    Context "Behavior" {
        It "Returns 1 when the Az.RecoveryServices module is missing" {
            Mock Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'Az.RecoveryServices' } { $null }
            $out = Main -OutputFormat Console -OutputPath $script:outDir *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 when not logged in to Azure" {
            Mock Get-AzContext { $null }
            $out = Main -OutputFormat Console -OutputPath $script:outDir *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Reports a fresh backup as Compliant at a 100% rate and returns 0" {
            $out = Main -OutputFormat Console -OutputPath $script:outDir *>&1
            $text = $out | Out-String
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text | Should -Match '\[\+\] Compliance Rate: 100%'
            $text | Should -Match '\[\+\].*analysis complete'
            Should -Invoke Get-AzRecoveryServicesBackupContainer -Times 1 -Exactly
            Should -Invoke Get-AzRecoveryServicesBackupItem -Times 1 -Exactly
        }

        It "Flags stale backups as Non-Compliant against the age threshold" {
            Mock Get-AzRecoveryServicesBackupItem {
                [pscustomobject]@{
                    ProtectionPolicyName = 'DailyPolicy'
                    LastBackupTime       = (Get-Date).AddDays(-5)
                }
            }
            $out = Main -BackupAgeThreshold 2 -OutputFormat Console -OutputPath $script:outDir *>&1
            $text = $out | Out-String
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text | Should -Match '=== Non-Compliant Backups ==='
            $text | Should -Match 'Last backup \d+ days ago'
            $text | Should -Match '\[-\] Compliance Rate: 0%'
        }

        It "Lists all VMs as unprotected when no Recovery Services Vault exists" {
            Mock Get-AzRecoveryServicesVault { @() }
            $out = Main -OutputFormat Console -OutputPath $script:outDir *>&1
            $text = $out | Out-String
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text | Should -Match '\[!\] No Recovery Services Vaults found in subscription sub-test'
            $text | Should -Match '=== Unprotected VMs ==='
            $text | Should -Match 'vm-a in rg1 - No Recovery Services Vault configured'
            Should -Invoke Get-AzRecoveryServicesBackupContainer -Times 0 -Exactly
        }

        It "Includes recent backup job analysis when -IncludeBackupJobs is supplied" {
            Mock Get-AzRecoveryServicesBackupJob {
                @(
                    [pscustomobject]@{ JobId = 'j1'; WorkloadName = 'vm-a'; Operation = 'Backup'; Status = 'Completed'; StartTime = (Get-Date).AddHours(-2); EndTime = (Get-Date).AddHours(-1) }
                    [pscustomobject]@{ JobId = 'j2'; WorkloadName = 'vm-b'; Operation = 'Backup'; Status = 'Failed'; StartTime = (Get-Date).AddHours(-3); EndTime = (Get-Date).AddHours(-3).AddMinutes(5) }
                )
            }
            $out = Main -IncludeBackupJobs -OutputFormat Console -OutputPath $script:outDir *>&1
            $text = $out | Out-String
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text | Should -Match 'Retrieved 2 backup jobs'
            Should -Invoke Get-AzRecoveryServicesBackupJob -Times 1 -Exactly
        }
    }
}
