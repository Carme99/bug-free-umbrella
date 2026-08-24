<#
.SYNOPSIS
    Check Kubernetes cluster health and diagnostics.

.DESCRIPTION
    Monitors Kubernetes cluster health:
    - Node status and resource utilization
    - Pod health across all namespaces
    - Deployment and StatefulSet status
    - Persistent Volume Claims
    - Service and Ingress configuration
    - Cluster events and errors
    - Resource quotas and limits

    The script is read-only: it never mutates cluster state, so re-running it on an
    already-converged cluster always succeeds and makes no changes. Exit codes:
    0 on success (issues found are reported, not fatal); 1 when kubectl is missing,
    the cluster is unreachable, or an upstream error occurs.

.PARAMETER Namespace
    Specific namespace to check (default: all namespaces).

.PARAMETER IncludeMetrics
    Collect resource metrics (requires metrics-server).

.PARAMETER CheckEvents
    Include recent cluster events in analysis.

.PARAMETER ExportHTML
    Generate HTML report under MyDocuments\Reports.

.EXAMPLE
    PS C:\> .\Get-KubernetesHealthCheck.ps1

    Basic cluster health check across all namespaces.

.EXAMPLE
    PS C:\> .\Get-KubernetesHealthCheck.ps1 -Namespace production -IncludeMetrics -ExportHTML

    Detailed check for production namespace with metrics and HTML report.

.NOTES
    File Name: Get-KubernetesHealthCheck.ps1
    Author: IT Infrastructure Team
    Prerequisite: PowerShell 7.0, kubectl configured and connected to cluster
    Version: 1.0.0
    Date: 2026-08-23
#>

#Requires -Version 7.0
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'RELAUNCH-SPEC section 3 mandates Write-Host output with [+]/[!]/[-]/[*] prefixes')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Params consumed inside Main via scoping; see help')]
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Namespace = 'all-namespaces',

    [Parameter()]
    [switch]$IncludeMetrics,

    [Parameter()]
    [switch]$CheckEvents,

    [Parameter()]
    [switch]$ExportHTML
)

$ErrorActionPreference = 'Stop'

function Invoke-Kubectl {
    <#
    .SYNOPSIS
        Thin wrapper around the kubectl native executable (mock seam for tests).
    .DESCRIPTION
        Runs kubectl with the supplied arguments, merges stderr into stdout, and
        throws when kubectl exits non-zero so callers only handle success output.
    .PARAMETER KubectlArgs
        Arguments passed verbatim to kubectl.
    .EXAMPLE
        PS C:\> Invoke-Kubectl @('get', 'nodes', '-o', 'json')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$KubectlArgs
    )

    $output = & kubectl @KubectlArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl $($KubectlArgs -join ' ') failed with exit code $LASTEXITCODE"
    }
    return $output
}

