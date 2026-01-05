<#
.SYNOPSIS
    Detects unauthorized network shares on the device.

.DESCRIPTION
    Checks for network shares that are not in the approved list, which could
    represent a security risk or data exposure.

.NOTES
    Author: Intune Admin
    Version: 1.0
    Intune Context: SYSTEM
    Exit 0: Only authorized shares present
    Exit 1: Unauthorized shares detected

.CONFIGURATION
    $approvedShares: List of approved share names (default: system shares)
#>

try {
    # Configuration - Add your approved share names here
    $approvedShares = @(
        "ADMIN$",
        "C$",
        "D$",
        "IPC$",
        "print$"
    )

    $issues = @()
    $unauthorizedShares = @()

    # Get all network shares
    $shares = Get-SmbShare -ErrorAction SilentlyContinue

    foreach ($share in $shares) {
        # Skip special shares (ending with $) if they're in approved list
        $isApproved = $false

        foreach ($approved in $approvedShares) {
            if ($share.Name -like $approved) {
                $isApproved = $true
                break
            }
        }

        if (-not $isApproved) {
            $unauthorizedShares += [PSCustomObject]@{
                Name = $share.Name
                Path = $share.Path
                Description = $share.Description
            }
        }
    }

    if ($unauthorizedShares.Count -gt 0) {
        Write-Host "Unauthorized network shares detected:"
        foreach ($share in $unauthorizedShares) {
            Write-Host "  - $($share.Name) ($($share.Path))"
        }
        exit 1
    }

    Write-Host "No unauthorized network shares detected"
    exit 0

} catch {
    Write-Host "Error checking network shares: $_"
    exit 1
}
