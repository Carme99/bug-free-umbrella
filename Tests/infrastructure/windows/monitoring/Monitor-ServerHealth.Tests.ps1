#Requires -Modules Pester

Describe "Monitor-ServerHealth" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot `
            ""../../../../scripts/infrastructure/windows/monitoring/Monitor-ServerHealth.ps1""

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Stub Windows-only commands so Pester can attach mocks on Linux.
        function Get-WinEvent { }
        function Get-CimInstance { }
        function Get-Service { }
        function Get-Process { }
        function Get-Counter { }
        function Get-Volume { }
        function Get-NetAdapter { }

        # Mock ALL externals so nothing touches the machine or network.
        Mock Test-AdminPrivilege { $true }
        Mock Start-Sleep { }
        Mock Read-Host { 'N' }
        Mock Write-Progress { }
        Mock Get-Counter {
            [pscustomobject]@{
                CounterSamples = @(
                    [pscustomobject]@{ CookedValue = 12.5 },
                    [pscustomobject]@{ CookedValue = 12.5 },
                    [pscustomobject]@{ CookedValue = 12.5 },
                    [pscustomobject]@{ CookedValue = 12.5 },
                    [pscustomobject]@{ CookedValue = 12.5 }
                )
            }
        }
        Mock Get-CimInstance {
            [pscustomobject]@{
                Caption               = 'Microsoft Windows Server 2022 Standard'
                Version               = '10.0.20348'
                BuildNumber           = '20348'
                NumberOfProcesses     = 120
                LastBootUpTime        = (Get-Date).AddDays(-3)
                TotalVisibleMemorySize = 8388608   # KB
                FreePhysicalMemory    = 4194304    # KB
                Manufacturer          = 'Contoso'
                Model                 = 'HV-1'
                Domain                = 'CONTOSO'
                AllocatedBaseSize     = 8192       # page file MB
                CurrentUsage          = 1024       # page file MB
            }
        }
        Mock Get-Process {
            @([pscustomobject]@{ ProcessName = 'System'; Id = 4; CPU = 12.5; WorkingSet64 = 100MB; Threads = @() })
        }
        Mock Get-Volume {
            @([pscustomobject]@{
                DriveLetter = 'C'; DriveType = 'Fixed'; Size = 200GB
                SizeRemaining = 100GB; FileSystemLabel = 'System'
            })
        }
        Mock Get-Service {
            [pscustomobject]@{
                Name = 'EventLog'; DisplayName = 'Windows Event Log'
                Status = 'Running'; StartType = 'Automatic'
            }
        }
        Mock Get-WinEvent { $null }
        Mock Get-NetAdapter {
            @([pscustomobject]@{
                Name = 'Ethernet'; InterfaceDescription = 'Virtual Adapter'
                Status = 'Up'; LinkSpeed = '10 Gbps'; MacAddress = 'AA-BB-CC-DD-EE-FF'
            })
        }

        $scriptText = Get-Content -Raw $scriptPath
    }

    Context "Help & Metadata" {
        It "Declares Version 1.0.0" {
            $scriptText | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
        }

        It "Declares relaunch Date 2026-08-23" {
            $scriptText | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
        }

        It "Declares File Name matching the disk filename" {
            $expected = Split-Path -Leaf $scriptPath
            $scriptText | Should -Match "(?m)^\s*File Name\s*:\s*$([regex]::Escape($expected))\s*$"
        }

        It "Declares an Author and Prerequisite" {
            $scriptText | Should -Match '(?m)^\s*Author\s*:\s*\S'
            $scriptText | Should -Match '(?m)^\s*Prerequisite\s*:\s*PowerShell'
        }

        It "Has at least two EXAMPLE blocks with PS C:\> prompts" {
            ([regex]::Matches($scriptText, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($scriptText, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }

        It "Has one .PARAMETER per declared parameter, in order" {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($scriptText, [ref]$tokens, [ref]$errors)
            $declared = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $documented = @([regex]::Matches($scriptText, '(?m)^\.PARAMETER\s+(\w+)') |
                ForEach-Object { $_.Groups[1].Value })
            $documented.Count | Should -Be $declared.Count
            for ($i = 0; $i -lt $declared.Count; $i++) {
                $documented[$i] | Should -Be $declared[$i]
            }
        }
    }

    Context "Syntax & Static" {
        It "Parses cleanly via the PowerShell parser" {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
            $errors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only syntax (no #Requires -Version 7.0 present)" {
            $scriptText | Should -Not -Match '#Requires\s+-Version\s+7'
            $scriptText | Should -Not -Match '\?\?'
            $scriptText | Should -Not -Match '&&'
            $scriptText | Should -Not -Match '\|\|'
            $scriptText | Should -Not -Match '-Parallel\b'
        }

        It "Wraps execution in Main and exits only via the top-level guard" {
            $scriptText | Should -Match '(?m)^function Main \{'
            $guardLine = [regex]::Escape("if (`$MyInvocation.InvocationName -ne '.') { exit (Main) }")
            $scriptText | Should -Match $guardLine
            ([regex]::Matches($scriptText, '\bexit\b')).Count | Should -Be 1
        }

        It "Uses UTF-8 BOM and CRLF line endings" {
            $raw = [System.IO.File]::ReadAllBytes($scriptPath)
            ($raw[0], $raw[1], $raw[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            [System.Text.Encoding]::UTF8.GetString($raw) | Should -Not -Match "(?<!`r)`n"
        }
    }

    Context "Behavior" {
        It "Runs all core health checks against healthy mocks and returns 0" {
            $ShowProgress = $true   # bypasses the interactive menu without enabling exports

            $out = Main *>&1
            $rc = $out | Where-Object { $_ -is [int] } | Select-Object -First 1
            $rc | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[\+\]'
            $text | Should -Match 'HEALTHY'
            $script:healthReport.Status | Should -Be 'Healthy'
            Should -Invoke Get-Counter -Times 7 -Exactly -Because "5 CPU samples + threads + handles"
        }

        It "Is idempotent: a repeated run on the same system succeeds again" {
            $ShowProgress = $true
            (Main *>&1 | Where-Object { $_ -is [int] }) | Should -Contain 0
            (Main *>&1 | Where-Object { $_ -is [int] }) | Should -Contain 0
        }

        It "Returns 1 with [-] output when disk enumeration fails upstream" {
            $ShowProgress = $true
            Mock Get-Volume { throw "storage stack unavailable" }
            $out = Main *>&1
            $rc = $out | Where-Object { $_ -is [int] } | Select-Object -First 1
            $rc | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Returns 1 with [-] output when administrator privileges are missing" {
            Mock Test-AdminPrivilege { $false }
            $out = Main *>&1
            $rc = $out | Where-Object { $_ -is [int] } | Select-Object -First 1
            $rc | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
