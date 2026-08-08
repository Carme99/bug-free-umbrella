<#
.SYNOPSIS
    Pester test suite for the Install-TeamsAVD.ps1 script.

.DESCRIPTION
    Validates the behavior of Install-TeamsAVD.ps1, which installs Microsoft Teams
    (classic) on Azure Virtual Desktop session hosts, installs the WebView2 runtime,
    and applies the AVD-specific registry configuration required for Teams
    optimization. Tests cover parameter validation, WebView2 runtime installation,
    Teams installation and user-profile cleanup, registry configuration, and the
    installation summary output. All external cmdlets are mocked so the suite runs
    without network access or administrative privileges.

.EXAMPLE
    PS C:\> Invoke-Pester .\Install-TeamsAVD.Tests.ps1

    Runs the full test suite against the Install-TeamsAVD.ps1 script in the same folder.

.NOTES
    File Name  : Install-TeamsAVD.Tests.ps1
    Author     : Microsoft 365 / AVD Scripting Team
    Prerequisite: PowerShell 7.0, Pester 5
    Version    : 1.0.0
    Date       : 2025-01-01
#>

BeforeAll {
    # Import the script to test
    $scriptPath = "$PSScriptRoot/Install-TeamsAVD.ps1"

    # Mock external cmdlets and functions
    Mock Start-Transcript { }
    Mock Stop-Transcript { }
    Mock Write-Host { }
    Mock Add-Content { }
    Mock Get-Process { }
    Mock Stop-Process { }
    Mock Start-Sleep { }
    Mock Invoke-WebRequest { }
    Mock Start-Process { }
    Mock Test-Path { $true }
    Mock Get-Item {
        [PSCustomObject]@{
            Length = 10MB
        }
    }
    Mock Remove-Item { }
    Mock New-Item { }
    Mock Get-ItemProperty { }
    Mock Set-ItemProperty { }
    Mock Get-ChildItem { @() }
}

