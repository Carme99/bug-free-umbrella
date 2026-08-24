#Requires -Modules Pester

# Pester 5 suite for scripts/collaboration/microsoft365/exchange-online/Get-UserMailboxPermissions.ps1
# Runs fully offline on Linux pwsh: all Exchange Online cmdlets are mocked by name.

Describe "Get-UserMailboxPermissions" {

    BeforeAll {
        # Mirrored layout: Tests/collaboration/microsoft365/exchange-online/ -> repo root is four levels up.
        $scriptRelPath = "../../../../scripts/collaboration/microsoft365/exchange-online/Get-UserMailboxPermissions.ps1"
        $scriptPath = Join-Path $PSScriptRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        # Mandatory -UserEmail is satisfied with a placeholder; behavioral tests override it per test.
        . $scriptPath -UserEmail "audit@contoso.com"

        # Static analysis inputs
        $rawContent = Get-Content -Raw -LiteralPath $scriptPath
        $parseTokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath, [ref]$parseTokens, [ref]$parseErrors)
        $paramNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })

        # Local stubs guarantee every external cmdlet is mockable even when its module is absent.
        function Get-ConnectionInformation { }
        function Get-EXOMailbox { param([string]$Identity, [string[]]$Properties) }
        function Get-EXOMailboxPermission { param([string]$Identity) }
        function Get-EXORecipientPermission { param([string]$Identity) }
        function Get-EXOMailboxFolderPermission { param([string]$Identity) }

        # Base external mocks (offline). Scoped filters keep Pester internals untouched.
        Mock Get-Module {
            [pscustomobject]@{ Name = 'ExchangeOnlineManagement'; Version = [version]'3.4.0' }
        } -ParameterFilter { $Name -eq 'ExchangeOnlineManagement' }
        Mock Import-Module { } -ParameterFilter { $Name -eq 'ExchangeOnlineManagement' }
        Mock Get-ConnectionInformation { [pscustomobject]@{ UserPrincipalName = 'admin@contoso.com' } }
        Mock Get-EXOMailbox {
            [pscustomobject]@{
                DisplayName            = 'John Doe'
                PrimarySmtpAddress     = 'john.doe@contoso.com'
                GrantSendOnBehalfTo    = @()
                ForwardingAddress      = $null
                ForwardingSmtpAddress  = $null
            }
        }
        Mock Get-EXOMailboxPermission { @() }
        Mock Get-EXORecipientPermission { @() }
        Mock Get-EXOMailboxFolderPermission { @() }
    }

    Context "Help & Metadata" {

        It "Declares Version 1.0.0 and relaunch Date 2026-08-23 in .NOTES" {
            $rawContent | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\b'
            $rawContent | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\b'
        }

        It "Declares the actual filename and PowerShell 7.0 prerequisite" {
            $rawContent | Should -Match '(?m)^\s*File Name\s*:\s*Get-UserMailboxPermissions\.ps1\b'
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

        It "Wraps execution in a guarded Main function" {
            $fnType = [System.Management.Automation.Language.FunctionDefinitionAst]
            $mainFn = @($ast.FindAll({ param($node) $node -is $fnType -and $node.Name -eq 'Main' }, $true))
            $mainFn.Count | Should -Be 1
            $guardLine = "if (`$MyInvocation.InvocationName -ne '.') { exit (Main) }"
            ($rawContent -replace '\s', ' ') | Should -Match ([regex]::Escape($guardLine))
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

        It "Audits explicit permissions and returns 0 when connected" {
            $UserEmail = 'john.doe@contoso.com'
            Mock Get-EXOMailboxPermission {
                @([pscustomobject]@{
                     User = 'alice@contoso.com'; AccessRights = @('FullAccess'); IsInherited = $false; Deny = $false
                })
            }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] })[-1] | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] Found 1 Full Access permission\(s\)'
            Should -Invoke Get-EXOMailboxPermission -Exactly 1 -ParameterFilter { $Identity -eq 'john.doe@contoso.com' }
        }

        It "Returns 1 with [-] prefixed output when not connected to Exchange Online" {
            $UserEmail = 'john.doe@contoso.com'
            Mock Get-ConnectionInformation { $null }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] })[-1] | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] Not connected to Exchange Online!'
            Should -Invoke Get-EXOMailbox -Times 0 -Exactly -Because 'no work should happen while disconnected'
        }

        It "Returns 1 when the target mailbox cannot be resolved" {
            $UserEmail = 'ghost@contoso.com'
            Mock Get-EXOMailbox { throw "The recipient 'ghost@contoso.com' was not found." }

            $out = Main *>&1
            @($out | Where-Object { $_ -is [int] })[-1] | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] User not found:'
        }

        It "Skips folder permission queries unless -IncludeFolderPermissions is set" {
            $UserEmail = 'john.doe@contoso.com'

            $IncludeFolderPermissions = $false
            Main *>&1 | Out-Null
            Should -Invoke Get-EXOMailboxFolderPermission -Times 0 -Exactly

            $IncludeFolderPermissions = $true
            Main *>&1 | Out-Null
            Should -Invoke Get-EXOMailboxFolderPermission -Times 4 -Exactly `
                -Because 'Calendar, Inbox, Contacts and Tasks are queried'
        }
    }
}
