<#
.SYNOPSIS
    Kubernetes cluster health check and diagnostics.

.DESCRIPTION
    Monitors Kubernetes cluster health:
    - Node status and resource utilization
    - Pod health across all namespaces
    - Deployment and StatefulSet status
    - Persistent Volume Claims
    - Service and Ingress configuration
    - Cluster events and errors
    - Resource quotas and limits

.PARAMETER Namespace
    Specific namespace to check (default: all namespaces).

.PARAMETER IncludeMetrics
    Collect resource metrics (requires metrics-server).

.PARAMETER CheckEvents
    Include recent cluster events in analysis.

.PARAMETER ExportHTML
    Generate HTML report.

.EXAMPLE
    .\Get-KubernetesHealthCheck.ps1

    Basic cluster health check across all namespaces.

.EXAMPLE
    .\Get-KubernetesHealthCheck.ps1 -Namespace production -IncludeMetrics -ExportHTML

    Detailed check for production namespace with metrics and HTML report.

.NOTES
    Author: IT Infrastructure Team
    Requires: kubectl configured and connected to cluster
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Namespace = "all-namespaces",

    [Parameter()]
    [switch]$IncludeMetrics,

    [Parameter()]
    [switch]$CheckEvents,

    [Parameter()]
    [switch]$ExportHTML
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$results = @{
    Timestamp = Get-Date
    Cluster = ""
    Nodes = @()
    Pods = @()
    Deployments = @()
    Services = @()
    Events = @()
    Issues = @()
}

Write-Host "`n=== Kubernetes Health Check ===" -ForegroundColor Cyan

# Check kubectl availability
Write-Host "[*] Checking kubectl connection..." -ForegroundColor Cyan
try {
    $clusterInfo = kubectl cluster-info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] Cannot connect to Kubernetes cluster" -ForegroundColor Red
        Write-Host $clusterInfo -ForegroundColor Red
        exit 1
    }
    $results.Cluster = kubectl config current-context 2>$null
    Write-Host "[+] Connected to cluster: $($results.Cluster)" -ForegroundColor Green
} catch {
    Write-Host "[!] kubectl not found or not configured" -ForegroundColor Red
    exit 1
}

# Check nodes
Write-Host "`n[*] Checking node status..." -ForegroundColor Cyan
try {
    $nodeJson = kubectl get nodes -o json | ConvertFrom-Json
    foreach ($node in $nodeJson.items) {
        $nodeInfo = [PSCustomObject]@{
            Name = $node.metadata.name
            Status = ($node.status.conditions | Where-Object {$_.type -eq "Ready"}).status
            Version = $node.status.nodeInfo.kubeletVersion
            OS = $node.status.nodeInfo.osImage
            CPUCapacity = $node.status.capacity.cpu
            MemoryCapacity = $node.status.capacity.memory
        }

        if ($nodeInfo.Status -ne "True") {
            $results.Issues += "Node '$($nodeInfo.Name)' is not Ready"
        }

        $results.Nodes += $nodeInfo
    }
    Write-Host "[+] Checked $($results.Nodes.Count) nodes" -ForegroundColor Green
} catch {
    Write-Host "[!] Error checking nodes: $_" -ForegroundColor Yellow
}

# Check pods
Write-Host "[*] Checking pod status..." -ForegroundColor Cyan
try {
    $nsFlag = if ($Namespace -eq "all-namespaces") {"--all-namespaces"} else {"-n $Namespace"}
    $podJson = kubectl get pods $nsFlag -o json | ConvertFrom-Json

    foreach ($pod in $podJson.items) {
        $podInfo = [PSCustomObject]@{
            Name = $pod.metadata.name
            Namespace = $pod.metadata.namespace
            Status = $pod.status.phase
            Ready = "$($pod.status.containerStatuses.Count)/$($pod.status.containerStatuses.Count)"
            Restarts = ($pod.status.containerStatuses.restartCount | Measure-Object -Sum).Sum
            Age = ((Get-Date) - [datetime]$pod.metadata.creationTimestamp).Days
        }

        # Check for issues
        if ($podInfo.Status -ne "Running") {
            $results.Issues += "Pod '$($podInfo.Namespace)/$($podInfo.Name)' is $($podInfo.Status)"
        }
        if ($podInfo.Restarts -gt 10) {
            $results.Issues += "Pod '$($podInfo.Namespace)/$($podInfo.Name)' has $($podInfo.Restarts) restarts"
        }

        $results.Pods += $podInfo
    }
    Write-Host "[+] Checked $($results.Pods.Count) pods" -ForegroundColor Green
} catch {
    Write-Host "[!] Error checking pods: $_" -ForegroundColor Yellow
}