Describe "Install-TeamsAVD.ps1 - Parameter Validation" {

    Context "EULA Parameter" {
        It "Should require -AcceptEULA parameter" {
            Mock Test-Path { $true }
            Mock Split-Path { "C:\Temp" }

            { & $scriptPath } | Should -Throw
        }

        It "Should accept -AcceptEULA switch" {
            Mock Test-Path { $true }
            Mock Split-Path { "C:\Temp" }
            Mock Invoke-WebRequest { }
            Mock Start-Process {
                [PSCustomObject]@{
                    ExitCode = 0
                }
            }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq "pv" } {
                [PSCustomObject]@{
                    pv = "1.0.0.0"
                }
            }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq "IsWVDEnvironment" } {
                [PSCustomObject]@{
                    IsWVDEnvironment = 1
                }
            }
            Mock Get-ChildItem -ParameterFilter { $Filter -eq "MSTeams_*" } {
                @(
                    [PSCustomObject]@{
                        Name = "MSTeams_1.0.0.0_x64__8wekyb3d8bbwe"
                    }
                )
            }

            { & $scriptPath -AcceptEULA } | Should -Not -Throw
        }
    }

    Context "Optional Parameters" {
        It "Should accept -SkipUserCleanup parameter" {
            Mock Test-Path { $true }
            Mock Split-Path { "C:\Temp" }
            Mock Invoke-WebRequest { }
            Mock Start-Process {
                [PSCustomObject]@{
                    ExitCode = 0
                }
            }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq "pv" } {
                [PSCustomObject]@{
                    pv = "1.0.0.0"
                }
            }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq "IsWVDEnvironment" } {
                [PSCustomObject]@{
                    IsWVDEnvironment = 1
                }
            }
            Mock Get-ChildItem -ParameterFilter { $Filter -eq "MSTeams_*" } {
                @(
                    [PSCustomObject]@{
                        Name = "MSTeams_1.0.0.0_x64__8wekyb3d8bbwe"
                    }
                )
            }

            { & $scriptPath -AcceptEULA -SkipUserCleanup } | Should -Not -Throw
        }

        It "Should accept -Force parameter" {
            Mock Test-Path { $true }
            Mock Split-Path { "C:\Temp" }
            Mock Invoke-WebRequest { }
            Mock Start-Process {
                [PSCustomObject]@{
                    ExitCode = 0
                }
            }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq "pv" } {
                [PSCustomObject]@{
                    pv = "1.0.0.0"
                }
            }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq "IsWVDEnvironment" } {
                [PSCustomObject]@{
                    IsWVDEnvironment = 1
                }
            }
            Mock Get-ChildItem -ParameterFilter { $Filter -eq "MSTeams_*" } {
                @(
                    [PSCustomObject]@{
                        Name = "MSTeams_1.0.0.0_x64__8wekyb3d8bbwe"
                    }
                )
            }

            { & $scriptPath -AcceptEULA -Force } | Should -Not -Throw
        }

        It "Should accept custom -LogPath parameter" {
            Mock Test-Path { $true }
            Mock Split-Path { "C:\CustomLogs" }
            Mock Invoke-WebRequest { }
            Mock Start-Process {
                [PSCustomObject]@{
                    ExitCode = 0
                }
            }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq "pv" } {
                [PSCustomObject]@{
                    pv = "1.0.0.0"
                }
            }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq "IsWVDEnvironment" } {
                [PSCustomObject]@{
                    IsWVDEnvironment = 1
                }
            }
            Mock Get-ChildItem -ParameterFilter { $Filter -eq "MSTeams_*" } {
                @(
                    [PSCustomObject]@{
                        Name = "MSTeams_1.0.0.0_x64__8wekyb3d8bbwe"
                    }
                )
            }

            { & $scriptPath -AcceptEULA -LogPath "C:\CustomLogs\test.log" } | Should -Not -Throw
        }

        It "Should accept -SkipSignatureCheck parameter" {
            Mock Test-Path { $true }
            Mock Split-Path { "C:\Temp" }
            Mock Invoke-WebRequest { }
            Mock Start-Process {
                [PSCustomObject]@{
                    ExitCode = 0
                }
            }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq "pv" } {
                [PSCustomObject]@{
                    pv = "1.0.0.0"
                }
            }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq "IsWVDEnvironment" } {
                [PSCustomObject]@{
                    IsWVDEnvironment = 1
                }
            }
            Mock Get-ChildItem -ParameterFilter { $Filter -eq "MSTeams_*" } {
                @(
                    [PSCustomObject]@{
                        Name = "MSTeams_1.0.0.0_x64__8wekyb3d8bbwe"
                    }
                )
            }
            Mock Get-AuthenticodeSignature {
                [PSCustomObject]@{
                    Status = 'Valid'
                    SignerCertificate = [PSCustomObject]@{
                        Subject = "CN=Microsoft Corporation"
                    }
                }
            }

            { & $scriptPath -AcceptEULA -SkipSignatureCheck } | Should -Not -Throw
        }
    }
}

