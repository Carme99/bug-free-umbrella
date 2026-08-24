<#
.SYNOPSIS
    Cleans up unused Docker resources and reports storage savings.
.DESCRIPTION
    Performs selective Docker cleanup: removes stopped containers, dangling images,
    unused volumes, and prunes the build cache. Each category is opt-in via its switch,
    or all at once with -Force. Disk usage is reported before and after cleanup.
    The script is idempotent: on an already-clean Docker installation every prune
    completes successfully (exit 0) and nothing further is removed.
    Supports -WhatIf / -Confirm; no resource is deleted without passing the
    ShouldProcess gate.
.PARAMETER RemoveStoppedContainers
    Remove all stopped containers (docker container prune -f).
.PARAMETER RemoveDanglingImages
    Remove dangling, untagged images (docker image prune -f).
.PARAMETER RemoveUnusedVolumes
    Remove volumes not used by any container (docker volume prune -f).
.PARAMETER PruneBuildCache
    Clean the Docker build cache (docker builder prune -f).
.PARAMETER Force
    Perform every cleanup category without selecting individual switches.
.EXAMPLE
    PS C:\> .\Optimize-DockerCleanup.ps1 -RemoveStoppedContainers -RemoveDanglingImages
    Removes stopped containers and dangling images only.
.EXAMPLE
    PS C:\> .\Optimize-DockerCleanup.ps1 -Force -WhatIf
    Shows what a full cleanup would remove without deleting anything.
.NOTES
    File Name   : Optimize-DockerCleanup.ps1
    Author      : IT Infrastructure Team
    Prerequisite: PowerShell 7.0
    Version     : 1.0.0
    Date        : 2026-08-23
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$RemoveStoppedContainers,
    [switch]$RemoveDanglingImages,
    [switch]$RemoveUnusedVolumes,
    [switch]$PruneBuildCache,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Analyzer warnings accepted: PSAvoidUsingWriteHost (spec section 3 mandates Write-Host prefix output)
# and PSReviewUnusedParameter (script params are consumed by Main via parent scope).

function Invoke-Docker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$DockerArgs
    )
    $output = & docker @DockerArgs 2>&1
    $code = $LASTEXITCODE
    foreach ($line in @($output)) {
        Write-Host $line -ForegroundColor Gray
    }
    return $code
}

function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-Host "[*] Checking current disk usage..." -ForegroundColor Cyan
        try {
            Invoke-Docker -DockerArgs @('system', 'df') | Out-Null
            Write-Host "[+] Retrieved current Docker disk usage" -ForegroundColor Green
        }
        catch {
            Write-Host "[!] Unable to get disk usage stats: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        $cleanedItems = @()
        $hadFailure = $false

        if ($RemoveStoppedContainers -or $Force) {
            Write-Host "[*] Removing stopped containers..." -ForegroundColor Cyan
            if ($PSCmdlet.ShouldProcess('Stopped Docker containers', 'Remove')) {
                $pruneResult = Invoke-Docker -DockerArgs @('container', 'prune', '-f')
                if ($pruneResult -eq 0) {
                    $cleanedItems += 'Stopped containers'
                    Write-Host "[+] Removed stopped containers" -ForegroundColor Green
                }
                else {
                    Write-Host "[-] Failed to remove stopped containers (exit $pruneResult)" -ForegroundColor Red
                    $hadFailure = $true
                }
            }
        }

        if ($RemoveDanglingImages -or $Force) {
            Write-Host "[*] Removing dangling images..." -ForegroundColor Cyan
            if ($PSCmdlet.ShouldProcess('Dangling Docker images', 'Remove')) {
                $pruneResult = Invoke-Docker -DockerArgs @('image', 'prune', '-f')
                if ($pruneResult -eq 0) {
                    $cleanedItems += 'Dangling images'
                    Write-Host "[+] Removed dangling images" -ForegroundColor Green
                }
                else {
                    Write-Host "[-] Failed to remove dangling images (exit $pruneResult)" -ForegroundColor Red
                    $hadFailure = $true
                }
            }
        }

        if ($RemoveUnusedVolumes -or $Force) {
            Write-Host "[*] Removing unused volumes..." -ForegroundColor Cyan
            if ($PSCmdlet.ShouldProcess('Unused Docker volumes', 'Remove')) {
                $pruneResult = Invoke-Docker -DockerArgs @('volume', 'prune', '-f')
                if ($pruneResult -eq 0) {
                    $cleanedItems += 'Unused volumes'
                    Write-Host "[+] Removed unused volumes" -ForegroundColor Green
                }
                else {
                    Write-Host "[-] Failed to remove unused volumes (exit $pruneResult)" -ForegroundColor Red
                    $hadFailure = $true
                }
            }
        }

        if ($PruneBuildCache -or $Force) {
            Write-Host "[*] Pruning build cache..." -ForegroundColor Cyan
            if ($PSCmdlet.ShouldProcess('Docker build cache', 'Prune')) {
                $pruneResult = Invoke-Docker -DockerArgs @('builder', 'prune', '-f')
                if ($pruneResult -eq 0) {
                    $cleanedItems += 'Build cache'
                    Write-Host "[+] Pruned build cache" -ForegroundColor Green
                }
                else {
                    Write-Host "[-] Failed to prune build cache (exit $pruneResult)" -ForegroundColor Red
                    $hadFailure = $true
                }
            }
        }

        Write-Host "[*] Checking disk usage after cleanup..." -ForegroundColor Cyan
        try {
            Invoke-Docker -DockerArgs @('system', 'df') | Out-Null
            Write-Host "[+] Retrieved post-cleanup Docker disk usage" -ForegroundColor Green
        }
        catch {
            Write-Host "[!] Could not get post-cleanup disk usage: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        Write-Host ""
        Write-Host "=== Cleanup Summary ===" -ForegroundColor Cyan
        Write-Host "Cleaned: $($cleanedItems -join ', ')" -ForegroundColor Green

        if ($hadFailure) {
            Write-Host "[-] Cleanup completed with failures" -ForegroundColor Red
            return 1
        }
        Write-Host "[+] Cleanup complete" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
}

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
