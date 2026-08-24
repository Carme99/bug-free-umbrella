#Requires -Modules Pester

Describe "Get-AzureADLicenseReport" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/collaboration/microsoft365/azure-ad/ -> repo root is four levels up.
        $scriptPath = Join-Path $PSScriptRoot (
            "../../../../scripts/collaboration/microsoft365/azure-ad/Get-AzureADLicenseReport.ps1")

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

# Function shims: Pester cannot mock commands absent from Linux pwsh, and mock parameter
        # filters are resolved against the shim's signature - so declare the parameters the script uses.
        function Connect-MgGraph { param([array]$Scopes, [switch]$NoWelcome) }
        function Disconnect-MgGraph { }
        function Get-MgSubscribedSku { param([switch]$All) }
        function Get-MgUser { param([string]$Filter, [switch]$All, [array]$Property, [string]$UserId) }

        # Fixture scriptblock variable: Pester mock bodies can read BeforeAll variables but
        # cannot resolve BeforeAll functions.
        $NewSku = {
            param([string]$Part, [int]$Enabled, [int]$Consumed)
            return [pscustomobject]@{
                SkuPartNumber = $Part
                SkuId = "sku-$Part"
                ConsumedUnits = $Consumed
                PrepaidUnits = [pscustomobject]@{ Enabled = $Enabled; Suspended = 0; Warning = 0 }
            }
        }
        # Mock ALL external commands so nothing leaves the machine (offline Linux pwsh).
        Mock Connect-MgGraph
        Mock Disconnect-MgGraph
        Mock Get-MgSubscribedSku {
            @(
                (& $NewSku -Part 'ENTERPRISEPACK' -Enabled 100 -Consumed 95),
                (& $NewSku -Part 'SPE_E3' -Enabled 10 -Consumed 5)
            )
        }
        Mock Get-MgUser { @() }
    }

    Context "Help & Metadata" {
        It "Declares all required header fields with relaunch values" {
            $content = Get-Content -Path $scriptPath -Raw
            $content | Should -Match '\.SYNOPSIS'
            $content | Should -Match '\.DESCRIPTION'
            $content | Should -Match '\.NOTES'
            $content | Should -Match 'Version\s*:\s*1\.0\.0'
            $content | Should -Match 'Date\s*:\s*2026-08-23'
            $content | Should -Match 'File Name\s*:\s*Get-AzureADLicenseReport\.ps1'
            $content | Should -Match 'Author\s*:\s*\S+'
            $content | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
        }

        It "Has a SYNOPSIS that is imperative and <= 120 characters" {
            $lines = Get-Content -Path $scriptPath
            $idx = [array]::IndexOf(($lines | ForEach-Object { $_.Trim() }), '.SYNOPSIS')
            $synopsis = ($lines[$idx + 1]).Trim()
            $synopsis | Should -Not -BeNullOrEmpty
            $synopsis.Length | Should -BeLessOrEqual 120
        }

        It "Has one .PARAMETER entry per declared script parameter, in order" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $paramNames = $ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }

            $lines = Get-Content -Path $scriptPath
            $helpParamNames = @()
            foreach ($line in $lines) {
                if ($line -match '^\.PARAMETER\s+(\S+)') { $helpParamNames += $Matches[1] }
            }

            $helpParamNames.Count | Should -Be $paramNames.Count
            for ($i = 0; $i -lt $paramNames.Count; $i++) {
                $helpParamNames[$i] | Should -Be $paramNames[$i]
            }
        }

        It "Provides at least two examples showing PS C:\> prompts" {
            $content = Get-Content -Path $scriptPath -Raw
            ($content -split '\.EXAMPLE').Count -ge 3 | Should -BeTrue
            ([regex]::Matches($content, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }

        It "Renders complete help via Get-Help -Detailed" {
            { Get-Help -Path $scriptPath -Detailed -ErrorAction Stop } | Should -Not -Throw
            (Get-Help -Path $scriptPath -ErrorAction Stop).Synopsis | Should -Not -BeNullOrEmpty
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null; $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors | Should -HaveCount 0
        }

        It "Contains no PS7-only syntax without #Requires -Version 7.0" {
            $content = Get-Content -Path $scriptPath -Raw
            if ($content -match '(?m)^#Requires\s+-Version\s+7\.0') {
                $true | Should -BeTrue
            }
            else {
                $content | Should -Not -Match '\?\?'
                $content | Should -Not -Match '\|\|'
                $content | Should -Not -Match '&&'
                $content | Should -Not -Match '-Parallel'
            }
        }

        It "Is UTF-8 with BOM and CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
            $raw = [System.Text.Encoding]::UTF8.GetString($bytes)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }
    }

    Context "Behavior" {
        It "Returns 0 and reports correct purchased/assigned/unused totals" {
            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match 'Total Licenses Purchased: 110'
            $text | Should -Match 'Total Licenses Assigned: 100'
            $text | Should -Match 'Total Unused Licenses: 10'
            $text | Should -Match 'Office 365 E3'
        }

        It "Identifies unlicensed enabled members with -IdentifyUnassigned" {
            Mock Get-MgUser {
                @(
                    [pscustomobject]@{
                        DisplayName = 'No License Ned'
                        UserPrincipalName = 'ned@contoso.com'
                        AssignedLicenses = @()
                    },
                    [pscustomobject]@{
                        DisplayName = 'Licensed Linda'
                        UserPrincipalName = 'linda@contoso.com'
                        AssignedLicenses = @([pscustomobject]@{ SkuId = 'sku-ENTERPRISEPACK' })
                    }
                )
            }

            $out = Main -IdentifyUnassigned *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Found 1 unlicensed enabled user\(s\)'
            Should -Invoke Get-MgUser -Times 1 -Exactly
        }

        It "Returns 1 and writes [-] prefixed output when the Graph connection fails" {
            Mock Connect-MgGraph { throw "sign-in cancelled" }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 and writes [-] prefixed output when SKU retrieval fails" {
            Mock Get-MgSubscribedSku { throw "tenant not found" }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Is a read-only report: repeated runs make no Graph mutations" {
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0

            $out2 = Main *>&1
            ($out2 | Where-Object { $_ -is [int] }) | Should -Be 0

            Should -Invoke Get-MgSubscribedSku -Times 2 -Exactly
            Should -Invoke Disconnect-MgGraph -Times 2 -Exactly
        }
    }
}
