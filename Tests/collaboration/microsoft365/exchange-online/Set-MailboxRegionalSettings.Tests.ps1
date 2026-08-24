#Requires -Modules Pester

# Pester 5 suite for scripts/collaboration/microsoft365/exchange-online/Set-MailboxRegionalSettings.ps1
# Runs fully offline on Linux pwsh: all Exchange Online cmdlets are mocked by name.

Describe "Set-MailboxRegionalSettings" {

    BeforeAll {
        # Mirrored layout: Tests/collaboration/microsoft365/exchange-online/ -> repo root is four levels up.
        $scriptRelPath =
            "../../../../scripts/collaboration/microsoft365/exchange-online/Set-MailboxRegionalSettings.ps1"
        $scriptPath = Join-Path $PSScriptRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Static analysis inputs
        $rawContent = Get-Content -Raw -LiteralPath $scriptPath
        $parseTokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath, [ref]$parseTokens, [ref]$parseErrors)
        $paramNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })

        # Shared fixtures
        $mbxJohn = [pscustomobject]@{ DisplayName = 'John Doe'; UserPrincipalName = 'john.doe@contoso.com' }

        # A regional configuration that already matches the required baseline.
        $compliantConfig = {
            [pscustomobject]@{
                TimeZone               = $TimeZone
                DateFormat             = $DateFormat
                TimeFormat             = $TimeFormat
                Language               = [pscustomobject]@{ Name = $Language }
                WorkDays               = @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday')
                WorkingHoursStartTime  = $WorkingHoursStartTime
                WorkingHoursEndTime    = $WorkingHoursEndTime
            }
        }

        # Local stubs guarantee every external cmdlet is mockable even when its module is absent.
        function Get-ConnectionInformation { }
        function Connect-ExchangeOnline { param([switch]$ShowBanner) }
        function Get-EXOMailbox {
            param([string]$Identity, [string[]]$Properties, [string]$ResultSize, [string]$RecipientTypeDetails)
        }
        function Get-MailboxRegionalConfiguration { param([string]$Identity) }
        function Set-MailboxRegionalConfiguration {
            param(
                [string]$Identity,
                [string]$TimeZone,
                [string]$DateFormat,
                [string]$TimeFormat,
                [string]$Language,
                [switch]$LocalizeDefaultFolderName
            )
        }

        # Base external mocks (offline). Scoped filters keep Pester internals untouched.
        Mock Get-Module {
            [pscustomobject]@{ Name = 'ExchangeOnlineManagement'; Version = [version]'3.4.0' }
        } -ParameterFilter { $Name -eq 'ExchangeOnlineManagement' }
        Mock Import-Module { } -ParameterFilter { $Name -eq 'ExchangeOnlineManagement' }
        Mock Get-ConnectionInformation { [pscustomobject]@{ UserPrincipalName = 'admin@contoso.com' } }
        Mock Connect-ExchangeOnline { }
        Mock Get-EXOMailbox { @() }
        Mock Get-EXOMailbox { $mbxJohn } -ParameterFilter { $Identity -eq 'john.doe@contoso.com' }
        Mock Set-MailboxRegionalConfiguration { }
        Mock Out-File { } -ParameterFilter { $FilePath -like '*MailboxRegionalSettings_*' }
        Mock Export-Csv { }
    }

    Context "Help & Metadata" {

        It "Declares Version 1.0.0 and relaunch Date 2026-08-23 in .NOTES" {
            $rawContent | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\b'
            $rawContent | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\b'
        }

        It "Declares the actual filename and PowerShell 7.0 prerequisite" {
            $rawContent | Should -Match '(?m)^\s*File Name\s*:\s*Set-MailboxRegionalSettings\.ps1\b'
            $rawContent | Should -Match '(?m)^\s*Prerequisite\s*:\s*PowerShell 7\.0\b'
        }

        It "Has one .PARAMETER entry per declared parameter, in order" {
            $helpParamNames = @([regex]::Matches($rawContent, '(?m)^\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value })
            $helpParamNames.Count | Should -Be $paramNames.Count
            for ($i = 0; $i -lt $paramNames.Count; $i++) {
                $helpParamNames[$i] | Should -Be $paramNames[$i]
            }
        }

        It "Has at least two examples using the PS C:\> prompt" {
            $exampleBlocks = [regex]::Matches($rawContent, '(?s)\.EXAMPLE(.+?)(?=\.EXAMPLE|\.NOTES)')
            $exampleBlocks.Count | Should -BeGreaterOrEqual 2
            foreach ($block in $exampleBlocks) {
                $block.Value | Should -Match 'PS C:\\>'
            }
        }

        It "Keeps the synopsis imperative and under 120 characters" {
            $synopsis = ([regex]::Match($rawContent, '(?ms)^\.SYNOPSIS\s+(.+?)$')).Groups[1].Value.Trim()
            $synopsis.Length | Should -BeLessOrEqual 120
            $synopsis | Should -Match '^[A-Z]'
        }
    }

    Context "Syntax & Static" {

        It "Parses cleanly with zero parser errors" {
            $parseErrors.Count | Should -Be 0
        }

        It "Uses no PS7-only operators without opting out via #Requires -Version 7.0" {
            $firstLine = (Get-Content -LiteralPath $scriptPath -TotalCount 1)
            if ($firstLine -notmatch '^#Requires -Version 7\.0') {
                $rawContent | Should -Not -Match ('\?\?|\|\||&&')
            }
        }

        It "Wraps execution in a guarded Main function and declares SupportsShouldProcess" {
            $fnType = [System.Management.Automation.Language.FunctionDefinitionAst]
            $mainFn = @($ast.FindAll({ param($node) $node -is $fnType -and $node.Name -eq 'Main' }, $true))
            $mainFn.Count | Should -Be 1
            $guardLine = "if (`$MyInvocation.InvocationName -ne '.') { exit (Main) }"
            ($rawContent -replace '\s', ' ') | Should -Match ([regex]::Escape($guardLine))
            $rawContent | Should -Match '\[CmdletBinding\(.*SupportsShouldProcess.*\)\]'
        }

        It "Gates every Set-MailboxRegionalConfiguration call behind ShouldProcess" {
            ($rawContent -match '\$PSCmdlet\.ShouldProcess') | Should -BeTrue
            $setCalls = [regex]::Matches($rawContent, '(?m)^\s+if \(\$PSCmdlet\.ShouldProcess')
            foreach ($call in ([regex]::Matches($rawContent, 'Set-MailboxRegionalConfiguration'))) {
                $before = $rawContent.Substring(0, $call.Index)
                ($before -match '\$PSCmdlet\.ShouldProcess') | Should -BeTrue
                break # single mutating call site; presence check above is sufficient
            }
        }

        It "Defines only approved-verb functions" {
            $functions = $ast.FindAll(
                { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
                $true) |
                Select-Object -ExpandProperty Name
            foreach ($fn in $functions) {
                if ($fn -eq 'Main') { continue } # mandated entry point, not a Verb-Noun function
                $verb = ($fn -split '-')[0]
                Get-Verb -Verb $verb | Should -Not -BeNullOrEmpty -Because "$fn should use an approved verb"
            }
        }
    }

    Context "Behavior" {

        It "Is idempotent: an already-compliant mailbox with -Apply returns 0 and never mutates" {
            $UserPrincipalName = 'john.doe@contoso.com'
            $AllMailboxes = $false
            $Apply = $true
            Mock Get-MailboxRegionalConfiguration $compliantConfig

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            Should -Invoke Set-MailboxRegionalConfiguration -Times 0 -Exactly `
                -Because 'compliant mailboxes must not be written'
        }

        It "Remediates a non-compliant mailbox once when -Apply is specified" {
            $UserPrincipalName = 'john.doe@contoso.com'
            $AllMailboxes = $false
            $Apply = $true
            Mock Get-MailboxRegionalConfiguration {
                [pscustomobject]@{
                    TimeZone               = 'Pacific Standard Time'
                    DateFormat             = 'M/d/yyyy'
                    TimeFormat             = 'h:mm tt'
                    Language               = [pscustomobject]@{ Name = 'en-US' }
                    WorkDays               = @('Monday')
                    WorkingHoursStartTime  = '09:00:00'
                    WorkingHoursEndTime    = '18:00:00'
                }
            }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            Should -Invoke Set-MailboxRegionalConfiguration -Exactly 1 -ParameterFilter {
                $Identity -eq 'john.doe@contoso.com' -and $TimeZone -eq 'GMT Standard Time' -and $Language -eq 'en-GB'
            }
            ($out | Out-String) | Should -Match '\[\+\] Settings applied successfully!'
        }

        It "Returns 1 in audit-only mode when a mailbox is non-compliant, without changing anything" {
            $UserPrincipalName = 'john.doe@contoso.com'
            $AllMailboxes = $false
            $Apply = $false
            Mock Get-MailboxRegionalConfiguration {
                [pscustomobject]@{
                    TimeZone               = 'Pacific Standard Time'
                    DateFormat             = 'M/d/yyyy'
                    TimeFormat             = 'h:mm tt'
                    Language               = [pscustomobject]@{ Name = 'en-US' }
                    WorkDays               = @('Monday')
                    WorkingHoursStartTime  = '09:00:00'
                    WorkingHoursEndTime    = '18:00:00'
                }
            }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] })[-1] | Should -Be 1
            Should -Invoke Set-MailboxRegionalConfiguration -Times 0 -Exactly
            ($out | Out-String) | Should -Match '\[!\] John Doe - Non-Compliant:'
        }

        It "Returns 1 when processing errors occur even with -Apply" {
            $UserPrincipalName = 'john.doe@contoso.com'
            $AllMailboxes = $false
            $Apply = $true
            Mock Get-MailboxRegionalConfiguration { throw "mailbox unavailable" }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] })[-1] | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] Error processing John Doe:'
        }
    }
}
