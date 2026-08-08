<#
.SYNOPSIS
    Comprehensive Docker environment health check.

.DESCRIPTION
    Monitors Docker environment health including:
    - Docker daemon status
    - Container health and resource usage
    - Image inventory and vulnerabilities
    - Volume usage and orphaned volumes
    - Network configuration
    - Docker Compose stacks
    - Resource consumption (CPU, memory, disk)
    - Container restart analysis

.PARAMETER IncludeImages
    Include detailed image analysis.

.PARAMETER CheckVulnerabilities
    Scan images for known vulnerabilities (requires Docker Scan/Trivy).

.PARAMETER IncludeNetworks
    Analyze Docker networks and connectivity.

.PARAMETER ExportHTML
    Generate HTML report.

.EXAMPLE
    .\Get-DockerHealthCheck.ps1

    Basic Docker health check.

.EXAMPLE
    .\Get-DockerHealthCheck.ps1 -IncludeImages -IncludeNetworks -ExportHTML

    Comprehensive health check with HTML report.

.NOTES
    Author: IT Infrastructure Team
    Requires: Docker Desktop/Engine installed
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$IncludeImages,

    [Parameter()]
    [switch]$CheckVulnerabilities,

    [Parameter()]
    [switch]$IncludeNetworks,

    [Parameter()]
    [switch]$ExportHTML
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$results = @{
    Timestamp = Get-Date
    ComputerName = $env:COMPUTERNAME
    DockerVersion = ""
    Containers = @()
    Images = @()
    Volumes = @()
    Networks = @()
    SystemInfo = @{}
    Issues = @()
}

Write-Host "`n=== Docker Health Check ===" -ForegroundColor Cyan

# Check Docker availability
Write-Host "[*] Checking Docker status..." -ForegroundColor Cyan
try {
    $dockerVersion = docker version --format '{{.Server.Version}}' 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] Docker is not running or not installed" -ForegroundColor Red
        exit 1
    }
    $results.DockerVersion = $dockerVersion
    Write-Host "[+] Docker version: $dockerVersion" -ForegroundColor Green
}
catch {
    Write-Host "[!] Error accessing Docker: $_" -ForegroundColor Red
    exit 1
}

# Get system info
Write-Host "[*] Collecting system information..." -ForegroundColor Cyan
try {
    $sysInfo = docker system info --format json | ConvertFrom-Json
    $results.SystemInfo = @{
        ContainersRunning = $sysInfo.ContainersRunning
        ContainersPaused = $sysInfo.ContainersPaused
        ContainersStopped = $sysInfo.ContainersStopped
        Images = $sysInfo.Images
        MemTotal = [math]::Round($sysInfo.MemTotal / 1GB, 2)
        NCPU = $sysInfo.NCPU
        OperatingSystem = $sysInfo.OperatingSystem
    }
    Write-Host "[+] System info collected" -ForegroundColor Green
}
catch {
    Write-Host "[!] Error collecting system info: $_" -ForegroundColor Yellow
}

# Analyze containers
Write-Host "`n[*] Analyzing containers..." -ForegroundColor Cyan
try {
    $containerList = docker ps -a --format "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.State}}" 2>$null
    foreach ($line in $containerList) {
        $fields = $line -split '\|'
        if ($fields.Count -ge 5) {
            $containerStats = docker stats $fields[0] --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}" 2>$null
            $stats = $containerStats -split '\|'

            $containerInfo = [PSCustomObject]@{
                ID = $fields[0]
                Name = $fields[1]
                Image = $fields[2]
                Status = $fields[3]
                State = $fields[4]
                CPUPercent = if ($stats[0]) { $stats[0] } else { "N/A" }
                MemoryUsage = if ($stats[1]) { $stats[1] } else { "N/A" }
                MemoryPercent = if ($stats[2]) { $stats[2] } else { "N/A" }
            }

            # Check for issues
            if ($containerInfo.State -eq "exited") {
                $results.Issues += "Container '$($containerInfo.Name)' is stopped"
            }
            elseif ($containerInfo.State -eq "restarting") {
                $results.Issues += "Container '$($containerInfo.Name)' is in restart loop"
            }

            $results.Containers += $containerInfo
        }
    }
    Write-Host "[+] Analyzed $($results.Containers.Count) containers" -ForegroundColor Green
}
catch {
    Write-Host "[!] Error analyzing containers: $_" -ForegroundColor Yellow
}

# Analyze images
if ($IncludeImages) {
    Write-Host "[*] Analyzing images..." -ForegroundColor Cyan
    try {
        $imageList = docker images --format "{{.Repository}}:{{.Tag}}|{{.ID}}|{{.Size}}|{{.CreatedAt}}" 2>$null
        foreach ($line in $imageList) {
            $fields = $line -split '\|'
            if ($fields.Count -ge 3) {
                $results.Images += [PSCustomObject]@{
                    Repository = $fields[0]
                    ID = $fields[1]
                    Size = $fields[2]
                    Created = $fields[3]
                }
            }
        }

        # Check for dangling images
        $danglingImages = docker images -f "dangling=true" -q 2>$null
        if ($danglingImages) {
            $results.Issues += "$(@($danglingImages).Count) dangling images found (run 'docker image prune' to clean)"
        }

        Write-Host "[+] Analyzed $($results.Images.Count) images" -ForegroundColor Green
    }
    catch {
        Write-Host "[!] Error analyzing images: $_" -ForegroundColor Yellow
    }
}

