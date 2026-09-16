#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/backup/Test-AzureRecoveryVaultRedundancy.ps1.

.DESCRIPTION
    Validates help and metadata conformance, static syntax rules, and observable behavior of the vault
    redundancy audit using fully mocked Az cmdlets, so no Azure query ever leaves the machine. Runs
    offline on Linux pwsh; no network, Azure connectivity, or installed Az modules are required.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/backup/Test-AzureRecoveryVaultRedundancy.Tests.ps1
    Runs this test file.

.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/backup/Test-AzureRecoveryVaultRedundancy.Tests.ps1 -Output Detailed
    Runs this test file with per-test output.

.NOTES
    File Name   : Test-AzureRecoveryVaultRedundancy.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Test-AzureRecoveryVaultRedundancy' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            '../../../../scripts/cloud/azure/backup/Test-AzureRecoveryVaultRedundancy.ps1'

        # Safe: the script's top-level guard skips Main when dot-sourcing (spec section 3).
        . $scriptPath

        # The Az modules are not installed offline: declare the cmdlets the script calls as advanced
        # functions with their real parameter sets, so an unsupported parameter fails the test instead
        # of passing silently, then Mock each one. -Vault is typed [object] because the ARSVault type
        # only exists in the real module.
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
        function Get-AzRecoveryServicesBackupProperty {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false)][object]$Vault
            )
        }

        # One vault per supported redundancy tier, plus the redundancy each one reports.
        $script:redundancyByVault = @{
            'rsv-geo'   = 'GeoRedundant'
            'rsv-geoz'  = 'GeoZoneRedundant'
            'rsv-zone'  = 'ZoneRedundant'
            'rsv-local' = 'LocallyRedundant'
        }
        $script:allVaults = @(
            foreach ($name in @('rsv-geo', 'rsv-geoz', 'rsv-zone', 'rsv-local')) {
                [pscustomobject]@{
                    Name              = $name
                    Id                = '/subscriptions/sub-1/resourceGroups/rg-backup/providers' +
                        '/Microsoft.RecoveryServices/vaults/' + $name
                    ResourceGroupName = 'rg-backup'
                    Location          = 'uksouth'
                }
            }
        )

        Mock Import-Module { }
        Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } } }
        Mock Get-AzSubscription { @([pscustomobject]@{ Id = 'sub-1'; Name = 'sub-prod' }) }
        Mock Set-AzContext { }
        Mock Get-AzRecoveryServicesVault { @($script:allVaults) }
        Mock Get-AzRecoveryServicesBackupProperty {
            param($Vault)
            [pscustomobject]@{
                BackupStorageRedundancy = [string]$script:redundancyByVault[$Vault.Name]
                CrossRegionRestore      = $true
            }
        }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Test-AzureRecoveryVaultRedundancy\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            foreach ($name in @('SubscriptionId', 'MinimumRedundancy', 'IncludeCrossRegionRestore',
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
            $raw | Should -Match '2 = findings detected'
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

        It 'Cites Microsoft Learn and reads the documented redundancy cmdlet' {
            $raw | Should -Match 'learn\.microsoft\.com'
            $raw | Should -Match 'Get-AzRecoveryServicesBackupProperty'
            $raw | Should -Match 'BackupStorageRedundancy'
            $raw | Should -Match 'CrossRegionRestore'
        }
    }

    Context 'Behavior' {
        It 'Returns 0 when every vault is geo-redundant and cross-region restore is enabled' {
            $SubscriptionId = '*'
            $MinimumRedundancy = 'GeoRedundant'
            $IncludeCrossRegionRestore = $false
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Get-AzRecoveryServicesVault {
                @($script:allVaults | Where-Object { $_.Name -in @('rsv-geo', 'rsv-geoz') })
            }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Connected to: sub-prod'
            $text | Should -Match 'Vaults audited    : 2'
            $text | Should -Match 'Minimum redundancy: GeoRedundant'
            $text | Should -Match 'rsv-geo : GeoRedundant \(cross-region restore: Enabled\)'
            $text | Should -Match '\[\+\] All vaults meet the minimum redundancy of GeoRedundant\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-AzRecoveryServicesBackupProperty -Times 2 -Exactly `
                -ParameterFilter { $null -ne $Vault }
        }

        It 'Flags every vault below the minimum and returns 2' {
            $SubscriptionId = '*'
            $MinimumRedundancy = 'GeoRedundant'
            $IncludeCrossRegionRestore = $false
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[!\] 2 vault\(s\) are below the minimum'
            $text | Should -Match '\[!\] 2 redundancy finding\(s\) detected\.'
            $text | Should -Match 'rsv-local : LocallyRedundant'
            $text | Should -Match 'rsv-zone : ZoneRedundant'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2 -Because 'zone and local are below geo'
        }

        It 'Ranks geo-zone above geo, geo above zone, and zone above local' {
            $SubscriptionId = '*'
            $IncludeCrossRegionRestore = $false
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            $MinimumRedundancy = 'LocallyRedundant'
            (Main *>&1 | Where-Object { $_ -is [int] }) | Should -Be 0 -Because 'every vault meets local'

            $MinimumRedundancy = 'ZoneRedundant'
            $outAtZone = Main *>&1
            ($outAtZone | Where-Object { $_ -is [int] }) | Should -Be 2 -Because 'only the local vault fails'
            ($outAtZone | Out-String) | Should -Match '\[!\] 1 vault\(s\) are below the minimum'

            $MinimumRedundancy = 'GeoZoneRedundant'
            $outAtGeoZone = Main *>&1
            ($outAtGeoZone | Where-Object { $_ -is [int] }) | Should -Be 2 -Because 'only rsv-geoz meets it'
            ($outAtGeoZone | Out-String) | Should -Match '\[!\] 3 vault\(s\) are below the minimum'
        }

        It 'Treats an unrecognised redundancy type as below the minimum' {
            $SubscriptionId = '*'
            $MinimumRedundancy = 'LocallyRedundant'
            $IncludeCrossRegionRestore = $false
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Get-AzRecoveryServicesBackupProperty {
                param($Vault)
                [pscustomobject]@{ BackupStorageRedundancy = 'RA-GZRS'; CrossRegionRestore = $true }
            }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[!\] 4 vault\(s\) are below the minimum'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2 -Because 'compliance cannot be proven'
        }

        It 'Reports cross-region-restore state and only flags it when asked' {
            $SubscriptionId = '*'
            $MinimumRedundancy = 'LocallyRedundant'
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Get-AzRecoveryServicesBackupProperty {
                param($Vault)
                [pscustomobject]@{
                    BackupStorageRedundancy = [string]$script:redundancyByVault[$Vault.Name]
                    CrossRegionRestore      = $false
                }
            }

            $IncludeCrossRegionRestore = $false
            $outWithout = Main *>&1
            ($outWithout | Out-String) | Should -Match 'rsv-geo : GeoRedundant \(cross-region restore: Disabled\)'
            ($outWithout | Where-Object { $_ -is [int] }) | Should -Be 0 -Because 'the switch gates the finding'

            $IncludeCrossRegionRestore = $true
            $outWith = Main *>&1
            $textWith = $outWith | Out-String
            $textWith | Should -Match '\[!\] 2 vault\(s\) do not have cross-region restore enabled\.'
            $textWith | Should -Match '\[!\] 2 redundancy finding\(s\) detected\.'
            ($outWith | Where-Object { $_ -is [int] }) | Should -Be 2 -Because 'only the geo vaults are in scope'
        }

        It 'Writes a CSV report to -OutputPath and leaves the working directory untouched' {
            $SubscriptionId = '*'
            $MinimumRedundancy = 'LocallyRedundant'
            $IncludeCrossRegionRestore = $false
            $OutputFormat = 'Csv'
            $OutputPath = $TestDrive
            $workingDirectory = (Get-Location).Path

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[\+\] Report written to:'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0

            $reports = @(Get-ChildItem -Path $TestDrive -Filter 'AzureVaultRedundancy-*.csv')
            $reports.Count | Should -Be 1
            $csv = Get-Content -LiteralPath $reports[0].FullName -Raw
            $csv | Should -Match 'GeoRedundant'
            $csv | Should -Match 'LocallyRedundant'
            $csv | Should -Match 'CrossRegionRestore'

            (Get-Location).Path | Should -Be $workingDirectory -Because 'output is only written under -OutputPath'
            @(Get-ChildItem -Path $workingDirectory -Filter 'AzureVaultRedundancy-*.csv').Count | Should -Be 0
        }

        It 'Returns 1 with [-] output when not connected to Azure' {
            $SubscriptionId = '*'
            $MinimumRedundancy = 'GeoRedundant'
            $IncludeCrossRegionRestore = $false
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Get-AzContext { $null }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: Not connected to Azure'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-AzRecoveryServicesBackupProperty -Times 0 -Exactly `
                -Because 'the connection check fails first'
        }

        It 'Returns 1 when the Az.Accounts module cannot be imported' {
            $SubscriptionId = '*'
            $MinimumRedundancy = 'GeoRedundant'
            $IncludeCrossRegionRestore = $false
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Import-Module { throw 'Az.Accounts is not installed' }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match '\[-\] Error: Az\.Accounts is not installed'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Skips a vault whose backup properties cannot be read and still audits the rest' {
            $SubscriptionId = '*'
            $MinimumRedundancy = 'GeoRedundant'
            $IncludeCrossRegionRestore = $false
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Mock Get-AzRecoveryServicesBackupProperty {
                param($Vault)
                if ($Vault.Name -eq 'rsv-geo') { throw 'VaultNotFound: the vault was not found' }
                [pscustomobject]@{
                    BackupStorageRedundancy = [string]$script:redundancyByVault[$Vault.Name]
                    CrossRegionRestore      = $true
                }
            }

            $out = Main *>&1
            $text = $out | Out-String

            $text | Should -Match "\[!\] Failed to read the backup properties of 'rsv-geo'"
            $text | Should -Match 'Vaults audited    : 3'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2 -Because 'the two sub-geo vaults remain findings'
        }

        It 'Is idempotent: repeated read-only runs return the same exit code' {
            $SubscriptionId = '*'
            $MinimumRedundancy = 'LocallyRedundant'
            $IncludeCrossRegionRestore = $false
            $OutputFormat = 'Table'
            $OutputPath = $TestDrive

            Main | Should -Be 0
            Main | Should -Be 0
            Should -Invoke Get-AzRecoveryServicesBackupProperty -Times 8 -Exactly -Because 'four vaults per run'
        }
    }
}