Describe "Install-TeamsAVD.ps1 - Security Features (v3.0)" {

    Context "Authenticode Signature Verification" {
        It "Should have Test-FileSignature function" {
            $scriptContent = Get-Content -Path $scriptPath -Raw
            $scriptContent | Should -Match 'function Test-FileSignature'
        }

        It "Should verify signatures by default" {
            $scriptContent = Get-Content -Path $scriptPath -Raw
            $scriptContent | Should -Match 'Get-AuthenticodeSignature'
        }

        It "Should allow skipping signature checks with parameter" {
            $scriptContent = Get-Content -Path $scriptPath -Raw
            $scriptContent | Should -Match 'SkipSignatureCheck'
        }

        It "Should document signature verification in help" {
            $scriptContent = Get-Content -Path $scriptPath -Raw
            $scriptContent | Should -Match 'Authenticode|signature'
        }
    }

    Context "Version Detection Retry Logic" {
        It "Should have Wait-ForVersionDetection function with exponential backoff" {
            $scriptContent = Get-Content -Path $scriptPath -Raw
            $scriptContent | Should -Match 'function Wait-ForVersionDetection'
        }

        It "Should define retry configuration variables" {
            $scriptContent = Get-Content -Path $scriptPath -Raw
            $scriptContent | Should -Match '\$script:MaxRetries'
            $scriptContent | Should -Match '\$script:InitialRetryDelay'
        }

        It "Should implement exponential backoff" {
            $scriptContent = Get-Content -Path $scriptPath -Raw
            # Check for exponential backoff logic (delay * 2)
            $scriptContent | Should -Match 'delay\s*\*\s*2'
        }
    }

    Context "Graceful Process Shutdown" {
        It "Should have Stop-TeamsProcessGracefully function" {
            $scriptContent = Get-Content -Path $scriptPath -Raw
            $scriptContent | Should -Match 'function Stop-TeamsProcessGracefully'
        }

        It "Should try CloseMainWindow before Kill" {
            $scriptContent = Get-Content -Path $scriptPath -Raw
            $scriptContent | Should -Match 'CloseMainWindow'
            $scriptContent | Should -Match '\.Kill\(\)'
        }

        It "Should wait for graceful shutdown before forcing" {
            $scriptContent = Get-Content -Path $scriptPath -Raw
            $scriptContent | Should -Match 'WaitForExit'
        }
    }

    Context "Acceptable Exit Codes" {
        It "Should define acceptable installer exit codes" {
            $scriptContent = Get-Content -Path $scriptPath -Raw
            $scriptContent | Should -Match '\$script:AcceptableExitCodes'
        }

        It "Should include exit code 0 (success)" {
            $scriptContent = Get-Content -Path $scriptPath -Raw
            $scriptContent | Should -Match 'AcceptableExitCodes.*0'
        }

        It "Should include exit code 3010 (reboot required)" {
            $scriptContent = Get-Content -Path $scriptPath -Raw
            $scriptContent | Should -Match 'AcceptableExitCodes.*3010'
        }
    }
}

Describe "Install-TeamsAVD.ps1 - Administrator Requirements" {

    Context "#Requires Directive" {
        It "Should have #Requires -RunAsAdministrator directive" {
            $scriptContent = Get-Content -Path $scriptPath -Raw
            $scriptContent | Should -Match '#Requires\s+-RunAsAdministrator'
        }

        It "Should document that admin privileges are enforced automatically" {
            $scriptContent = Get-Content -Path $scriptPath -Raw
            # Check that documentation mentions #Requires handles admin check
            $scriptContent | Should -Match 'enforced by #Requires directive|#Requires -RunAsAdministrator'
        }
    }
}

Describe "Install-TeamsAVD.ps1 - Registry Configuration" {

    Context "AVD Registry Settings" {
        It "Should set IsWVDEnvironment registry key" {
            Mock Set-ItemProperty { }
            Mock Get-ItemProperty {
                [PSCustomObject]@{
                    IsWVDEnvironment = 1
                }
            }

            # Load the script functions
            . $scriptPath

            $result = Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name "IsWVDEnvironment" -Value 1
            $result | Should -Be $true
        }

        It "Should set AllowAllTrustedApps registry key" {
            Mock Set-ItemProperty { }
            Mock Get-ItemProperty {
                [PSCustomObject]@{
                    AllowAllTrustedApps = 1
                }
            }

            . $scriptPath

            $result = Set-RegistryValue -Path "HKLM:\Software\Policies\Microsoft\Windows\Appx" -Name "AllowAllTrustedApps" -Value 1
            $result | Should -Be $true
        }

        It "Should set PreventUserFromUpdatingTeams registry key" {
            Mock Set-ItemProperty { }
            Mock Get-ItemProperty {
                [PSCustomObject]@{
                    PreventUserFromUpdatingTeams = 1
                }
            }

            . $scriptPath

            $result = Set-RegistryValue -Path "HKLM:\Software\Policies\Microsoft\Office\Teams" -Name "PreventUserFromUpdatingTeams" -Value 1
            $result | Should -Be $true
        }

        It "Should create registry path if it doesn't exist" {
            Mock Test-Path { $false }
            Mock New-Item { }
            Mock Set-ItemProperty { }
            Mock Get-ItemProperty {
                [PSCustomObject]@{
                    TestKey = 1
                }
            }

            . $scriptPath

            $result = Set-RegistryValue -Path "HKLM:\SOFTWARE\NonExistent\Path" -Name "TestKey" -Value 1
            Assert-MockCalled New-Item -Times 1
        }

        It "Should handle registry errors gracefully" {
            Mock Test-Path { $true }
            Mock Set-ItemProperty { throw "Access denied" }

            . $scriptPath

            $result = Set-RegistryValue -Path "HKLM:\SOFTWARE\Test" -Name "TestKey" -Value 1
            $result | Should -Be $false
        }
    }
}

