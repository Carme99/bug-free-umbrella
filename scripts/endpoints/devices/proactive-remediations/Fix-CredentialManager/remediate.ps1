<#
.SYNOPSIS
    Removes stale or orphaned credentials.

.DESCRIPTION
    Removes problematic credentials from Windows Credential Manager that may
    be causing authentication issues or clutter.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Remediation successful
#>

try {
    $remediationActions = @()

    # Get stored credentials using cmdkey
    $credList = cmdkey /list 2>&1

    if ($LASTEXITCODE -eq 0) {
        # Parse credential list
        $targetPattern = "Target:\s+(.+)"
        $matches = [regex]::Matches($credList, $targetPattern)

        foreach ($match in $matches) {
            $target = $match.Groups[1].Value.Trim()

            # Remove known problematic credential patterns
            if ($target -match "virtualapp/didlogical|_MSLITE_") {
                try {
                    cmdkey /delete:"$target" | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        $remediationActions += "Removed stale credential: $target"
                    }
                } catch {
                    Write-Host "Warning: Could not remove credential $target : $_"
                }
            }
        }
    }

    if ($remediationActions.Count -gt 0) {
        Write-Host "Credential Manager remediation completed:"
        foreach ($action in $remediationActions) {
            Write-Host "  - $action"
        }
    } else {
        Write-Host "No stale credentials found to remove"
    }

    exit 0

} catch {
    Write-Host "Error during Credential Manager remediation: $_"
    exit 1
}
