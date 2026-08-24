#Requires -Modules Pester

Describe "Get-SharedMailboxReport" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/collaboration/microsoft365/exchange-online/
        # -> the repo root is four levels up.
        $scriptRelPath = "../../../../scripts/collaboration/microsoft365/exchange-online/Get-SharedMailboxReport.ps1"
        $scriptPath = (Resolve-Path (Join-Path $PSScriptRoot $scriptRelPath)).Path

        # Offline fixtures
        $sharedListing = @([pscustomobject]@{
            DisplayName       = 'Shared-Finance'
            UserPrincipalName = 'shared-finance@contoso.com'
            PrimarySmtpAddress = 'shared-finance@contoso.com'
            WhenCreated       = (Get-Date '2024-01-01')
            AccountDisabled   = $true
        })
        $smbDetail = [pscustomobject]@{ GrantSendOnBehalfTo = @() }

        # The ExchangeOnlineManagement module is NOT installed in CI, and Pester 5 cannot
        # mock commands that do not exist on disk. Seed permissive stub functions with the
        # exact parameter surface the script uses, then layer Pester mocks on top.
        function Get-ConnectionInformation {
            [CmdletBinding()] param()
        }
        function Connect-ExchangeOnline {
            [CmdletBinding()] param([switch]$ShowBanner)
        }
        function Get-EXOMailbox {
            [CmdletBinding()] param(
                [string]$Identity,
                [string]$ResultSize,
                [string[]]$Properties,
                [string]$RecipientTypeDetails
            )
        }
        function Get-EXOMailboxStatistics {
            [CmdletBinding()] param([string]$Identity)
        }
        function Get-EXOMailboxPermission {
            [CmdletBinding()] param([string]$Identity)
        }
        function Get-EXORecipientPermission {
            [CmdletBinding()] param([string]$Identity)
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
        Mock Test-Path -ParameterFilter { $PathType -eq 'Container' } { $true }
        Mock New-Item { }
        Mock Get-ConnectionInformation { $null }
        Mock Connect-ExchangeOnline { }
        Mock Get-EXOMailbox {
            if ($Properties -contains 'GrantSendOnBehalfTo') { return $smbDetail }
            return $sharedListing
        }
        Mock Get-EXOMailboxStatistics {
            @([pscustomobject]@{
                TotalItemSize = '512 MB (536,870,912 bytes)'
                ItemCount     = 50
                LastLogonTime = (Get-Date).AddDays(-1)
            })
        }
        Mock Get-EXOMailboxPermission { @() }
        Mock Get-EXORecipientPermission { @() }
        Mock Out-File { }
        Mock Export-Csv { }

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        . $scriptPath
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
            $raw | Should -Match 'File Name\s*:\s*Get-SharedMailboxReport\.ps1'
        }

        It "Uses Bug-Free Umbrella as author" {
            $raw | Should -Match 'Author\s*:\s*Bug-Free Umbrella'
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
        It "Runs a clean audit end-to-end and returns 0" {
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] Found 1 shared mailbox\(es\)'
            ($out | Out-String) | Should -Match 'Issues Found: 0'
            Should -Invoke Get-EXOMailboxStatistics -Exactly 1
            Should -Invoke Connect-ExchangeOnline -Exactly 1 -Because "no prior connection exists"
        }

        It "Returns the documented exit code 1 when sign-in is enabled on a shared mailbox" {
            $enabledMailbox = @([pscustomobject]@{
                DisplayName = 'Shared-Bad'; UserPrincipalName = 'shared-bad@contoso.com'
                PrimarySmtpAddress = 'shared-bad@contoso.com'; WhenCreated = (Get-Date '2024-01-01')
                AccountDisabled = $false
            })
            Mock Get-EXOMailbox {
                if ($Properties -contains 'GrantSendOnBehalfTo') { return $smbDetail }
                return $enabledMailbox
            }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match 'Sign-In Enabled \(should be disabled\): 1'
            ($out | Out-String) | Should -Match 'Issues Found: 1'
        }

        It "Counts Full Access, Send As, and Send on Behalf permissions" {
            . $scriptPath -IncludePermissions
            Mock Get-EXOMailboxPermission {
                @([pscustomobject]@{
                    User = 'alice@contoso.com'; AccessRights = @('FullAccess')
                    IsInherited = $false
                })
            }
            Mock Get-EXORecipientPermission {
                @([pscustomobject]@{
                    Trustee = 'bob@contoso.com'; AccessRights = @('SendAs')
                })
            }
            Mock Get-EXOMailbox {
                if ($Properties -contains 'GrantSendOnBehalfTo') {
                    return [pscustomobject]@{ GrantSendOnBehalfTo = @('manager@contoso.com') }
                }
                return $sharedListing
            }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Without Permissions: 0'
            Should -Invoke Get-EXORecipientPermission -Exactly 1
        }

        It "Flags shared mailboxes without any permissions" {
            . $scriptPath -IncludePermissions
            Mock Get-EXOMailboxPermission { @() }
            Mock Get-EXORecipientPermission { @() }
            Mock Get-EXOMailbox {
                if ($Properties -contains 'GrantSendOnBehalfTo') {
                    return [pscustomobject]@{ GrantSendOnBehalfTo = @() }
                }
                return $sharedListing
            }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match 'Without Permissions: 1'
            ($out | Out-String) | Should -Match 'Issues Found: 1'
        }

        It "Detects inactive mailboxes with -CheckInactive without failing the run" {
            . $scriptPath -CheckInactive -InactivityDays 90
            Mock Get-EXOMailboxStatistics {
                @([pscustomobject]@{
                    TotalItemSize = '512 MB (536,870,912 bytes)'
                    ItemCount     = 50
                    LastLogonTime = (Get-Date).AddDays(-180)
                })
            }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Inactive \(>90 days\): 1'
        }

        It "Returns 1 with [-] output when connecting fails" {
            Mock Connect-ExchangeOnline { throw 'logon failed' }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Exports an HTML report when -ExportHTML is used" {
            . $scriptPath -ExportHTML
            Main | Should -Be 0
            Should -Invoke Out-File -ParameterFilter { $FilePath -like '*SharedMailboxAudit_*.html' } -Exactly 1
        }

        It "Exports a CSV report when -ExportCSV is used" {
            . $scriptPath -ExportCSV
            Main | Should -Be 0
            Should -Invoke Export-Csv -ParameterFilter { $Path -like '*SharedMailboxAudit_*.csv' } -Exactly 1
        }
    }
}
