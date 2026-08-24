#Requires -Modules Pester

Describe "Get-HyperVHealth" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/infrastructure/virtualization/Get-HyperVHealth.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        . $scriptPath
        # Stub Hyper-V/Windows-only commands up front so Pester can mock them on Linux.
        function Get-Service { }
        function Get-VMHost { }
        function Get-Counter { }
        function Get-VM { }
        function Get-VMSwitch { }
        function Get-VMIntegrationService { }
        function Get-VMSnapshot { }
        function Get-VMReplication { }


        # Mock ALL external commands/modules (Hyper-V module is NOT required at test runtime).
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock Out-File { }
        Mock Export-Csv { }
        Mock Get-Service { [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' } }
        Mock Get-VMHost {
            [pscustomobject]@{ LogicalProcessorCount = 16; MemoryCapacity = 32GB }
        }
        Mock Get-Counter {
            [pscustomobject]@{ CounterSamples = [pscustomobject]@{ CookedValue = 8GB } }
        }
        Mock Get-VM { @() }
        Mock Get-VMSwitch {
            @(
                [pscustomobject]@{
                    Name             = 'ExternalSwitch'
                    SwitchType       = 'External'
                    AllowManagementOS = $true
                }
            )
        }

        # Default parameter state; individual Its override as needed.
        $IncludeVMs = $false
        $CheckReplication = $false
        $CheckSnapshots = $false
        $ExportHTML = $false
        $ExportCSV = $false
    }

    Context "Help & Metadata" {
        It "Declares File Name matching the disk filename" {
            $helpText = Get-Content -Raw $scriptPath
            $helpText | Should -Match 'File Name\s*:\s*Get-HyperVHealth\.ps1'
        }

        It "Declares Author and Prerequisite" {
            $helpText = Get-Content -Raw $scriptPath
            $helpText | Should -Match 'Author\s*:\s*\S'
            $helpText | Should -Match 'Prerequisite\s*:\s*PowerShell'
        }

        It "Declares Version 1.0.0 and Date 2026-08-23" {
            $helpText = Get-Content -Raw $scriptPath
            $helpText | Should -Match 'Version\s*:\s*1\.0\.0'
            $helpText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Has one .PARAMETER block per declared parameter, in order" {
            $helpText = Get-Content -Raw $scriptPath
            $paramBlocks = ([regex]::Matches($helpText, '(?m)^\.PARAMETER')).Count
            $declaredParams = ([regex]::Matches($helpText, '\[Parameter\(')).Count
            $paramBlocks | Should -Be $declaredParams
            $expectedOrder = @('IncludeVMs', 'CheckReplication', 'CheckSnapshots', 'ExportHTML', 'ExportCSV')
            $foundOrder = [regex]::Matches($helpText, '(?m)^\.PARAMETER\s+(\S+)') |
                ForEach-Object { $_.Groups[1].Value }
            $foundOrder | Should -Be $expectedOrder
        }

        It "Has at least two .EXAMPLE blocks with PS C:\> prompts" {
            $helpText = Get-Content -Raw $scriptPath
            ([regex]::Matches($helpText, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($helpText, 'PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero parser errors" {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors.Count | Should -Be 0
        }

        It "Contains no PS7-only syntax without a #Requires -Version 7.0 line" {
            $raw = Get-Content -Raw $scriptPath
            if (-not ($raw -match '(?m)^#Requires\s+-Version\s+7')) {
                $raw | Should -Not -Match '\?\?'
                $raw | Should -Not -Match '\|\|'
                $raw | Should -Not -Match '&&'
                $raw | Should -Not -Match '-Parallel\b'
            }
        }

        It "Uses UTF-8 BOM and CRLF line endings" {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            $raw = [System.Text.Encoding]::UTF8.GetString($bytes)
            $bareLf = [regex]::Matches($raw, "(?<!`r)`n")
            $bareLf.Count | Should -Be 0
        }
    }

    Context "Behavior" {
        It "Returns 0 on a healthy host (vmms running, low memory usage)" {
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
            Should -Invoke Get-VMSwitch -Times 1 -Exactly -Scope It
        }

        It "Returns 1 with [-] output when the Hyper-V management service is down" {
            Mock Get-Service { $null }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Is idempotent: repeated health-check runs return consistent results" {
            $firstRun = (Main *>&1 | Where-Object { $_ -is [int] })
            $secondRun = (Main *>&1 | Where-Object { $_ -is [int] })
            $firstRun | Should -Be 0
            $secondRun | Should -Be 0
        }

        It "Checks integration services for each VM when -IncludeVMs is set" {
            Mock Get-VM {
                @(
                    [pscustomobject]@{
                        Name           = 'VM01'
                        State          = 'Running'
                        MemoryDemand   = 2GB
                        MemoryAssigned = 4GB
                        ReplicationState = 'Disabled'
                    }
                )
            }
            Mock Get-VMIntegrationService {
                @([pscustomobject]@{ Enabled = $true; PrimaryOperationalStatus = 'Ok' })
            }
            $IncludeVMs = $true
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-VMIntegrationService -Times 1 -Exactly -Scope It
        }

        It "Flags VMs with snapshots as a warning when -CheckSnapshots is set" {
            $snapshotTime = (Get-Date).AddDays(-10)
            Mock Get-VM {
                @(
                    [pscustomobject]@{
                        Name             = 'VM02'
                        State            = 'Off'
                        ReplicationState = 'Disabled'
                    }
                )
            }
            Mock Get-VMSnapshot {
                @([pscustomobject]@{ CreationTime = $snapshotTime })
            }
            $CheckSnapshots = $true
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0   # warnings alone keep exit code 0
            ($out | Out-String) | Should -Match 'snapshots?'
        }
    }
}
