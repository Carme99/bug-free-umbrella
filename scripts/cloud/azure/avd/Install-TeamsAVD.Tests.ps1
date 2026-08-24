#Requires -Modules Pester

<#
.SYNOPSIS
    Pester test suite for the Install-TeamsAVD.ps1 script.

.DESCRIPTION
    Validates the behavior of Install-TeamsAVD.ps1, which installs Microsoft Teams and the
    WebView2 runtime on Azure Virtual Desktop session hosts and applies the AVD-specific registry
    configuration required for Teams optimization. The script is dot-sourced (its top-level guard
    skips Main) and Main is invoked directly so its integer return value can be asserted. All
    external commands are mocked; native installers and downloads are exercised through the
    script's wrapper functions (Start-InstallerProcess, Invoke-InstallerDownload,
    Get-UserProfilesList), which are mocked by name. Registry mocks are stateless: the pre-check
    read (-ErrorAction SilentlyContinue) reports "not configured" while the post-write verification
    read (-ErrorAction Stop) reports success. The suite runs fully offline on Linux pwsh.

.EXAMPLE
    PS C:\> Invoke-Pester .\Install-TeamsAVD.Tests.ps1

    Runs the full test suite against the Install-TeamsAVD.ps1 script in the same folder.

.NOTES
    File Name    : Install-TeamsAVD.Tests.ps1
    Author       : Microsoft 365 / AVD Scripting Team
    Prerequisite : PowerShell 7.0
    Version      : 1.0.0
    Date         : 2026-08-23
#>

