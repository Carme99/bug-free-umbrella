<#
.SYNOPSIS
    Remediates Windows Search service issues.

.DESCRIPTION
    This remediation script fixes Windows Search issues by:
    - Stopping Windows Search service
    - Clearing search index cache
    - Restarting Windows Search service
    - Setting service to Automatic startup
    - Rebuilding search index if necessary

.NOTES
    Returns exit code 0 if remediation is successful.
    Returns exit code 1 if remediation fails.
#>

try {
    Write-Host "Starting Windows Search remediation..."

    # Stop Windows Search service
    Write-Host "Stopping Windows Search service..."
    $searchService = Get-Service -Name "WSearch" -ErrorAction SilentlyContinue

    if ($searchService) {
        if ($searchService.Status -eq 'Running') {
            Stop-Service -Name "WSearch" -Force -ErrorAction Stop
            Start-Sleep -Seconds 3
            Write-Host "Windows Search service stopped"
        }
    }
    else {
        Write-Host "Windows Search service not found!"
        exit 1
    }

    # Clear search index cache
    Write-Host "Clearing search index cache..."
    $searchDataPath = "$env:ProgramData\Microsoft\Search\Data"

    if (Test-Path $searchDataPath) {
        try {
            # Remove database files
            Get-ChildItem -Path $searchDataPath -Include "*.edb", "*.chk", "*.log" -Recurse -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue

            Write-Host "Search cache cleared successfully"
        }
        catch {
            Write-Host "Warning: Could not fully clear search cache: $($_.Exception.Message)"
            # Continue even if cache clear fails
        }
    }

    # Set service to Automatic startup
    Write-Host "Setting Windows Search service to Automatic startup..."
    Set-Service -Name "WSearch" -StartupType Automatic -ErrorAction Stop

    # Start Windows Search service
    Write-Host "Starting Windows Search service..."
    Start-Service -Name "WSearch" -ErrorAction Stop
    Start-Sleep -Seconds 5

    # Verify service is running
    $searchService = Get-Service -Name "WSearch"

    if ($searchService.Status -eq 'Running') {
        Write-Host "Windows Search service is now running"

        # Trigger index rebuild
        try {
            Write-Host "Triggering search index rebuild..."
            $searchCatalog = New-Object -ComObject Search.SearchCatalogManager
            $catalog = $searchCatalog.GetCatalog("SystemIndex")
            $catalog.Reindex()
            Write-Host "Search index rebuild initiated"
        }
        catch {
            Write-Host "Note: Could not trigger index rebuild automatically: $($_.Exception.Message)"
            Write-Host "Index will rebuild automatically over time"
        }

        Write-Host "Windows Search remediation completed successfully"
        exit 0
    }
    else {
        Write-Host "Failed to start Windows Search service. Status: $($searchService.Status)"
        exit 1
    }

}
catch {
    Write-Host "Error during Windows Search remediation: $($_.Exception.Message)"
    exit 1
}
