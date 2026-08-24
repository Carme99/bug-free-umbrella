#Requires -Modules Pester

<#
.SYNOPSIS
    Pester 5 tests for scripts/cloud/azure/avd/New-AzureComputeGalleryImage.ps1.

.DESCRIPTION
    Validates header/metadata conformance, static syntax rules, and observable
    behavior of the Azure Compute Gallery image pipeline. All Az cmdlets are
    stubbed then mocked at command-name level (the Az module is not required
    offline), so the suite runs green on Linux pwsh with no network access.

.NOTES
    File Name: New-AzureComputeGalleryImage.Tests.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

Describe "New-AzureComputeGalleryImage" {
    BeforeAll {
        # Mirrored layout: Tests/cloud/azure/avd/ -> script is four levels up + across.
        $scriptPath = Join-Path $PSScriptRoot "../../../../scripts/cloud/azure/avd/New-AzureComputeGalleryImage.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # The Az module is not installed offline: create resolvable stubs so Pester can mock them.
        foreach ($azCommand in @(
                'Connect-AzAccount', 'Get-AzContext', 'Get-AzVM', 'Get-AzGallery',
                'Get-AzGalleryImageDefinition', 'Get-AzGalleryImageVersion', 'Get-AzVirtualNetwork',
                'Get-AzVirtualNetworkSubnetConfig', 'Get-AzDisk', 'New-AzResourceGroup',
                'New-AzSnapshotConfig', 'New-AzSnapshot', 'New-AzDiskConfig', 'New-AzDisk',
                'New-AzVMConfig', 'Set-AzVMBootDiagnostic', 'Set-AzVMOSDisk', 'New-AzNetworkInterface',
                'Add-AzVMNetworkInterface', 'New-AzVM', 'Invoke-AzVMRunCommand', 'Stop-AzVM',
                'Set-AzVM', 'New-AzImageConfig', 'Set-AzImageOsDisk', 'New-AzImage',
                'New-AzGalleryImageVersion', 'Remove-AzResourceGroup'
            )) {
            if (-not (Get-Command $azCommand -ErrorAction SilentlyContinue)) {
                . ([scriptblock]::Create("function global:$azCommand { }"))
            }
        }

        Mock Connect-AzAccount { }
        Mock Get-AzContext {
            [pscustomobject]@{
                Subscription = [pscustomobject]@{ Name = 'sub' }
                Tenant       = [pscustomobject]@{ Id = 'tenant-id' }
            }
        }
        Mock Get-AzVM { $script:vmStub }
        Mock Get-AzGallery { [pscustomobject]@{ Name = 'MyGallery' } }
        Mock Get-AzGalleryImageDefinition { [pscustomobject]@{ Name = 'Win11-Enterprise' } }
        Mock Get-AzGalleryImageVersion { @() }
        Mock Get-AzVirtualNetwork { [pscustomobject]@{ Id = 'vnet-id' } }
        Mock Get-AzVirtualNetworkSubnetConfig { [pscustomobject]@{ Id = 'subnet-id' } }
        Mock Get-AzDisk { [pscustomobject]@{ Id = 'disk-id' } }
        Mock New-AzResourceGroup { [pscustomobject]@{ ResourceGroupName = 'acg-temp' } }
        Mock New-AzSnapshotConfig { [pscustomobject]@{ } }
        Mock New-AzSnapshot { [pscustomobject]@{ Id = 'snapshot-id'; Location = 'eastus' } }
        Mock New-AzDiskConfig { [pscustomobject]@{ } }
        Mock New-AzDisk { [pscustomobject]@{ Id = 'managed-disk-id' } }
        Mock New-AzVMConfig { [pscustomobject]@{ VMName = 'clone' } }
        Mock Set-AzVMBootDiagnostic {
            param([Parameter(ValueFromPipeline)][object]$VM, [switch]$Disable)
            $VM
        }
        Mock Set-AzVMOSDisk {
            param([object]$VM, $ManagedDiskId, $CreateOption, [switch]$Windows)
            $VM
        }
        Mock New-AzNetworkInterface { [pscustomobject]@{ Id = 'nic-id' } }
        Mock Add-AzVMNetworkInterface {
            param([object]$VM, $Id)
            $VM
        }
        Mock New-AzVM { [pscustomobject]@{ } }
        Mock Wait-ForVMAgent { $true }
        Mock Invoke-AzVMRunCommand { [pscustomobject]@{ } }
        Mock Stop-AzVM { [pscustomobject]@{ } }
        Mock Set-AzVM { [pscustomobject]@{ } }
        Mock New-AzImageConfig { [pscustomobject]@{ } }
        Mock Set-AzImageOsDisk {
            param([Parameter(ValueFromPipeline)][object]$Image, $OsState, $OsType, $ManagedDiskId)
            $Image
        }
        Mock New-AzImage { [pscustomobject]@{ Id = 'image-id' } }
        Mock New-AzGalleryImageVersion { [pscustomobject]@{ } }
        Mock Remove-AzResourceGroup { [pscustomobject]@{ } }
        Mock Add-Content { }   # keep file logging inert during tests

        $script:vmStub = [pscustomobject]@{
            Name     = 'WIN11-GOLD'
            Statuses = @([pscustomobject]@{ Code = 'PowerState/Running'; DisplayStatus = 'VM running' })
            StorageProfile = [pscustomobject]@{
                OsDisk = [pscustomobject]@{ Name = 'os-disk'; HyperVGeneration = 'V2'; EncryptionSettings = $null }
            }
        }

        # Bind explicit-parameter-set values consumed by Main via dynamic scoping.
        # Dot-execute (. $script:testConfiguration) inside each It so the values land in
        # the It scope, shadowing the param() defaults captured when the script was sourced.
        $script:testConfiguration = {
            $ParameterSetName      = 'Explicit'   # force the explicit-parameter branch
            $TenantId              = '00000000-0000-0000-0000-000000000001'
            $SubscriptionId        = '00000000-0000-0000-0000-000000000002'
            $Location              = 'East US'
            $SourceVMName          = 'WIN11-GOLD'
            $SourceVMResourceGroup = 'rg-images'
            $GalleryResourceGroup  = 'rg-images'
            $GalleryName           = 'MyGallery'
            $ImageDefinitionName   = 'Win11-Enterprise'
            $VNetName              = 'vnet-prod'
            $VNetResourceGroup     = 'rg-network'
            $SubnetName            = 'snet-images'
            $VMSize                = 'Standard_D2s_v3'
            $VersioningStrategy    = 'Major'
            $SkipAgentCheck        = $true
            $SkipCleanup           = $false
            $SkipPreFlightChecks   = $true
            $Force                 = $true
            $WhatIf                = $false
        }

        function Get-MainOutputText {
            param($Output)
            ($Output | ForEach-Object { $_.ToString() }) -join "`n"
        }
    }

    Context "Help & Metadata" {
        BeforeAll {
            $content = Get-Content $scriptPath -Raw
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Resolve-Path $scriptPath).Path, [ref]$null, [ref]$errors)
            $paramNames = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $paramNames.Count | Should -BeGreaterThan 0

            $helpNames = @([regex]::Matches($content, '(?m)^\.PARAMETER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
        }

        It "Declares all five required .NOTES fields with relaunch values" {
            $content | Should -Match ([regex]::Escape('File Name: New-AzureComputeGalleryImage.ps1'))
            $content | Should -Match '(?m)^\s*Author:\s+\S'
            $content | Should -Match ([regex]::Escape('Prerequisite: PowerShell 7.0'))
            $content | Should -Match ([regex]::Escape('Version: 1.0.0'))
            $content | Should -Match ([regex]::Escape('Date: 2026-08-23'))
        }

        It "Documents one .PARAMETER per declared parameter, in param() order" {
            $helpNames.Count | Should -Be $paramNames.Count
            for ($i = 0; $i -lt $paramNames.Count; $i++) {
                $helpNames[$i] | Should -Be $paramNames[$i] -Because "parameter $($paramNames[$i]) must be documented in order"
            }
        }

        It "Has at least two examples with a PS C:\> prompt line" {
            ([regex]::Matches($content, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            $content | Should -Match 'PS C:\\>'
        }

        It "Renders Get-Help -Detailed completely" {
            $help = Get-Help (Resolve-Path $scriptPath).Path -Detailed
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
            @($help.Parameters.Parameter.Name).Count | Should -BeGreaterOrEqual $paramNames.Count
        }
    }

    Context "Syntax & Static" {
        BeforeAll {
            $content = Get-Content $scriptPath -Raw
            $errors = $null
            $tokens = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                (Resolve-Path $scriptPath).Path, [ref]$tokens, [ref]$errors)
        }

        It "Parses without syntax errors" {
            @($errors).Count | Should -Be 0
        }

        It "Contains no PS7-only operators (no #Requires -Version 7.0 opt-out present)" {
            $content | Should -Not -Match '#Requires\s+-Version'
            $content | Should -Not -Match '\|\|'
            $content | Should -Not -Match '&&'
            $content | Should -Not -Match '\?\?'
            $tokens.Kind | Should -Not -Contain 'QuestionMark'
            $tokens.Kind | Should -Not -Contain 'AndAnd'
            $tokens.Kind | Should -Not -Contain 'OrOr'
        }

        It "Is UTF-8 with BOM and uses CRLF line endings throughout" {
            $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $scriptPath).Path)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
            [regex]::IsMatch($content, '(?<!\r)\n') | Should -BeFalse -Because "bare LF endings are not allowed"
        }

        It "Uses 4-space indent (no tabs), no trailing whitespace, max 120 columns" {
            foreach ($line in (Get-Content $scriptPath)) {
                $line | Should -Not -Match "`t"
                $line | Should -Not -Match ' +$'
                $line.Length | Should -BeLessOrEqual 120
            }
        }

        It "Wraps execution in Main and exits only via the dot-source guard" {
            $guardPattern = [regex]::Escape("if (`$MyInvocation.InvocationName -ne '.') { exit (Main) }")
            $content | Should -Match '(?m)^function Main \{'
            $content | Should -Match $guardPattern
            ($content -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\bexit\b' }).Count | Should -Be 1
        }
    }

    Context "Behavior" {
        It "Runs the full publish pipeline against mocked Az cmdlets and returns 0" {
            . $script:testConfiguration
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Get-MainOutputText $out | Should -Match '\[\+\]'
            Get-MainOutputText $out | Should -Match '\[\*\]'
            Should -Invoke New-AzResourceGroup -Times 1 -Exactly
            Should -Invoke Invoke-AzVMRunCommand -Times 1 -Exactly
            Should -Invoke New-AzGalleryImageVersion -Times 1 -Exactly
            Should -Invoke Remove-AzResourceGroup -Times 1 -Exactly -Because "temporary resources are cleaned up by default"
        }

        It "Is idempotent in dry-run mode: validates then exits 0 creating nothing" {
            . $script:testConfiguration
            $WhatIf = $true
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Get-MainOutputText $out | Should -Match 'Dry-run completed successfully'
            Should -Invoke New-AzResourceGroup -Times 0 -Exactly -Because "a converged/dry run makes zero mutations"
            Should -Invoke New-AzSnapshot -Times 0 -Exactly
            Should -Invoke New-AzVM -Times 0 -Exactly
            Should -Invoke New-AzGalleryImageVersion -Times 0 -Exactly
            Should -Invoke Remove-AzResourceGroup -Times 0 -Exactly
        }

        It "Returns 1 and writes [-] output when Azure authentication fails" {
            . $script:testConfiguration
            Mock Connect-AzAccount { throw "auth service unreachable" }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Get-MainOutputText $out | Should -Match '\[-\]'
            Should -Invoke New-AzResourceGroup -Times 0 -Exactly -Because "no resources may be created after auth failure"
        }

        It "Returns 1 when the source VM cannot be found" {
            . $script:testConfiguration
            Mock Get-AzVM { $null }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Get-MainOutputText $out | Should -Match "Source VM 'WIN11-GOLD' not found"
            Should -Invoke New-AzSnapshot -Times 0 -Exactly
        }
    }
}
