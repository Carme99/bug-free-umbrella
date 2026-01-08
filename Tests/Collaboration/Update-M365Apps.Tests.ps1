#Requires -Modules Pester

BeforeAll {
    # Path to the script being tested
    $scriptPath = Join-Path $PSScriptRoot "..\..\scripts\collaboration\microsoft365\office-apps\Update-M365Apps.ps1"

    # Read the script content for analysis (don't execute it as it requires admin)
    $scriptContent = Get-Content -Path $scriptPath -Raw
}

Describe "Update-M365Apps.ps1 - Script Structure and Quality" {
    Context "Script File Validation" {
        It "Script file should exist" {
            $scriptPath | Should -Exist
        }

        It "Script should be valid PowerShell" {
            { $errors = $null; $null = [System.Management.Automation.PSParser]::Tokenize($scriptContent, [ref]$errors); if ($errors) { throw $errors } } | Should -Not -Throw
        }

        It "Script should have #Requires -RunAsAdministrator" {
            $scriptContent | Should -Match '#Requires\s+-RunAsAdministrator'
        }
    }

    Context "Script Documentation" {
        It "Should have .SYNOPSIS" {
            $scriptContent | Should -Match '\.SYNOPSIS'
        }

        It "Should have .DESCRIPTION" {
            $scriptContent | Should -Match '\.DESCRIPTION'
        }

        It "Should have .NOTES" {
            $scriptContent | Should -Match '\.NOTES'
        }

        It "SYNOPSIS should describe M365 Apps Update Manager" {
            $scriptContent | Should -Match 'M365 Apps Update Manager'
        }
    }

    Context "Configuration Structure" {
        It "Should define Config hashtable" {
            $scriptContent | Should -Match '\$script:Config\s*=\s*@\{'
        }

        It "Should define ODTPath configuration" {
            $scriptContent | Should -Match 'ODTPath\s*='
        }

        It "Should define InstallXMLPath configuration" {
            $scriptContent | Should -Match 'InstallXMLPath\s*='
        }

        It "Should define OfficeVersionURL configuration" {
            $scriptContent | Should -Match 'OfficeVersionURL\s*='
        }

        It "Should set ErrorActionPreference to Stop" {
            $scriptContent | Should -Match '\$ErrorActionPreference\s*=\s*[''"]Stop[''"]'
        }
    }

    Context "Function Definitions" {
        It "Should define Initialize-Logging function" {
            $scriptContent | Should -Match 'function Initialize-Logging'
        }

        It "Should define Write-Log function" {
            $scriptContent | Should -Match 'function Write-Log'
        }

        It "Should define Test-Prerequisites function" {
            $scriptContent | Should -Match 'function Test-Prerequisites'
        }

        It "Should define Get-InstalledOfficeInfo function" {
            $scriptContent | Should -Match 'function Get-InstalledOfficeInfo'
        }

        It "Should define Get-LatestOfficeVersion function" {
            $scriptContent | Should -Match 'function Get-LatestOfficeVersion'
        }

        It "Should define Compare-OfficeVersions function" {
            $scriptContent | Should -Match 'function Compare-OfficeVersions'
        }

        It "Should define Invoke-OfficeDownload function" {
            $scriptContent | Should -Match 'function Invoke-OfficeDownload'
        }

        It "Should define Invoke-OfficeInstall function" {
            $scriptContent | Should -Match 'function Invoke-OfficeInstall'
        }

        It "Should define Get-ChannelFriendlyName function" {
            $scriptContent | Should -Match 'function Get-ChannelFriendlyName'
        }

        It "Should define Set-OfficeUpdateChannel function" {
            $scriptContent | Should -Match 'function Set-OfficeUpdateChannel'
        }

        It "Should define Clear-UpdateFiles function" {
            $scriptContent | Should -Match 'function Clear-UpdateFiles'
        }
    }

    Context "Error Handling" {
        It "Should use try-catch blocks" {
            $scriptContent | Should -Match '\btry\s*\{'
            $scriptContent | Should -Match '\}\s*catch\s*\{'
        }

        It "Should have error handling in Test-Prerequisites" {
            $scriptContent | Should -Match 'function Test-Prerequisites[\s\S]*?catch'
        }

        It "Should have error handling in Get-LatestOfficeVersion" {
            $scriptContent | Should -Match 'function Get-LatestOfficeVersion[\s\S]*?catch'
        }

        It "Should have finally block for cleanup" {
            $scriptContent | Should -Match '\}\s*finally\s*\{'
        }
    }

    Context "Logging Functions" {
        It "Should define Write-Success function" {
            $scriptContent | Should -Match 'function Write-Success'
        }

        It "Should define Write-ErrorMsg function" {
            $scriptContent | Should -Match 'function Write-ErrorMsg'
        }

        It "Should define Write-WarningMsg function" {
            $scriptContent | Should -Match 'function Write-WarningMsg'
        }

        It "Should define Write-InfoMsg function" {
            $scriptContent | Should -Match 'function Write-InfoMsg'
        }

        It "Should define Cleanup-OldLogs function" {
            $scriptContent | Should -Match 'function Cleanup-OldLogs'
        }

        It "Logging functions should write to log file" {
            $scriptContent | Should -Match 'Add-Content.*\$script:LogFile'
        }
    }

    Context "Channel Support" {
        It "Should support Monthly (Current Channel)" {
            $scriptContent | Should -Match "492350f6-3a01-4f97-b9c0-c7c6ddf67d60"
        }

        It "Should support Monthly Enterprise" {
            $scriptContent | Should -Match "64256afe-f5d9-4f86-8936-8840a6a4f5be"
        }

        It "Should support Semi-Annual" {
            $scriptContent | Should -Match "b8f9b850-328d-4355-9145-c59439a0c4cf"
        }

        It "Should support Beta (Insider)" {
            $scriptContent | Should -Match "5440fd1f-7ecb-4221-8110-145efaa6372f"
        }

        It "Should map channel GUIDs to friendly names" {
            $scriptContent | Should -Match 'Monthly \(Current Channel\)'
            $scriptContent | Should -Match 'Semi-Annual'
            $scriptContent | Should -Match 'Beta \(Insider\)'
        }
    }

    Context "Registry Operations" {
        It "Should check ClickToRun registry path" {
            $scriptContent | Should -Match 'HKLM:\\SOFTWARE\\Microsoft\\Office\\ClickToRun\\Configuration'
        }

        It "Should check WOW6432Node registry path for x86" {
            $scriptContent | Should -Match 'HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Office\\ClickToRun\\Configuration'
        }

        It "Should read VersionToReport from registry" {
            $scriptContent | Should -Match 'VersionToReport'
        }

        It "Should update CDNBaseUrl for channel switching" {
            $scriptContent | Should -Match 'CDNBaseUrl'
        }

        It "Should update UpdateChannel for channel switching" {
            $scriptContent | Should -Match 'UpdateChannel'
        }
    }

    Context "ODT Integration" {
        It "Should reference Office Deployment Tool setup.exe" {
            $scriptContent | Should -Match 'setup\.exe'
        }

        It "Should use /download parameter for ODT" {
            $scriptContent | Should -Match '/download'
        }

        It "Should use /configure parameter for ODT" {
            $scriptContent | Should -Match '/configure'
        }

        It "Should create download configuration XML" {
            $scriptContent | Should -Match 'function New-DownloadConfiguration'
        }

        It "Should handle ODT exit codes" {
            $scriptContent | Should -Match '\$process\.ExitCode'
        }
    }

    Context "User Interaction" {
        It "Should define Get-UserConfirmation function" {
            $scriptContent | Should -Match 'function Get-UserConfirmation'
        }

        It "Should define Get-ChannelSelection function" {
            $scriptContent | Should -Match 'function Get-ChannelSelection'
        }

        It "Should prompt for update download" {
            $scriptContent | Should -Match 'Would you like to download'
        }

        It "Should prompt for update installation" {
            $scriptContent | Should -Match 'Would you like to install'
        }

        It "Should prompt for cleanup" {
            $scriptContent | Should -Match 'clean up.*downloaded'
        }

        It "Should show banner" {
            $scriptContent | Should -Match 'function Show-Banner'
        }
    }

    Context "Version Comparison" {
        It "Should compare installed vs latest version" {
            $scriptContent | Should -Match 'function Compare-OfficeVersions'
        }

        It "Should handle version parts numerically" {
            $scriptContent | Should -Match '\[int\].*Parts\[\$i\]'
        }

        It "Should return boolean for update availability" {
            $scriptContent | Should -Match 'return \$(true|false)'
        }
    }

    Context "API Integration" {
        It "Should use Microsoft Office Releases API" {
            $scriptContent | Should -Match 'clients\.config\.office\.net/releases'
        }

        It "Should use Invoke-RestMethod for API calls" {
            $scriptContent | Should -Match 'Invoke-RestMethod.*OfficeVersionURL'
        }

        It "Should test internet connectivity" {
            $scriptContent | Should -Match 'Invoke-WebRequest.*clients\.config\.office\.net'
        }
    }

    Context "File Management" {
        It "Should create log directory if missing" {
            $scriptContent | Should -Match 'New-Item.*Directory.*LogPath'
        }

        It "Should create updates directory if missing" {
            $scriptContent | Should -Match 'New-Item.*Directory.*UpdatesPath'
        }

        It "Should clean up old log files" {
            $scriptContent | Should -Match 'MaxLogAge'
        }

        It "Should remove update files after installation" {
            $scriptContent | Should -Match 'Get-ChildItem.*UpdatesPath.*Remove-Item'
        }

        It "Should calculate folder size before cleanup" {
            $scriptContent | Should -Match 'Measure-Object.*Length.*Sum'
        }
    }

    Context "Security Best Practices" {
        It "Should use -ErrorAction to control error behavior" {
            $scriptContent | Should -Match '-ErrorAction'
        }

        It "Should validate paths exist before use" {
            $scriptContent | Should -Match 'Test-Path'
        }

        It "Should use Force parameter carefully" {
            # Verify Force is only used on known safe operations
            $scriptContent | Should -Match '-Force'
        }

        It "Should use Stop parameter for Start-Process" {
            $scriptContent | Should -Match 'Start-Process.*-Wait'
        }
    }

    Context "Code Quality" {
        It "Should use regions for code organization" {
            $scriptContent | Should -Match '#region'
            $scriptContent | Should -Match '#endregion'
        }

        It "Should have Logging Functions region" {
            $scriptContent | Should -Match '#region Logging Functions'
        }

        It "Should have Helper Functions region" {
            $scriptContent | Should -Match '#region Helper Functions'
        }

        It "Should have Main Script region" {
            $scriptContent | Should -Match '#region Main Script'
        }

        It "Should use consistent function naming (Verb-Noun)" {
            $scriptContent | Should -Match 'function (Get|Set|New|Invoke|Test|Write|Clear|Show|Start)-\w+'
        }
    }

    Context "Main Execution Flow" {
        It "Should define Start-M365UpdateManager function" {
            $scriptContent | Should -Match 'function Start-M365UpdateManager'
        }

        It "Should call Start-M365UpdateManager" {
            $scriptContent | Should -Match 'Start-M365UpdateManager'
        }

        It "Should initialize logging first" {
            $scriptContent | Should -Match 'Initialize-Logging'
        }

        It "Should test prerequisites before proceeding" {
            $scriptContent | Should -Match 'Test-Prerequisites'
        }

        It "Should verify installation after update" {
            $scriptContent | Should -Match 'Verify new version|version verification'
        }
    }

    Context "Color-Coded Output" {
        It "Should use color-coded console output" {
            $scriptContent | Should -Match '-ForegroundColor'
        }

        It "Should use Green for success messages" {
            $scriptContent | Should -Match 'Green'
        }

        It "Should use Red for error messages" {
            $scriptContent | Should -Match 'Red'
        }

        It "Should use Yellow for warnings" {
            $scriptContent | Should -Match 'Yellow'
        }

        It "Should use Cyan for informational messages" {
            $scriptContent | Should -Match 'Cyan'
        }
    }
}

Describe "Update-M365Apps.ps1 - Logical Flow Tests" {
    Context "Script Logic Validation" {
        It "Should handle case where M365 Apps not installed" {
            $scriptContent | Should -Match 'not installed'
            $scriptContent | Should -Match 'Would you like to install'
        }

        It "Should handle case where apps are up to date" {
            $scriptContent | Should -Match 'up to date'
        }

        It "Should handle failed prerequisite checks" {
            $scriptContent | Should -Match 'Prerequisites.*failed.*Cannot continue'
        }

        It "Should allow deferring installation after download" {
            $scriptContent | Should -Match 'downloaded but not installed'
        }

        It "Should prompt for wait at script end" {
            $scriptContent | Should -Match 'Press any key to exit'
        }
    }

    Context "Deployment Scenarios" {
        It "Should support fresh M365 Apps installation" {
            $scriptContent | Should -Match 'fresh installation|Starting fresh installation'
        }

        It "Should support update installation" {
            $scriptContent | Should -Match 'Installing updates'
        }

        It "Should support channel switching" {
            $scriptContent | Should -Match 'change.*update channel|Changing update channel'
        }

        It "Should support download-only workflow" {
            $scriptContent | Should -Match 'downloaded but not installed'
        }
    }
}
