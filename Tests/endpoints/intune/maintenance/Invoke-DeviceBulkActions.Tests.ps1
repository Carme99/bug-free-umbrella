#Requires -Modules Pester

Describe "Invoke-DeviceBulkActions.ps1" {
    BeforeAll {
        $scriptFile = Join-Path $PSScriptRoot `
            "../../../../scripts/endpoints/intune/maintenance/Invoke-DeviceBulkActions.ps1"
        $rawBytes = [System.IO.File]::ReadAllBytes($scriptFile)
        $rawText = [System.IO.File]::ReadAllText($scriptFile)

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptFile, [ref]$tokens, [ref]$parseErrors)

        # Placeholder definitions so Pester can Mock Graph cmdlets without the module installed.
        function Connect-MgGraph { }
        function Get-MgContext { }
        function Get-MgGroup { }
        function Get-MgGroupMember { }
        function Get-MgDeviceManagementManagedDevice { param([string]$Filter, [string]$ManagedDeviceId) }
        function Invoke-MgSyncDeviceManagementManagedDevice { }
        function Invoke-MgRestartDeviceManagementManagedDevice { }
        function Invoke-MgRetireDeviceManagementManagedDevice { }
        function Invoke-MgWipeDeviceManagementManagedDevice { }
        function Invoke-MgCollectDeviceManagementManagedDeviceDiagnostic { }

        # Safe: the script's top-level guard skips Main when dot-sourced.
        # -Action is mandatory; supplying it keeps dot-sourcing non-interactive while the
        # top-level guard (InvocationName '.') still skips execution.
        . $scriptFile -Action 'Sync'

        # Mock every external surface at command-name level (offline).
        Mock Get-MgContext { [pscustomobject]@{ TenantId = 'tenant-1' } }
        Mock Connect-MgGraph { }
        Mock Get-MgGroup { }
        Mock Get-MgGroupMember { }
        Mock Get-MgDeviceManagementManagedDevice {
            [pscustomobject]@{ Id = 'dev-1'; DeviceName = 'PC1'; ComplianceState = 'compliant' }
        }
        Mock Invoke-MgSyncDeviceManagementManagedDevice { }
        Mock Invoke-MgRestartDeviceManagementManagedDevice { }
        Mock Invoke-MgRetireDeviceManagementManagedDevice { }
        Mock Invoke-MgWipeDeviceManagementManagedDevice { }
        Mock Invoke-MgCollectDeviceManagementManagedDeviceDiagnostic { }
    }

    Context "Help & Metadata" {
        It "Starts with a UTF-8 BOM" {
            ($rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF) | Should -BeTrue
        }

        It "Has all five required .NOTES fields with relaunch values" {
            $rawText | Should -Match '\.NOTES'
            $rawText | Should -Match 'File Name:\s*Invoke-DeviceBulkActions\.ps1'
            $rawText | Should -Match 'Author:\s*\S+'
            $rawText | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
            $rawText | Should -Match 'Version:\s*1\.0\.0'
            $rawText | Should -Match 'Date:\s*2026-08-23'
        }

        It "Has one .PARAMETER entry per declared parameter" {
            $paramCount = $ast.ParamBlock.Parameters.Count
            $helpParams = ([regex]::Matches($rawText, '(?m)^\.PARAMETER')).Count
            $paramCount | Should -Be 5
            $helpParams | Should -Be $paramCount
        }

        It "Declares SupportsShouldProcess for its destructive bulk operations" {
            $rawText | Should -Match '\[CmdletBinding\(SupportsShouldProcess'
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $parseErrors | Should -HaveCount 0
        }

        It "Contains no PS7-only operators" {
            $codeWithoutStrings = [regex]::Replace($rawText, '"[^"]*"|''[^'']*''|#[^\r\n]*', '')
            $codeWithoutStrings | Should -Not -Match '&&'
            $codeWithoutStrings | Should -Not -Match '\|\|'
            $codeWithoutStrings | Should -Not -Match '\?\?'
        }

        It "Defines a Main function" {
            $mainFn = $ast.Find({ param($a)
                $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Main'
            }, $false)
            $mainFn | Should -Not -BeNullOrEmpty
        }

        It "Has the dot-source guard and exit ONLY in the guard line" {
            @( $rawText -split "`r?`n" | Where-Object { $_ -cmatch '(^|[^\w])exit[ (\r\n]' } ).Count | Should -Be 1
            $guardLine = "if (`$MyInvocation.InvocationName -ne '.') { exit (Main) }"
            ($rawText -split "`r?`n") | Should -Contain $guardLine
        }
    }

    Context "Behavior" {
        It "Syncs two named devices and returns 0" {
            Mock Get-MgDeviceManagementManagedDevice {
                [pscustomobject]@{ Id = 'dev-1'; DeviceName = 'PC1'; ComplianceState = 'compliant' }
            }

            $Action = 'Sync'
            $DeviceNames = @('PC1', 'PC2')
            $DeviceFilter = $null
            $GroupName = $null
            $NonCompliantOnly = $false

            Main | Should -Be 0
            Should -Invoke Get-MgDeviceManagementManagedDevice -Times 2 -Exactly
            Should -Invoke Invoke-MgSyncDeviceManagementManagedDevice -Times 2 -Exactly
        }

        It "Honors -WhatIf: no device actions are executed and it returns 0" {
            $Action = 'Wipe'
            $DeviceNames = @('PC1')
            $DeviceFilter = $null
            $GroupName = $null
            $NonCompliantOnly = $false

            $WhatIfPreference = $true
            try {
                Main | Should -Be 0
                Should -Invoke Invoke-MgWipeDeviceManagementManagedDevice -Times 0 -Exactly
            }
            finally {
                $WhatIfPreference = $false
            }
        }

        It "Is idempotent on selection: NonCompliantOnly targets only non-compliant devices" {
            Mock Get-MgDeviceManagementManagedDevice {
                @(
                    [pscustomobject]@{ Id = 'dev-1'; DeviceName = 'PC1'; ComplianceState = 'compliant' },
                    [pscustomobject]@{ Id = 'dev-2'; DeviceName = 'PC2'; ComplianceState = 'noncompliant' }
                )
            }

            $Action = 'Restart'
            $DeviceNames = $null
            $DeviceFilter = $null
            $GroupName = $null
            $NonCompliantOnly = $true

            Main | Should -Be 0
            Should -Invoke Invoke-MgRestartDeviceManagementManagedDevice -Times 1 -Exactly
        }

        It "Returns 0 when no devices match the criteria" {
            Mock Get-MgDeviceManagementManagedDevice { }

            $Action = 'Sync'
            $DeviceNames = $null
            $DeviceFilter = $null
            $GroupName = $null
            $NonCompliantOnly = $false

            Main | Should -Be 0
            Should -Invoke Invoke-MgSyncDeviceManagementManagedDevice -Times 0 -Exactly
        }

        It "Returns 1 with [-] output when Graph authentication fails" {
            Mock Get-MgContext { }
            Mock Connect-MgGraph { throw "no network" }

            $Action = 'Sync'
            $DeviceNames = @('PC1')

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [-] output when a per-device action fails" {
            Mock Get-MgDeviceManagementManagedDevice {
                [pscustomobject]@{ Id = 'dev-1'; DeviceName = 'PC1'; ComplianceState = 'compliant' }
            }
            Mock Invoke-MgSyncDeviceManagementManagedDevice { throw "device offline" }

            $Action = 'Sync'
            $DeviceNames = @('PC1')
            $DeviceFilter = $null
            $GroupName = $null
            $NonCompliantOnly = $false

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
