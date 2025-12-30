# Detect stuck Windows Update
$wuService = Get-Service wuauserv -ErrorAction SilentlyContinue

if(-not $wuService) {
    Write-Host "Windows Update service not found"
    exit 1
}

if($wuService.Status -ne 'Running') {
    Write-Host "Windows Update service is $($wuService.Status)"
    exit 1
}

# Check for pending updates stuck for more than 7 days
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $searchResult = $updateSearcher.Search("IsInstalled=0")
    
    if($searchResult.Updates.Count -gt 0) {
        Write-Host "Found $($searchResult.Updates.Count) pending updates"
        exit 1
    }
}
catch {
    Write-Host "Could not query updates: $($_.Exception.Message)"
    exit 1
}

Write-Host "Windows Update healthy"
exit 0
