<#
.SYNOPSIS
    Detects issues with the Print Spooler service.

.DESCRIPTION
    This detection script checks if Print Spooler is functioning properly:
    - Verifies Print Spooler service is running
    - Checks if service is set to Automatic startup
    - Validates spool directory is accessible
    - Checks for stuck print jobs

.NOTES
    Returns exit code 1 if issues are detected (triggers remediation).
    Returns exit code 0 if everything is working properly.
#>

try {
    Write-Host "Checking Print Spooler service status..."

    # Check Print Spooler service
    $spoolerService = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue

    if (-not $spoolerService) {
        Write-Host "Print Spooler service not found!"
        exit 1
    }

    # Check if service is running
    if ($spoolerService.Status -ne 'Running') {
        Write-Host "Print Spooler service is not running. Current status: $($spoolerService.Status)"
        exit 1
    }

    # Check if service startup type is Automatic
    if ($spoolerService.StartType -ne 'Automatic') {
        Write-Host "Print Spooler service startup type is not Automatic. Current: $($spoolerService.StartType)"
        exit 1
    }

    # Check spool directory
    $spoolPath = "$env:SystemRoot\System32\spool\PRINTERS"
    if (-not (Test-Path $spoolPath)) {
        Write-Host "Spool directory not found: $spoolPath"
        exit 1
    }

    # Check for stuck print jobs
    try {
        $printJobs = Get-ChildItem -Path $spoolPath -Filter "*.spl" -ErrorAction SilentlyContinue
        if ($printJobs.Count -gt 10) {
            Write-Host "Detected $($printJobs.Count) files in spool directory - possible stuck jobs"
            exit 1
        }

        # Check for very old spool files (> 24 hours)
        $oldJobs = $printJobs | Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-24) }
        if ($oldJobs.Count -gt 0) {
            Write-Host "Detected $($oldJobs.Count) old print jobs (> 24 hours)"
            exit 1
        }
    } catch {
        # If we can't check, assume there might be an issue
        Write-Host "Could not access spool directory: $($_.Exception.Message)"
        exit 1
    }

    Write-Host "Print Spooler is functioning properly"
    exit 0

} catch {
    Write-Host "Error checking Print Spooler: $($_.Exception.Message)"
    exit 1
}
