# Detect low disk space (less than 10% or 10GB free)
$threshold = 10 # Percentage
$minGB = 10

$volumes = Get-Volume | Where-Object {$_.DriveLetter -and $_.DriveType -eq 'Fixed'}
$issues = @()

foreach($vol in $volumes) {
    $freePercent = ($vol.SizeRemaining / $vol.Size) * 100
    $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 2)
    
    if($freePercent -lt $threshold -or $freeGB -lt $minGB) {
        $issues += "$($vol.DriveLetter): $freeGB GB free ($([math]::Round($freePercent,1))%)"
    }
}

if($issues.Count -gt 0) {
    Write-Host "Low disk space detected: $($issues -join ', ')"
    exit 1
}

Write-Host "Disk space healthy"
exit 0
