#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/backup/Get-AzureBackupComplianceReport.ps1.

.DESCRIPTION
    Validates help and metadata conformance, static syntax rules, and observable behavior of the Azure
    Backup compliance report using fully mocked Az cmdlets, so no Azure query ever leaves the machine.
    Runs offline on Linux pwsh; no network, Azure connectivity, or installed Az modules are required.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/backup/Get-AzureBackupComplianceReport.Tests.ps1
    Runs this test file.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/backup/Get-AzureBackupComplianceReport.Tests.ps1 -Output Detailed
    Runs this test file with per-test output.

.NOTES
    File Name   : Get-AzureBackupComplianceReport.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-AzureBackupComplianceReport' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            '../../../../scripts/cloud/azure/backup/Get-AzureBackupComplianceReport.ps1'

        # Safe: the script's top-level guard skips Main when dot-sourcing (spec section 3).
        . $scriptPath

        # The Az modules are not installed offline: declare the cmdlets the script calls as advanced
        # functions with their real parameter sets, so an unsupported parameter fails the test instead
        # of passing silently, then Mock each one.
        function Get-AzContext {
            [CmdletBinding()]
            param()
        }
        function Get-AzSubscription {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false)][string]$SubscriptionId
            )
        }
        function Set-AzContext {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false)][string]$SubscriptionId
            )
        }
        function Get-AzRecoveryServicesVault {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false)][string]$ResourceGroupName,
                [Parameter(Mandatory = $false)][string]$Name
            )
        }
        function Get-AzRecoveryServicesVaultProperty {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false)][string]$VaultId
            )
        }
        function Get-AzRecoveryServicesBackupItem {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false)][string]$VaultId,
                [Parameter(Mandatory = $false)][string]$BackupManagementType,
                [Parameter(Mandatory = $false)][string]$WorkloadType
            )
        }
        function Get-AzRecoveryServicesBackupJob {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false)][string]$VaultId,
                [Parameter(Mandatory = $false)][string]$Status,
                [Parameter(Mandatory = $false)][datetime]$From
            )
        }
        function Get-AzVM {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false)][string]$ResourceGroupName
            )
        }

        $script:vaultId = '/subscriptions/sub-1/resourceGroups/rg-backup/providers' +
            '/Microsoft.RecoveryServices/vaults/rsv-prod'

        Mock Import-Module { }
        Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } } }
        Mock Get-AzSubscription { @([pscustomobject]@{ Id = 'sub-1'; Name = 'sub-prod' }) }
        Mock Set-AzContext { }
        Mock Get-AzRecoveryServicesVault {
            @([pscustomobject]@{
                    Name              = 'rsv-prod'
                    Id                = $script:vaultId
                    ResourceGroupName = 'rg-backup'
                    Location          = 'uksouth'
                })
        }
        Mock Get-AzRecoveryServicesVaultProperty {
            [pscustomobject]@{ SoftDeleteFeatureState = 'Enabled' }
        }

        # A healthy protected item: the VM is backed up and the backup is six hours old.
        Mock Get-AzRecoveryServicesBackupItem {
            param($VaultId, $BackupManagementType, $WorkloadType)
            @([pscustomobject]@{
                    FriendlyName     = 'vm-app-1'
                    ContainerName    = 'iaasvmcontainerv2;rg-app;vm-app-1'
                    LastBackupTime   = (Get-Date).AddHours(-6)
                    LastBackupStatus = 'Completed'
                })
        }
        Mock Get-AzRecoveryServicesBackupJob {
            param($VaultId, $Status, $From)
            @()
        }
        Mock Get-AzVM {
            @([pscustomobject]@{ Name = 'vm-app-1'; ResourceGroupName = 'rg-app'; Location = 'uksouth' })
        }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Get-AzureBackupComplianceReport\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            foreach ($name in @('SubscriptionId', 'ResourceGroupName', 'VaultName', 'StaleBackupDays',
                    'OutputFormat', 'OutputPath')) {
                $raw | Should -Match "(?m)\.PARAMETER\s+$name"
            }
        }

        It 'Provides at least two examples with PS prompts' {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, '(?m)^\s*PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }

        It 'Documents the 0, 2 and 1 exit codes' {
            $raw | Should -Match '(?m)Exit codes: 0 ='
            $raw | Should -Match '2 = report produced and findings detected'
            $raw | Should -Match '1 = error'
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $errors.Count | Should -Be 0
        }

        It 'Uses CmdletBinding, Main function, and dot-source guard' {
            $raw | Should -Match '\[CmdletBinding\('
            $raw | Should -Match '(?m)function Main\b'
            $raw | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
        }

        It 'Contains no PS7-only operators and no #Requires opt-out' {
            ($raw -match '\?\?') | Should -BeFalse
            ($raw -match '\|\|') | Should -BeFalse
            ($raw -match '&&') | Should -BeFalse
            ($raw -match '#Requires\s+-Version') | Should -BeFalse
        }

        It 'Is UTF-8 with BOM and CRLF line endings' {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }

        It 'Cites Microsoft Learn and queries the documented Recovery Services cmdlets' {
            $raw | Should -Match 'learn\.microsoft\.com'
            $raw | Should -Match 'Get-AzRecoveryServicesBackupItem'
            $raw | Should -Match 'Get-AzRecoveryServicesBackupJob'
            $raw | Should -Match 'Get-AzRecoveryServicesVaultProperty'
        }
    }

    Context 'Behavior' {
        It 'Returns 0 when every VM is protected, backups are fresh and soft delete is enabled' {
            $SubscriptionId = '*'
            $ResourceGroupName = '*'
            $VaultName = '*'
            $StaleBackupDays = 7
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Connected to: sub-prod'
            $text | Should -Match 'Vaults audited : 1'
            $text | Should -Match 'Protected items: 1'
            $text | Should -Match '\[\+\] No backup compliance findings detected\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-AzRecoveryServicesBackupItem -Times 1 -Exactly `
                -ParameterFilter { $BackupManagementType -eq 'AzureVM' -and $WorkloadType -eq 'AzureVM' }
            Should -Invoke Get-AzRecoveryServicesVaultProperty -Times 1 -Exactly
            Should -Invoke Get-AzRecoveryServicesBackupJob -Times 1 -Exactly `
                -ParameterFilter { $Status -eq 'Failed' }
        }

        It 'Reports all four finding categories and returns 2' {
            $SubscriptionId = '*'
            $ResourceGroupName = '*'
            $VaultName = '*'
            $StaleBackupDays = 7
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Get-AzRecoveryServicesBackupItem {
                param($VaultId, $BackupManagementType, $WorkloadType)
                @([pscustomobject]@{
                        FriendlyName   = 'vm-app-1'
                        ContainerName  = 'iaasvmcontainerv2;rg-app;vm-app-1'
                        LastBackupTime = (Get-Date).AddDays(-9)
                    })
            }
            Mock Get-AzRecoveryServicesBackupJob {
                param($VaultId, $Status, $From)
                @([pscustomobject]@{ JobId = 'job-1'; WorkloadName = 'vm-app-1'; Status = 'Failed' })
            }
            Mock Get-AzRecoveryServicesVaultProperty {
                [pscustomobject]@{ SoftDeleteFeatureState = 'Disabled' }
            }
            Mock Get-AzVM {
                @(
                    [pscustomobject]@{ Name = 'vm-app-1'; ResourceGroupName = 'rg-app' }
                    [pscustomobject]@{ Name = 'vm-orphan'; ResourceGroupName = 'rg-app' }
                )
            }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[!\] 1 virtual machine\(s\) have no backup protection\.'
            $text | Should -Match '\[!\] 1 protected item\(s\) are older than 7 day\(s\)\.'
            $text | Should -Match '\[!\] 1 backup job\(s\) failed in the last 7 day\(s\)\.'
            $text | Should -Match '\[!\] 1 vault\(s\) do not have soft delete enabled\.'
            $text | Should -Match '\[!\] 4 backup compliance finding\(s\) detected\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Honours -StaleBackupDays at the staleness boundary' {
            $SubscriptionId = '*'
            $ResourceGroupName = '*'
            $VaultName = '*'
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Get-AzRecoveryServicesBackupItem {
                param($VaultId, $BackupManagementType, $WorkloadType)
                @([pscustomobject]@{
                        FriendlyName   = 'vm-app-1'
                        ContainerName  = 'iaasvmcontainerv2;rg-app;vm-app-1'
                        LastBackupTime = (Get-Date).AddDays(-8)
                    })
            }

            $StaleBackupDays = 8
            ($StaleBackupDays, (Main *>&1 | Where-Object { $_ -is [int] })) | Out-Null
            $outAtBoundary = Main *>&1
            ($outAtBoundary | Where-Object { $_ -is [int] }) | Should -Be 0 -Because '8 days is not older than 8'
            ($outAtBoundary | Out-String) | Should -Match '\[\+\] No backup compliance findings detected\.'

            $StaleBackupDays = 7
            $outBeyondBoundary = Main *>&1
            ($outBeyondBoundary | Where-Object { $_ -is [int] }) | Should -Be 2 -Because '8 days is older than 7'
            ($outBeyondBoundary | Out-String) | Should -Match '\[!\] 1 protected item\(s\) are older than 7 day\(s\)\.'
        }

        It 'Writes a CSV report to -OutputPath and leaves the working directory untouched' {
            $SubscriptionId = '*'
            $ResourceGroupName = '*'
            $VaultName = '*'
            $StaleBackupDays = 7
            $OutputFormat = 'Csv'
            $OutputPath = $TestDrive
            $workingDirectory = (Get-Location).Path

            Mock Get-AzRecoveryServicesBackupItem {
                param($VaultId, $BackupManagementType, $WorkloadType)
                @([pscustomobject]@{
                        FriendlyName   = 'vm-app-1'
                        ContainerName  = 'iaasvmcontainerv2;rg-app;vm-app-1'
                        LastBackupTime = (Get-Date).AddDays(-9)
                    })
            }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Report written to:'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2

            $reports = @(Get-ChildItem -Path $TestDrive -Filter 'AzureBackupCompliance-*.csv')
            $reports.Count | Should -Be 1
            (Get-Content -LiteralPath $reports[0].FullName -Raw) | Should -Match 'StaleBackup'

            (Get-Location).Path | Should -Be $workingDirectory -Because 'output is only written under -OutputPath'
            @(Get-ChildItem -Path $workingDirectory -Filter 'AzureBackupCompliance-*.csv').Count | Should -Be 0
        }

        It 'Honours the VaultName filter and skips the VM check when only one vault is audited' {
            $SubscriptionId = '*'
            $ResourceGroupName = '*'
            $VaultName = 'rsv-prod'
            $StaleBackupDays = 7
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Get-AzRecoveryServicesVault {
                @(
                    [pscustomobject]@{
                        Name = 'rsv-prod'
                        Id   = $script:vaultId
                    }
                    [pscustomobject]@{
                        Name = 'rsv-legacy'
                        Id   = '/subscriptions/sub-1/resourceGroups/rg-legacy/providers' +
                            '/Microsoft.RecoveryServices/vaults/rsv-legacy'
                    }
                )
            }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match 'Vaults audited : 1'
            $text | Should -Match 'Vault filter active: the UnprotectedVM check is skipped'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-AzRecoveryServicesBackupItem -Times 1 -Exactly `
                -Because 'only the filtered vault is queried'
            Should -Invoke Get-AzVM -Times 0 -Exactly
        }

        It 'Passes the ResourceGroupName filter to the vault and VM queries' {
            $SubscriptionId = '*'
            $ResourceGroupName = 'rg-backup'
            $VaultName = '*'
            $StaleBackupDays = 7
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-AzRecoveryServicesVault -Times 1 -Exactly `
                -ParameterFilter { $ResourceGroupName -eq 'rg-backup' }
            Should -Invoke Get-AzVM -Times 1 -Exactly `
                -ParameterFilter { $ResourceGroupName -eq 'rg-backup' }
        }

        It 'Returns 1 with [-] output when not connected to Azure' {
            $SubscriptionId = '*'
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Get-AzContext { $null }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: Not connected to Azure'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-AzRecoveryServicesVault -Times 0 -Exactly -Because 'the connection check fails first'
        }

        It 'Returns 1 when the Az.Accounts module cannot be imported' {
            $SubscriptionId = '*'
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Import-Module { throw 'Az.Accounts is not installed' }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: Az\.Accounts is not installed'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Returns 1 when every vault query throws' {
            $SubscriptionId = '*'
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Get-AzSubscription { throw 'AuthorizationFailed: the client does not have authorization' }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: AuthorizationFailed'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Is idempotent: repeated read-only runs return the same exit code' {
            $SubscriptionId = '*'
            $ResourceGroupName = '*'
            $VaultName = '*'
            $StaleBackupDays = 7
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Main | Should -Be 0
            Main | Should -Be 0
            Should -Invoke Get-AzRecoveryServicesVault -Times 2 -Exactly -Because 'one query per run'
            Should -Invoke Get-AzRecoveryServicesVaultProperty -Times 2 -Exactly
        }
    }
}
