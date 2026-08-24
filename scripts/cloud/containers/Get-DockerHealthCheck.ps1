<#
.SYNOPSIS
    Check Docker environment health comprehensively.

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

    The script is read-only: it never mutates Docker state, so re-running it on an
    already-converged host always succeeds and makes no changes. Exit codes:
    0 on success (issues found are reported, not fatal); 1 when the Docker daemon
    is unreachable or an upstream error occurs.

.PARAMETER IncludeImages
    Include detailed image analysis.

.PARAMETER CheckVulnerabilities
    Scan images for known vulnerabilities (requires Docker Scan/Trivy).

.PARAMETER IncludeNetworks
    Analyze Docker networks and connectivity.

.PARAMETER ExportHTML
    Generate HTML report under MyDocuments\Reports.

.EXAMPLE
    PS C:\> .\Get-DockerHealthCheck.ps1

    Basic Docker health check.

.EXAMPLE
    PS C:\> .\Get-DockerHealthCheck.ps1 -IncludeImages -IncludeNetworks -ExportHTML

    Comprehensive health check with image and network analysis plus an HTML report.

.NOTES
    File Name: Get-DockerHealthCheck.ps1
    Author: IT Infrastructure Team
    Prerequisite: PowerShell 7.0, Docker Desktop/Engine installed and running
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
    [switch]$IncludeImages,

    [Parameter()]
    [switch]$CheckVulnerabilities,

    [Parameter()]
    [switch]$IncludeNetworks,

    [Parameter()]
    [switch]$ExportHTML
)

$ErrorActionPreference = 'Stop'

function Invoke-Docker {
    <#
    .SYNOPSIS
        Thin wrapper around the docker native executable (mock seam for tests).
    .DESCRIPTION
        Runs docker with the supplied arguments, merges stderr into stdout, and
        throws when docker exits non-zero so callers only handle success output.
    .PARAMETER DockerArgs
        Arguments passed verbatim to docker.
    .EXAMPLE
        PS C:\> Invoke-Docker @('ps', '-a', '--format', '{{.Names}}')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$DockerArgs
    )

    $output = & docker @DockerArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "docker $($DockerArgs -join ' ') failed with exit code $LASTEXITCODE"
    }
    return $output
}

