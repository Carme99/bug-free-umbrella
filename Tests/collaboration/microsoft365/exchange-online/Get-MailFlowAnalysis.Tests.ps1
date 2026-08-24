#Requires -Modules Pester

Describe "Get-MailFlowAnalysis" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/collaboration/microsoft365/exchange-online/
        # -> the repo root is four levels up.
        $scriptRelPath = "../../../../scripts/collaboration/microsoft365/exchange-online/Get-MailFlowAnalysis.ps1"
        $scriptPath = (Resolve-Path (Join-Path $PSScriptRoot $scriptRelPath)).Path
        $outputDir = Join-Path $TestDrive 'reports'

        # Offline fixtures: 4 messages -> 3 delivered, 1 failed (75% delivery rate).
        function New-TraceMessage {
            param([string]$SenderAddress, [string]$RecipientAddress, [string]$Status, [string]$Subject)
            [pscustomobject]@{
                SenderAddress = $SenderAddress
                RecipientAddress = $RecipientAddress
                Status = $Status
                Subject = $Subject
                Received = (Get-Date)
            }
        }
        $traceMessages = @(
            New-TraceMessage 'a@external.com' 'alice@contoso.com' 'Delivered' 'One'
            New-TraceMessage 'b@contoso.com' 'bob@contoso.com' 'Delivered' 'Two'
            New-TraceMessage 'c@external.com' 'carol@contoso.com' 'Delivered' 'Three'
            New-TraceMessage 'd@external.com' 'dan@contoso.com' 'Failed' 'Four'
        )
        $transportRule = [pscustomobject]@{
            Name = 'Disclaimer Rule'; Priority = 0; State = 'Enabled'; Mode = 'Enforce'
            Conditions = @([pscustomobject]@{}); Actions = @([pscustomobject]@{})
        }

        # The ExchangeOnlineManagement module is NOT installed in CI, and Pester 5 cannot
        # mock commands that do not exist on disk. Seed permissive stub functions with the
        # exact parameter surface the script uses, then layer Pester mocks on top.
        function Get-OrganizationConfig {
            [CmdletBinding()] param()
        }
        function Get-MessageTraceV2 {
            [CmdletBinding()] param([datetime]$StartDate, [datetime]$EndDate, [string]$ResultSize)
        }
        function Get-TransportRule {
            [CmdletBinding()] param()
        }
        function Get-InboundConnector {
            [CmdletBinding()] param()
        }
        function Get-OutboundConnector {
            [CmdletBinding()] param()
        }
        function Out-File {
            [CmdletBinding()] param(
                [Parameter(ValueFromPipeline = $true)]$InputObject,
                [string]$FilePath,
                [string]$Encoding
            )
        }
        function Export-Csv {
            [CmdletBinding()] param(
                [Parameter(ValueFromPipeline = $true)]$InputObject,
                [string]$Path,
                [switch]$NoTypeInformation
            )
        }

        # Mock ALL external commands so nothing leaves the machine (offline, Linux pwsh).
        Mock Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'ExchangeOnlineManagement' } {
            [pscustomobject]@{ Name = 'ExchangeOnlineManagement' }
        }
        Mock Test-Path -ParameterFilter { $PathType -eq 'Container' } { $true }
        Mock New-Item { }
        Mock Get-OrganizationConfig { [pscustomobject]@{ Name = 'contoso.onmicrosoft.com' } }
        Mock Get-MessageTraceV2 { $traceMessages }
        Mock Get-TransportRule { @($transportRule) }
        Mock Get-InboundConnector { @() }
        Mock Get-OutboundConnector { @() }
        Mock Out-File { }
        Mock Export-Csv { }

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        . $scriptPath -OutputFormat Console -OutputPath $outputDir
    }

    Context "Help & Metadata" {
        BeforeAll {
            $raw = Get-Content -Path $scriptPath -Raw
            $tokens = $null; $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declaredParams = @($ast.ParamBlock.Parameters | ForEach-Object {
                if ($_.Name -is [string]) { $_.Name } else { $_.Name.Extent.Text }
            } | ForEach-Object { $_.TrimStart('$') })
            $helpParams = @([regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
        }

        It "Declares File Name matching the actual filename" {
            $raw | Should -Match 'File Name\s*:\s*Get-MailFlowAnalysis\.ps1'
        }

        It "Preserves the existing author" {
            $raw | Should -Match 'Author\s*:\s*IT Operations'
        }

        It "Requires PowerShell 7.0" {
            $raw | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
        }

        It "Is version 1.0.0" {
            $raw | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
        }

        It "Is dated the relaunch date 2026-08-23" {
            $raw | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
        }

        It "Documents every declared parameter, in order" {
            $helpParams.Count | Should -Be $declaredParams.Count
            for ($i = 0; $i -lt $declaredParams.Count; $i++) {
                $helpParams[$i] | Should -Be $declaredParams[$i]
            }
        }

        It "Has at least two examples with PS C:\> prompts" {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }

        It "Has a synopsis of at most 120 characters" {
            $synopsis = ([regex]::Match($raw, '(?s)^\.SYNOPSIS\s*\r?\n\s*(.+?)\r?\n')).Groups[1].Value.Trim()
            $synopsis.Length | Should -BeLessOrEqual 120
        }
    }

    Context "Syntax & Static" {
        BeforeAll {
            $tokens = $null; $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $rawText = Get-Content -Path $scriptPath -Raw
        }

        It "Parses without errors" {
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only operators without #Requires -Version 7.0" {
            $hasRequires = $rawText -match '(?m)^#Requires\s+-Version\s+7\.0'
            if (-not $hasRequires) {
                $rawText | Should -Not -Match '\?\?|\?\?=|&&|\|\|'
            }
        }

        It "Uses no tabs" {
            $rawText | Should -Not -Match "`t"
        }

        It "Has no trailing whitespace" {
            $rawText | Should -Not -Match '(?m)[ \t]+\r?\n'
        }

        It "Keeps all lines within 120 columns" {
            ($rawText -split "\r?\n" | Where-Object { $_.Length -gt 120 }) | Should -BeNullOrEmpty
        }

        It "Wraps the body in Main with the dot-source exit guard" {
            $rawText | Should -Match '(?m)^function Main \{'
            $guardLine = 'if ($MyInvocation.InvocationName -ne ''.'') { exit (Main) }'
            $rawText | Should -Match ([regex]::Escape($guardLine))
        }
    }

    Context "Behavior" {
        It "Runs a 7-day console analysis in a single trace query and returns 0" {
            . $scriptPath -OutputFormat Console -OutputPath $outputDir
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Delivery Rate: 75%'
            Should -Invoke Get-MessageTraceV2 -Exactly 1 -Because "ranges of 10 days or less need one query"
        }

        It "Walks longer periods in 10-day windows" {
            . $scriptPath -OutputFormat Console -DaysToAnalyze 30 -OutputPath $outputDir
            Main | Should -Be 0
            Should -Invoke Get-MessageTraceV2 -Exactly 3
        }

        It "Caps analysis at the 90-day trace retention" {
            . $scriptPath -OutputFormat Console -DaysToAnalyze 180 -OutputPath $outputDir
            Main | Should -Be 0
            # 90 days walked in 10-day windows = 9 queries
            Should -Invoke Get-MessageTraceV2 -Exactly 9
        }

        It "Reports delivery failures with -AnalyzeFailures" {
            . $scriptPath -OutputFormat Console -AnalyzeFailures -OutputPath $outputDir
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '=== Recent Delivery Failures ==='
            ($out | Out-String) | Should -Match 'd@external.com'
        }

        It "Summarizes transport rules and connectors when requested" {
            . $scriptPath -OutputFormat Console -IncludeTransportRules -IncludeConnectors -OutputPath $outputDir
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Found 1 enabled transport rules'
            ($out | Out-String) | Should -Match 'Found 0 inbound and 0 outbound connectors'
            Should -Invoke Get-TransportRule -Exactly 1
        }

        It "Warns and continues when message trace retrieval fails" {
            Mock Get-MessageTraceV2 { throw 'throttled' }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Error retrieving message trace'
        }

        It "Returns 1 with [-] output when not connected to Exchange Online" {
            Mock Get-OrganizationConfig { throw 'no remote session' }
            . $scriptPath -OutputFormat Console -OutputPath $outputDir
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 with [-] output when ExchangeOnlineManagement is missing" {
            Mock Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'ExchangeOnlineManagement' } { }
            . $scriptPath -OutputFormat Console -OutputPath $outputDir
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Writes a JSON report when -OutputFormat JSON is used" {
            . $scriptPath -OutputFormat JSON -OutputPath $outputDir
            Main | Should -Be 0
            Should -Invoke Out-File -ParameterFilter { $FilePath -like '*.json' } -Exactly 1
        }

        It "Writes a CSV report when -OutputFormat CSV is used" {
            . $scriptPath -OutputFormat CSV -OutputPath $outputDir
            Main | Should -Be 0
            # NOTE: the mocked Export-Csv body fires once per piped item, so assert
            # at-least-once rather than exactly-once here.
            Should -Invoke Export-Csv -ParameterFilter { $Path -like '*MailFlow-TopSenders-*.csv' }
        }
    }
}
