#Requires -Modules Pester

Describe "Update-M365Apps" {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/collaboration/microsoft365/office-apps/ ->
        # script is four levels up + across into scripts/.
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/collaboration/microsoft365/office-apps/Update-M365Apps.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Keep any stray .NET file writes (XmlDocument.Save) inside Pester's temp drive.
        Push-Location $TestDrive

        $channelGuidUrl = 'http://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60'

        # ---- Offline stubs + mocks for every external command ----
        # Pre-defined stub: gives the Get-ChildItem mock the dynamic -File
        # parameter (FileSystem provider) that Clear-UpdateFiles relies on.
        function Get-ChildItem {
            [CmdletBinding()]
            param(
                [string]$Path,
                [string]$Filter,
                [switch]$Recurse,
                [switch]$Force,
                [switch]$File,
                [switch]$Directory
            )
        }

        Mock Test-Path { $true }
        # Join-Path cannot resolve Windows drive-qualified paths on Linux.
        Mock Join-Path { param($Path, $ChildPath) "$Path/$ChildPath" }
        Mock Get-ChildItem { @() }
        Mock Remove-Item { }
        Mock New-Item { }
        Mock Add-Content { }
        Mock Start-Sleep { }
        Mock Read-Host { '' }   # empty answer accepts defaults (declines N-default prompts)
        Mock Invoke-WebRequest { [pscustomobject]@{ StatusCode = 200 } }
        Mock Invoke-RestMethod {
            @([pscustomobject]@{ channelId = 'Current'; channel = 'Current'; latestVersion = '16.0.17999.20000' })
        }
        # Only intercept the ODT config read; let -Raw reads (metadata checks) through.
        Mock Get-Content {
            [xml]('<Configuration><Add OfficeClientEdition="64" ' +
                'SourcePath="C:\AVD\M365Apps\OfficeUpdates" /><RemoveMSI /></Configuration>')
        } -ParameterFilter { -not $Raw }
        Mock Get-ItemProperty {
            [pscustomobject]@{
                VersionToReport   = '16.0.17999.20000'
                Platform          = 'x64'
                UpdateChannel     = $channelGuidUrl
                CDNBaseUrl        = $channelGuidUrl
                ProductReleaseIds = 'O365ProPlusRetail'
                InstallationPath  = 'C:\Program Files\Microsoft Office'
            }
        }
        # Native setup.exe is reachable ONLY through the Invoke-ODTSetup wrapper -> mock the WRAPPER.
        Mock Invoke-ODTSetup { 0 }

        # Pester 5.7 gives each phase a fresh script scope: $script:Config set during
        # dot-sourcing is invisible to Main once an It runs. Re-seed it from inside each
        # behavioral test so Main's $script: lookups resolve in the active script scope.
        function Init-TestScriptState {
            $script:Config = @{
                ODTPath          = 'C:\AVD\M365Apps\setup.exe'
                InstallXMLPath   = 'C:\AVD\M365Apps\install.xml'
                DownloadXMLPath  = 'C:\AVD\M365Apps\download.xml'
                UpdatesPath      = 'C:\AVD\M365Apps\OfficeUpdates'
                LogPath          = 'C:\AVD\M365Apps\Logs'
                MaxLogAge        = 30
                Channel          = 'Current'
                OfficeVersionURL = 'https://clients.config.office.net/releases/v1.0/OfficeReleases'
            }
            $script:LogFile = $null
        }
    }

    AfterAll {
        Pop-Location
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date 2026-08-23 in .NOTES" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match 'Version\s*:\s*1\.0\.0'
            $raw | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Matches .NOTES File Name to the disk filename and declares the prerequisite" {
            $raw = Get-Content -Raw $scriptPath
            $raw | Should -Match 'File Name\s*:\s*Update-M365Apps\.ps1'
            $raw | Should -Match 'Prerequisite\s*:\s*PowerShell 7\.0'
        }

        It "Has one .PARAMETER section per declared parameter (both zero: no param block)" {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $declared = @($ast.ParamBlock.Parameters)
            $helpParams = [regex]::Matches((Get-Content -Raw $scriptPath), '(?m)^\s*\.PARAMETER\s+(\S+)')
            $helpParams.Count | Should -Be $declared.Count
            $helpParams.Count | Should -Be 0
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

        It "Invokes the native setup.exe ONLY through the Invoke-ODTSetup wrapper" {
            $raw = Get-Content -Raw $scriptPath
            ([regex]::Matches($raw, 'Start-Process')).Count | Should -Be 1
            $split = [regex]::Split($raw, 'function Invoke-ODTSetup')
            $split.Count | Should -Be 2
            $split[0] | Should -Not -Match 'Start-Process'
            $split[1] | Should -Match 'Start-Process'
            $split[1] | Should -Match 'LASTEXITCODE'
            $raw | Should -Not -Match '&\s*(winget|setup|reg)(\.exe)?\b'
        }
    }

    Context "Behavior" {
        It "Is idempotent on a converged system: up-to-date install returns 0 with no deployment calls" {
            Init-TestScriptState
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'up to date'
            Should -Invoke Invoke-ODTSetup -Times 0 -Exactly -Because "no update is available"
        }

        It "Detects an available update but deploys nothing when the user declines the download" {
            Init-TestScriptState
            Mock Get-ItemProperty {
                [pscustomobject]@{
                    VersionToReport   = '16.0.16000.20000'
                    Platform          = 'x64'
                    UpdateChannel     = $channelGuidUrl
                    CDNBaseUrl        = $channelGuidUrl
                    ProductReleaseIds = 'O365ProPlusRetail'
                    InstallationPath  = 'C:\Program Files\Microsoft Office'
                }
            }
            # Get-UserConfirmation invokes bare Read-Host (no -Prompt): answer by
            # call order instead. Call 1 = channel prompt (default N), call 2 = download prompt.
            $readHostAnswers = @{ Calls = 0 }
            Mock Read-Host {
                $readHostAnswers.Calls++
                if ($readHostAnswers.Calls -eq 2) { 'n' } else { '' }
            }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match 'Update available!'
            $text | Should -Match 'Download cancelled by user\.'
            Should -Invoke Invoke-ODTSetup -Times 0 -Exactly
        }

        It "Runs the full update flow through the ODT wrapper: download, install, verify (2 wrapper calls)" {
            Init-TestScriptState
            $registryState = @{ Calls = 0 }
            Mock Get-ItemProperty {
                $registryState.Calls++
                $ver = if ($registryState.Calls -ge 2) { '16.0.17999.20000' } else { '16.0.16000.20000' }
                [pscustomobject]@{
                    VersionToReport   = $ver
                    Platform          = 'x64'
                    UpdateChannel     = $channelGuidUrl
                    CDNBaseUrl        = $channelGuidUrl
                    ProductReleaseIds = 'O365ProPlusRetail'
                    InstallationPath  = 'C:\Program Files\Microsoft Office'
                }
            }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Successfully updated to version 16\.0\.17999\.20000'
            Should -Invoke Invoke-ODTSetup -Times 2 -Exactly -Because "one download and one /configure install"
        }

        It "Returns 1 with [-] output when the Office Deployment Tool is missing" {
            Init-TestScriptState
            Mock Test-Path { $false }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\].*Prerequisites check failed'
        }
    }
}
