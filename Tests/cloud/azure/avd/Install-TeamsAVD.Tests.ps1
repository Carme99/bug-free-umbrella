#Requires -Modules Pester

Describe "Install-TeamsAVD" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/cloud/azure/avd/ -> the script sits
        # three levels up + across at scripts/cloud/azure/avd/. The top-level guard
        # skips Main when dot-sourced.
        $scriptPath = Join-Path $PSScriptRoot "../../../../scripts/cloud/azure/avd/Install-TeamsAVD.ps1"
        . $scriptPath

        # Bind the script's parameters to safe offline values for behavior tests.
        $LogPath = Join-Path $TestDrive "logs/TeamsAVD_Install_Test.log"
        $AcceptEULA = $true
        $SkipUserCleanup = $false
        $Force = $false
        $SkipSignatureCheck = $false
        $InstallWebRtcRedirector = $false

        # ---- Mock ALL external commands/wrappers. Nothing leaves the machine. ----

        # Native installers are only ever started through the wrapper seam (never by exe name).
        Mock Start-InstallerProcess { [pscustomobject]@{ ExitCode = 0 } }
        Mock Invoke-InstallerDownload { }

        # Signature validation is the script's own wrapper over Get-AuthenticodeSignature.
        Mock Test-FileSignature { $true }

        # Registry/filesystem surface (HKLM does not exist on Linux CI).
        Mock Test-Path { $true }
        Mock Get-Item { [pscustomobject]@{ Length = 10MB } }
        Mock Remove-Item { }
        Mock New-Item { }
        Mock Set-ItemProperty { }
        Mock Get-ItemProperty {
            [pscustomobject]@{
                pv                                = '120.0.6099.56'
                IsWVDEnvironment                  = 1
                AllowAllTrustedApps               = 1
                AllowDevelopmentWithoutDevLicense = 1
                PreventUserFromUpdatingTeams      = 1
            }
        }

        # Transcript logging must not touch real console host state.
        Mock Start-Transcript { }
        Mock Stop-Transcript { }

        # User-profile discovery is the script's own wrapper over Get-ChildItem.
        Mock Get-UserProfilesList { @() }

        # Version probes start uninstalled; Wait-ForVersionDetection stands in for post-install detection.
        Mock Get-WebView2Version { $null }
        Mock Get-TeamsVersion { $null }
        Mock Wait-ForVersionDetection { '9.9.9' }
    }

    Context "Help & Metadata" {
        It "Declares all five required .NOTES fields with relaunch values" {
            $raw = Get-Content $scriptPath -Raw
            $raw | Should -Match '(?m)^\s*\.NOTES'
            $raw | Should -Match 'File Name\s*:\s*Install-TeamsAVD\.ps1'
            $raw | Should -Match 'Author\s*:\s*\S'
            $raw | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match 'Version\s*:\s*1\.0\.0'
            $raw | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Documents one .PARAMETER per declared parameter, in declaration order" {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object {
                if ($_.Name -is [string]) { $_.Name.TrimStart('$') }
                else { $_.Name.Extent.Text.TrimStart('$') }
            })
            $documented = @([regex]::Matches(
                    (Get-Content $scriptPath -Raw), '(?m)^\s*\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value })
            $documented.Count | Should -Be $declared.Count
            $documented | Should -Be $declared
        }

        It "Provides at least two realistic examples with PS prompts" {
            $raw = Get-Content $scriptPath -Raw
            $examples = [regex]::Matches($raw, '(?m)^\s*\.EXAMPLE')
            $examples.Count | Should -BeGreaterOrEqual 2
            $raw | Should -Match '(?m)^\s*PS C:\\>'
        }

        It "Renders completely via Get-Help -Detailed" {
            $help = Get-Help -Detailed $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
            # Declared parameters plus WhatIf/Confirm from SupportsShouldProcess.
            @($help.Parameters.Parameter).Count | Should -Be 8
            @($help.examples.example).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses without errors via the language parser" {
            $tokens = $null
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $parseErrors.Count | Should -Be 0
        }

        It "Opts out of 5.1 semantics with #Requires -Version 7.0 on line 1" {
            (Get-Content $scriptPath)[0] | Should -Match '^#Requires -Version 7\.0'
        }

        It "Uses UTF-8 with BOM and CRLF-only line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
            $rawText = [System.IO.File]::ReadAllText($scriptPath)
            $rawText | Should -Not -Match "(?<!\r)\n" -Because "bare LF bytes are forbidden"
        }

        It "Meets formatting rules: 4-space indent, no tabs, no trailing whitespace, <=120 columns" {
            $lines = @(Get-Content $scriptPath)
            ($lines | Where-Object { $_ -match "`t" }) | Should -BeNullOrEmpty
            ($lines | Where-Object { $_ -match ' +$' }) | Should -BeNullOrEmpty
            ($lines | Where-Object { $_.Length -gt 120 }) | Should -BeNullOrEmpty
        }

        It "Declares [CmdletBinding(SupportsShouldProcess)] and only approved verbs" {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $cmdletBinding = $ast.ParamBlock.Attributes |
                Where-Object { $_.TypeName.Name -eq 'CmdletBinding' }
            $cmdletBinding | Should -Not -BeNullOrEmpty
            $cmdletBinding.NamedArguments |
                Where-Object { $_.ArgumentName -eq 'SupportsShouldProcess' } | Should -Not -BeNullOrEmpty

            $functions = $ast.FindAll(
                { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
                $false)
            $approvedVerbs = (Get-Verb).Verb
            foreach ($fn in $functions) {
                if ($fn.Name -eq 'Main') { continue }  # entry-point helper per RELAUNCH-SPEC §3
                $verb = ($fn.Name -split '-')[0]
                $approvedVerbs | Should -Contain $verb -Because "$($fn.Name) must use an approved verb"
            }
        }
    }

    Context "Behavior" {
        It "Performs a fresh install: downloads both installers, runs both wrappers, returns 0" {
            Main | Should -Be 0
            Should -Invoke Invoke-InstallerDownload -Times 2 -Exactly
            Should -Invoke Start-InstallerProcess -Times 2 -Exactly
            Should -Invoke Wait-ForVersionDetection -Times 2 -Exactly
        }

        It "Is idempotent: converged system returns 0 with no downloads or installer runs" {
            Mock Get-WebView2Version { '120.0.6099.56' }
            Mock Get-TeamsVersion { '24193.1708.2432.2349' }
            Main | Should -Be 0
            Should -Invoke Invoke-InstallerDownload -Times 0 -Exactly -Because "components are current"
            Should -Invoke Start-InstallerProcess -Times 0 -Exactly -Because "nothing left to install"
        }

        It "Returns 1 and performs no work when the EULA is not accepted" {
            $AcceptEULA = $false
            try {
                Main | Should -Be 1
                Should -Invoke Invoke-InstallerDownload -Times 0 -Exactly
                Should -Invoke Start-Transcript -Times 0 -Exactly
            }
            finally {
                $AcceptEULA = $true
            }
        }

        It "Installs the WebRTC Redirector via msiexec when -InstallWebRtcRedirector is set" {
            $InstallWebRtcRedirector = $true
            try {
                # The generic Test-Path mock reports everything present; make the
                # redirector service itself look absent so the msiexec path executes.
                Mock Test-Path -ParameterFilter { $Path -eq $script:WebRtcRedirectorInstallPath } `
                    { $false }
                Main | Should -Be 0
                Should -Invoke Start-InstallerProcess -Times 3 -Exactly
                Should -Invoke Start-InstallerProcess -ParameterFilter { $FilePath -eq 'msiexec.exe' } `
                    -Times 1 -Exactly
            }
            finally {
                $InstallWebRtcRedirector = $false
            }
        }

        It "Returns 3 and writes [-]-prefixed error output when an installer fails" {
            Mock Start-InstallerProcess { [pscustomobject]@{ ExitCode = 1603 } }
            Mock Wait-ForVersionDetection { $null }
            $output = Main *>&1
            ($output | Where-Object { $_ -is [int] }) | Should -Be 3
            ($output | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 4 when registry configuration fails" {
            Mock Set-RegistryValue { $false }
            Mock Get-WebView2Version { '120.0.6099.56' }
            Mock Get-TeamsVersion { '24193.1708.2432.2349' }
            Main | Should -Be 4
        }
    }
}
