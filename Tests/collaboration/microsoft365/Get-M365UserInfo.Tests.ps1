#Requires -Modules Pester

Describe "Get-M365UserInfo" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/collaboration/microsoft365/ ->
        # script is three levels up + across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/collaboration/microsoft365/Get-M365UserInfo.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Reset script-scoped state initialized by the dot-sourced script.
        $script:UserData = @{}
        $script:ConnectedServices.ExchangeOnline = $false
        $script:ConnectedServices.MicrosoftGraph = $false

        # Default parameter state (dot-sourced param defaults).
        $UserEmail = ''
        $AutoConnect = $false
        $QuickView = $false
        $ExportReport = $false

        # ---- Offline stubs + mocks for every external command ----
        # Pre-define stub functions for module cmdlets whose modules are not
        # installed offline, so Pester has a resolvable command to mock.
        function Get-ConnectionInformation { }
        function Get-MgContext { }
        function Connect-ExchangeOnline { }
        function Connect-MgGraph { }
        function Get-EXOMailbox { }
        function Get-EXOMailboxStatistics { }
        function Get-MgUser { }
        function Get-MgUserLicenseDetail { }
        function Get-QuarantineMessage { }
        function Get-MobileDevice { }
        function Get-MgUserMemberOf { }

        Mock Clear-Host { }
        Mock Read-Host { '' }

        # Module availability probes report required modules as installed.
        Mock Get-Module { [pscustomobject]@{ Name = $Name } } -ParameterFilter {
            $Name -eq 'ExchangeOnlineManagement' -or $Name -eq 'Microsoft.Graph.Authentication'
        }
        Mock Get-ConnectionInformation { [pscustomobject]@{ UserPrincipalName = 'admin@contoso.com' } }
        Mock Connect-ExchangeOnline { }
        Mock Get-MgContext { [pscustomobject]@{ Account = 'admin@contoso.com' } }
        Mock Connect-MgGraph { }

        $mailbox = [pscustomobject]@{
            DisplayName          = 'John Doe'
            PrimarySmtpAddress   = 'john.doe@contoso.com'
            UserPrincipalName    = 'john.doe@contoso.com'
            RecipientTypeDetails = 'UserMailbox'
            ProhibitSendQuota    = '100 GB (107374182400 bytes)'
            ArchiveStatus        = 'Active'
        }
        $aadUser = [pscustomobject]@{
            DisplayName     = 'John Doe'
            UserPrincipalName = 'john.doe@contoso.com'
            JobTitle        = 'Analyst'
            Department      = 'IT'
            AccountEnabled  = $true
            CreatedDateTime = [datetime]'2024-01-01'
            SignInActivity  = $null
        }
        Mock Get-EXOMailbox { $mailbox }
        Mock Get-MgUser { $aadUser }
        Mock Get-EXOMailboxStatistics {
            [pscustomobject]@{
                TotalItemSize = '1.50 GB (1610612736 bytes)'
                ItemCount     = 1234
                LastLogonTime = [datetime]'2026-08-20'
            }
        }
        Mock Get-MgUserLicenseDetail {
            @([pscustomobject]@{ SkuPartNumber = 'ENTERPRISEPACK'; ServicePlans = @() })
        }
        Mock Get-QuarantineMessage { $null }
        Mock Get-MobileDevice { @() }
        Mock Get-MgUserMemberOf { @() }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date 2026-08-23 in .NOTES" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match 'Version\s*:\s*1\.0\.0'
            $raw | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Matches .NOTES File Name to the disk filename and declares the prerequisite" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match 'File Name\s*:\s*Get-M365UserInfo\.ps1'
            $raw | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
        }

        It "Has one .PARAMETER section per declared parameter, in declaration order" {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$errors)
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $helpParams = [regex]::Matches((Get-Content -Raw $scriptPath), '(?m)^\s*\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value }
            $helpParams | Should -Be $declared
        }

        It "Has at least two examples showing realistic PS C:\> invocations" {
            $raw = Get-Content -Raw $scriptPath
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            $raw | Should -Match 'PS C:\\>'
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero parser errors" {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
            $errors.Count | Should -Be 0
        }

        It "Uses no PS7-only syntax and does not opt out via #Requires -Version 7.0" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Not -Match '#Requires\s+-Version\s+7\.0'
            $raw | Should -Not -Match '\|\|'
            $raw | Should -Not -Match '&&'
            $raw | Should -Not -Match '\?\?'
        }

        It "Is stored UTF-8 with BOM and CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0..2] -join ',') | Should -Be '239,187,191'
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            [regex]::Matches($text, "(?<!\r)\n").Count | Should -Be 0
        }
    }

    Context "Behavior" {
        It "Returns 1 with [-] output when no service connects and the technician declines reconnect" {
            Mock Get-Module { $null } -ParameterFilter {
                $Name -eq 'ExchangeOnlineManagement' -or $Name -eq 'Microsoft.Graph.Authentication'
            }
            Mock Read-Host { 'N' }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "QuickView retrieves mailbox statistics, licenses, and quarantine, then returns 0 with [+] output" {
            $UserEmail = 'john.doe@contoso.com'
            $AutoConnect = $true
            $QuickView = $true
            $ExportReport = $false
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Get-EXOMailboxStatistics -Times 1 -Exactly
            Should -Invoke Get-MgUserLicenseDetail -Times 1 -Exactly
            Should -Invoke Get-QuarantineMessage -Times 1 -Exactly
        }

        It "Returns 1 and reports failure when the mailbox cannot be retrieved" {
            $UserEmail = 'ghost@contoso.com'
            $AutoConnect = $true
            $QuickView = $false
            $ExportReport = $false
            Mock Get-EXOMailbox { throw "recipient not found" }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match 'Could not retrieve mailbox'
        }

        It "ExportReport mode writes an HTML report file and returns 0" {
            $UserEmail = 'john.doe@contoso.com'
            $AutoConnect = $true
            $QuickView = $false
            $ExportReport = $true
            Mock Join-Path { '/tmp/mock-reports' }
            Mock Test-Path { $false }
            Mock New-Item { }
            Mock Out-File { }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Out-File -Times 1 -Exactly
        }
    }
}