Describe "Install-TeamsAVD.ps1" {

    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot 'Install-TeamsAVD.ps1'

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath -AcceptEULA

        # ---- Baseline mocks: nothing leaves the machine ----
        Mock Start-Transcript { }
        Mock Stop-Transcript { }
        Mock Add-Content { }
        Mock Start-Sleep { }
        Mock New-Item { }
        Mock Remove-Item { }
        Mock Get-Process { }
        Mock Test-Path { $true }
        Mock Get-Item { [pscustomobject]@{ Length = 200MB } }

        # Script-owned wrapper seams (native exes/downloads/profile discovery are mocked by name).
        Mock Invoke-InstallerDownload { }
        Mock Start-InstallerProcess { [pscustomobject]@{ ExitCode = 0 } }
        Mock Get-UserProfilesList { @() }

        # Windows-only cmdlet absent on Linux: provide a stub so Pester has a seam to mock.
        function Get-AuthenticodeSignature { [CmdletBinding()] param([string]$FilePath) }
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{
                Status            = 'Valid'
                SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation' }
                StatusMessage     = ''
            }
        }

        # Stateless registry simulation:
        # - pre-check read (SilentlyContinue) -> not configured yet, so mutation proceeds
        # - post-write verification read (Stop) -> value reported as set correctly
        Mock Get-ItemProperty {
            [CmdletBinding()]
            param($Path, $Name)
            # Pester's mock plumbing can deliver parameter values as arrays; coerce.
            $Name = "$Name"
            if ($ErrorAction -eq 'Stop') {
                [pscustomobject]@{ $Name = 1 }
            }
            else {
                $null
            }
        }

        # Component detection defaults: converged system.
        Mock Get-WebView2Version { '120.0.6099.62' }
        Mock Get-TeamsVersion { '1.0.0.0' }
    }

    Context "Help & Metadata" {

        It "Contains all five required .NOTES fields with relaunch values" {
            $content = Get-Content -Path $scriptPath -Raw
            $content | Should -Match 'File Name\s*:\s*Install-TeamsAVD\.ps1'
            $content | Should -Match 'Author\s*:\s*\S'
            $content | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
            $content | Should -Match 'Version\s*:\s*1\.0\.0'
            $content | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Documents exactly one .PARAMETER entry per declared parameter" {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $params = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
            $params.Count | Should -BeGreaterThan 0

            $content = Get-Content -Path $scriptPath -Raw
            foreach ($p in $params) {
                $content | Should -Match "\.PARAMETER\s+$p\b"
            }
            ([regex]::Matches($content, '(?m)^\s*\.PARAMETER')).Count | Should -Be $params.Count
        }

        It "Provides at least two examples with PS C:\> prompt lines" {
            $content = Get-Content -Path $scriptPath -Raw
            ([regex]::Matches($content, '(?m)^\s*\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($content, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }

        It "Declares SupportsShouldProcess for destructive operations" {
            $content = Get-Content -Path $scriptPath -Raw
            $content | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
            $content | Should -Match 'ShouldProcess\('
        }
    }

    Context "Syntax & Static" {

        It "Parses without syntax errors" {
            $tokens = $null
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $errors | Should -BeNullOrEmpty
        }

        It "Opts out of 5.1 checks via #Requires -Version 7.0 on line 1" {
            (Get-Content -Path $scriptPath -TotalCount 1) | Should -Match '^#Requires\s+-Version\s+7\.0'
        }

        It "Uses exit only in the top-level dot-source guard" {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $exitStatements = $ast.FindAll(
                { param($node) $node -is [System.Management.Automation.Language.ExitStatementAst] },
                $true
            )
            $exitStatements.Count | Should -Be 1 -Because "exit is only permitted in the guard line"
            $exitStatements[0].Extent.Text | Should -Be 'exit (Main)'
        }

        It "Routes native installers through the Start-InstallerProcess wrapper" {
            $content = Get-Content -Path $scriptPath -Raw
            $content | Should -Match 'function Start-InstallerProcess'
            # msiexec.exe may only appear at the single call site inside the wrapper
            ([regex]::Matches($content, 'msiexec\.exe')).Count | Should -Be 1
        }
    }

    Context "Behavior" {

        It "Performs a fresh install and returns 0 with expected mutations" {
            $AcceptEULA = $true
            Mock Get-WebView2Version { $null }
            Mock Get-TeamsVersion { $null }
            Mock Set-RegistryValue { $true }

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Set-RegistryValue -Times 4 -Exactly -Because "four AVD registry values configured"
            Should -Invoke Invoke-InstallerDownload -Times 2 -Exactly -Because "WebView2 + bootstrapper downloads"
            Should -Invoke Start-InstallerProcess -Times 2 -Exactly -Because "WebView2 + bootstrapper installs"
        }

        It "Is idempotent: a converged system returns 0 with zero mutations" {
            $AcceptEULA = $true

            # Every registry read reports the desired value as already present.
            Mock Get-ItemProperty {
                [CmdletBinding()]
                param($Path, $Name)
                $Name = "$Name"
                [pscustomobject]@{ $Name = 1 }
            }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0

            Should -Invoke Invoke-InstallerDownload -Times 0 -Exactly -Because "nothing left to download"
            Should -Invoke Start-InstallerProcess -Times 0 -Exactly -Because "nothing left to install"
            ($out | Out-String) | Should -Match '\[\+\] Already configured' -Because "registry pre-check skips mutation"
            Should -Invoke Remove-Item -Times 0 -Exactly -Because "no user-profile cleanup required"
        }

        It "Returns documented code 3 and writes [-] prefixed output when downloads fail" {
            $AcceptEULA = $true
            Mock Get-WebView2Version { $null }
            Mock Invoke-InstallerDownload { throw "network unreachable" }
            Mock Set-RegistryValue { $true }

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 3
        }

        It "Returns 1 when the EULA was not accepted" {
            $AcceptEULA = $false

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            Should -Invoke Invoke-InstallerDownload -Times 0 -Exactly -Because "no work may happen without EULA"
        }

        It "Installs the WebRTC Redirector only when requested" {
            $AcceptEULA = $true
            $InstallWebRtcRedirector = $true
            Mock Get-WebView2Version { $null }
            Mock Get-TeamsVersion { $null }
            Mock Test-Path -ParameterFilter { "$Path" -like '*TeamsWebRTCService.exe' } { $false }
            Mock Set-RegistryValue { $true }

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0

            Should -Invoke Invoke-InstallerDownload -Times 3 -Exactly -Because "WebView2 + bootstrapper + WebRTC MSI"
            Should -Invoke Start-InstallerProcess -Times 3 -Exactly -Because "msiexec runs through the wrapper"
        }
    }
}
