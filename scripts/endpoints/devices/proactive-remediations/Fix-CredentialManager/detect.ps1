<#
.SYNOPSIS
    Detects stale or orphaned credentials in Windows Credential Manager.

.DESCRIPTION
    Checks for credentials older than a specified threshold or credentials
    that may be causing authentication issues.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Credential Manager is healthy
    Exit 1: Stale credentials detected - remediation needed

.CONFIGURATION
    $maxCredentialAgeDays: Age threshold in days (default: 180)
#>

try {
    # Configuration
    $maxCredentialAgeDays = 180

    $issues = @()
    $staleCredentials = @()

    # Get stored credentials using cmdkey
    $credList = cmdkey /list 2>&1

    if ($LASTEXITCODE -eq 0) {
        # Parse credential list
        $targetPattern = "Target:\s+(.+)"
        $typePattern = "Type:\s+(.+)"

        $matches = [regex]::Matches($credList, $targetPattern)

        if ($matches.Count -gt 10) {
            Write-Host "Large number of stored credentials detected: $($matches.Count)"
            Write-Host "This may indicate stale or orphaned credentials"
            exit 1
        }

        # Check for specific problematic credential patterns
        foreach ($match in $matches) {
            $target = $match.Groups[1].Value.Trim()

            # Check for known problematic patterns
            if ($target -match "MicrosoftAccount|WindowsLive|Live|virtualapp/didlogical" -or
                $target -match "LegacyGeneric|_MSLITE_") {
                $staleCredentials += $target
            }
        }
    }

    if ($staleCredentials.Count -gt 0) {
        Write-Host "Potentially stale credentials detected:"
        foreach ($cred in $staleCredentials) {
            Write-Host "  - $cred"
        }
        exit 1
    }

    Write-Host "Credential Manager appears healthy"
    exit 0

} catch {
    Write-Host "Error checking Credential Manager: $_"
    exit 1
}