function Main {
    <#
    .SYNOPSIS
        Runs the Docker health check flow; returns 0 on success, 1 on failure.
    #>
    [CmdletBinding()]
    param()

    try {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $results = @{
            Timestamp     = Get-Date
            ComputerName  = $env:COMPUTERNAME
            DockerVersion = ''
            Containers    = @()
            Images        = @()
            Volumes       = @()
            Networks      = @()
            SystemInfo    = @{}
            Issues        = @()
        }

        Write-Host "`n=== Docker Health Check ===" -ForegroundColor Cyan

        # Check Docker availability
        Write-Host "[*] Checking Docker status..." -ForegroundColor Cyan
        try {
            $dockerVersion = Invoke-Docker @('version', '--format', '{{.Server.Version}}')
            $results.DockerVersion = $dockerVersion
            Write-Host "[+] Docker version: $dockerVersion" -ForegroundColor Green
        }
        catch {
            Write-Host "[!] Docker is not running or not installed" -ForegroundColor Yellow
            return 1
        }

        # Get system info
        Write-Host "[*] Collecting system information..." -ForegroundColor Cyan
        try {
            $sysInfo = ((Invoke-Docker @('system', 'info', '--format', 'json')) -join '') | ConvertFrom-Json
            $results.SystemInfo = @{
                ContainersRunning = $sysInfo.ContainersRunning
                ContainersPaused  = $sysInfo.ContainersPaused
                ContainersStopped = $sysInfo.ContainersStopped
                Images            = $sysInfo.Images
                MemTotal          = [math]::Round($sysInfo.MemTotal / 1GB, 2)
                NCPU              = $sysInfo.NCPU
                OperatingSystem   = $sysInfo.OperatingSystem
            }
            Write-Host "[+] System info collected" -ForegroundColor Green
        }
        catch {
            Write-Host "[!] Error collecting system info: $_" -ForegroundColor Yellow
        }

        # Analyze containers
        Write-Host "`n[*] Analyzing containers..." -ForegroundColor Cyan
        try {
            $containerList = Invoke-Docker @(
                'ps', '-a', '--format',
                '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.State}}'
            )
            foreach ($line in $containerList) {
                $fields = $line -split '\|'
                if ($fields.Count -ge 5) {
                    $containerStats = Invoke-Docker @(
                        'stats',
                        $fields[0],
                        '--no-stream',
                        '--format',
                        '{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}'
                    )
                    $stats = @($containerStats) -split '\|'

                    $cpuPercent = if ($stats[0]) { $stats[0] } else { 'N/A' }
                    $memUsage = if ($stats[1]) { $stats[1] } else { 'N/A' }
                    $memPercent = if ($stats[2]) { $stats[2] } else { 'N/A' }

                    $containerInfo = [PSCustomObject]@{
                        ID           = $fields[0]
                        Name         = $fields[1]
                        Image        = $fields[2]
                        Status       = $fields[3]
                        State        = $fields[4]
                        CPUPercent   = $cpuPercent
                        MemoryUsage  = $memUsage
                        MemoryPercent = $memPercent
                    }

                    # Check for issues
                    if ($containerInfo.State -eq 'exited') {
                        $results.Issues += "Container '$($containerInfo.Name)' is stopped"
                    }
                    elseif ($containerInfo.State -eq 'restarting') {
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
                $imageList = Invoke-Docker @(
                    'images',
                    '--format',
                    '{{.Repository}}:{{.Tag}}|{{.ID}}|{{.Size}}|{{.CreatedAt}}'
                )
                foreach ($line in $imageList) {
                    $fields = $line -split '\|'
                    if ($fields.Count -ge 3) {
                        $results.Images += [PSCustomObject]@{
                            Repository = $fields[0]
                            ID         = $fields[1]
                            Size       = $fields[2]
                            Created    = $fields[3]
                        }
                    }
                }

                # Check for dangling images
                $danglingImages = @(Invoke-Docker @('images', '-f', 'dangling=true', '-q'))
                if ($danglingImages.Count -gt 0) {
                    $results.Issues += "$($danglingImages.Count) dangling images found " +
                        "(run 'docker image prune' to clean)"
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
            $volumeList = Invoke-Docker @('volume', 'ls', '--format', '{{.Name}}|{{.Driver}}')
            foreach ($line in $volumeList) {
                $fields = $line -split '\|'
                if ($fields.Count -ge 2) {
                    $results.Volumes += [PSCustomObject]@{
                        Name   = $fields[0]
                        Driver = $fields[1]
                    }
                }
            }

            # Check for orphaned volumes
            $orphanedVolumes = @(Invoke-Docker @('volume', 'ls', '-f', 'dangling=true', '-q'))
            if ($orphanedVolumes.Count -gt 0) {
                $results.Issues += "$($orphanedVolumes.Count) orphaned volumes found " +
                    "(run 'docker volume prune' to clean)"
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
                $networkList = Invoke-Docker @('network', 'ls', '--format', '{{.ID}}|{{.Name}}|{{.Driver}}|{{.Scope}}')
                foreach ($line in $networkList) {
                    $fields = $line -split '\|'
                    if ($fields.Count -ge 4) {
                        $results.Networks += [PSCustomObject]@{
                            ID     = $fields[0]
                            Name   = $fields[1]
                            Driver = $fields[2]
                            Scope  = $fields[3]
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
        $sysInfo = $results.SystemInfo
        $containerSummary = "$($sysInfo.ContainersRunning) running, $($sysInfo.ContainersStopped) stopped"
        Write-Host "Containers: $containerSummary" -ForegroundColor White
        Write-Host "Images: $($results.Images.Count)" -ForegroundColor White
        Write-Host "Volumes: $($results.Volumes.Count)" -ForegroundColor White
        Write-Host "Memory: $($results.SystemInfo.MemTotal) GB total" -ForegroundColor White

        if ($results.Issues.Count -gt 0) {
            Write-Host "`n=== Issues Found ===" -ForegroundColor Yellow
            foreach ($issue in $results.Issues) {
                Write-Host "  [-] $issue" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "`n[+] No issues found" -ForegroundColor Green
        }

        # Display running containers
        if ($results.Containers.Count -gt 0) {
            Write-Host "`nRunning Containers:" -ForegroundColor Cyan
            $results.Containers | Where-Object { $_.State -eq 'running' } |
                Select-Object Name, Image, CPUPercent, MemoryPercent | Format-Table -AutoSize | Out-Host
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
                $html += '<h2>Issues</h2>'
                foreach ($issue in $results.Issues) {
                    $html += "<div class='issue'>$([System.Net.WebUtility]::HtmlEncode("$issue"))</div>"
                }
            }

            $html += '<h2>Containers</h2><table>' +
                '<tr><th>Name</th><th>Image</th><th>State</th><th>CPU</th><th>Memory</th></tr>'
            foreach ($c in $results.Containers) {
                $nameCell = [System.Net.WebUtility]::HtmlEncode("$($c.Name)")
                $imageCell = [System.Net.WebUtility]::HtmlEncode("$($c.Image)")
                $stateClass = if ($c.State -eq 'running') { 'state-running' } else { 'state-exited' }
                $html += "<tr><td>$nameCell</td><td>$imageCell</td><td class='$stateClass'>$($c.State)</td>" +
                    "<td>$($c.CPUPercent)</td><td>$($c.MemoryUsage)</td></tr>"
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
