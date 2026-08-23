<#
.SYNOPSIS
    Remediates Print Spooler service issues.

.DESCRIPTION
    This remediation script fixes Print Spooler issues by:
    - Stopping Print Spooler service
    - Clearing stuck print jobs from spool directory
    - Restarting Print Spooler service
    - Setting service to Automatic startup

.NOTES
    Returns exit code 0 if remediation is successful.
    Returns exit code 1 if remediation fails.
#>

try {
    Write-Host "Starting Print Spooler remediation..."

    # Stop Print Spooler service
    Write-Host "Stopping Print Spooler service..."
    $spoolerService = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue

    if ($spoolerService) {
        if ($spoolerService.Status -eq 'Running') {
            Stop-Service -Name "Spooler" -Force -ErrorAction Stop
            Start-Sleep -Seconds 3
            Write-Host "Print Spooler service stopped"
        }
    }
    else {
        Write-Host "Print Spooler service not found!"
        exit 1
    }

    # Clear spool directory
    Write-Host "Clearing print spool directory..."
    $spoolPath = "$env:SystemRoot\System32\spool\PRINTERS"

    if (Test-Path $spoolPath) {
        try {
            # Remove all spool files
            Get-ChildItem -Path $spoolPath -Include "*.shd", "*.spl" -Recurse -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue

            Write-Host "Print spool cleared successfully"
        }
        catch {
            Write-Host "Warning: Could not fully clear spool directory: $($_.Exception.Message)"
            # Continue even if some files can't be deleted
        }
    }
    else {
        Write-Host "Spool directory not found: $spoolPath"
        # Create it if it doesn't exist
        try {
            New-Item -Path $spoolPath -ItemType Directory -Force | Out-Null
            Write-Host "Created spool directory"
        }
        catch {
            Write-Host "Failed to create spool directory: $($_.Exception.Message)"
            exit 1
        }
    }

    # Set service to Automatic startup
    Write-Host "Setting Print Spooler service to Automatic startup..."
    Set-Service -Name "Spooler" -StartupType Automatic -ErrorAction Stop

    # Start Print Spooler service
    Write-Host "Starting Print Spooler service..."
    Start-Service -Name "Spooler" -ErrorAction Stop
    Start-Sleep -Seconds 3

    # Verify service is running
    $spoolerService = Get-Service -Name "Spooler"

    if ($spoolerService.Status -eq 'Running') {
        Write-Host "Print Spooler service is now running"
        Write-Host "Print Spooler remediation completed successfully"
        exit 0
    }
    else {
        Write-Host "Failed to start Print Spooler service. Status: $($spoolerService.Status)"
        exit 1
    }

}
catch {
    Write-Host "Error during Print Spooler remediation: $($_.Exception.Message)"
    exit 1
}
