<#
.SYNOPSIS
    Clean up Docker resources and optimize storage.

.DESCRIPTION
    Performs Docker cleanup operations:
    - Remove stopped containers
    - Remove dangling images
    - Remove unused volumes
    - Remove unused networks
    - Prune build cache
    - Reports space savings

.PARAMETER RemoveStoppedContainers
    Remove all stopped containers.

.PARAMETER RemoveDanglingImages
    Remove dangling (untagged) images.

.PARAMETER RemoveUnusedVolumes
    Remove volumes not used by any container.

.PARAMETER PruneBuildCache
    Clean Docker build cache.

.PARAMETER Force
    Skip confirmation prompts and perform all cleanup operations.

.EXAMPLE
    .\Optimize-DockerCleanup.ps1 -RemoveStoppedContainers -RemoveDanglingImages

    Clean stopped containers and dangling images.

.EXAMPLE
    .\Optimize-DockerCleanup.ps1 -Force

    Perform all cleanup operations without prompts.

.NOTES
    Author: IT Infrastructure Team
    Requires: Docker
#>

[CmdletBinding()]
param(
    [switch]$RemoveStoppedContainers,
    [switch]$RemoveDanglingImages,
    [switch]$RemoveUnusedVolumes,
    [switch]$PruneBuildCache,
    [switch]$Force
)

Write-Host "`n=== Docker Cleanup Tool ===" -ForegroundColor Cyan

# Get disk usage before cleanup
Write-Host "[*] Checking current disk usage..." -ForegroundColor Cyan
try {
    $dfBefore = docker system df 2>$null
    Write-Host "`nBefore cleanup:" -ForegroundColor White
    Write-Host $dfBefore -ForegroundColor Gray
} catch {
    Write-Host "[!] Unable to get disk usage stats" -ForegroundColor Yellow
}

$cleanedItems = @()

if ($RemoveStoppedContainers -or $Force) {
    Write-Host "`n[*] Removing stopped containers..." -ForegroundColor Cyan
    $result = docker container prune -f 2>&1
    Write-Host $result -ForegroundColor Gray
    $cleanedItems += "Stopped containers"
}

if ($RemoveDanglingImages -or $Force) {
    Write-Host "`n[*] Removing dangling images..." -ForegroundColor Cyan
    $result = docker image prune -f 2>&1
    Write-Host $result -ForegroundColor Gray
    $cleanedItems += "Dangling images"
}

if ($RemoveUnusedVolumes -or $Force) {
    Write-Host "`n[*] Removing unused volumes..." -ForegroundColor Cyan
    $result = docker volume prune -f 2>&1
    Write-Host $result -ForegroundColor Gray
    $cleanedItems += "Unused volumes"
}

if ($PruneBuildCache -or $Force) {
    Write-Host "`n[*] Pruning build cache..." -ForegroundColor Cyan
    $result = docker builder prune -f 2>&1
    Write-Host $result -ForegroundColor Gray
    $cleanedItems += "Build cache"
}

# Show disk usage after cleanup
Write-Host "`n[*] Checking disk usage after cleanup..." -ForegroundColor Cyan
try {
    $dfAfter = docker system df 2>$null
    Write-Host "`nAfter cleanup:" -ForegroundColor White
    Write-Host $dfAfter -ForegroundColor Gray
} catch {}

Write-Host "`n=== Cleanup Summary ===" -ForegroundColor Cyan
Write-Host "Cleaned: $($cleanedItems -join ', ')" -ForegroundColor Green
Write-Host "`n[+] Cleanup complete!`n" -ForegroundColor Green