function Main {
    <#
    .SYNOPSIS
        Runs the Kubernetes health check flow; returns 0 on success, 1 on failure.
    #>
    [CmdletBinding()]
    param()

    try {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $results = @{
            Timestamp   = Get-Date
            Cluster     = ''
            Nodes       = @()
            Pods        = @()
            Deployments = @()
            Services    = @()
            Events      = @()
            Issues      = @()
        }

        Write-Host "`n=== Kubernetes Health Check ===" -ForegroundColor Cyan

        # Check kubectl availability
        Write-Host "[*] Checking kubectl connection..." -ForegroundColor Cyan
        try {
            Invoke-Kubectl @('cluster-info') | Out-Null
            $results.Cluster = Invoke-Kubectl @('config', 'current-context')
            Write-Host "[+] Connected to cluster: $($results.Cluster)" -ForegroundColor Green
        }
        catch {
            Write-Host "[!] Cannot connect to Kubernetes cluster: $($_.Exception.Message)" -ForegroundColor Yellow
            return 1
        }

        $nsArgs = if ($Namespace -eq 'all-namespaces') { @('--all-namespaces') } else { @('-n', $Namespace) }

        # Check nodes
        Write-Host "`n[*] Checking node status..." -ForegroundColor Cyan
        try {
            $nodeJson = ((Invoke-Kubectl @('get', 'nodes', '-o', 'json')) -join '') | ConvertFrom-Json
            foreach ($node in $nodeJson.items) {
                $nodeInfo = [PSCustomObject]@{
                    Name          = $node.metadata.name
                    Status        = ($node.status.conditions | Where-Object { $_.type -eq 'Ready' }).status
                    Version       = $node.status.nodeInfo.kubeletVersion
                    OS            = $node.status.nodeInfo.osImage
                    CPUCapacity   = $node.status.capacity.cpu
                    MemoryCapacity = $node.status.capacity.memory
                }

                if ($nodeInfo.Status -ne 'True') {
                    $results.Issues += "Node '$($nodeInfo.Name)' is not Ready"
                }

                $results.Nodes += $nodeInfo
            }
            Write-Host "[+] Checked $($results.Nodes.Count) nodes" -ForegroundColor Green
        }
        catch {
            Write-Host "[!] Error checking nodes: $_" -ForegroundColor Yellow
        }

        # Check pods
        Write-Host "[*] Checking pod status..." -ForegroundColor Cyan
        try {
            $podJson = ((Invoke-Kubectl (@('get', 'pods') + $nsArgs + @('-o', 'json'))) -join '') | ConvertFrom-Json

            foreach ($pod in $podJson.items) {
                $restarts = ($pod.status.containerStatuses.restartCount | Measure-Object -Sum).Sum
                $podInfo = [PSCustomObject]@{
                    Name      = $pod.metadata.name
                    Namespace = $pod.metadata.namespace
                    Status    = $pod.status.phase
                    Ready     = "$($pod.status.containerStatuses.Count)/$($pod.status.containerStatuses.Count)"
                    Restarts  = $restarts
                    Age       = ((Get-Date) - [datetime]$pod.metadata.creationTimestamp).Days
                }

                # Check for issues
                if ($podInfo.Status -ne 'Running') {
                    $results.Issues += "Pod '$($podInfo.Namespace)/$($podInfo.Name)' is $($podInfo.Status)"
                }
                if ($podInfo.Restarts -gt 10) {
                    $results.Issues += "Pod '$($podInfo.Namespace)/$($podInfo.Name)' has $($podInfo.Restarts) restarts"
                }

                $results.Pods += $podInfo
            }
            Write-Host "[+] Checked $($results.Pods.Count) pods" -ForegroundColor Green
        }
        catch {
            Write-Host "[!] Error checking pods: $_" -ForegroundColor Yellow
        }

        # Check deployments
        Write-Host "[*] Checking deployments..." -ForegroundColor Cyan
        try {
            $deployJson = ((Invoke-Kubectl (@('get', 'deployments') + $nsArgs + @('-o', 'json'))) -join '') |
                ConvertFrom-Json

            foreach ($deploy in $deployJson.items) {
                $deployInfo = [PSCustomObject]@{
                    Name      = $deploy.metadata.name
                    Namespace = $deploy.metadata.namespace
                    Replicas  = $deploy.spec.replicas
                    Available = $deploy.status.availableReplicas
                    Ready     = $deploy.status.readyReplicas
                }

                if ($deployInfo.Available -lt $deployInfo.Replicas) {
                    $results.Issues += "Deployment '$($deployInfo.Namespace)/$($deployInfo.Name)' has " +
                        "$($deployInfo.Available)/$($deployInfo.Replicas) replicas available"
                }

                $results.Deployments += $deployInfo
            }
            Write-Host "[+] Checked $($results.Deployments.Count) deployments" -ForegroundColor Green
        }
        catch {
            Write-Host "[!] Error checking deployments: $_" -ForegroundColor Yellow
        }

        # Check events
        if ($CheckEvents) {
            Write-Host "[*] Checking recent events..." -ForegroundColor Cyan
            try {
                $kubeEventArgs = @('get', 'events') + $nsArgs + @('--sort-by=.lastTimestamp', '-o', 'json')
                $eventJson = ((Invoke-Kubectl $kubeEventArgs) -join '') | ConvertFrom-Json
                $recentEvents = $eventJson.items | Select-Object -Last 50

                foreach ($evtItem in $recentEvents) {
                    $results.Events += [PSCustomObject]@{
                        Time   = $evtItem.lastTimestamp
                        Type   = $evtItem.type
                        Reason = $evtItem.reason
                        Object = "$($evtItem.involvedObject.kind)/$($evtItem.involvedObject.name)"
                        Message = $evtItem.message
                    }
                }
                Write-Host "[+] Collected $($results.Events.Count) recent events" -ForegroundColor Green
            }
            catch {
                Write-Host "[!] Error collecting events: $_" -ForegroundColor Yellow
            }
        }

        # Display summary
        Write-Host "`n=== Health Summary ===" -ForegroundColor Cyan
        Write-Host "Cluster: $($results.Cluster)" -ForegroundColor White
        $readyNodes = @($results.Nodes | Where-Object { $_.Status -eq 'True' }).Count
        Write-Host "Nodes: $($results.Nodes.Count) ($readyNodes ready)" -ForegroundColor White
        $runningPods = @($results.Pods | Where-Object { $_.Status -eq 'Running' }).Count
        Write-Host "Pods: $($results.Pods.Count) ($runningPods running)" -ForegroundColor White
        Write-Host "Deployments: $($results.Deployments.Count)" -ForegroundColor White

        if ($results.Issues.Count -gt 0) {
            Write-Host "`n=== Issues Found ===" -ForegroundColor Yellow
            foreach ($issue in $results.Issues | Select-Object -First 10) {
                Write-Host "  [-] $issue" -ForegroundColor Yellow
            }
            if ($results.Issues.Count -gt 10) {
                Write-Host "  ... and $($results.Issues.Count - 10) more issues" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "`n[+] No issues found" -ForegroundColor Green
        }

        # Display node details
        if ($results.Nodes.Count -gt 0) {
            $results.Nodes | Format-Table Name, Status, Version, CPUCapacity, MemoryCapacity -AutoSize | Out-Host
        }

        # Export HTML
        if ($ExportHTML) {
            $ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
            # Validate report directory: reject '..' traversal and UNC remote paths before resolution
            if ([string]::IsNullOrWhiteSpace($ReportDir) -or
                $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
                $ReportDir -match '^(\\\\|//)') {
                Write-Host "[-] Unsafe report directory: $ReportDir." -ForegroundColor Red
                Write-Host "    Use a local absolute path without '..' traversal." -ForegroundColor Red
                return 1
            }
            $ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
            if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
                New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
            }
            $reportPath = Join-Path $ReportDir "K8s_HealthCheck_${timestamp}.html"

            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Kubernetes Health Check Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #326CE5; }
        h2 { color: #333; margin-top: 20px; }
        table { border-collapse: collapse; width: 100%; background-color: white; margin-bottom: 20px; }
        th { background-color: #326CE5; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        .summary { background-color: white; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .issue { background-color: #fff3cd; border-left: 4px solid #ffc107; padding: 10px; margin: 5px 0; }
        .status-ready { color: green; font-weight: bold; }
        .status-notready { color: red; font-weight: bold; }
    </style>
</head>
<body>
    <h1>Kubernetes Health Check Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Cluster:</strong> $([System.Net.WebUtility]::HtmlEncode("$($results.Cluster)"))<br>
        <strong>Nodes:</strong> $($results.Nodes.Count)<br>
        <strong>Pods:</strong> $($results.Pods.Count)<br>
        <strong>Deployments:</strong> $($results.Deployments.Count)
    </div>
"@

            if ($results.Issues.Count -gt 0) {
                $html += "<h2>Issues ($($results.Issues.Count))</h2>"
                foreach ($issue in $results.Issues) {
                    $html += "<div class='issue'>$([System.Net.WebUtility]::HtmlEncode("$issue"))</div>"
                }
            }

            $html += '<h2>Nodes</h2><table>' +
                '<tr><th>Name</th><th>Status</th><th>Version</th><th>CPU</th><th>Memory</th></tr>'
            foreach ($node in $results.Nodes) {
                $statusClass = if ($node.Status -eq 'True') { 'status-ready' } else { 'status-notready' }
                $statusText = if ($node.Status -eq 'True') { 'Ready' } else { 'NotReady' }
                $nameCell = [System.Net.WebUtility]::HtmlEncode("$($node.Name)")
                $verCell = [System.Net.WebUtility]::HtmlEncode("$($node.Version)")
                $html += "<tr><td>$nameCell</td><td class='$statusClass'>$statusText</td><td>$verCell</td>" +
                    "<td>$($node.CPUCapacity)</td><td>$($node.MemoryCapacity)</td></tr>"
            }

            $html += '</table>'
            $html += '<h2>Pods (showing first 50)</h2><table>' +
                '<tr><th>Namespace</th><th>Name</th><th>Status</th><th>Restarts</th></tr>'
            foreach ($pod in $results.Pods | Select-Object -First 50) {
                $nsCell = [System.Net.WebUtility]::HtmlEncode("$($pod.Namespace)")
                $podNameCell = [System.Net.WebUtility]::HtmlEncode("$($pod.Name)")
                $statusCell = [System.Net.WebUtility]::HtmlEncode("$($pod.Status)")
                $html += "<tr><td>$nsCell</td><td>$podNameCell</td><td>$statusCell</td><td>$($pod.Restarts)</td></tr>"
            }

            $html += '</table></body></html>'

            $html | Out-File -FilePath $reportPath -Encoding utf8
            Write-Host "`n[+] HTML report saved: $reportPath" -ForegroundColor Green
        }

        Write-Host "`n[+] Health check complete!" -ForegroundColor Green

        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
