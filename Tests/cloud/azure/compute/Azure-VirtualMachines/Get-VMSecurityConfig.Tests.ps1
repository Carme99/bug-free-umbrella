<#
.SYNOPSIS
    Pester 5 tests for scripts/cloud/azure/compute/Azure-VirtualMachines/Get-VMSecurityConfig.ps1.

.DESCRIPTION
    Offline Pester coverage: help/metadata conformance, syntax/static checks, and behavior of
    Main against fully mocked Az PowerShell cmdlets. No network, admin rights, or modules
    beyond Pester are required.

.NOTES
    File Name   : Get-VMSecurityConfig.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

#Requires -Modules Pester

Describe "Get-VMSecurityConfig" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../../../scripts/cloud/azure/compute/Azure-VirtualMachines/Get-VMSecurityConfig.ps1"
        $scriptContent = Get-Content -Path $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        . $scriptPath

        # Az cmdlets are absent offline; Pester needs a stub before it can mock by name.
        function Get-AzContext { }
        function Get-AzSubscription { }
        function Set-AzContext { }
        function Get-AzVM { }
        function Get-AzVMDiskEncryptionStatus { }
        function Get-AzNetworkInterface { }
        function Get-AzVMExtension { }

        $script:outDir = Join-Path ([System.IO.Path]::GetTempPath()) "bfu-pester-vmsec-$PID"
        New-Item -ItemType Directory -Path $script:outDir -Force | Out-Null

        Mock Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'Az.Compute' } { [pscustomobject]@{ Name = 'Az.Compute' } }
        Mock Import-Module { }
        Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-test' } } }
        Mock Get-AzSubscription { @([pscustomobject]@{ Name = 'sub-test'; Id = '00000000-0000-0000-0000-000000000000' }) }
        Mock Set-AzContext { }
        Mock Get-AzVM { @($script:hardenedVm) }

        # Fully hardened VM: encrypted OS disk, NSG attached, no public IP, boot diagnostics on.
        $script:nsgNic = [pscustomobject]@{
            Id              = '/subscriptions/s/resourceGroups/rg1/providers/Microsoft.Network/networkInterfaces/nic-a'
            IpConfigurations = @([pscustomobject]@{ PublicIpAddress = $null })
            NetworkSecurityGroup = [pscustomobject]@{ Name = 'nsg-a' }
        }
        $script:hardenedVm = [pscustomobject]@{
            Name              = 'vm-hardened'
            ResourceGroupName = 'rg1'
            Location          = 'westeurope'
            StorageProfile    = [pscustomobject]@{ OsDisk = [pscustomobject]@{ OsType = 'Windows' } }
            Statuses          = @([pscustomobject]@{ Code = 'PowerState/running'; DisplayStatus = 'VM running' })
            NetworkProfile    = [pscustomobject]@{ NetworkInterfaces = @($script:nsgNic) }
            DiagnosticsProfile = [pscustomobject]@{ BootDiagnostics = [pscustomobject]@{ Enabled = $true } }
            Identity          = $null
        }

        Mock Get-AzVMDiskEncryptionStatus {
            [pscustomobject]@{ OsVolumeEncrypted = 'Encrypted'; DataVolumesEncrypted = 'Encrypted' }
        }
        Mock Get-AzNetworkInterface { $script:nsgNic }
        Mock Get-AzVMExtension { @() }
    }

    Context "Help & Metadata" {
        It "Declares all five required .NOTES fields with relaunch values" {
            $scriptContent | Should -Match '\.NOTES'
            $scriptContent | Should -Match 'File Name\s*:\s*Get-VMSecurityConfig\.ps1'
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
            ($scriptContent -split '\.EXAMPLE')[1] | Should -Match 'PS C:\\>\s+\.\\Get-VMSecurityConfig\.ps1'
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
        It "Returns 1 when the Az.Compute module is missing" {
            Mock Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'Az.Compute' } { $null }
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

        It "Rates a hardened VM Excellent with zero findings and returns 0" {
            $out = Main -CheckEncryption -CheckNetworkSecurity -OutputFormat Console -OutputPath $script:outDir *>&1
            $text = $out | Out-String
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text | Should -Match '\[\+\] Security Findings: 0 \(0 high severity\)'
            $text | Should -Match '\[\+\].*audit complete'
            Should -Invoke Get-AzVMDiskEncryptionStatus -Times 1 -Exactly
            Should -Invoke Get-AzNetworkInterface -Times 1 -Exactly
        }

        It "Flags unencrypted OS disks as a high-severity finding" {
            Mock Get-AzVMDiskEncryptionStatus {
                [pscustomobject]@{ OsVolumeEncrypted = 'NotEncrypted'; DataVolumesEncrypted = 'NotEncrypted' }
            }
            $out = Main -CheckEncryption -OutputFormat Console -OutputPath $script:outDir *>&1
            $text = $out | Out-String
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text | Should -Match 'OS disk encryption not enabled'
            $text | Should -Match '\[!\] Security Findings: 1 \(1 high severity\)'
        }

        It "Flags public IPs and missing NSGs as findings" {
            $exposedNic = [pscustomobject]@{
                Id                   = $script:nsgNic.Id
                IpConfigurations     = @([pscustomobject]@{ PublicIpAddress = [pscustomobject]@{ Name = 'pip-a' } })
                NetworkSecurityGroup = $null
            }
            Mock Get-AzNetworkInterface { $exposedNic }
            $out = Main -CheckNetworkSecurity -OutputFormat Console -OutputPath $script:outDir *>&1
            $text = $out | Out-String
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text | Should -Match 'No NSG protection'
            $text | Should -Match '\[!\] Security Findings: 2 \(1 high severity\)'
            Should -Invoke Get-AzNetworkInterface -Times 1 -Exactly
        }

        It "Is idempotent: repeated runs are read-only and both succeed" {
            $first = Main -OutputFormat Console -OutputPath $script:outDir *>&1
            $second = Main -OutputFormat Console -OutputPath $script:outDir *>&1
            $first | Where-Object { $_ -is [int] } | Should -Be 0
            $second | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Get-AzVM -Times 2 -Exactly -Because "each run re-reads state and mutates nothing"
        }
    }
}
