#Requires -Modules Pester

Describe "Monitor-AzureAPIManagement" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/data/api/ -> script is two levels up.
        $scriptPath = [IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot "../../../scripts/data/api/Monitor-AzureAPIManagement.ps1"))
        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        # Mandatory parameters need a value at dot-source time; tests override via scope below.
        . $scriptPath -SubscriptionId '00000000-0000-0000-0000-000000000000' `
            -ResourceGroupName 'rg-placeholder' -ServiceName 'apim-placeholder'

        # Run offline against throwaway paths; never touch user directories.
        $SubscriptionId = '00000000-0000-0000-0000-000000000000'
        $ResourceGroupName = 'rg-apim'
        $ServiceName = 'apim-demo'
        $DaysToAnalyze = 7
        $OutputFormat = 'Console'
        $OutputPath = Join-Path $TestDrive 'reports'
        $IncludeAPIDetails = $false
        $IncludeBackendHealth = $false

        # The Az module is not installed offline; stub its surface so Pester can attach mocks.
        function Get-AzContext { }
        function Set-AzContext { }
        function New-AzApiManagementContext { }
        function Get-AzApiManagement { }
        function Get-AzApiManagementApi { }
        function Get-AzApiManagementOperation { }
        function Get-AzApiManagementBackend { }
        function Get-AzMetric { }

        # Az module entry points are mocked by name; nothing requires Azure connectivity.
        Mock Get-Module { [pscustomobject]@{ Name = 'Az.ApiManagement' } }
        Mock Import-Module { }
        Mock Get-AzContext { [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'demo@example.com' } } }
        Mock Set-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = $SubscriptionId } } }
        Mock New-AzApiManagementContext { [pscustomobject]@{ } }
        Mock Get-AzApiManagement {
            [pscustomobject]@{
                Name = 'apim-demo'
                Location = 'West Europe'
                Sku = 'Developer'
                ProvisioningState = 'Succeeded'
                GatewayUrl = 'https://apim-demo.azure-api.net'
                PortalUrl = 'https://apim-demo.portal.azure-api.net'
                PublicIPAddresses = @('203.0.113.10')
            }
        }
        Mock Get-AzMetric {
            param($MetricName)
            if ($MetricName -eq 'Capacity') {
                [pscustomobject]@{
                    Data = @([pscustomobject]@{ Average = 40 }, [pscustomobject]@{ Average = 60 })
                }
            }
            else {
                [pscustomobject]@{
                    Data = @([pscustomobject]@{ Total = 450 }, [pscustomobject]@{ Total = 50 })
                }
            }
        }
    }

    Context "Help & Metadata" {
        BeforeAll {
            $raw = Get-Content -Raw -LiteralPath $scriptPath
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declaredParams = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $documentedParams = [regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value }
        }

        It "Declares the complete .NOTES header (File Name, Author, Prerequisite, Version, Date)" {
            $raw | Should -Match '(?m)^\.NOTES'
            $raw | Should -Match 'File Name\s*:\s*Monitor-AzureAPIManagement\.ps1'
            $raw | Should -Match 'Author\s*:\s*\S+'
            $raw | Should -Match 'Prerequisite\s*:\s*PowerShell'
            $raw | Should -Match 'Version\s*:\s*1\.0\.0'
            $raw | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Documents exactly one .PARAMETER per declared parameter, in declaration order" {
            $documentedParams.Count | Should -Be $declaredParams.Count
            for ($i = 0; $i -lt $declaredParams.Count; $i++) {
                $documentedParams[$i] | Should -Be $declaredParams[$i]
            }
        }

        It "Provides at least two .EXAMPLE blocks with PS C:\> prompt lines" {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            $raw | Should -Match 'PS C:\\>'
        }
    }

    Context "Syntax & Static" {
        It "Parses via the PowerShell parser with zero errors" {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            @($parseErrors).Count | Should -Be 0
        }

        It "Contains no PS7-only operators (no #Requires -Version 7.0 opt-out present)" {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $ps7OnlyKinds = @('QuestionMark', 'QuestionMarkQuestionMark', 'AmpersandAmpersand', 'PipePipe')
            $offending = @($tokens | Where-Object { $_.Kind -in $ps7OnlyKinds })
            $offending | Should -BeNullOrEmpty -Because "PS7-only operators require the 7.0 opt-out"
        }

        It "Wraps the body in Main and keeps exit in the dot-source guard only" {
            $exitLines = @((Get-Content -LiteralPath $scriptPath) | Where-Object { $_ -match '\bexit\b' })
            @($exitLines).Count | Should -Be 1
            $exitLines[0] | Should -Match '\$MyInvocation\.InvocationName'
            Get-Content -Raw -LiteralPath $scriptPath | Should -Match 'function Main'
        }
    }

    Context "Behavior" {
        It "Collects service health plus four metric queries and returns 0" {
            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Contain 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Get-AzMetric -Times 4 -Exactly -Because "Total/Successful/Failed requests + Capacity"
            Should -Invoke Set-AzContext -Times 1 -Exactly
        }

        It "Is idempotent: a second identical run also returns 0 with no extra mutations" {
            Mock New-AzApiManagementContext { [pscustomobject]@{ } }   # fresh mock: resets call history
            Main | Should -Be 0
            Main | Should -Be 0
            Should -Invoke New-AzApiManagementContext -Times 2 -Exactly
        }

        It "Returns 1 and writes [-] prefixed output when not logged in to Azure" {
            Mock Get-AzContext { $null }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\].*(Not logged in|Error)'
        }

        It "Returns 1 and writes [-] output when the required Az module is absent" {
            Mock Get-Module { $null }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Degrades gracefully to a warning when Azure Monitor metrics fail" {
            Mock Get-AzMetric { throw "429 Too Many Requests" }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Contain 0
            ($out | Out-String) | Should -Match '\[!\] Failed to retrieve metrics'
        }
    }

    Context "Behavior with optional API details" {
        BeforeAll {
            $IncludeAPIDetails = $true
            Mock Get-AzApiManagementApi {
                @([pscustomobject]@{
                    ApiId = 'echo-api'
                    Name = 'Echo API'
                    Path = '/echo'
                    Protocols = @('https')
                    ServiceUrl = 'https://backend.example.com'
                    IsCurrent = $true
                    Description = 'Demo API'
                })
            }
            Mock Get-AzApiManagementOperation {
                @([pscustomobject]@{ Name = 'Retrieve resource' }, [pscustomobject]@{ Name = 'Create resource' })
            }
        }

        It "Enumerates APIs and operations and returns 0" {
            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] }) | Should -Contain 0
            ($out | Out-String) | Should -Match 'Found 1 APIs with 2 operations'
            Should -Invoke Get-AzApiManagementApi -Times 1 -Exactly
            Should -Invoke Get-AzApiManagementOperation -Times 1 -Exactly
        }
    }
}
