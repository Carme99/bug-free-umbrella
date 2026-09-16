#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/storage/Get-AzureStorageLifecycleReport.ps1.
.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior
    of the Azure Storage lifecycle coverage report using fully mocked Az cmdlets. Runs
    offline on Linux pwsh; no network, Azure connectivity, or installed product
    modules required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/storage/Get-AzureStorageLifecycleReport.Tests.ps1
    Runs this test file.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/storage/Get-AzureStorageLifecycleReport.Tests.ps1 -Output Detailed
    Runs this test file with per-test output.
.NOTES
    File Name   : Get-AzureStorageLifecycleReport.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-AzureStorageLifecycleReport' {
    BeforeAll {
        $report = '../../../../scripts/cloud/azure/storage/Get-AzureStorageLifecycleReport.ps1'
        $scriptPath = Join-Path $PSScriptRoot $report

        # Safe: the script's top-level guard skips Main when dot-sourced (spec section 3).
        . $scriptPath

        # The Az module is not installed offline: declare its cmdlets as empty advanced
        # functions carrying their real parameter sets, so Pester can mock them and an
        # unsupported parameter fails instead of passing silently.
        function Get-AzContext {
            [CmdletBinding()]
            param([Parameter()][object]$DefaultProfile)
        }
        function Set-AzContext {
            [CmdletBinding()]
            param(
                [Parameter()][string]$SubscriptionId,
                [Parameter()][object]$DefaultProfile
            )
        }
        function Get-AzSubscription {
            [CmdletBinding()]
            param(
                [Parameter()][string]$SubscriptionId,
                [Parameter()][string]$TenantId,
                [Parameter()][string]$SubscriptionName,
                [Parameter()][object]$DefaultProfile
            )
        }
        function Get-AzStorageAccount {
            [CmdletBinding(DefaultParameterSetName = 'ResourceGroupParameterSet')]
            param(
                [Parameter(ParameterSetName = 'ResourceGroupParameterSet', Position = 0)]
                [Parameter(ParameterSetName = 'AccountNameParameterSet', Mandatory = $true, Position = 0)]
                [Parameter(ParameterSetName = 'BlobRestoreParameterSet', Mandatory = $true, Position = 0)]
                [string]$ResourceGroupName,

                [Parameter(ParameterSetName = 'AccountNameParameterSet', Mandatory = $true, Position = 1)]
                [Parameter(ParameterSetName = 'BlobRestoreParameterSet', Mandatory = $true, Position = 1)]
                [string]$Name,

                [Parameter(ParameterSetName = 'AccountNameParameterSet')]
                [switch]$IncludeGeoReplicationStats,

                [Parameter(ParameterSetName = 'BlobRestoreParameterSet')]
                [switch]$IncludeBlobRestoreStatus,

                [switch]$AsJob,

                [Parameter()][object]$DefaultProfile
            )
        }
        function Get-AzStorageAccountManagementPolicy {
            [CmdletBinding(DefaultParameterSetName = 'AccountName')]
            param(
                [Parameter(ParameterSetName = 'AccountName', Mandatory = $true, Position = 0)]
                [string]$ResourceGroupName,

                [Parameter(ParameterSetName = 'AccountName', Mandatory = $true, Position = 1)]
                [string]$StorageAccountName,

                [Parameter(ParameterSetName = 'AccountResourceId', Mandatory = $true, Position = 0)]
                [string]$StorageAccountResourceId,

                [Parameter(ParameterSetName = 'AccountObject', Mandatory = $true)]
                [object]$StorageAccount,

                [Parameter()][object]$DefaultProfile
            )
        }

        $tempBase = $env:TEMP
        if (-not $tempBase) {
            $tempBase = [IO.Path]::GetTempPath()
        }
        $script:tempRoot = Join-Path $tempBase ('bfu-storage-lifecycle-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
        $script:startCwd = (Get-Location).ProviderPath

        $script:policyJson = @'
[
    {
        "Enabled": true,
        "Name": "tier-and-expire",
        "Definition": {
            "Actions": {
                "BaseBlob": {
                    "TierToCool": { "DaysAfterModificationGreaterThan": 30 },
                    "Delete": { "DaysAfterModificationGreaterThan": 365 }
                },
                "Snapshot": {
                    "Delete": { "DaysAfterCreationGreaterThan": 90 }
                }
            },
            "Filters": { "BlobTypes": [ "blockBlob" ] }
        }
    },
    {
        "Enabled": false,
        "Name": "archive-append",
        "Definition": {
            "Actions": {
                "BaseBlob": {
                    "TierToArchive": { "DaysAfterModificationGreaterThan": 120 }
                }
            },
            "Filters": { "BlobTypes": [ "appendBlob" ] }
        }
    }
]
'@

        $script:coveredAccount = [pscustomobject]@{
            StorageAccountName = 'stcovered'
            ResourceGroupName  = 'rg1'
        }
        $script:coveredPolicy = [pscustomobject]@{
            Id                 = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Storage' +
                '/storageAccounts/stcovered/managementPolicies/default'
            StorageAccountName = 'stcovered'
            ResourceGroupName  = 'rg1'
            Rules              = $script:policyJson
        }

        Mock Import-Module { }
        Mock Get-AzContext {
            [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } }
        }
        Mock Set-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } } }
        Mock Get-AzSubscription {
            @([pscustomobject]@{ Id = 'sub-id-1'; Name = 'sub-prod' })
        }
        Mock Get-AzStorageAccount { @($script:coveredAccount) }
        Mock Get-AzStorageAccountManagementPolicy { $script:coveredPolicy }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:tempRoot) {
            Remove-Item -LiteralPath $script:tempRoot -Recurse -Force
        }
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with v2.0.0 values' {
            $raw | Should -Match '(?m)File Name\s*:\s*Get-AzureStorageLifecycleReport\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*2\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-09-16'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            foreach ($name in @('SubscriptionId', 'ResourceGroupName', 'OutputFormat', 'OutputPath')) {
                $raw | Should -Match "(?m)\.PARAMETER\s+$name"
            }
        }

        It 'Provides at least two examples with PS prompts' {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, '(?m)^\s*PS C:\\>')).Count | Should -BeGreaterOrEqual 2
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

        It 'Cites Microsoft Learn in its help' {
            $raw | Should -Match 'learn\.microsoft\.com'
        }
    }

    Context 'Behavior' {
        It 'Reports rule count, blob types and actions for a covered account and exits 0' {
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Azure context: sub-prod'
            $text | Should -Match '\[\+\] rg1/stcovered: 2 rule\(s\), 1 enabled'
            $text | Should -Match 'blob types: appendBlob, blockBlob'
            $text | Should -Match 'actions: .*BaseBlob/Delete'
            $text | Should -Match 'actions: .*Snapshot/Delete'
            $text | Should -Match 'Accounts with a lifecycle policy: 1'
            $text | Should -Match '\[\+\] Lifecycle coverage: every storage account has a lifecycle policy\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-AzStorageAccountManagementPolicy -Times 1 -Exactly `
                -ParameterFilter { $StorageAccountName -eq 'stcovered' -and $ResourceGroupName -eq 'rg1' }
        }

        It 'Flags an account whose policy read fails as not found, with exit 2' {
            Mock Get-AzStorageAccountManagementPolicy {
                throw 'ManagementPolicyNotFound: The management policy was not found.'
            }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\!\] rg1/stcovered: no lifecycle policy'
            $text | Should -Match 'MissingLifecyclePolicy'
            $text | Should -Match '\[\!\] Lifecycle gaps: 1 storage account\(s\) have no policy\.'
            ($text -match 'Report incomplete') | Should -BeFalse
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Exits 1 when the policy read fails for a reason other than a missing policy' {
            Mock Get-AzStorageAccountManagementPolicy { throw 'provider error' }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\!\] Failed to read lifecycle policy for rg1/stcovered: provider error'
            $text | Should -Match '\[\!\] Report incomplete: one or more lifecycle queries failed\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Exits 1 when a policy document cannot be parsed' {
            Mock Get-AzStorageAccountManagementPolicy {
                [pscustomobject]@{
                    Id                 = '/managementPolicies/default'
                    StorageAccountName = 'stcovered'
                    ResourceGroupName  = 'rg1'
                    Rules              = 'this is not json'
                }
            }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\!\] Failed to parse lifecycle policy for rg1/stcovered:'
            $text | Should -Match '\[\!\] Report incomplete'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Counts covered and uncovered accounts separately' {
            Mock Get-AzStorageAccount {
                @(
                    $script:coveredAccount
                    [pscustomobject]@{ StorageAccountName = 'stnopolicy'; ResourceGroupName = 'rg1' }
                )
            }
            Mock Get-AzStorageAccountManagementPolicy {
                if ($StorageAccountName -eq 'stcovered') {
                    $script:coveredPolicy
                }
                else {
                    throw 'The management policy was not found for the storage account.'
                }
            }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\+\] rg1/stcovered: 2 rule\(s\), 1 enabled'
            $text | Should -Match '\[\!\] rg1/stnopolicy: no lifecycle policy'
            $text | Should -Match 'Accounts with a lifecycle policy: 1'
            $text | Should -Match 'Gaps: 1'
            $text | Should -Match '\[\!\] Lifecycle gaps: 1 storage account\(s\) have no policy\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Exits 1 with a [-] message when there is no Azure context' {
            Mock Get-AzContext { $null }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\].*Not connected to Azure'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-AzStorageAccountManagementPolicy -Times 0 -Exactly `
                -Because 'context check fails first'
        }

        It 'Applies the subscription and resource group filter to the inventory query' {
            $SubscriptionId = '22222222-2222-2222-2222-222222222222'
            $ResourceGroupName = 'rg-prod'
            try {
                Main | Should -Be 0
                Should -Invoke Get-AzSubscription -Times 1 -Exactly `
                    -ParameterFilter { $SubscriptionId -eq '22222222-2222-2222-2222-222222222222' }
                Should -Invoke Get-AzStorageAccount -Times 1 -Exactly `
                    -ParameterFilter { $ResourceGroupName -eq 'rg-prod' }
            }
            finally {
                $SubscriptionId = '*'
                $ResourceGroupName = $null
            }
        }

        It 'Writes a JSON report under the temp directory without changing the working directory' {
            $OutputFormat = 'Json'
            $OutputPath = Join-Path $script:tempRoot 'json'
            try {
                $out = Main *>&1
                ($out | Out-String) | Should -Match '\[\+\] JSON report written:'
                $files = @(Get-ChildItem -LiteralPath $OutputPath -Filter '*.json')
                $files.Count | Should -Be 1
                $report = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
                $report.AccountsWithPolicy | Should -Be 1
                @($report.Coverage).Count | Should -Be 1
                @($report.Coverage)[0].Rules | Should -Be 2
                @($report.Findings).Count | Should -Be 0
                ($out | Where-Object { $_ -is [int] }) | Should -Be 0
                (Get-Location).ProviderPath | Should -Be $script:startCwd
            }
            finally {
                $OutputFormat = 'Table'
                $OutputPath = $null
            }
        }

        It 'Rejects an unsafe OutputPath without querying Azure' {
            $OutputPath = '..\..\escape'
            try {
                $out = Main *>&1
                ($out | Out-String) | Should -Match '\[-\] Unsafe OutputPath:'
                ($out | Where-Object { $_ -is [int] }) | Should -Be 1
                Should -Invoke Get-AzSubscription -Times 0 -Exactly
            }
            finally {
                $OutputPath = $null
            }
        }
    }
}
