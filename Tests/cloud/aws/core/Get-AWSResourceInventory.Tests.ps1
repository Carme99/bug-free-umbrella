#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for scripts/cloud/aws/core/Get-AWSResourceInventory.ps1.
.DESCRIPTION
    Validates help/metadata conformance, static syntax rules, and observable behavior
    of the AWS resource inventory script using fully mocked AWS PowerShell cmdlets.
    Runs offline on Linux pwsh; no network, credentials, or installed modules required.
.EXAMPLE
    PS C:\> Invoke-Pester -Path ./Tests/cloud/aws/core/Get-AWSResourceInventory.Tests.ps1
    Runs this test file.
.NOTES
    File Name   : Get-AWSResourceInventory.Tests.ps1
    Author      : Bug-Free Umbrella
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>

Describe 'Get-AWSResourceInventory' {
    BeforeAll {

        # Safe: the script's top-level guard skips Main when dot-sourced (spec section 3).
        $scriptPath = Join-Path $PSScriptRoot '../../../../scripts/cloud/aws/core/Get-AWSResourceInventory.ps1'
        . $scriptPath

        # Mock ALL external module cmdlets so nothing leaves the machine.
        # The AWS module is not installed offline: stub its cmdlets so Pester can mock them.
        function Set-AWSCredential { }
        function Set-DefaultAWSRegion { }
        function Get-EC2Instance { }
        function Get-S3Bucket { }
        function Get-RDSDBInstance { }
        function Get-LMFunctionList { }

        Mock Import-Module { }
        Mock Set-AWSCredential { }
        Mock Set-DefaultAWSRegion { }
        Mock Get-EC2Instance {
            @{
                Instances = @(
                    [pscustomobject]@{ State = [pscustomobject]@{ Name = 'running' } }
                    [pscustomobject]@{ State = [pscustomobject]@{ Name = 'stopped' } }
                )
            }
        }
        Mock Get-S3Bucket { @([pscustomobject]@{ BucketName = 'bucket-a' }) }
        Mock Get-RDSDBInstance { @([pscustomobject]@{ DBInstanceIdentifier = 'db-1' }) }
        Mock Get-LMFunctionList { @([pscustomobject]@{ FunctionName = 'fn-1' }) }

        $raw = [IO.File]::ReadAllText($scriptPath)
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    }

    Context 'Help & Metadata' {
        It 'Declares all five NOTES fields with relaunch values' {
            ($raw -match '(?m)^\.NOTES') | Should -BeTrue
            $raw | Should -Match '(?m)File Name\s*:\s*Get-AWSResourceInventory\.ps1'
            $raw | Should -Match '(?m)Author\s*:\s*\S+'
            $raw | Should -Match '(?m)Prerequisite\s*:\s*PowerShell 7\.0'
            $raw | Should -Match '(?m)Version\s*:\s*1\.0\.0'
            $raw | Should -Match '(?m)Date\s*:\s*2026-08-23'
        }

        It 'Has one PARAMETER entry per declared parameter' {
            $paramNames = @('Region', 'ProfileName', 'ExportHTML')
            foreach ($name in $paramNames) {
                $raw | Should -Match "(?m)\.PARAMETER\s+$name"
                $raw | Should -Match "\[.*\]\`$$name"
            }
        }

        It 'Provides at least two examples with PS prompts' {
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($raw, '(?m)^\s*PS C:\\>')).Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $errors.Count | Should -Be 0
        }

        It 'Uses CmdletBinding, Main function, and dot-source guard' {
            $raw | Should -Match '\[CmdletBinding\(\)\]'
            $raw | Should -Match '(?m)function Main\b'
            $raw | Should -Match 'if \(\$MyInvocation\.InvocationName -ne ''\.''\) \{ exit \(Main\) \}'
        }

        It 'Contains no PS7-only operators (no #Requires opt-out)' {
            ($raw -match '\?\?') | Should -BeFalse
            ($raw -match '\|\|') | Should -BeFalse
            ($raw -match '&&') | Should -BeFalse
        }

        It 'Is UTF-8 with BOM and CRLF line endings' {
            $bytes = [IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0], $bytes[1], $bytes[2]) | Should -Be (0xEF, 0xBB, 0xBF)
            ($raw -replace "`r`n", '').Contains("`n") | Should -BeFalse
        }
    }

    Context 'Behavior' {
        It 'Inventories all four services and returns 0' {
            $out = Main *>&1
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Found 2 EC2 instances \(1 running\)'
            $text | Should -Match '\[\+\] Found 1 S3 buckets'
            $text | Should -Match '\[\+\] Found 1 RDS instances'
            $text | Should -Match '\[\+\] Found 1 Lambda functions'
            $text | Should -Match '\[\+\] Inventory complete'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            Should -Invoke Get-EC2Instance -Times 1 -Exactly
            Should -Invoke Get-S3Bucket -Times 1 -Exactly
            Should -Invoke Get-RDSDBInstance -Times 1 -Exactly
            Should -Invoke Get-LMFunctionList -Times 1 -Exactly
        }

        It 'Connects to the requested region without mutating anything' {
            Main | Should -Be 0
            Should -Invoke Set-DefaultAWSRegion -Times 1 -Exactly -ParameterFilter { $Region -eq 'us-east-1' }
            Should -Invoke Set-AWSCredential -Times 0 -Exactly -Because 'no profile was supplied'
        }

        It 'Uses the named credential profile when ProfileName is set' {
            $ProfileName = 'prod'
            try {
                Main | Should -Be 0
                Should -Invoke Set-AWSCredential -Times 1 -Exactly -ParameterFilter { $ProfileName -eq 'prod' }
            }
            finally {
                $ProfileName = $null
            }
        }

        It 'Returns 1 with [-] output when the AWS module cannot be imported' {
            Mock Import-Module { throw 'module not found' }
            $out = Main *>&1
            ($out | Out-String) | Should -Match '\[-\] Error: module not found'
            $out | Where-Object { $_ -is [int] } | Should -Be 1
        }

        It 'Is idempotent: repeated runs are read-only and always succeed' {
            Main | Should -Be 0
            Main | Should -Be 0
            Should -Invoke Get-EC2Instance -Times 2 -Exactly -Because 'one inventory query per run'
        }
    }
}