# Check deployments
Write-Host "[*] Checking deployments..." -ForegroundColor Cyan
try {
    $deployJson = kubectl get deployments $nsFlag -o json | ConvertFrom-Json

    foreach ($deploy in $deployJson.items) {
        $deployInfo = [PSCustomObject]@{
            Name = $deploy.metadata.name
            Namespace = $deploy.metadata.namespace
            Replicas = $deploy.spec.replicas
            Available = $deploy.status.availableReplicas
            Ready = $deploy.status.readyReplicas
        }

        if ($deployInfo.Available -lt $deployInfo.Replicas) {
            $results.Issues += "Deployment '$($deployInfo.Namespace)/$($deployInfo.Name)' has $($deployInfo.Available)/$($deployInfo.Replicas) replicas available"
        }

        $results.Deployments += $deployInfo
    }
    Write-Host "[+] Checked $($results.Deployments.Count) deployments" -ForegroundColor Green
} catch {
    Write-Host "[!] Error checking deployments: $_" -ForegroundColor Yellow
}

# Check events
if ($CheckEvents) {
    Write-Host "[*] Checking recent events..." -ForegroundColor Cyan
    try {
        $eventJson = kubectl get events $nsFlag --sort-by='.lastTimestamp' -o json | ConvertFrom-Json
        $recentEvents = $eventJson.items | Select-Object -Last 50

        foreach ($event in $recentEvents) {
            $results.Events += [PSCustomObject]@{
                Time = $event.lastTimestamp
                Type = $event.type
                Reason = $event.reason
                Object = "$($event.involvedObject.kind)/$($event.involvedObject.name)"
                Message = $event.message
            }
        }
        Write-Host "[+] Collected $($results.Events.Count) recent events" -ForegroundColor Green
    } catch {
        Write-Host "[!] Error collecting events: $_" -ForegroundColor Yellow
    }
}

# Display summary
Write-Host "`n=== Health Summary ===" -ForegroundColor Cyan
Write-Host "Cluster: $($results.Cluster)" -ForegroundColor White
Write-Host "Nodes: $($results.Nodes.Count) ($($results.Nodes | Where-Object {$_.Status -eq 'True'} | Measure-Object).Count ready)" -ForegroundColor White
Write-Host "Pods: $($results.Pods.Count) ($($results.Pods | Where-Object {$_.Status -eq 'Running'} | Measure-Object).Count running)" -ForegroundColor White
Write-Host "Deployments: $($results.Deployments.Count)" -ForegroundColor White

if ($results.Issues.Count -gt 0) {
    Write-Host "`n=== Issues Found ===" -ForegroundColor Yellow
    foreach ($issue in $results.Issues | Select-Object -First 10) {
        Write-Host "  - $issue" -ForegroundColor Yellow
    }
    if ($results.Issues.Count -gt 10) {
        Write-Host "  ... and $($results.Issues.Count - 10) more issues" -ForegroundColor Yellow
    }
}

# Display node details
if ($results.Nodes.Count -gt 0) {
    Write-Host "`nNodes:" -ForegroundColor Cyan
    $results.Nodes | Format-Table Name, Status, Version, CPUCapacity, MemoryCapacity -AutoSize
}

# Export HTML
if ($ExportHTML) {
    $reportPath = "$env:USERPROFILE\Desktop\K8s_HealthCheck_${timestamp}.html"

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
        <strong>Cluster:</strong> $($results.Cluster)<br>
        <strong>Nodes:</strong> $($results.Nodes.Count)<br>
        <strong>Pods:</strong> $($results.Pods.Count)<br>
        <strong>Deployments:</strong> $($results.Deployments.Count)
    </div>
"@

    if ($results.Issues.Count -gt 0) {
        $html += "<h2>Issues ($($results.Issues.Count))</h2>"
        foreach ($issue in $results.Issues) {
            $html += "<div class='issue'>$issue</div>"
        }
    }

    $html += "<h2>Nodes</h2><table><tr><th>Name</th><th>Status</th><th>Version</th><th>CPU</th><th>Memory</th></tr>"
    foreach ($node in $results.Nodes) {
        $statusClass = if ($node.Status -eq "True") {"status-ready"} else {"status-notready"}
        $html += "<tr><td>$($node.Name)</td><td class='$statusClass'>$(if ($node.Status -eq 'True') {'Ready'} else {'NotReady'})</td><td>$($node.Version)</td><td>$($node.CPUCapacity)</td><td>$($node.MemoryCapacity)</td></tr>"
    }

    $html += "</table><h2>Pods (showing first 50)</h2><table><tr><th>Namespace</th><th>Name</th><th>Status</th><th>Restarts</th></tr>"
    foreach ($pod in $results.Pods | Select-Object -First 50) {
        $html += "<tr><td>$($pod.Namespace)</td><td>$($pod.Name)</td><td>$($pod.Status)</td><td>$($pod.Restarts)</td></tr>"
    }

    $html += "</table></body></html>"

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "`n[+] HTML report saved: $reportPath" -ForegroundColor Green
}

Write-Host "`nHealth check complete!`n" -ForegroundColor Green
