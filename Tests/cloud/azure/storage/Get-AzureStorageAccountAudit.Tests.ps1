#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/azure/storage/Get-AzureStorageAccountAudit.ps1.
.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior
    of the Azure Storage account security audit using fully mocked Az cmdlets. Runs
    offline on Linux pwsh; no network, Azure connectivity, or installed product
    modules required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/storage/Get-AzureStorageAccountAudit.Tests.ps1
    Runs this test file.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/azure/storage/Get-AzureStorageAccountAudit.Tests.ps1 -Output Detailed
    Runs this test file with per-test output.
.NOTES
    File Name   : Get-AzureStorageAccountAudit.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 2.0.0
    Date        : 2026-09-16
#>

Describe 'Get-AzureStorageAccountAudit' {
    BeforeAll {
        $audit = '../../../../scripts/cloud/azure/storage/Get-AzureStorageAccountAudit.ps1'
        $scriptPath = Join-Path $PSScriptRoot $audit

        # Safe: the script's top-level guard skips Main when dot-sourced (spec section 3).
        . $scriptPath

        # The Az module is not installed offline: declare its cmdlets as empty advanced
        # functions carrying their real parameter sets, so Pester can mock them and an
        # unsupported parameter fails instead of passing silently.
        function Get-AzContext {
            [CmdletBinding()]
            param()
        }
        function Set-AzContext {
            [CmdletBinding()]
            param([string]$SubscriptionId, [string]$SubscriptionName, [string]$Name)
        }
        function Get-AzSubscription {
            [CmdletBinding()]
            param([string]$SubscriptionId, [string]$SubscriptionName, [string]$TenantId)
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

        $tempBase = $env:TEMP
        if (-not $tempBase) {
            $tempBase = [IO.Path]::GetTempPath()
        }
        $script:tempRoot = Join-Path $tempBase ('bfu-storage-account-audit-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
        $script:startCwd = (Get-Location).ProviderPath

        $script:compliantAccount = [pscustomobject]@{
            StorageAccountName    = 'stcompliant'
            ResourceGroupName     = 'rg1'
            Id                    = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.Storage' +
                '/storageAccounts/stcompliant'
            AllowBlobPublicAccess = $false
            AllowSharedKeyAccess  = $false
            MinimumTlsVersion     = 'TLS1_2'
            NetworkRuleSet        = [pscustomobject]@{ DefaultAction = 'Deny' }
            Encryption            = [pscustomobject]@{
                KeySource                       = 'Microsoft.Keyvault'
                RequireInfrastructureEncryption = $true
            }
        }

        Mock Import-Module { }
        Mock Get-AzContext {
            [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } }
        }
        Mock Set-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sub-prod' } } }
        Mock Get-AzSubscription {
            @([pscustomobject]@{ Id = 'sub-id-1'; Name = 'sub-prod' })
        }
        Mock Get-AzStorageAccount { @($script:compliantAccount) }

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
            $raw | Should -Match '(?m)File Name\s*:\s*Get-AzureStorageAccountAudit\.ps1'
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
        It 'Reports a compliant storage account and exits 0' {
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Azure context: sub-prod'
            $text | Should -Match '\[\+\] Inventory: 1 storage account\(s\)'
            $text | Should -Match '\[\+\] Audit complete: no findings\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-AzSubscription -Times 1 -Exactly
            Should -Invoke Get-AzStorageAccount -Times 1 -Exactly
        }

        It 'Flags every hardening gap on a permissive account with exit 2' {
            Mock Get-AzStorageAccount {
                @(
                    [pscustomobject]@{
                        StorageAccountName    = 'stopen'
                        ResourceGroupName     = 'rg1'
                        AllowBlobPublicAccess = $true
                        AllowSharedKeyAccess  = $true
                        MinimumTlsVersion     = 'TLS1_0'
                        NetworkRuleSet        = [pscustomobject]@{ DefaultAction = 'Allow' }
                        Encryption            = [pscustomobject]@{
                            KeySource                       = 'Microsoft.Storage'
                            RequireInfrastructureEncryption = $false
                        }
                    }
                )
            }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match 'rg1/stopen'
            $text | Should -Match 'PublicBlobAccessEnabled'
            $text | Should -Match 'SharedKeyAccessEnabled'
            $text | Should -Match 'WeakMinimumTlsVersion'
            $text | Should -Match 'NetworkDefaultAllow'
            $text | Should -Match 'MissingInfrastructureEncryption'
            $text | Should -Match 'MissingCustomerManagedKey'
            $text | Should -Match '\[\!\] Audit complete: 6 finding\(s\) require review\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Treats absent account properties as insecure defaults' {
            Mock Get-AzStorageAccount {
                @(
                    [pscustomobject]@{
                        StorageAccountName = 'stbare'
                        ResourceGroupName  = 'rg1'
                    }
                )
            }

            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match 'rg1/stbare'
            $text | Should -Match 'SharedKeyAccessEnabled'
            $text | Should -Match 'WeakMinimumTlsVersion'
            $text | Should -Match 'NetworkDefaultAllow'
            $text | Should -Match 'MissingInfrastructureEncryption'
            $text | Should -Match 'MissingCustomerManagedKey'
            ($text -match 'PublicBlobAccessEnabled') | Should -BeFalse
            $text | Should -Match '\[\!\] Audit complete: 5 finding\(s\) require review\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 2
        }

        It 'Exits 1 with a [-] message when there is no Azure context' {
            Mock Get-AzContext { $null }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\].*Not connected to Azure'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Get-AzStorageAccount -Times 0 -Exactly -Because 'context check fails first'
        }

        It 'Exits 1 when an inventory query fails so the audit is incomplete' {
            Mock Get-AzStorageAccount { throw 'provider error' }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\!\] Failed to read storage accounts: provider error'
            $text | Should -Match '\[\!\] Audit incomplete: one or more inventory queries failed\.'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It 'Audits every accessible subscription when SubscriptionId is wildcard' {
            Mock Get-AzSubscription {
                @(
                    [pscustomobject]@{ Id = 'sub-id-1'; Name = 'sub-prod' }
                    [pscustomobject]@{ Id = 'sub-id-2'; Name = 'sub-dev' }
                )
            }
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\*\] Auditing 2 subscription\(s\)'
            $text | Should -Match '\[\*\] Auditing subscription: sub-dev'
            Should -Invoke Set-AzContext -Times 2 -Exactly
            Should -Invoke Get-AzStorageAccount -Times 2 -Exactly
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
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
                $report.AccountsAudited | Should -Be 1
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
