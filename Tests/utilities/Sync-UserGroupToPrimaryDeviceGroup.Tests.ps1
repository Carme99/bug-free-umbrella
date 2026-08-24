#Requires -Modules Pester

Describe "Sync-UserGroupToPrimaryDeviceGroup" {
    BeforeAll {
        # Stub Microsoft Graph commands so Pester can mock them without the module installed.
        function Connect-MgGraph { }
        function Disconnect-MgGraph { }
        function Get-MgGroup { }
        function Get-MgGroupMember { }
        function Get-MgUserManagedDevice { }
        function Get-MgDevice { }
        function New-MgGroupMember { param($GroupId, $DirectoryObjectId) }
        function Remove-MgGroupMemberByRef { param($GroupId, $DirectoryObjectId) }

        # Mirrored layout: this file lives at Tests/utilities/ -> script is two levels up.
        $scriptPath = Join-Path $PSScriptRoot "../../scripts/utilities/Sync-UserGroupToPrimaryDeviceGroup.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        # Graph entry points are mocked at command-name level; no module install or network needed.
        . $scriptPath

        $sourceGroup = [pscustomobject]@{ Id = 'src-group-1'; DisplayName = 'All Users' }
        $targetGroup = [pscustomobject]@{ Id = 'tgt-group-1'; DisplayName = 'Primary Devices' }
        $sourceMember = [pscustomobject]@{
            Id                   = 'user-1'
            AdditionalProperties = @{ displayName = 'Alice'; userPrincipalName = 'alice@contoso.com' }
        }
        $primaryDevice = [pscustomobject]@{
            Id              = 'device-1'
            DeviceName      = 'PC-ALICE'
            IsManaged       = $true
            AzureAdDeviceId = 'aad-device-1'
            OperatingSystem = 'Windows'
            LastSyncDateTime = $null
        }

        Mock Connect-MgGraph { }
        Mock Disconnect-MgGraph { }
        Mock Get-MgGroup {
            param($Filter)
            if ($Filter -like "*All Users*") { @($sourceGroup) } else { @($targetGroup) }
        }
        Mock Get-MgGroupMember {
            param($GroupId)
            if ($GroupId -eq 'src-group-1') { @($sourceMember) } else { @() }
        }
        Mock Get-MgUserManagedDevice { @($primaryDevice) }
        Mock Get-MgDevice { @([pscustomobject]@{ Id = 'aad-device-1' }) }
        Mock New-MgGroupMember { }
        Mock Remove-MgGroupMemberByRef { }
    }

    Context "Help & Metadata" {
        It "Declares File Name, Version 1.0.0 and relaunch Date 2026-08-23 in the header" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match 'File Name:\s*Sync-UserGroupToPrimaryDeviceGroup\.ps1'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
            $raw | Should -Match 'Author:\s*\S+'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
        }

        It "Has one .PARAMETER entry per declared parameter, in declaration order" {
            $tokens = $null; $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declared = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)

            $helpParams = [regex]::Matches((Get-Content -Raw $scriptPath), '\.PARAMETER\s+(\w+)') |
                ForEach-Object { $_.Groups[1].Value }

            $helpParams.Count | Should -Be $declared.Count
            $helpParams | Should -Be $declared
        }

        It "Provides SYNOPSIS, DESCRIPTION and at least two EXAMPLES with PS C:\> prompts" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match '\.SYNOPSIS'
            $raw | Should -Match '\.DESCRIPTION'
            ([regex]::Matches($raw, '\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses cleanly with zero parser errors" {
            $tokens = $null; $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only tokens (opt-out requires line 1)" {
            $raw = Get-Content -Raw $scriptPath
            $requiresV7 = ($raw -split "`r?`n")[0] -match '#Requires\s+-Version\s+7'
            if (-not $requiresV7) {
                $tokens = $null; $parseErrors = $null
                [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
                $badKinds = $tokens | Where-Object {
                    $_.Kind.ToString() -in @('QuestionMark', 'QuestionQuestion', 'AmpersandAmpersand', 'PipePipe')
                }
                $badKinds | Should -BeNullOrEmpty -Because "PS7-only operators need #Requires -Version 7.0 on line 1"
            }
        }

        It "Uses UTF-8 BOM and CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            ($text -replace "`r`n", '') | Should -Not -Match "`n"
        }
    }

    Context "Behavior" {
        It "Connects to Graph, resolves both groups and returns 0 on a successful sync run" {
            $out = Main -SourceGroupName 'All Users' -TargetGroupName 'Primary Devices' *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Connect-MgGraph -Times 1 -Exactly
            Should -Invoke Disconnect-MgGraph -Times 1 -Exactly -Because "finally must always disconnect"
            Should -Invoke Get-MgGroupMember -Times 2 -Exactly -Because "source and target membership are both read"
            Should -Invoke Get-MgUserManagedDevice -Times 1 -Exactly
        }

        It "Is idempotent: an in-sync target group mutates nothing and reports no changes needed" {
            # Target group already contains the device's directory id.
            Mock Get-MgGroupMember {
                param($GroupId)
                if ($GroupId -eq 'src-group-1') { @($sourceMember) }
                else { @([pscustomobject]@{ Id = 'aad-device-1'; AdditionalProperties = @{} }) }
            }

            $out = Main -SourceGroupName 'All Users' -TargetGroupName 'Primary Devices' *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'No changes needed'
            Should -Invoke New-MgGroupMember -Times 0 -Exactly
            Should -Invoke Remove-MgGroupMemberByRef -Times 0 -Exactly
        }

        It "Adds missing primary devices to the target group after interactive confirmation" {
            Mock Read-Host { 'Y' }

            $out = Main -SourceGroupName 'All Users' -TargetGroupName 'Primary Devices' *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke New-MgGroupMember -Times 1 -Exactly
            Should -Invoke New-MgGroupMember `
                -ParameterFilter { $DirectoryObjectId -eq 'aad-device-1' } -Times 1 -Exactly
            Should -Invoke Remove-MgGroupMemberByRef -Times 0 -Exactly
        }

        It "Removes stale devices from the target group during a full sync" {
            Mock Read-Host { 'Y' }
            # Target group holds a stale member that is not among the desired devices.
            Mock Get-MgGroupMember {
                param($GroupId)
                if ($GroupId -eq 'src-group-1') { @($sourceMember) }
                else { @([pscustomobject]@{ Id = 'stale-device-id'; AdditionalProperties = @{} }) }
            }

            $out = Main -SourceGroupName 'All Users' -TargetGroupName 'Primary Devices' *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke New-MgGroupMember -Times 1 -Exactly
            Should -Invoke Remove-MgGroupMemberByRef -Times 1 -Exactly
            Should -Invoke Remove-MgGroupMemberByRef `
                -ParameterFilter { $DirectoryObjectId -eq 'stale-device-id' } -Times 1 -Exactly
        }

        It "Returns 1 and writes [-] prefixed output when Graph lookup fails" {
            Mock Get-MgGroup { throw "network unreachable" }

            $out = Main -SourceGroupName 'All Users' -TargetGroupName 'Primary Devices' *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
            Should -Invoke Disconnect-MgGraph -Times 1 -Exactly -Because "finally must still disconnect"
        }
    }
}
