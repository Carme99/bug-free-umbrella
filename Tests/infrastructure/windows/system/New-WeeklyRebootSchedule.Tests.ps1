#Requires -Modules Pester

Describe "New-WeeklyRebootSchedule" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            "../../../../scripts/infrastructure/windows/system/New-WeeklyRebootSchedule.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Windows-only cmdlets are absent on Linux CI - define no-op stubs
        # so Pester has an existing command to attach each Mock to.
        foreach ($cmd in @('Get-CimInstance', 'Get-ScheduledTask', 'Unregister-ScheduledTask',
                'Register-ScheduledTask', 'New-ScheduledTaskAction', 'New-ScheduledTaskTrigger',
                'New-ScheduledTaskSettingsSet', 'New-ScheduledTaskPrincipal', 'Get-ScheduledTaskInfo')) {
            if (-not (Get-Command -Name $cmd -ErrorAction SilentlyContinue)) {
                . ([scriptblock]::Create("function script:$cmd { }"))
            }
        }

        # Mock platform/external seams so nothing leaves the machine.
        Mock -CommandName Test-AdminPrivilege { $true }
        Mock -CommandName Get-CimInstance {
            [pscustomobject]@{ Caption = "Microsoft Windows Server 2022"; Version = "10.0.20348" }
        }
        Mock -CommandName Start-Sleep { }
        Mock -CommandName New-ScheduledTaskAction { [pscustomobject]@{ Execute = "shutdown.exe" } }
        Mock -CommandName New-ScheduledTaskTrigger { [pscustomobject]@{ DaysOfWeek = $null } }
        Mock -CommandName New-ScheduledTaskSettingsSet { [pscustomobject]@{ } }
        Mock -CommandName New-ScheduledTaskPrincipal { [pscustomobject]@{ UserId = "NT AUTHORITY\SYSTEM" } }
        Mock -CommandName Unregister-ScheduledTask { }
        Mock -CommandName Register-ScheduledTask { [pscustomobject]@{ TaskName = $TaskName; State = "Ready" } }
        Mock -CommandName Get-ScheduledTaskInfo { [pscustomobject]@{ NextRunTime = (Get-Date).AddDays(1) } }

        function New-FakeTask {
            return [pscustomobject]@{ TaskName = "Weekly Server Reboot"; State = "Ready" }
        }
    }

    Context "Help & Metadata" {
        It "Declares the required header fields with relaunch values" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            $text | Should -Match '\.SYNOPSIS'
            $text | Should -Match '\.DESCRIPTION'
            $text | Should -Match 'File Name:\s*New-WeeklyRebootSchedule\.ps1'
            $text | Should -Match 'Version:\s*1\.0\.0'
            $text | Should -Match 'Date:\s*2026-08-23'
            $text | Should -Match 'Prerequisite:\s*PowerShell'
            $text | Should -Match 'Author:\s*System Administrator'
        }

        It "Documents exactly the declared parameters in order" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            $helpParams = [regex]::Matches($text, '(?m)^\.PARAMETER\s+(\w+)') | ForEach-Object { $_.Groups[1].Value }
            $tokens = $null; $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors)
            $declared = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
            $helpParams | Should -Be $declared
        }

        It "Provides at least two examples with PS C:\> prompts" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            ([regex]::Matches($text, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($text, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses cleanly" {
            $tokens = $null; $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only syntax without #Requires -Version 7.0" {
            $text = Get-Content -LiteralPath $scriptPath -Raw
            if ($text -notmatch '(?m)^#Requires\s+-Version\s+7') {
                $text | Should -Not -Match '\?\?'
                $text | Should -Not -Match '\|\|'
                $text | Should -Not -Match '&&'
                $text | Should -Not -Match '-Parallel'
            }
        }

        It "Uses no tabs, max 120 columns and no trailing whitespace" {
            $lines = Get-Content -LiteralPath $scriptPath
            $bad = @($lines | Where-Object { $_ -match '`t' -or $_ -match '\s$' -or $_.Length -gt 120 })
            $bad | Should -BeNullOrEmpty
        }
    }

    Context "Behavior" {
        It "Creates the task and returns 0 when it does not already exist" {
            $script:taskCalls = 0
            Mock -CommandName Get-ScheduledTask {
                $script:taskCalls++
                if ($script:taskCalls -eq 1) { return $null }
                return New-FakeTask
            }

            $out = Main -DayOfWeek Sunday -Time "03:00" -Force *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Register-ScheduledTask -Times 1 -Exactly
            Should -Invoke Unregister-ScheduledTask -Times 0 -Exactly
        }

        It "Is idempotent: existing task plus declined confirmation mutates nothing" {
            Mock -CommandName Get-ScheduledTask { New-FakeTask }
            Mock -CommandName Read-Host { "N" }

            $out = Main -DayOfWeek Monday -Time "02:00" *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'cancelled by user'
            Should -Invoke Unregister-ScheduledTask -Times 0 -Exactly
            Should -Invoke Register-ScheduledTask -Times 0 -Exactly
        }

        It "Returns 1 with [-] output when task registration fails" {
            Mock -CommandName Get-ScheduledTask { $null }
            Mock -CommandName Register-ScheduledTask { throw "Access denied" }

            $out = Main -DayOfWeek Sunday -Time "03:00" -Force *>&1

            ($out | Out-String) | Should -Match '\[-\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }
    }
}
