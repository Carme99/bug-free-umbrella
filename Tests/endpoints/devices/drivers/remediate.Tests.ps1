#Requires -Modules Pester

Describe 'endpoints/drivers/remediate' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/endpoints/devices/drivers/remediate.ps1'

        # Safe: the script top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Platform stubs so Pester can mock Windows-only cmdlets absent on Linux pwsh.
        if (-not (Get-Command 'Get-CimInstance' -ErrorAction SilentlyContinue)) {
            function Get-CimInstance { throw 'placeholder: Get-CimInstance unavailable on this platform' }
        }    }

    Context 'Help & Metadata' {
        It 'Declares Version 1.0.0 and the relaunch date' {
            $rawText = Get-Content -Path $scriptPath -Raw
            $rawText | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
            $rawText | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
        }

        It 'Records the actual disk file name in .NOTES' {
            $rawText = Get-Content -Path $scriptPath -Raw
            $rawText | Should -Match "(?m)^\s*File Name\s*:\s*remediate.ps1\s*$"
        }

        It 'Documents every declared parameter' {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $paramNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $scriptHelpOnly = ((Get-Content -Path $scriptPath -Raw) -split '(?m)^\s*(?:function|#region)\s')[0]
            $helpNames = @([regex]::Matches($scriptHelpOnly, '(?m)^\s*\.PARAMETER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
            $paramNames.Count | Should -Be $helpNames.Count
            foreach ($p in $paramNames) { $helpNames | Should -Contain $p }
        }
    }

    Context 'Syntax & Static' {
        It 'Parses without parser errors' {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors | Should -BeNullOrEmpty
        }

        It 'Uses UTF-8 BOM and CRLF line endings' {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be @(0xEF, 0xBB, 0xBF)
            $rawText = [System.Text.Encoding]::UTF8.GetString($bytes)
            ($rawText -replace '\r\n', '') | Should -Not -Match '\n'
        }

        It 'Keeps lines within 120 columns without tabs or trailing whitespace' {
            $lines = Get-Content -Path $scriptPath
            ($lines | Where-Object { $_.Length -gt 120 -and $_ -notmatch '^\s*https?://\S+\s*$' }) | Should -BeNullOrEmpty
            ($lines | Where-Object { $_ -match '\t' }) | Should -BeNullOrEmpty
            ($lines | Where-Object { $_ -match '\s+$' }) | Should -BeNullOrEmpty
        }

        It 'Avoids PS7-only syntax without #Requires -Version 7.0' {
            $rawText = Get-Content -Path $scriptPath -Raw
            if ($rawText -notmatch '(?m)^\s*#\s*Requires\s+-Version\s+7\.0') {
                $rawText | Should -Not -Match '\?\?'
                $rawText | Should -Not -Match '&&'
                $rawText | Should -Not -Match '\|\|'
                $rawText | Should -Not -Match '\?\s*[^:\r\n]+\s*:'
            }
        }

        It 'Exits only via the dot-source guard' {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $exitTokens = @($tokens | Where-Object { $_.Kind -eq [System.Management.Automation.Language.TokenKind]::Exit })
            $exitTokens.Count | Should -Be 1
            (Get-Content -Path $scriptPath -Raw) | Should -Match ([regex]::Escape('if ($MyInvocation.InvocationName -ne ''.'') { exit (Main) }'))
        }

    }

    Context 'Behavior' {
        It 'Returns 0 and changes nothing on a non-target device' {
            Mock Get-CimInstance { [pscustomobject]@{ Model = 'NOTATARGET' } }
            Mock Set-ItemProperty { }
            Mock New-Item { }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Set-ItemProperty -Exactly 0
        }

        It 'Applies the deny list and retroactive flag on a target device' {
            Mock Get-CimInstance { [pscustomobject]@{ Model = '21L8S0VP00' } }
            function Set-ItemProperty { [CmdletBinding()] param([string]$Path, [string]$Name, [object]$Value, [string]$Type, [switch]$Force)}
            Mock Test-Path { $true }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq 'DenyDeviceIDs' } { $null }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq 'DenyDeviceIDsRetroactive' } { $null }
            Mock Set-ItemProperty { }
            Mock New-Item { }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Set-ItemProperty -Exactly 2
        }

        It 'Is idempotent: converged device returns 0 with no changes' {
            Mock Get-CimInstance { [pscustomobject]@{ Model = '21L8S0VP00' } }
            function Set-ItemProperty { [CmdletBinding()] param([string]$Path, [string]$Name, [object]$Value, [string]$Type, [switch]$Force)}
            Mock Test-Path { $true }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq 'DenyDeviceIDs' } { [pscustomobject]@{ DenyDeviceIDs = @('PCIVEN_1002&DEV_1681') } }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq 'DenyDeviceIDsRetroactive' } { [pscustomobject]@{ DenyDeviceIDsRetroactive = 1 } }
            Mock Set-ItemProperty { }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Set-ItemProperty -Exactly 0
        }

        It 'Returns 1 and writes [-] prefixed output when the registry write fails' {
            Mock Get-CimInstance { [pscustomobject]@{ Model = '21L8S0VP00' } }
            function Set-ItemProperty { [CmdletBinding()] param([string]$Path, [string]$Name, [object]$Value, [string]$Type, [switch]$Force)}
            Mock Test-Path { $true }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq 'DenyDeviceIDs' } { $null }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq 'DenyDeviceIDsRetroactive' } { $null }
            Mock Set-ItemProperty { throw 'access denied' }
            Mock New-Item { }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