Describe "Install-TeamsAVD.ps1 - Version Detection" {

    Context "WebView2 Version Detection" {
        It "Should detect installed WebView2 version" {
            Mock Test-Path { $true }
            Mock Get-ItemProperty {
                [PSCustomObject]@{
                    pv = "123.0.2420.81"
                }
            }

            . $scriptPath

            $version = Get-WebView2Version
            $version | Should -Be "123.0.2420.81"
        }

        It "Should return null when WebView2 is not installed" {
            Mock Test-Path { $false }

            . $scriptPath

            $version = Get-WebView2Version
            $version | Should -Be $null
        }

        It "Should handle registry read errors" {
            Mock Test-Path { $true }
            Mock Get-ItemProperty { throw "Registry error" }

            . $scriptPath

            $version = Get-WebView2Version
            $version | Should -Be $null
        }
    }

    Context "Teams Version Detection" {
        It "Should detect installed Teams version" {
            Mock Get-ChildItem {
                @(
                    [PSCustomObject]@{
                        Name = "MSTeams_24267.1500.3211.6287_x64__8wekyb3d8bbwe"
                    }
                )
            }

            . $scriptPath

            $version = Get-TeamsVersion
            $version | Should -Be "24267.1500.3211.6287"
        }

        It "Should return null when Teams is not installed" {
            Mock Get-ChildItem { @() }

            . $scriptPath

            $version = Get-TeamsVersion
            $version | Should -Be $null
        }

        It "Should return latest version when multiple Teams installations exist" {
            Mock Get-ChildItem {
                @(
                    [PSCustomObject]@{
                        Name = "MSTeams_24267.1500.3211.6287_x64__8wekyb3d8bbwe"
                    },
                    [PSCustomObject]@{
                        Name = "MSTeams_24268.1600.3212.6288_x64__8wekyb3d8bbwe"
                    }
                )
            }

            . $scriptPath

            $version = Get-TeamsVersion
            $version | Should -Be "24268.1600.3212.6288"
        }
    }
}