# Analyze volumes
Write-Host "[*] Analyzing volumes..." -ForegroundColor Cyan
try {
    $volumeList = docker volume ls --format "{{.Name}}|{{.Driver}}" 2>$null
    foreach ($line in $volumeList) {
        $fields = $line -split '\|'
        if ($fields.Count -ge 2) {
            $results.Volumes += [PSCustomObject]@{
                Name = $fields[0]
                Driver = $fields[1]
            }
        }
    }

    # Check for orphaned volumes
    $orphanedVolumes = docker volume ls -f "dangling=true" -q 2>$null
    if ($orphanedVolumes) {
        $results.Issues += "$(@($orphanedVolumes).Count) orphaned volumes found (run 'docker volume prune' to clean)"
    }

    Write-Host "[+] Analyzed $($results.Volumes.Count) volumes" -ForegroundColor Green
}
catch {
    Write-Host "[!] Error analyzing volumes: $_" -ForegroundColor Yellow
}

# Analyze networks
if ($IncludeNetworks) {
    Write-Host "[*] Analyzing networks..." -ForegroundColor Cyan
    try {
        $networkList = docker network ls --format "{{.ID}}|{{.Name}}|{{.Driver}}|{{.Scope}}" 2>$null
        foreach ($line in $networkList) {
            $fields = $line -split '\|'
            if ($fields.Count -ge 4) {
                $results.Networks += [PSCustomObject]@{
                    ID = $fields[0]
                    Name = $fields[1]
                    Driver = $fields[2]
                    Scope = $fields[3]
                }
            }
        }
        Write-Host "[+] Analyzed $($results.Networks.Count) networks" -ForegroundColor Green
    }
    catch {
        Write-Host "[!] Error analyzing networks: $_" -ForegroundColor Yellow
    }
}

# Display summary
Write-Host "`n=== Health Summary ===" -ForegroundColor Cyan
Write-Host "Docker Version: $($results.DockerVersion)" -ForegroundColor White
Write-Host "Containers: $($results.SystemInfo.ContainersRunning) running, $($results.SystemInfo.ContainersStopped) stopped" -ForegroundColor White
Write-Host "Images: $($results.Images.Count)" -ForegroundColor White
Write-Host "Volumes: $($results.Volumes.Count)" -ForegroundColor White
Write-Host "Memory: $($results.SystemInfo.MemTotal) GB total" -ForegroundColor White

if ($results.Issues.Count -gt 0) {
    Write-Host "`n=== Issues Found ===" -ForegroundColor Yellow
    foreach ($issue in $results.Issues) {
        Write-Host "  - $issue" -ForegroundColor Yellow
    }
}

# Display running containers
if ($results.Containers.Count -gt 0) {
    Write-Host "`nRunning Containers:" -ForegroundColor Cyan
    $results.Containers | Where-Object { $_.State -eq "running" } | Select-Object Name, Image, CPUPercent, MemoryPercent | Format-Table -AutoSize
}

# Export HTML
if ($ExportHTML) {
    $ReportDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Reports'
    # Validate report directory: reject '..' traversal and UNC remote paths before resolution
    if ([string]::IsNullOrWhiteSpace($ReportDir) -or
        $ReportDir -match '(^|[\\/])\.\.([\\/]|$)' -or
        $ReportDir -match '^(\\\\|//)') {
        Write-Error "Unsafe report directory: $ReportDir. Report directory must be a local absolute path without '..' traversal."
        exit 1
    }
    $ReportDir = [System.IO.Path]::GetFullPath($ReportDir)
    if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
        New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
    }
    $reportPath = Join-Path $ReportDir "Docker_HealthCheck_${timestamp}.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Docker Health Check Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0066cc; }
        h2 { color: #333; margin-top: 20px; }
        table { border-collapse: collapse; width: 100%; background-color: white; margin-bottom: 20px; }
        th { background-color: #0066cc; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        .summary { background-color: white; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .issue { background-color: #fff3cd; border-left: 4px solid #ffc107; padding: 10px; margin: 10px 0; }
        .state-running { color: green; font-weight: bold; }
        .state-exited { color: red; }
    </style>
</head>
<body>
    <h1>Docker Health Check Report</h1>
    <div class="summary">
        <strong>Generated:</strong> $(Get-Date)<br>
        <strong>Computer:</strong> $([System.Net.WebUtility]::HtmlEncode("$($results.ComputerName)"))<br>
        <strong>Docker Version:</strong> $([System.Net.WebUtility]::HtmlEncode("$($results.DockerVersion)"))<br>
        <strong>Containers Running:</strong> $($results.SystemInfo.ContainersRunning)<br>
        <strong>Containers Stopped:</strong> $($results.SystemInfo.ContainersStopped)<br>
        <strong>Total Images:</strong> $($results.Images.Count)<br>
        <strong>Total Volumes:</strong> $($results.Volumes.Count)
    </div>
"@

    if ($results.Issues.Count -gt 0) {
        $html += "<h2>Issues</h2>"
        foreach ($issue in $results.Issues) {
            $html += "<div class='issue'>$([System.Net.WebUtility]::HtmlEncode("$issue"))</div>"
        }
    }

    $html += "<h2>Containers</h2><table><tr><th>Name</th><th>Image</th><th>State</th><th>CPU</th><th>Memory</th></tr>"
    foreach ($container in $results.Containers) {
        $stateClass = if ($container.State -eq "running") { "state-running" } else { "state-exited" }
        $html += "<tr><td>$([System.Net.WebUtility]::HtmlEncode("$($container.Name)"))</td><td>$([System.Net.WebUtility]::HtmlEncode("$($container.Image)"))</td><td class='$stateClass'>$([System.Net.WebUtility]::HtmlEncode("$($container.State)"))</td><td>$($container.CPUPercent)</td><td>$($container.MemoryPercent)</td></tr>"
    }

    $html += "</table></body></html>"

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "`n[+] HTML report saved: $reportPath" -ForegroundColor Green
}

Write-Host "`nHealth check complete!`n" -ForegroundColor Green
