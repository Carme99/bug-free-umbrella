#Requires -Modules Pester

<#
.SYNOPSIS
    Pester 5 tests for scripts/cloud/containers/Get-KubernetesHealthCheck.ps1.

.DESCRIPTION
    Offline tests: kubectl is never invoked directly; the script routes all native
    calls through Invoke-Kubectl, which these tests mock by name (Pester cannot mock
    native executables). Asserts Main return codes, output prefixes, issue detection,
    and idempotent behavior. No cluster connectivity required.

.NOTES
    File Name: Get-KubernetesHealthCheck.Tests.ps1
    Author: Bug-Free Umbrella
    Prerequisite: PowerShell 7.0, Pester 5.7.1
    Version: 1.0.0
    Date: 2026-08-23
#>

Describe "Get-KubernetesHealthCheck" {
    BeforeAll {
        $script:eap = $ErrorActionPreference
        $script:scriptPath = Join-Path $PSScriptRoot '../../../scripts/cloud/containers/Get-KubernetesHealthCheck.ps1'

        # Cluster payloads returned by the mocked wrapper as single-string JSON.
        $script:nodeJson = ConvertTo-Json -InputObject @{
            items = @(
                @{
                    metadata = @{ name = 'node-1' }
                    status   = @{
                        conditions = @(@{ type = 'Ready'; status = 'True' })
                        nodeInfo   = @{ kubeletVersion = 'v1.29.4'; osImage = 'Ubuntu 22.04' }
                        capacity   = @{ cpu = '8'; memory = '32Gi' }
                    }
                }
            )
        } -Depth 10 -Compress

        $script:podJsonRunning = ConvertTo-Json -InputObject @{
            items = @(
                @{
                    metadata = @{
                        name              = 'web-1'
                        namespace         = 'default'
                        creationTimestamp = '2026-08-01T00:00:00Z'
                    }
                    status = @{
                        phase             = 'Running'
                        containerStatuses = @(@{ restartCount = 2 })
                    }
                }
            )
        } -Depth 10 -Compress

        $script:podJsonPending = ConvertTo-Json -InputObject @{
            items = @(
                @{
                    metadata = @{
                        name              = 'stuck-1'
                        namespace         = 'default'
                        creationTimestamp = '2026-08-20T00:00:00Z'
                    }
                    status = @{
                        phase             = 'Pending'
                        containerStatuses = @(@{ restartCount = 25 })
                    }
                }
            )
        } -Depth 10 -Compress

        $script:deployJsonHealthy = ConvertTo-Json -InputObject @{
            items = @(
                @{
                    metadata = @{ name = 'web'; namespace = 'default' }
                    spec     = @{ replicas = 2 }
                    status   = @{ availableReplicas = 2; readyReplicas = 2 }
                }
            )
        } -Depth 10 -Compress

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $script:scriptPath

        Mock New-Item -ParameterFilter { $ItemType -eq 'Directory' } { }
        Mock Out-File { }

        # Default healthy-cluster dispatch for the wrapper mock.
        Mock Invoke-Kubectl {
            param([string[]]$KubectlArgs)
            switch ($KubectlArgs[0]) {
                'cluster-info' { @('Kubernetes control plane is running') }
                'config' { @('kind-kind') }
                'get' {
                    switch ($KubectlArgs[1]) {
                        'nodes' { $script:nodeJson }
                        'pods' { $script:podJsonRunning }
                        'deployments' { $script:deployJsonHealthy }
                        default { @() }
                    }
                }
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
            Where-Object { $_ -match '(?<![\w-])&\s+kubectl\b' -and $_ -notmatch 'function\s+Invoke-Kubectl' })
    }

    AfterAll {
        $ErrorActionPreference = $script:eap
    }

    Context "Help & Metadata" {
        It "declares File Name matching the disk filename" {
            $raw | Should -Match '(?m)^\s*File Name:\s*Get-KubernetesHealthCheck\.ps1\s*$'
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

        It "invokes the kubectl executable only inside the Invoke-Kubectl wrapper" {
            $nativeCalls.Count | Should -Be 1
            $calls = @($ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.CommandAst] }, $true) |
                Where-Object { $_.GetCommandName() -eq 'Invoke-Kubectl' })
            $calls.Count | Should -BeGreaterThan 5
        }

        It "keeps lines within 120 columns" {
            $long = @((Get-Content -LiteralPath $script:scriptPath) |
                Where-Object { $_.Length -gt 120 })
            $long | Should -BeNullOrEmpty
        }
    }

    Context "Behavior" {
        It "returns 0 on a healthy cluster and reports node/pod counts" {
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[\+\] Connected to cluster: kind-kind'
            $text | Should -Match '\[\+\] Checked 1 nodes'
            $text | Should -Match '\[\+\] Checked 1 pods'
            $text | Should -Match '\[\+\] No issues found'
        }

        It "flags non-running pods and excessive restarts as issues while still returning 0" {
            Mock Invoke-Kubectl {
                param([string[]]$KubectlArgs)
                if ($KubectlArgs[0] -eq 'config') { @('kind-kind') }
                elseif ($KubectlArgs[0] -eq 'cluster-info') { @('ok') }
                elseif ($KubectlArgs[1] -eq 'nodes') { $script:nodeJson }
                elseif ($KubectlArgs[1] -eq 'pods') { $script:podJsonPending }
                elseif ($KubectlArgs[1] -eq 'deployments') { $script:deployJsonHealthy }
                else { @() }
            }

            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match "Pod 'default/stuck-1' is Pending"
            $text | Should -Match "Pod 'default/stuck-1' has 25 restarts"
        }

        It "is idempotent: re-running against a healthy cluster succeeds with identical reads" {
            Main | Should -Be 0
            Main | Should -Be 0
            Should -Invoke Invoke-Kubectl -Times 10 -Exactly `
                -Because 'each run makes five read-only calls'
        }

        It "passes the namespace flag through when a specific namespace is requested" {
            $Namespace = 'production'
            Mock Invoke-Kubectl {
                param([string[]]$KubectlArgs)
                if ($KubectlArgs -contains '-n' -and $KubectlArgs -contains 'production') {
                    return @()
                }
                switch ($KubectlArgs[0]) {
                    'cluster-info' { @('ok') }
                    'get' { if ($KubectlArgs[1] -eq 'nodes') { $script:nodeJson } else { @() } }
                    default { @() }
                }
            }

            Main | Should -Be 0
            Should -Invoke Invoke-Kubectl -ParameterFilter { $KubectlArgs -contains '-n' } -Times 2 -Exactly
        }

        It "returns 1 and writes [!] output when the cluster is unreachable" {
            Mock Invoke-Kubectl { throw 'dial tcp: connection refused' }
            $out = Main *>&1
            $out | Where-Object { $_ -is [int] } | Should -Be 1
            ($out | Out-String) | Should -Match '\[!\] Cannot connect to Kubernetes cluster'
        }
    }
}
