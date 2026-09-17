#Requires -Modules Pester

Describe "Add-LenovoFriendlyModelNames.ps1" {
    BeforeAll {
        $scriptFile = Join-Path $PSScriptRoot `
            "../../../../scripts/endpoints/intune/maintenance/Add-LenovoFriendlyModelNames.ps1"
        $rawBytes = [System.IO.File]::ReadAllBytes($scriptFile)
        $rawText = [System.IO.File]::ReadAllText($scriptFile)
        # Placeholder definitions so Pester can Mock Graph cmdlets without the module installed.
        function Connect-MgGraph { }
        function Disconnect-MgGraph { }
        function Invoke-MgGraphRequest { }
        function Get-MgDeviceManagementManagedDevice { }
        function Update-MgDeviceManagementManagedDevice { }

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptFile, [ref]$tokens, [ref]$parseErrors)

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptFile

        # Mock every external surface at command-name level (offline).
        Mock Disconnect-MgGraph { }
        Mock Connect-MgGraph { }
        # Full signature: an empty param() stub cannot expose -Uri/-Method to a
        # -ParameterFilter, so assertions against specific Graph calls would silently
        # match nothing.
        Mock Invoke-MgGraphRequest {
            param([string]$Uri, [string]$Method, $Body)
        }
        Mock Start-Sleep { }
        Mock Invoke-RestMethod { }
        Mock Get-MgDeviceManagementManagedDevice { }
        Mock Update-MgDeviceManagementManagedDevice { }
    }

    Context "Help & Metadata" {
        It "Starts with a UTF-8 BOM" {
            ($rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF) | Should -BeTrue
        }

        It "Has all five required .NOTES fields with relaunch values" {
            $rawText | Should -Match '\.NOTES'
            $rawText | Should -Match 'File Name:\s*Add-LenovoFriendlyModelNames\.ps1'
            $rawText | Should -Match 'Author:\s*\S+'
            $rawText | Should -Match 'Prerequisite:\s*PowerShell 5\.1\+'
            $rawText | Should -Match 'Version:\s*2\.0\.0'
            $rawText | Should -Match 'Date:\s*2026-09-16'
        }

        It "Has one .PARAMETER entry per declared parameter" {
            # The contract is one documented .PARAMETER per declared parameter; the absolute
            # count is incidental and must not be pinned, or every added parameter breaks it.
            $paramCount = $ast.ParamBlock.Parameters.Count
            $helpParams = ([regex]::Matches($rawText, '(?m)^\.PARAMETER')).Count
            $helpParams | Should -Be $paramCount
        }

        It "Declares SupportsShouldProcess for its bulk update operations" {
            $rawText | Should -Match '\[CmdletBinding\(SupportsShouldProcess'
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $parseErrors | Should -HaveCount 0
        }

        It "Contains no PS7-only operators (targets PowerShell 5.1+)" {
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
            $guardLine = 'if ($MyInvocation.InvocationName -ne ''.'') { exit (Main) }'
            ($rawText -split "`r?`n") | Should -Contain $guardLine
        }
    }

    Context "Behavior" {
        It "Audits mappings in AuditOnly mode: returns 0 and performs no updates" {
            Mock Get-MgDeviceManagementManagedDevice {
                [pscustomobject]@{
                    id = 'dev-1';
                    deviceName = 'LAPTOP01';
                    model = '21AHS0AB00';
                    notes = '';
                    azureADDeviceId = 'aad-1'
                }
            }
            Mock Invoke-RestMethod {
                @([pscustomobject]@{ name = 'ThinkPad T14 Gen 3 (Type 21AH, 21AJ)' })
            }

            $AuditOnly = $true
            Main | Should -Be 0
            Should -Invoke Update-MgDeviceManagementManagedDevice -Times 0 -Exactly
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
        }

        It "Updates Intune Notes and Entra extension attributes for unmapped devices" {
            Mock Get-MgDeviceManagementManagedDevice {
                [pscustomobject]@{
                    id = 'dev-1';
                    deviceName = 'LAPTOP01';
                    model = '21AHS0AB00';
                    notes = '';
                    azureADDeviceId = 'aad-1'
                }
            }
            Mock Invoke-RestMethod {
                @([pscustomobject]@{ name = 'ThinkPad T14 Gen 3 (Type 21AH, 21AJ)' })
            }
            Mock Update-MgDeviceManagementManagedDevice { }
            # Record the Graph traffic rather than filtering the shared stub: the filter cannot see
            # named parameters reliably and would silently match nothing.
            $script:graphCalls = @()
            Mock Invoke-MgGraphRequest {
                param([string]$Uri, [string]$Method, $Body)
                $script:graphCalls += [pscustomobject]@{ Uri = $Uri; Method = $Method }
            }
            $AuditOnly = $false
            $UpdateExtensionAttributes = $true
            Main | Should -Be 0
            Should -Invoke Update-MgDeviceManagementManagedDevice -Times 1 -Exactly -Because "the note is empty"
            # Extension attributes are not on the Intune managedDevice resource, so the read comes
            # from /v1.0/devices and the write goes to the Entra device.
            @($script:graphCalls | Where-Object { $_.Method -eq 'GET' -and $_.Uri -like '*/v1.0/devices*' }).Count |
                Should -Be 1 -Because "the Entra device extension attributes are read once"
            @($script:graphCalls | Where-Object { $_.Method -eq 'PATCH' -and $_.Uri -like '/v1.0/devices/*' }).Count |
                Should -Be 1 -Because "the extension attribute is written to the Entra device"
        }

        It "Is idempotent with extension attributes enabled: a converged device is not re-PATCHed" {
            # The Intune managedDevice resource has NO extensionAttributes property, so the
            # current value can only come from the Entra device resource. This fixture models
            # both seams the way Graph actually behaves: the managed device carries no
            # extensionAttributes, and they are supplied by the Entra /devices collection.
            Mock Get-MgDeviceManagementManagedDevice {
                [pscustomobject]@{
                    id = 'dev-1';
                    deviceName = 'LAPTOP01';
                    model = '21AHS0AB00';
                    notes = 'ThinkPad T14 Gen 3';
                    azureADDeviceId = 'aad-1'
                }
            }
            # Pester mocks bind by the real cmdlet's parameter names; record via $PSBoundParameters
            # so the assertion sees what the script actually asked for.
            $script:graphCalls = @()
            # Pester mock bodies do not populate $PSBoundParameters, so bind by name and read the
            # variables directly - the pattern used by this repo's other stubs.
            Mock Invoke-MgGraphRequest {
                param([string]$Uri, [string]$Method, $Body)
                $script:graphCalls += "$Method $Uri"
                if ($Method -eq 'GET' -and $Uri -like '*/v1.0/devices*') {
                    return [pscustomobject]@{
                        value = @([pscustomobject]@{
                            id = 'entra-obj-1'
                            deviceId = 'aad-1'
                            extensionAttributes = [pscustomobject]@{ ExtensionAttribute1 = 'ThinkPad T14 Gen 3' }
                        })
                    }
                }
                throw "unexpected Graph call: $Method $Uri"
            }
            Mock Invoke-RestMethod {
                @([pscustomobject]@{ name = 'ThinkPad T14 Gen 3 (Type 21AH, 21AJ)' })
            }
            Mock Update-MgDeviceManagementManagedDevice { }
            $AuditOnly = $false
            $UpdateExtensionAttributes = $true
            $ExtensionAttributeName = 'ExtensionAttribute1'
            $UpdateNotes = $true
            Main | Should -Be 0
            Should -Invoke Update-MgDeviceManagementManagedDevice -Times 0 -Exactly -Because "the note already matches"
            $script:graphCalls | Where-Object { $_ -like 'PATCH*' } | Should -BeNullOrEmpty `
                -Because "the extension attribute already holds the target value"
        }
        It "Is idempotent: converged Notes and disabled extension attributes cause no writes" {
            Mock Get-MgDeviceManagementManagedDevice {
                [pscustomobject]@{
                    id = 'dev-1';
                    deviceName = 'LAPTOP01';
                    model = '21AHS0AB00';
                    notes = "ThinkPad T14 Gen 3";
                    azureADDeviceId = 'aad-1'
                }
            }
            Mock Invoke-RestMethod {
                @([pscustomobject]@{ name = 'ThinkPad T14 Gen 3 (Type 21AH, 21AJ)' })
            }
            Mock Update-MgDeviceManagementManagedDevice { }

            $AuditOnly = $false
            $UpdateExtensionAttributes = $false
            Main | Should -Be 0
            Should -Invoke Update-MgDeviceManagementManagedDevice -Times 0 -Exactly
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
        }

        It "Returns 1 with [-] output when FailIfMissingMappings cannot resolve an MTM" {
            Mock Get-MgDeviceManagementManagedDevice {
                [pscustomobject]@{
                    id = 'dev-1';
                    deviceName = 'LAPTOP01';
                    model = '21AHS0AB00';
                    notes = '';
                    azureADDeviceId = 'aad-1'
                }
            }
            Mock Invoke-RestMethod {
                @([pscustomobject]@{ name = 'ThinkCentre M90 (Type 99XX)' })
            }

            $AuditOnly = $false
            $FailIfMissingMappings = $true
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 with [-] output when the Intune query fails" {
            Mock Get-MgDeviceManagementManagedDevice { throw "Graph unreachable" }

            $AuditOnly = $false
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
