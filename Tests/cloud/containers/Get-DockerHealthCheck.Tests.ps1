#Requires -Modules Pester

<#
.SYNOPSIS
    Pester 5 tests for scripts/cloud/containers/Get-DockerHealthCheck.ps1.

.DESCRIPTION
    Offline tests: docker is never invoked directly; the script routes all native
    calls through Invoke-Docker, which these tests mock by name (Pester cannot mock
    native executables). Asserts Main return codes, output prefixes, issue detection,
    and idempotent behavior. No Docker daemon required.

.NOTES
    File Name: Get-DockerHealthCheck.Tests.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0, Pester 5.7.1
    Version: 1.0.0
    Date: 2026-08-23
#>

Describe "Get-DockerHealthCheck" {
    BeforeAll {
        $script:eap = $ErrorActionPreference
        $script:scriptPath = Join-Path $PSScriptRoot '../../../scripts/cloud/containers/Get-DockerHealthCheck.ps1'

        $script:sysInfoJson = ConvertTo-Json -InputObject @{
            ContainersRunning = 1
            ContainersPaused  = 0
            ContainersStopped = 1
            Images            = 42
            MemTotal          = 17179869184
            NCPU              = 8
            OperatingSystem   = 'Ubuntu 22.04'
        } -Depth 5 -Compress

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $script:scriptPath

        Mock New-Item -ParameterFilter { $ItemType -eq 'Directory' } { }
        Mock Out-File { }

        # Default mixed-state dispatch: one running container, one stopped.
        Mock Invoke-Docker {
            param([string[]]$DockerArgs)
            switch ($DockerArgs[0]) {
                'version' { @('24.0.7') }
                'system' { $script:sysInfoJson }
                'ps' {
                    @(
                        'abc123|web-1|nginx:latest|Up 5 minutes|running',
                        'def456|batch|alpine:3.19|Exited (0) 2 days ago|exited'
                    )
                }
                'stats' { @('0.35%|128MiB|1.20%') }
                'volume' { @('data-vol|local') }
                'network' { @() }
                'images' { @() }
                default { @() }
            }
        }

        # Static analysis inputs
        $tokens = $null
        $script:parseErrors = $null
        $script:ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:scriptPath, [ref]$tokens, [ref]$script:parseErrors)
        $script:paramBlock = $ast.Find(
            { param($a) $a -is [System.Management.Automation.Language.ParamBlockAst] }, $true)
        $script:paramNames = @($paramBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })

        $script:raw = [IO.File]::ReadAllText($script:scriptPath)
        $script:header = ($raw -split '\[CmdletBinding\(\)\]')[0]
        $script:bom = ([IO.File]::ReadAllBytes($script:scriptPath)[0..2]) -join ','
        $bareLf = 0
        for ($i = 1; $i -lt $raw.Length; $i++) {
            if ($raw[$i] -eq "`n" -and $raw[$i - 1] -ne "`r") { $bareLf++ }
        }
        $script:bareLfCount = $bareLf
        $script:exitStatements = @($ast.Find(
            { param($a) $a -is [System.Management.Automation.Language.ExitStatementAst] }, $true))
        $nativeCalls = @((Get-Content -LiteralPath $script:scriptPath) |
            Where-Object { $_ -match '(?<![\w-])&\s+docker\b' })
    }

    AfterAll {
        $ErrorActionPreference = $script:eap
    }

    Context "Help & Metadata" {
        It "declares File Name matching the disk filename" {
            $raw | Should -Match '(?m)^\s*File Name:\s*Get-DockerHealthCheck\.ps1\s*$'
        }

        It "declares Version 1.0.0 and Date 2026-08-23" {
            $raw | Should -Match '(?m)^\s*Version:\s*1\.0\.0\s*$'
            $raw | Should -Match '(?m)^\s*Date:\s*2026-08-23\s*$'
        }

        It "declares Author and PowerShell 7.0 prerequisite" {
            $raw | Should -Match '(?m)^\s*Author:\s*\S'
            $raw | Should -Match '(?m)^\s*Prerequisite:.*PowerShell 7\.0'
        }

        It "has one .PARAMETER per declared parameter, in param order" {
            $helpRegex = '(?m)^\s*\.PARAMETER\s+(\S+)'
            $helpParams = @([regex]::Matches($script:header, $helpRegex) |
                ForEach-Object { $_.Groups[1].Value })
            $helpParams | Should -Be $paramNames
        }

        It "binds comment-based help so Get-Help -Detailed renders fully" {
            $h = Get-Help -Name $script:scriptPath -Detailed
            $h.Synopsis | Should -Not -Match [regex]::Escape($script:scriptPath)
            @($h.examples.example).Count | Should -BeGreaterOrEqual 2
        }
        It "has at least two examples with PS C:\> prompts" {
            ($raw -split '\.EXAMPLE').Count - 1 | Should -BeGreaterOrEqual 2
            $raw | Should -Match 'PS C:\\>'
        }
    }

    Context "Syntax & Static" {
        It "parses with zero errors" {
            $parseErrors | Should -BeNullOrEmpty
        }

        It "is UTF-8 BOM with CRLF line endings" {
            $bom | Should -Be '239,187,191'
            $bareLfCount | Should -Be 0
        }

        It "uses exit only in the top-level dot-source guard" {
            $exitStatements.Count | Should -Be 1
            $guardLine = (Get-Content -LiteralPath $script:scriptPath)[$exitStatements[0].Extent.StartLineNumber - 1]
            $guardLine | Should -Match 'if \(\$MyInvocation\.InvocationName -ne'
        }

        It "invokes the docker executable only inside the Invoke-Docker wrapper" {
            $nativeCalls.Count | Should -Be 1
            $calls = @($ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.CommandAst] }, $true) |
                Where-Object { $_.GetCommandName() -eq 'Invoke-Docker' })
            $calls.Count | Should -BeGreaterThan 5
        }

        It "keeps lines within 120 columns" {
            $long = @((Get-Content -LiteralPath $script:scriptPath) |
                Where-Object { $_.Length -gt 120 })
            $long | Should -BeNullOrEmpty
        }
    }

    Context "Behavior" {
        It "returns 0 and reports the daemon version and container analysis" {
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Docker version: 24\.0\.7'
            $text | Should -Match '\[\+\] Analyzed 2 containers'
            $text | Should -Match '\[\+\] Analyzed 1 volumes'
        }

        It "flags exited containers as issues while still returning 0" {
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            ($out | Out-String) | Should -Match "Container 'batch' is stopped"
        }

        It "reports dangling images and orphaned volumes when image analysis is enabled" {
            Mock Invoke-Docker {
                param([string[]]$DockerArgs)
                if ($DockerArgs[0] -eq 'images') {
                    if ($DockerArgs -contains '-q') { return @('sha256dead', 'sha256beef') }
                    return @()
                }
                switch ($DockerArgs[0]) {
                    'version' { @('24.0.7') }
                    'system' { $script:sysInfoJson }
                    'ps' { @('abc123|web-1|nginx:latest|Up 5 minutes|running') }
                    'stats' { @('0.35%|128MiB|1.20%') }
                    'volume' { if ($DockerArgs -contains '-f') { return @('orphan-vol') }; return @('data-vol|local') }
                    'network' { @() }
                    default { @() }
                }
            }
            $IncludeImages = $true

            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '2 dangling images found'
            $text | Should -Match '1 orphaned volumes found'
        }

        It "is idempotent: re-running against a healthy daemon succeeds with identical reads" {
            Main | Should -Be 0
            Main | Should -Be 0
            Should -Invoke Invoke-Docker -Times 14 -Exactly `
                -Because 'each run makes seven read-only calls'
        }

        It "returns 1 and writes [!] output when the daemon is unreachable" {
            Mock Invoke-Docker { throw 'Cannot connect to the Docker daemon at unix:///var/run/docker.sock' }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[!\] Docker is not running or not installed'
        }
    }
}
