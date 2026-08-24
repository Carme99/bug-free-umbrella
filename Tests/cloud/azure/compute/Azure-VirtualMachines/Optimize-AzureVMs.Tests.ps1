<#
.SYNOPSIS
    Pester 5 tests for scripts/cloud/azure/compute/Azure-VirtualMachines/Optimize-AzureVMs.ps1.

.DESCRIPTION
    Offline Pester coverage: help/metadata conformance, syntax/static checks, and behavior of
    Main against fully mocked Az PowerShell cmdlets. No network, admin rights, or modules
    beyond Pester are required.

.NOTES
    File Name   : Optimize-AzureVMs.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

#Requires -Modules Pester

Describe "Optimize-AzureVMs" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../../../scripts/cloud/azure/compute/Azure-VirtualMachines/Optimize-AzureVMs.ps1"
        $scriptContent = Get-Content -Path $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        . $scriptPath

        # Az cmdlets are absent offline; Pester needs a stub before it can mock by name.
        function Get-AzContext { }
        function Get-AzSubscription { }
        function Set-AzContext { }
        function Get-AzVM { }
        function Get-AzMetric { }

        $script:outDir = Join-Path ([System.IO.Path]::GetTempPath()) "bfu-pester-optimize-vms-$PID"
        New-Item -ItemType Directory -Path $script:outDir -Force | Out-Null

        # Module guard passes without the real Az module installed; other Get-Module calls fall through.
        Mock Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'Az.Compute' } { [pscustomobject]@{ Name = 'Az.Compute' } }
        Mock Import-Module { }
        Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-test' } } }
        Mock Get-AzSubscription { @([pscustomobject]@{ Name = 'sub-test'; Id = '00000000-0000-0000-0000-000000000000' }) }
        Mock Set-AzContext { }
        Mock Get-AzVM { @($script:runningVm) }
        Mock Get-AzMetric {
            [pscustomobject]@{
                Data = @(
                    [pscustomobject]@{ Average = 5 }
                    [pscustomobject]@{ Average = 7 }
                )
            }
        }

        $script:runningVm = [pscustomobject]@{
            Name                     = 'vm-a'
            ResourceGroupName        = 'rg1'
            Location                 = 'westeurope'
            Id                       = '/subscriptions/s/resourceGroups/rg1/providers/Microsoft.Compute/virtualMachines/vm-a'
            HardwareProfile          = [pscustomobject]@{ VmSize = 'Standard_D2s_v3' }
            StorageProfile           = [pscustomobject]@{
                OsDisk = [pscustomobject]@{
                    OsType      = 'Windows'
                    ManagedDisk = [pscustomobject]@{ StorageAccountType = 'Standard_LRS' }
                }
            }
            Statuses                 = @([pscustomobject]@{ Code = 'PowerState/running'; DisplayStatus = 'VM running' })
            AvailabilitySetReference = $null
            Zones                    = @()
        }
    }

    Context "Help & Metadata" {
        It "Declares all five required .NOTES fields with relaunch values" {
            $scriptContent | Should -Match '\.NOTES'
            $scriptContent | Should -Match 'File Name\s*:\s*Optimize-AzureVMs\.ps1'
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
            ($scriptContent -split '\.EXAMPLE')[1] | Should -Match 'PS C:\\>\s+\.\\Optimize-AzureVMs\.ps1'
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
        It "Returns 1 and writes [-] output when the Az.Compute module is missing" {
            Mock Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'Az.Compute' } { $null }
            $out = Main -OutputFormat Console -OutputPath $script:outDir *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 and writes [-] output when not logged in to Azure" {
            Mock Get-AzContext { $null }
            $out = Main -OutputFormat Console -OutputPath $script:outDir *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Analyzes a running underutilized VM and returns 0 with summary output" {
            $out = Main -GenerateRecommendations -OutputFormat Console -OutputPath $script:outDir *>&1
            $text = $out | Out-String
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text | Should -Match '\[\+\].*Azure VM optimization analysis complete'
            $text | Should -Match '\[!\] Underutilized VMs: 1'
            $text | Should -Match '\[!\] \[Right-Sizing\]'
            Should -Invoke Get-AzMetric -Times 1 -Exactly
            Should -Invoke Set-AzContext -Times 1 -Exactly
        }

        It "Is idempotent: repeated runs are read-only and both succeed" {
            $first = Main -OutputFormat Console -OutputPath $script:outDir *>&1
            $second = Main -OutputFormat Console -OutputPath $script:outDir *>&1
            $first | Where-Object { $_ -is [int] } | Should -Be 0
            $second | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Get-AzVM -Times 2 -Exactly -Because "each run re-reads state and mutates nothing"
        }

        It "Lists stopped-but-allocated VMs without querying metrics" {
            $stoppedVm = [pscustomobject]@{
                Name                     = 'vm-stopped'
                ResourceGroupName        = 'rg1'
                Location                 = 'westeurope'
                Id                       = '/subscriptions/s/resourceGroups/rg1/providers/Microsoft.Compute/virtualMachines/vm-stopped'
                HardwareProfile          = [pscustomobject]@{ VmSize = 'Standard_D4s_v3' }
                StorageProfile           = [pscustomobject]@{
                    OsDisk = [pscustomobject]@{
                        OsType      = 'Windows'
                        ManagedDisk = [pscustomobject]@{ StorageAccountType = 'Premium_LRS' }
                    }
                }
                Statuses                 = @([pscustomobject]@{ Code = 'PowerState/stopped'; DisplayStatus = 'VM stopped' })
                AvailabilitySetReference = $null
                Zones                    = @()
            }
            Mock Get-AzVM { @($stoppedVm) }
            $out = Main -OutputFormat Console -OutputPath $script:outDir *>&1
            $text = $out | Out-String
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text | Should -Match 'Stopped VMs \(Still Incurring Costs\)'
            $text | Should -Match 'vm-stopped in rg1'
            Should -Invoke Get-AzMetric -Times 0 -Exactly -Because "metrics are only gathered for running VMs"
        }

        It "Rejects unsafe OutputPath traversal with exit code 1" {
            $out = Main -OutputFormat Console -OutputPath "../evil-reports" *>&1
            ($out | Out-String) | Should -Match 'Unsafe OutputPath'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
