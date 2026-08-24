#Requires -Modules Pester

Describe "Backup-GroupPolicies" {
    BeforeAll {
        $scriptRelPath = '../../../../scripts/infrastructure/windows/group-policy/Backup-GroupPolicies.ps1'
        $scriptPath = Join-Path $PSScriptRoot $scriptRelPath

        # Safe: the script's top-level guard skips Main when dot-sourced. The mandatory
        # param must be supplied explicitly - dot-sourced param blocks do not read caller variables.
        . $scriptPath -BackupPath (Join-Path $TestDrive 'pre-dot-backup')

        # Local stubs for ActiveDirectory/GroupPolicy module commands: they do not exist
        # on Linux, and Pester cannot mock a command that does not resolve.
        function Get-ADDomain { }
        function Get-GPO { }
        function Backup-GPO { }
        function Get-GPOReport { }

        function New-FakeGpo {
            param([string]$Name)
            return [pscustomobject]@{
                Id               = [guid]::NewGuid()
                DisplayName      = $Name
                GpoStatus        = 'AllSettingsEnabled'
                CreationTime     = (Get-Date).AddDays(-100)
                ModificationTime = (Get-Date).AddDays(-5)
                WmiFilter        = $null
                Owner            = 'CONTOSO\Domain Admins'
                Computer         = [pscustomobject]@{ Enabled = $true; DSVersion = 3 }
                User             = [pscustomobject]@{ Enabled = $true; DSVersion = 2 }
            }
        }

        # Mock -CommandName ALL external commands/modules so nothing touches a real domain.
        Mock -CommandName Get-ADDomain { [pscustomobject]@{ DNSRoot = 'contoso.com' } }
        Mock -CommandName Get-GPO { @(New-FakeGpo 'Baseline Security'; New-FakeGpo 'Drive Maps') }
        Mock -CommandName Backup-GPO { [pscustomobject]@{ Id = [guid]::NewGuid() } }
        # This script only ever requests the XML link report (no -Path), so a plain mock suffices.
        Mock -CommandName Get-GPOReport { '<GPO><LinksTo></LinksTo></GPO>' }
        Mock -CommandName Remove-Item { }
    }

    Context "Help & Metadata" {
        It "Declares File Name matching the disk filename" {
            Get-Content -Raw $scriptPath | Should -Match 'File Name:\s*Backup-GroupPolicies\.ps1'
        }

        It "Declares Version 1.0.0 and relaunch Date" {
            $helpText = Get-Content -Raw $scriptPath
            $helpText | Should -Match 'Version:\s*1\.0\.0'
            $helpText | Should -Match 'Date:\s*2026-08-23'
        }

        It "Has one .PARAMETER entry per declared parameter, in order" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $paramNames = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $paramMatches = [regex]::Matches(
                (Get-Content -Raw $scriptPath), '(?m)^\.PARAMETER\s+(\S+)')
            $declared = @($paramMatches | ForEach-Object { $_.Groups[1].Value })
            $declared.Count | Should -Be $paramNames.Count
            for ($i = 0; $i -lt $paramNames.Count; $i++) {
                $declared[$i] | Should -Be $paramNames[$i]
            }
        }

        It "Declares SupportsShouldProcess because retention cleanup deletes old backups" {
            (Get-Content -Raw $scriptPath) | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
            (Get-Content -Raw $scriptPath) | Should -Match '\$PSCmdlet\.ShouldProcess'
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
            $errors.Count | Should -Be 0
        }

        It "Contains no PS7-only syntax without a #Requires -Version 7.0 opt-out" {
            $text = Get-Content -Raw $scriptPath
            if (-not ($text -match '(?m)^\s*#Requires\s+-Version\s+7\.0')) {
                $text | Should -Not -Match '\?\?'
                $text | Should -Not -Match '\|\|'
                $text | Should -Not -Match '&&'
                $text | Should -Not -Match '-Parallel\b'
            }
        }
    }

    Context "Behavior" {
        It "Backs up every GPO and returns 0 on success" {
            $backupRoot = Join-Path $TestDrive 'gpo-backups'
            $BackupPath = $backupRoot
            $Comment = 'Automated GPO backup'; $RetentionDays = 90
            $CompressBackup = $false; $GPOName = $null

            Main | Should -Be 0
            Should -Invoke Backup-GPO -Times 2 -Exactly
            $created = Get-ChildItem -Path $backupRoot -Directory -Filter 'GPO_Backup_*'
            @($created).Count | Should -Be 1
            Join-Path $created[0].FullName 'BackupLog.csv' | Should -Exist
            Join-Path $created[0].FullName 'BackupManifest.json' | Should -Exist
            Join-Path $created[0].FullName 'BackupReport.html' | Should -Exist
        }

        It "Returns 1 with [-] output when the named GPO does not exist" {
            # Per-run Main only issues one Get-GPO call shape; an unfiltered override is
            # sufficient (ParameterFilter is unreliable in this Pester/pwsh combination).
            Mock -CommandName Get-GPO { throw 'GPO not found' }
            $BackupPath = (Join-Path $TestDrive 'gpo-backups-missing')
            $Comment = 'x'; $RetentionDays = 90; $CompressBackup = $false
            $GPOName = 'Nope'

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It "Is idempotent: converged retention makes no deletions and still returns 0" {
            Mock -CommandName Get-ChildItem { @() }
            $BackupPath = (Join-Path $TestDrive 'gpo-backups-clean')
            $Comment = 'x'; $RetentionDays = 90; $CompressBackup = $false; $GPOName = $null

            Main | Should -Be 0
            Should -Invoke Backup-GPO -Times 2 -Exactly
            Should -Invoke Remove-Item -Times 0 -Exactly -Because "converged retention deletes nothing"
        }

        It "Deletes expired backup folders through the ShouldProcess gate" {
            $expired = [pscustomobject]@{ FullName = (Join-Path $TestDrive 'old'); Name = 'GPO_Backup_Old' }
            Mock -CommandName Get-ChildItem { @($expired) }
            Mock -CommandName Remove-Item { }
            $BackupPath = (Join-Path $TestDrive 'gpo-backups-retention')
            $Comment = 'x'; $RetentionDays = 30; $CompressBackup = $false; $GPOName = $null

            Main | Should -Be 0
            # The unfiltered listing mock feeds both the directory scan and the ZIP scan,
            # so the single expired item yields one folder deletion plus one ZIP deletion.
            Should -Invoke Remove-Item -Times 2 -Exactly
        }
    }
}