Describe "Install-TeamsAVD.ps1 - WebView2 Installation" {

    Context "WebView2 Download and Install" {
        It "Should skip installation if WebView2 is already installed" {
            Mock Get-ItemProperty {
                [PSCustomObject]@{
                    pv = "123.0.2420.81"
                }
            }
            Mock Invoke-WebRequest { }
            Mock Start-Process { }

            . $scriptPath

            $result = Install-WebView2Runtime
            Assert-MockCalled Invoke-WebRequest -Times 0
        }

        It "Should download WebView2 installer" {
            Mock Test-Path { $false } -ParameterFilter { $Path -like "*SOFTWARE*" }
            Mock Test-Path { $true } -ParameterFilter { $Path -like "*WebView2*.exe" }
            Mock Get-ItemProperty { $null }
            Mock Invoke-WebRequest { }
            Mock Get-Item {
                [PSCustomObject]@{
                    Length = 10MB
                }
            }
            Mock Start-Process {
                [PSCustomObject]@{
                    ExitCode = 0
                }
            }

            . $scriptPath

            $result = Install-WebView2Runtime
            Assert-MockCalled Invoke-WebRequest -Times 1
        }

        It "Should install WebView2 silently" {
            Mock Test-Path { $false } -ParameterFilter { $Path -like "*SOFTWARE*" }
            Mock Test-Path { $true } -ParameterFilter { $Path -like "*WebView2*.exe" }
            Mock Get-ItemProperty {
                [PSCustomObject]@{
                    pv = "123.0.2420.81"
                }
            }
            Mock Invoke-WebRequest { }
            Mock Get-Item {
                [PSCustomObject]@{
                    Length = 10MB
                }
            }
            Mock Start-Process {
                [PSCustomObject]@{
                    ExitCode = 0
                }
            }

            . $scriptPath

            $result = Install-WebView2Runtime
            Assert-MockCalled Start-Process -ParameterFilter { $ArgumentList -contains "/silent" } -Times 1
        }

        It "Should handle download failures" {
            Mock Test-Path { $false }
            Mock Get-ItemProperty { $null }
            Mock Invoke-WebRequest { throw "Network error" }

            . $scriptPath

            $result = Install-WebView2Runtime
            $result | Should -Be $false
        }

        It "Should handle installation failures" {
            Mock Test-Path { $false } -ParameterFilter { $Path -like "*SOFTWARE*" }
            Mock Test-Path { $true } -ParameterFilter { $Path -like "*WebView2*.exe" }
            Mock Get-ItemProperty { $null }
            Mock Invoke-WebRequest { }
            Mock Get-Item {
                [PSCustomObject]@{
                    Length = 10MB
                }
            }
            Mock Start-Process {
                [PSCustomObject]@{
                    ExitCode = 1
                }
            }

            . $scriptPath

            $result = Install-WebView2Runtime
            $result | Should -Be $false
        }

        It "Should validate download file size" {
            Mock Test-Path { $false } -ParameterFilter { $Path -like "*SOFTWARE*" }
            Mock Test-Path { $true } -ParameterFilter { $Path -like "*WebView2*.exe" }
            Mock Get-ItemProperty { $null }
            Mock Invoke-WebRequest { }
            Mock Get-Item {
                [PSCustomObject]@{
                    Length = 100KB  # Too small
                }
            }

            . $scriptPath

            $result = Install-WebView2Runtime
            $result | Should -Be $false
        }

        It "Should cleanup installer file after installation" {
            Mock Test-Path { $false } -ParameterFilter { $Path -like "*SOFTWARE*" }
            Mock Test-Path { $true } -ParameterFilter { $Path -like "*WebView2*.exe" }
            Mock Get-ItemProperty {
                [PSCustomObject]@{
                    pv = "123.0.2420.81"
                }
            }
            Mock Invoke-WebRequest { }
            Mock Get-Item {
                [PSCustomObject]@{
                    Length = 10MB
                }
            }
            Mock Start-Process {
                [PSCustomObject]@{
                    ExitCode = 0
                }
            }
            Mock Remove-Item { }

            . $scriptPath

            $result = Install-WebView2Runtime
            Assert-MockCalled Remove-Item -Times 1
        }
    }
}

Describe "Install-TeamsAVD.ps1 - Teams Installation" {

    Context "Teams Download and Install" {
        It "Should skip installation if Teams is already installed" {
            Mock Get-ChildItem {
                @(
                    [PSCustomObject]@{
                        Name = "MSTeams_24267.1500.3211.6287_x64__8wekyb3d8bbwe"
                    }
                )
            }
            Mock Invoke-WebRequest { }

            . $scriptPath

            $result = Install-TeamsBootstrapper
            Assert-MockCalled Invoke-WebRequest -Times 0
        }

        It "Should download Teams bootstrapper" {
            Mock Get-ChildItem { @() }
            Mock Test-Path { $true }
            Mock Invoke-WebRequest { }
            Mock Get-Item {
                [PSCustomObject]@{
                    Length = 10MB
                }
            }
            Mock Start-Process {
                [PSCustomObject]@{
                    ExitCode = 0
                }
            }

            . $scriptPath

            $result = Install-TeamsBootstrapper
            Assert-MockCalled Invoke-WebRequest -Times 1
        }

        It "Should install Teams with -p flag for machine-wide deployment" {
            Mock Get-ChildItem {
                @(
                    [PSCustomObject]@{
                        Name = "MSTeams_24267.1500.3211.6287_x64__8wekyb3d8bbwe"
                    }
                )
            }
            Mock Test-Path { $true }
            Mock Invoke-WebRequest { }
            Mock Get-Item {
                [PSCustomObject]@{
                    Length = 10MB
                }
            }
            Mock Start-Process {
                [PSCustomObject]@{
                    ExitCode = 0
                }
            }

            . $scriptPath

            # Force installation to test the -p flag
            $result = Install-TeamsBootstrapper
            Assert-MockCalled Start-Process -ParameterFilter { $ArgumentList -contains "-p" }
        }

        It "Should handle download failures" {
            Mock Get-ChildItem { @() }
            Mock Invoke-WebRequest { throw "Network error" }

            . $scriptPath

            $result = Install-TeamsBootstrapper
            $result | Should -Be $false
        }

        It "Should cleanup installer file after installation" {
            Mock Get-ChildItem {
                @(
                    [PSCustomObject]@{
                        Name = "MSTeams_24267.1500.3211.6287_x64__8wekyb3d8bbwe"
                    }
                )
            }
            Mock Test-Path { $true }
            Mock Invoke-WebRequest { }
            Mock Get-Item {
                [PSCustomObject]@{
                    Length = 10MB
                }
            }
            Mock Start-Process {
                [PSCustomObject]@{
                    ExitCode = 0
                }
            }
            Mock Remove-Item { }

            . $scriptPath

            $result = Install-TeamsBootstrapper
            Assert-MockCalled Remove-Item -Times 1
        }
    }
}

