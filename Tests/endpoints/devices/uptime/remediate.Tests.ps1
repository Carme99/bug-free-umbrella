#Requires -Modules Pester

Describe "remediate.ps1 (uptime)" {
    BeforeAll {
        # Mirrored layout: walk up 4 levels from this test folder to the repository root.
        $repoRoot = (Get-Item (Join-Path $PSScriptRoot "../../../../")).FullName
        $scriptPath = Join-Path $repoRoot "scripts/endpoints/devices/uptime/remediate.ps1"

        # Safe: the top-level guard skips Main when dot-sourced (docs/RELAUNCH-SPEC.md section 3).
        . $scriptPath


        # Windows-only ScheduledTasks cmdlets do not exist on Linux pwsh; stub them so
        # Pester has a command surface to mock (docs/RELAUNCH-SPEC.md section 5).
        # Full parameter signatures so Pester can bind named parameters for ParameterFilters.
        function Get-ScheduledTask {
            [CmdletBinding()]
            param([string]$TaskName)
            $null
        }

        function Unregister-ScheduledTask {
            [CmdletBinding()]
            param([string]$TaskName, [switch]$Confirm)
        }

        function Register-ScheduledTask {
            [CmdletBinding()]
            param([string]$TaskName, $Action, $Trigger, $Principal, [switch]$Force)
        }

        function New-ScheduledTaskAction {
            [CmdletBinding()]
            param([string]$Execute, [string]$Argument)
            $null
        }

        function New-ScheduledTaskTrigger {
            [CmdletBinding()]
            param([switch]$Once, [datetime]$At)
            $null
        }

        function New-ScheduledTaskPrincipal {
            [CmdletBinding()]
            param([string]$UserId, [string]$LogonType, [string]$RunLevel)
            $null
        }
        # Keep the run fully offline: every external surface is mocked.
        Mock Write-DeploymentLog { }
        Mock Install-BurntToastModule { }
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock Get-ScheduledTask { $null }
        Mock New-ScheduledTaskAction { [pscustomobject]@{ Execute = 'powershell.exe' } }
        Mock New-ScheduledTaskTrigger { [pscustomobject]@{ At = (Get-Date) } }
        Mock New-ScheduledTaskPrincipal { [pscustomobject]@{ UserId = 'contoso\user' } }
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0 and relaunch Date 2026-08-23" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$') | Should -BeTrue
            ($raw -match '(?m)^\s*Date\s*:\s*2026-08-23\s*$') | Should -BeTrue
        }

        It "Declares File Name matching the on-disk filename" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match "(?m)^\s*File Name\s*:\s*remediate\.ps1\s*$") | Should -BeTrue
        }

        It "Documents every declared parameter in declaration order (none declared)" {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $raw = Get-Content -Path $scriptPath -Raw
            $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $documented = @([regex]::Matches($raw, '(?m)^\.PARAMETER\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
            $declared.Count | Should -Be 0
            $documented.Count | Should -Be 0
        }

        It "Provides at least two examples" {
            $raw = Get-Content -Path $scriptPath -Raw
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Is UTF-8 BOM encoded with CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            (@($bytes[0], $bytes[1], $bytes[2])) | Should -Be @(0xEF, 0xBB, 0xBF)
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            $bareLfLines = @(($text -split "`n") | Where-Object { $_ -and ($_ -notmatch "`r$") })
            $bareLfLines.Count | Should -Be 0
        }

        It "Contains no PS7-only operators without an opt-out pragma" {
            $raw = Get-Content -Path $scriptPath -Raw
            foreach ($pattern in '&&', '\|\|', '\?\?') {
                ($raw -match $pattern) | Should -BeFalse
            }
        }

        It "Gates destructive task operations behind SupportsShouldProcess" {
            $raw = Get-Content -Path $scriptPath -Raw
            ($raw -match '\[CmdletBinding\(SupportsShouldProcess\)\]') | Should -BeTrue
            ($raw -match '\$PSCmdlet\.ShouldProcess') | Should -BeTrue
        }
    }

    Context "Behavior" {
        It "Deploys the notification script and registers the scheduled task on a fresh device" {
            Mock Write-Host { }
            Mock Save-RestartNotificationScript { }
            Mock Register-ScheduledTask { }

            Main | Should -Be 0

            Should -Invoke Save-RestartNotificationScript -Times 1 -Exactly -ParameterFilter {
                $Path -like '*RestartNotification.ps1'
            }
            Should -Invoke Register-ScheduledTask -Times 1 -Exactly -ParameterFilter {
                $TaskName -eq 'RestartNotification'
            }
        }

        It "Is idempotent on a converged device: replaces the existing task and still succeeds" {
            Mock Write-Host { }
            Mock Save-RestartNotificationScript { }
            Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = 'RestartNotification' } }
            Mock Unregister-ScheduledTask { }
            Mock Register-ScheduledTask { }

            Main | Should -Be 0

            Should -Invoke Unregister-ScheduledTask -Times 1 -Exactly -ParameterFilter {
                $TaskName -eq 'RestartNotification'
            }
            Should -Invoke Register-ScheduledTask -Times 1 -Exactly
        }

        It "Returns 1 with [-] output when module installation fails" {
            Mock Write-Host { param($Object) $Object }
            Mock Install-BurntToastModule { throw 'no network' }

            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\]'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It "Honors -WhatIf: nothing is written and no task is registered or removed" {
            Mock Write-Host { }
            Mock Save-RestartNotificationScript { throw 'WhatIf must prevent write' }
            Mock Register-ScheduledTask { throw 'WhatIf must prevent registration' }
            Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = 'RestartNotification' } }
            Mock Unregister-ScheduledTask { throw 'WhatIf must prevent removal' }

            Main -WhatIf | Should -Be 0

            Should -Invoke Save-RestartNotificationScript -Times 0 -Exactly
            Should -Invoke Register-ScheduledTask -Times 0 -Exactly
            Should -Invoke Unregister-ScheduledTask -Times 0 -Exactly
            Should -Invoke New-Item -Times 0 -Exactly
        }
    }
}
