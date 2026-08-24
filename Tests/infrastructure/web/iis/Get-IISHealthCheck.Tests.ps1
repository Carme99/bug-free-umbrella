#Requires -Modules Pester

Describe "Get-IISHealthCheck" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../../scripts/infrastructure/web/iis/Get-IISHealthCheck.ps1"
        $scriptText = Get-Content -LiteralPath $scriptPath -Raw

        # Placeholder functions: product modules are not installed offline;
        # Pester Mock requires the command names to be resolvable.
        function Get-WindowsFeature { }
        function Get-IISAppPool { }
        function Get-IISSite { }
        function Get-Counter { }

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Avoid touching the real home directory when resolving the Reports folder.
        Mock New-Item { }

        # Shared builders for IISAdministration objects.
        function New-TestAppPool {
            param([string]$State = 'Started')
            [pscustomobject]@{
                Name                  = 'Pool1'
                State                 = $State
                ManagedRuntimeVersion = 'v4.0'
                ManagedPipelineMode   = 'Integrated'
                StartMode             = 'OnDemand'
                Enable32BitAppOnWin64 = $false
                ProcessModel          = [pscustomobject]@{ IdleTimeout = [timespan]::FromMinutes(20) }
Recycling             = [pscustomobject]@{
                        PeriodicRestart     = [pscustomobject]@{ Schedule = @(); PrivateMemory = 0 }
                    }
            }
        }
        function New-TestSite {
            param([string]$State = 'Started', [string]$PhysicalPath)
            [pscustomobject]@{
                Name       = 'Site1'
                Id         = 1
                State      = $State
                Bindings   = @([pscustomobject]@{ Protocol = 'http'; BindingInformation = '*:80:' })
                LogFile    = [pscustomobject]@{ Directory = 'C:\inetpub\logs\LogFiles' }
                Applications = @{
                    '/' = [pscustomobject]@{
                        ApplicationPoolName = 'Pool1'
                        VirtualDirectories  = @{ '/' = [pscustomobject]@{ PhysicalPath = $PhysicalPath } }
                    }
                }
            }
        }

        Mock Get-WindowsFeature { [pscustomobject]@{ Name = 'Web-Server'; Installed = $true } }
        Mock Get-ItemProperty { [pscustomobject]@{ VersionString = '10.0.20348' } }
    }

    Context "Help & Metadata" {
        It "Declares the complete header block" {
            $scriptText | Should -Match '(?m)^\.SYNOPSIS'
            $scriptText | Should -Match '(?m)^\.DESCRIPTION'
            $scriptText | Should -Match '(?m)^\.NOTES'
        }

        It "Populates all five .NOTES fields correctly" {
            $scriptText | Should -Match 'File Name\s*:\s*Get-IISHealthCheck\.ps1'
            $scriptText | Should -Match 'Author\s*:\s*\S'
            $scriptText | Should -Match 'Prerequisite\s*:\s*PowerShell'
            $scriptText | Should -Match 'Version\s*:\s*1\.0\.0'
            $scriptText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Has at least 2 examples with PS C:\> prompts" {
            ([regex]::Matches($scriptText, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($scriptText, [regex]::Escape('PS C:\>'))).Count | Should -BeGreaterOrEqual 2
        }

        It "Documents one .PARAMETER per declared parameter, in order" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
            $declared = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
            $documented = [regex]::Matches($scriptText, '(?m)^\.PARAMETER\s+(\S+)') |
                    ForEach-Object { $_.Groups[1].Value }
            $documented | Should -Be $declared
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                    $scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
            $errors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only operators without a #Requires -Version 7.0 opt-out" {
            if ($scriptText -notmatch '(?m)^#Requires\s+-Version\s+7\.0') {
                $tokens = $null
                $parseErrors = $null
                [System.Management.Automation.Language.Parser]::ParseInput(
                        $scriptText, [ref]$tokens, [ref]$parseErrors) | Out-Null
                $kindType = [System.Management.Automation.Language.TokenKind]
                $ps7Kinds = @('AmpersandAmpersand', 'BarBar', 'QuestionMark', 'QuestionQuestionEquals') |
                    Where-Object { $kindType.GetMember($_) }
                $offenders = @($tokens | Where-Object { $ps7Kinds -contains [string]$_.Kind })
                $offenders | Should -BeNullOrEmpty -Because "PS7-only operators require #Requires opt-out"
            }
        }

        It "Uses the mandatory Main entrypoint and dot-source guard" {
            $guard = "if (`$MyInvocation.InvocationName -ne '.') { exit (Main) }"
            $scriptText.Contains($guard) | Should -BeTrue
        }
    }

    Context "Behavior" {
        It "Returns 0 with [+] output on a healthy, fully-started server" {
            $physPath = Join-Path $TestDrive 'wwwroot'
            [void][System.IO.Directory]::CreateDirectory($physPath)
            Mock Get-IISAppPool { @(New-TestAppPool -State 'Started') }
            Mock Get-IISSite { @(New-TestSite -State 'Started' -PhysicalPath $physPath) }

            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
        }

        It "Returns 1 and writes [-] output when IIS is not installed" {
            Mock Get-WindowsFeature { [pscustomobject]@{ Name = 'Web-Server'; Installed = $false } }

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It "Flags stopped pools and sites as ACTION REQUIRED and returns 1 below score threshold" {
            $physPath = Join-Path $TestDrive 'wwwroot2'
            [void][System.IO.Directory]::CreateDirectory($physPath)
            Mock Get-IISAppPool { @(New-TestAppPool -State 'Stopped') }
            Mock Get-IISSite { @(New-TestSite -State 'Stopped' -PhysicalPath $physPath) }

            $out = Main *>&1

            ($out | Out-String) | Should -Match 'ACTION REQUIRED'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