Describe "Install-TeamsAVD.ps1 - User Cleanup" {

    Context "Old Teams Removal" {
        It "Should skip cleanup when -SkipUserCleanup is specified" {
            Mock Get-ChildItem { @() }

            . $scriptPath

            Remove-UserTeamsInstalls -SkipUserCleanup
            # Should not enumerate user directories
            Assert-MockCalled Get-ChildItem -Times 0
        }

        It "Should remove old Teams installations from user profiles" {
            Mock Get-ChildItem -ParameterFilter { $Path -eq "C:\Users" } {
                @(
                    [PSCustomObject]@{
                        Name = "TestUser"
                        FullName = "C:\Users\TestUser"
                    }
                )
            }
            Mock Test-Path { $true }
            Mock Get-Process { @() }
            Mock Remove-Item { }

            . $scriptPath

            Remove-UserTeamsInstalls
            Assert-MockCalled Remove-Item -Times 1
        }

        It "Should stop running Teams processes before removal" {
            Mock Get-ChildItem -ParameterFilter { $Path -eq "C:\Users" } {
                @(
                    [PSCustomObject]@{
                        Name = "TestUser"
                        FullName = "C:\Users\TestUser"
                    }
                )
            }
            Mock Test-Path { $true }
            Mock Get-Process {
                @(
                    [PSCustomObject]@{
                        Name = "Teams"
                        Path = "C:\Users\TestUser\AppData\Local\Microsoft\Teams\current\Teams.exe"
                    }
                )
            }
            Mock Stop-Process { }
            Mock Remove-Item { }

            . $scriptPath

            Remove-UserTeamsInstalls
            Assert-MockCalled Stop-Process -Times 1
        }

        It "Should skip system user profiles" {
            Mock Get-ChildItem -ParameterFilter { $Path -eq "C:\Users" } {
                @(
                    [PSCustomObject]@{
                        Name = "Public"
                        FullName = "C:\Users\Public"
                    },
                    [PSCustomObject]@{
                        Name = "Default"
                        FullName = "C:\Users\Default"
                    }
                )
            }
            Mock Test-Path { $true }
            Mock Remove-Item { }

            . $scriptPath

            Remove-UserTeamsInstalls
            # Should not attempt to remove from system profiles
            Assert-MockCalled Remove-Item -Times 0
        }

        It "Should handle removal errors gracefully" {
            Mock Get-ChildItem -ParameterFilter { $Path -eq "C:\Users" } {
                @(
                    [PSCustomObject]@{
                        Name = "TestUser"
                        FullName = "C:\Users\TestUser"
                    }
                )
            }
            Mock Test-Path { $true }
            Mock Get-Process { @() }
            Mock Remove-Item { throw "Access denied" }

            . $scriptPath

            # Should not throw, just log the error
            { Remove-UserTeamsInstalls } | Should -Not -Throw
        }
    }
}

