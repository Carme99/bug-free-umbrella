#Requires -Modules Pester

Describe "Get-PrintServerHealth" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../scripts/infrastructure/print/Get-PrintServerHealth.ps1"

        # Safe: the script's top-level guard skips Main when dot-sourced (RELAUNCH-SPEC §3).
        . $scriptPath
        # Stub Windows-only commands up front so Pester can mock them on Linux.
        function Get-WinEvent { }
        function Get-Printer { }
        function Get-PrintJob { }
        function Remove-PrintJob { }
        function Get-PrinterDriver { }
        function Get-Service { }
        function Get-PSDrive { }


        # Mock ALL external commands/modules so nothing leaves the machine.
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock Out-File { }
        Mock Export-Csv { }
        Mock Get-WinEvent { @() }

        # Default parameter state; individual Its override as needed.
        $ClearStuckJobs = $false
        $CheckDrivers = $false
        $ExportHTML = $false
        $ExportCSV = $false
    }

    Context "Help & Metadata" {
        It "Declares File Name matching the disk filename" {
            $helpText = Get-Content -Raw $scriptPath
            $helpText | Should -Match 'File Name\s*:\s*Get-PrintServerHealth\.ps1'
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
            $expectedOrder = @('ClearStuckJobs', 'StuckJobThresholdHours', 'CheckDrivers', 'ExportHTML', 'ExportCSV')
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
        It "Returns 0 on a healthy server (spooler running, ample disk, no printers)" {
            Mock Get-Service { [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' } }
            Mock Get-PSDrive { [pscustomobject]@{ Free = 100GB; Used = 50GB } }
            Mock Get-Printer { @() }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\]'
        }

        It "Returns 1 with [-] output when the Print Spooler is stopped" {
            Mock Get-Service { [pscustomobject]@{ Status = 'Stopped'; StartType = 'Automatic' } }
            Mock Get-PSDrive { [pscustomobject]@{ Free = 100GB; Used = 50GB } }
            Mock Get-Printer { @() }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }

        It "Is idempotent: repeated health-check runs return consistent results" {
            Mock Get-Service { [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' } }
            Mock Get-PSDrive { [pscustomobject]@{ Free = 100GB; Used = 50GB } }
            Mock Get-Printer { @() }
            $firstRun = (Main *>&1 | Where-Object { $_ -is [int] })
            $secondRun = (Main *>&1 | Where-Object { $_ -is [int] })
            $firstRun | Should -Be 0
            $secondRun | Should -Be 0
        }

        It "Clears only stuck jobs through the ShouldProcess gate when -ClearStuckJobs is set" {
            Mock Get-Service { [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' } }
            Mock Get-PSDrive { [pscustomobject]@{ Free = 100GB; Used = 50GB } }
            Mock Get-Printer {
                @([pscustomobject]@{ Name = 'HP LaserJet'; PrinterStatus = 'Normal'; Type = 'Local'; Shared = $false })
            }
            Mock Get-PrintJob {
                @(
                    [pscustomobject]@{
                        Id            = 42
                        DocumentName  = 'Quarterly Report'
                        UserName      = 'alice'
                        PrinterName   = 'HP LaserJet'
                        SubmittedTime = (Get-Date).AddHours(-5)
                    },
                    [pscustomobject]@{
                        Id            = 43
                        DocumentName  = 'Fresh Doc'
                        UserName      = 'bob'
                        PrinterName   = 'HP LaserJet'
                        SubmittedTime = (Get-Date).AddMinutes(-5)
                    }
                )
            }
            Mock Remove-PrintJob { }
            $ClearStuckJobs = $true
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Remove-PrintJob -Times 1 -Exactly -Scope It `
                -Because "only jobs older than the threshold are stuck"
        }

        It "Returns 1 when printer enumeration fails outright" {
            Mock Get-Service { [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' } }
            Mock Get-PSDrive { [pscustomobject]@{ Free = 100GB; Used = 50GB } }
            Mock Get-Printer { throw "spooler RPC failure" }
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\]'
        }
    }
}
