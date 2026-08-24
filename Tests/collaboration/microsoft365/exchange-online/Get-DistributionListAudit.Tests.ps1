#Requires -Modules Pester

Describe "Get-DistributionListAudit" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/collaboration/microsoft365/exchange-online/
        # -> the repo root is four levels up.
        $scriptRelPath = "../../../../scripts/collaboration/microsoft365/exchange-online/Get-DistributionListAudit.ps1"
        $scriptPath = (Resolve-Path (Join-Path $PSScriptRoot $scriptRelPath)).Path
        $outputDir = Join-Path $TestDrive 'reports'

        # Offline fixtures
        $dl = [pscustomobject]@{
            DisplayName                       = 'Finance DL'
            PrimarySmtpAddress                = 'finance@contoso.com'
            Alias                             = 'finance'
            RecipientTypeDetails              = 'MailUniversalDistributionGroup'
            ManagedBy                         = @('owner@contoso.com')
            RequireSenderAuthenticationEnabled = $true
            HiddenFromAddressListsEnabled     = $false
            Identity                          = 'fin-dl'
        }
        $groupMember = [pscustomobject]@{ PrimarySmtpAddress = 'alice@contoso.com' }

        # The ExchangeOnlineManagement module is NOT installed in CI, and Pester 5 cannot
        # mock commands that do not exist on disk. Seed permissive stub functions with the
        # exact parameter surface the script uses, then layer Pester mocks on top.
        function Get-OrganizationConfig {
            [CmdletBinding()] param()
        }
        function Get-AcceptedDomain {
            [CmdletBinding()] param()
        }
        function Get-DistributionGroup {
            [CmdletBinding()] param([string]$ResultSize, [string]$RecipientTypeDetails)
        }
        function Get-DistributionGroupMember {
            [CmdletBinding()] param([string]$Identity)
        }
        function Get-UnifiedGroup {
            [CmdletBinding()] param([string]$ResultSize)
        }
        function Get-UnifiedGroupLinks {
            [CmdletBinding()] param([string]$Identity, [string]$LinkType)
        }

        # Mock ALL external commands so nothing leaves the machine (offline, Linux pwsh).
        Mock Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'ExchangeOnlineManagement' } {
            [pscustomobject]@{ Name = 'ExchangeOnlineManagement' }
        }
        Mock Test-Path -ParameterFilter { $PathType -eq 'Container' } { $true }
        Mock New-Item { }
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

        Mock Get-OrganizationConfig { [pscustomobject]@{ Name = 'contoso.onmicrosoft.com' } }
        Mock Get-AcceptedDomain {
            [pscustomobject]@{ Default = $true; DomainName = [pscustomobject]@{ Domain = 'contoso.com' } }
        }
        Mock Get-DistributionGroup -ParameterFilter { $RecipientTypeDetails -eq 'MailUniversalSecurityGroup' } { @() }
        Mock Get-DistributionGroup { @($dl) }
        Mock Get-DistributionGroupMember { @($groupMember) }
        Mock Get-UnifiedGroup { @() }
        Mock Get-UnifiedGroupLinks { @() }
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
            $raw | Should -Match 'File Name\s*:\s*Get-DistributionListAudit\.ps1'
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
        It "Runs a console audit end-to-end and returns 0" {
            . $scriptPath -OutputFormat Console -OutputPath $outputDir
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] Found 1 distribution lists'
            Should -Invoke Get-DistributionGroupMember -Exactly 1
            Should -Invoke New-Item -Exactly 0 -Because "the output directory already exists"
        }

        It "Flags groups below the minimum member threshold" {
            . $scriptPath -OutputFormat Console -MinimumMembers 5 -OutputPath $outputDir
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Small Groups \(< 5 members\): 1'
        }

        It "Detects orphaned groups when -CheckForOrphaned is set" {
            $orphanedDl = [pscustomobject]@{
                DisplayName = 'Orphan DL'; PrimarySmtpAddress = 'orphan@contoso.com'; Alias = 'orphan'
                RecipientTypeDetails = 'MailUniversalDistributionGroup'; ManagedBy = @()
                RequireSenderAuthenticationEnabled = $true; HiddenFromAddressListsEnabled = $false
                Identity = 'orph-dl'
            }
            Mock Get-DistributionGroup { @($orphanedDl) }
            . $scriptPath -OutputFormat Console -CheckForOrphaned -OutputPath $outputDir
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '=== Orphaned Groups ==='
            ($out | Out-String) | Should -Match 'Orphaned Groups \(no owners\): 1'
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
            Should -Invoke Get-OrganizationConfig -Exactly 0 -Because "the module guard fires first"
        }

        It "Rejects unsafe OutputPath traversal before creating anything" {
            . $scriptPath -OutputFormat Console -OutputPath (Join-Path $outputDir '..\..')
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
            Should -Invoke Get-Module -Exactly 0 -Because "path validation precedes the module check"
        }

        It "Writes a JSON report when -OutputFormat JSON is used" {
            . $scriptPath -OutputFormat JSON -OutputPath $outputDir
            Main | Should -Be 0
            Should -Invoke Out-File -ParameterFilter { $FilePath -like '*.json' } -Exactly 1
        }

        It "Writes a CSV report when -OutputFormat CSV is used" {
            . $scriptPath -OutputFormat CSV -OutputPath $outputDir
            Main | Should -Be 0
            Should -Invoke Export-Csv -ParameterFilter { $Path -like '*.csv' } -Exactly 1
        }

        It "Writes an HTML report when -OutputFormat HTML is used" {
            . $scriptPath -OutputFormat HTML -OutputPath $outputDir
            Main | Should -Be 0
            Should -Invoke Out-File -ParameterFilter { $FilePath -like '*DistributionList-Audit-*.html' } -Exactly 1
        }
    }
}