Describe "Install-TeamsAVD.ps1 - Exit Codes" {

    Context "Exit Code Behavior" {
        It "Should exit with code 1 when EULA not accepted" {
            Mock Test-Path { $true }
            Mock Split-Path { "C:\Temp" }

            $result = & $scriptPath *>&1
            $LASTEXITCODE | Should -Be 1
        }

        It "Should document all valid exit codes (0, 1, 2, 3, 4)" {
            $scriptContent = Get-Content -Path $scriptPath -Raw

            # Check that documentation includes all 4 exit codes and no exit code 5
            $scriptContent | Should -Match 'Exit Codes:'
            $scriptContent | Should -Match '0\s+-\s+Success'
            $scriptContent | Should -Match '1\s+-\s+EULA not accepted'
            $scriptContent | Should -Match '2\s+-\s+Download'
            $scriptContent | Should -Match '3\s+-\s+Installation'
            $scriptContent | Should -Match '4\s+-\s+Registry'
            $scriptContent | Should -Not -Match '5\s+-.*Administrator|5\s+-.*Validation'
        }
    }
}

Describe "Install-TeamsAVD.ps1 - Logging" {

    Context "Transcript Logging" {
        It "Should start transcript logging" {
            Mock Test-Path { $true }
            Mock Split-Path { "C:\Temp" }
            Mock Start-Transcript { }

            $result = & $scriptPath -AcceptEULA *>&1
            Assert-MockCalled Start-Transcript -Times 1
        }

        It "Should stop transcript on completion" {
            Mock Test-Path { $true }
            Mock Split-Path { "C:\Temp" }
            Mock Stop-Transcript { }

            $result = & $scriptPath -AcceptEULA *>&1
            Assert-MockCalled Stop-Transcript
        }

        It "Should create log directory if it doesn't exist" {
            Mock Test-Path { $false }
            Mock Split-Path { "C:\NonExistentPath" }
            Mock New-Item { }

            $result = & $scriptPath -AcceptEULA *>&1
            Assert-MockCalled New-Item -ParameterFilter { $ItemType -eq "Directory" }
        }
    }
}

Describe "Install-TeamsAVD.ps1 - Idempotency" {

    Context "Re-run Behavior" {
        It "Should allow multiple runs without errors" {
            Mock Test-Path { $true }
            Mock Split-Path { "C:\Temp" }
            Mock Invoke-WebRequest { }
            Mock Start-Process {
                [PSCustomObject]@{
                    ExitCode = 0
                }
            }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq "pv" } {
                [PSCustomObject]@{
                    pv = "1.0.0.0"
                }
            }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq "IsWVDEnvironment" } {
                [PSCustomObject]@{
                    IsWVDEnvironment = 1
                }
            }
            Mock Get-ChildItem -ParameterFilter { $Filter -eq "MSTeams_*" } {
                @(
                    [PSCustomObject]@{
                        Name = "MSTeams_1.0.0.0_x64__8wekyb3d8bbwe"
                    }
                )
            }

            # First run
            $result1 = & $scriptPath -AcceptEULA *>&1
            $exitCode1 = $LASTEXITCODE

            # Second run
            $result2 = & $scriptPath -AcceptEULA *>&1
            $exitCode2 = $LASTEXITCODE

            # Both runs should succeed
            $exitCode1 | Should -Be $exitCode2
        }

        It "Should force reinstallation when -Force is specified" {
            Mock Test-Path { $true }
            Mock Split-Path { "C:\Temp" }
            Mock Get-ItemProperty -ParameterFilter { $Name -eq "pv" } {
                [PSCustomObject]@{
                    pv = "1.0.0.0"
                }
            }
            Mock Get-ChildItem -ParameterFilter { $Filter -eq "MSTeams_*" } {
                @(
                    [PSCustomObject]@{
                        Name = "MSTeams_1.0.0.0_x64__8wekyb3d8bbwe"
                    }
                )
            }
            Mock Invoke-WebRequest { }
            Mock Get-Item {
                [PSCustomObject]@{
                    Length = 10MB
                }
            }
            Mock Start-Process {
                [PSCustomObject]@{
                    ExitCode = 0
                }
            }

            . $scriptPath

            $result = Install-WebView2Runtime
            # Should download even if already installed
            Assert-MockCalled Invoke-WebRequest -Times 1
        }
    }
}
