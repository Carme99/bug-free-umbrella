#Requires -Modules Pester

Describe "Set-SiteRegionalSettings.ps1" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/collaboration/microsoft365/sharepoint-onedrive/ -> four levels up to repo root.
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/collaboration/microsoft365/sharepoint-onedrive/Set-SiteRegionalSettings.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (spec §3).
        . $scriptPath

        # Stub + mock external module surface so nothing leaves the machine.
        # PnP.PowerShell is not installed offline: declare stubs so Pester can attach mocks.
        function Connect-PnPOnline { }
        function Get-PnPTenantSite { }
        function Get-PnPWeb { }
        function Get-PnPContext { }
        function Set-PnPWeb { }
        Mock Get-Module { [pscustomobject]@{ Name = 'PnP.PowerShell' } }
        Mock Import-Module { }
        Mock Connect-PnPOnline { }
        Mock Get-PnPTenantSite { @() }
        Mock Read-Host { 'https://contoso-admin.sharepoint.com' }
        Mock Set-SiteRegionalConfiguration { $true }
        Mock Test-Path { $true }
        Mock New-Item { }

        function New-MockRegionalSettings {
            param(
                [int]$TimeZoneId = 2,
                [int]$Locale = 2057,
                [int]$Calendar = 1,
                [bool]$Use24Hour = $true
            )
            [pscustomobject]@{
                RegionalSettings = [pscustomobject]@{
                    TimeZone         = [pscustomobject]@{ Id = $TimeZoneId }
                    LocaleId         = $Locale
                    CalendarType     = $Calendar
                    WorkDayStartHour = 8
                    WorkDayEndHour   = 17
                    FirstDayOfWeek   = 1
                    Time24           = $Use24Hour
                }
            }
        }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date 2026-08-23" {
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            $raw | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
            $raw | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
        }

        It "Declares File Name matching the actual filename and PowerShell 7.0 prerequisite" {
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            $fileName = Split-Path $scriptPath -Leaf
            $raw | Should -Match ([regex]::Escape("File Name  : $fileName"))
            $raw | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
        }

        It "Has an imperative .SYNOPSIS of at most 120 characters" {
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            $match = [regex]::Match($raw, '(?ms)\.SYNOPSIS\r?\n(.*?)\r?\n\.')
            $match.Success | Should -BeTrue
            $synopsis = (($match.Groups[1].Value -split "\r?\n") | ForEach-Object { $_.Trim() }) -join ' '
            $synopsis | Should -Not -BeNullOrEmpty
            $synopsis.Length | Should -BeLessOrEqual 120
        }

        It "Documents exactly one .PARAMETER block per declared parameter, in order" {
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            $helpParams = [regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value }

            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declaredParams = $ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }

            $helpParams.Count | Should -Be $declaredParams.Count
            $helpParams | Should -Be $declaredParams
        }

        It "Provides at least two .EXAMPLE blocks with PS C:\> prompts" {
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            ([regex]::Matches($raw, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero syntax errors" {
            $tokens = $null
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Uses no PS7-only operators unless #Requires -Version 7.0 is line 1" {
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            $firstLine = ($raw -split "\r?\n")[0]
            $allowsPs7OnlySyntax = $firstLine -match '#Requires\s+-Version\s+7'

            if (-not $allowsPs7OnlySyntax) {
                $badKinds = @('AndAnd', 'OrOr', 'QuestionMark', 'QuestionQuestion', 'QuestionQuestionEquals')
                $tokens = $null
                $parseErrors = $null
                $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
                $offenders = @($tokens | Where-Object { $badKinds -contains $_.Kind.ToString() })
                $offenders | Should -BeNullOrEmpty -Because "PS7-only operators require #Requires -Version 7.0"
                $raw | Should -Not -Match '\-Parallel'
            }
        }

        It "Is saved as UTF-8 with BOM and CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
            $raw = Get-Content -LiteralPath $scriptPath -Raw
            $raw | Should -Not -Match "(?<!\r)\n"
        }

        It "Keeps every line at or below 120 columns without trailing whitespace" {
            $lines = [System.IO.File]::ReadAllLines($scriptPath)
            $tooLong = @($lines | Where-Object { $_.Length -gt 120 })
            $tooLong | Should -BeNullOrEmpty
            $trailing = @($lines | Where-Object { $_ -match '[ \t]+$' })
            $trailing | Should -BeNullOrEmpty
        }

        It "Contains exit only in the top-level dot-source guard line" {
            $lines = [System.IO.File]::ReadAllLines($scriptPath)
            $exitLines = @($lines | Where-Object { $_ -cmatch '(?<!\w)exit(?!\w)' })
            $exitLines.Count | Should -Be 1
            $exitLines[0] | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\)'
        }
    }

    Context "Behavior" {
        It "Returns 1 with [-] prefixed output when the PnP.PowerShell module is missing" {
            Mock Get-Module { $null }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Returns 1 when neither -SiteUrl nor -AllSites is supplied" {
            $SiteUrl = ''
            $AllSites = $false

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Is idempotent: a compliant site returns 0 with no mutation attempted" {
            $SiteUrl = 'https://contoso.sharepoint.com/sites/TeamSite'
            $Apply = $false
            Mock Get-PnPWeb { New-MockRegionalSettings }

            $out = Main *>&1

            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Set-SiteRegionalConfiguration -Times 0 -Exactly -Because "site is already compliant"
        }

        It "Reports non-compliant sites in audit mode and returns 1 without changing anything" {
            $SiteUrl = 'https://contoso.sharepoint.com/sites/TeamSite'
            $Apply = $false
            Mock Get-PnPWeb { New-MockRegionalSettings -TimeZoneId 13 -Locale 1033 -Calendar 1 -Use24Hour:$false }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[!\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            Should -Invoke Set-SiteRegionalConfiguration -Times 0 -Exactly
        }

        It "Applies settings exactly once for a non-compliant site under -Apply and returns 0" {
            $SiteUrl = 'https://contoso.sharepoint.com/sites/TeamSite'
            $Apply = $true
            Mock Get-PnPWeb { New-MockRegionalSettings -TimeZoneId 13 -Locale 1033 -Calendar 1 -Use24Hour:$false }

            $out = Main *>&1

            $out | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Set-SiteRegionalConfiguration -Times 1 -Exactly
        }

        It "Gates the site mutation behind ShouldProcess: -WhatIf performs no changes" {
            Mock Set-PnPWeb { }
            Mock Get-PnPContext { throw "CSOM must not run under -WhatIf" }

            $whatIfParams = @{
                SiteUrl          = 'https://contoso.sharepoint.com/sites/TeamSite'
                LocaleId         = 2057
                TimeZone         = 2
                CalendarType     = 1
                WorkDayStartHour = 8
                WorkDayEndHour   = 17
                FirstDayOfWeek   = 1
                Time24           = $true
                WhatIf           = $true
            }

            { Set-SiteRegionalConfiguration @whatIfParams } | Should -Not -Throw
            Should -Invoke Set-PnPWeb -Times 0 -Exactly -Because "-WhatIf suppresses mutations"
        }
    }
}
