#Requires -Modules Pester

Describe "Test-RemediationFixOneDriveKnownFolderMove" -Tag Ep6SysA {
    BeforeAll {
        # Mirrored layout: walk up from Tests/... to the repo root, then across to scripts/.
        $repoRoot = $PSScriptRoot
        while (-not (Test-Path (Join-Path $repoRoot '.git'))) { $repoRoot = Split-Path $repoRoot -Parent }
        $scriptRelPath = 'scripts/endpoints/remediation/system/Test-RemediationFixOneDriveKnownFolderMove.ps1'
        $scriptPath = Join-Path $repoRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares required .NOTES fields with Version 1.0.0 and Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match 'File Name:\s*Test-RemediationFixOneDriveKnownFolderMove\.ps1'
            $raw | Should -Match 'Version:\s*1\.0\.0'
            $raw | Should -Match 'Date:\s*2026-08-23'
            $raw | Should -Match 'Author:'
            $raw | Should -Match 'Prerequisite:\s*PowerShell 7\.0'
        }

        It "Has SYNOPSIS, DESCRIPTION and at least two EXAMPLES" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
        }

        It "Declares one .PARAMETER per param() parameter" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
            if ($null -eq $ast.ParamBlock) { $declared = @() }
            else { $declared = @($ast.ParamBlock.Parameters.Name.VariableText) }
            $raw = Get-Content -Path $scriptPath -Raw
            $paramHelpMatches = [regex]::Matches($raw, '(?m)^\s*\.PARAMETER\s+(\S+)')
            $documented = @($paramHelpMatches | ForEach-Object { $_.Groups[1].Value })
            @($documented).Count | Should -Be @($declared).Count
            foreach ($p in $declared) { $documented | Should -Contain $p }
        }
    }

    Context "Syntax & Static" {
        BeforeAll {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        }
        It "Parses with zero errors" {
            $errors | Should -BeNullOrEmpty
        }
        It "Contains no PS7-only operators (no #Requires -Version 7.0 opt-out present)" {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Not -Match '(?m)&&|\|\||\?\?|\?\?='
            $raw | Should -Not -Match '\$\w+\s*\?\s*[^:]'
        }
        It "Calls exit only in the top-level dot-source guard" {
            $raw = Get-Content -Path $scriptPath -Raw
            @([regex]::Matches($raw, '\bexit\b')).Count | Should -Be 1
            $raw | Should -BeLike '*if ($MyInvocation.InvocationName -ne ''.'') { exit (Main) }*'
        }
    }

    Context "Behavior" {
        It "Returns 0 when OneDrive runs and all known folders are protected (converged)" {
            function Get-WmiObject { }
            # Catch-all first: Pester applies the most recently defined matching mock.
            Mock Test-Path { $false }
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*OneDrive.exe' }
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*Business1*' }
            Mock Get-WmiObject { [pscustomobject] @{ UserName = 'CONTOSO\alice' } }
            Mock Resolve-CurrentUserSid { 'S-1-5-21-1004336348' }
            Mock Get-ItemProperty {
                [pscustomobject] @{
                    DesktopFolderProtectedStatus   = 2
                    DocumentsFolderProtectedStatus = 2
                    PicturesFolderProtectedStatus  = 2
                }
            }
            Mock Get-Process { [pscustomobject] @{ ProcessName = 'OneDrive' } }
            Main *>&1 | Where-Object { $_ -is [int] } | Should -Be 0
            Should -Invoke Resolve-CurrentUserSid -Times 1 -Exactly
        }

        It "Returns 1 when OneDrive is not installed" {
            function Get-WmiObject { }
            Mock Test-Path { $false }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match 'not installed'
        }

        It "Returns 1 and lists each KFM issue found" {
            function Get-WmiObject { }
            # Catch-all first: Pester applies the most recently defined matching mock.
            Mock Test-Path { $false }
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*OneDrive.exe' }
            Mock Get-WmiObject { [pscustomobject] @{ UserName = 'CONTOSO\alice' } }
            Mock Resolve-CurrentUserSid { 'S-1-5-21-1004336348' }
            Mock Get-Process { $null }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            $text = $out | Out-String
            $text | Should -Match 'not running'
            $text | Should -Match 'Business account not configured'
            $text | Should -Match 'sync folder not found'
        }

        It "Flags unprotected folders when protection statuses are not 2" {
            function Get-WmiObject { }
            # Catch-all first: Pester applies the most recently defined matching mock.
            Mock Test-Path { $false }
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*OneDrive.exe' }
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*Business1*' }
            Mock Get-WmiObject { [pscustomobject] @{ UserName = 'CONTOSO\alice' } }
            Mock Resolve-CurrentUserSid { 'S-1-5-21-1004336348' }
            Mock Get-ItemProperty {
                [pscustomobject] @{
                    DesktopFolderProtectedStatus   = 2
                    DocumentsFolderProtectedStatus = 0
                    PicturesFolderProtectedStatus  = $null
                }
            }
            Mock Get-Process { [pscustomobject] @{ ProcessName = 'OneDrive' } }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            $text = $out | Out-String
            $text | Should -Match 'Documents folder is not protected'
            $text | Should -Match 'Pictures folder is not protected'
            $text | Should -Not -Match 'Desktop folder is not protected'
        }

        It "Returns 1 with [-] prefixed output when SID resolution fails" {
            function Get-WmiObject { }
            # Catch-all first: Pester applies the most recently defined matching mock.
            Mock Test-Path { $false }
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*OneDrive.exe' }
            Mock Get-WmiObject { [pscustomobject] @{ UserName = 'CONTOSO\ghost' } }
            Mock Resolve-CurrentUserSid { throw "no domain controller reachable" }
            Mock Get-Process { [pscustomobject] @{ ProcessName = 'OneDrive' } }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }
    }
}
