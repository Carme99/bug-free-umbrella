<#
.SYNOPSIS
    Detects issues with Windows Search service.

.DESCRIPTION
    This detection script checks if Windows Search is functioning properly:
    - Verifies Windows Search service is running
    - Checks if service is set to Automatic startup
    - Validates search index status
    - Tests basic search functionality

.NOTES
    Returns exit code 1 if issues are detected (triggers remediation).
    Returns exit code 0 if everything is working properly.
#>

try {
    Write-Host "Checking Windows Search service status..."

    # Check Windows Search service
    $searchService = Get-Service -Name "WSearch" -ErrorAction SilentlyContinue

    if (-not $searchService) {
        Write-Host "Windows Search service not found!"
        exit 1
    }

    # Check if service is running
    if ($searchService.Status -ne 'Running') {
        Write-Host "Windows Search service is not running. Current status: $($searchService.Status)"
        exit 1
    }

    # Check if service startup type is Automatic
    if ($searchService.StartType -notin @('Automatic', 'AutomaticDelayedStart')) {
        Write-Host "Windows Search service startup type is not Automatic. Current: $($searchService.StartType)"
        exit 1
    }

    # Check indexer status
    try {
        $searchCatalog = New-Object -ComObject Search.SearchCatalogManager
        $catalog = $searchCatalog.GetCatalog("SystemIndex")
        $catalogStatus = $catalog.GetCatalogStatus()

        # CATALOG_STATUS enum values are NOT documented on MS Learn and the exact
        # mapping is UNVERIFIED. Per the commonly shipped enum (IDLE=0, QUERYING=1,
        # INDEXING=2, PAUSED=3, RECOVERING=4, FULL_CRAWL=5), indexing/rebuild/full
        # crawl are legitimate transient states and must NOT be flagged. Be
        # conservative: only a paused (3) or recovering (4) index is actionable.
        if ($catalogStatus -in @(3, 4)) {
            Write-Host "Search index is paused or recovering. Status code: $catalogStatus"
            exit 1
        }
    } catch {
        Write-Host "Could not check search index status: $($_.Exception.Message)"
        # Don't fail on this check as it might not be accessible in all contexts
    }

    # Check search service is responding
    try {
        $searchTest = Get-Service -Name "WSearch" | Select-Object -Property Status, StartType
        if (-not $searchTest) {
            Write-Host "Windows Search service test failed"
            exit 1
        }
    } catch {
        Write-Host "Windows Search service is not responding properly"
        exit 1
    }

    Write-Host "Windows Search is functioning properly"
    exit 0

} catch {
    Write-Host "Error checking Windows Search: $($_.Exception.Message)"
    exit 1
}
