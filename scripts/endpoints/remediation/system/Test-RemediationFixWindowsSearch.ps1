<#
.SYNOPSIS
    Detects issues with Windows Search service.

.DESCRIPTION
    Verifies that the Windows Search (WSearch) service exists, is running and is set to an
    automatic startup type, then checks the search index status through the Search.SearchCatalogManager
    COM object (created only via the Get-SearchCatalogManager wrapper) - only a paused or
    recovering index is flagged, since indexing states are legitimate transient conditions.
    Finally it re-queries the service to confirm it responds. This is a read-only detection
    script: it changes nothing, so re-running it is safe (idempotent).
    Exit codes:
    - 0: healthy - Windows Search is functioning properly.
    - 1: non-compliant - issues detected that trigger remediation, or the check failed.

.EXAMPLE
    PS C:\> .\Test-RemediationFixWindowsSearch.ps1
    Checks WSearch service and index state; exits 0 when healthy, 1 when remediation is needed.

.EXAMPLE
    PS C:\> & 'C:\Program Files\Intune\ProactiveRemediations\Test-RemediationFixWindowsSearch.ps1'
    Runs the same check from the Intune Management Extension under the SYSTEM context.

.NOTES
    File Name: Test-RemediationFixWindowsSearch.ps1
    Author: Intune Admin
    Prerequisite: PowerShell 7.0
    Version: 1.0.0
    Date: 2026-08-23
#>

[CmdletBinding()]

$ErrorActionPreference = 'Stop'

#region Functions

function Get-SearchCatalogManager {
    <#
    .SYNOPSIS
        Thin wrapper that creates the Search.SearchCatalogManager COM object (mock seam for tests).
    #>
    param([Parameter(Mandatory)][string]$ComObjectName)

    return (New-Object -ComObject $ComObjectName)
}

function Main {
    try {
        $outputMsg = "[*] Checking Windows Search service status..."
        Write-Host $outputMsg -ForegroundColor Cyan

        # Check Windows Search service.
        $searchService = Get-Service -Name "WSearch" -ErrorAction SilentlyContinue

        if (-not $searchService) {
            $outputMsg = "[!] Windows Search service not found!"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        # Check if service is running.
        if ($searchService.Status -ne 'Running') {
            $outputMsg = "[!] Windows Search service is not running. Current status: $($searchService.Status)"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        # Check if service startup type is Automatic.
        if ($searchService.StartType -notin @('Automatic', 'AutomaticDelayedStart')) {
            $outputMsg = "[!] Windows Search service startup type is not Automatic. "
            $outputMsg += "Current: $($searchService.StartType)"
            Write-Host $outputMsg -ForegroundColor Yellow
            return 1
        }

        # Check indexer status.
        try {
            $searchCatalog = Get-SearchCatalogManager -ComObjectName 'Search.SearchCatalogManager'
            $catalog = $searchCatalog.GetCatalog("SystemIndex")
            $catalogStatus = $catalog.GetCatalogStatus()

            # CATALOG_STATUS enum values are NOT documented on MS Learn and the exact
            # mapping is UNVERIFIED. Per the commonly shipped enum (IDLE=0, QUERYING=1,
            # INDEXING=2, PAUSED=3, RECOVERING=4, FULL_CRAWL=5), indexing/rebuild/full
            # crawl are legitimate transient states and must NOT be flagged. Be
            # conservative: only a paused (3) or recovering (4) index is actionable.
            if ($catalogStatus -in @(3, 4)) {
                $outputMsg = "[!] Search index is paused or recovering. Status code: $catalogStatus"
                Write-Host $outputMsg -ForegroundColor Yellow
                return 1
            }
        }
        catch {
            $outputMsg = "[!] Could not check search index status: $($_.Exception.Message)"
            Write-Host $outputMsg -ForegroundColor Yellow
            # Don't fail on this check as it might not be accessible in all contexts
        }

        # Check search service is responding.
        try {
            $searchTest = Get-Service -Name "WSearch" | Select-Object -Property Status, StartType
            if (-not $searchTest) {
                $outputMsg = "[!] Windows Search service test failed"
                Write-Host $outputMsg -ForegroundColor Yellow
                return 1
            }
        }
        catch {
            $outputMsg = "[-] Windows Search service is not responding properly"
            Write-Host $outputMsg -ForegroundColor Red
            return 1
        }

        $outputMsg = "[+] Windows Search is functioning properly"

        Write-Host $outputMsg -ForegroundColor Green
        return 0
    }
    catch {
        $outputMsg = "[-] Error checking Windows Search: $($_.Exception.Message)"
        Write-Host $outputMsg -ForegroundColor Red
        return 1
    }
}

#endregion

# Execute only when run as a script; dot-sourcing (Pester tests, module builds) skips execution.
if ($MyInvocation.InvocationName -ne '.') { exit (Main) }
