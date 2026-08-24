#Requires -Modules Pester

Describe "Get-IntuneDevicePrimaryUsers" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/endpoints/intune/reporting/ ->
        # the script is four levels up plus across under scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/intune/reporting/Get-IntuneDevicePrimaryUsers.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # The script's $OutputPath default resolves $env:USERPROFILE at dot-source time;
        # guarantee it exists on Linux CI.
        if (-not $env:USERPROFILE) { $env:USERPROFILE = $HOME }

        # Stub product-module cmdlets not installed on this machine so Pester can mock them.
        # Signatures mirror the parameters the script passes so Pester -ParameterFilter
        # variables ($Filter, $UserId, ...) bind correctly.
        function Connect-MgGraph { param($Scopes, $NoWelcome) }
        function Disconnect-MgGraph { }
        function Invoke-MgGraphRequest { param($Method, $Uri, $OutputType) }
        function Get-MgDeviceManagementManagedDevice { param($ManagedDeviceId, $Filter, $Property, $Top) }
        function Get-MgDevice { param($Filter, $DeviceId, $Property, $ConsistencyLevel) }
        function Get-MgDeviceRegisteredOwner { param($DeviceId, $All) }
        function Get-MgUser { param($Filter, $UserId, $ConsistencyLevel) }

        # Safe: the top-level guard skips Main when dot-sourced.
        . $scriptPath

        $matchObject = {
            [pscustomobject]@{
                id                = 'md-1'
                deviceName        = 'LTW1010013'
                userPrincipalName = 'alice@contoso.com'
                azureAdDeviceId   = 'aad-guid-0001'
                lastSyncDateTime  = [datetime]'2026-08-23T10:00:00'
            }
        }

        $detailObject = {
            [pscustomobject]@{
                id                       = 'md-1'
                deviceName               = 'LTW1010013'
                azureAdDeviceId          = 'aad-guid-0001'
                userPrincipalName        = 'alice@contoso.com'
                lastSyncDateTime         = [datetime]'2026-08-23T10:00:00'
                manufacturer             = 'Dell Inc.'
                model                    = 'Latitude 7440'
                serialNumber             = 'SERV1CE'
                operatingSystem          = 'Windows'
                osVersion                = '10.0.26100'
                totalStorageSpaceInBytes = 512110190592
                freeStorageSpaceInBytes  = 256055095296
                physicalMemoryInBytes    = 34359738368
                processorArchitecture    = 'x64'
                hardwareInformation      = [pscustomobject]@{
                    processorName           = 'AuthenticAMD  Ryzen 5  7640HS'
                    processorManufacturer   = $null
                }
            }
        }

        # Mock ALL external commands so nothing leaves the machine (offline Linux CI).
        Mock Get-Module { [pscustomobject]@{ Name = 'Microsoft.Graph.Authentication' } } -ParameterFilter {
            $ListAvailable -and $Name -eq 'Microsoft.Graph.Authentication'
        }
        Mock Connect-MgGraph { }
        Mock Disconnect-MgGraph { }
        Mock Get-MgDeviceManagementManagedDevice { & $matchObject }
        Mock Invoke-MgGraphRequest {
            param($Uri)
            if ($Uri -like '*/users?*') {
                # managedDevice/users primary-user relation
                [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{
                            id = 'u-1'; userPrincipalName = 'alice@contoso.com'; displayName = 'Alice Anderson'
                        }
                    )
                }
            }
            else { & $detailObject }
        }
        Mock Get-MgDevice { } -ParameterFilter { $Filter -like 'displayName eq*' }
        Mock Get-MgDevice {
            [pscustomobject]@{
                id                  = 'ent-1'
                displayName         = 'LTW1010013'
                deviceId            = 'aad-guid-0001'
                extensionAttributes = [pscustomobject]@{ extensionAttribute1 = ' Latitude 7440 Dev' }
            }
        } -ParameterFilter { $Filter -like 'deviceId eq*' }
        Mock Get-MgDeviceRegisteredOwner { @() }
        Mock Get-MgUser { } -ParameterFilter { $Filter -like 'userPrincipalName eq*' }
        Mock Get-MgUser {
            [pscustomobject]@{ Id = 'u-1'; DisplayName = 'Alice Anderson' }
        } -ParameterFilter { $UserId -eq 'u-1' }
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '(?m)^\s*File Name\s*:\s*Get-IntuneDevicePrimaryUsers\.ps1\s*$'
            $raw | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
            $raw | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
            $raw | Should -Match '(?m)^\s*Prerequisite\s*:\s*PowerShell 7\.0\s*$'
        }

        It "Has SYNOPSIS, DESCRIPTION and at least two EXAMPLES with PS C:\> prompts" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
            (Get-Content -Path $scriptPath -Raw) | Should -Match 'PS C:\\>'
        }

        It "Declares one .PARAMETER per param() parameter, in declaration order" {
            $toks = $null
            $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$toks, [ref]$errs)
            $declaredParams = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $documentedParams = @(Select-String -Path $scriptPath -Pattern '^\s*\.PARAMETER\s+(\S+)' |
                ForEach-Object { $_.Matches[0].Groups[1].Value })
            $documentedParams.Count | Should -Be $declaredParams.Count
            $documentedParams | Should -Be $declaredParams
        }
    }

    Context "Syntax & Static" {
        BeforeAll {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        }
        It "Parses with zero errors" {
            $errors | Should -BeNullOrEmpty
        }
        It "Contains no PS7-only operators (no #Requires -Version 7.0 opt-out present)" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Not -Match '(?m)&&|\|\||\?\?|\?\??='
        }
        It "Uses exit only in the top-level dot-source guard line" {
            $findExit = { $args[0] -is [System.Management.Automation.Language.ExitStatementAst] }
            $exitStatements = @($ast.FindAll($findExit, $true))
            $exitStatements.Count | Should -Be 1
            $exitStatements[0].Parent.ToString() | Should -Match 'exit \(Main\)'
        }
        It "Is saved as UTF-8 with BOM and CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
            [System.IO.File]::ReadAllText($scriptPath) | Should -Not -Match '(?<!\r)\n'
        }
        It "Uses only approved verbs for its functions" {
            $approved = (Get-Verb | Select-Object -ExpandProperty Verb)
            $findFn = { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }
            $functions = @($ast.FindAll($findFn, $true))
            $functions | Should -Not -BeNullOrEmpty
            foreach ($fn in ($functions | Where-Object { $_.Name -ne 'Main' })) {
                ($fn.Name -split '-')[0] | Should -BeIn $approved -Because "$($fn.Name) must use an approved verb"
            }
        }
    }

    Context "Behavior" {
        It "Resolves primary user via the Intune users relation, exports CSV and returns 0" {
            $OutputPath = Join-Path ([System.IO.Path]::GetTempPath()) "puitest_$PID.csv"
            $DeviceName = @('LTW1010013')

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[\*\] Connecting to Microsoft Graph'
            $text | Should -Match '\[\+\] Saved to:'
            Test-Path $OutputPath | Should -BeTrue

            $row = (Import-Csv $OutputPath)[0]
            $row.DeviceName | Should -Be 'LTW1010013'
            $row.PrimaryUserUPN | Should -Be 'alice@contoso.com'
            $row.PrimaryUserDisplayName | Should -Be 'Alice Anderson'
            $row.Source | Should -Be 'Intune managedDevice/users (beta)'
            $row.Manufacturer | Should -Be 'Dell Inc.'
            $row.FriendlyModel | Should -Be 'Latitude 7440 Dev'
            $row.CPU | Should -Be 'AMD Ryzen 5 7640HS'
            [int]$row.RAM_GB | Should -Be 32
            Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
        }

        It "Falls back to managedDevice.userPrincipalName when the users relation is empty" {
            Mock Invoke-MgGraphRequest {
                param($Uri)
                if ($Uri -like '*/users?*') {
                    [pscustomobject]@{ value = @() }
                }
                else { & $detailObject }
            }
            Mock Get-MgUser {
                [pscustomobject]@{ DisplayName = 'Alice FromUpn' }
            } -ParameterFilter { $Filter -like 'userPrincipalName eq*' }

            $OutputPath = Join-Path ([System.IO.Path]::GetTempPath()) "puitest_upn_$PID.csv"
            $DeviceName = @('LTW1010013')

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0

            $row = (Import-Csv $OutputPath)[0]
            $row.PrimaryUserUPN | Should -Be 'alice@contoso.com'
            $row.PrimaryUserDisplayName | Should -Be 'Alice FromUpn'
            $row.Source | Should -Be 'managedDevice.userPrincipalName'
            Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
        }

        It "Reports devices not found in Intune without failing" {
            Mock Get-MgDeviceManagementManagedDevice { $null }

            $OutputPath = Join-Path ([System.IO.Path]::GetTempPath()) "puitest_nf_$PID.csv"
            $DeviceName = @('UNKNOWN-LT')

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0

            $row = (Import-Csv $OutputPath)[0]
            $row.DeviceName | Should -Be 'UNKNOWN-LT'
            $row.Source | Should -Be 'Not found in Intune'
            Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
        }

        It "Skips CSV export and returns 0 when -NoExport is set" {
            $NoExport = $true
            $DeviceName = @('LTW1010013')

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\*\] NoExport specified\. Skipping CSV export\.'
        }

        It "Warns and returns 0 when no usable device names are supplied" {
            $DeviceName = @('')

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
                ForEach-Object { $_.Message } | Should -Contain 'No usable device names found. Exiting.'
        }

        It "Returns 1 when the Microsoft.Graph.Authentication module is missing" {
            Mock Get-Module { $null } -ParameterFilter {
                $ListAvailable -and $Name -eq 'Microsoft.Graph.Authentication'
            }
            $DeviceName = @('LTW1010013')

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] Microsoft\.Graph\.Authentication module not found!'
        }

        It "Suppresses [*]-prefixed INFO output when -Quiet is set" {
            $Quiet = $true
            $NoExport = $true
            $DeviceName = @('LTW1010013')

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Not -Match '\[\*\] Connecting to Microsoft Graph'
        }

        It "Is idempotent: repeated read-only runs both return 0" {
            $DeviceName = @('LTW1010013')
            (Main *>&1) | Where-Object { $_ -is [int] } | Should -Be 0
            (Main *>&1) | Where-Object { $_ -is [int] } | Should -Be 0
        }
    }
}
