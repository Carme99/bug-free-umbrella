#Requires -Modules Pester

# Pester 5 suite for scripts/collaboration/microsoft365/exchange-online/Manage-QuarantinedEmails.ps1
# Runs fully offline on Linux pwsh: Exchange Online cmdlets and Read-Host are mocked;
# the native surface is reached only through mockable wrapper functions.

Describe "Manage-QuarantinedEmails" {

    BeforeAll {
        # Mirrored layout: Tests/collaboration/microsoft365/exchange-online/ -> repo root is four levels up.
        $scriptRelPath = "../../../../scripts/collaboration/microsoft365/exchange-online/Manage-QuarantinedEmails.ps1"
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

        # Shared message fixtures
        $msgOne = [pscustomobject]@{
            Identity         = 'msg-001'
            ReceivedTime     = (Get-Date).AddDays(-1)
            SenderAddress    = 'sender@external.com'
            RecipientAddress = @('test@contoso.com')
            Subject          = 'Test Quarantined Email'
            QuarantineTypes  = @('Spam')
            Direction        = 'Inbound'
            Size             = 51200
            PolicyName       = 'Default Anti-Spam Policy'
        }
        $msgTwo = [pscustomobject]@{
            Identity         = 'msg-002'
            ReceivedTime     = (Get-Date).AddDays(-2)
            SenderAddress    = 'phishing@malicious.com'
            RecipientAddress = @('test@contoso.com')
            Subject          = 'Urgent: Verify Your Account'
            QuarantineTypes  = @('HighConfPhish')
            Direction        = 'Inbound'
            Size             = 102400
            PolicyName       = 'Default Anti-Phishing Policy'
        }

        # Local stubs guarantee every external cmdlet is mockable even when its module is absent.
        function Get-ConnectionInformation { }
        function Connect-ExchangeOnline { param([switch]$ShowBanner) }
        function Get-EXOMailbox { param([string]$Identity) }
        function Get-QuarantineMessage {
            param([string]$RecipientAddress, [datetime]$StartReceivedDate, [datetime]$EndReceivedDate)
        }
        function Release-QuarantineMessage { param([string]$Identity, [switch]$ReleaseToAll) }

        # Base external mocks (offline). Scoped filters keep Pester internals untouched.
        Mock Get-Module {
            [pscustomobject]@{ Name = 'ExchangeOnlineManagement'; Version = [version]'3.4.0' }
        } -ParameterFilter { $Name -eq 'ExchangeOnlineManagement' }
        Mock Import-Module { } -ParameterFilter { $Name -eq 'ExchangeOnlineManagement' }
        Mock Get-ConnectionInformation { [pscustomobject]@{ UserPrincipalName = 'admin@contoso.com' } }
        Mock Connect-ExchangeOnline { }
        Mock Get-EXOMailbox {
            [pscustomobject]@{
                DisplayName        = 'Test User'
                PrimarySmtpAddress = 'primary@contoso.com'
                UserPrincipalName  = 'test@contoso.com'
            }
        }
        Mock Get-QuarantineMessage { @() }
        Mock Release-QuarantineMessage { }
        Mock Read-Host { '0' }
    }

    Context "Help & Metadata" {

        It "Declares Version 1.0.0 and relaunch Date 2026-08-23 in .NOTES" {
            $rawContent | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\b'
            $rawContent | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\b'
        }

        It "Declares the actual filename, preserved author, and PowerShell 7.0 prerequisite" {
            $rawContent | Should -Match '(?m)^\s*File Name\s*:\s*Manage-QuarantinedEmails\.ps1\b'
            $rawContent | Should -Match '(?m)^\s*Author\s*:\s*IT Operations\b'
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
            $rawContent | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
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

        It "Is idempotent: an empty quarantine returns 0 with no release attempted" {
            $UserEmail = 'test@contoso.com'
            $AutoConnect = $false
            $Days = 7
            Mock Get-QuarantineMessage { @() }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            ($out | Out-String) | Should -Match '\[\*\] Searching for quarantined messages'
            Should -Invoke Release-QuarantineMessage -Times 0 -Exactly -Because 'nothing to release means no mutation'
            Should -Invoke Get-QuarantineMessage -Exactly 1 `
                -Because 'a converged tenant needs exactly one detection pass'
        }

        It "Selects, confirms, and releases a quarantined message through the interactive loop" {
            $UserEmail = 'test@contoso.com'
            $AutoConnect = $false
            $Days = 7

            # Interactive answers: select item 1, choose action 1 (release), confirm Y.
            $answers = [System.Collections.Generic.Queue[string]]::new()
            $answers.Enqueue('1'); $answers.Enqueue('1'); $answers.Enqueue('Y')
            Mock Read-Host { if ($answers.Count -gt 0) { $answers.Dequeue() } else { '0' } }

            # First search returns two messages; after release the refreshed search returns none.
            # Property writes survive across mock invocations; variable writes would not.
            $searchState = [pscustomobject]@{ Calls = 0 }
            Mock Get-QuarantineMessage {
                $searchState.Calls++
                if ($searchState.Calls -eq 1) { @($msgOne, $msgTwo) } else { @() }
            }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            Should -Invoke Release-QuarantineMessage
            ($out | Out-String) | Should -Match '\[\+\] Message successfully released to: test@contoso\.com'
        }

        It "Honors -WhatIf: the ShouldProcess gate prevents any release call" {
            $UserEmail = 'test@contoso.com'
            $AutoConnect = $false
            $Days = 7
            $WhatIfPreference = $true

            $answers = [System.Collections.Generic.Queue[string]]::new()
            $answers.Enqueue('1'); $answers.Enqueue('1'); $answers.Enqueue('Y')
            Mock Read-Host { if ($answers.Count -gt 0) { $answers.Dequeue() } else { '0' } }
            Mock Get-QuarantineMessage { ,@($msgOne) }

            $out = Main *>&1
            $WhatIfPreference = $false
            @($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            Should -Invoke Release-QuarantineMessage -Times 0 -Exactly `
                -Because 'WhatIf must suppress the state-changing call'
        }

        It "Returns 1 when not connected and -AutoConnect is not specified" {
            $UserEmail = 'test@contoso.com'
            $AutoConnect = $false
            Mock Get-ConnectionInformation { $null }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] })[-1] | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] Not connected to Exchange Online!'
            Should -Invoke Connect-ExchangeOnline -Times 0 -Exactly
        }

        It "Returns 1 for a syntactically invalid email address before any lookup" {
            $UserEmail = 'not-an-email'
            $AutoConnect = $false

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] })[-1] | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] Invalid email address format'
            Should -Invoke Get-EXOMailbox -Times 0 -Exactly
        }

        It "Validates email addresses via Test-EmailAddress" {
            Test-EmailAddress -Email 'user@domain.com' | Should -BeTrue
            Test-EmailAddress -Email 'user.name@sub.domain.com' | Should -BeTrue
            Test-EmailAddress -Email 'invalid' | Should -BeFalse
            Test-EmailAddress -Email 'user@.com' | Should -BeFalse
            Test-EmailAddress -Email '' | Should -BeFalse
        }
    }
}
